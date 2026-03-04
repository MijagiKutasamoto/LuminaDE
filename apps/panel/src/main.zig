const std = @import("std");
const core = @import("luminade_core");
const ui = @import("luminade_ui");

const PanelLaunchGuard = struct {
    window_start_ns: i64,
    launches_in_window: u16,
    last_launch_ns: i64,

    fn init() PanelLaunchGuard {
        return .{
            .window_start_ns = 0,
            .launches_in_window = 0,
            .last_launch_ns = 0,
        };
    }

    fn allow(self: *PanelLaunchGuard, now_ns: i64) bool {
        const min_gap_ns: i64 = 250 * std.time.ns_per_ms;
        if (self.last_launch_ns != 0 and now_ns - self.last_launch_ns < min_gap_ns) return false;

        const window_ns: i64 = 10 * std.time.ns_per_s;
        if (self.window_start_ns == 0 or now_ns - self.window_start_ns >= window_ns) {
            self.window_start_ns = now_ns;
            self.launches_in_window = 0;
        }

        if (self.launches_in_window >= 12) return false;
        self.launches_in_window += 1;
        self.last_launch_ns = now_ns;
        return true;
    }
};

const PanelInteractionBehavior = struct {
    focus_policy: []const u8,
    pointer_target_px: u8,

    fn fromProfile(profile: core.DesktopProfile) PanelInteractionBehavior {
        const base: u8 = switch (profile.interaction_mode) {
            .mouse_first => 44,
            .balanced => 40,
            .keyboard_first => 32,
        };

        const adjusted_i16 = @as(i16, @intCast(base)) + @divTrunc(@as(i16, profile.pointer_sensitivity), 10);
        const adjusted_clamped = @max(@as(i16, 28), @min(@as(i16, 56), adjusted_i16));

        const focus_policy = switch (profile.interaction_mode) {
            .mouse_first => if (profile.pointer_accel_profile == .flat) "hover-precise" else "hover-first",
            .balanced => "smart-focus",
            .keyboard_first => "keyboard-first",
        };

        return .{
            .focus_policy = focus_policy,
            .pointer_target_px = @as(u8, @intCast(adjusted_clamped)),
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const cfg = core.RuntimeConfig.init(allocator);
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var daemon_mode = true;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--daemon")) daemon_mode = true;
        if (std.mem.eql(u8, arg, "--once")) daemon_mode = false;
    }

    core.printBanner(.panel, cfg);
    core.printModernSummary(.panel, cfg);

    var watcher = try ui.OutputWatcher.init(allocator);
    defer watcher.deinit();

    var native_runtime = ui.NativePanelRuntime.init();
    var launch_guards = std.StringHashMap(PanelLaunchGuard).init(allocator);
    defer {
        var it = launch_guards.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        launch_guards.deinit();
    }

    std.debug.print("[watcher] backend={s}\n", .{watcher.backendName()});
    printOutputState(&watcher);

    if (daemon_mode) {
        std.debug.print("Panel GUI mode started (GUI-first daemon).\n", .{});
        while (true) {
            const event = try watcher.waitForEvent(5000);
            if (event and try watcher.poll()) {
                std.debug.print("[watcher] monitor topology changed, refreshing panel surfaces\n", .{});
                printOutputState(&watcher);
            }
            try renderPanel(cfg, allocator, &native_runtime);
            _ = try processPanelGuiEventQueue(allocator, &launch_guards);
        }
    }

    try renderPanel(cfg, allocator, &native_runtime);
}

fn renderPanel(
    cfg: core.RuntimeConfig,
    allocator: std.mem.Allocator,
    native_runtime: *ui.NativePanelRuntime,
) !void {
    const ts = std.time.timestamp();
    const active_ws = parseActiveWorkspace();
    const behavior = PanelInteractionBehavior.fromProfile(cfg.profile);

    std.debug.print("[panel] ts={d} | ", .{ts});

    var ws: u8 = 1;
    while (ws <= 4) : (ws += 1) {
        if (ws == active_ws) {
            std.debug.print("[{d}*] ", .{ws});
        } else {
            std.debug.print("[{d}] ", .{ws});
        }
    }

    std.debug.print("| gaps={d} radius={d} blur={d} smart-hide={any} wm={s} input={s} focus={s} hitbox={d}px accel={s} natural={any} tap={any}\n", .{
        cfg.profile.workspace_gaps,
        cfg.profile.corner_radius,
        cfg.profile.blur_sigma,
        cfg.profile.smart_hide_panel,
        @tagName(cfg.profile.window_mode),
        @tagName(cfg.profile.interaction_mode),
        behavior.focus_policy,
        behavior.pointer_target_px,
        @tagName(cfg.profile.pointer_accel_profile),
        cfg.profile.natural_scroll,
        cfg.profile.tap_to_click,
    });

    var outputs = try ui.detectOutputs(allocator);
    defer ui.freeOutputs(allocator, &outputs);

    for (outputs.items) |output| {
        try renderPanelGui(allocator, cfg, output, active_ws, behavior, native_runtime);
    }
}

fn parseActiveWorkspace() u8 {
    const env_value = std.posix.getenv("LUMINADE_ACTIVE_WS") orelse return 1;
    return std.fmt.parseUnsigned(u8, env_value, 10) catch 1;
}

fn printOutputState(watcher: *ui.OutputWatcher) void {
    std.debug.print("Detected outputs: {d}\n", .{watcher.outputs.items.len});
    for (watcher.outputs.items) |output| {
        const surface = ui.fullscreenSurface(.panel, output);
        ui.printSurfaceSummary(surface, ui.ThemeTokens.modernDefault());
        ui.printRenderSpec(ui.renderSpecForSurface(surface));
    }
}

fn renderPanelGui(
    allocator: std.mem.Allocator,
    cfg: core.RuntimeConfig,
    output: ui.OutputProfile,
    active_ws: u8,
    behavior: PanelInteractionBehavior,
    native_runtime: *ui.NativePanelRuntime,
) !void {
    const surface = ui.fullscreenSurface(.panel, output);
    var frame = ui.GuiFrame.init(allocator, "Panel", surface);
    defer frame.deinit();

    try ui.addWidget(&frame, .{
        .id = "panel-root",
        .kind = .row,
        .label = "panel-root",
        .rect = .{ .x = 0, .y = 0, .w = surface.width, .h = cfg.profile.panel_height },
        .interactive = false,
        .hoverable = false,
    });

    var x: i32 = 10;
    var ws: u8 = 1;
    while (ws <= 4) : (ws += 1) {
        const label = if (ws == active_ws) "ws-active" else "ws";
        const ws_id = try std.fmt.allocPrint(allocator, "ws-{d}@{s}", .{ ws, output.name });
        defer allocator.free(ws_id);
        try ui.addWidget(&frame, .{
            .id = ws_id,
            .kind = .badge,
            .label = label,
            .rect = .{ .x = x, .y = 6, .w = behavior.pointer_target_px, .h = @max(cfg.profile.panel_height - 12, 16) },
            .interactive = true,
            .hoverable = true,
        });
        x += @as(i32, behavior.pointer_target_px) + 6;
    }

    const app_size = @max(cfg.profile.panel_height - 12, @as(u16, 16));
    const app_terminal_id = try std.fmt.allocPrint(allocator, "app-terminal@{s}", .{output.name});
    defer allocator.free(app_terminal_id);
    const app_browser_id = try std.fmt.allocPrint(allocator, "app-browser@{s}", .{output.name});
    defer allocator.free(app_browser_id);
    const app_files_id = try std.fmt.allocPrint(allocator, "app-files@{s}", .{output.name});
    defer allocator.free(app_files_id);

    try ui.addWidget(&frame, .{
        .id = app_terminal_id,
        .kind = .button,
        .label = "Terminal",
        .rect = .{ .x = x + 12, .y = 6, .w = app_size + 20, .h = app_size },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = app_browser_id,
        .kind = .button,
        .label = "Browser",
        .rect = .{ .x = x + 38 + @as(i32, @intCast(app_size)), .y = 6, .w = app_size + 20, .h = app_size },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = app_files_id,
        .kind = .button,
        .label = "Files",
        .rect = .{ .x = x + 64 + 2 * @as(i32, @intCast(app_size)), .y = 6, .w = app_size + 20, .h = app_size },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "clock",
        .kind = .text,
        .label = "clock",
        .rect = .{ .x = @as(i32, @intCast(surface.width)) - 170, .y = 8, .w = 160, .h = 20 },
        .interactive = false,
        .hoverable = false,
    });

    const native = try ui.initNativePanelSession(allocator, output, cfg.profile.panel_height);
    try ui.commitNativePanelFrame(allocator, native_runtime, native, &frame);

    ui.printGuiFrame(&frame);
}

fn panelGuiEventsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_PANEL_GUI_EVENTS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/gui-panel-events.tsv");
}

fn processPanelGuiEventQueue(
    allocator: std.mem.Allocator,
    launch_guards: *std.StringHashMap(PanelLaunchGuard),
) !bool {
    const path = try panelGuiEventsPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 128 * 1024);
    defer allocator.free(content);
    if (content.len == 0) return false;

    var changed = false;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var tokens = std.ArrayList([]const u8).init(allocator);
        defer tokens.deinit();
        var split = std.mem.splitScalar(u8, line, '\t');
        while (split.next()) |part_raw| {
            const part = std.mem.trim(u8, part_raw, " \t\r");
            if (part.len == 0) continue;
            try tokens.append(part);
        }
        if (tokens.items.len < 2) continue;

        const action = tokens.items[0];
        const widget_id_full = tokens.items[1];
        const target = splitWidgetTarget(widget_id_full);
        const widget_id = target.base_id;
        const output_key = target.output_name orelse "global";

        if (std.mem.eql(u8, action, "click")) {
            if (try handlePanelClick(allocator, launch_guards, widget_id, output_key)) {
                changed = true;
            }
            continue;
        }

        if (std.mem.eql(u8, action, "context") and tokens.items.len >= 3) {
            if (try handlePanelContext(allocator, widget_id, tokens.items[2])) {
                changed = true;
            }
        }
    }

    var truncate = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer truncate.close();
    try truncate.writer().writeAll(
        "# action\twidget-id\t[menu-action]\n# click\tapp-terminal@eDP-1\n# click\tws-2@eDP-1\n# context\tapp-terminal@eDP-1\tfavorite-add\n",
    );

    return changed;
}

fn handlePanelClick(
    allocator: std.mem.Allocator,
    launch_guards: *std.StringHashMap(PanelLaunchGuard),
    widget_id: []const u8,
    output_key: []const u8,
) !bool {
    const map = mapPanelWidget(widget_id) orelse {
        if (parseWorkspaceFromWidget(widget_id)) |workspace| {
            const switched = try switchWorkspaceForOutput(allocator, output_key, workspace);
            std.debug.print(
                "[panel] workspace click={s}@{s} switched={any}\n",
                .{ widget_id, output_key, switched },
            );
            return switched;
        }
        return false;
    };

    const now_ns = std.time.nanoTimestamp();
    if (!(try allowLaunchForOutput(allocator, launch_guards, output_key, now_ns))) {
        std.debug.print("[panel] launch throttled widget={s}@{s}\n", .{ widget_id, output_key });
        return false;
    }

    try launchCommandDetached(allocator, map.command);
    try incrementHistory(allocator, map.entry_id);
    std.debug.print("[panel] launched id={s} cmd={s}\n", .{ map.entry_id, map.command });
    return true;
}

fn handlePanelContext(allocator: std.mem.Allocator, widget_id: []const u8, menu_action: []const u8) !bool {
    const map = mapPanelWidget(widget_id) orelse return false;

    if (std.mem.eql(u8, menu_action, "favorite-add")) {
        try setFavorite(allocator, map.entry_id, true);
        return true;
    }
    if (std.mem.eql(u8, menu_action, "favorite-remove")) {
        try setFavorite(allocator, map.entry_id, false);
        return true;
    }
    if (std.mem.eql(u8, menu_action, "remove-history")) {
        try removeHistoryEntry(allocator, map.entry_id);
        return true;
    }

    return false;
}

const PanelAppMap = struct {
    entry_id: []const u8,
    command: []const u8,
};

fn mapPanelWidget(widget_id: []const u8) ?PanelAppMap {
    if (std.mem.eql(u8, widget_id, "app-terminal")) return .{ .entry_id = "terminal", .command = "foot" };
    if (std.mem.eql(u8, widget_id, "app-browser")) return .{ .entry_id = "browser", .command = "firefox" };
    if (std.mem.eql(u8, widget_id, "app-files")) return .{ .entry_id = "files", .command = "thunar" };
    return null;
}

const PanelWidgetTarget = struct {
    base_id: []const u8,
    output_name: ?[]const u8,
};

fn splitWidgetTarget(widget_id: []const u8) PanelWidgetTarget {
    const at_idx = std.mem.indexOfScalar(u8, widget_id, '@') orelse {
        return .{ .base_id = widget_id, .output_name = null };
    };

    const base = std.mem.trim(u8, widget_id[0..at_idx], " \t\r");
    const out = std.mem.trim(u8, widget_id[at_idx + 1 ..], " \t\r");
    return .{ .base_id = base, .output_name = if (out.len == 0) null else out };
}

fn parseWorkspaceFromWidget(widget_id: []const u8) ?u8 {
    if (!std.mem.startsWith(u8, widget_id, "ws-")) return null;
    const raw = std.mem.trim(u8, widget_id[3..], " \t\r");
    const n = std.fmt.parseUnsigned(u8, raw, 10) catch return null;
    if (n < 1 or n > 32) return null;
    return n;
}

fn switchWorkspaceForOutput(
    allocator: std.mem.Allocator,
    output_key: []const u8,
    workspace: u8,
) !bool {
    const bit: u32 = @as(u32, 1) << @as(u5, @intCast(workspace - 1));

    const cmd = if (std.mem.eql(u8, output_key, "global"))
        try std.fmt.allocPrint(allocator, "riverctl set-focused-tags {d}", .{bit})
    else
        try std.fmt.allocPrint(allocator, "riverctl focus-output '{s}' && riverctl set-focused-tags {d}", .{ output_key, bit });
    defer allocator.free(cmd);

    var child = std.process.Child.init(&.{ "sh", "-lc", cmd }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return false;
    const term = child.wait() catch return false;

    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn allowLaunchForOutput(
    allocator: std.mem.Allocator,
    launch_guards: *std.StringHashMap(PanelLaunchGuard),
    output_key: []const u8,
    now_ns: i64,
) !bool {
    const gop = try launch_guards.getOrPut(output_key);
    if (!gop.found_existing) {
        gop.key_ptr.* = try allocator.dupe(u8, output_key);
        gop.value_ptr.* = PanelLaunchGuard.init();
    }

    return gop.value_ptr.allow(now_ns);
}

fn launchCommandDetached(allocator: std.mem.Allocator, command: []const u8) !void {
    const shell_cmd = try std.fmt.allocPrint(allocator, "{s} >/dev/null 2>&1 &", .{command});
    defer allocator.free(shell_cmd);

    var child = std.process.Child.init(&.{ "sh", "-lc", shell_cmd }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    _ = try child.wait();
}

fn favoritesPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_FAVORITES")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/launcher-favorites.tsv");
}

fn loadFavorites(allocator: std.mem.Allocator, favorites: *std.StringHashMap(void)) !void {
    const path = try favoritesPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (favorites.contains(line)) continue;
        try favorites.put(try allocator.dupe(u8, line), {});
    }
}

fn saveFavorites(allocator: std.mem.Allocator, favorites: *std.StringHashMap(void)) !void {
    const path = try favoritesPath(allocator);
    defer allocator.free(path);

    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var out = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer out.close();
    try out.writer().writeAll("# launcher favorites (entry ids)\n");

    var it = favorites.keyIterator();
    while (it.next()) |key_ptr| {
        try out.writer().print("{s}\n", .{key_ptr.*});
    }
}

fn setFavorite(allocator: std.mem.Allocator, id: []const u8, enabled: bool) !void {
    var favorites = std.StringHashMap(void).init(allocator);
    defer {
        var it = favorites.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        favorites.deinit();
    }
    try loadFavorites(allocator, &favorites);

    if (enabled) {
        const gop = try favorites.getOrPut(id);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, id);
            gop.value_ptr.* = {};
        }
    } else if (favorites.fetchRemove(id)) |kv| {
        allocator.free(kv.key);
    }

    try saveFavorites(allocator, &favorites);
}

fn historyPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_HISTORY")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/launcher-history.tsv");
}

fn loadHistory(allocator: std.mem.Allocator, history: *std.StringHashMap(u32)) !void {
    const path = try historyPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;

        const sep = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const id = std.mem.trim(u8, line[0..sep], " \t\r");
        const count_raw = std.mem.trim(u8, line[sep + 1 ..], " \t\r");
        const count = std.fmt.parseUnsigned(u32, count_raw, 10) catch continue;
        try history.put(try allocator.dupe(u8, id), count);
    }
}

fn saveHistory(allocator: std.mem.Allocator, history: *std.StringHashMap(u32)) !void {
    const path = try historyPath(allocator);
    defer allocator.free(path);

    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var out = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer out.close();

    var it = history.iterator();
    while (it.next()) |item| {
        try out.writer().print("{s}\t{d}\n", .{ item.key_ptr.*, item.value_ptr.* });
    }
}

fn incrementHistory(allocator: std.mem.Allocator, id: []const u8) !void {
    var history = std.StringHashMap(u32).init(allocator);
    defer {
        var it = history.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        history.deinit();
    }

    try loadHistory(allocator, &history);
    const gop = try history.getOrPut(id);
    if (gop.found_existing) {
        gop.value_ptr.* += 1;
    } else {
        gop.key_ptr.* = try allocator.dupe(u8, id);
        gop.value_ptr.* = 1;
    }
    try saveHistory(allocator, &history);
}

fn removeHistoryEntry(allocator: std.mem.Allocator, id: []const u8) !void {
    var history = std.StringHashMap(u32).init(allocator);
    defer {
        var it = history.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        history.deinit();
    }

    try loadHistory(allocator, &history);
    if (history.fetchRemove(id)) |kv| {
        allocator.free(kv.key);
    }
    try saveHistory(allocator, &history);
}
