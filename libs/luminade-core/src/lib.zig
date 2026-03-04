const std = @import("std");

pub const ProfileError = error{
    InvalidField,
    InvalidValue,
};

pub const Lang = enum {
    en,
    pl,

    pub fn fromString(value: []const u8) Lang {
        if (std.mem.eql(u8, value, "pl")) return .pl;
        return .en;
    }
};

pub const AppKind = enum {
    panel,
    launcher,
    settings,

    pub fn asString(self: AppKind) []const u8 {
        return switch (self) {
            .panel => "panel",
            .launcher => "launcher",
            .settings => "settings",
        };
    }
};

pub const RuntimeConfig = struct {
    allocator: std.mem.Allocator,
    lang: Lang,
    profile: DesktopProfile,

    pub fn init(allocator: std.mem.Allocator) RuntimeConfig {
        return loadRuntimeConfig(allocator);
    }
};

pub const ThemeMode = enum {
    dark,
    light,
    auto,

    pub fn fromString(value: []const u8) ThemeMode {
        if (std.mem.eql(u8, value, "light")) return .light;
        if (std.mem.eql(u8, value, "auto")) return .auto;
        return .dark;
    }
};

pub const Density = enum {
    compact,
    comfortable,

    pub fn fromString(value: []const u8) Density {
        if (std.mem.eql(u8, value, "compact")) return .compact;
        return .comfortable;
    }
};

pub const Motion = enum {
    minimal,
    smooth,

    pub fn fromString(value: []const u8) Motion {
        if (std.mem.eql(u8, value, "minimal")) return .minimal;
        return .smooth;
    }
};

pub const WindowMode = enum {
    tiling,
    floating,
    hybrid,

    pub fn fromString(value: []const u8) WindowMode {
        if (std.mem.eql(u8, value, "floating")) return .floating;
        if (std.mem.eql(u8, value, "hybrid")) return .hybrid;
        return .tiling;
    }
};

pub const InteractionMode = enum {
    keyboard_first,
    balanced,
    mouse_first,

    pub fn fromString(value: []const u8) InteractionMode {
        if (std.mem.eql(u8, value, "balanced")) return .balanced;
        if (std.mem.eql(u8, value, "mouse_first")) return .mouse_first;
        return .keyboard_first;
    }
};

pub const PointerAccelProfile = enum {
    adaptive,
    flat,

    pub fn fromString(value: []const u8) PointerAccelProfile {
        if (std.mem.eql(u8, value, "flat")) return .flat;
        return .adaptive;
    }
};

pub const TilingAlgorithm = enum {
    master_stack,
    grid,

    pub fn fromString(value: []const u8) TilingAlgorithm {
        if (std.mem.eql(u8, value, "grid")) return .grid;
        return .master_stack;
    }
};

pub const InputApplyReport = struct {
    backend: []const u8,
    applied_count: u8,
    skipped_count: u8,
    device_count: u8,
};

pub const DeviceInputRule = struct {
    matcher: []u8,
    pointer_sensitivity: ?i8,
    pointer_accel_profile: ?PointerAccelProfile,
    natural_scroll: ?bool,
    tap_to_click: ?bool,
};

pub const EffectiveInputProfile = struct {
    pointer_sensitivity: i8,
    pointer_accel_profile: PointerAccelProfile,
    natural_scroll: bool,
    tap_to_click: bool,
};

pub const DesktopProfile = struct {
    theme_mode: ThemeMode,
    density: Density,
    motion: Motion,
    panel_height: u8,
    corner_radius: u8,
    blur_sigma: u8,
    launcher_width: u16,
    workspace_gaps: u8,
    smart_hide_panel: bool,
    window_mode: WindowMode,
    interaction_mode: InteractionMode,
    pointer_sensitivity: i8,
    pointer_accel_profile: PointerAccelProfile,
    natural_scroll: bool,
    tap_to_click: bool,
    tiling_algorithm: TilingAlgorithm,
    master_ratio_percent: u8,
    layout_gap: u8,
    float_overlays_in_hybrid: bool,

    pub fn modernDefault() DesktopProfile {
        return .{
            .theme_mode = .dark,
            .density = .comfortable,
            .motion = .smooth,
            .panel_height = 36,
            .corner_radius = 12,
            .blur_sigma = 14,
            .launcher_width = 780,
            .workspace_gaps = 8,
            .smart_hide_panel = false,
            .window_mode = .tiling,
            .interaction_mode = .mouse_first,
            .pointer_sensitivity = 0,
            .pointer_accel_profile = .adaptive,
            .natural_scroll = false,
            .tap_to_click = true,
            .tiling_algorithm = .master_stack,
            .master_ratio_percent = 60,
            .layout_gap = 8,
            .float_overlays_in_hybrid = true,
        };
    }

    pub fn fromEnv() DesktopProfile {
        var profile = modernDefault();
        profile.applyEnvOverrides();
        return profile;
    }

    pub fn load(allocator: std.mem.Allocator) !DesktopProfile {
        const path = try profilePath(allocator);
        defer allocator.free(path);

        var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return modernDefault(),
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 64 * 1024);
        defer allocator.free(content);

        var profile = modernDefault();
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq_idx], " \t\r");
            const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t\r");
            profile.setField(key, value) catch {};
        }

        profile.applyEnvOverrides();
        return profile;
    }

    pub fn save(self: DesktopProfile, allocator: std.mem.Allocator) !void {
        const path = try profilePath(allocator);
        defer allocator.free(path);

        const dir_name = std.fs.path.dirname(path) orelse ".";
        try std.fs.cwd().makePath(dir_name);

        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        const writer = file.writer();
        try writer.writeAll("# LuminaDE desktop profile\n");
        try writer.print("theme={s}\n", .{@tagName(self.theme_mode)});
        try writer.print("density={s}\n", .{@tagName(self.density)});
        try writer.print("motion={s}\n", .{@tagName(self.motion)});
        try writer.print("panel_height={d}\n", .{self.panel_height});
        try writer.print("corner_radius={d}\n", .{self.corner_radius});
        try writer.print("blur_sigma={d}\n", .{self.blur_sigma});
        try writer.print("launcher_width={d}\n", .{self.launcher_width});
        try writer.print("workspace_gaps={d}\n", .{self.workspace_gaps});
        try writer.print("smart_hide_panel={s}\n", .{if (self.smart_hide_panel) "true" else "false"});
        try writer.print("window_mode={s}\n", .{@tagName(self.window_mode)});
        try writer.print("interaction_mode={s}\n", .{@tagName(self.interaction_mode)});
        try writer.print("pointer_sensitivity={d}\n", .{self.pointer_sensitivity});
        try writer.print("pointer_accel_profile={s}\n", .{@tagName(self.pointer_accel_profile)});
        try writer.print("natural_scroll={s}\n", .{if (self.natural_scroll) "true" else "false"});
        try writer.print("tap_to_click={s}\n", .{if (self.tap_to_click) "true" else "false"});
        try writer.print("tiling_algorithm={s}\n", .{@tagName(self.tiling_algorithm)});
        try writer.print("master_ratio_percent={d}\n", .{self.master_ratio_percent});
        try writer.print("layout_gap={d}\n", .{self.layout_gap});
        try writer.print("float_overlays_in_hybrid={s}\n", .{if (self.float_overlays_in_hybrid) "true" else "false"});
    }

    pub fn setField(self: *DesktopProfile, key: []const u8, value: []const u8) ProfileError!void {
        if (std.mem.eql(u8, key, "theme")) {
            self.theme_mode = ThemeMode.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "density")) {
            self.density = Density.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "motion")) {
            self.motion = Motion.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "panel_height")) {
            self.panel_height = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "corner_radius")) {
            self.corner_radius = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "blur_sigma")) {
            self.blur_sigma = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "launcher_width")) {
            self.launcher_width = std.fmt.parseUnsigned(u16, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "workspace_gaps")) {
            self.workspace_gaps = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "smart_hide_panel")) {
            self.smart_hide_panel = parseBool(value);
            return;
        }
        if (std.mem.eql(u8, key, "window_mode")) {
            self.window_mode = WindowMode.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "interaction_mode")) {
            self.interaction_mode = InteractionMode.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "pointer_sensitivity")) {
            const parsed = std.fmt.parseInt(i16, value, 10) catch return error.InvalidValue;
            if (parsed < -100 or parsed > 100) return error.InvalidValue;
            self.pointer_sensitivity = @as(i8, @intCast(parsed));
            return;
        }
        if (std.mem.eql(u8, key, "pointer_accel_profile")) {
            self.pointer_accel_profile = PointerAccelProfile.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "natural_scroll")) {
            self.natural_scroll = parseBool(value);
            return;
        }
        if (std.mem.eql(u8, key, "tap_to_click")) {
            self.tap_to_click = parseBool(value);
            return;
        }
        if (std.mem.eql(u8, key, "tiling_algorithm")) {
            self.tiling_algorithm = TilingAlgorithm.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "master_ratio_percent")) {
            const parsed_ratio = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            if (parsed_ratio < 20 or parsed_ratio > 80) return error.InvalidValue;
            self.master_ratio_percent = parsed_ratio;
            return;
        }
        if (std.mem.eql(u8, key, "layout_gap")) {
            self.layout_gap = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "float_overlays_in_hybrid")) {
            self.float_overlays_in_hybrid = parseBool(value);
            return;
        }

        return error.InvalidField;
    }

    pub fn applyEnvOverrides(self: *DesktopProfile) void {

        const env_theme = std.posix.getenv("LUMINADE_THEME") orelse @tagName(self.theme_mode);
        self.theme_mode = ThemeMode.fromString(env_theme);

        const env_density = std.posix.getenv("LUMINADE_DENSITY") orelse @tagName(self.density);
        self.density = Density.fromString(env_density);

        const env_motion = std.posix.getenv("LUMINADE_MOTION") orelse @tagName(self.motion);
        self.motion = Motion.fromString(env_motion);

        const env_panel_height = std.posix.getenv("LUMINADE_PANEL_HEIGHT");
        if (env_panel_height) |value| {
            self.panel_height = std.fmt.parseUnsigned(u8, value, 10) catch self.panel_height;
        }

        const env_launcher_width = std.posix.getenv("LUMINADE_LAUNCHER_WIDTH");
        if (env_launcher_width) |value| {
            self.launcher_width = std.fmt.parseUnsigned(u16, value, 10) catch self.launcher_width;
        }

        const env_workspace_gaps = std.posix.getenv("LUMINADE_WORKSPACE_GAPS");
        if (env_workspace_gaps) |value| {
            self.workspace_gaps = std.fmt.parseUnsigned(u8, value, 10) catch self.workspace_gaps;
        }

        const env_smart_hide = std.posix.getenv("LUMINADE_PANEL_AUTOHIDE");
        if (env_smart_hide) |value| {
            self.smart_hide_panel = parseBool(value);
        }

        const env_window_mode = std.posix.getenv("LUMINADE_WINDOW_MODE") orelse @tagName(self.window_mode);
        self.window_mode = WindowMode.fromString(env_window_mode);

        const env_interaction_mode = std.posix.getenv("LUMINADE_INTERACTION_MODE") orelse @tagName(self.interaction_mode);
        self.interaction_mode = InteractionMode.fromString(env_interaction_mode);

        const env_pointer_sensitivity = std.posix.getenv("LUMINADE_POINTER_SENSITIVITY");
        if (env_pointer_sensitivity) |value| {
            const parsed = std.fmt.parseInt(i16, value, 10) catch self.pointer_sensitivity;
            if (parsed >= -100 and parsed <= 100) {
                self.pointer_sensitivity = @as(i8, @intCast(parsed));
            }
        }

        const env_pointer_accel_profile = std.posix.getenv("LUMINADE_POINTER_ACCEL_PROFILE") orelse @tagName(self.pointer_accel_profile);
        self.pointer_accel_profile = PointerAccelProfile.fromString(env_pointer_accel_profile);

        const env_natural_scroll = std.posix.getenv("LUMINADE_NATURAL_SCROLL");
        if (env_natural_scroll) |value| {
            self.natural_scroll = parseBool(value);
        }

        const env_tap_to_click = std.posix.getenv("LUMINADE_TAP_TO_CLICK");
        if (env_tap_to_click) |value| {
            self.tap_to_click = parseBool(value);
        }

        const env_tiling_algorithm = std.posix.getenv("LUMINADE_TILING_ALGORITHM") orelse @tagName(self.tiling_algorithm);
        self.tiling_algorithm = TilingAlgorithm.fromString(env_tiling_algorithm);

        const env_master_ratio = std.posix.getenv("LUMINADE_MASTER_RATIO_PERCENT");
        if (env_master_ratio) |value| {
            const parsed_ratio = std.fmt.parseUnsigned(u8, value, 10) catch self.master_ratio_percent;
            if (parsed_ratio >= 20 and parsed_ratio <= 80) {
                self.master_ratio_percent = parsed_ratio;
            }
        }

        const env_layout_gap = std.posix.getenv("LUMINADE_LAYOUT_GAP");
        if (env_layout_gap) |value| {
            self.layout_gap = std.fmt.parseUnsigned(u8, value, 10) catch self.layout_gap;
        }

        const env_float_overlays = std.posix.getenv("LUMINADE_FLOAT_OVERLAYS_IN_HYBRID");
        if (env_float_overlays) |value| {
            self.float_overlays_in_hybrid = parseBool(value);
        }
    }
};

pub fn profilePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_PROFILE_PATH")) |value| {
        return try allocator.dupe(u8, value);
    }

    return try allocator.dupe(u8, ".luminade/profile.conf");
}

pub fn deviceProfilesPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_DEVICE_PROFILES_PATH")) |value| {
        return try allocator.dupe(u8, value);
    }

    return try allocator.dupe(u8, ".luminade/device-profiles.conf");
}

pub fn parseBool(value: []const u8) bool {
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

pub fn tr(kind: AppKind, lang: Lang) []const u8 {
    return switch (kind) {
        .panel => switch (lang) {
            .en => "Panel ready: workspaces, clock and status modules online.",
            .pl => "Panel gotowy: moduły pulpitów, zegara i statusu są aktywne.",
        },
        .launcher => switch (lang) {
            .en => "Launcher ready: type to search apps, files and commands.",
            .pl => "Launcher gotowy: wpisuj, aby wyszukiwać aplikacje, pliki i polecenia.",
        },
        .settings => switch (lang) {
            .en => "Settings ready: configure desktop and system integration.",
            .pl => "Ustawienia gotowe: skonfiguruj pulpit i integrację z systemem.",
        },
    };
}

pub fn printBanner(kind: AppKind, cfg: RuntimeConfig) void {
    std.debug.print("LuminaDE/{s} [{s}]\n", .{ kind.asString(), @tagName(cfg.lang) });
    std.debug.print("{s}\n", .{tr(kind, cfg.lang)});
}

pub fn loadRuntimeConfig(allocator: std.mem.Allocator) RuntimeConfig {
    const env_value = std.posix.getenv("LUMINADE_LANG") orelse "en";
    const profile = DesktopProfile.load(allocator) catch DesktopProfile.fromEnv();

    return .{
        .allocator = allocator,
        .lang = Lang.fromString(env_value),
        .profile = profile,
    };
}

pub fn printModernSummary(kind: AppKind, cfg: RuntimeConfig) void {
    std.debug.print(
        "Theme={s}, Density={s}, Motion={s}, Radius={d}, Blur={d}, Gaps={d}, WM={s}, Input={s}\n",
        .{
            @tagName(cfg.profile.theme_mode),
            @tagName(cfg.profile.density),
            @tagName(cfg.profile.motion),
            cfg.profile.corner_radius,
            cfg.profile.blur_sigma,
            cfg.profile.workspace_gaps,
            @tagName(cfg.profile.window_mode),
            @tagName(cfg.profile.interaction_mode),
        },
    );

    switch (kind) {
        .panel => std.debug.print(
            "Panel height={d}, smart-hide={any}, pointer={d} accel={s}, tile={s} ratio={d}% gap={d}\n",
            .{
                cfg.profile.panel_height,
                cfg.profile.smart_hide_panel,
                cfg.profile.pointer_sensitivity,
                @tagName(cfg.profile.pointer_accel_profile),
                @tagName(cfg.profile.tiling_algorithm),
                cfg.profile.master_ratio_percent,
                cfg.profile.layout_gap,
            },
        ),
        .launcher => std.debug.print(
            "Launcher width={d}px, interaction={s}, pointer={d}\n",
            .{ cfg.profile.launcher_width, @tagName(cfg.profile.interaction_mode), cfg.profile.pointer_sensitivity },
        ),
        .settings => std.debug.print(
            "Settings mode=unified desktop+system control, natural-scroll={any}, tap-to-click={any}\n",
            .{ cfg.profile.natural_scroll, cfg.profile.tap_to_click },
        ),
    }
}

pub fn applyInputProfile(allocator: std.mem.Allocator, profile: DesktopProfile, dry_run: bool) !InputApplyReport {
    const riverctl_probe = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "riverctl", "-h" },
        .max_output_bytes = 16 * 1024,
    }) catch {
        return .{ .backend = "noop", .applied_count = 0, .skipped_count = 4, .device_count = 0 };
    };
    defer allocator.free(riverctl_probe.stdout);
    defer allocator.free(riverctl_probe.stderr);

    switch (riverctl_probe.term) {
        .Exited => |code| if (code != 0) return .{ .backend = "noop", .applied_count = 0, .skipped_count = 4, .device_count = 0 },
        else => return .{ .backend = "noop", .applied_count = 0, .skipped_count = 4, .device_count = 0 },
    }

    const env_path = std.fs.path.join(allocator, &.{ ".luminade", "runtime-input.env" }) catch {
        return .{ .backend = "riverctl", .applied_count = 0, .skipped_count = 4, .device_count = 0 };
    };
    defer allocator.free(env_path);

    const parent = std.fs.path.dirname(env_path) orelse ".";
    std.fs.cwd().makePath(parent) catch {};

    var file = std.fs.cwd().createFile(env_path, .{ .truncate = true }) catch {
        return .{ .backend = "riverctl", .applied_count = 0, .skipped_count = 4, .device_count = 0 };
    };
    defer file.close();

    var devices = std.ArrayList([]u8).init(allocator);
    defer {
        for (devices.items) |name| allocator.free(name);
        devices.deinit();
    }
    try collectInputDevices(allocator, &devices);

    var rules = try loadDeviceInputRules(allocator);
    defer freeDeviceInputRules(allocator, &rules);

    if (devices.items.len == 0) {
        try devices.append(try allocator.dupe(u8, "*"));
    }

    var applied_count: u8 = 0;
    var skipped_count: u8 = 0;

    const writer = file.writer();
    writer.print("# Input profile apply plan\n", .{}) catch {};
    writer.print("dry_run={s}\n", .{if (dry_run) "true" else "false"}) catch {};
    writer.print("pointer_sensitivity={d}\n", .{profile.pointer_sensitivity}) catch {};
    writer.print("pointer_accel_profile={s}\n", .{accel_profile}) catch {};
    writer.print("natural_scroll={s}\n", .{if (profile.natural_scroll) "true" else "false"}) catch {};
    writer.print("tap_to_click={s}\n", .{if (profile.tap_to_click) "true" else "false"}) catch {};
    writer.print("devices={d}\n", .{devices.items.len}) catch {};
    writer.print("device_rules={d}\n", .{rules.items.len}) catch {};

    for (devices.items) |device| {
        const effective = effectiveProfileForDevice(profile, rules.items, device);
        const pointer_accel = pointerAccelValue(effective.pointer_sensitivity);
        const accel_profile = @tagName(effective.pointer_accel_profile);
        const natural_value = if (effective.natural_scroll) "enabled" else "disabled";
        const tap_value = if (effective.tap_to_click) "enabled" else "disabled";

        writer.print("\n# device={s}\n", .{device}) catch {};
        writer.print("effective.pointer_sensitivity={d}\n", .{effective.pointer_sensitivity}) catch {};
        writer.print("effective.pointer_accel_profile={s}\n", .{accel_profile}) catch {};
        writer.print("effective.natural_scroll={s}\n", .{if (effective.natural_scroll) "true" else "false"}) catch {};
        writer.print("effective.tap_to_click={s}\n", .{if (effective.tap_to_click) "true" else "false"}) catch {};

        if (try tryApplyRiverInputOption(allocator, writer, dry_run, device, "pointer-accel", pointer_accel)) {
            applied_count += 1;
        } else skipped_count += 1;

        if (try tryApplyRiverInputOption(allocator, writer, dry_run, device, "accel-profile", accel_profile)) {
            applied_count += 1;
        } else skipped_count += 1;

        if (try tryApplyRiverInputOption(allocator, writer, dry_run, device, "natural-scroll", natural_value)) {
            applied_count += 1;
        } else skipped_count += 1;

        if (try tryApplyRiverInputOption(allocator, writer, dry_run, device, "tap", tap_value)) {
            applied_count += 1;
        } else skipped_count += 1;
    }

    return .{
        .backend = if (dry_run) "riverctl-dry-run" else "riverctl",
        .applied_count = applied_count,
        .skipped_count = skipped_count,
        .device_count = @as(u8, @intCast(@min(devices.items.len, std.math.maxInt(u8)))),
    };
}

fn effectiveProfileForDevice(
    global: DesktopProfile,
    rules: []const DeviceInputRule,
    device_name: []const u8,
) EffectiveInputProfile {
    var result: EffectiveInputProfile = .{
        .pointer_sensitivity = global.pointer_sensitivity,
        .pointer_accel_profile = global.pointer_accel_profile,
        .natural_scroll = global.natural_scroll,
        .tap_to_click = global.tap_to_click,
    };

    for (rules) |rule| {
        if (!containsIgnoreCase(device_name, rule.matcher)) continue;
        if (rule.pointer_sensitivity) |v| result.pointer_sensitivity = v;
        if (rule.pointer_accel_profile) |v| result.pointer_accel_profile = v;
        if (rule.natural_scroll) |v| result.natural_scroll = v;
        if (rule.tap_to_click) |v| result.tap_to_click = v;
    }

    return result;
}

fn pointerAccelValue(sensitivity: i8) []const u8 {
    if (sensitivity <= -75) return "-1.0";
    if (sensitivity <= -50) return "-0.75";
    if (sensitivity <= -25) return "-0.5";
    if (sensitivity <= -10) return "-0.25";
    if (sensitivity < 10) return "0.0";
    if (sensitivity < 25) return "0.25";
    if (sensitivity < 50) return "0.5";
    if (sensitivity < 75) return "0.75";
    return "1.0";
}

fn collectInputDevices(allocator: std.mem.Allocator, devices: *std.ArrayList([]u8)) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.keyIterator();
        while (it.next()) |key_ptr| allocator.free(key_ptr.*);
        seen.deinit();
    }

    const river_list = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "riverctl", "list-inputs" },
        .max_output_bytes = 128 * 1024,
    }) catch {
        try collectInputDevicesFromLibinput(allocator, devices, &seen);
        return;
    };
    defer allocator.free(river_list.stdout);
    defer allocator.free(river_list.stderr);

    switch (river_list.term) {
        .Exited => |code| {
            if (code == 0) {
                var lines = std.mem.splitScalar(u8, river_list.stdout, '\n');
                while (lines.next()) |line_raw| {
                    const line = std.mem.trim(u8, line_raw, " \t\r");
                    if (line.len == 0) continue;
                    if (std.ascii.startsWithIgnoreCase(line, "identifier") or std.ascii.startsWithIgnoreCase(line, "name")) continue;

                    const id = if (std.mem.indexOfAny(u8, line, "\t ")) |sep|
                        std.mem.trim(u8, line[0..sep], " \t\r")
                    else
                        line;
                    if (id.len == 0) continue;
                    if (seen.contains(id)) continue;

                    const owned_seen = try allocator.dupe(u8, id);
                    try seen.put(owned_seen, {});
                    try devices.append(try allocator.dupe(u8, id));
                }
            }
        },
        else => {},
    }

    if (devices.items.len == 0) {
        try collectInputDevicesFromLibinput(allocator, devices, &seen);
    }
}

fn collectInputDevicesFromLibinput(
    allocator: std.mem.Allocator,
    devices: *std.ArrayList([]u8),
    seen: *std.StringHashMap(void),
) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "libinput", "list-devices" },
        .max_output_bytes = 512 * 1024,
    }) catch return;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return,
        else => return,
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "Device:")) continue;
        const name = std.mem.trim(u8, line[7..], " \t\r");
        if (name.len == 0) continue;
        if (seen.contains(name)) continue;

        const owned_seen = try allocator.dupe(u8, name);
        try seen.put(owned_seen, {});
        try devices.append(try allocator.dupe(u8, name));
    }
}

fn tryApplyRiverInputOption(
    allocator: std.mem.Allocator,
    writer: anytype,
    dry_run: bool,
    device: []const u8,
    option_name: []const u8,
    option_value: []const u8,
) !bool {
    const cmd = [_][]const u8{ "riverctl", "input", device, option_name, option_value };
    writer.print("riverctl input {s} {s} {s}\n", .{ device, option_name, option_value }) catch {};

    if (dry_run) return true;

    if (try runCommandOk(allocator, &cmd)) return true;

    const cmd_alt = [_][]const u8{ "riverctl", "input", device, option_name, if (std.mem.eql(u8, option_value, "enabled")) "on" else if (std.mem.eql(u8, option_value, "disabled")) "off" else option_value };
    if (!std.mem.eql(u8, cmd_alt[4], option_value)) {
        writer.print("riverctl input {s} {s} {s}\n", .{ device, option_name, cmd_alt[4] }) catch {};
        if (try runCommandOk(allocator, &cmd_alt)) return true;
    }

    return false;
}

fn runCommandOk(allocator: std.mem.Allocator, argv: []const []const u8) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 32 * 1024,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

pub fn loadDeviceInputRules(allocator: std.mem.Allocator) !std.ArrayList(DeviceInputRule) {
    var rules = std.ArrayList(DeviceInputRule).init(allocator);

    const path = try deviceProfilesPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return rules,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 256 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const p1 = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const p2_rel = std.mem.indexOfScalar(u8, line[p1 + 1 ..], '\t') orelse continue;
        const p2 = p1 + 1 + p2_rel;

        const matcher = std.mem.trim(u8, line[0..p1], " \t\r");
        const key = std.mem.trim(u8, line[p1 + 1 .. p2], " \t\r");
        const value = std.mem.trim(u8, line[p2 + 1 ..], " \t\r");
        if (matcher.len == 0 or key.len == 0 or value.len == 0) continue;

        var idx: ?usize = null;
        for (rules.items, 0..) |rule, i| {
            if (std.mem.eql(u8, rule.matcher, matcher)) {
                idx = i;
                break;
            }
        }

        if (idx == null) {
            try rules.append(.{
                .matcher = try allocator.dupe(u8, matcher),
                .pointer_sensitivity = null,
                .pointer_accel_profile = null,
                .natural_scroll = null,
                .tap_to_click = null,
            });
            idx = rules.items.len - 1;
        }

        var target = &rules.items[idx.?];
        if (std.mem.eql(u8, key, "pointer_sensitivity")) {
            const parsed = std.fmt.parseInt(i16, value, 10) catch continue;
            if (parsed < -100 or parsed > 100) continue;
            target.pointer_sensitivity = @as(i8, @intCast(parsed));
            continue;
        }
        if (std.mem.eql(u8, key, "pointer_accel_profile")) {
            target.pointer_accel_profile = PointerAccelProfile.fromString(value);
            continue;
        }
        if (std.mem.eql(u8, key, "natural_scroll")) {
            target.natural_scroll = parseBool(value);
            continue;
        }
        if (std.mem.eql(u8, key, "tap_to_click")) {
            target.tap_to_click = parseBool(value);
            continue;
        }
    }

    return rules;
}

pub fn freeDeviceInputRules(allocator: std.mem.Allocator, rules: *std.ArrayList(DeviceInputRule)) void {
    for (rules.items) |rule| {
        allocator.free(rule.matcher);
    }
    rules.deinit();
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
