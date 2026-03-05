const std = @import("std");

/// Errors returned by profile loading/saving and field updates.
pub const ProfileError = error{
    InvalidField,
    InvalidValue,
};

/// Supported UI languages.
pub const Lang = enum {
    en,
    pl,

    pub fn fromString(value: []const u8) Lang {
        if (std.mem.eql(u8, value, "pl")) return .pl;
        return .en;
    }
};

/// Top-level LuminaDE application kinds.
pub const AppKind = enum {
    panel,
    launcher,
    settings,
    welcome,

    pub fn asString(self: AppKind) []const u8 {
        return switch (self) {
            .panel => "panel",
            .launcher => "launcher",
            .settings => "settings",
            .welcome => "welcome",
        };
    }
};

/// Runtime bundle shared by apps (allocator + language + desktop profile).
pub const RuntimeConfig = struct {
    allocator: std.mem.Allocator,
    lang: Lang,
    profile: DesktopProfile,

    pub fn init(allocator: std.mem.Allocator) RuntimeConfig {
        return loadRuntimeConfig(allocator);
    }
};

/// Icon style variant used when resolving icon assets.
pub const IconVariant = enum {
    colored,
    symbolic,
};

/// Best-effort icon path resolver with in-memory cache.
///
/// This is a skeleton API for v0.5+: it resolves names against common
/// `hicolor` locations and returns owned path slices for callers.
pub const IconResolver = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap([]u8),

    /// Initialize resolver with empty cache.
    pub fn init(allocator: std.mem.Allocator) IconResolver {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap([]u8).init(allocator),
        };
    }

    /// Free all cached keys/paths owned by resolver.
    pub fn deinit(self: *IconResolver) void {
        var it = self.cache.iterator();
        while (it.next()) |item| {
            self.allocator.free(item.key_ptr.*);
            self.allocator.free(item.value_ptr.*);
        }
        self.cache.deinit();
    }

    /// Resolve icon name to absolute path in common `hicolor` directories.
    ///
    /// Returns an owned slice that the caller must free.
    pub fn resolve(self: *IconResolver, name: []const u8, variant: IconVariant) !?[]u8 {
        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ @tagName(variant), name });

        if (self.cache.get(cache_key)) |cached| {
            self.allocator.free(cache_key);
            return try self.allocator.dupe(u8, cached);
        }

        const resolved = try self.findIconPath(name, variant) orelse blk: {
            if (!std.mem.eql(u8, name, "luminade")) {
                if (try self.findIconPath("luminade", variant)) |fallback| break :blk fallback;
            }
            self.allocator.free(cache_key);
            return null;
        };

        try self.cache.put(cache_key, resolved);
        return try self.allocator.dupe(u8, resolved);
    }

    fn findIconPath(self: *IconResolver, name: []const u8, variant: IconVariant) !?[]u8 {
        if (std.posix.getenv("XDG_DATA_HOME")) |root| {
            if (try self.findInRoot(root, name, variant)) |path| return path;
        }

        if (std.posix.getenv("HOME")) |home| {
            const local_root = try std.fmt.allocPrint(self.allocator, "{s}/.local/share", .{home});
            defer self.allocator.free(local_root);
            if (try self.findInRoot(local_root, name, variant)) |path| return path;
        }

        if (try self.findInRoot("/usr/local/share", name, variant)) |path| return path;
        if (try self.findInRoot("/usr/share", name, variant)) |path| return path;

        return null;
    }

    fn findInRoot(self: *IconResolver, root: []const u8, name: []const u8, variant: IconVariant) !?[]u8 {
        const primary_dir = switch (variant) {
            .colored => "scalable",
            .symbolic => "symbolic",
        };
        const secondary_dir = switch (variant) {
            .colored => "symbolic",
            .symbolic => "scalable",
        };

        const dirs = [_][]const u8{ primary_dir, secondary_dir };
        const exts = [_][]const u8{ "svg", "png" };

        for (dirs) |dir| {
            for (exts) |ext| {
                const path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/icons/hicolor/{s}/apps/{s}.{s}",
                    .{ root, dir, name, ext },
                );
                if (iconPathExists(path)) {
                    return path;
                }
                self.allocator.free(path);
            }
        }

        return null;
    }
};

fn iconPathExists(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        const file = std.fs.openFileAbsolute(path, .{}) catch return false;
        file.close();
        return true;
    }

    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

/// Global theme mode.
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

/// Named theme profile preset persisted in user config.
pub const ThemeProfileName = enum {
    aurora_glass,
    graphite,
    solaris_light,

    pub fn fromString(value: []const u8) ThemeProfileName {
        if (std.mem.eql(u8, value, "graphite")) return .graphite;
        if (std.mem.eql(u8, value, "solaris_light")) return .solaris_light;
        return .aurora_glass;
    }
};

/// Resolved theme token profile used by UI runtime.
pub const ThemeProfile = struct {
    name: ThemeProfileName,
    mode: ThemeMode,
    corner_radius: u8,
    spacing_unit: u8,
    blur_sigma: u8,
    accent: []u8,

    pub fn builtIn(allocator: std.mem.Allocator, name: ThemeProfileName, mode: ThemeMode) !ThemeProfile {
        return switch (name) {
            .aurora_glass => .{
                .name = .aurora_glass,
                .mode = mode,
                .corner_radius = 18,
                .spacing_unit = 10,
                .blur_sigma = 20,
                .accent = try allocator.dupe(u8, "blue"),
            },
            .graphite => .{
                .name = .graphite,
                .mode = mode,
                .corner_radius = 12,
                .spacing_unit = 8,
                .blur_sigma = 12,
                .accent = try allocator.dupe(u8, "slate"),
            },
            .solaris_light => .{
                .name = .solaris_light,
                .mode = .light,
                .corner_radius = 16,
                .spacing_unit = 10,
                .blur_sigma = 8,
                .accent = try allocator.dupe(u8, "amber"),
            },
        };
    }

    pub fn deinit(self: *ThemeProfile, allocator: std.mem.Allocator) void {
        allocator.free(self.accent);
    }

    pub fn setField(self: *ThemeProfile, allocator: std.mem.Allocator, key: []const u8, value: []const u8) ProfileError!void {
        if (std.mem.eql(u8, key, "mode")) {
            self.mode = ThemeMode.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "corner_radius")) {
            self.corner_radius = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "spacing_unit")) {
            self.spacing_unit = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "blur_sigma")) {
            self.blur_sigma = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            return;
        }
        if (std.mem.eql(u8, key, "accent")) {
            allocator.free(self.accent);
            self.accent = try allocator.dupe(u8, value);
            return;
        }
        return error.InvalidField;
    }
};

/// Shortcut actions exposed in Settings and consumed by launcher/panel/session.
pub const ShortcutAction = enum {
    launcher_toggle,
    terminal_open,
    browser_open,
    files_open,
    settings_open,

    pub fn asString(self: ShortcutAction) []const u8 {
        return switch (self) {
            .launcher_toggle => "launcher_toggle",
            .terminal_open => "terminal_open",
            .browser_open => "browser_open",
            .files_open => "files_open",
            .settings_open => "settings_open",
        };
    }

    pub fn fromString(value: []const u8) ?ShortcutAction {
        if (std.mem.eql(u8, value, "launcher_toggle")) return .launcher_toggle;
        if (std.mem.eql(u8, value, "terminal_open")) return .terminal_open;
        if (std.mem.eql(u8, value, "browser_open")) return .browser_open;
        if (std.mem.eql(u8, value, "files_open")) return .files_open;
        if (std.mem.eql(u8, value, "settings_open")) return .settings_open;
        return null;
    }
};

/// One persisted shortcut binding.
pub const ShortcutBinding = struct {
    action: ShortcutAction,
    chord: []u8,
};

/// Density preset for spacing/layout defaults.
pub const Density = enum {
    compact,
    comfortable,

    pub fn fromString(value: []const u8) Density {
        if (std.mem.eql(u8, value, "compact")) return .compact;
        return .comfortable;
    }
};

/// Motion preset for UI transitions.
pub const Motion = enum {
    minimal,
    smooth,

    pub fn fromString(value: []const u8) Motion {
        if (std.mem.eql(u8, value, "minimal")) return .minimal;
        return .smooth;
    }
};

/// Window management mode.
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

/// Interaction preference for ranking and hitbox tuning.
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

/// Pointer acceleration strategy.
pub const PointerAccelProfile = enum {
    adaptive,
    flat,

    pub fn fromString(value: []const u8) PointerAccelProfile {
        if (std.mem.eql(u8, value, "flat")) return .flat;
        return .adaptive;
    }
};

/// Tiling layout algorithm.
pub const TilingAlgorithm = enum {
    master_stack,
    grid,

    pub fn fromString(value: []const u8) TilingAlgorithm {
        if (std.mem.eql(u8, value, "grid")) return .grid;
        return .master_stack;
    }
};

/// Multi-display layout mode.
pub const DisplayLayoutMode = enum {
    single,
    extended,
    mirrored,

    pub fn fromString(value: []const u8) DisplayLayoutMode {
        if (std.mem.eql(u8, value, "extended")) return .extended;
        if (std.mem.eql(u8, value, "mirrored")) return .mirrored;
        return .single;
    }
};

/// Default terminal app choices exposed in profile/settings.
pub const DefaultTerminalApp = enum {
    foot,
    alacritty,
    kitty,

    pub fn fromString(value: []const u8) DefaultTerminalApp {
        if (std.mem.eql(u8, value, "alacritty")) return .alacritty;
        if (std.mem.eql(u8, value, "kitty")) return .kitty;
        return .foot;
    }
};

/// Default browser app choices exposed in profile/settings.
pub const DefaultBrowserApp = enum {
    firefox,
    chromium,
    brave,

    pub fn fromString(value: []const u8) DefaultBrowserApp {
        if (std.mem.eql(u8, value, "chromium")) return .chromium;
        if (std.mem.eql(u8, value, "brave")) return .brave;
        return .firefox;
    }
};

/// Default file manager choices exposed in profile/settings.
pub const DefaultFilesApp = enum {
    thunar,
    nautilus,
    dolphin,

    pub fn fromString(value: []const u8) DefaultFilesApp {
        if (std.mem.eql(u8, value, "nautilus")) return .nautilus;
        if (std.mem.eql(u8, value, "dolphin")) return .dolphin;
        return .thunar;
    }
};

/// Summary returned by input profile application pipeline.
pub const InputApplyReport = struct {
    backend: []const u8,
    applied_count: u8,
    skipped_count: u8,
    device_count: u8,
};

/// Cross-app system actions executed via shell command fallbacks.
pub const SystemAction = enum {
    lock_session,
    suspend,
    logout,
    audio_volume_up,
    audio_volume_down,
    audio_mute_toggle,
    open_network,
};

/// Per-device input override rule matched by device-name substring.
pub const DeviceInputRule = struct {
    matcher: []u8,
    pointer_sensitivity: ?i8,
    pointer_accel_profile: ?PointerAccelProfile,
    natural_scroll: ?bool,
    tap_to_click: ?bool,
};

/// Effective input profile after global + device-rule merge.
pub const EffectiveInputProfile = struct {
    pointer_sensitivity: i8,
    pointer_accel_profile: PointerAccelProfile,
    natural_scroll: bool,
    tap_to_click: bool,
};

/// Persistent desktop profile used by panel/launcher/settings/welcome.
pub const DesktopProfile = struct {
    theme_mode: ThemeMode,
    theme_profile: ThemeProfileName,
    density: Density,
    motion: Motion,
    panel_height: u8,
    corner_radius: u8,
    blur_sigma: u8,
    launcher_width: u16,
    display_scale_percent: u8,
    display_layout_mode: DisplayLayoutMode,
    default_terminal_app: DefaultTerminalApp,
    default_browser_app: DefaultBrowserApp,
    default_files_app: DefaultFilesApp,
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
            .theme_profile = .aurora_glass,
            .density = .comfortable,
            .motion = .smooth,
            .panel_height = 42,
            .corner_radius = 18,
            .blur_sigma = 20,
            .launcher_width = 960,
            .display_scale_percent = 100,
            .display_layout_mode = .single,
            .default_terminal_app = .foot,
            .default_browser_app = .firefox,
            .default_files_app = .thunar,
            .workspace_gaps = 12,
            .smart_hide_panel = false,
            .window_mode = .tiling,
            .interaction_mode = .mouse_first,
            .pointer_sensitivity = 0,
            .pointer_accel_profile = .adaptive,
            .natural_scroll = false,
            .tap_to_click = true,
            .tiling_algorithm = .master_stack,
            .master_ratio_percent = 60,
            .layout_gap = 12,
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
        try writer.print("theme_profile={s}\n", .{@tagName(self.theme_profile)});
        try writer.print("density={s}\n", .{@tagName(self.density)});
        try writer.print("motion={s}\n", .{@tagName(self.motion)});
        try writer.print("panel_height={d}\n", .{self.panel_height});
        try writer.print("corner_radius={d}\n", .{self.corner_radius});
        try writer.print("blur_sigma={d}\n", .{self.blur_sigma});
        try writer.print("launcher_width={d}\n", .{self.launcher_width});
        try writer.print("display_scale_percent={d}\n", .{self.display_scale_percent});
        try writer.print("display_layout_mode={s}\n", .{@tagName(self.display_layout_mode)});
        try writer.print("default_terminal_app={s}\n", .{@tagName(self.default_terminal_app)});
        try writer.print("default_browser_app={s}\n", .{@tagName(self.default_browser_app)});
        try writer.print("default_files_app={s}\n", .{@tagName(self.default_files_app)});
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
        if (std.mem.eql(u8, key, "theme_profile")) {
            self.theme_profile = ThemeProfileName.fromString(value);
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
        if (std.mem.eql(u8, key, "display_scale_percent")) {
            const parsed_scale = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidValue;
            if (parsed_scale < 50 or parsed_scale > 200) return error.InvalidValue;
            self.display_scale_percent = parsed_scale;
            return;
        }
        if (std.mem.eql(u8, key, "display_layout_mode")) {
            self.display_layout_mode = DisplayLayoutMode.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "default_terminal_app")) {
            self.default_terminal_app = DefaultTerminalApp.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "default_browser_app")) {
            self.default_browser_app = DefaultBrowserApp.fromString(value);
            return;
        }
        if (std.mem.eql(u8, key, "default_files_app")) {
            self.default_files_app = DefaultFilesApp.fromString(value);
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

        const env_theme_profile = std.posix.getenv("LUMINADE_THEME_PROFILE") orelse @tagName(self.theme_profile);
        self.theme_profile = ThemeProfileName.fromString(env_theme_profile);

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

        const env_display_scale = std.posix.getenv("LUMINADE_DISPLAY_SCALE_PERCENT");
        if (env_display_scale) |value| {
            const parsed_scale = std.fmt.parseUnsigned(u8, value, 10) catch self.display_scale_percent;
            if (parsed_scale >= 50 and parsed_scale <= 200) {
                self.display_scale_percent = parsed_scale;
            }
        }

        const env_display_layout = std.posix.getenv("LUMINADE_DISPLAY_LAYOUT_MODE") orelse @tagName(self.display_layout_mode);
        self.display_layout_mode = DisplayLayoutMode.fromString(env_display_layout);

        const env_default_terminal = std.posix.getenv("LUMINADE_DEFAULT_TERMINAL_APP") orelse @tagName(self.default_terminal_app);
        self.default_terminal_app = DefaultTerminalApp.fromString(env_default_terminal);

        const env_default_browser = std.posix.getenv("LUMINADE_DEFAULT_BROWSER_APP") orelse @tagName(self.default_browser_app);
        self.default_browser_app = DefaultBrowserApp.fromString(env_default_browser);

        const env_default_files = std.posix.getenv("LUMINADE_DEFAULT_FILES_APP") orelse @tagName(self.default_files_app);
        self.default_files_app = DefaultFilesApp.fromString(env_default_files);

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

    /// Resolve terminal executable name from current default-terminal setting.
    pub fn terminalCommand(self: DesktopProfile) []const u8 {
        return switch (self.default_terminal_app) {
            .foot => "foot",
            .alacritty => "alacritty",
            .kitty => "kitty",
        };
    }

    /// Resolve browser executable name from current default-browser setting.
    pub fn browserCommand(self: DesktopProfile) []const u8 {
        return switch (self.default_browser_app) {
            .firefox => "firefox",
            .chromium => "chromium",
            .brave => "brave-browser",
        };
    }

    /// Resolve file-manager executable name from current default-files setting.
    pub fn filesCommand(self: DesktopProfile) []const u8 {
        return switch (self.default_files_app) {
            .thunar => "thunar",
            .nautilus => "nautilus",
            .dolphin => "dolphin",
        };
    }
};

/// Resolve desktop profile path (`LUMINADE_PROFILE_PATH` or default).
pub fn profilePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_PROFILE_PATH")) |value| {
        return try allocator.dupe(u8, value);
    }

    return try allocator.dupe(u8, ".luminade/profile.conf");
}

/// Resolve per-device input rules path (`LUMINADE_DEVICE_PROFILES_PATH` or default).
pub fn deviceProfilesPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_DEVICE_PROFILES_PATH")) |value| {
        return try allocator.dupe(u8, value);
    }

    return try allocator.dupe(u8, ".luminade/device-profiles.conf");
}

/// Resolve theme profile override path (`LUMINADE_THEME_PROFILE_DIR` or default).
pub fn themeProfilePath(allocator: std.mem.Allocator, profile_name: ThemeProfileName) ![]u8 {
    if (std.posix.getenv("LUMINADE_THEME_PROFILE_DIR")) |dir| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}.conf", .{ dir, @tagName(profile_name) });
    }
    return try std.fmt.allocPrint(allocator, ".luminade/themes/{s}.conf", .{@tagName(profile_name)});
}

/// Load resolved theme profile (built-in fallback + optional local override file).
pub fn loadThemeProfile(allocator: std.mem.Allocator, desktop: DesktopProfile) !ThemeProfile {
    var theme = try ThemeProfile.builtIn(allocator, desktop.theme_profile, desktop.theme_mode);

    const path = try themeProfilePath(allocator, desktop.theme_profile);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return theme,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t\r");
        const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t\r");
        theme.setField(allocator, key, value) catch {};
    }

    return theme;
}

/// Persist concrete theme profile tokens to profile override file.
pub fn saveThemeProfile(allocator: std.mem.Allocator, theme: ThemeProfile) !void {
    const path = try themeProfilePath(allocator, theme.name);
    defer allocator.free(path);

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("# LuminaDE theme profile override\n");
    try writer.print("mode={s}\n", .{@tagName(theme.mode)});
    try writer.print("corner_radius={d}\n", .{theme.corner_radius});
    try writer.print("spacing_unit={d}\n", .{theme.spacing_unit});
    try writer.print("blur_sigma={d}\n", .{theme.blur_sigma});
    try writer.print("accent={s}\n", .{theme.accent});
}

/// Resolve shortcuts file path (`LUMINADE_SHORTCUTS_PATH` or default).
pub fn shortcutsPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_SHORTCUTS_PATH")) |value| {
        return try allocator.dupe(u8, value);
    }
    return try allocator.dupe(u8, ".luminade/shortcuts.conf");
}

fn defaultShortcutFor(action: ShortcutAction) []const u8 {
    return switch (action) {
        .launcher_toggle => "Super+Space",
        .terminal_open => "Super+Enter",
        .browser_open => "Super+B",
        .files_open => "Super+E",
        .settings_open => "Super+,",
    };
}

/// Load shortcut bindings with built-in fallback values.
pub fn loadShortcuts(allocator: std.mem.Allocator) !std.ArrayList(ShortcutBinding) {
    var bindings = std.ArrayList(ShortcutBinding).init(allocator);
    errdefer freeShortcuts(allocator, &bindings);

    const ordered_actions = [_]ShortcutAction{
        .launcher_toggle,
        .terminal_open,
        .browser_open,
        .files_open,
        .settings_open,
    };

    for (ordered_actions) |action| {
        try bindings.append(.{
            .action = action,
            .chord = try allocator.dupe(u8, defaultShortcutFor(action)),
        });
    }

    const path = try shortcutsPath(allocator);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return bindings,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t\r");
        const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t\r");
        const action = ShortcutAction.fromString(key) orelse continue;
        try setShortcutBinding(allocator, &bindings, action, value);
    }

    return bindings;
}

/// Replace one shortcut binding chord.
pub fn setShortcutBinding(
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(ShortcutBinding),
    action: ShortcutAction,
    chord: []const u8,
) !void {
    for (bindings.items) |*binding| {
        if (binding.action != action) continue;
        allocator.free(binding.chord);
        binding.chord = try allocator.dupe(u8, chord);
        return;
    }

    try bindings.append(.{
        .action = action,
        .chord = try allocator.dupe(u8, chord),
    });
}

/// Read shortcut chord for action.
pub fn shortcutBinding(bindings: []const ShortcutBinding, action: ShortcutAction) []const u8 {
    for (bindings) |binding| {
        if (binding.action == action) return binding.chord;
    }
    return defaultShortcutFor(action);
}

/// Persist current shortcut bindings.
pub fn saveShortcuts(allocator: std.mem.Allocator, bindings: []const ShortcutBinding) !void {
    const path = try shortcutsPath(allocator);
    defer allocator.free(path);

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("# LuminaDE shortcut bindings\n");
    for (bindings) |binding| {
        try writer.print("{s}={s}\n", .{ binding.action.asString(), binding.chord });
    }
}

/// Free memory owned by shortcut bindings.
pub fn freeShortcuts(allocator: std.mem.Allocator, bindings: *std.ArrayList(ShortcutBinding)) void {
    for (bindings.items) |binding| {
        allocator.free(binding.chord);
    }
    bindings.deinit();
}

/// Resolve stored language path (`LUMINADE_LANG_PATH` or default).
pub fn langPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("LUMINADE_LANG_PATH")) |value| {
        return try allocator.dupe(u8, value);
    }

    return try allocator.dupe(u8, ".luminade/lang.conf");
}

/// Persist selected UI language to runtime storage.
pub fn saveLang(allocator: std.mem.Allocator, lang: Lang) !void {
    const path = try langPath(allocator);
    defer allocator.free(path);

    const dir_name = std.fs.path.dirname(path) orelse ".";
    try std.fs.cwd().makePath(dir_name);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writer().print("{s}\n", .{@tagName(lang)});
}

fn loadLang(allocator: std.mem.Allocator) Lang {
    if (std.posix.getenv("LUMINADE_LANG")) |env_value| {
        return Lang.fromString(env_value);
    }

    const path = langPath(allocator) catch return .en;
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch return .en;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 128) catch return .en;
    defer allocator.free(content);

    const value = std.mem.trim(u8, content, " \t\r\n");
    if (value.len == 0) return .en;
    return Lang.fromString(value);
}

/// Parse common boolean strings (`1/true/yes/on`).
pub fn parseBool(value: []const u8) bool {
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn localeFilePath(allocator: std.mem.Allocator, lang: Lang) ![]u8 {
    if (std.posix.getenv("LUMINADE_LOCALES_DIR")) |dir| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ dir, @tagName(lang) });
    }
    return try std.fmt.allocPrint(allocator, "config/locales/{s}.json", .{@tagName(lang)});
}

/// Get localized string for `key` from language JSON, or `null` if missing.
pub fn localeGet(allocator: std.mem.Allocator, lang: Lang, key: []const u8) !?[]u8 {
    const path = try localeFilePath(allocator, lang);
    defer allocator.free(path);

    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 256 * 1024);
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const value = parsed.value.object.get(key) orelse return null;
    if (value != .string) return null;

    return try allocator.dupe(u8, value.string);
}

/// Resolve localized value with explicit fallback text.
pub fn localeGetOrFallback(
    allocator: std.mem.Allocator,
    lang: Lang,
    key: []const u8,
    fallback: []const u8,
) ![]u8 {
    const value = try localeGet(allocator, lang, key);
    if (value) |resolved| return resolved;
    return try allocator.dupe(u8, fallback);
}

/// Resolve localized value with EN fallback and finally key-name fallback.
pub fn localeGetWithEnFallback(
    allocator: std.mem.Allocator,
    lang: Lang,
    key: []const u8,
) ![]u8 {
    if (try localeGet(allocator, lang, key)) |resolved| {
        return resolved;
    }
    if (lang != .en) {
        if (try localeGet(allocator, .en, key)) |resolved_en| {
            return resolved_en;
        }
    }
    return try allocator.dupe(u8, key);
}

/// Built-in banner fallback strings used when locale file lookup fails.
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
        .welcome => switch (lang) {
            .en => "Welcome ready: complete first-run setup and explore LuminaDE.",
            .pl => "Powitanie gotowe: skonfiguruj pierwszy start i poznaj LuminaDE.",
        },
    };
}

/// Print startup banner for app kind using locale key lookup + fallback.
pub fn printBanner(kind: AppKind, cfg: RuntimeConfig) void {
    std.debug.print("LuminaDE/{s} [{s}]\n", .{ kind.asString(), @tagName(cfg.lang) });

    const key = switch (kind) {
        .panel => "panel.ready",
        .launcher => "launcher.ready",
        .settings => "settings.ready",
        .welcome => "welcome.ready",
    };

    const resolved = localeGet(cfg.allocator, cfg.lang, key) catch null;
    defer if (resolved) |msg| cfg.allocator.free(msg);

    std.debug.print("{s}\n", .{resolved orelse tr(kind, cfg.lang)});
}

/// Load runtime config (profile + language) from persisted files/env.
pub fn loadRuntimeConfig(allocator: std.mem.Allocator) RuntimeConfig {
    const profile = DesktopProfile.load(allocator) catch DesktopProfile.fromEnv();

    return .{
        .allocator = allocator,
        .lang = loadLang(allocator),
        .profile = profile,
    };
}

/// Print concise runtime summary for diagnostics.
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
        .welcome => std.debug.print(
            "Welcome mode=first-run onboarding, interaction={s}, launcher-width={d}\n",
            .{ @tagName(cfg.profile.interaction_mode), cfg.profile.launcher_width },
        ),
    }
}

/// Apply input profile via external tools (`riverctl`/fallback probes).
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

/// Execute system action using prioritized command fallbacks.
pub fn runSystemAction(allocator: std.mem.Allocator, action: SystemAction) !bool {
    return switch (action) {
        .lock_session => try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "loginctl", "lock-session" },
                &.{ "sh", "-lc", "command -v swaylock >/dev/null 2>&1 && swaylock" },
            },
        ),
        .suspend => try runSystemCommandFallback(allocator, &.{&.{ "systemctl", "suspend" }}),
        .logout => try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "loginctl", "terminate-user", std.posix.getenv("USER") orelse "" },
                &.{ "sh", "-lc", "pkill -KILL -u \"$USER\"" },
            },
        ),
        .audio_volume_up => try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+" },
                &.{ "pactl", "set-sink-volume", "@DEFAULT_SINK@", "+5%" },
            },
        ),
        .audio_volume_down => try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-" },
                &.{ "pactl", "set-sink-volume", "@DEFAULT_SINK@", "-5%" },
            },
        ),
        .audio_mute_toggle => try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle" },
                &.{ "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle" },
            },
        ),
        .open_network => try runSystemCommandFallback(
            allocator,
            &.{
                &.{ "nm-connection-editor" },
                &.{ "nmtui" },
                &.{ "iwgtk" },
            },
        ),
    };
}

fn runSystemCommandFallback(allocator: std.mem.Allocator, candidates: []const []const []const u8) !bool {
    for (candidates) |argv| {
        if (argv.len == 0) continue;
        if (try runCommandOk(allocator, argv)) return true;
    }
    return false;
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

/// Load per-device input rules from TSV file.
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

/// Free memory owned by rules returned from `loadDeviceInputRules`.
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
