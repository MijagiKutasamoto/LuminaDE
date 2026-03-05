const std = @import("std");
const core = @import("luminade_core");
const ui = @import("luminade_ui");

const Entry = struct {
    id: []const u8,
    title: []const u8,
    command: []const u8,
    tags: []const u8,
};

const DesktopCacheRecord = struct {
    source_path: []const u8,
    source_mtime: i128,
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
    alias_hit: bool,
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
    printOutputState(allocator, &watcher, cfg.profile);

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

            try runSearch(allocator, current_query, limit, behavior, cfg.profile, cfg.profile.launcher_width, cfg.lang);
            _ = try processLauncherGuiEventQueue(allocator, &launch_guard);

            const event = try watcher.waitForEvent(1500);
            if (event and try watcher.poll()) {
                std.debug.print("[watcher] monitor topology changed, refreshing launcher surfaces\n", .{});
                printOutputState(allocator, &watcher, cfg.profile);
            }
        }
    }

    try runSearch(allocator, query orelse "", limit, behavior, cfg.profile, cfg.profile.launcher_width, cfg.lang);
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
    profile: core.DesktopProfile,
    launcher_width: u16,
    lang: core.Lang,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var entries = try loadCatalog(arena_allocator, profile);

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
        const alias_hit = aliasMatch(entry.tags, query);

        try scored.append(.{
            .entry = entry,
            .score = score,
            .uses = uses,
            .pinned = pinned,
            .alias_hit = alias_hit,
        });
    }

    const trimmed_query = std.mem.trim(u8, query, " \t\r\n");
    if (trimmed_query.len > 0) {
        if (quickMathEval(trimmed_query)) |calc_value| {
            const calc_title = try std.fmt.allocPrint(arena_allocator, "= {d}", .{calc_value});
            const escaped = try shellEscapeSingleQuotes(arena_allocator, calc_title);
            const calc_cmd = try std.fmt.allocPrint(
                arena_allocator,
                "sh -lc \"if command -v wl-copy >/dev/null 2>&1; then printf '%s' '{s}' | wl-copy; fi\"",
                .{escaped},
            );
            try scored.append(.{
                .entry = .{
                    .id = "calc-result",
                    .title = calc_title,
                    .command = calc_cmd,
                    .tags = "calculator math alias:calc alias:=",
                },
                .score = 25_000,
                .uses = 0,
                .pinned = false,
                .alias_hit = true,
            });
        }

        if (std.ascii.eqlIgnoreCase(trimmed_query, "yt") or std.ascii.eqlIgnoreCase(trimmed_query, "youtube")) {
            try scored.append(.{
                .entry = .{
                    .id = "alias-youtube",
                    .title = "YouTube",
                    .command = "xdg-open https://youtube.com",
                    .tags = "web browser alias:yt alias:youtube",
                },
                .score = 24_000,
                .uses = 0,
                .pinned = false,
                .alias_hit = true,
            });
        }

        const runner_title = try std.fmt.allocPrint(arena_allocator, "Run command: {s}", .{trimmed_query});
        try scored.append(.{
            .entry = .{
                .id = "runner-command",
                .title = runner_title,
                .command = trimmed_query,
                .tags = "runner shell command alias:run",
            },
            .score = 900,
            .uses = 0,
            .pinned = false,
            .alias_hit = false,
        });
    }

    std.sort.heap(ScoredEntry, scored.items, {}, lessByScore);

    const to_show = @min(limit, scored.items.len);
    std.debug.print(
        "Launcher results ({d}/{d}, indexed={d}) for query='{s}' [mode={s}]\n",
        .{ to_show, scored.items.len, entries.items.len, query, @tagName(behavior.mode) },
    );
    for (scored.items[0..to_show], 0..) |item, idx| {
        std.debug.print("{d}. {s}{s}{s} [{s}] score={d} uses={d} -> {s}\n", .{
            idx + 1,
            if (item.pinned) "★ " else "",
            if (item.alias_hit) "~ " else "",
            item.entry.title,
            item.entry.id,
            item.score,
            item.uses,
            item.entry.command,
        });
    }

    try renderLauncherGui(allocator, query, scored.items[0..to_show], behavior, launcher_width, lang, profile);
    try writeLauncherResultBindings(allocator, scored.items[0..to_show]);
}

fn renderLauncherGui(
    allocator: std.mem.Allocator,
    query: []const u8,
    items: []const ScoredEntry,
    behavior: InteractionBehavior,
    launcher_width: u16,
    lang: core.Lang,
    profile: core.DesktopProfile,
) !void {
    var theme_profile = try core.loadThemeProfile(allocator, profile);
    defer theme_profile.deinit(allocator);
    const theme_tokens: ui.ThemeTokens = .{
        .corner_radius = theme_profile.corner_radius,
        .spacing_unit = theme_profile.spacing_unit,
        .blur_sigma = theme_profile.blur_sigma,
    };
    const decor_theme = ui.SurfaceDecorationTheme.fromThemeTokens(theme_tokens);

    const surface = ui.launcherSurfaceThemed(launcher_width, decor_theme);
    var frame = ui.GuiFrame.init(allocator, "Launcher", surface);
    defer frame.deinit();

    const visual_target_width: u16 = @max(launcher_width, 860);
    const panel_width = @min(surface.width -| 96, visual_target_width);
    const panel_x = @divTrunc(@as(i32, @intCast(surface.width)) - @as(i32, @intCast(panel_width)), 2);
    const root_y: i32 = 88;

    try ui.addWidget(&frame, .{
        .id = "launcher-root",
        .kind = .column,
        .label = "launcher-root",
        .rect = .{ .x = panel_x, .y = root_y, .w = panel_width, .h = @max(surface.height - 176, 260) },
        .interactive = false,
        .hoverable = false,
    });

    const title_label = try localeText(allocator, lang, "launcher.title", "Launch");
    defer allocator.free(title_label);
    const hint_label = try localeText(allocator, lang, "launcher.hint", "Apps, commands, recent");
    defer allocator.free(hint_label);
    const search_placeholder = try localeText(allocator, lang, "launcher.search.placeholder", "Type to search");
    defer allocator.free(search_placeholder);

    try ui.addWidget(&frame, .{
        .id = "launcher-title",
        .kind = .text,
        .label = title_label,
        .rect = .{ .x = panel_x + 20, .y = root_y + 12, .w = 180, .h = 24 },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "launcher-hint",
        .kind = .text,
        .label = hint_label,
        .rect = .{ .x = panel_x + 20, .y = root_y + 36, .w = 280, .h = 20 },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "search-input",
        .kind = .input,
        .label = if (query.len == 0) search_placeholder else query,
        .rect = .{ .x = panel_x + 18, .y = root_y + 64, .w = panel_width - 36, .h = @max(@as(u16, behavior.pointer_target_px), 46) },
        .interactive = true,
        .hoverable = true,
    });

    var y: i32 = root_y + 128;
    const item_h: u16 = @max(@as(u16, behavior.pointer_target_px), 42);
    for (items, 0..) |item, idx| {
        const id = if (idx == 0) "result-0" else if (idx == 1) "result-1" else if (idx == 2) "result-2" else if (idx == 3) "result-3" else if (idx == 4) "result-4" else "result-n";
        const localized_title = try launcherEntryTitle(allocator, lang, item.entry);
        defer allocator.free(localized_title);
        const item_label = try ui.composeIconLabel(allocator, iconNameForLauncherEntry(item.entry), localized_title);
        defer allocator.free(item_label);

        if (item.pinned) {
            const pin_id = if (idx == 0) "pin-0" else if (idx == 1) "pin-1" else if (idx == 2) "pin-2" else if (idx == 3) "pin-3" else if (idx == 4) "pin-4" else "pin-n";
            try ui.addWidget(&frame, .{
                .id = pin_id,
                .kind = .badge,
                .label = "★",
                .rect = .{ .x = panel_x + 26, .y = y + 10, .w = 20, .h = 20 },
                .interactive = false,
                .hoverable = false,
            });
        }

        try ui.addWidget(&frame, .{
            .id = id,
            .kind = .list_item,
            .label = item_label,
            .rect = .{ .x = panel_x + 18, .y = y, .w = panel_width - 36, .h = item_h },
            .interactive = true,
            .hoverable = true,
        });
        y += @as(i32, @intCast(item_h)) + 10;
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

fn iconNameForLauncherEntry(entry: Entry) []const u8 {
    if (iconNameFromTags(entry.tags)) |icon_from_tags| return icon_from_tags;

    if (std.mem.eql(u8, entry.id, "terminal")) return "luminade-terminal";
    if (std.mem.eql(u8, entry.id, "browser")) return "luminade-browser";
    if (std.mem.eql(u8, entry.id, "files")) return "luminade-files";
    if (std.mem.eql(u8, entry.id, "settings")) return "preferences-system-symbolic";
    if (std.mem.eql(u8, entry.id, "welcome")) return "luminade-welcome";
    if (std.mem.eql(u8, entry.id, "audio")) return "audio-volume-high-symbolic";

    if (std.mem.indexOf(u8, entry.command, "code") != null or std.mem.indexOf(u8, entry.tags, "editor") != null) {
        return "luminade-settings";
    }
    if (std.mem.indexOf(u8, entry.tags, "web") != null or std.mem.indexOf(u8, entry.tags, "internet") != null) {
        return "network-wireless-symbolic";
    }

    return "luminade";
}

fn iconNameFromTags(tags: []const u8) ?[]const u8 {
    var tok = std.mem.tokenizeAny(u8, tags, " \t");
    while (tok.next()) |part| {
        if (!std.mem.startsWith(u8, part, "icon:")) continue;
        const name = std.mem.trim(u8, part[5..], " \t\r");
        if (name.len > 0) return name;
    }
    return null;
}

fn launcherEntryTitle(allocator: std.mem.Allocator, lang: core.Lang, entry: Entry) ![]u8 {
    const key = if (std.mem.eql(u8, entry.id, "terminal"))
        "launcher.entry.terminal"
    else if (std.mem.eql(u8, entry.id, "browser"))
        "launcher.entry.browser"
    else if (std.mem.eql(u8, entry.id, "files"))
        "launcher.entry.files"
    else if (std.mem.eql(u8, entry.id, "settings"))
        "launcher.entry.settings"
    else if (std.mem.eql(u8, entry.id, "welcome"))
        "launcher.entry.welcome"
    else if (std.mem.eql(u8, entry.id, "editor"))
        "launcher.entry.editor"
    else if (std.mem.eql(u8, entry.id, "audio"))
        "launcher.entry.audio"
    else
        "";

    if (key.len == 0) return try allocator.dupe(u8, entry.title);
    return localeText(allocator, lang, key, entry.title);
}

fn localeText(allocator: std.mem.Allocator, lang: core.Lang, key: []const u8, fallback: []const u8) ![]u8 {
    if (try core.localeGet(allocator, lang, key)) |resolved| {
        return resolved;
    }
    if (lang != .en) {
        if (try core.localeGet(allocator, .en, key)) |resolved_en| {
            return resolved_en;
        }
    }
    return try allocator.dupe(u8, fallback);
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

fn loadCatalog(allocator: std.mem.Allocator, profile: core.DesktopProfile) !std.ArrayList(Entry) {
    var entries = std.ArrayList(Entry).init(allocator);
    var seen = std.StringHashMap(void).init(allocator);

    const seed_catalog = [_]Entry{
        .{ .id = "terminal", .title = "Terminal", .command = profile.terminalCommand(), .tags = "shell dev system alias:term alias:tty icon:luminade-terminal" },
        .{ .id = "browser", .title = "Web Browser", .command = profile.browserCommand(), .tags = "internet web alias:www alias:yt icon:luminade-browser" },
        .{ .id = "files", .title = "File Manager", .command = profile.filesCommand(), .tags = "files disk alias:fm icon:luminade-files" },
        .{ .id = "settings", .title = "Lumina Settings", .command = "luminade-settings", .tags = "control panel system alias:cfg icon:preferences-system-symbolic" },
        .{ .id = "welcome", .title = "Lumina Welcome", .command = "luminade-welcome --force", .tags = "onboarding setup first-run icon:luminade-welcome" },
        .{ .id = "editor", .title = "Code Editor", .command = "code", .tags = "ide editor development alias:code icon:luminade-settings" },
        .{ .id = "audio", .title = "Audio Mixer", .command = "pavucontrol", .tags = "sound pipewire alias:vol alias:volume icon:audio-volume-high-symbolic" },
    };

    for (seed_catalog) |item| {
        try entries.append(item);
        try seen.put(try allocator.dupe(u8, item.id), {});
    }

    try collectDesktopApps(allocator, &entries, &seen);
    try collectSystemApps(allocator, &entries, &seen);
    return entries;
}

fn collectDesktopApps(
    allocator: std.mem.Allocator,
    entries: *std.ArrayList(Entry),
    seen: *std.StringHashMap(void),
) !void {
    var records = std.ArrayList(DesktopCacheRecord).init(allocator);
    defer {
        for (records.items) |record| freeDesktopCacheRecord(allocator, record);
        records.deinit();
    }

    const cache_loaded = try loadDesktopCacheRecords(allocator, &records);
    var cache_updated = false;
    const refresh = shouldForceDesktopRefresh() or try desktopCacheNeedsRefresh(allocator);

    if (!cache_loaded) {
        var rebuilt = try rebuildDesktopCacheRecords(allocator);
        defer rebuilt.deinit();
        for (rebuilt.items) |record| try records.append(record);
        rebuilt.clearRetainingCapacity();
        cache_updated = true;
    } else if (refresh) {
        var refreshed = try refreshDesktopCacheIncremental(allocator, records.items);
        defer refreshed.deinit();

        for (records.items) |record| freeDesktopCacheRecord(allocator, record);
        records.clearRetainingCapacity();

        for (refreshed.items) |record| try records.append(record);
        refreshed.clearRetainingCapacity();
        cache_updated = true;
    }

    if (cache_updated) {
        try saveDesktopCacheRecords(allocator, records.items);
    }

    for (records.items) |record| {
        if (seen.contains(record.id)) continue;

        const owned_id = try allocator.dupe(u8, record.id);
        try seen.put(owned_id, {});
        try entries.append(.{
            .id = owned_id,
            .title = try allocator.dupe(u8, record.title),
            .command = try allocator.dupe(u8, record.command),
            .tags = try allocator.dupe(u8, record.tags),
        });
    }
}

fn freeDesktopCacheRecord(allocator: std.mem.Allocator, record: DesktopCacheRecord) void {
    allocator.free(record.source_path);
    allocator.free(record.id);
    allocator.free(record.title);
    allocator.free(record.command);
    allocator.free(record.tags);
}

fn shouldForceDesktopRefresh() bool {
    if (std.posix.getenv("LUMINADE_LAUNCHER_DESKTOP_REFRESH")) |value| {
        return parseDesktopBool(value);
    }
    return false;
}

fn loadDesktopCacheRecords(allocator: std.mem.Allocator, records: *std.ArrayList(DesktopCacheRecord)) !bool {
    const path = try desktopCachePath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var fields = std.mem.splitScalar(u8, line, '\t');
        const c1 = fields.next() orelse continue;
        const c2 = fields.next() orelse continue;
        const c3 = fields.next() orelse continue;
        const c4 = fields.next() orelse continue;
        const c5 = fields.next();
        const c6 = fields.next();

        if (c6 != null) {
            try records.append(.{
                .source_path = try allocator.dupe(u8, std.mem.trim(u8, c1, " \t\r")),
                .source_mtime = std.fmt.parseInt(i128, std.mem.trim(u8, c2, " \t\r"), 10) catch 0,
                .id = try allocator.dupe(u8, std.mem.trim(u8, c3, " \t\r")),
                .title = try allocator.dupe(u8, std.mem.trim(u8, c4, " \t\r")),
                .command = try allocator.dupe(u8, std.mem.trim(u8, c5.?, " \t\r")),
                .tags = try allocator.dupe(u8, std.mem.trim(u8, c6.?, " \t\r")),
            });
        } else {
            // Backward compatibility: old cache format `id,title,command,tags`.
            try records.append(.{
                .source_path = try allocator.dupe(u8, ""),
                .source_mtime = 0,
                .id = try allocator.dupe(u8, std.mem.trim(u8, c1, " \t\r")),
                .title = try allocator.dupe(u8, std.mem.trim(u8, c2, " \t\r")),
                .command = try allocator.dupe(u8, std.mem.trim(u8, c3, " \t\r")),
                .tags = try allocator.dupe(u8, std.mem.trim(u8, c4, " \t\r")),
            });
        }
    }

    return true;
}

fn saveDesktopCacheRecords(allocator: std.mem.Allocator, records: []const DesktopCacheRecord) !void {
    const path = try desktopCachePath(allocator);
    defer allocator.free(path);

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("# source-path\tsource-mtime\tid\ttitle\tcommand\ttags\n");
    for (records) |record| {
        try writer.print(
            "{s}\t{d}\t{s}\t{s}\t{s}\t{s}\n",
            .{ record.source_path, record.source_mtime, record.id, record.title, record.command, record.tags },
        );
    }
}

fn rebuildDesktopCacheRecords(allocator: std.mem.Allocator) !std.ArrayList(DesktopCacheRecord) {
    return refreshDesktopCacheIncremental(allocator, &.{});
}

fn refreshDesktopCacheIncremental(
    allocator: std.mem.Allocator,
    existing: []const DesktopCacheRecord,
) !std.ArrayList(DesktopCacheRecord) {
    var out = std.ArrayList(DesktopCacheRecord).init(allocator);

    var source_to_index = std.StringHashMap(usize).init(allocator);
    defer {
        var it = source_to_index.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        source_to_index.deinit();
    }

    for (existing, 0..) |record, idx| {
        if (record.source_path.len == 0) continue;
        try source_to_index.put(try allocator.dupe(u8, record.source_path), idx);
    }

    var seen_ids = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen_ids.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        seen_ids.deinit();
    }

    var dirs = std.ArrayList([]const u8).init(allocator);
    defer {
        for (dirs.items) |dir_path| allocator.free(dir_path);
        dirs.deinit();
    }
    try appendDesktopSourceDirs(allocator, &dirs);

    for (dirs.items) |dir_path| {
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |item| {
            if (item.kind != .file and item.kind != .sym_link) continue;
            if (!std.mem.endsWith(u8, item.name, ".desktop")) continue;

            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, item.name });
            defer allocator.free(full_path);

            const stat = dir.statFile(item.name) catch continue;

            if (source_to_index.get(full_path)) |existing_idx| {
                const cached = existing[existing_idx];
                if (cached.source_mtime == stat.mtime) {
                    if (seen_ids.contains(cached.id)) continue;
                    try seen_ids.put(try allocator.dupe(u8, cached.id), {});

                    try out.append(.{
                        .source_path = try allocator.dupe(u8, cached.source_path),
                        .source_mtime = cached.source_mtime,
                        .id = try allocator.dupe(u8, cached.id),
                        .title = try allocator.dupe(u8, cached.title),
                        .command = try allocator.dupe(u8, cached.command),
                        .tags = try allocator.dupe(u8, cached.tags),
                    });
                    continue;
                }
            }

            const parsed = try parseDesktopFile(allocator, full_path) orelse continue;
            defer {
                allocator.free(parsed.id);
                allocator.free(parsed.title);
                allocator.free(parsed.command);
                allocator.free(parsed.tags);
            }

            const unique_id = try allocateUniqueIdForSeen(allocator, &seen_ids, parsed.id);
            defer allocator.free(unique_id);

            try out.append(.{
                .source_path = try allocator.dupe(u8, full_path),
                .source_mtime = stat.mtime,
                .id = try allocator.dupe(u8, unique_id),
                .title = try allocator.dupe(u8, parsed.title),
                .command = try allocator.dupe(u8, parsed.command),
                .tags = try allocator.dupe(u8, parsed.tags),
            });
        }
    }

    return out;
}

fn appendDesktopSourceDirs(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8)) !void {
    if (std.posix.getenv("HOME")) |home| {
        const user_apps = try std.fmt.allocPrint(allocator, "{s}/.local/share/applications", .{home});
        defer allocator.free(user_apps);
        try out.append(try allocator.dupe(u8, user_apps));
    }
    try out.append(try allocator.dupe(u8, "/usr/share/applications"));
    try out.append(try allocator.dupe(u8, "/usr/local/share/applications"));
}

fn desktopCachePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_DESKTOP_CACHE")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/launcher-desktop-index.tsv");
}

fn desktopCacheNeedsRefresh(allocator: std.mem.Allocator) !bool {
    const cache_path = try desktopCachePath(allocator);
    defer allocator.free(cache_path);

    const cache_mtime = fileMtimeIfExists(cache_path) orelse return true;
    const newest_desktop = try newestDesktopSourceMtime(allocator);
    return newest_desktop > cache_mtime;
}

fn newestDesktopSourceMtime(allocator: std.mem.Allocator) !i128 {
    var newest: i128 = 0;

    var dirs = std.ArrayList([]const u8).init(allocator);
    defer {
        for (dirs.items) |dir_path| allocator.free(dir_path);
        dirs.deinit();
    }
    try appendDesktopSourceDirs(allocator, &dirs);

    for (dirs.items) |dir_path| {
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |item| {
            if (item.kind != .file and item.kind != .sym_link) continue;
            if (!std.mem.endsWith(u8, item.name, ".desktop")) continue;

            const stat = dir.statFile(item.name) catch continue;
            if (stat.mtime > newest) newest = stat.mtime;
        }
    }

    return newest;
}

fn fileMtimeIfExists(path: []const u8) ?i128 {
    if (std.fs.path.isAbsolute(path)) {
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();

        const stat = file.stat() catch return null;
        return stat.mtime;
    }

    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    const stat = file.stat() catch return null;
    return stat.mtime;
}

fn parseDesktopFile(allocator: std.mem.Allocator, path: []const u8) !?Entry {
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 256 * 1024) catch return null;
    defer allocator.free(content);

    var in_desktop_entry = false;
    var hidden = false;
    var no_display = false;
    var name_value: ?[]u8 = null;
    var exec_value: ?[]u8 = null;
    var tags_value: ?[]u8 = null;
    var id_value: ?[]u8 = null;
    var icon_value: ?[]u8 = null;

    defer {
        if (name_value) |value| allocator.free(value);
        if (exec_value) |value| allocator.free(value);
        if (tags_value) |value| allocator.free(value);
        if (id_value) |value| allocator.free(value);
        if (icon_value) |value| allocator.free(value);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (line[0] == '[' and std.mem.eql(u8, line, "[Desktop Entry]")) {
            in_desktop_entry = true;
            continue;
        }
        if (line[0] == '[' and !std.mem.eql(u8, line, "[Desktop Entry]")) {
            if (in_desktop_entry) break;
            continue;
        }
        if (!in_desktop_entry) continue;

        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..separator], " \t\r");
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t\r");

        if (std.mem.eql(u8, key, "Hidden") and parseDesktopBool(value)) hidden = true;
        if (std.mem.eql(u8, key, "NoDisplay") and parseDesktopBool(value)) no_display = true;

        if (std.mem.eql(u8, key, "Name") and name_value == null and value.len > 0) {
            name_value = try allocator.dupe(u8, value);
            continue;
        }

        if (std.mem.eql(u8, key, "Exec") and exec_value == null and value.len > 0) {
            const command = extractDesktopExecCommand(value) orelse continue;
            exec_value = try allocator.dupe(u8, command);
            continue;
        }

        if (id_value == null and value.len > 0 and
            (std.mem.eql(u8, key, "X-Flatpak") or std.mem.eql(u8, key, "StartupWMClass")))
        {
            id_value = try allocator.dupe(u8, value);
            continue;
        }

        if (std.mem.eql(u8, key, "Icon") and icon_value == null and value.len > 0) {
            icon_value = try allocator.dupe(u8, value);
            continue;
        }

        if ((std.mem.eql(u8, key, "Keywords") or std.mem.eql(u8, key, "Categories")) and tags_value == null and value.len > 0) {
            tags_value = desktopTagsFromField(allocator, value) catch try allocator.dupe(u8, value);
            continue;
        }
    }

    if (hidden or no_display) return null;
    const title = name_value orelse return null;
    const command = exec_value orelse return null;
    const id = if (id_value) |raw_id|
        try slugFromText(allocator, raw_id)
    else
        try desktopIdFromPath(allocator, path);

    const tags_out = if (tags_value) |value|
        try allocator.dupe(u8, value)
    else
        try allocator.dupe(u8, "desktop");

    const final_tags = if (icon_value) |icon_name|
        try std.fmt.allocPrint(allocator, "{s} icon:{s}", .{ tags_out, icon_name })
    else
        tags_out;
    if (icon_value != null) allocator.free(tags_out);

    return .{
        .id = id,
        .title = try allocator.dupe(u8, title),
        .command = try allocator.dupe(u8, command),
        .tags = final_tags,
    };
}

fn parseDesktopBool(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn extractDesktopExecCommand(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, " \t\r");
    if (trimmed.len == 0) return null;

    if (trimmed[0] == '"') {
        const end_quote = std.mem.indexOfScalarPos(u8, trimmed, 1, '"') orelse return null;
        if (end_quote <= 1) return null;
        return trimmed[1..end_quote];
    }

    const first_space = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
    const command = trimmed[0..first_space];
    if (command.len == 0) return null;
    return command;
}

fn desktopTagsFromField(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var last_was_space = false;
    for (value) |ch| {
        const mapped = if (ch == ';' or ch == ',') ' ' else ch;
        if (std.ascii.isWhitespace(mapped)) {
            if (!last_was_space and out.items.len > 0) {
                try out.append(' ');
                last_was_space = true;
            }
            continue;
        }
        try out.append(std.ascii.toLower(mapped));
        last_was_space = false;
    }

    if (out.items.len == 0) {
        try out.appendSlice("desktop");
    }
    return try out.toOwnedSlice();
}

fn slugFromText(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var last_dash = false;
    for (value) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try out.append(std.ascii.toLower(ch));
            last_dash = false;
            continue;
        }

        if (ch == ' ' or ch == '-' or ch == '_' or ch == '.') {
            if (!last_dash and out.items.len > 0) {
                try out.append('-');
                last_dash = true;
            }
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice("desktop-app");
    }
    return try out.toOwnedSlice();
}

fn desktopIdFromPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const base = std.fs.path.basename(path);
    const stem = if (std.mem.endsWith(u8, base, ".desktop") and base.len > ".desktop".len)
        base[0 .. base.len - ".desktop".len]
    else
        base;

    return slugFromText(allocator, stem);
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

    if (aliasMatch(entry.tags, query)) score += 1400;

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

fn aliasMatch(tags: []const u8, query: []const u8) bool {
    const q = std.mem.trim(u8, query, " \t\r\n");
    if (q.len == 0) return false;

    var tok = std.mem.tokenizeAny(u8, tags, " \t");
    while (tok.next()) |part| {
        if (!std.mem.startsWith(u8, part, "alias:")) continue;
        const alias = std.mem.trim(u8, part[6..], " \t\r");
        if (alias.len == 0) continue;
        if (equalsIgnoreCase(alias, q)) return true;
    }
    return false;
}

fn quickMathEval(expr_raw: []const u8) ?f64 {
    const expr = std.mem.trim(u8, expr_raw, " \t\r\n");
    if (expr.len == 0) return null;
    if (!std.ascii.isDigit(expr[0])) return null;

    var idx: usize = 0;
    var total: f64 = 0;
    var term = parseNumber(expr, &idx) orelse return null;
    var pending_add: u8 = '+';

    while (idx < expr.len) {
        skipSpaces(expr, &idx);
        if (idx >= expr.len) break;
        const op = expr[idx];
        if (op != '+' and op != '-' and op != '*' and op != '/') return null;
        idx += 1;

        var rhs = parseNumber(expr, &idx) orelse return null;
        if (op == '*') {
            term *= rhs;
            continue;
        }
        if (op == '/') {
            if (rhs == 0) return null;
            term /= rhs;
            continue;
        }

        if (pending_add == '+') total += term else total -= term;
        pending_add = op;
        term = rhs;
    }

    if (pending_add == '+') total += term else total -= term;
    return total;
}

fn skipSpaces(text: []const u8, idx: *usize) void {
    while (idx.* < text.len and std.ascii.isWhitespace(text[idx.*])) : (idx.* += 1) {}
}

fn parseNumber(text: []const u8, idx: *usize) ?f64 {
    skipSpaces(text, idx);
    if (idx.* >= text.len) return null;

    const start = idx.*;
    var seen_digit = false;
    var seen_dot = false;

    while (idx.* < text.len) : (idx.* += 1) {
        const ch = text[idx.*];
        if (std.ascii.isDigit(ch)) {
            seen_digit = true;
            continue;
        }
        if (ch == '.') {
            if (seen_dot) break;
            seen_dot = true;
            continue;
        }
        break;
    }

    if (!seen_digit) return null;
    return std.fmt.parseFloat(f64, text[start..idx.*]) catch null;
}

fn shellEscapeSingleQuotes(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice("'\\''");
        } else {
            try out.append(ch);
        }
    }

    return try out.toOwnedSlice();
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

fn printOutputState(allocator: std.mem.Allocator, watcher: *ui.OutputWatcher, profile: core.DesktopProfile) void {
    var theme_profile = core.loadThemeProfile(allocator, profile) catch return;
    defer theme_profile.deinit(allocator);
    const theme_tokens: ui.ThemeTokens = .{
        .corner_radius = theme_profile.corner_radius,
        .spacing_unit = theme_profile.spacing_unit,
        .blur_sigma = theme_profile.blur_sigma,
    };
    const decor_theme = ui.SurfaceDecorationTheme.fromThemeTokens(theme_tokens);

    std.debug.print("Detected outputs: {d}\n", .{watcher.outputs.items.len});
    for (watcher.outputs.items) |output| {
        const surface = ui.fullscreenSurfaceThemed(.launcher, output, decor_theme);
        ui.printSurfaceSummary(surface, theme_tokens);
        ui.printRenderSpec(ui.renderSpecForSurface(surface));
    }
}
