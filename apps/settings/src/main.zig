const std = @import("std");
const core = @import("luminade_core");
const ui = @import("luminade_ui");

const SettingsTextKey = enum {
    settings_title,
    section_layout,
    section_input,
    section_device_profiles,
    section_live_preview,
    section_system,
    label_window_mode,
    label_tiling,
    label_pointer_sensitivity,
    label_natural_scroll,
    label_device_matcher,
    label_save_device_profile,
    label_apply_input,
    label_system_lock,
    label_system_suspend,
    label_system_logout,
    label_audio_up,
    label_audio_down,
    label_audio_mute,
    word_on,
    word_off,
    preview_main,
    preview_docs,
    preview_overlay,
};

fn tr(lang: core.Lang, key: SettingsTextKey) []const u8 {
    return switch (lang) {
        .pl => switch (key) {
            .settings_title => "Ustawienia",
            .section_layout => "Układ i okna",
            .section_input => "Mysz i touchpad",
            .section_device_profiles => "Profile urządzeń",
            .section_live_preview => "Podgląd na żywo (układ)",
            .section_system => "System i zasilanie",
            .label_window_mode => "Tryb okien",
            .label_tiling => "Kafelkowanie",
            .label_pointer_sensitivity => "Czułość wskaźnika",
            .label_natural_scroll => "Naturalne przewijanie",
            .label_device_matcher => "Matcher urządzenia (fragment nazwy)",
            .label_save_device_profile => "Zapisz profil urządzenia",
            .label_apply_input => "Zastosuj wejście teraz",
            .label_system_lock => "Zablokuj ekran",
            .label_system_suspend => "Uśpij",
            .label_system_logout => "Wyloguj",
            .label_audio_up => "Głośniej",
            .label_audio_down => "Ciszej",
            .label_audio_mute => "Wycisz/odcisz",
            .word_on => "włączone",
            .word_off => "wyłączone",
            .preview_main => "Główne",
            .preview_docs => "Dokumenty",
            .preview_overlay => "Nakładka",
        },
        .en => switch (key) {
            .settings_title => "Settings",
            .section_layout => "Layout & Windows",
            .section_input => "Mouse & Touchpad",
            .section_device_profiles => "Device Profiles",
            .section_live_preview => "Live Preview (Layout)",
            .section_system => "System & Power",
            .label_window_mode => "Window mode",
            .label_tiling => "Tiling",
            .label_pointer_sensitivity => "Pointer sensitivity",
            .label_natural_scroll => "Natural scroll",
            .label_device_matcher => "Device matcher (substring)",
            .label_save_device_profile => "Save device profile",
            .label_apply_input => "Apply input now",
            .label_system_lock => "Lock screen",
            .label_system_suspend => "Suspend",
            .label_system_logout => "Log out",
            .label_audio_up => "Volume up",
            .label_audio_down => "Volume down",
            .label_audio_mute => "Mute / unmute",
            .word_on => "on",
            .word_off => "off",
            .preview_main => "Main",
            .preview_docs => "Docs",
            .preview_overlay => "Overlay",
        },
    };
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

    std.debug.print("Detected outputs: {d}\n", .{outputs.items.len});
    for (outputs.items) |output| {
        const surface = ui.fullscreenSurface(.settings, output);
        ui.printSurfaceSummary(surface, ui.ThemeTokens.modernDefault());
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
        for (outputs.items) |output| {
            const surface = ui.fullscreenSurface(.settings, output);
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
    try truncate.writer().writeAll("# widget-id\t[arg1]\t[arg2]\n");

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
    var frame = ui.GuiFrame.init(allocator, tr(lang, .settings_title), surface);
    defer frame.deinit();

    const window_mode_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ tr(lang, .label_window_mode), @tagName(profile.window_mode) });
    defer allocator.free(window_mode_label);
    const tiling_label = try std.fmt.allocPrint(allocator, "{s}: {s} ({d}%)", .{ tr(lang, .label_tiling), @tagName(profile.tiling_algorithm), profile.master_ratio_percent });
    defer allocator.free(tiling_label);
    const pointer_label = try std.fmt.allocPrint(allocator, "{s}: {d}", .{ tr(lang, .label_pointer_sensitivity), profile.pointer_sensitivity });
    defer allocator.free(pointer_label);
    const natural_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ tr(lang, .label_natural_scroll), if (profile.natural_scroll) tr(lang, .word_on) else tr(lang, .word_off) });
    defer allocator.free(natural_label);
    const device_matcher_label = tr(lang, .label_device_matcher);

    try ui.addWidget(&frame, .{
        .id = "settings-root",
        .kind = .column,
        .label = "settings-root",
        .rect = .{ .x = 24, .y = 56, .w = @max(surface.width - 48, 240), .h = @max(surface.height - 80, 160) },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "section-layout",
        .kind = .text,
        .label = tr(lang, .section_layout),
        .rect = .{ .x = 32, .y = 74, .w = 280, .h = 28 },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "section-input",
        .kind = .text,
        .label = tr(lang, .section_input),
        .rect = .{ .x = 32, .y = 164, .w = 280, .h = 28 },
        .interactive = false,
        .hoverable = false,
    });
    try ui.addWidget(&frame, .{
        .id = "section-device-profiles",
        .kind = .text,
        .label = tr(lang, .section_device_profiles),
        .rect = .{ .x = 32, .y = 258, .w = 280, .h = 28 },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "window-mode",
        .kind = .button,
        .label = window_mode_label,
        .rect = .{ .x = 32, .y = 108, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "tiling-algorithm",
        .kind = .button,
        .label = tiling_label,
        .rect = .{ .x = 264, .y = 108, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "pointer-sensitivity",
        .kind = .input,
        .label = pointer_label,
        .rect = .{ .x = 32, .y = 198, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "natural-scroll",
        .kind = .toggle,
        .label = natural_label,
        .rect = .{ .x = 264, .y = 198, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "device-matcher",
        .kind = .input,
        .label = device_matcher_label,
        .rect = .{ .x = 32, .y = 292, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "save-device-profile",
        .kind = .button,
        .label = tr(lang, .label_save_device_profile),
        .rect = .{ .x = 264, .y = 292, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "apply-input",
        .kind = .button,
        .label = tr(lang, .label_apply_input),
        .rect = .{ .x = 32, .y = 344, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });

    try ui.addWidget(&frame, .{
        .id = "section-live-preview",
        .kind = .text,
        .label = tr(lang, .section_live_preview),
        .rect = .{ .x = 32, .y = 398, .w = 320, .h = 28 },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "section-system",
        .kind = .text,
        .label = tr(lang, .section_system),
        .rect = .{ .x = 568, .y = 74, .w = 280, .h = 28 },
        .interactive = false,
        .hoverable = false,
    });

    try ui.addWidget(&frame, .{
        .id = "system-lock",
        .kind = .button,
        .label = tr(lang, .label_system_lock),
        .rect = .{ .x = 568, .y = 108, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "system-suspend",
        .kind = .button,
        .label = tr(lang, .label_system_suspend),
        .rect = .{ .x = 568, .y = 156, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "system-logout",
        .kind = .button,
        .label = tr(lang, .label_system_logout),
        .rect = .{ .x = 568, .y = 204, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "audio-volume-up",
        .kind = .button,
        .label = tr(lang, .label_audio_up),
        .rect = .{ .x = 568, .y = 252, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "audio-volume-down",
        .kind = .button,
        .label = tr(lang, .label_audio_down),
        .rect = .{ .x = 568, .y = 300, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });
    try ui.addWidget(&frame, .{
        .id = "audio-mute",
        .kind = .button,
        .label = tr(lang, .label_audio_mute),
        .rect = .{ .x = 568, .y = 348, .w = 220, .h = 40 },
        .interactive = true,
        .hoverable = true,
    });

    try addLayoutPreviewWidgets(allocator, &frame, surface, profile, lang);

    ui.printGuiFrame(&frame);
}

fn addLayoutPreviewWidgets(
    allocator: std.mem.Allocator,
    frame: *ui.GuiFrame,
    surface: ui.SurfaceSpec,
    profile: core.DesktopProfile,
    lang: core.Lang,
) !void {
    const preview: ui.Rect = .{
        .x = 32,
        .y = 432,
        .w = @min(@as(u16, 520), surface.width -| 64),
        .h = @min(@as(u16, 220), surface.height -| 456),
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
            0 => tr(lang, .preview_main),
            1 => tr(lang, .preview_docs),
            else => tr(lang, .preview_overlay),
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
    std.debug.print("- density={s}\n", .{@tagName(profile.density)});
    std.debug.print("- motion={s}\n", .{@tagName(profile.motion)});
    std.debug.print("- panel_height={d}\n", .{profile.panel_height});
    std.debug.print("- corner_radius={d}\n", .{profile.corner_radius});
    std.debug.print("- blur_sigma={d}\n", .{profile.blur_sigma});
    std.debug.print("- launcher_width={d}\n", .{profile.launcher_width});
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
    std.debug.print("  cycle-tiling-algorithm\n", .{});
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
    std.debug.print("  gui-click natural-scroll\n", .{});
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

    if (std.mem.eql(u8, action, "cycle-tiling-algorithm")) {
        cfg.profile.tiling_algorithm = switch (cfg.profile.tiling_algorithm) {
            .master_stack => .grid,
            .grid => .master_stack,
        };
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
        return try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "loginctl", "lock-session" },
                &.{ "sh", "-lc", "command -v swaylock >/dev/null 2>&1 && swaylock" },
            },
        );
    }

    if (std.mem.eql(u8, action, "system-suspend")) {
        return try runSystemCommandFallback(allocator, &.{&.{ "systemctl", "suspend" }});
    }

    if (std.mem.eql(u8, action, "system-logout")) {
        return try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "loginctl", "terminate-user", std.posix.getenv("USER") orelse "" },
                &.{ "sh", "-lc", "pkill -KILL -u \"$USER\"" },
            },
        );
    }

    if (std.mem.eql(u8, action, "audio-volume-up")) {
        return try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+" },
                &.{ "pactl", "set-sink-volume", "@DEFAULT_SINK@", "+5%" },
            },
        );
    }

    if (std.mem.eql(u8, action, "audio-volume-down")) {
        return try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-" },
                &.{ "pactl", "set-sink-volume", "@DEFAULT_SINK@", "-5%" },
            },
        );
    }

    if (std.mem.eql(u8, action, "audio-mute")) {
        return try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle" },
                &.{ "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle" },
            },
        );
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

    if (std.mem.eql(u8, widget_id, "natural-scroll")) {
        return applyGuiAction(allocator, cfg, &.{"toggle-natural-scroll"});
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

fn runSystemCommandFallback(allocator: std.mem.Allocator, candidates: []const []const []const u8) !bool {
    for (candidates) |argv| {
        if (argv.len == 0) continue;
        if (try runCommandOk(allocator, argv)) return true;
    }
    return false;
}

fn runCommandOk(allocator: std.mem.Allocator, argv: []const []const u8) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 16 * 1024,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
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
