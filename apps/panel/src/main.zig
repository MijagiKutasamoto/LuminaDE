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
    var icon_resolver = core.IconResolver.init(allocator);
    defer icon_resolver.deinit();
    var texture_cache = ui.TextureCache.init(allocator);
    defer texture_cache.deinit();
    var launch_guards = std.StringHashMap(PanelLaunchGuard).init(allocator);
    defer {
        var it = launch_guards.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        launch_guards.deinit();
    }

    std.debug.print("[watcher] backend={s}\n", .{watcher.backendName()});
    printOutputState(allocator, &watcher, cfg.profile);

    if (daemon_mode) {
        std.debug.print("Panel GUI mode started (GUI-first daemon).\n", .{});
        while (true) {
            const event = try watcher.waitForEvent(5000);
            if (event and try watcher.poll()) {
                std.debug.print("[watcher] monitor topology changed, refreshing panel surfaces\n", .{});
                printOutputState(allocator, &watcher, cfg.profile);
            }
            try renderPanel(cfg, allocator, &native_runtime, &icon_resolver, &texture_cache);
            _ = try processPanelPointerInputQueue(allocator, cfg.profile, &launch_guards);
            _ = try processPanelGuiEventQueue(allocator, cfg.profile, &launch_guards);
        }
    }

    try renderPanel(cfg, allocator, &native_runtime, &icon_resolver, &texture_cache);
}

fn renderPanel(
    cfg: core.RuntimeConfig,
    allocator: std.mem.Allocator,
    native_runtime: *ui.NativePanelRuntime,
    icon_resolver: *core.IconResolver,
    texture_cache: *ui.TextureCache,
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

    var theme_profile = try core.loadThemeProfile(allocator, cfg.profile);
    defer theme_profile.deinit(allocator);
    const theme_tokens: ui.ThemeTokens = .{
        .corner_radius = theme_profile.corner_radius,
        .spacing_unit = theme_profile.spacing_unit,
        .blur_sigma = theme_profile.blur_sigma,
    };
    const decor_theme = ui.SurfaceDecorationTheme.fromThemeTokens(theme_tokens);

    for (outputs.items) |output| {
        try renderPanelGui(allocator, cfg, output, active_ws, behavior, native_runtime, icon_resolver, texture_cache, decor_theme);
    }
}

fn parseActiveWorkspace() u8 {
    const env_value = std.posix.getenv("LUMINADE_ACTIVE_WS") orelse return 1;
    return std.fmt.parseUnsigned(u8, env_value, 10) catch 1;
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
        const surface = ui.fullscreenSurfaceThemed(.panel, output, decor_theme);
        ui.printSurfaceSummary(surface, theme_tokens);
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
    icon_resolver: *core.IconResolver,
    texture_cache: *ui.TextureCache,
    decor_theme: ui.SurfaceDecorationTheme,
) !void {
    const surface = ui.fullscreenSurfaceThemed(.panel, output, decor_theme);
    var frame = ui.GuiFrame.init(allocator, "Panel", surface);
    defer frame.deinit();

    const panel_h_i = @as(i32, @intCast(cfg.profile.panel_height));
    const pill_y = @max(@as(i32, 4), @divTrunc(panel_h_i - 32, 2));
    const surface_w_i = @as(i32, @intCast(surface.width));

    try ui.addWidget(&frame, .{
        .id = "panel-root",
        .kind = .row,
        .label = "panel-root",
        .rect = .{ .x = 0, .y = 0, .w = surface.width, .h = cfg.profile.panel_height },
        .interactive = false,
        .hoverable = false,
    });

    const mode_mouse = try localeText(allocator, cfg.lang, "panel.mode.mouse_first", "mouse-first");
    defer allocator.free(mode_mouse);
    const mode_balanced = try localeText(allocator, cfg.lang, "panel.mode.balanced", "balanced");
    defer allocator.free(mode_balanced);
    const mode_keyboard = try localeText(allocator, cfg.lang, "panel.mode.keyboard_first", "keyboard-first");
    defer allocator.free(mode_keyboard);
    const mode_label = switch (cfg.profile.interaction_mode) {
        .mouse_first => mode_mouse,
        .balanced => mode_balanced,
        .keyboard_first => mode_keyboard,
    };

    const ws_active_label = try localeText(allocator, cfg.lang, "panel.workspace.active", "ws-active");
    defer allocator.free(ws_active_label);
    const ws_idle_label = try localeText(allocator, cfg.lang, "panel.workspace.idle", "ws");
    defer allocator.free(ws_idle_label);

    const app_terminal_text = try localeText(allocator, cfg.lang, "panel.app.terminal", "Terminal");
    defer allocator.free(app_terminal_text);
    const app_browser_text = try localeText(allocator, cfg.lang, "panel.app.browser", "Browser");
    defer allocator.free(app_browser_text);
    const app_files_text = try localeText(allocator, cfg.lang, "panel.app.files", "Files");
    defer allocator.free(app_files_text);
    const clock_text = try localeText(allocator, cfg.lang, "panel.clock", "clock");
    defer allocator.free(clock_text);
    const mode_pill_w: u16 = 178;
    try ui.addWidget(&frame, .{
        .id = "mode-pill",
        .kind = .badge,
        .label = mode_label,
        .rect = .{ .x = @divTrunc(surface_w_i - @as(i32, @intCast(mode_pill_w)), 2), .y = pill_y, .w = mode_pill_w, .h = 32 },
        .interactive = false,
        .hoverable = false,
    });

    var x: i32 = 12;
    var ws: u8 = 1;
    while (ws <= 4) : (ws += 1) {
        const label = if (ws == active_ws) ws_active_label else ws_idle_label;
        const ws_id = try std.fmt.allocPrint(allocator, "ws-{d}@{s}", .{ ws, output.name });
        defer allocator.free(ws_id);
        try ui.addWidget(&frame, .{
            .id = ws_id,
            .kind = .badge,
            .label = label,
            .rect = .{ .x = x, .y = @max(@as(i32, 4), @divTrunc(panel_h_i - (@as(i32, behavior.pointer_target_px) - 2), 2)), .w = behavior.pointer_target_px, .h = @max(cfg.profile.panel_height - 10, 18) },
            .interactive = true,
            .hoverable = true,
        });
        x += @as(i32, behavior.pointer_target_px) + 8;
    }

    const app_size = @max(cfg.profile.panel_height - 10, @as(u16, 18));
    const app_terminal_id = try std.fmt.allocPrint(allocator, "app-terminal@{s}", .{output.name});
    defer allocator.free(app_terminal_id);
    const app_browser_id = try std.fmt.allocPrint(allocator, "app-browser@{s}", .{output.name});
    defer allocator.free(app_browser_id);
    const app_files_id = try std.fmt.allocPrint(allocator, "app-files@{s}", .{output.name});
    defer allocator.free(app_files_id);
    const sys_net_id = try std.fmt.allocPrint(allocator, "sys-net@{s}", .{output.name});
    defer allocator.free(sys_net_id);
    const sys_audio_id = try std.fmt.allocPrint(allocator, "sys-audio@{s}", .{output.name});
    defer allocator.free(sys_audio_id);
    const sys_power_id = try std.fmt.allocPrint(allocator, "sys-power@{s}", .{output.name});
    defer allocator.free(sys_power_id);
    const net_label = try panelNetworkStatusLabel(allocator, cfg.lang);
    defer allocator.free(net_label);
    const vol_label = try panelAudioStatusLabel(allocator, cfg.lang);
    defer allocator.free(vol_label);
    const bat_label = try panelBatteryStatusLabel(allocator, cfg.lang);
    defer allocator.free(bat_label);

    const terminal_button_label = try ui.composeIconLabel(allocator, "luminade-terminal", app_terminal_text);
    defer allocator.free(terminal_button_label);
    const browser_button_label = try ui.composeIconLabel(allocator, "luminade-browser", app_browser_text);
    defer allocator.free(browser_button_label);
    const files_button_label = try ui.composeIconLabel(allocator, "luminade-files", app_files_text);
    defer allocator.free(files_button_label);

    const net_button_label = try ui.composeIconLabel(allocator, "network-wireless-symbolic", net_label);
    defer allocator.free(net_button_label);
    const audio_button_label = try ui.composeIconLabel(allocator, "audio-volume-high-symbolic", vol_label);
    defer allocator.free(audio_button_label);
    const power_button_label = try ui.composeIconLabel(allocator, "system-shutdown-symbolic", bat_label);
    defer allocator.free(power_button_label);

    try ui.addWidget(&frame, .{
        .id = app_terminal_id,
        .kind = .button,
        .label = terminal_button_label,
        .rect = .{ .x = x + 18, .y = @max(@as(i32, 4), @divTrunc(panel_h_i - @as(i32, @intCast(app_size)), 2)), .w = app_size + 28, .h = app_size },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = app_browser_id,
        .kind = .button,
        .label = browser_button_label,
        .rect = .{ .x = x + 58 + @as(i32, @intCast(app_size)), .y = @max(@as(i32, 4), @divTrunc(panel_h_i - @as(i32, @intCast(app_size)), 2)), .w = app_size + 28, .h = app_size },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = app_files_id,
        .kind = .button,
        .label = files_button_label,
        .rect = .{ .x = x + 98 + 2 * @as(i32, @intCast(app_size)), .y = @max(@as(i32, 4), @divTrunc(panel_h_i - @as(i32, @intCast(app_size)), 2)), .w = app_size + 28, .h = app_size },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "clock",
        .kind = .text,
        .label = clock_text,
        .rect = .{ .x = surface_w_i - 234, .y = @max(@as(i32, 4), @divTrunc(panel_h_i - 24, 2)), .w = 222, .h = 24 },
        .interactive = false,
        .hoverable = false,
    });

    const sys_w: u16 = 68;
    const sys_h: u16 = 28;
    const sys_gap: i32 = 8;
    const sys_start_x = (surface_w_i - 234) - (3 * @as(i32, @intCast(sys_w)) + 2 * sys_gap) - 14;
    const sys_y = @max(@as(i32, 4), @divTrunc(panel_h_i - @as(i32, @intCast(sys_h)), 2));

    try ui.addWidget(&frame, .{
        .id = sys_net_id,
        .kind = .button,
        .label = net_button_label,
        .rect = .{ .x = sys_start_x, .y = sys_y, .w = sys_w, .h = sys_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = sys_audio_id,
        .kind = .button,
        .label = audio_button_label,
        .rect = .{ .x = sys_start_x + @as(i32, @intCast(sys_w)) + sys_gap, .y = sys_y, .w = sys_w, .h = sys_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = sys_power_id,
        .kind = .button,
        .label = power_button_label,
        .rect = .{ .x = sys_start_x + 2 * (@as(i32, @intCast(sys_w)) + sys_gap), .y = sys_y, .w = sys_w, .h = sys_h },
        .interactive = true,
        .hoverable = true,
    });

    // Pre-resolve icon assets so renderer can reuse cached texture handles.
    primePanelTextures(allocator, &frame, icon_resolver, texture_cache) catch |err| {
        std.debug.print("[panel] texture prime failed output={s} err={s}\n", .{ output.name, @errorName(err) });
    };

    const native = try ui.initNativePanelSession(allocator, output, cfg.profile.panel_height);
    try ui.commitNativePanelFrame(allocator, native_runtime, native, &frame);

    writePanelHitMapForOutput(allocator, output.name, &frame) catch |err| {
        std.debug.print("[panel] hitmap write failed output={s} err={s}\n", .{ output.name, @errorName(err) });
    };

    ui.printGuiFrame(&frame);
}

fn panelGuiEventsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_PANEL_GUI_EVENTS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/gui-panel-events.tsv");
}

fn panelInputEventsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_UI_INPUT_EVENTS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/ui-events.tsv");
}

fn processPanelPointerInputQueue(
    allocator: std.mem.Allocator,
    profile: core.DesktopProfile,
    launch_guards: *std.StringHashMap(PanelLaunchGuard),
) !bool {
    const path = try panelInputEventsPath(allocator);
    defer allocator.free(path);

    var events = try ui.loadUiEventsFromTsv(allocator, path, 512);
    defer events.deinit();
    if (events.items.len == 0) return false;

    var changed = false;

    for (events.items) |event| {
        switch (event) {
            .pointer_motion => {},
            .pointer_button => |button| {
                if (!button.pressed) continue;
                const target = try resolvePanelHitTarget(allocator, button.x, button.y) orelse continue;
                defer allocator.free(target.widget_id);
                defer allocator.free(target.output_key);

                if (button.button == .left) {
                    if (try handlePanelClick(allocator, profile, launch_guards, target.widget_id, target.output_key)) {
                        changed = true;
                    }
                    continue;
                }

                if (button.button == .right) {
                    const menu_action = defaultContextActionForWidget(target.widget_id) orelse continue;
                    if (try handlePanelContext(allocator, target.widget_id, menu_action)) {
                        changed = true;
                    }
                }
            },
            .pointer_scroll => |scroll| {
                const target = try resolvePanelHitTarget(allocator, scroll.x, scroll.y) orelse continue;
                defer allocator.free(target.widget_id);
                defer allocator.free(target.output_key);

                if (scroll.delta_y == 0) continue;
                const direction: []const u8 = if (scroll.delta_y < 0) "up" else "down";
                if (try handlePanelScroll(allocator, target.widget_id, target.output_key, direction)) {
                    changed = true;
                }
            },
        }
    }

    var truncate = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer truncate.close();
    try truncate.writer().writeAll(
        "# kind\t...\n# motion\t120\t22\n# button\tleft\tpress\t120\t22\n# scroll\t0\t-1\t120\t22\n",
    );

    return changed;
}

fn processPanelGuiEventQueue(
    allocator: std.mem.Allocator,
    profile: core.DesktopProfile,
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
            if (try handlePanelClick(allocator, profile, launch_guards, widget_id, output_key)) {
                changed = true;
            }
            continue;
        }

        if (std.mem.eql(u8, action, "context") and tokens.items.len >= 3) {
            if (try handlePanelContext(allocator, widget_id, tokens.items[2])) {
                changed = true;
            }
            continue;
        }

        if (std.mem.eql(u8, action, "scroll") and tokens.items.len >= 3) {
            if (try handlePanelScroll(allocator, widget_id, output_key, tokens.items[2])) {
                changed = true;
            }
        }
    }

    var truncate = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer truncate.close();
    try truncate.writer().writeAll(
        "# action\twidget-id\t[menu-action]\n# click\tapp-terminal@eDP-1\n# click\tws-2@eDP-1\n# click\tsys-audio@eDP-1\n# click\tsys-power@eDP-1\n# context\tapp-terminal@eDP-1\tfavorite-add\n",
    );

    return changed;
}

fn handlePanelClick(
    allocator: std.mem.Allocator,
    profile: core.DesktopProfile,
    launch_guards: *std.StringHashMap(PanelLaunchGuard),
    widget_id: []const u8,
    output_key: []const u8,
) !bool {
    if (parseWorkspaceFromWidget(widget_id)) |workspace| {
        const switched = try switchWorkspaceForOutput(allocator, output_key, workspace);
        if (switched) {
            const payload = try std.fmt.allocPrint(allocator, "{s}\t{d}", .{ output_key, workspace });
            defer allocator.free(payload);
            queueSessiondPub("workspace", "focus", payload) catch {};
        }
        std.debug.print(
            "[panel] workspace click={s}@{s} switched={any}\n",
            .{ widget_id, output_key, switched },
        );
        return switched;
    }

    const now_ns = std.time.nanoTimestamp();
    if (!(try allowLaunchForOutput(allocator, launch_guards, output_key, now_ns))) {
        std.debug.print("[panel] launch throttled widget={s}@{s}\n", .{ widget_id, output_key });
        return false;
    }

    if (try runPanelSystemAction(allocator, widget_id)) {
        std.debug.print("[panel] system action={s}@{s} ok\n", .{ widget_id, output_key });
        return true;
    }

    const map = mapPanelWidget(widget_id, profile) orelse return false;

    try launchCommandDetached(allocator, map.command);
    try incrementHistory(allocator, map.entry_id);
    std.debug.print("[panel] launched id={s} cmd={s}\n", .{ map.entry_id, map.command });
    return true;
}

fn handlePanelContext(allocator: std.mem.Allocator, widget_id: []const u8, menu_action: []const u8) !bool {
    if (std.mem.eql(u8, widget_id, "sys-power")) {
        if (std.mem.eql(u8, menu_action, "power-save")) {
            const ok = runShellQuick(allocator, "powerprofilesctl set power-saver");
            if (ok) queueSessiondPub("power", "profile", "power-saver") catch {};
            return ok;
        }
        if (std.mem.eql(u8, menu_action, "performance")) {
            const ok = runShellQuick(allocator, "powerprofilesctl set performance");
            if (ok) queueSessiondPub("power", "profile", "performance") catch {};
            return ok;
        }
        if (std.mem.eql(u8, menu_action, "balanced")) {
            const ok = runShellQuick(allocator, "powerprofilesctl set balanced");
            if (ok) queueSessiondPub("power", "profile", "balanced") catch {};
            return ok;
        }
    }

    if (std.mem.eql(u8, widget_id, "clock")) {
        if (std.mem.eql(u8, menu_action, "open-calendar") or std.mem.eql(u8, menu_action, "calendar-popup")) {
            return runShellDetachedQuick(
                allocator,
                "if command -v gnome-calendar >/dev/null 2>&1; then gnome-calendar; " ++
                    "elif command -v korganizer >/dev/null 2>&1; then korganizer; " ++
                    "elif command -v xdg-open >/dev/null 2>&1; then xdg-open calendar:; fi",
            );
        }
    }

    const profile = core.DesktopProfile.load(allocator) catch core.DesktopProfile.fromEnv();
    const map = mapPanelWidget(widget_id, profile) orelse return false;

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

fn handlePanelScroll(
    allocator: std.mem.Allocator,
    widget_id: []const u8,
    output_key: []const u8,
    direction_raw: []const u8,
) !bool {
    const dir = parseScrollDirection(direction_raw) orelse return false;

    if (std.mem.eql(u8, widget_id, "sys-audio")) {
        const cmd = if (dir > 0)
            "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
        else
            "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-";
        const ok = runShellQuick(allocator, cmd);
        if (ok) queueSessiondPub("audio", "change", if (dir > 0) "up" else "down") catch {};
        return ok;
    }

    if (parseWorkspaceFromWidget(widget_id)) |current_ws| {
        var next_ws = @as(i16, current_ws) + @as(i16, dir);
        next_ws = @max(@as(i16, 1), @min(@as(i16, 32), next_ws));
        const switched = try switchWorkspaceForOutput(allocator, output_key, @as(u8, @intCast(next_ws)));
        if (switched) {
            const payload = try std.fmt.allocPrint(allocator, "{s}\t{d}", .{ output_key, next_ws });
            defer allocator.free(payload);
            queueSessiondPub("workspace", "scroll", payload) catch {};
        }
        return switched;
    }

    return false;
}

fn parseScrollDirection(direction_raw: []const u8) ?i8 {
    const d = std.mem.trim(u8, direction_raw, " \t\r");
    if (std.mem.eql(u8, d, "up") or std.mem.eql(u8, d, "+") or std.mem.eql(u8, d, "1")) return 1;
    if (std.mem.eql(u8, d, "down") or std.mem.eql(u8, d, "-") or std.mem.eql(u8, d, "-1")) return -1;

    const n = std.fmt.parseInt(i8, d, 10) catch return null;
    if (n == 0) return null;
    return if (n > 0) 1 else -1;
}

fn runShellQuick(allocator: std.mem.Allocator, command: []const u8) bool {
    var child = std.process.Child.init(&.{ "sh", "-lc", command }, allocator);
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

fn runShellDetachedQuick(allocator: std.mem.Allocator, command: []const u8) bool {
    const shell_cmd = std.fmt.allocPrint(allocator, "{s} >/dev/null 2>&1 &", .{command}) catch return false;
    defer allocator.free(shell_cmd);

    var child = std.process.Child.init(&.{ "sh", "-lc", shell_cmd }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return false;
    _ = child.wait() catch return false;
    return true;
}

fn queueSessiondPub(topic: []const u8, event_name: []const u8, payload: []const u8) !void {
    const path = std.posix.getenv("LUMINADE_SESSIOND_COMMANDS") orelse ".luminade/sessiond-commands.tsv";
    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(path, .{ .truncate = false }),
        else => return err,
    };
    defer file.close();

    const clean_payload = std.mem.replaceOwned(u8, std.heap.page_allocator, payload, "\n", " ") catch payload;
    defer if (clean_payload.ptr != payload.ptr) std.heap.page_allocator.free(clean_payload);

    try file.seekFromEnd(0);
    try file.writer().print("PUB\t{s}\t{s}\t{s}\n", .{ topic, event_name, clean_payload });
}

const PanelAppMap = struct {
    entry_id: []const u8,
    command: []const u8,
};

fn mapPanelWidget(widget_id: []const u8, profile: core.DesktopProfile) ?PanelAppMap {
    if (std.mem.eql(u8, widget_id, "app-terminal")) return .{ .entry_id = "terminal", .command = profile.terminalCommand() };
    if (std.mem.eql(u8, widget_id, "app-browser")) return .{ .entry_id = "browser", .command = profile.browserCommand() };
    if (std.mem.eql(u8, widget_id, "app-files")) return .{ .entry_id = "files", .command = profile.filesCommand() };
    return null;
}

const PanelWidgetTarget = struct {
    base_id: []const u8,
    output_name: ?[]const u8,
};

const PanelHitTarget = struct {
    widget_id: []u8,
    output_key: []u8,
};

fn splitWidgetTarget(widget_id: []const u8) PanelWidgetTarget {
    const at_idx = std.mem.indexOfScalar(u8, widget_id, '@') orelse {
        return .{ .base_id = widget_id, .output_name = null };
    };

    const base = std.mem.trim(u8, widget_id[0..at_idx], " \t\r");
    const out = std.mem.trim(u8, widget_id[at_idx + 1 ..], " \t\r");
    return .{ .base_id = base, .output_name = if (out.len == 0) null else out };
}

fn writePanelHitMapForOutput(allocator: std.mem.Allocator, output_name: []const u8, frame: *const ui.GuiFrame) !void {
    const path = try panelHitMapPathForOutput(allocator, output_name);
    defer allocator.free(path);

    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var out = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer out.close();
    try out.writer().writeAll("# widget-id\toutput\tx\ty\tw\th\tinteractive\n");

    for (frame.widgets.items) |widget| {
        try out.writer().print(
            "{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{s}\n",
            .{ widget.id, output_name, widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, if (widget.interactive) "1" else "0" },
        );
    }
}

fn panelHitMapPathForOutput(allocator: std.mem.Allocator, output_name: []const u8) ![]u8 {
    const safe = try sanitizePathSegment(allocator, output_name);
    defer allocator.free(safe);
    return try std.fmt.allocPrint(allocator, ".luminade/panel-hitmap-{s}.tsv", .{safe});
}

fn resolvePanelHitTarget(allocator: std.mem.Allocator, x: i32, y: i32) !?PanelHitTarget {
    var dir = std.fs.cwd().openDir(".luminade", .{ .iterate = true }) catch return null;
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "panel-hitmap-")) continue;
        if (!std.mem.endsWith(u8, entry.name, ".tsv")) continue;

        var file = dir.openFile(entry.name, .{}) catch continue;
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 256 * 1024);
        defer allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            var cols = std.mem.splitScalar(u8, line, '\t');
            const widget_id = std.mem.trim(u8, cols.next() orelse continue, " \t\r");
            const output = std.mem.trim(u8, cols.next() orelse continue, " \t\r");
            const rx = std.fmt.parseInt(i32, std.mem.trim(u8, cols.next() orelse continue, " \t\r"), 10) catch continue;
            const ry = std.fmt.parseInt(i32, std.mem.trim(u8, cols.next() orelse continue, " \t\r"), 10) catch continue;
            const rw = std.fmt.parseUnsigned(u16, std.mem.trim(u8, cols.next() orelse continue, " \t\r"), 10) catch continue;
            const rh = std.fmt.parseUnsigned(u16, std.mem.trim(u8, cols.next() orelse continue, " \t\r"), 10) catch continue;
            const interactive = std.mem.eql(u8, std.mem.trim(u8, cols.next() orelse continue, " \t\r"), "1");
            if (!interactive) continue;
            if (!pointInRect(x, y, rx, ry, rw, rh)) continue;

            const target = splitWidgetTarget(widget_id);
            return .{
                .widget_id = try allocator.dupe(u8, target.base_id),
                .output_key = try allocator.dupe(u8, target.output_name orelse output),
            };
        }
    }

    return null;
}

fn pointInRect(px: i32, py: i32, rx: i32, ry: i32, rw: u16, rh: u16) bool {
    const max_x = rx + @as(i32, @intCast(rw));
    const max_y = ry + @as(i32, @intCast(rh));
    return px >= rx and py >= ry and px < max_x and py < max_y;
}

fn defaultContextActionForWidget(widget_id: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, widget_id, "clock")) return "open-calendar";
    if (std.mem.eql(u8, widget_id, "sys-power")) return "balanced";
    if (std.mem.eql(u8, widget_id, "app-terminal")) return "favorite-add";
    if (std.mem.eql(u8, widget_id, "app-browser")) return "favorite-add";
    if (std.mem.eql(u8, widget_id, "app-files")) return "favorite-add";
    return null;
}

fn sanitizePathSegment(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len == 0) return try allocator.dupe(u8, "unknown");

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    for (raw) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.') {
            try out.append(ch);
        } else {
            try out.append('_');
        }
    }

    return try out.toOwnedSlice();
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

fn runPanelSystemAction(allocator: std.mem.Allocator, widget_id: []const u8) !bool {
    if (std.mem.eql(u8, widget_id, "sys-audio")) {
        return try core.runSystemAction(allocator, .audio_mute_toggle);
    }

    if (std.mem.eql(u8, widget_id, "sys-power")) {
        return try core.runSystemAction(allocator, .lock_session);
    }

    if (std.mem.eql(u8, widget_id, "sys-net")) {
        return try core.runSystemAction(allocator, .open_network);
    }

    return false;
}

fn panelNetworkStatusLabel(allocator: std.mem.Allocator, lang: core.Lang) ![]u8 {
    const up = try localeText(allocator, lang, "panel.status.net.up", "Net:up");
    defer allocator.free(up);
    const down = try localeText(allocator, lang, "panel.status.net.down", "Net:down");
    defer allocator.free(down);
    const na = try localeText(allocator, lang, "panel.status.net.na", "Net:na");
    defer allocator.free(na);

    const state = try runCommandCaptureTrimmed(allocator, &.{ "sh", "-lc", "nmcli -t -f STATE general 2>/dev/null" });
    defer if (state) |s| allocator.free(s);

    if (state) |s| {
        if (std.mem.indexOf(u8, s, "connected") != null) return try allocator.dupe(u8, up);
        if (std.mem.indexOf(u8, s, "disconnected") != null) return try allocator.dupe(u8, down);
    }

    const fallback = try runCommandCaptureTrimmed(allocator, &.{ "sh", "-lc", "cat /sys/class/net/wlan0/operstate 2>/dev/null || cat /sys/class/net/eth0/operstate 2>/dev/null" });
    defer if (fallback) |s| allocator.free(s);
    if (fallback) |s| {
        if (std.mem.indexOf(u8, s, "up") != null) return try allocator.dupe(u8, up);
        if (std.mem.indexOf(u8, s, "down") != null) return try allocator.dupe(u8, down);
    }

    return try allocator.dupe(u8, na);
}

fn panelAudioStatusLabel(allocator: std.mem.Allocator, lang: core.Lang) ![]u8 {
    const vol_prefix = try localeText(allocator, lang, "panel.status.vol.prefix", "Vol");
    defer allocator.free(vol_prefix);
    const muted = try localeText(allocator, lang, "panel.status.vol.muted", "Vol:muted");
    defer allocator.free(muted);
    const na = try localeText(allocator, lang, "panel.status.vol.na", "Vol:na");
    defer allocator.free(na);

    const line = try runCommandCaptureTrimmed(allocator, &.{ "sh", "-lc", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null" });
    defer if (line) |s| allocator.free(s);

    if (line) |s| {
        if (std.mem.indexOf(u8, s, "MUTED") != null) return try allocator.dupe(u8, muted);

        var tok = std.mem.tokenizeAny(u8, s, " \t");
        while (tok.next()) |part| {
            const v = std.fmt.parseFloat(f32, part) catch continue;
            const pct: i32 = @as(i32, @intFromFloat(v * 100.0));
            const clamped = @max(@as(i32, 0), @min(@as(i32, 150), pct));
            return try std.fmt.allocPrint(allocator, "{s}:{d}%", .{ vol_prefix, clamped });
        }
    }

    return try allocator.dupe(u8, na);
}

fn panelBatteryStatusLabel(allocator: std.mem.Allocator, lang: core.Lang) ![]u8 {
    const bat_prefix = try localeText(allocator, lang, "panel.status.bat.prefix", "Bat");
    defer allocator.free(bat_prefix);
    const na = try localeText(allocator, lang, "panel.status.bat.na", "Bat:na");
    defer allocator.free(na);

    const cap = try runCommandCaptureTrimmed(allocator, &.{ "sh", "-lc", "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || cat /sys/class/power_supply/BAT1/capacity 2>/dev/null" });
    defer if (cap) |s| allocator.free(s);

    if (cap) |c| {
        const status = try runCommandCaptureTrimmed(allocator, &.{ "sh", "-lc", "cat /sys/class/power_supply/BAT0/status 2>/dev/null || cat /sys/class/power_supply/BAT1/status 2>/dev/null" });
        defer if (status) |s| allocator.free(s);

        if (status) |s| {
            if (std.mem.startsWith(u8, s, "Charging")) return try std.fmt.allocPrint(allocator, "{s}:+{s}%", .{ bat_prefix, c });
            if (std.mem.startsWith(u8, s, "Discharging")) return try std.fmt.allocPrint(allocator, "{s}:{s}%", .{ bat_prefix, c });
        }
        return try std.fmt.allocPrint(allocator, "{s}:{s}%", .{ bat_prefix, c });
    }

    return try allocator.dupe(u8, na);
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

fn runCommandCaptureTrimmed(allocator: std.mem.Allocator, argv: []const []const u8) !?[]u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 32 * 1024,
    }) catch return null;
    defer allocator.free(result.stderr);

    const ok = switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        allocator.free(result.stdout);
        return null;
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) {
        allocator.free(result.stdout);
        return null;
    }

    const duped = try allocator.dupe(u8, trimmed);
    allocator.free(result.stdout);
    return duped;
}

fn primePanelTextures(
    allocator: std.mem.Allocator,
    frame: *const ui.GuiFrame,
    icon_resolver: *core.IconResolver,
    texture_cache: *ui.TextureCache,
) !void {
    for (frame.widgets.items) |widget| {
        const icon_label = ui.parseIconLabel(widget.label);
        const icon_name = icon_label.icon_name orelse continue;

        const variant: core.IconVariant = if (std.mem.endsWith(u8, icon_name, "-symbolic")) .symbolic else .colored;
        const icon_path = try icon_resolver.resolve(icon_name, variant) orelse continue;
        defer allocator.free(icon_path);

        _ = try texture_cache.getOrLoad(icon_path, frame.surface.scale);
    }
}
