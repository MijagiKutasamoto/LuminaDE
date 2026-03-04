const std = @import("std");
const core = @import("luminade_core");
const ui = @import("luminade_ui");

const Entry = struct {
    id: []const u8,
    title: []const u8,
    command: []const u8,
    tags: []const u8,
};

const ScoredEntry = struct {
    entry: Entry,
    score: u32,
    uses: u32,
    pinned: bool,
};

const ResultBinding = struct {
    widget_id: []const u8,
    entry_id: []const u8,
    command: []const u8,
};

const LaunchGuard = struct {
    window_start_ns: i64,
    launches_in_window: u16,
    last_launch_ns: i64,

    fn init() LaunchGuard {
        return .{
            .window_start_ns = 0,
            .launches_in_window = 0,
            .last_launch_ns = 0,
        };
    }

    fn allowLaunch(self: *LaunchGuard, now_ns: i64) bool {
        const min_gap_ns: i64 = 250 * std.time.ns_per_ms;
        if (self.last_launch_ns != 0 and now_ns - self.last_launch_ns < min_gap_ns) {
            return false;
        }

        const window_ns: i64 = 10 * std.time.ns_per_s;
        if (self.window_start_ns == 0 or now_ns - self.window_start_ns >= window_ns) {
            self.window_start_ns = now_ns;
            self.launches_in_window = 0;
        }

        const max_launches_per_window: u16 = 12;
        if (self.launches_in_window >= max_launches_per_window) {
            return false;
        }

        self.launches_in_window += 1;
        self.last_launch_ns = now_ns;
        return true;
    }
};

const InteractionBehavior = struct {
    mode: core.InteractionMode,
    focus_policy: []const u8,
    pointer_target_px: u8,
    default_result_limit: usize,
    pointer_sensitivity: i8,
    accel_profile: core.PointerAccelProfile,
    natural_scroll: bool,
    tap_to_click: bool,

    fn fromProfile(profile: core.DesktopProfile) InteractionBehavior {
        const base_target: u8 = switch (profile.interaction_mode) {
            .mouse_first => 44,
            .balanced => 40,
            .keyboard_first => 32,
        };
        const adjusted_target_i16 = @as(i16, @intCast(base_target)) + @divTrunc(@as(i16, profile.pointer_sensitivity), 10);
        const adjusted_target = @as(u8, @intCast(@max(@as(i16, 28), @min(@as(i16, 56), adjusted_target_i16))));

        const base_limit: usize = switch (profile.interaction_mode) {
            .mouse_first => 12,
            .balanced => 10,
            .keyboard_first => 8,
        };
        const limit_bonus: usize = if (profile.pointer_sensitivity > 0)
            @as(usize, @intCast(@divTrunc(@as(i16, profile.pointer_sensitivity), 25)))
        else
            0;

        const focus_policy = switch (profile.interaction_mode) {
            .mouse_first => if (profile.pointer_accel_profile == .flat) "hover-precise" else "hover-first",
            .balanced => "smart-focus",
            .keyboard_first => "keyboard-first",
        };

        return .{
            .mode = profile.interaction_mode,
            .focus_policy = focus_policy,
            .pointer_target_px = adjusted_target,
            .default_result_limit = base_limit + limit_bonus,
            .pointer_sensitivity = profile.pointer_sensitivity,
            .accel_profile = profile.pointer_accel_profile,
            .natural_scroll = profile.natural_scroll,
            .tap_to_click = profile.tap_to_click,
        };
    }
};

const seed_catalog = [_]Entry{
    .{ .id = "terminal", .title = "Terminal", .command = "foot", .tags = "shell dev system" },
    .{ .id = "browser", .title = "Web Browser", .command = "firefox", .tags = "internet web" },
    .{ .id = "files", .title = "File Manager", .command = "thunar", .tags = "files disk" },
    .{ .id = "settings", .title = "Lumina Settings", .command = "luminade-settings", .tags = "control panel system" },
    .{ .id = "editor", .title = "Code Editor", .command = "code", .tags = "ide editor development" },
    .{ .id = "audio", .title = "Audio Mixer", .command = "pavucontrol", .tags = "sound pipewire" },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const cfg = core.RuntimeConfig.init(allocator);
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var daemon_mode = false;
    var query: ?[]const u8 = null;
    var record_id: ?[]const u8 = null;
    var limit: usize = 0;
    var limit_explicit = false;
    var show_all = false;
    var gui_mode = true;

    if (args.len >= 2 and std.mem.eql(u8, args[1], "favorite")) {
        try handleFavoriteCommand(allocator, args[2..]);
        return;
    }

    const behavior = InteractionBehavior.fromProfile(cfg.profile);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--daemon")) {
            daemon_mode = true;
            gui_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--query") and i + 1 < args.len) {
            i += 1;
            query = args[i];
            gui_mode = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--record") and i + 1 < args.len) {
            i += 1;
            record_id = args[i];
            gui_mode = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--limit") and i + 1 < args.len) {
            i += 1;
            limit = std.fmt.parseUnsigned(usize, args[i], 10) catch limit;
            limit_explicit = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--all")) {
            show_all = true;
            gui_mode = false;
            continue;
        }
    }

    core.printBanner(.launcher, cfg);
    core.printModernSummary(.launcher, cfg);
    std.debug.print(
        "[interaction] mode={s} focus={s} pointer-target={d}px sens={d} accel={s} natural={any} tap={any}\n",
        .{
            @tagName(behavior.mode),
            behavior.focus_policy,
            behavior.pointer_target_px,
            behavior.pointer_sensitivity,
            @tagName(behavior.accel_profile),
            behavior.natural_scroll,
            behavior.tap_to_click,
        },
    );

    var watcher = try ui.OutputWatcher.init(allocator);
    defer watcher.deinit();
    std.debug.print("[watcher] backend={s}\n", .{watcher.backendName()});
    printOutputState(&watcher);

    if (record_id) |id| {
        try recordSelection(allocator, id);
        std.debug.print("Recorded launcher usage for '{s}'.\n", .{id});
        return;
    }

    if (!limit_explicit) limit = behavior.default_result_limit;
    if (show_all) limit = std.math.maxInt(usize);

    if (gui_mode or daemon_mode) {
        std.debug.print("Launcher GUI mode started (GUI-first).\n", .{});
        var launch_guard = LaunchGuard.init();
        while (true) {
            const current_query = try loadLauncherGuiQuery(allocator);
            defer allocator.free(current_query);

            try runSearch(allocator, current_query, limit, behavior, cfg.profile.launcher_width);
            _ = try processLauncherGuiEventQueue(allocator, &launch_guard);

            const event = try watcher.waitForEvent(1500);
            if (event and try watcher.poll()) {
                std.debug.print("[watcher] monitor topology changed, refreshing launcher surfaces\n", .{});
                printOutputState(&watcher);
            }
        }
    }

    try runSearch(allocator, query orelse "", limit, behavior, cfg.profile.launcher_width);
}

fn loadLauncherGuiQuery(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_QUERY")) |value| {
        return try allocator.dupe(u8, value);
    }

    const path = std.posix.getenv("LUMINADE_LAUNCHER_QUERY_PATH") orelse ".luminade/gui-launcher-query.txt";
    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return try allocator.dupe(u8, ""),
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(content);
    return try allocator.dupe(u8, std.mem.trim(u8, content, " \t\r\n"));
}

fn runSearch(
    allocator: std.mem.Allocator,
    query: []const u8,
    limit: usize,
    behavior: InteractionBehavior,
    launcher_width: u16,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var entries = try loadCatalog(arena_allocator);

    var history = std.StringHashMap(u32).init(allocator);
    defer {
        var it = history.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        history.deinit();
    }

    try loadHistory(allocator, &history);

    var favorites = std.StringHashMap(void).init(allocator);
    defer {
        var fit = favorites.keyIterator();
        while (fit.next()) |key_ptr| allocator.free(key_ptr.*);
        favorites.deinit();
    }
    try loadFavorites(allocator, &favorites);

    var scored = std.ArrayList(ScoredEntry).init(allocator);
    defer scored.deinit();

    for (entries.items) |entry| {
        const uses = history.get(entry.id) orelse 0;
        const pinned = favorites.contains(entry.id);
        const score = scoreEntry(entry, query, uses, behavior, pinned);
        if (score == 0 and query.len > 0) continue;

        try scored.append(.{
            .entry = entry,
            .score = score,
            .uses = uses,
            .pinned = pinned,
        });
    }

    std.sort.heap(ScoredEntry, scored.items, {}, lessByScore);

    const to_show = @min(limit, scored.items.len);
    std.debug.print(
        "Launcher results ({d}/{d}, indexed={d}) for query='{s}' [mode={s}]\n",
        .{ to_show, scored.items.len, entries.items.len, query, @tagName(behavior.mode) },
    );
    for (scored.items[0..to_show], 0..) |item, idx| {
        std.debug.print("{d}. {s}{s} [{s}] score={d} uses={d} -> {s}\n", .{
            idx + 1,
            if (item.pinned) "★ " else "",
            item.entry.title,
            item.entry.id,
            item.score,
            item.uses,
            item.entry.command,
        });
    }

    try renderLauncherGui(allocator, query, scored.items[0..to_show], behavior, launcher_width);
    try writeLauncherResultBindings(allocator, scored.items[0..to_show]);
}

fn renderLauncherGui(
    allocator: std.mem.Allocator,
    query: []const u8,
    items: []const ScoredEntry,
    behavior: InteractionBehavior,
    launcher_width: u16,
) !void {
    const surface = ui.launcherSurface(launcher_width);
    var frame = ui.GuiFrame.init(allocator, "Launcher", surface);
    defer frame.deinit();

    const panel_width = @min(surface.width -| 64, launcher_width);
    const panel_x = @divTrunc(@as(i32, @intCast(surface.width)) - @as(i32, @intCast(panel_width)), 2);

    try ui.addWidget(&frame, .{
        .id = "launcher-root",
        .kind = .column,
        .label = "launcher-root",
        .rect = .{ .x = panel_x, .y = 80, .w = panel_width, .h = @max(surface.height - 160, 200) },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "search-input",
        .kind = .input,
        .label = if (query.len == 0) "Type to search" else query,
        .rect = .{ .x = panel_x + 16, .y = 96, .w = panel_width - 32, .h = @max(@as(u16, behavior.pointer_target_px), 40) },
        .interactive = true,
        .hoverable = true,
    });

    var y: i32 = 148;
    const item_h: u16 = @max(@as(u16, behavior.pointer_target_px), 36);
    for (items, 0..) |item, idx| {
        const id = if (idx == 0) "result-0" else if (idx == 1) "result-1" else if (idx == 2) "result-2" else if (idx == 3) "result-3" else if (idx == 4) "result-4" else "result-n";

        if (item.pinned) {
            const pin_id = if (idx == 0) "pin-0" else if (idx == 1) "pin-1" else if (idx == 2) "pin-2" else if (idx == 3) "pin-3" else if (idx == 4) "pin-4" else "pin-n";
            try ui.addWidget(&frame, .{
                .id = pin_id,
                .kind = .badge,
                .label = "★",
                .rect = .{ .x = panel_x + 22, .y = y + 8, .w = 20, .h = 20 },
                .interactive = false,
                .hoverable = false,
            });
        }

        try ui.addWidget(&frame, .{
            .id = id,
            .kind = .list_item,
            .label = item.entry.title,
            .rect = .{ .x = panel_x + 16, .y = y, .w = panel_width - 32, .h = item_h },
            .interactive = true,
            .hoverable = true,
        });
        y += @as(i32, @intCast(item_h)) + 8;
    }

    ui.printGuiFrame(&frame);
}

fn launcherGuiEventsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_GUI_EVENTS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/gui-launcher-events.tsv");
}

fn launcherBindingsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_BINDINGS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/gui-launcher-bindings.tsv");
}

fn writeLauncherResultBindings(allocator: std.mem.Allocator, items: []const ScoredEntry) !void {
    const path = try launcherBindingsPath(allocator);
    defer allocator.free(path);

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("# widget-id\tentry-id\tcommand\n");
    for (items, 0..) |item, idx| {
        const widget_id = if (idx == 0) "result-0" else if (idx == 1) "result-1" else if (idx == 2) "result-2" else if (idx == 3) "result-3" else if (idx == 4) "result-4" else "result-n";
        try writer.print("{s}\t{s}\t{s}\n", .{ widget_id, item.entry.id, item.entry.command });
    }
}

fn processLauncherGuiEventQueue(allocator: std.mem.Allocator, launch_guard: *LaunchGuard) !bool {
    const path = try launcherGuiEventsPath(allocator);
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
        const widget_id = tokens.items[1];
        const binding = try resolveLauncherBinding(allocator, widget_id) orelse continue;
        defer allocator.free(binding.widget_id);
        defer allocator.free(binding.entry_id);
        defer allocator.free(binding.command);

        if (std.mem.eql(u8, action, "click")) {
            const now_ns = std.time.nanoTimestamp();
            if (!launch_guard.allowLaunch(now_ns)) {
                std.debug.print("[launcher] click throttled widget={s} id={s}\n", .{ widget_id, binding.entry_id });
                continue;
            }

            try launchCommandDetached(allocator, binding.command);
            try recordSelection(allocator, binding.entry_id);
            std.debug.print("[launcher] launched id={s} cmd={s}\n", .{ binding.entry_id, binding.command });
            changed = true;
            continue;
        }

        if (std.mem.eql(u8, action, "context") and tokens.items.len >= 3) {
            const menu_action = tokens.items[2];
            if (std.mem.eql(u8, menu_action, "favorite-add")) {
                try setFavorite(allocator, binding.entry_id, true);
                changed = true;
            } else if (std.mem.eql(u8, menu_action, "favorite-remove")) {
                try setFavorite(allocator, binding.entry_id, false);
                changed = true;
            } else if (std.mem.eql(u8, menu_action, "remove-history")) {
                try removeHistoryEntry(allocator, binding.entry_id);
                changed = true;
            }
        }
    }

    var truncate = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer truncate.close();
    try truncate.writer().writeAll("# action\twidget-id\t[menu-action]\n# click\tresult-0\n# context\tresult-0\tfavorite-add\n");

    return changed;
}

fn resolveLauncherBinding(allocator: std.mem.Allocator, widget_id: []const u8) !?ResultBinding {
    const path = try launcherBindingsPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 128 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var split = std.mem.splitScalar(u8, line, '\t');
        const w = split.next() orelse continue;
        const id = split.next() orelse continue;
        const cmd = split.next() orelse continue;

        if (!std.mem.eql(u8, std.mem.trim(u8, w, " \t\r"), widget_id)) continue;
        return .{
            .widget_id = try allocator.dupe(u8, std.mem.trim(u8, w, " \t\r")),
            .entry_id = try allocator.dupe(u8, std.mem.trim(u8, id, " \t\r")),
            .command = try allocator.dupe(u8, std.mem.trim(u8, cmd, " \t\r")),
        };
    }

    return null;
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
    } else {
        if (favorites.fetchRemove(id)) |kv| {
            allocator.free(kv.key);
        }
    }

    try saveFavorites(allocator, &favorites);
}

fn loadCatalog(allocator: std.mem.Allocator) !std.ArrayList(Entry) {
    var entries = std.ArrayList(Entry).init(allocator);
    var seen = std.StringHashMap(void).init(allocator);

    for (seed_catalog) |item| {
        try entries.append(item);
        try seen.put(try allocator.dupe(u8, item.id), {});
    }

    try collectSystemApps(allocator, &entries, &seen);
    return entries;
}

fn collectSystemApps(
    allocator: std.mem.Allocator,
    entries: *std.ArrayList(Entry),
    seen: *std.StringHashMap(void),
) !void {
    const path_env = std.posix.getenv("PATH") orelse return;
    var dir_it = std.mem.splitScalar(u8, path_env, ':');

    while (dir_it.next()) |dir_raw| {
        const dir_path = std.mem.trim(u8, dir_raw, " \t\r");
        if (dir_path.len == 0) continue;

        var dir = openDirFromPath(dir_path) catch continue;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |item| {
            if (item.kind != .file and item.kind != .sym_link) continue;

            const command = item.name;
            if (!isLaunchableCommand(command)) continue;
            if (seen.contains(command)) continue;

            const stat = dir.statFile(command) catch continue;
            if ((stat.mode & 0o111) == 0) continue;

            const owned_key = try allocator.dupe(u8, command);
            try seen.put(owned_key, {});

            const title = try allocator.dupe(u8, command);
            try entries.append(.{
                .id = owned_key,
                .title = title,
                .command = owned_key,
                .tags = "system",
            });
        }
    }
}

fn openDirFromPath(path: []const u8) !std.fs.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return try std.fs.openDirAbsolute(path, .{ .iterate = true });
    }

    return try std.fs.cwd().openDir(path, .{ .iterate = true });
}

fn isLaunchableCommand(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.') return false;
    if (std.mem.indexOfScalar(u8, name, '/')) |_| return false;
    return true;
}

fn lessByScore(_: void, a: ScoredEntry, b: ScoredEntry) bool {
    if (a.pinned != b.pinned) return a.pinned;
    return a.score > b.score;
}

fn scoreEntry(entry: Entry, query: []const u8, uses: u32, behavior: InteractionBehavior, pinned: bool) u32 {
    var score: u32 = switch (behavior.mode) {
        .mouse_first => uses * 80,
        .balanced => uses * 60,
        .keyboard_first => uses * 50,
    };

    if (pinned) score += 2000;

    if (behavior.natural_scroll and behavior.mode == .mouse_first) score += 8;
    if (behavior.tap_to_click and behavior.mode != .keyboard_first) score += 12;

    if (query.len == 0) return score + 10;

    switch (behavior.mode) {
        .mouse_first => {
            if (equalsIgnoreCase(entry.id, query)) score += 900;
            if (containsIgnoreCase(entry.title, query)) score += 700;
            if (containsIgnoreCase(entry.tags, query)) score += 400;
            if (subsequenceIgnoreCase(entry.title, query)) score += 60;
        },
        .balanced => {
            if (equalsIgnoreCase(entry.id, query)) score += 1000;
            if (containsIgnoreCase(entry.title, query)) score += 650;
            if (containsIgnoreCase(entry.tags, query)) score += 320;
            if (subsequenceIgnoreCase(entry.title, query)) score += 120;
        },
        .keyboard_first => {
            if (equalsIgnoreCase(entry.id, query)) score += 1100;
            if (containsIgnoreCase(entry.title, query)) score += 550;
            if (containsIgnoreCase(entry.tags, query)) score += 260;
            if (subsequenceIgnoreCase(entry.title, query)) score += 200;
        },
    }

    return score;
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

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("# launcher favorites (entry ids)\n");

    var it = favorites.keyIterator();
    while (it.next()) |key_ptr| {
        try writer.print("{s}\n", .{key_ptr.*});
    }
}

fn handleFavoriteCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printFavoriteUsage();
        return;
    }

    var favorites = std.StringHashMap(void).init(allocator);
    defer {
        var it = favorites.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        favorites.deinit();
    }
    try loadFavorites(allocator, &favorites);

    const cmd = args[0];
    if (std.mem.eql(u8, cmd, "list")) {
        std.debug.print("Launcher favorites: {d}\n", .{favorites.count()});
        var it = favorites.keyIterator();
        while (it.next()) |key_ptr| {
            std.debug.print("- {s}\n", .{key_ptr.*});
        }
        return;
    }

    if ((std.mem.eql(u8, cmd, "add") or std.mem.eql(u8, cmd, "remove")) and args.len < 2) {
        printFavoriteUsage();
        return;
    }

    if (std.mem.eql(u8, cmd, "add")) {
        const id = args[1];
        const gop = try favorites.getOrPut(id);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, id);
            gop.value_ptr.* = {};
            try saveFavorites(allocator, &favorites);
        }
        std.debug.print("Added launcher favorite: {s}\n", .{id});
        return;
    }

    if (std.mem.eql(u8, cmd, "remove")) {
        const id = args[1];
        if (favorites.fetchRemove(id)) |kv| {
            allocator.free(kv.key);
            try saveFavorites(allocator, &favorites);
            std.debug.print("Removed launcher favorite: {s}\n", .{id});
        } else {
            std.debug.print("Favorite not found: {s}\n", .{id});
        }
        return;
    }

    printFavoriteUsage();
}

fn printFavoriteUsage() void {
    std.debug.print("Launcher favorite usage:\n", .{});
    std.debug.print("  luminade-launcher favorite list\n", .{});
    std.debug.print("  luminade-launcher favorite add <entry-id>\n", .{});
    std.debug.print("  luminade-launcher favorite remove <entry-id>\n", .{});
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) {
            return true;
        }
    }

    return false;
}

fn subsequenceIgnoreCase(text: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return true;

    var p: usize = 0;
    for (text) |ch| {
        if (std.ascii.toLower(ch) == std.ascii.toLower(pattern[p])) {
            p += 1;
            if (p == pattern.len) return true;
        }
    }

    return false;
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

fn recordSelection(allocator: std.mem.Allocator, id: []const u8) !void {
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

fn saveHistory(allocator: std.mem.Allocator, history: *std.StringHashMap(u32)) !void {
    const path = try historyPath(allocator);
    defer allocator.free(path);

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var iter = history.iterator();
    const writer = file.writer();
    while (iter.next()) |item| {
        try writer.print("{s}\t{d}\n", .{ item.key_ptr.*, item.value_ptr.* });
    }
}

fn printOutputState(watcher: *ui.OutputWatcher) void {
    std.debug.print("Detected outputs: {d}\n", .{watcher.outputs.items.len});
    for (watcher.outputs.items) |output| {
        const surface = ui.fullscreenSurface(.launcher, output);
        ui.printSurfaceSummary(surface, ui.ThemeTokens.modernDefault());
        ui.printRenderSpec(ui.renderSpecForSurface(surface));
    }
}
