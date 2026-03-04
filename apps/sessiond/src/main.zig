const std = @import("std");

const ManagedAppDescriptor = struct {
    name: []const u8,
    argv: []const []const u8,
    autostart: bool,
    auto_restart: bool,
    max_restarts: u8,
    restart_backoff_ms: i64,
};

const ExitKind = enum {
    none,
    exited,
    signal,
    stopped,
    unknown,
};

const ManagedAppState = struct {
    child: ?std.process.Child,
    running: bool,
    auto_restart: bool,
    pending_restart: bool,
    restart_count: u8,
    restart_window_start_ms: i64,
    next_restart_ms: i64,
    pid: i64,
    last_exit_kind: ExitKind,
    last_exit_code: i32,
};

const panel_argv = [_][]const u8{ "luminade-panel" };
const launcher_argv = [_][]const u8{ "luminade-launcher" };
const settings_argv = [_][]const u8{ "luminade-settings" };

const apps = [_]ManagedAppDescriptor{
    .{ .name = "panel", .argv = panel_argv[0..], .autostart = true, .auto_restart = true, .max_restarts = 8, .restart_backoff_ms = 1200 },
    .{ .name = "launcher", .argv = launcher_argv[0..], .autostart = true, .auto_restart = true, .max_restarts = 8, .restart_backoff_ms = 1200 },
    .{ .name = "settings", .argv = settings_argv[0..], .autostart = false, .auto_restart = true, .max_restarts = 5, .restart_backoff_ms = 1500 },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var foreground = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--foreground")) foreground = true;
    }

    try ensureRuntimeFiles();

    const cmd_socket = try setupCommandSocket();
    defer {
        std.posix.close(cmd_socket);
        std.fs.cwd().deleteFile(socketPath()) catch {};
    }

    var states: [apps.len]ManagedAppState = undefined;
    const now_ms = std.time.milliTimestamp();
    for (apps, 0..) |desc, i| {
        states[i] = .{
            .child = null,
            .running = false,
            .auto_restart = desc.auto_restart,
            .pending_restart = false,
            .restart_count = 0,
            .restart_window_start_ms = now_ms,
            .next_restart_ms = 0,
            .pid = 0,
            .last_exit_kind = .none,
            .last_exit_code = 0,
        };
    }

    std.debug.print("sessiond started{s}\n", .{if (foreground) " in foreground" else ""});

    for (apps, 0..) |desc, i| {
        if (desc.autostart) try startApp(allocator, desc, &states[i]);
    }

    var last_snapshot_ms: i64 = 0;

    while (true) {
        const loop_now = std.time.milliTimestamp();

        const should_shutdown_socket = try processSocketCommands(allocator, cmd_socket, &states);
        const should_shutdown_queue = try processCommandQueue(allocator, &states);
        const should_shutdown = should_shutdown_socket or should_shutdown_queue;

        try monitorApps(allocator, &states, loop_now);

        if (loop_now - last_snapshot_ms >= 1000) {
            try writeStateSnapshot(&states, loop_now);
            last_snapshot_ms = loop_now;
        }

        if (should_shutdown) {
            std.debug.print("sessiond shutdown requested\n", .{});
            break;
        }

        std.time.sleep(250 * std.time.ns_per_ms);
    }

    for (states[0..]) |*state| stopApp(state);
}

fn ensureRuntimeFiles() !void {
    try std.fs.cwd().makePath(".luminade");
    try ensureFileWithHeader(commandsPath(), "# cmd\targ1\targ2\n");
    try ensureFileWithHeader(settingsEventsPath(), "# widget-id\targ1\targ2\n");
    try ensureFileWithHeader(launcherQueryPath(), "\n");
    try ensureFileWithHeader(statePath(), "# sessiond state\n");
}

fn commandsPath() []const u8 {
    return std.posix.getenv("LUMINADE_SESSIOND_COMMANDS") orelse ".luminade/sessiond-commands.tsv";
}

fn socketPath() []const u8 {
    return std.posix.getenv("LUMINADE_SESSIOND_SOCKET") orelse ".luminade/sessiond.sock";
}

fn settingsEventsPath() []const u8 {
    return std.posix.getenv("LUMINADE_SETTINGS_GUI_EVENTS") orelse ".luminade/gui-settings-events.tsv";
}

fn launcherQueryPath() []const u8 {
    return std.posix.getenv("LUMINADE_LAUNCHER_QUERY_PATH") orelse ".luminade/gui-launcher-query.txt";
}

fn statePath() []const u8 {
    return std.posix.getenv("LUMINADE_SESSIOND_STATE") orelse ".luminade/sessiond-state.tsv";
}

fn ensureFileWithHeader(path: []const u8, header: []const u8) !void {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            var created = try std.fs.cwd().createFile(path, .{ .truncate = true });
            defer created.close();
            try created.writer().writeAll(header);
            return;
        },
        else => return err,
    };
    file.close();
}

fn setupCommandSocket() !std.posix.socket_t {
    std.fs.cwd().deleteFile(socketPath()) catch {};

    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    errdefer std.posix.close(fd);

    const addr = try std.net.Address.initUnix(socketPath());
    try std.posix.bind(fd, &addr.any, addr.getOsSockLen());
    try std.posix.listen(fd, 32);

    return fd;
}

fn startApp(allocator: std.mem.Allocator, desc: ManagedAppDescriptor, state: *ManagedAppState) !void {
    if (state.running) return;

    var child = std.process.Child.init(desc.argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();

    state.child = child;
    state.running = true;
    state.pending_restart = false;
    state.pid = @as(i64, @intCast(state.child.?.id));

    std.debug.print("sessiond: started {s} pid={d}\n", .{ desc.name, state.pid });
}

fn stopApp(state: *ManagedAppState) void {
    if (state.child) |*child| {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }
    state.child = null;
    state.running = false;
    state.pending_restart = false;
    state.pid = 0;
}

fn monitorApps(allocator: std.mem.Allocator, states: *[apps.len]ManagedAppState, now_ms: i64) !void {
    for (apps, 0..) |desc, i| {
        var state = &states[i];

        if (state.running and state.child != null) {
            if (state.child.?.tryWait() catch null) |term| {
                state.running = false;
                state.child = null;
                state.pid = 0;
                setExitState(state, term);

                std.debug.print("sessiond: {s} exited ({s}:{d})\n", .{ desc.name, @tagName(state.last_exit_kind), state.last_exit_code });

                if (state.auto_restart) {
                    if (now_ms - state.restart_window_start_ms > 60_000) {
                        state.restart_window_start_ms = now_ms;
                        state.restart_count = 0;
                    }

                    if (state.restart_count < desc.max_restarts) {
                        state.restart_count += 1;
                        state.pending_restart = true;
                        state.next_restart_ms = now_ms + desc.restart_backoff_ms;
                    } else {
                        state.pending_restart = false;
                        std.debug.print("sessiond: restart budget exhausted for {s}\n", .{desc.name});
                    }
                }
            }
        }

        if (!state.running and state.pending_restart and now_ms >= state.next_restart_ms) {
            startApp(allocator, desc, state) catch |err| {
                std.debug.print("sessiond: restart failed for {s}: {s}\n", .{ desc.name, @errorName(err) });
                state.next_restart_ms = now_ms + desc.restart_backoff_ms;
                continue;
            };
        }
    }
}

fn setExitState(state: *ManagedAppState, term: std.process.Child.Term) void {
    switch (term) {
        .Exited => |code| {
            state.last_exit_kind = .exited;
            state.last_exit_code = code;
        },
        .Signal => |sig| {
            state.last_exit_kind = .signal;
            state.last_exit_code = sig;
        },
        .Stopped => |sig| {
            state.last_exit_kind = .stopped;
            state.last_exit_code = sig;
        },
        else => {
            state.last_exit_kind = .unknown;
            state.last_exit_code = 0;
        },
    }
}

fn processSocketCommands(
    allocator: std.mem.Allocator,
    socket_fd: std.posix.socket_t,
    states: *[apps.len]ManagedAppState,
) !bool {
    var should_shutdown = false;

    var pfd = [_]std.posix.pollfd{.{
        .fd = socket_fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    const ready = try std.posix.poll(&pfd, 0);
    if (ready <= 0 or (pfd[0].revents & std.posix.POLL.IN) == 0) return false;

    while (true) {
        const client_fd = std.posix.accept(socket_fd, null, null, 0) catch |err| switch (err) {
            error.WouldBlock => break,
            else => return err,
        };
        defer std.posix.close(client_fd);

        var data = std.ArrayList(u8).init(allocator);
        defer data.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = std.posix.read(client_fd, &buf) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };
            if (n == 0) break;
            try data.appendSlice(buf[0..n]);
            if (data.items.len > 512 * 1024) break;
        }

        var lines = std.mem.splitScalar(u8, data.items, '\n');
        while (lines.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            if (try processCommandLine(allocator, states, line)) should_shutdown = true;
        }
    }

    return should_shutdown;
}

fn processCommandQueue(allocator: std.mem.Allocator, states: *[apps.len]ManagedAppState) !bool {
    var file = std.fs.cwd().openFile(commandsPath(), .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 512 * 1024);
    defer allocator.free(content);

    var shutdown = false;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (try processCommandLine(allocator, states, line)) shutdown = true;
    }

    var clear = try std.fs.cwd().createFile(commandsPath(), .{ .truncate = true });
    defer clear.close();
    try clear.writer().writeAll("# cmd\targ1\targ2\n");

    return shutdown;
}

fn processCommandLine(
    allocator: std.mem.Allocator,
    states: *[apps.len]ManagedAppState,
    line: []const u8,
) !bool {
    var fields = std.ArrayList([]const u8).init(allocator);
    defer fields.deinit();

    var split = std.mem.splitScalar(u8, line, '\t');
    while (split.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t\r");
        if (part.len == 0) continue;
        try fields.append(part);
    }
    if (fields.items.len == 0) return false;

    const cmd = fields.items[0];
    const args = if (fields.items.len > 1) fields.items[1..] else &.{};

    if (std.mem.eql(u8, cmd, "PING")) return false;
    if (std.mem.eql(u8, cmd, "SHUTDOWN")) return true;
    if (std.mem.eql(u8, cmd, "OPEN_SETTINGS")) {
        try startNamedApp(allocator, states, "settings");
        return false;
    }
    if (std.mem.eql(u8, cmd, "STOP_SETTINGS")) {
        stopNamedApp(states, "settings");
        return false;
    }
    if (std.mem.eql(u8, cmd, "RESTART") and args.len >= 1) {
        try restartNamedApp(allocator, states, args[0]);
        return false;
    }
    if (std.mem.eql(u8, cmd, "LAUNCHER_QUERY") and args.len >= 1) {
        try writeTextFile(launcherQueryPath(), args[0]);
        return false;
    }
    if (std.mem.eql(u8, cmd, "SETTINGS_EVENT") and args.len >= 1) {
        const event_line = try joinWithTabs(allocator, args);
        defer allocator.free(event_line);
        try appendLine(allocator, settingsEventsPath(), event_line);
        return false;
    }

    return false;
}

fn startNamedApp(allocator: std.mem.Allocator, states: *[apps.len]ManagedAppState, name: []const u8) !void {
    const idx = findAppIndex(name) orelse return;
    states[idx].auto_restart = true;
    states[idx].pending_restart = false;
    try startApp(allocator, apps[idx], &states[idx]);
}

fn stopNamedApp(states: *[apps.len]ManagedAppState, name: []const u8) void {
    const idx = findAppIndex(name) orelse return;
    states[idx].auto_restart = false;
    stopApp(&states[idx]);
}

fn restartNamedApp(allocator: std.mem.Allocator, states: *[apps.len]ManagedAppState, name: []const u8) !void {
    const idx = findAppIndex(name) orelse return;
    stopNamedApp(states, name);
    states[idx].auto_restart = true;
    try startApp(allocator, apps[idx], &states[idx]);
}

fn findAppIndex(name: []const u8) ?usize {
    for (apps, 0..) |app, idx| if (std.mem.eql(u8, app.name, name)) return idx;
    return null;
}

fn writeStateSnapshot(states: *[apps.len]ManagedAppState, now_ms: i64) !void {
    var file = try std.fs.cwd().createFile(statePath(), .{ .truncate = true });
    defer file.close();

    const w = file.writer();
    try w.print("timestamp_ms\t{d}\n", .{now_ms});
    try w.writeAll("name\trunning\tpid\trestarts\tpending\tlast_exit_kind\tlast_exit_code\n");

    for (apps, 0..) |app, i| {
        const state = states[i];
        try w.print("{s}\t{s}\t{d}\t{d}\t{s}\t{s}\t{d}\n", .{
            app.name,
            if (state.running) "true" else "false",
            state.pid,
            state.restart_count,
            if (state.pending_restart) "true" else "false",
            @tagName(state.last_exit_kind),
            state.last_exit_code,
        });
    }
}

fn joinWithTabs(allocator: std.mem.Allocator, fields: []const []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    for (fields, 0..) |f, idx| {
        if (idx != 0) try out.append('\t');
        try out.appendSlice(f);
    }
    return try out.toOwnedSlice();
}

fn appendLine(allocator: std.mem.Allocator, path: []const u8, line: []const u8) !void {
    const existing = try readTextFileOrEmpty(allocator, path);
    defer allocator.free(existing);

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    if (existing.len > 0) {
        try out.appendSlice(existing);
        if (existing[existing.len - 1] != '\n') try out.append('\n');
    }
    try out.appendSlice(line);
    try out.append('\n');

    try writeTextFile(path, out.items);
}

fn readTextFileOrEmpty(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return try allocator.dupe(u8, ""),
        else => return err,
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, 512 * 1024);
}

fn writeTextFile(path: []const u8, text: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writer().writeAll(text);
}
