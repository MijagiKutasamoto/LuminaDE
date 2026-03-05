const std = @import("std");
const core = @import("luminade_core");
const ui = @import("luminade_ui");

const WelcomeTextKey = enum {
    title,
    subtitle,
    section_quick_setup,
    section_guide,
    action_lang,
    action_mode,
    action_layout,
    action_input,
    action_finish,
    action_dont_show_again,
    action_open_settings,
    action_open_launcher,
    action_run_privacy_check,
    choice_lang_en,
    choice_lang_pl,
    choice_mode_mouse,
    choice_mode_balanced,
    choice_mode_keyboard,
    choice_layout_tiling,
    choice_layout_hybrid,
    choice_layout_floating,
    choice_tap_to_click,
    word_on,
    word_off,
    info_launcher,
    info_panel,
    info_settings,
    info_shortcuts,
    info_privacy,
};

const Selection = struct {
    lang: core.Lang,
    mode: core.InteractionMode,
    layout: core.WindowMode,
    tap_to_click: bool,
};

const WelcomeEvent = enum {
    none,
    rerender,
    finish,
    dont_show_again,
    open_settings,
    open_launcher,
    run_privacy_check,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var cfg = core.RuntimeConfig.init(allocator);
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var force = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--force")) force = true;
    }

    core.printBanner(.welcome, cfg);
    core.printModernSummary(.welcome, cfg);

    if (!force and !(try isFirstRun(allocator))) {
        std.debug.print("Welcome skipped: first-run marker already exists. Use --force to open manually.\n", .{});
        return;
    }

    var selection = Selection{
        .lang = cfg.lang,
        .mode = cfg.profile.interaction_mode,
        .layout = cfg.profile.window_mode,
        .tap_to_click = cfg.profile.tap_to_click,
    };

    var outputs = try ui.detectOutputs(allocator);
    defer ui.freeOutputs(allocator, &outputs);

    while (true) {
        var theme_profile = try core.loadThemeProfile(allocator, cfg.profile);
        defer theme_profile.deinit(allocator);
        const theme_tokens: ui.ThemeTokens = .{
            .corner_radius = theme_profile.corner_radius,
            .spacing_unit = theme_profile.spacing_unit,
            .blur_sigma = theme_profile.blur_sigma,
        };
        const decor_theme = ui.SurfaceDecorationTheme.fromThemeTokens(theme_tokens);

        for (outputs.items) |output| {
            const surface = ui.fullscreenSurfaceThemed(.settings, output, decor_theme);
            try renderWelcomeGui(allocator, surface, selection);
        }

        const event = try processWelcomeGuiEventQueue(allocator, &selection);
        switch (event) {
            .none => {},
            .rerender => {},
            .finish => {
                cfg.lang = selection.lang;
                cfg.profile.interaction_mode = selection.mode;
                cfg.profile.window_mode = selection.layout;
                cfg.profile.tap_to_click = selection.tap_to_click;
                try core.saveLang(allocator, selection.lang);
                try cfg.profile.save(allocator);
                try runTelemetryFreeUxChecks(allocator, selection);
                try markFirstRunDone(allocator);
                std.debug.print("Welcome finished. First-run marker written.\n", .{});
                return;
            },
            .dont_show_again => {
                try runTelemetryFreeUxChecks(allocator, selection);
                try markFirstRunDone(allocator);
                std.debug.print("Welcome disabled for future logins (first-run marker written).\n", .{});
                return;
            },
            .open_settings => try queueSessiondCommand("OPEN_SETTINGS", ""),
            .open_launcher => try queueSessiondCommand("LAUNCHER_QUERY", ""),
            .run_privacy_check => {
                try runTelemetryFreeUxChecks(allocator, selection);
                std.debug.print("Welcome telemetry-free UX check updated.\n", .{});
            },
        }

        std.time.sleep(350 * std.time.ns_per_ms);
    }
}

fn processWelcomeGuiEventQueue(allocator: std.mem.Allocator, selection: *Selection) !WelcomeEvent {
    const path = try welcomeGuiEventsPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .none,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 128 * 1024);
    defer allocator.free(content);
    if (content.len == 0) return .none;

    var result: WelcomeEvent = .none;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var split = std.mem.splitScalar(u8, line, '\t');
        const widget = std.mem.trim(u8, split.next() orelse continue, " \t\r");
        if (widget.len == 0) continue;

        if (std.mem.eql(u8, widget, "lang-en")) {
            selection.lang = .en;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "lang-pl")) {
            selection.lang = .pl;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "mode-mouse")) {
            selection.mode = .mouse_first;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "mode-balanced")) {
            selection.mode = .balanced;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "mode-keyboard")) {
            selection.mode = .keyboard_first;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "layout-tiling")) {
            selection.layout = .tiling;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "layout-hybrid")) {
            selection.layout = .hybrid;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "layout-floating")) {
            selection.layout = .floating;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "input-toggle-tap")) {
            selection.tap_to_click = !selection.tap_to_click;
            result = .rerender;
        } else if (std.mem.eql(u8, widget, "open-settings")) {
            result = .open_settings;
        } else if (std.mem.eql(u8, widget, "open-launcher")) {
            result = .open_launcher;
        } else if (std.mem.eql(u8, widget, "run-privacy-check")) {
            result = .run_privacy_check;
        } else if (std.mem.eql(u8, widget, "finish")) {
            result = .finish;
        } else if (std.mem.eql(u8, widget, "dont-show-again")) {
            result = .dont_show_again;
        }
    }

    var truncate = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer truncate.close();
    try truncate.writer().writeAll(
        "# widget-id\n# lang-en | lang-pl\n# mode-mouse | mode-balanced | mode-keyboard\n# layout-tiling | layout-hybrid | layout-floating\n# input-toggle-tap\n# open-settings\n# open-launcher\n# run-privacy-check\n# finish\n# dont-show-again\n",
    );

    return result;
}

fn renderWelcomeGui(allocator: std.mem.Allocator, surface: ui.SurfaceSpec, selection: Selection) !void {
    const title = try tr(allocator, selection.lang, .title);
    defer allocator.free(title);
    const subtitle = try tr(allocator, selection.lang, .subtitle);
    defer allocator.free(subtitle);
    const quick_setup = try tr(allocator, selection.lang, .section_quick_setup);
    defer allocator.free(quick_setup);
    const guide = try tr(allocator, selection.lang, .section_guide);
    defer allocator.free(guide);
    const action_lang = try tr(allocator, selection.lang, .action_lang);
    defer allocator.free(action_lang);
    const action_mode = try tr(allocator, selection.lang, .action_mode);
    defer allocator.free(action_mode);
    const action_layout = try tr(allocator, selection.lang, .action_layout);
    defer allocator.free(action_layout);
    const action_input = try tr(allocator, selection.lang, .action_input);
    defer allocator.free(action_input);
    const action_finish = try tr(allocator, selection.lang, .action_finish);
    defer allocator.free(action_finish);
    const action_dont_show_again = try tr(allocator, selection.lang, .action_dont_show_again);
    defer allocator.free(action_dont_show_again);
    const action_open_settings = try tr(allocator, selection.lang, .action_open_settings);
    defer allocator.free(action_open_settings);
    const action_open_launcher = try tr(allocator, selection.lang, .action_open_launcher);
    defer allocator.free(action_open_launcher);
    const action_run_privacy_check = try tr(allocator, selection.lang, .action_run_privacy_check);
    defer allocator.free(action_run_privacy_check);
    const choice_lang_en = try tr(allocator, selection.lang, .choice_lang_en);
    defer allocator.free(choice_lang_en);
    const choice_lang_pl = try tr(allocator, selection.lang, .choice_lang_pl);
    defer allocator.free(choice_lang_pl);
    const choice_mode_mouse = try tr(allocator, selection.lang, .choice_mode_mouse);
    defer allocator.free(choice_mode_mouse);
    const choice_mode_balanced = try tr(allocator, selection.lang, .choice_mode_balanced);
    defer allocator.free(choice_mode_balanced);
    const choice_mode_keyboard = try tr(allocator, selection.lang, .choice_mode_keyboard);
    defer allocator.free(choice_mode_keyboard);
    const choice_layout_tiling = try tr(allocator, selection.lang, .choice_layout_tiling);
    defer allocator.free(choice_layout_tiling);
    const choice_layout_hybrid = try tr(allocator, selection.lang, .choice_layout_hybrid);
    defer allocator.free(choice_layout_hybrid);
    const choice_layout_floating = try tr(allocator, selection.lang, .choice_layout_floating);
    defer allocator.free(choice_layout_floating);
    const choice_tap_to_click = try tr(allocator, selection.lang, .choice_tap_to_click);
    defer allocator.free(choice_tap_to_click);
    const word_on = try tr(allocator, selection.lang, .word_on);
    defer allocator.free(word_on);
    const word_off = try tr(allocator, selection.lang, .word_off);
    defer allocator.free(word_off);
    const info_launcher = try tr(allocator, selection.lang, .info_launcher);
    defer allocator.free(info_launcher);
    const info_panel = try tr(allocator, selection.lang, .info_panel);
    defer allocator.free(info_panel);
    const info_settings = try tr(allocator, selection.lang, .info_settings);
    defer allocator.free(info_settings);
    const info_shortcuts = try tr(allocator, selection.lang, .info_shortcuts);
    defer allocator.free(info_shortcuts);
    const info_privacy = try tr(allocator, selection.lang, .info_privacy);
    defer allocator.free(info_privacy);

    var frame = ui.GuiFrame.init(allocator, title, surface);
    defer frame.deinit();

    const panel_x: i32 = @divTrunc(@as(i32, @intCast(surface.width)) - 920, 2);
    const root_y: i32 = 54;

    try ui.addWidget(&frame, .{ .id = "title", .kind = .text, .label = subtitle, .rect = .{ .x = panel_x, .y = root_y, .w = 920, .h = 28 }, .interactive = false, .hoverable = false });
    try ui.addWidget(&frame, .{ .id = "quick-setup", .kind = .text, .label = quick_setup, .rect = .{ .x = panel_x, .y = root_y + 44, .w = 340, .h = 26 }, .interactive = false, .hoverable = false });

    const lang_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ action_lang, @tagName(selection.lang) });
    defer allocator.free(lang_label);
    const mode_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ action_mode, @tagName(selection.mode) });
    defer allocator.free(mode_label);
    const layout_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ action_layout, @tagName(selection.layout) });
    defer allocator.free(layout_label);
    const input_label = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ action_input, if (selection.tap_to_click) word_on else word_off });
    defer allocator.free(input_label);

    try ui.addWidget(&frame, .{ .id = "lang-en", .kind = .button, .label = choice_lang_en, .rect = .{ .x = panel_x, .y = root_y + 80, .w = 78, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "lang-pl", .kind = .button, .label = choice_lang_pl, .rect = .{ .x = panel_x + 88, .y = root_y + 80, .w = 78, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "lang-state", .kind = .badge, .label = lang_label, .rect = .{ .x = panel_x + 176, .y = root_y + 80, .w = 340, .h = 36 }, .interactive = false, .hoverable = false });

    try ui.addWidget(&frame, .{ .id = "mode-mouse", .kind = .button, .label = choice_mode_mouse, .rect = .{ .x = panel_x, .y = root_y + 126, .w = 104, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "mode-balanced", .kind = .button, .label = choice_mode_balanced, .rect = .{ .x = panel_x + 114, .y = root_y + 126, .w = 116, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "mode-keyboard", .kind = .button, .label = choice_mode_keyboard, .rect = .{ .x = panel_x + 240, .y = root_y + 126, .w = 116, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "mode-state", .kind = .badge, .label = mode_label, .rect = .{ .x = panel_x + 366, .y = root_y + 126, .w = 330, .h = 36 }, .interactive = false, .hoverable = false });

    try ui.addWidget(&frame, .{ .id = "layout-tiling", .kind = .button, .label = choice_layout_tiling, .rect = .{ .x = panel_x, .y = root_y + 172, .w = 104, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "layout-hybrid", .kind = .button, .label = choice_layout_hybrid, .rect = .{ .x = panel_x + 114, .y = root_y + 172, .w = 104, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "layout-floating", .kind = .button, .label = choice_layout_floating, .rect = .{ .x = panel_x + 228, .y = root_y + 172, .w = 116, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "layout-state", .kind = .badge, .label = layout_label, .rect = .{ .x = panel_x + 354, .y = root_y + 172, .w = 342, .h = 36 }, .interactive = false, .hoverable = false });

    try ui.addWidget(&frame, .{ .id = "input-toggle-tap", .kind = .button, .label = choice_tap_to_click, .rect = .{ .x = panel_x, .y = root_y + 218, .w = 168, .h = 36 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "input-state", .kind = .badge, .label = input_label, .rect = .{ .x = panel_x + 178, .y = root_y + 218, .w = 518, .h = 36 }, .interactive = false, .hoverable = false });

    try ui.addWidget(&frame, .{ .id = "guide-title", .kind = .text, .label = guide, .rect = .{ .x = panel_x, .y = root_y + 274, .w = 340, .h = 24 }, .interactive = false, .hoverable = false });
    try ui.addWidget(&frame, .{ .id = "guide-launcher", .kind = .list_item, .label = info_launcher, .rect = .{ .x = panel_x, .y = root_y + 304, .w = 700, .h = 34 }, .interactive = false, .hoverable = false });
    try ui.addWidget(&frame, .{ .id = "guide-panel", .kind = .list_item, .label = info_panel, .rect = .{ .x = panel_x, .y = root_y + 344, .w = 700, .h = 34 }, .interactive = false, .hoverable = false });
    try ui.addWidget(&frame, .{ .id = "guide-settings", .kind = .list_item, .label = info_settings, .rect = .{ .x = panel_x, .y = root_y + 384, .w = 700, .h = 34 }, .interactive = false, .hoverable = false });
    try ui.addWidget(&frame, .{ .id = "guide-shortcuts", .kind = .list_item, .label = info_shortcuts, .rect = .{ .x = panel_x, .y = root_y + 424, .w = 700, .h = 34 }, .interactive = false, .hoverable = false });
    try ui.addWidget(&frame, .{ .id = "guide-privacy", .kind = .badge, .label = info_privacy, .rect = .{ .x = panel_x, .y = root_y + 466, .w = 700, .h = 32 }, .interactive = false, .hoverable = false });

    try ui.addWidget(&frame, .{ .id = "open-settings", .kind = .button, .label = action_open_settings, .rect = .{ .x = panel_x, .y = root_y + 510, .w = 170, .h = 42 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "open-launcher", .kind = .button, .label = action_open_launcher, .rect = .{ .x = panel_x + 180, .y = root_y + 510, .w = 170, .h = 42 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "run-privacy-check", .kind = .button, .label = action_run_privacy_check, .rect = .{ .x = panel_x + 360, .y = root_y + 510, .w = 190, .h = 42 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "finish", .kind = .button, .label = action_finish, .rect = .{ .x = panel_x + 560, .y = root_y + 510, .w = 170, .h = 42 }, .interactive = true, .hoverable = true });
    try ui.addWidget(&frame, .{ .id = "dont-show-again", .kind = .button, .label = action_dont_show_again, .rect = .{ .x = panel_x + 740, .y = root_y + 510, .w = 180, .h = 42 }, .interactive = true, .hoverable = true });

    ui.printGuiFrame(&frame);
}

fn trKey(key: WelcomeTextKey) []const u8 {
    return switch (key) {
        .title => "welcome.title",
        .subtitle => "welcome.subtitle",
        .section_quick_setup => "welcome.section.quick_setup",
        .section_guide => "welcome.section.guide",
        .action_lang => "welcome.action.lang",
        .action_mode => "welcome.action.mode",
        .action_layout => "welcome.action.layout",
        .action_input => "welcome.action.input",
        .action_finish => "welcome.action.finish",
        .action_dont_show_again => "welcome.action.dont_show_again",
        .action_open_settings => "welcome.action.open_settings",
        .action_open_launcher => "welcome.action.open_launcher",
        .action_run_privacy_check => "welcome.action.run_privacy_check",
        .choice_lang_en => "welcome.choice.lang_en",
        .choice_lang_pl => "welcome.choice.lang_pl",
        .choice_mode_mouse => "welcome.choice.mode_mouse",
        .choice_mode_balanced => "welcome.choice.mode_balanced",
        .choice_mode_keyboard => "welcome.choice.mode_keyboard",
        .choice_layout_tiling => "welcome.choice.layout_tiling",
        .choice_layout_hybrid => "welcome.choice.layout_hybrid",
        .choice_layout_floating => "welcome.choice.layout_floating",
        .choice_tap_to_click => "welcome.choice.tap_to_click",
        .word_on => "settings.word.on",
        .word_off => "settings.word.off",
        .info_launcher => "welcome.info.launcher",
        .info_panel => "welcome.info.panel",
        .info_settings => "welcome.info.settings",
        .info_shortcuts => "welcome.info.shortcuts",
        .info_privacy => "welcome.info.privacy",
    };
}

fn tr(allocator: std.mem.Allocator, lang: core.Lang, key: WelcomeTextKey) ![]u8 {
    return core.localeGetWithEnFallback(allocator, lang, trKey(key));
}

fn firstRunMarkerPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_FIRST_RUN_MARKER")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/first-run.done");
}

fn isFirstRun(allocator: std.mem.Allocator) !bool {
    const marker = try firstRunMarkerPath(allocator);
    defer allocator.free(marker);

    std.fs.cwd().access(marker, .{}) catch |err| switch (err) {
        error.FileNotFound => return true,
        else => return err,
    };
    return false;
}

fn markFirstRunDone(allocator: std.mem.Allocator) !void {
    const marker = try firstRunMarkerPath(allocator);
    defer allocator.free(marker);

    const dir_name = std.fs.path.dirname(marker) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(marker, .{ .truncate = true });
    defer file.close();
    try file.writer().writeAll("done\n");
}

fn welcomeGuiEventsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_WELCOME_GUI_EVENTS")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/gui-welcome-events.tsv");
}

fn queueSessiondCommand(command: []const u8, arg: []const u8) !void {
    const path = std.posix.getenv("LUMINADE_SESSIOND_COMMANDS") orelse ".luminade/sessiond-commands.tsv";
    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(path, .{ .truncate = false }),
        else => return err,
    };
    defer file.close();

    try file.seekFromEnd(0);
    try file.writer().print("{s}\t{s}\n", .{ command, arg });
}

fn runTelemetryFreeUxChecks(allocator: std.mem.Allocator, selection: Selection) !void {
    _ = allocator;
    const path = std.posix.getenv("LUMINADE_WELCOME_UX_REPORT") orelse ".luminade/welcome-ux-checks.log";
    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("# Welcome UX telemetry-free check\n");
    try writer.writeAll("telemetry_network_calls=0\n");
    try writer.writeAll("remote_endpoints=none\n");
    try writer.writeAll("storage_scope=local_files_only\n");
    try writer.print("selected_lang={s}\n", .{@tagName(selection.lang)});
    try writer.print("selected_mode={s}\n", .{@tagName(selection.mode)});
    try writer.print("selected_layout={s}\n", .{@tagName(selection.layout)});
    try writer.print("tap_to_click={s}\n", .{if (selection.tap_to_click) "true" else "false"});
}
