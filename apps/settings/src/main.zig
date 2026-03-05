const std = @import("std");
const core = @import("luminade_core");
const ui = @import("luminade_ui");

const SettingsTextKey = enum {
    settings_title,
    section_layout,
    section_display,
    section_input,
    section_defaults,
    section_device_profiles,
    section_live_preview,
    section_system,
    section_appearance,
    section_shortcuts,
    label_window_mode,
    label_tiling,
    label_display_scale,
    label_display_layout,
    label_pointer_sensitivity,
    label_natural_scroll,
    label_default_terminal,
    label_default_browser,
    label_default_files,
    label_theme_mode,
    label_theme_profile,
    label_shortcut_launcher,
    label_shortcut_terminal,
    label_shortcut_browser,
    label_shortcut_files,
    label_shortcut_settings,
    label_device_matcher,
    label_save_device_profile,
    label_apply_input,
    label_system_lock,
    label_system_suspend,
    label_system_logout,
    label_system_network,
    label_audio_up,
    label_audio_down,
    label_audio_mute,
    word_on,
    word_off,
    preview_main,
    preview_docs,
    preview_overlay,
};

fn trKey(key: SettingsTextKey) []const u8 {
    return switch (key) {
        .settings_title => "settings.title",
        .section_layout => "settings.section.layout",
        .section_display => "settings.section.display",
        .section_input => "settings.section.input",
        .section_defaults => "settings.section.defaults",
        .section_device_profiles => "settings.section.device_profiles",
        .section_live_preview => "settings.section.live_preview",
        .section_system => "settings.section.system",
        .section_appearance => "settings.section.appearance",
        .section_shortcuts => "settings.section.shortcuts",
        .label_window_mode => "settings.label.window_mode",
        .label_tiling => "settings.label.tiling",
        .label_display_scale => "settings.label.display_scale",
        .label_display_layout => "settings.label.display_layout",
        .label_pointer_sensitivity => "settings.label.pointer_sensitivity",
        .label_natural_scroll => "settings.label.natural_scroll",
        .label_default_terminal => "settings.label.default_terminal",
        .label_default_browser => "settings.label.default_browser",
        .label_default_files => "settings.label.default_files",
        .label_theme_mode => "settings.label.theme_mode",
        .label_theme_profile => "settings.label.theme_profile",
        .label_shortcut_launcher => "settings.label.shortcut_launcher",
        .label_shortcut_terminal => "settings.label.shortcut_terminal",
        .label_shortcut_browser => "settings.label.shortcut_browser",
        .label_shortcut_files => "settings.label.shortcut_files",
        .label_shortcut_settings => "settings.label.shortcut_settings",
        .label_device_matcher => "settings.label.device_matcher",
        .label_save_device_profile => "settings.label.save_device_profile",
        .label_apply_input => "settings.label.apply_input",
        .label_system_lock => "settings.label.system_lock",
        .label_system_suspend => "settings.label.system_suspend",
        .label_system_logout => "settings.label.system_logout",
        .label_system_network => "settings.label.system_network",
        .label_audio_up => "settings.label.audio_up",
        .label_audio_down => "settings.label.audio_down",
        .label_audio_mute => "settings.label.audio_mute",
        .word_on => "settings.word.on",
        .word_off => "settings.word.off",
        .preview_main => "settings.preview.main",
        .preview_docs => "settings.preview.docs",
        .preview_overlay => "settings.preview.overlay",
    };
}

fn tr(allocator: std.mem.Allocator, lang: core.Lang, key: SettingsTextKey) ![]u8 {
    return core.localeGetWithEnFallback(allocator, lang, trKey(key));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var cfg = core.RuntimeConfig.init(allocator);
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    core.printBanner(.settings, cfg);
    core.printModernSummary(.settings, cfg);

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

    std.debug.print("Detected outputs: {d}\n", .{outputs.items.len});
    for (outputs.items) |output| {
        const surface = ui.fullscreenSurfaceThemed(.settings, output, decor_theme);
        ui.printSurfaceSummary(surface, theme_tokens);
        ui.printRenderSpec(ui.renderSpecForSurface(surface));
        try renderSettingsGui(allocator, surface, cfg.profile, cfg.lang);
    }

    if (args.len <= 1) {
        try runSettingsGuiMode(allocator, &cfg, &outputs);
        return;
    }

    if (std.mem.eql(u8, args[1], "show")) {
        printProfile(cfg.profile, cfg.lang);
        return;
    }

    if (std.mem.eql(u8, args[1], "reset")) {
        cfg.profile = core.DesktopProfile.modernDefault();
        cfg.profile.applyEnvOverrides();
        try cfg.profile.save(allocator);
        std.debug.print("Profile reset to modern defaults.\n", .{});
        printProfile(cfg.profile, cfg.lang);
        return;
    }

    if (std.mem.eql(u8, args[1], "set")) {
        if (args.len < 4) {
            printUsage(cfg.lang);
            return;
        }

        const key = args[2];
        const value = args[3];

        cfg.profile.setField(key, value) catch |err| {
            std.debug.print("Cannot set field '{s}': {s}\n", .{ key, @errorName(err) });
            printUsage(cfg.lang);
            return;
        };

        try cfg.profile.save(allocator);
        std.debug.print("Saved {s}={s}\n", .{ key, value });
        printProfile(cfg.profile, cfg.lang);
        return;
    }

    if (std.mem.eql(u8, args[1], "gui-action")) {
        if (args.len < 3) {
            printUsage(cfg.lang);
            return;
        }

        const handled = try applyGuiAction(allocator, &cfg, args[2..]);
        if (!handled) {
            std.debug.print("Unknown gui action.\n", .{});
            printUsage(cfg.lang);
            return;
        }

        try cfg.profile.save(allocator);
        std.debug.print("GUI action applied and profile saved.\n", .{});
        printProfile(cfg.profile, cfg.lang);
        return;
    }

    if (std.mem.eql(u8, args[1], "gui-click")) {
        if (args.len < 3) {
            printUsage(cfg.lang);
            return;
        }

        const handled = try dispatchGuiWidgetClick(allocator, &cfg, args[2], args[3..]);
        if (!handled) {
            std.debug.print("Unknown widget action for '{s}'.\n", .{args[2]});
            printUsage(cfg.lang);
            return;
        }

        try cfg.profile.save(allocator);
        std.debug.print("GUI click action applied and profile saved.\n", .{});
        printProfile(cfg.profile, cfg.lang);
        return;
    }

    if (std.mem.eql(u8, args[1], "set-device")) {
        if (args.len < 5) {
            printUsage(cfg.lang);
            return;
        }

        try setDeviceProfileEntry(allocator, args[2], args[3], args[4]);
        std.debug.print("Saved device profile matcher='{s}' {s}={s}\n", .{ args[2], args[3], args[4] });
        return;
    }

    if (std.mem.eql(u8, args[1], "list-device-profiles")) {
        try listDeviceProfiles(allocator);
        return;
    }

    if (std.mem.eql(u8, args[1], "clear-device-profiles")) {
        try clearDeviceProfiles(allocator);
        std.debug.print("Device profiles cleared.\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "launcher-favorite")) {
        try handleLauncherFavoriteCommand(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, args[1], "export")) {
        try cfg.profile.save(allocator);
        const path = try core.profilePath(allocator);
        defer allocator.free(path);
        std.debug.print("Profile exported to: {s}\n", .{path});
        return;
    }

    if (std.mem.eql(u8, args[1], "layout-demo")) {
        try runLayoutDemo(allocator, cfg.profile, &outputs);
        return;
    }

    if (std.mem.eql(u8, args[1], "apply-input")) {
        var dry_run = false;
        if (args.len >= 3 and std.mem.eql(u8, args[2], "--dry-run")) {
            dry_run = true;
        }

        const report = try core.applyInputProfile(allocator, cfg.profile, dry_run);
        std.debug.print(
            "Input apply backend={s} devices={d} applied={d} skipped={d}\n",
            .{ report.backend, report.device_count, report.applied_count, report.skipped_count },
        );
        if (std.mem.eql(u8, report.backend, "noop")) {
            std.debug.print("Brak riverctl/libinput w tym środowisku; backend runtime pozostaje symulowany.\n", .{});
        }
        return;
    }

    printUsage(cfg.lang);
}

fn runSettingsGuiMode(
    allocator: std.mem.Allocator,
    cfg: *core.RuntimeConfig,
    outputs: *std.ArrayList(ui.OutputProfile),
) !void {
    std.debug.print("Settings GUI mode started (GUI-first, no CLI required).\n", .{});
    while (true) {
        var theme_profile_loop = try core.loadThemeProfile(allocator, cfg.profile);
        defer theme_profile_loop.deinit(allocator);
        const theme_tokens_loop: ui.ThemeTokens = .{
            .corner_radius = theme_profile_loop.corner_radius,
            .spacing_unit = theme_profile_loop.spacing_unit,
            .blur_sigma = theme_profile_loop.blur_sigma,
        };
        const decor_theme_loop = ui.SurfaceDecorationTheme.fromThemeTokens(theme_tokens_loop);

        for (outputs.items) |output| {
            const surface = ui.fullscreenSurfaceThemed(.settings, output, decor_theme_loop);
            try renderSettingsGui(allocator, surface, cfg.profile, cfg.lang);
        }

        const changed = try processSettingsGuiEventQueue(allocator, cfg);
        if (changed) {
            try cfg.profile.save(allocator);
            std.debug.print("Settings GUI event applied and saved.\n", .{});
            printProfile(cfg.profile, cfg.lang);
        }

        std.time.sleep(500 * std.time.ns_per_ms);
    }
}

fn processSettingsGuiEventQueue(allocator: std.mem.Allocator, cfg: *core.RuntimeConfig) !bool {
    const path = try settingsGuiEventsPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 256 * 1024);
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
        if (tokens.items.len == 0) continue;

        const widget = tokens.items[0];
        const args = if (tokens.items.len > 1) tokens.items[1..] else &.{};
        if (try dispatchGuiWidgetClick(allocator, cfg, widget, args)) {
            changed = true;
        }
    }

    var truncate = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer truncate.close();
        try truncate.writer().writeAll("# widget-id\t[arg1]\t[arg2]\n# window-mode\n# display-layout\n# display-scale-minus\n# display-scale-plus\n# natural-scroll\n# apply-input\t--dry-run\n# system-lock\n# system-network\n# audio-volume-up\n");

    return changed;
}

fn settingsGuiEventsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_SETTINGS_GUI_EVENTS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/gui-settings-events.tsv");
}

fn renderSettingsGui(
    allocator: std.mem.Allocator,
    surface: ui.SurfaceSpec,
    profile: core.DesktopProfile,
    lang: core.Lang,
) !void {
    const settings_title = try tr(allocator, lang, .settings_title);
    defer allocator.free(settings_title);

    var frame = ui.GuiFrame.init(allocator, settings_title, surface);
    defer frame.deinit();

    const window_mode_text = try tr(allocator, lang, .label_window_mode);
    defer allocator.free(window_mode_text);
    const tiling_text = try tr(allocator, lang, .label_tiling);
    defer allocator.free(tiling_text);
    const display_scale_text = try tr(allocator, lang, .label_display_scale);
    defer allocator.free(display_scale_text);
    const display_layout_text = try tr(allocator, lang, .label_display_layout);
    defer allocator.free(display_layout_text);
    const pointer_text = try tr(allocator, lang, .label_pointer_sensitivity);
    defer allocator.free(pointer_text);
    const natural_text = try tr(allocator, lang, .label_natural_scroll);
    defer allocator.free(natural_text);
    const default_terminal_text = try tr(allocator, lang, .label_default_terminal);
    defer allocator.free(default_terminal_text);
    const default_browser_text = try tr(allocator, lang, .label_default_browser);
    defer allocator.free(default_browser_text);
    const default_files_text = try tr(allocator, lang, .label_default_files);
    defer allocator.free(default_files_text);
    const theme_mode_text = try tr(allocator, lang, .label_theme_mode);
    defer allocator.free(theme_mode_text);
    const theme_profile_text = try tr(allocator, lang, .label_theme_profile);
    defer allocator.free(theme_profile_text);
    const shortcut_launcher_text = try tr(allocator, lang, .label_shortcut_launcher);
    defer allocator.free(shortcut_launcher_text);
    const shortcut_terminal_text = try tr(allocator, lang, .label_shortcut_terminal);
    defer allocator.free(shortcut_terminal_text);
    const shortcut_browser_text = try tr(allocator, lang, .label_shortcut_browser);
    defer allocator.free(shortcut_browser_text);
    const shortcut_files_text = try tr(allocator, lang, .label_shortcut_files);
    defer allocator.free(shortcut_files_text);
    const shortcut_settings_text = try tr(allocator, lang, .label_shortcut_settings);
    defer allocator.free(shortcut_settings_text);
    const word_on = try tr(allocator, lang, .word_on);
    defer allocator.free(word_on);
    const word_off = try tr(allocator, lang, .word_off);
    defer allocator.free(word_off);
    const device_matcher_label = try tr(allocator, lang, .label_device_matcher);
    defer allocator.free(device_matcher_label);

    const window_mode_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ window_mode_text, @tagName(profile.window_mode) });
    defer allocator.free(window_mode_label);
    const tiling_label = try std.fmt.allocPrint(allocator, "{s}: {s} ({d}%)", .{ tiling_text, @tagName(profile.tiling_algorithm), profile.master_ratio_percent });
    defer allocator.free(tiling_label);
    const display_scale_label = try std.fmt.allocPrint(allocator, "{s}: {d}%", .{ display_scale_text, profile.display_scale_percent });
    defer allocator.free(display_scale_label);
    const display_layout_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ display_layout_text, @tagName(profile.display_layout_mode) });
    defer allocator.free(display_layout_label);
    const pointer_label = try std.fmt.allocPrint(allocator, "{s}: {d}", .{ pointer_text, profile.pointer_sensitivity });
    defer allocator.free(pointer_label);
    const natural_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ natural_text, if (profile.natural_scroll) word_on else word_off });
    defer allocator.free(natural_label);
    const default_terminal_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ default_terminal_text, @tagName(profile.default_terminal_app) });
    defer allocator.free(default_terminal_label);
    const default_browser_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ default_browser_text, @tagName(profile.default_browser_app) });
    defer allocator.free(default_browser_label);
    const default_files_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ default_files_text, @tagName(profile.default_files_app) });
    defer allocator.free(default_files_label);
    const theme_mode_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ theme_mode_text, @tagName(profile.theme_mode) });
    defer allocator.free(theme_mode_label);
    const theme_profile_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ theme_profile_text, @tagName(profile.theme_profile) });
    defer allocator.free(theme_profile_label);
    const system_lock_text = try tr(allocator, lang, .label_system_lock);
    defer allocator.free(system_lock_text);
    const system_suspend_text = try tr(allocator, lang, .label_system_suspend);
    defer allocator.free(system_suspend_text);
    const system_logout_text = try tr(allocator, lang, .label_system_logout);
    defer allocator.free(system_logout_text);
    const system_network_text = try tr(allocator, lang, .label_system_network);
    defer allocator.free(system_network_text);
    const audio_up_text = try tr(allocator, lang, .label_audio_up);
    defer allocator.free(audio_up_text);
    const audio_down_text = try tr(allocator, lang, .label_audio_down);
    defer allocator.free(audio_down_text);
    const audio_mute_text = try tr(allocator, lang, .label_audio_mute);
    defer allocator.free(audio_mute_text);

    const system_lock_label = try ui.composeIconLabel(allocator, "system-lock-screen-symbolic", system_lock_text);
    defer allocator.free(system_lock_label);
    const system_suspend_label = try ui.composeIconLabel(allocator, "system-suspend-symbolic", system_suspend_text);
    defer allocator.free(system_suspend_label);
    const system_logout_label = try ui.composeIconLabel(allocator, "system-log-out-symbolic", system_logout_text);
    defer allocator.free(system_logout_label);
    const system_network_label = try ui.composeIconLabel(allocator, "network-wireless-symbolic", system_network_text);
    defer allocator.free(system_network_label);
    const audio_up_label = try ui.composeIconLabel(allocator, "audio-volume-high-symbolic", audio_up_text);
    defer allocator.free(audio_up_label);
    const audio_down_label = try ui.composeIconLabel(allocator, "audio-volume-medium-symbolic", audio_down_text);
    defer allocator.free(audio_down_label);
    const audio_mute_label = try ui.composeIconLabel(allocator, "audio-volume-muted-symbolic", audio_mute_text);
    defer allocator.free(audio_mute_label);

    const section_layout_label = try tr(allocator, lang, .section_layout);
    defer allocator.free(section_layout_label);
    const section_input_label = try tr(allocator, lang, .section_input);
    defer allocator.free(section_input_label);
    const section_defaults_label = try tr(allocator, lang, .section_defaults);
    defer allocator.free(section_defaults_label);
    const section_display_label = try tr(allocator, lang, .section_display);
    defer allocator.free(section_display_label);
    const section_device_profiles_label = try tr(allocator, lang, .section_device_profiles);
    defer allocator.free(section_device_profiles_label);
    const save_device_profile_label = try tr(allocator, lang, .label_save_device_profile);
    defer allocator.free(save_device_profile_label);
    const apply_input_label = try tr(allocator, lang, .label_apply_input);
    defer allocator.free(apply_input_label);
    const section_live_preview_label = try tr(allocator, lang, .section_live_preview);
    defer allocator.free(section_live_preview_label);
    const section_system_label = try tr(allocator, lang, .section_system);
    defer allocator.free(section_system_label);
    const section_appearance_label = try tr(allocator, lang, .section_appearance);
    defer allocator.free(section_appearance_label);
    const section_shortcuts_label = try tr(allocator, lang, .section_shortcuts);
    defer allocator.free(section_shortcuts_label);

    var shortcuts = try core.loadShortcuts(allocator);
    defer core.freeShortcuts(allocator, &shortcuts);

    const shortcut_launcher_label = try std.fmt.allocPrint(
        allocator,
        "{s}: {s}",
        .{ shortcut_launcher_text, core.shortcutBinding(shortcuts.items, .launcher_toggle) },
    );
    defer allocator.free(shortcut_launcher_label);
    const shortcut_terminal_label = try std.fmt.allocPrint(
        allocator,
        "{s}: {s}",
        .{ shortcut_terminal_text, core.shortcutBinding(shortcuts.items, .terminal_open) },
    );
    defer allocator.free(shortcut_terminal_label);
    const shortcut_browser_label = try std.fmt.allocPrint(
        allocator,
        "{s}: {s}",
        .{ shortcut_browser_text, core.shortcutBinding(shortcuts.items, .browser_open) },
    );
    defer allocator.free(shortcut_browser_label);
    const shortcut_files_label = try std.fmt.allocPrint(
        allocator,
        "{s}: {s}",
        .{ shortcut_files_text, core.shortcutBinding(shortcuts.items, .files_open) },
    );
    defer allocator.free(shortcut_files_label);
    const shortcut_settings_label = try std.fmt.allocPrint(
        allocator,
        "{s}: {s}",
        .{ shortcut_settings_text, core.shortcutBinding(shortcuts.items, .settings_open) },
    );
    defer allocator.free(shortcut_settings_label);

    // Settings uses a responsive two-column geometry so controls keep consistent rhythm across resolutions.
    const outer: i32 = 36;
    const col_gap: i32 = 26;
    const section_h: u16 = 30;
    const control_h: u16 = 46;
    const section_to_controls: i32 = 36;
    const row_gap: i32 = 12;
    const block_gap: i32 = 30;

    const surface_w = @as(i32, @intCast(surface.width));
    const content_w = @max(@as(i32, 340), surface_w - 2 * outer);
    const right_col_w = @max(@as(i32, 240), @min(@as(i32, 340), @divTrunc(content_w, 3)));
    const left_col_w = @max(@as(i32, 240), content_w - right_col_w - col_gap);
    const left_half_w = @max(@as(i32, 160), @divTrunc(left_col_w - 14, 2));
    const left_x: i32 = outer;
    const right_x: i32 = left_x + left_col_w + col_gap;
    const top_y: i32 = 74;

    try ui.addWidget(&frame, .{
        .id = "settings-root",
        .kind = .column,
        .label = "settings-root",
        .rect = .{
            .x = outer - 8,
            .y = 56,
            .w = @as(u16, @intCast(@max(@as(i32, 240), content_w + 16))),
            .h = @max(surface.height - 80, 160),
        },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "settings-look-chip",
        .kind = .badge,
        .label = "Aurora Glass",
        .rect = .{ .x = left_x, .y = 40, .w = 150, .h = 24 },
        .interactive = false,
        .hoverable = false,
    });

    const left_card_h = @max(@as(i32, 420), @as(i32, @intCast(surface.height)) - top_y - 44);
    const right_card_h = @max(@as(i32, 360), @as(i32, @intCast(surface.height)) - top_y - 44);

    try ui.addWidget(&frame, .{
        .id = "settings-card-left",
        .kind = .row,
        .label = "card-left",
        .rect = .{
            .x = left_x - 10,
            .y = top_y - 14,
            .w = @as(u16, @intCast(left_col_w + 20)),
            .h = @as(u16, @intCast(left_card_h)),
        },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "settings-card-right",
        .kind = .row,
        .label = "card-right",
        .rect = .{
            .x = right_x - 10,
            .y = top_y - 14,
            .w = @as(u16, @intCast(right_col_w + 20)),
            .h = @as(u16, @intCast(right_card_h)),
        },
        .interactive = false,
        .hoverable = false,
    });

    const section_layout_y = top_y;
    const section_display_y = section_layout_y + section_to_controls + @as(i32, @intCast(control_h)) + block_gap;
    const section_input_y = section_display_y + section_to_controls + @as(i32, @intCast(control_h)) + block_gap;
    const section_defaults_y = section_input_y + section_to_controls + @as(i32, @intCast(control_h)) + block_gap;
    const section_device_y = section_defaults_y + section_to_controls + @as(i32, @intCast(control_h)) + block_gap;
    const section_live_y = section_device_y + section_to_controls + @as(i32, @intCast(control_h)) + block_gap;

    const layout_row_y = section_layout_y + section_to_controls;
    const display_row_y = section_display_y + section_to_controls;
    const input_row_y = section_input_y + section_to_controls;
    const defaults_row_y = section_defaults_y + section_to_controls;
    const device_row_y = section_device_y + section_to_controls;

    try ui.addWidget(&frame, .{
        .id = "section-layout",
        .kind = .text,
        .label = section_layout_label,
        .rect = .{ .x = left_x, .y = section_layout_y, .w = @as(u16, @intCast(left_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "section-display",
        .kind = .text,
        .label = section_display_label,
        .rect = .{ .x = left_x, .y = section_display_y, .w = @as(u16, @intCast(left_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "section-input",
        .kind = .text,
        .label = section_input_label,
        .rect = .{ .x = left_x, .y = section_input_y, .w = @as(u16, @intCast(left_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "section-defaults",
        .kind = .text,
        .label = section_defaults_label,
        .rect = .{ .x = left_x, .y = section_defaults_y, .w = @as(u16, @intCast(left_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "section-device-profiles",
        .kind = .text,
        .label = section_device_profiles_label,
        .rect = .{ .x = left_x, .y = section_device_y, .w = @as(u16, @intCast(left_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "window-mode",
        .kind = .button,
        .label = window_mode_label,
        .rect = .{ .x = left_x, .y = layout_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "tiling-algorithm",
        .kind = .button,
        .label = tiling_label,
        .rect = .{ .x = left_x + left_half_w + 14, .y = layout_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "display-scale-minus",
        .kind = .button,
        .label = "-",
        .rect = .{ .x = left_x, .y = display_row_y, .w = 48, .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "display-scale",
        .kind = .button,
        .label = display_scale_label,
        .rect = .{ .x = left_x + 56, .y = display_row_y, .w = @as(u16, @intCast(left_half_w - 56)), .h = control_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "display-scale-plus",
        .kind = .button,
        .label = "+",
        .rect = .{ .x = left_x + left_half_w - 48, .y = display_row_y, .w = 48, .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "display-layout",
        .kind = .button,
        .label = display_layout_label,
        .rect = .{ .x = left_x + left_half_w + 14, .y = display_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "pointer-sensitivity",
        .kind = .input,
        .label = pointer_label,
        .rect = .{ .x = left_x, .y = input_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "natural-scroll",
        .kind = .toggle,
        .label = natural_label,
        .rect = .{ .x = left_x + left_half_w + 14, .y = input_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "default-terminal",
        .kind = .button,
        .label = default_terminal_label,
        .rect = .{ .x = left_x, .y = defaults_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "default-browser",
        .kind = .button,
        .label = default_browser_label,
        .rect = .{ .x = left_x + left_half_w + 14, .y = defaults_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "default-files",
        .kind = .button,
        .label = default_files_label,
        .rect = .{ .x = left_x, .y = defaults_row_y + @as(i32, @intCast(control_h)) + row_gap, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "device-matcher",
        .kind = .input,
        .label = device_matcher_label,
        .rect = .{ .x = left_x, .y = device_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "save-device-profile",
        .kind = .button,
        .label = save_device_profile_label,
        .rect = .{ .x = left_x + left_half_w + 14, .y = device_row_y, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "apply-input",
        .kind = .button,
        .label = apply_input_label,
        .rect = .{ .x = left_x, .y = device_row_y + @as(i32, @intCast(control_h)) + row_gap, .w = @as(u16, @intCast(left_half_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "section-live-preview",
        .kind = .text,
        .label = section_live_preview_label,
        .rect = .{ .x = left_x, .y = section_live_y, .w = @as(u16, @intCast(left_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "section-system",
        .kind = .text,
        .label = section_system_label,
        .rect = .{ .x = right_x, .y = top_y, .w = @as(u16, @intCast(right_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });

    const system_row_1 = top_y + section_to_controls;
    const system_row_2 = system_row_1 + @as(i32, @intCast(control_h)) + row_gap;
    const system_row_3 = system_row_2 + @as(i32, @intCast(control_h)) + row_gap;
    const system_row_4 = system_row_3 + @as(i32, @intCast(control_h)) + row_gap;
    const system_row_5 = system_row_4 + @as(i32, @intCast(control_h)) + row_gap;
    const system_row_6 = system_row_5 + @as(i32, @intCast(control_h)) + row_gap;
    const system_row_7 = system_row_6 + @as(i32, @intCast(control_h)) + row_gap;
    const appearance_section_y = system_row_7 + @as(i32, @intCast(control_h)) + block_gap;
    const appearance_row_1 = appearance_section_y + section_to_controls;
    const appearance_row_2 = appearance_row_1 + @as(i32, @intCast(control_h)) + row_gap;
    const shortcuts_section_y = appearance_row_2 + @as(i32, @intCast(control_h)) + block_gap;
    const shortcuts_row_1 = shortcuts_section_y + section_to_controls;
    const shortcuts_row_2 = shortcuts_row_1 + @as(i32, @intCast(control_h)) + row_gap;
    const shortcuts_row_3 = shortcuts_row_2 + @as(i32, @intCast(control_h)) + row_gap;
    const shortcuts_row_4 = shortcuts_row_3 + @as(i32, @intCast(control_h)) + row_gap;
    const shortcuts_row_5 = shortcuts_row_4 + @as(i32, @intCast(control_h)) + row_gap;

    try ui.addWidget(&frame, .{
        .id = "system-lock",
        .kind = .button,
        .label = system_lock_label,
        .rect = .{ .x = right_x, .y = system_row_1, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "system-suspend",
        .kind = .button,
        .label = system_suspend_label,
        .rect = .{ .x = right_x, .y = system_row_2, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "system-logout",
        .kind = .button,
        .label = system_logout_label,
        .rect = .{ .x = right_x, .y = system_row_3, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "audio-volume-up",
        .kind = .button,
        .label = audio_up_label,
        .rect = .{ .x = right_x, .y = system_row_4, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "audio-volume-down",
        .kind = .button,
        .label = audio_down_label,
        .rect = .{ .x = right_x, .y = system_row_5, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "audio-mute",
        .kind = .button,
        .label = audio_mute_label,
        .rect = .{ .x = right_x, .y = system_row_6, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "system-network",
        .kind = .button,
        .label = system_network_label,
        .rect = .{ .x = right_x, .y = system_row_7, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "section-appearance",
        .kind = .text,
        .label = section_appearance_label,
        .rect = .{ .x = right_x, .y = appearance_section_y, .w = @as(u16, @intCast(right_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "theme-mode",
        .kind = .button,
        .label = theme_mode_label,
        .rect = .{ .x = right_x, .y = appearance_row_1, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "theme-profile",
        .kind = .button,
        .label = theme_profile_label,
        .rect = .{ .x = right_x, .y = appearance_row_2, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "section-shortcuts",
        .kind = .text,
        .label = section_shortcuts_label,
        .rect = .{ .x = right_x, .y = shortcuts_section_y, .w = @as(u16, @intCast(right_col_w)), .h = section_h },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "shortcut-launcher",
        .kind = .button,
        .label = shortcut_launcher_label,
        .rect = .{ .x = right_x, .y = shortcuts_row_1, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "shortcut-terminal",
        .kind = .button,
        .label = shortcut_terminal_label,
        .rect = .{ .x = right_x, .y = shortcuts_row_2, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "shortcut-browser",
        .kind = .button,
        .label = shortcut_browser_label,
        .rect = .{ .x = right_x, .y = shortcuts_row_3, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "shortcut-files",
        .kind = .button,
        .label = shortcut_files_label,
        .rect = .{ .x = right_x, .y = shortcuts_row_4, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "shortcut-settings",
        .kind = .button,
        .label = shortcut_settings_label,
        .rect = .{ .x = right_x, .y = shortcuts_row_5, .w = @as(u16, @intCast(right_col_w)), .h = control_h },
        .interactive = true,
        .hoverable = true,
    });

    try addLayoutPreviewWidgets(
        allocator,
        &frame,
        surface,
        profile,
        lang,
        left_x,
        section_live_y + section_to_controls,
        @as(u16, @intCast(left_col_w)),
    );

    ui.printGuiFrame(&frame);
}

fn addLayoutPreviewWidgets(
    allocator: std.mem.Allocator,
    frame: *ui.GuiFrame,
    surface: ui.SurfaceSpec,
    profile: core.DesktopProfile,
    lang: core.Lang,
    origin_x: i32,
    origin_y: i32,
    max_width: u16,
) !void {
    const preview_main_label = try tr(allocator, lang, .preview_main);
    defer allocator.free(preview_main_label);
    const preview_docs_label = try tr(allocator, lang, .preview_docs);
    defer allocator.free(preview_docs_label);
    const preview_overlay_label = try tr(allocator, lang, .preview_overlay);
    defer allocator.free(preview_overlay_label);

    const remaining_w = @as(i32, @intCast(surface.width)) - origin_x - 36;
    const remaining_h = @as(i32, @intCast(surface.height)) - origin_y - 40;
    if (remaining_w < 120 or remaining_h < 80) return;

    const preview: ui.Rect = .{
        .x = origin_x,
        .y = origin_y,
        .w = @min(max_width, @as(u16, @intCast(remaining_w))),
        .h = @min(@as(u16, 260), @as(u16, @intCast(remaining_h))),
    };

    if (preview.w < 120 or preview.h < 80) return;

    try ui.addWidget(frame, .{
        .id = "preview-canvas",
        .kind = .row,
        .label = "preview-canvas",
        .rect = preview,
        .interactive = false,
        .hoverable = false,
    });

    var windows = std.ArrayList(ui.WindowState).init(allocator);
    defer windows.deinit();

    try windows.append(.{
        .id = "preview-main",
        .role = .panel,
        .rect = .{ .x = 0, .y = 0, .w = 900, .h = 700 },
        .desired_w = 900,
        .desired_h = 700,
        .is_focused = true,
        .is_minimized = false,
        .is_floating = false,
        .z_index = 0,
    });
    try windows.append(.{
        .id = "preview-docs",
        .role = .panel,
        .rect = .{ .x = 0, .y = 0, .w = 900, .h = 700 },
        .desired_w = 900,
        .desired_h = 700,
        .is_focused = false,
        .is_minimized = false,
        .is_floating = false,
        .z_index = 0,
    });
    try windows.append(.{
        .id = "preview-launcher",
        .role = .launcher,
        .rect = .{ .x = 0, .y = 0, .w = 760, .h = 520 },
        .desired_w = 760,
        .desired_h = 520,
        .is_focused = false,
        .is_minimized = false,
        .is_floating = true,
        .z_index = 0,
    });

    const mode: ui.LayoutMode = switch (profile.window_mode) {
        .tiling => .tiling,
        .floating => .floating,
        .hybrid => .hybrid,
    };
    const algo: ui.LayoutAlgorithm = switch (profile.tiling_algorithm) {
        .master_stack => .master_stack,
        .grid => .grid,
    };

    const sim_output: ui.OutputProfile = .{
        .name = "preview",
        .width = 1920,
        .height = 1080,
        .scale = 1.0,
        .primary = true,
    };

    const layout_cfg: ui.LayoutConfig = .{
        .spacing = profile.layout_gap,
        .outer_gap = profile.layout_gap,
        .master_ratio_percent = profile.master_ratio_percent,
        .algorithm = algo,
        .float_overlays_in_hybrid = profile.float_overlays_in_hybrid,
    };
    try ui.applyWindowLayout(allocator, mode, sim_output, windows.items, layout_cfg);

    const sx_num = @as(i32, @intCast(preview.w));
    const sx_den: i32 = 1920;
    const sy_num = @as(i32, @intCast(preview.h));
    const sy_den: i32 = 1080;

    for (windows.items, 0..) |window, idx| {
        const px = preview.x + @divTrunc(window.rect.x * sx_num, sx_den);
        const py = preview.y + @divTrunc(window.rect.y * sy_num, sy_den);
        const pw_i = @max(@as(i32, 16), @divTrunc(@as(i32, @intCast(window.rect.w)) * sx_num, sx_den));
        const ph_i = @max(@as(i32, 12), @divTrunc(@as(i32, @intCast(window.rect.h)) * sy_num, sy_den));

        const widget_id = switch (idx) {
            0 => "preview-box-main",
            1 => "preview-box-docs",
            else => "preview-box-overlay",
        };
        const label = switch (idx) {
            0 => preview_main_label,
            1 => preview_docs_label,
            else => preview_overlay_label,
        };

        try ui.addWidget(frame, .{
            .id = widget_id,
            .kind = .badge,
            .label = label,
            .rect = .{
                .x = px,
                .y = py,
                .w = @as(u16, @intCast(pw_i)),
                .h = @as(u16, @intCast(ph_i)),
            },
            .interactive = false,
            .hoverable = false,
        });
    }
}

fn printProfile(profile: core.DesktopProfile, lang: core.Lang) void {
    std.debug.print("{s}\n", .{if (lang == .pl) "Aktualny profil" else "Current profile"});
    std.debug.print("- theme={s}\n", .{@tagName(profile.theme_mode)});
    std.debug.print("- theme_profile={s}\n", .{@tagName(profile.theme_profile)});
    std.debug.print("- density={s}\n", .{@tagName(profile.density)});
    std.debug.print("- motion={s}\n", .{@tagName(profile.motion)});
    std.debug.print("- panel_height={d}\n", .{profile.panel_height});
    std.debug.print("- corner_radius={d}\n", .{profile.corner_radius});
    std.debug.print("- blur_sigma={d}\n", .{profile.blur_sigma});
    std.debug.print("- launcher_width={d}\n", .{profile.launcher_width});
    std.debug.print("- display_scale_percent={d}\n", .{profile.display_scale_percent});
    std.debug.print("- display_layout_mode={s}\n", .{@tagName(profile.display_layout_mode)});
    std.debug.print("- default_terminal_app={s}\n", .{@tagName(profile.default_terminal_app)});
    std.debug.print("- default_browser_app={s}\n", .{@tagName(profile.default_browser_app)});
    std.debug.print("- default_files_app={s}\n", .{@tagName(profile.default_files_app)});
    std.debug.print("- workspace_gaps={d}\n", .{profile.workspace_gaps});
    std.debug.print("- smart_hide_panel={any}\n", .{profile.smart_hide_panel});
    std.debug.print("- window_mode={s}\n", .{@tagName(profile.window_mode)});
    std.debug.print("- interaction_mode={s}\n", .{@tagName(profile.interaction_mode)});
    std.debug.print("- pointer_sensitivity={d}\n", .{profile.pointer_sensitivity});
    std.debug.print("- pointer_accel_profile={s}\n", .{@tagName(profile.pointer_accel_profile)});
    std.debug.print("- natural_scroll={any}\n", .{profile.natural_scroll});
    std.debug.print("- tap_to_click={any}\n", .{profile.tap_to_click});
    std.debug.print("- tiling_algorithm={s}\n", .{@tagName(profile.tiling_algorithm)});
    std.debug.print("- master_ratio_percent={d}\n", .{profile.master_ratio_percent});
    std.debug.print("- layout_gap={d}\n", .{profile.layout_gap});
    std.debug.print("- float_overlays_in_hybrid={any}\n", .{profile.float_overlays_in_hybrid});
}

fn printUsage(lang: core.Lang) void {
    std.debug.print("{s}:\n", .{if (lang == .pl) "Użycie" else "Usage"});
    std.debug.print("  luminade-settings show\n", .{});
    std.debug.print("  luminade-settings set <key> <value>\n", .{});
    std.debug.print("  luminade-settings gui-action <action> [value]\n", .{});
    std.debug.print("  luminade-settings gui-click <widget-id> [args...]\n", .{});
    std.debug.print("  luminade-settings set-device <matcher> <key> <value>\n", .{});
    std.debug.print("  luminade-settings list-device-profiles\n", .{});
    std.debug.print("  luminade-settings clear-device-profiles\n", .{});
    std.debug.print("  luminade-settings launcher-favorite <list|add|remove|clear> [entry-id]\n", .{});
    std.debug.print("  luminade-settings reset\n", .{});
    std.debug.print("  luminade-settings export\n", .{});
    std.debug.print("  luminade-settings layout-demo\n", .{});
    std.debug.print("  luminade-settings apply-input\n", .{});
    std.debug.print("  luminade-settings apply-input --dry-run\n", .{});
    std.debug.print("\nKeys (new):\n", .{});
    std.debug.print("  window_mode = tiling | floating | hybrid\n", .{});
    std.debug.print("  theme_profile = aurora_glass | graphite | solaris_light\n", .{});
    std.debug.print("  display_scale_percent = 50..200\n", .{});
    std.debug.print("  display_layout_mode = single | extended | mirrored\n", .{});
    std.debug.print("  default_terminal_app = foot | alacritty | kitty\n", .{});
    std.debug.print("  default_browser_app = firefox | chromium | brave\n", .{});
    std.debug.print("  default_files_app = thunar | nautilus | dolphin\n", .{});
    std.debug.print("  interaction_mode = keyboard_first | balanced | mouse_first\n", .{});
    std.debug.print("  pointer_sensitivity = -100..100\n", .{});
    std.debug.print("  pointer_accel_profile = adaptive | flat\n", .{});
    std.debug.print("  natural_scroll = true | false\n", .{});
    std.debug.print("  tap_to_click = true | false\n", .{});
    std.debug.print("  tiling_algorithm = master_stack | grid\n", .{});
    std.debug.print("  master_ratio_percent = 20..80\n", .{});
    std.debug.print("  layout_gap = 0..255\n", .{});
    std.debug.print("  float_overlays_in_hybrid = true | false\n", .{});

    std.debug.print("\nDevice profile keys:\n", .{});
    std.debug.print("  pointer_sensitivity | pointer_accel_profile | natural_scroll | tap_to_click\n", .{});

    std.debug.print("\nGUI actions:\n", .{});
    std.debug.print("  toggle-natural-scroll\n", .{});
    std.debug.print("  toggle-tap-to-click\n", .{});
    std.debug.print("  cycle-window-mode\n", .{});
    std.debug.print("  cycle-display-layout\n", .{});
    std.debug.print("  adjust-display-scale <delta>\n", .{});
    std.debug.print("  cycle-tiling-algorithm\n", .{});
    std.debug.print("  cycle-default-terminal\n", .{});
    std.debug.print("  cycle-default-browser\n", .{});
    std.debug.print("  cycle-default-files\n", .{});
    std.debug.print("  cycle-theme-mode\n", .{});
    std.debug.print("  cycle-theme-profile\n", .{});
    std.debug.print("  set-pointer-sensitivity <value>\n", .{});
    std.debug.print("  set-master-ratio <20..80>\n", .{});
    std.debug.print("  set-layout-gap <0..255>\n", .{});
    std.debug.print("  system-lock\n", .{});
    std.debug.print("  system-suspend\n", .{});
    std.debug.print("  system-logout\n", .{});
    std.debug.print("  audio-volume-up\n", .{});
    std.debug.print("  audio-volume-down\n", .{});
    std.debug.print("  audio-mute\n", .{});

    std.debug.print("\nGUI widget click examples:\n", .{});
    std.debug.print("  gui-click window-mode\n", .{});
    std.debug.print("  gui-click tiling-algorithm\n", .{});
    std.debug.print("  gui-click display-layout\n", .{});
    std.debug.print("  gui-click display-scale-minus\n", .{});
    std.debug.print("  gui-click display-scale-plus\n", .{});
    std.debug.print("  gui-click natural-scroll\n", .{});
    std.debug.print("  gui-click default-terminal\n", .{});
    std.debug.print("  gui-click default-browser\n", .{});
    std.debug.print("  gui-click default-files\n", .{});
    std.debug.print("  gui-click theme-mode\n", .{});
    std.debug.print("  gui-click theme-profile\n", .{});
    std.debug.print("  gui-click shortcut-launcher\n", .{});
    std.debug.print("  gui-click pointer-sensitivity 25\n", .{});
    std.debug.print("  gui-click save-device-profile touchpad natural_scroll true\n", .{});
    std.debug.print("  gui-click apply-input [--dry-run]\n", .{});
    std.debug.print("  gui-click system-lock\n", .{});
    std.debug.print("  gui-click audio-volume-up\n", .{});
}

fn launcherFavoritesPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LAUNCHER_FAVORITES")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/launcher-favorites.tsv");
}

fn loadLauncherFavorites(allocator: std.mem.Allocator, favorites: *std.StringHashMap(void)) !void {
    const path = try launcherFavoritesPath(allocator);
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

fn saveLauncherFavorites(allocator: std.mem.Allocator, favorites: *std.StringHashMap(void)) !void {
    const path = try launcherFavoritesPath(allocator);
    defer allocator.free(path);

    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var out = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer out.close();

    const writer = out.writer();
    try writer.writeAll("# launcher favorites (entry ids)\n");
    var it = favorites.keyIterator();
    while (it.next()) |key_ptr| {
        try writer.print("{s}\n", .{key_ptr.*});
    }
}

fn handleLauncherFavoriteCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printLauncherFavoriteUsage();
        return;
    }

    var favorites = std.StringHashMap(void).init(allocator);
    defer {
        var it = favorites.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        favorites.deinit();
    }
    try loadLauncherFavorites(allocator, &favorites);

    const cmd = args[0];
    if (std.mem.eql(u8, cmd, "list")) {
        std.debug.print("Launcher favorites: {d}\n", .{favorites.count()});
        var it = favorites.keyIterator();
        while (it.next()) |key_ptr| {
            std.debug.print("- {s}\n", .{key_ptr.*});
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "clear")) {
        var it = favorites.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        favorites.clearRetainingCapacity();
        try saveLauncherFavorites(allocator, &favorites);
        std.debug.print("Launcher favorites cleared.\n", .{});
        return;
    }

    if ((std.mem.eql(u8, cmd, "add") or std.mem.eql(u8, cmd, "remove")) and args.len < 2) {
        printLauncherFavoriteUsage();
        return;
    }

    if (std.mem.eql(u8, cmd, "add")) {
        const id = args[1];
        const gop = try favorites.getOrPut(id);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, id);
            gop.value_ptr.* = {};
            try saveLauncherFavorites(allocator, &favorites);
        }
        std.debug.print("Launcher favorite added: {s}\n", .{id});
        return;
    }

    if (std.mem.eql(u8, cmd, "remove")) {
        const id = args[1];
        if (favorites.fetchRemove(id)) |kv| {
            allocator.free(kv.key);
            try saveLauncherFavorites(allocator, &favorites);
            std.debug.print("Launcher favorite removed: {s}\n", .{id});
        } else {
            std.debug.print("Launcher favorite not found: {s}\n", .{id});
        }
        return;
    }

    printLauncherFavoriteUsage();
}

fn printLauncherFavoriteUsage() void {
    std.debug.print("Launcher favorites usage:\n", .{});
    std.debug.print("  luminade-settings launcher-favorite list\n", .{});
    std.debug.print("  luminade-settings launcher-favorite add <entry-id>\n", .{});
    std.debug.print("  luminade-settings launcher-favorite remove <entry-id>\n", .{});
    std.debug.print("  luminade-settings launcher-favorite clear\n", .{});
}

fn applyGuiAction(
    allocator: std.mem.Allocator,
    cfg: *core.RuntimeConfig,
    action_args: []const []const u8,
) !bool {
    const action = action_args[0];

    if (std.mem.eql(u8, action, "toggle-natural-scroll")) {
        cfg.profile.natural_scroll = !cfg.profile.natural_scroll;
        return true;
    }

    if (std.mem.eql(u8, action, "toggle-tap-to-click")) {
        cfg.profile.tap_to_click = !cfg.profile.tap_to_click;
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-window-mode")) {
        cfg.profile.window_mode = switch (cfg.profile.window_mode) {
            .tiling => .floating,
            .floating => .hybrid,
            .hybrid => .tiling,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-display-layout")) {
        cfg.profile.display_layout_mode = switch (cfg.profile.display_layout_mode) {
            .single => .extended,
            .extended => .mirrored,
            .mirrored => .single,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "adjust-display-scale") and action_args.len >= 2) {
        const delta = std.fmt.parseInt(i16, action_args[1], 10) catch return false;
        const base = @as(i16, @intCast(cfg.profile.display_scale_percent));
        const adjusted = @max(@as(i16, 50), @min(@as(i16, 200), base + delta));
        cfg.profile.display_scale_percent = @as(u8, @intCast(adjusted));
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-tiling-algorithm")) {
        cfg.profile.tiling_algorithm = switch (cfg.profile.tiling_algorithm) {
            .master_stack => .grid,
            .grid => .master_stack,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-default-terminal")) {
        cfg.profile.default_terminal_app = switch (cfg.profile.default_terminal_app) {
            .foot => .alacritty,
            .alacritty => .kitty,
            .kitty => .foot,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-default-browser")) {
        cfg.profile.default_browser_app = switch (cfg.profile.default_browser_app) {
            .firefox => .chromium,
            .chromium => .brave,
            .brave => .firefox,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-default-files")) {
        cfg.profile.default_files_app = switch (cfg.profile.default_files_app) {
            .thunar => .nautilus,
            .nautilus => .dolphin,
            .dolphin => .thunar,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-theme-mode")) {
        cfg.profile.theme_mode = switch (cfg.profile.theme_mode) {
            .dark => .light,
            .light => .auto,
            .auto => .dark,
        };
        return true;
    }

    if (std.mem.eql(u8, action, "cycle-theme-profile")) {
        cfg.profile.theme_profile = switch (cfg.profile.theme_profile) {
            .aurora_glass => .graphite,
            .graphite => .solaris_light,
            .solaris_light => .aurora_glass,
        };

        var theme = try core.loadThemeProfile(allocator, cfg.profile);
        defer theme.deinit(allocator);
        try core.saveThemeProfile(allocator, theme);
        return true;
    }

    if (std.mem.eql(u8, action, "set-pointer-sensitivity") and action_args.len >= 2) {
        cfg.profile.setField("pointer_sensitivity", action_args[1]) catch return false;
        return true;
    }

    if (std.mem.eql(u8, action, "set-master-ratio") and action_args.len >= 2) {
        cfg.profile.setField("master_ratio_percent", action_args[1]) catch return false;
        return true;
    }

    if (std.mem.eql(u8, action, "set-layout-gap") and action_args.len >= 2) {
        cfg.profile.setField("layout_gap", action_args[1]) catch return false;
        return true;
    }

    if (std.mem.eql(u8, action, "system-lock")) {
        return try core.runSystemAction(allocator, .lock_session);
    }

    if (std.mem.eql(u8, action, "system-suspend")) {
        return try core.runSystemAction(allocator, .suspend);
    }

    if (std.mem.eql(u8, action, "system-logout")) {
        return try core.runSystemAction(allocator, .logout);
    }

    if (std.mem.eql(u8, action, "system-network-open")) {
        return try core.runSystemAction(allocator, .open_network);
    }

    if (std.mem.eql(u8, action, "audio-volume-up")) {
        return try core.runSystemAction(allocator, .audio_volume_up);
    }

    if (std.mem.eql(u8, action, "audio-volume-down")) {
        return try core.runSystemAction(allocator, .audio_volume_down);
    }

    if (std.mem.eql(u8, action, "audio-mute")) {
        return try core.runSystemAction(allocator, .audio_mute_toggle);
    }

    return false;
}

fn dispatchGuiWidgetClick(
    allocator: std.mem.Allocator,
    cfg: *core.RuntimeConfig,
    widget_id: []const u8,
    args: []const []const u8,
) !bool {
    if (std.mem.eql(u8, widget_id, "window-mode")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-window-mode"});
    }

    if (std.mem.eql(u8, widget_id, "tiling-algorithm")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-tiling-algorithm"});
    }
    if (std.mem.eql(u8, widget_id, "display-layout")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-display-layout"});
    }
    if (std.mem.eql(u8, widget_id, "display-scale-minus")) {
        return applyGuiAction(allocator, cfg, &.{ "adjust-display-scale", "-10" });
    }
    if (std.mem.eql(u8, widget_id, "display-scale-plus")) {
        return applyGuiAction(allocator, cfg, &.{ "adjust-display-scale", "10" });
    }

    if (std.mem.eql(u8, widget_id, "natural-scroll")) {
        return applyGuiAction(allocator, cfg, &.{"toggle-natural-scroll"});
    }

    if (std.mem.eql(u8, widget_id, "theme-mode")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-theme-mode"});
    }

    if (std.mem.eql(u8, widget_id, "theme-profile")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-theme-profile"});
    }

    if (std.mem.eql(u8, widget_id, "default-terminal")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-default-terminal"});
    }

    if (std.mem.eql(u8, widget_id, "default-browser")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-default-browser"});
    }

    if (std.mem.eql(u8, widget_id, "default-files")) {
        return applyGuiAction(allocator, cfg, &.{"cycle-default-files"});
    }

    if (std.mem.eql(u8, widget_id, "shortcut-launcher")) {
        try cycleShortcutBinding(allocator, .launcher_toggle);
        return true;
    }

    if (std.mem.eql(u8, widget_id, "shortcut-terminal")) {
        try cycleShortcutBinding(allocator, .terminal_open);
        return true;
    }

    if (std.mem.eql(u8, widget_id, "shortcut-browser")) {
        try cycleShortcutBinding(allocator, .browser_open);
        return true;
    }

    if (std.mem.eql(u8, widget_id, "shortcut-files")) {
        try cycleShortcutBinding(allocator, .files_open);
        return true;
    }

    if (std.mem.eql(u8, widget_id, "shortcut-settings")) {
        try cycleShortcutBinding(allocator, .settings_open);
        return true;
    }

    if (std.mem.eql(u8, widget_id, "pointer-sensitivity")) {
        if (args.len < 1) return false;
        return applyGuiAction(allocator, cfg, &.{ "set-pointer-sensitivity", args[0] });
    }

    if (std.mem.eql(u8, widget_id, "save-device-profile")) {
        if (args.len < 3) return false;
        try setDeviceProfileEntry(allocator, args[0], args[1], args[2]);
        std.debug.print("Saved device profile via GUI click matcher='{s}' {s}={s}\n", .{ args[0], args[1], args[2] });
        return true;
    }

    if (std.mem.eql(u8, widget_id, "apply-input")) {
        const dry_run = args.len >= 1 and std.mem.eql(u8, args[0], "--dry-run");
        const report = try core.applyInputProfile(allocator, cfg.profile, dry_run);
        std.debug.print(
            "Input apply backend={s} devices={d} applied={d} skipped={d}\n",
            .{ report.backend, report.device_count, report.applied_count, report.skipped_count },
        );
        return true;
    }

    if (std.mem.eql(u8, widget_id, "system-lock")) {
        return applyGuiAction(allocator, cfg, &.{"system-lock"});
    }
    if (std.mem.eql(u8, widget_id, "system-suspend")) {
        return applyGuiAction(allocator, cfg, &.{"system-suspend"});
    }
    if (std.mem.eql(u8, widget_id, "system-logout")) {
        return applyGuiAction(allocator, cfg, &.{"system-logout"});
    }
    if (std.mem.eql(u8, widget_id, "system-network")) {
        return applyGuiAction(allocator, cfg, &.{"system-network-open"});
    }
    if (std.mem.eql(u8, widget_id, "audio-volume-up")) {
        return applyGuiAction(allocator, cfg, &.{"audio-volume-up"});
    }
    if (std.mem.eql(u8, widget_id, "audio-volume-down")) {
        return applyGuiAction(allocator, cfg, &.{"audio-volume-down"});
    }
    if (std.mem.eql(u8, widget_id, "audio-mute")) {
        return applyGuiAction(allocator, cfg, &.{"audio-mute"});
    }

    return false;
}

fn cycleShortcutBinding(allocator: std.mem.Allocator, action: core.ShortcutAction) !void {
    var shortcuts = try core.loadShortcuts(allocator);
    defer core.freeShortcuts(allocator, &shortcuts);

    const current = core.shortcutBinding(shortcuts.items, action);
    const next = nextShortcutChord(action, current);
    try core.setShortcutBinding(allocator, &shortcuts, action, next);
    try core.saveShortcuts(allocator, shortcuts.items);
}

fn nextShortcutChord(action: core.ShortcutAction, current: []const u8) []const u8 {
    const choices = switch (action) {
        .launcher_toggle => [_][]const u8{ "Super+Space", "Alt+Space", "Ctrl+Space" },
        .terminal_open => [_][]const u8{ "Super+Enter", "Ctrl+Alt+T", "Super+T" },
        .browser_open => [_][]const u8{ "Super+B", "Ctrl+Alt+B", "Super+W" },
        .files_open => [_][]const u8{ "Super+E", "Ctrl+Alt+E", "Super+F" },
        .settings_open => [_][]const u8{ "Super+,", "Ctrl+Alt+S", "Super+S" },
    };

    for (choices, 0..) |choice, idx| {
        if (!std.mem.eql(u8, choice, current)) continue;
        return choices[(idx + 1) % choices.len];
    }
    return choices[0];
}

fn runLayoutDemo(
    allocator: std.mem.Allocator,
    profile: core.DesktopProfile,
    outputs: *std.ArrayList(ui.OutputProfile),
) !void {
    if (outputs.items.len == 0) return;

    const output = outputs.items[0];
    var windows = std.ArrayList(ui.WindowState).init(allocator);
    defer windows.deinit();

    try windows.append(.{
        .id = "app-main",
        .role = .panel,
        .rect = .{ .x = 100, .y = 100, .w = 900, .h = 700 },
        .desired_w = 900,
        .desired_h = 700,
        .is_focused = true,
        .is_minimized = false,
        .is_floating = false,
        .z_index = 0,
    });
    try windows.append(.{
        .id = "app-docs",
        .role = .panel,
        .rect = .{ .x = 200, .y = 160, .w = 900, .h = 700 },
        .desired_w = 900,
        .desired_h = 700,
        .is_focused = false,
        .is_minimized = false,
        .is_floating = false,
        .z_index = 0,
    });
    try windows.append(.{
        .id = "launcher",
        .role = .launcher,
        .rect = .{ .x = 320, .y = 200, .w = 760, .h = 520 },
        .desired_w = 760,
        .desired_h = 520,
        .is_focused = false,
        .is_minimized = false,
        .is_floating = true,
        .z_index = 0,
    });
    try windows.append(.{
        .id = "settings",
        .role = .settings,
        .rect = .{ .x = 360, .y = 220, .w = 860, .h = 620 },
        .desired_w = 860,
        .desired_h = 620,
        .is_focused = false,
        .is_minimized = false,
        .is_floating = true,
        .z_index = 0,
    });

    const mode: ui.LayoutMode = switch (profile.window_mode) {
        .tiling => .tiling,
        .floating => .floating,
        .hybrid => .hybrid,
    };
    const algo: ui.LayoutAlgorithm = switch (profile.tiling_algorithm) {
        .master_stack => .master_stack,
        .grid => .grid,
    };

    const config: ui.LayoutConfig = .{
        .spacing = profile.layout_gap,
        .outer_gap = profile.layout_gap,
        .master_ratio_percent = profile.master_ratio_percent,
        .algorithm = algo,
        .float_overlays_in_hybrid = profile.float_overlays_in_hybrid,
    };

    try ui.applyWindowLayout(allocator, mode, output, windows.items, config);
    std.debug.print(
        "Layout demo output={s} mode={s} algo={s} ratio={d}% gap={d}\n",
        .{ output.name, @tagName(mode), @tagName(algo), config.master_ratio_percent, config.spacing },
    );
    for (windows.items) |window| {
        std.debug.print(
            "- {s} role={s} rect=({d},{d},{d}x{d}) floating={any} z={d}\n",
            .{
                window.id,
                @tagName(window.role),
                window.rect.x,
                window.rect.y,
                window.rect.w,
                window.rect.h,
                window.is_floating,
                window.z_index,
            },
        );
    }
}

fn setDeviceProfileEntry(
    allocator: std.mem.Allocator,
    matcher: []const u8,
    key: []const u8,
    value: []const u8,
) !void {
    if (!isDeviceKeyAllowed(key)) return error.InvalidField;

    const path = try core.deviceProfilesPath(allocator);
    defer allocator.free(path);

    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var lines = std.ArrayList([]u8).init(allocator);
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit();
    }

    const existing_file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    if (existing_file) |file| {
        var opened = file;
        defer opened.close();

        const content = try opened.readToEndAlloc(allocator, 256 * 1024);
        defer allocator.free(content);

        var split = std.mem.splitScalar(u8, content, '\n');
        while (split.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, "\r");
            if (line.len == 0) continue;
            try lines.append(try allocator.dupe(u8, line));
        }
    }

    var replaced = false;
    for (lines.items) |*line_ptr| {
        const line = std.mem.trim(u8, line_ptr.*, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const p1 = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const p2_rel = std.mem.indexOfScalar(u8, line[p1 + 1 ..], '\t') orelse continue;
        const p2 = p1 + 1 + p2_rel;

        const line_matcher = std.mem.trim(u8, line[0..p1], " \t\r");
        const line_key = std.mem.trim(u8, line[p1 + 1 .. p2], " \t\r");
        if (std.mem.eql(u8, line_matcher, matcher) and std.mem.eql(u8, line_key, key)) {
            allocator.free(line_ptr.*);
            line_ptr.* = try std.fmt.allocPrint(allocator, "{s}\t{s}\t{s}", .{ matcher, key, value });
            replaced = true;
            break;
        }
    }

    if (!replaced) {
        try lines.append(try std.fmt.allocPrint(allocator, "{s}\t{s}\t{s}", .{ matcher, key, value }));
    }

    var out = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer out.close();
    const writer = out.writer();
    try writer.writeAll("# matcher\tkey\tvalue\n");
    for (lines.items) |line| {
        if (line[0] == '#') continue;
        try writer.print("{s}\n", .{line});
    }
}

fn listDeviceProfiles(allocator: std.mem.Allocator) !void {
    var rules = try core.loadDeviceInputRules(allocator);
    defer core.freeDeviceInputRules(allocator, &rules);

    std.debug.print("Device profiles: {d}\n", .{rules.items.len});
    for (rules.items) |rule| {
        std.debug.print("- matcher='{s}'\n", .{rule.matcher});
        if (rule.pointer_sensitivity) |v| std.debug.print("  pointer_sensitivity={d}\n", .{v});
        if (rule.pointer_accel_profile) |v| std.debug.print("  pointer_accel_profile={s}\n", .{@tagName(v)});
        if (rule.natural_scroll) |v| std.debug.print("  natural_scroll={any}\n", .{v});
        if (rule.tap_to_click) |v| std.debug.print("  tap_to_click={any}\n", .{v});
    }
}

fn clearDeviceProfiles(allocator: std.mem.Allocator) !void {
    const path = try core.deviceProfilesPath(allocator);
    defer allocator.free(path);

    const parent = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(parent);

    var out = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer out.close();
    try out.writer().writeAll("# matcher\tkey\tvalue\n");
}

fn isDeviceKeyAllowed(key: []const u8) bool {
    return std.mem.eql(u8, key, "pointer_sensitivity") or
        std.mem.eql(u8, key, "pointer_accel_profile") or
        std.mem.eql(u8, key, "natural_scroll") or
        std.mem.eql(u8, key, "tap_to_click");
}
