const std = @import("std");

pub const SurfaceRole = enum {
    panel,
    launcher,
    settings,
};

pub const WindowDecoration = struct {
    enabled: bool,
    titlebar_height: u8,
    round_corners: bool,
    shadow: bool,
};

pub const ThemeTokens = struct {
    corner_radius: u8,
    spacing_unit: u8,
    blur_sigma: u8,

    pub fn modernDefault() ThemeTokens {
        return .{
            .corner_radius = 12,
            .spacing_unit = 8,
            .blur_sigma = 14,
        };
    }
};

pub const SurfaceSpec = struct {
    role: SurfaceRole,
    app_id: []const u8,
    width: u16,
    height: u16,
    keyboard_first: bool,
    fullscreen: bool,
    output_name: []const u8,
    scale: f32,
    decoration: WindowDecoration,
};

pub const OutputProfile = struct {
    name: []const u8,
    width: u16,
    height: u16,
    scale: f32,
    primary: bool,
};

pub const RenderSpec = struct {
    output_name: []const u8,
    physical_width: u16,
    physical_height: u16,
    scale: f32,
    logical_width: u16,
    logical_height: u16,
};

pub const WidgetKind = enum {
    row,
    column,
    text,
    badge,
    input,
    list_item,
    button,
    icon,
    toggle,
};

pub const GuiWidget = struct {
    id: []const u8,
    kind: WidgetKind,
    label: []const u8,
    rect: Rect,
    interactive: bool,
    hoverable: bool,
};

pub const GuiFrame = struct {
    title: []const u8,
    surface: SurfaceSpec,
    widgets: std.ArrayList(GuiWidget),

    pub fn init(allocator: std.mem.Allocator, title: []const u8, surface: SurfaceSpec) GuiFrame {
        return .{
            .title = title,
            .surface = surface,
            .widgets = std.ArrayList(GuiWidget).init(allocator),
        };
    }

    pub fn deinit(self: *GuiFrame) void {
        self.widgets.deinit();
    }
};

pub const DecorationButtonKind = enum {
    close,
    maximize,
    minimize,
};

pub const DecorationButton = struct {
    kind: DecorationButtonKind,
    rect: Rect,
};

pub const DecorationLayout = struct {
    enabled: bool,
    title: []const u8,
    titlebar_rect: Rect,
    drag_region_rect: Rect,
    buttons: [3]DecorationButton,
};

pub const NativePanelBackend = enum {
    layer_shell,
    fallback,
};

pub const NativePanelSession = struct {
    backend: NativePanelBackend,
    output_name: []const u8,
    panel_height: u8,
    anchor_top: bool,
    exclusive_zone: i32,
    runtime_dir: ?[]const u8,
    wayland_display: ?[]const u8,
};

pub const NativePanelRuntime = struct {
    next_native_attempt_ns: i64,
    native_failure_count: u8,
    native_protocol_error_streak: u8,
    circuit_open_until_ns: i64,
    last_fallback_write_ns: i64,
    last_frame_fingerprint: u64,
    has_last_frame_fingerprint: bool,
    last_log_ns: i64,
    suppressed_log_count: u32,

    pub fn init() NativePanelRuntime {
        return .{
            .next_native_attempt_ns = 0,
            .native_failure_count = 0,
            .native_protocol_error_streak = 0,
            .circuit_open_until_ns = 0,
            .last_fallback_write_ns = 0,
            .last_frame_fingerprint = 0,
            .has_last_frame_fingerprint = false,
            .last_log_ns = 0,
            .suppressed_log_count = 0,
        };
    }
};

pub const LayoutMode = enum {
    tiling,
    floating,
    hybrid,
};

pub const LayoutAlgorithm = enum {
    master_stack,
    grid,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: u16,
    h: u16,
};

pub const WindowState = struct {
    id: []const u8,
    role: SurfaceRole,
    rect: Rect,
    desired_w: u16,
    desired_h: u16,
    is_focused: bool,
    is_minimized: bool,
    is_floating: bool,
    z_index: i32,
};

pub const LayoutConfig = struct {
    spacing: u8,
    outer_gap: u8,
    master_ratio_percent: u8,
    algorithm: LayoutAlgorithm,
    float_overlays_in_hybrid: bool,

    pub fn modernDefault(tokens: ThemeTokens) LayoutConfig {
        return .{
            .spacing = tokens.spacing_unit,
            .outer_gap = tokens.spacing_unit,
            .master_ratio_percent = 60,
            .algorithm = .master_stack,
            .float_overlays_in_hybrid = true,
        };
    }
};

pub fn addWidget(frame: *GuiFrame, widget: GuiWidget) !void {
    try frame.widgets.append(widget);
}

pub fn decorationLayoutForSurface(spec: SurfaceSpec) DecorationLayout {
    if (!spec.decoration.enabled) {
        return .{
            .enabled = false,
            .title = appTitleForRole(spec.role),
            .titlebar_rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .drag_region_rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .buttons = .{
                .{ .kind = .close, .rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 } },
                .{ .kind = .maximize, .rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 } },
                .{ .kind = .minimize, .rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 } },
            },
        };
    }

    const title_h = @as(i32, @intCast(spec.decoration.titlebar_height));
    const button_size_i32 = @as(i32, @max(@as(u8, 14), @min(@as(u8, 20), spec.decoration.titlebar_height -| 10)));
    const button_size = @as(u16, @intCast(button_size_i32));
    const margin: i32 = 8;
    const spacing: i32 = 6;
    const top = @divTrunc(@max(@as(i32, 0), title_h - button_size_i32), 2);
    const width_i = @as(i32, @intCast(spec.width));

    const close_x = width_i - margin - button_size_i32;
    const max_x = close_x - spacing - button_size_i32;
    const min_x = max_x - spacing - button_size_i32;

    return .{
        .enabled = true,
        .title = appTitleForRole(spec.role),
        .titlebar_rect = .{ .x = 0, .y = 0, .w = spec.width, .h = spec.decoration.titlebar_height },
        .drag_region_rect = .{
            .x = margin,
            .y = 0,
            .w = @as(u16, @intCast(@max(@as(i32, 1), min_x - margin - spacing))),
            .h = spec.decoration.titlebar_height,
        },
        .buttons = .{
            .{ .kind = .close, .rect = .{ .x = close_x, .y = top, .w = button_size, .h = button_size } },
            .{ .kind = .maximize, .rect = .{ .x = max_x, .y = top, .w = button_size, .h = button_size } },
            .{ .kind = .minimize, .rect = .{ .x = min_x, .y = top, .w = button_size, .h = button_size } },
        },
    };
}

pub fn printGuiFrame(frame: *const GuiFrame) void {
    std.debug.print(
        "[gui] frame='{s}' role={s} output={s} size={d}x{d} widgets={d}\n",
        .{
            frame.title,
            @tagName(frame.surface.role),
            frame.surface.output_name,
            frame.surface.width,
            frame.surface.height,
            frame.widgets.items.len,
        },
    );

    const decor = decorationLayoutForSurface(frame.surface);
    printDecorationLayout(decor);

    for (frame.widgets.items) |widget| {
        std.debug.print(
            "  [widget] id={s} kind={s} rect=({d},{d},{d}x{d}) interactive={any} hoverable={any} label='{s}'\n",
            .{
                widget.id,
                @tagName(widget.kind),
                widget.rect.x,
                widget.rect.y,
                widget.rect.w,
                widget.rect.h,
                widget.interactive,
                widget.hoverable,
                widget.label,
            },
        );
    }
}

pub fn printDecorationLayout(layout: DecorationLayout) void {
    if (!layout.enabled) {
        std.debug.print("  [decor] disabled\n", .{});
        return;
    }

    std.debug.print(
        "  [decor] title='{s}' titlebar=({d},{d},{d}x{d}) drag=({d},{d},{d}x{d})\n",
        .{
            layout.title,
            layout.titlebar_rect.x,
            layout.titlebar_rect.y,
            layout.titlebar_rect.w,
            layout.titlebar_rect.h,
            layout.drag_region_rect.x,
            layout.drag_region_rect.y,
            layout.drag_region_rect.w,
            layout.drag_region_rect.h,
        },
    );

    for (layout.buttons) |button| {
        std.debug.print(
            "    [button] {s} rect=({d},{d},{d}x{d})\n",
            .{ @tagName(button.kind), button.rect.x, button.rect.y, button.rect.w, button.rect.h },
        );
    }
}

pub fn initNativePanelSession(
    allocator: std.mem.Allocator,
    output: OutputProfile,
    panel_height: u8,
) !NativePanelSession {
    _ = allocator;

    const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR");
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY");
    const wayland_ready = runtime_dir != null and wayland_display != null;

    return .{
        .backend = if (wayland_ready) .layer_shell else .fallback,
        .output_name = output.name,
        .panel_height = panel_height,
        .anchor_top = true,
        .exclusive_zone = panel_height,
        .runtime_dir = runtime_dir,
        .wayland_display = wayland_display,
    };
}

pub fn commitNativePanelFrame(
    allocator: std.mem.Allocator,
    runtime: *NativePanelRuntime,
    session: NativePanelSession,
    frame: *const GuiFrame,
) !void {
    const now_ns = std.time.nanoTimestamp();
    const fingerprint = computePanelFrameFingerprint(session, frame);

    if (session.backend == .layer_shell and session.runtime_dir != null and session.wayland_display != null) {
        if (canAttemptNativeCommit(runtime, now_ns)) {
            const native_ok = tryLayerShellNativeCommit(allocator, session, frame) catch |err| {
                markNativeProtocolError(runtime, now_ns);
                logNativeEvent(
                    runtime,
                    now_ns,
                    "[native-panel] backend=layer_shell output={s} protocol-error={s} failures={d} circuit-open-ms={d}\n",
                    .{ session.output_name, @errorName(err), runtime.native_failure_count, circuitRemainingMs(runtime, now_ns) },
                );
                false
            };

            if (native_ok) {
                markNativeSuccess(runtime, now_ns, fingerprint);
                logNativeEvent(
                    runtime,
                    now_ns,
                    "[native-panel] backend=layer_shell output={s} widgets={d} native-path=ok\n",
                    .{ session.output_name, frame.widgets.items.len },
                );
                return;
            }

            if (runtime.native_protocol_error_streak == 0) {
                markNativeFailure(runtime, now_ns);
                logNativeEvent(
                    runtime,
                    now_ns,
                    "[native-panel] backend=layer_shell output={s} native-path=failed failures={d}\n",
                    .{ session.output_name, runtime.native_failure_count },
                );
            }
        } else {
            logNativeEvent(
                runtime,
                now_ns,
                "[native-panel] backend=layer_shell output={s} native-path=throttled\n",
                .{session.output_name},
            );
        }
    }

    if (!shouldWriteFallback(runtime, now_ns, fingerprint)) return;
    runtime.last_fallback_write_ns = now_ns;
    runtime.last_frame_fingerprint = fingerprint;
    runtime.has_last_frame_fingerprint = true;

    const state_path = std.posix.getenv("LUMINADE_NATIVE_PANEL_STATE") orelse ".luminade/native-panel-state.tsv";
    const parent = std.fs.path.dirname(state_path) orelse ".";
    try std.fs.cwd().makePath(parent);

    const temp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{state_path});
    defer allocator.free(temp_path);

    var file = try std.fs.cwd().createFile(temp_path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try writer.print("backend\t{s}\n", .{@tagName(.fallback)});
    try writer.print("output\t{s}\n", .{session.output_name});
    try writer.print("panel_height\t{d}\n", .{session.panel_height});
    try writer.print("anchor_top\t{s}\n", .{if (session.anchor_top) "true" else "false"});
    try writer.print("exclusive_zone\t{d}\n", .{session.exclusive_zone});
    try writer.print("runtime_dir\t{s}\n", .{session.runtime_dir orelse ""});
    try writer.print("wayland_display\t{s}\n", .{session.wayland_display orelse ""});
    try writer.print("widgets\t{d}\n", .{frame.widgets.items.len});

    for (frame.widgets.items) |widget| {
        try writer.print(
            "widget\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\n",
            .{ widget.id, @tagName(widget.kind), widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h },
        );
    }

    try file.sync();
    try std.fs.cwd().rename(temp_path, state_path);

    logNativeEvent(
        runtime,
        now_ns,
        "[native-panel] backend=fallback output={s} widgets={d} state={s}\n",
        .{ session.output_name, frame.widgets.items.len, state_path },
    );
}

fn canAttemptNativeCommit(runtime: *const NativePanelRuntime, now_ns: i64) bool {
    return now_ns >= runtime.next_native_attempt_ns and now_ns >= runtime.circuit_open_until_ns;
}

fn markNativeSuccess(runtime: *NativePanelRuntime, now_ns: i64, fingerprint: u64) void {
    runtime.next_native_attempt_ns = now_ns;
    runtime.native_failure_count = 0;
    runtime.native_protocol_error_streak = 0;
    runtime.circuit_open_until_ns = 0;
    runtime.last_frame_fingerprint = fingerprint;
    runtime.has_last_frame_fingerprint = true;
}

fn markNativeFailure(runtime: *NativePanelRuntime, now_ns: i64) void {
    if (runtime.native_failure_count < std.math.maxInt(u8)) {
        runtime.native_failure_count += 1;
    }

    const capped_failures = @min(runtime.native_failure_count, 8);
    const shift: u6 = @intCast(capped_failures);
    const base_ms: i64 = 250;
    const max_ms: i64 = 30_000;
    var backoff_ms = base_ms * (@as(i64, 1) << shift);
    if (backoff_ms > max_ms) backoff_ms = max_ms;

    runtime.next_native_attempt_ns = now_ns + backoff_ms * std.time.ns_per_ms;
}

fn markNativeProtocolError(runtime: *NativePanelRuntime, now_ns: i64) void {
    markNativeFailure(runtime, now_ns);

    if (runtime.native_protocol_error_streak < std.math.maxInt(u8)) {
        runtime.native_protocol_error_streak += 1;
    }

    const breaker_threshold: u8 = 4;
    const breaker_open_ns: i64 = 60 * std.time.ns_per_s;
    if (runtime.native_protocol_error_streak >= breaker_threshold) {
        runtime.circuit_open_until_ns = now_ns + breaker_open_ns;
        runtime.native_protocol_error_streak = 0;
    }
}

fn circuitRemainingMs(runtime: *const NativePanelRuntime, now_ns: i64) i64 {
    if (runtime.circuit_open_until_ns <= now_ns) return 0;
    return @divTrunc(runtime.circuit_open_until_ns - now_ns, std.time.ns_per_ms);
}

fn logNativeEvent(runtime: *NativePanelRuntime, now_ns: i64, comptime fmt: []const u8, args: anytype) void {
    const min_gap_ns: i64 = 250 * std.time.ns_per_ms;
    if (runtime.last_log_ns != 0 and now_ns - runtime.last_log_ns < min_gap_ns) {
        if (runtime.suppressed_log_count < std.math.maxInt(u32)) {
            runtime.suppressed_log_count += 1;
        }
        return;
    }

    if (runtime.suppressed_log_count > 0) {
        std.debug.print("[native-panel] log-throttle suppressed={d}\n", .{runtime.suppressed_log_count});
        runtime.suppressed_log_count = 0;
    }

    runtime.last_log_ns = now_ns;
    std.debug.print(fmt, args);
}

fn shouldWriteFallback(runtime: *const NativePanelRuntime, now_ns: i64, fingerprint: u64) bool {
    if (!runtime.has_last_frame_fingerprint) return true;
    if (runtime.last_frame_fingerprint != fingerprint) return true;

    const min_gap_ns = 500 * std.time.ns_per_ms;
    return (now_ns - runtime.last_fallback_write_ns) >= min_gap_ns;
}

fn computePanelFrameFingerprint(session: NativePanelSession, frame: *const GuiFrame) u64 {
    var hasher = std.hash.Wyhash.init(0xC0FFEE);

    hasher.update(session.output_name);
    hasher.update(frame.title);
    hasher.update(@tagName(session.backend));
    hasher.update(frame.surface.output_name);
    hashU16(&hasher, frame.surface.width);
    hashU16(&hasher, frame.surface.height);
    hashU8(&hasher, session.panel_height);

    for (frame.widgets.items) |widget| {
        hasher.update(widget.id);
        hasher.update(@tagName(widget.kind));
        hashI32(&hasher, widget.rect.x);
        hashI32(&hasher, widget.rect.y);
        hashU16(&hasher, widget.rect.w);
        hashU16(&hasher, widget.rect.h);
    }

    return hasher.final();
}

fn hashU8(hasher: *std.hash.Wyhash, value: u8) void {
    hasher.update(&[_]u8{value});
}

fn hashU16(hasher: *std.hash.Wyhash, value: u16) void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    hasher.update(&buf);
}

fn hashI32(hasher: *std.hash.Wyhash, value: i32) void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .little);
    hasher.update(&buf);
}

const RegistryGlobals = struct {
    compositor_name: ?u32,
    compositor_version: u32,
    layer_shell_name: ?u32,
    layer_shell_version: u32,
};

fn tryLayerShellNativeCommit(
    allocator: std.mem.Allocator,
    session: NativePanelSession,
    frame: *const GuiFrame,
) !bool {
    if (session.runtime_dir == null or session.wayland_display == null) return false;

    const socket_path = try std.fs.path.join(allocator, &.{ session.runtime_dir.?, session.wayland_display.? });
    defer allocator.free(socket_path);

    var stream = std.net.connectUnixSocket(socket_path) catch return false;
    defer stream.close();

    const registry_id: u32 = 2;
    const callback_id: u32 = 3;

    try sendDisplayGetRegistry(allocator, &stream, registry_id);
    try sendDisplaySync(allocator, &stream, callback_id);

    const globals = try readRegistryGlobalsUntilDone(allocator, &stream, registry_id, callback_id);
    if (globals.compositor_name == null or globals.layer_shell_name == null) return false;

    const smoke_create = shouldRunLayerShellSmokeCreate();
    if (smoke_create) {
        try runLayerShellSmokeCreate(allocator, &stream, session, globals, frame);
    }

    return true;
}

fn shouldRunLayerShellSmokeCreate() bool {
    const env = std.posix.getenv("LUMINADE_LAYER_SHELL_SMOKE_CREATE") orelse return true;
    return std.mem.eql(u8, env, "1") or std.mem.eql(u8, env, "true") or std.mem.eql(u8, env, "on");
}

fn runLayerShellSmokeCreate(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    session: NativePanelSession,
    globals: RegistryGlobals,
    frame: *const GuiFrame,
) !void {
    _ = frame;

    const compositor_id: u32 = 4;
    const layer_shell_id: u32 = 5;
    const wl_surface_id: u32 = 6;
    const layer_surface_id: u32 = 7;

    try sendRegistryBind(allocator, stream, 2, globals.compositor_name.?, "wl_compositor", @min(globals.compositor_version, 6), compositor_id);
    try sendRegistryBind(allocator, stream, 2, globals.layer_shell_name.?, "zwlr_layer_shell_v1", @min(globals.layer_shell_version, 4), layer_shell_id);

    try sendCompositorCreateSurface(allocator, stream, compositor_id, wl_surface_id);
    try sendLayerShellGetLayerSurface(allocator, stream, layer_shell_id, layer_surface_id, wl_surface_id, 0, 2, "luminade-panel");
    try sendLayerSurfaceSetSize(allocator, stream, layer_surface_id, 0, session.panel_height);
    try sendLayerSurfaceSetAnchor(allocator, stream, layer_surface_id, layerAnchorTopLeftRight());
    try sendLayerSurfaceSetExclusiveZone(allocator, stream, layer_surface_id, @as(i32, @intCast(session.exclusive_zone)));
    try sendSurfaceCommit(allocator, stream, wl_surface_id);
}

fn layerAnchorTopLeftRight() u32 {
    return 1 | 4 | 8;
}

fn readRegistryGlobalsUntilDone(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    registry_id: u32,
    callback_id: u32,
) !RegistryGlobals {
    var result = RegistryGlobals{
        .compositor_name = null,
        .compositor_version = 1,
        .layer_shell_name = null,
        .layer_shell_version = 1,
    };

    var reader = stream.reader();

    while (true) {
        var header: [8]u8 = undefined;
        try reader.readNoEof(&header);

        const object_id = readU32Le(header[0..4]);
        const word = readU32Le(header[4..8]);
        const size = @as(u16, @intCast(word >> 16));
        const opcode = @as(u16, @intCast(word & 0xffff));

        if (size < 8) return error.InvalidWaylandMessage;

        const payload_len: usize = size - 8;
        var payload = try allocator.alloc(u8, payload_len);
        defer allocator.free(payload);
        if (payload_len > 0) try reader.readNoEof(payload);

        if (object_id == registry_id and opcode == 0) {
            var off: usize = 0;
            if (payload.len < 12) continue;

            const name = readU32Le(payload[off..][0..4]);
            off += 4;
            const interface = try parseWaylandString(payload, &off);
            const version = readU32Le(payload[off..][0..4]);

            if (std.mem.eql(u8, interface, "wl_compositor")) {
                result.compositor_name = name;
                result.compositor_version = version;
            } else if (std.mem.eql(u8, interface, "zwlr_layer_shell_v1")) {
                result.layer_shell_name = name;
                result.layer_shell_version = version;
            }
        }

        if (object_id == callback_id and opcode == 0) break;
    }

    return result;
}

fn parseWaylandString(payload: []const u8, offset: *usize) ![]const u8 {
    if (payload.len < offset.* + 4) return error.InvalidWaylandMessage;
    const raw_len = readU32Le(payload[offset.*..][0..4]);
    offset.* += 4;

    const text_len: usize = @as(usize, @intCast(raw_len));
    if (text_len == 0) return "";
    if (payload.len < offset.* + text_len) return error.InvalidWaylandMessage;

    const text_full = payload[offset.* .. offset.* + text_len];
    const no_null = text_full[0 .. text_len - 1];
    offset.* += text_len;

    const rem = offset.* % 4;
    if (rem != 0) offset.* += (4 - rem);

    if (offset.* > payload.len) return error.InvalidWaylandMessage;
    return no_null;
}

fn sendDisplayGetRegistry(allocator: std.mem.Allocator, stream: *std.net.Stream, registry_id: u32) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, registry_id);
    try sendWaylandRequest(allocator, stream, 1, 1, payload.items);
}

fn sendDisplaySync(allocator: std.mem.Allocator, stream: *std.net.Stream, callback_id: u32) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, callback_id);
    try sendWaylandRequest(allocator, stream, 1, 0, payload.items);
}

fn sendRegistryBind(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    registry_id: u32,
    name: u32,
    interface_name: []const u8,
    version: u32,
    new_id: u32,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, name);
    try appendWaylandString(&payload, interface_name);
    try appendU32Le(&payload, version);
    try appendU32Le(&payload, new_id);
    try sendWaylandRequest(allocator, stream, registry_id, 0, payload.items);
}

fn sendCompositorCreateSurface(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    compositor_id: u32,
    new_surface_id: u32,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, new_surface_id);
    try sendWaylandRequest(allocator, stream, compositor_id, 0, payload.items);
}

fn sendLayerShellGetLayerSurface(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    layer_shell_id: u32,
    layer_surface_id: u32,
    wl_surface_id: u32,
    wl_output_id: u32,
    layer: u32,
    namespace_name: []const u8,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, layer_surface_id);
    try appendU32Le(&payload, wl_surface_id);
    try appendU32Le(&payload, wl_output_id);
    try appendU32Le(&payload, layer);
    try appendWaylandString(&payload, namespace_name);
    try sendWaylandRequest(allocator, stream, layer_shell_id, 1, payload.items);
}

fn sendLayerSurfaceSetSize(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    layer_surface_id: u32,
    width: u32,
    height: u8,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, width);
    try appendU32Le(&payload, height);
    try sendWaylandRequest(allocator, stream, layer_surface_id, 0, payload.items);
}

fn sendLayerSurfaceSetAnchor(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    layer_surface_id: u32,
    anchor_bits: u32,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendU32Le(&payload, anchor_bits);
    try sendWaylandRequest(allocator, stream, layer_surface_id, 1, payload.items);
}

fn sendLayerSurfaceSetExclusiveZone(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    layer_surface_id: u32,
    zone: i32,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    try appendI32Le(&payload, zone);
    try sendWaylandRequest(allocator, stream, layer_surface_id, 2, payload.items);
}

fn sendSurfaceCommit(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    wl_surface_id: u32,
) !void {
    try sendWaylandRequest(allocator, stream, wl_surface_id, 6, &.{});
}

fn sendWaylandRequest(
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    object_id: u32,
    opcode: u16,
    payload: []const u8,
) !void {
    const size_u32 = 8 + payload.len;
    if (size_u32 > std.math.maxInt(u16)) return error.WaylandMessageTooLarge;

    var msg = std.ArrayList(u8).init(allocator);
    defer msg.deinit();

    try appendU32Le(&msg, object_id);
    try appendU32Le(&msg, (@as(u32, @intCast(size_u32)) << 16) | @as(u32, opcode));
    try msg.appendSlice(payload);

    try stream.writer().writeAll(msg.items);
}

fn appendWaylandString(buf: *std.ArrayList(u8), text: []const u8) !void {
    const len_with_null: usize = text.len + 1;
    try appendU32Le(buf, len_with_null);
    try buf.appendSlice(text);
    try buf.append(0);

    const pad = (4 - (len_with_null % 4)) % 4;
    var i: usize = 0;
    while (i < pad) : (i += 1) try buf.append(0);
}

fn appendI32Le(buf: *std.ArrayList(u8), value: i32) !void {
    try appendU32Le(buf, @bitCast(value));
}

fn appendU32Le(buf: *std.ArrayList(u8), value: u32) !void {
    try buf.append(@intCast(value & 0xff));
    try buf.append(@intCast((value >> 8) & 0xff));
    try buf.append(@intCast((value >> 16) & 0xff));
    try buf.append(@intCast((value >> 24) & 0xff));
}

fn readU32Le(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

pub const OutputWatcher = struct {
    allocator: std.mem.Allocator,
    outputs: std.ArrayList(OutputProfile),
    backend: OutputEventBackend,
    wayland_socket: ?std.fs.File,
    monitor_child: ?std.process.Child,
    monitor_stdout: ?std.fs.File,

    pub const OutputEventBackend = enum {
        wayland,
        udev,
        poll,
    };

    pub fn init(allocator: std.mem.Allocator) !OutputWatcher {
        var watcher = OutputWatcher{
            .allocator = allocator,
            .outputs = try detectOutputs(allocator),
            .backend = .poll,
            .wayland_socket = null,
            .monitor_child = null,
            .monitor_stdout = null,
        };

        if (watcher.tryEnableWaylandBackend()) {
            return watcher;
        }
        try watcher.tryEnableUdevBackend();
        return watcher;
    }

    pub fn initWithBackend(allocator: std.mem.Allocator, backend: OutputEventBackend) !OutputWatcher {
        var watcher = OutputWatcher{
            .allocator = allocator,
            .outputs = try detectOutputs(allocator),
            .backend = .poll,
            .wayland_socket = null,
            .monitor_child = null,
            .monitor_stdout = null,
        };

        switch (backend) {
            .wayland => {
                if (!watcher.tryEnableWaylandBackend()) {
                    return error.WaylandBackendUnavailable;
                }
            },
            .udev => try watcher.tryEnableUdevBackend(),
            .poll => watcher.backend = .poll,
        }

        return watcher;
    }

    pub fn waitForEvent(self: *OutputWatcher, timeout_ms: i32) !bool {
        return switch (self.backend) {
            .wayland => try self.waitForWaylandEvent(timeout_ms),
            .udev => try self.waitForUdevEvent(timeout_ms),
            .poll => blk: {
                if (timeout_ms > 0) {
                    const ns = @as(u64, @intCast(timeout_ms)) * std.time.ns_per_ms;
                    std.time.sleep(ns);
                }
                break :blk true;
            },
        };
    }

    pub fn backendName(self: *const OutputWatcher) []const u8 {
        return switch (self.backend) {
            .wayland => "wayland",
            .udev => "udev",
            .poll => "poll",
        };
    }

    fn tryEnableWaylandBackend(self: *OutputWatcher) bool {
        const display_name = std.posix.getenv("WAYLAND_DISPLAY") orelse return false;
        const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return false;

        const socket_path = std.fs.path.join(self.allocator, &.{ runtime_dir, display_name }) catch return false;
        defer self.allocator.free(socket_path);

        const file = std.fs.openFileAbsolute(socket_path, .{}) catch return false;
        self.wayland_socket = file;
        self.backend = .wayland;
        return true;
    }

    fn waitForWaylandEvent(self: *OutputWatcher, timeout_ms: i32) !bool {
        const file = self.wayland_socket orelse return true;

        var poll_fds = [_]std.posix.pollfd{.{
            .fd = file.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const ready = try std.posix.poll(&poll_fds, timeout_ms);
        if (ready > 0 and (poll_fds[0].revents & std.posix.POLL.IN) != 0) {
            var buf: [2048]u8 = undefined;
            _ = file.read(&buf) catch {};
            return true;
        }

        return true;
    }

    fn tryEnableUdevBackend(self: *OutputWatcher) !void {
        var child = std.process.Child.init(
            &.{ "udevadm", "monitor", "--udev", "--subsystem-match=drm" },
            self.allocator,
        );
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch {
            self.backend = .poll;
            self.monitor_child = null;
            self.monitor_stdout = null;
            return;
        };

        self.monitor_stdout = child.stdout;
        self.monitor_child = child;
        self.backend = if (self.monitor_stdout != null) .udev else .poll;
    }

    fn waitForUdevEvent(self: *OutputWatcher, timeout_ms: i32) !bool {
        const file = self.monitor_stdout orelse return true;

        var poll_fds = [_]std.posix.pollfd{.{
            .fd = file.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const ready = try std.posix.poll(&poll_fds, timeout_ms);
        if (ready <= 0) return false;
        if ((poll_fds[0].revents & std.posix.POLL.IN) == 0) return false;

        var buf: [1024]u8 = undefined;
        const n = file.read(&buf) catch return true;
        if (n == 0) return true;

        const chunk = buf[0..n];
        return std.mem.indexOf(u8, chunk, "drm") != null or std.mem.indexOf(u8, chunk, "change") != null;
    }

    fn stopBackend(self: *OutputWatcher) void {
        if (self.wayland_socket) |file| file.close();
        self.wayland_socket = null;

        if (self.monitor_stdout) |file| file.close();
        self.monitor_stdout = null;

        if (self.monitor_child) |*child| {
            _ = child.kill() catch {};
            _ = child.wait() catch {};
        }
        self.monitor_child = null;
    }

    pub fn deinit(self: *OutputWatcher) void {
        self.stopBackend();
        freeOutputs(self.allocator, &self.outputs);
    }

    pub fn poll(self: *OutputWatcher) !bool {
        var next = try detectOutputs(self.allocator);
        errdefer freeOutputs(self.allocator, &next);

        if (outputsEqual(self.outputs.items, next.items)) {
            freeOutputs(self.allocator, &next);
            return false;
        }

        freeOutputs(self.allocator, &self.outputs);
        self.outputs = next;
        return true;
    }
};

pub fn applyWindowLayout(
    allocator: std.mem.Allocator,
    mode: LayoutMode,
    output: OutputProfile,
    windows: []WindowState,
    cfg: LayoutConfig,
) !void {
    const area = contentArea(output, cfg.outer_gap);

    var tiled_indices = std.ArrayList(usize).init(allocator);
    defer tiled_indices.deinit();

    var floating_indices = std.ArrayList(usize).init(allocator);
    defer floating_indices.deinit();

    for (windows, 0..) |window, idx| {
        if (window.is_minimized) continue;

        const overlay_role = window.role == .launcher or window.role == .settings;
        const force_floating = mode == .floating or
            window.is_floating or
            (mode == .hybrid and cfg.float_overlays_in_hybrid and overlay_role);

        if (force_floating) {
            try floating_indices.append(idx);
        } else {
            try tiled_indices.append(idx);
        }
    }

    switch (cfg.algorithm) {
        .master_stack => layoutMasterStack(windows, tiled_indices.items, area, cfg.spacing, cfg.master_ratio_percent),
        .grid => layoutGrid(windows, tiled_indices.items, area, cfg.spacing),
    }

    for (floating_indices.items, 0..) |idx, z| {
        var rect = windows[idx].rect;
        if (rect.w == 0) rect.w = if (windows[idx].desired_w > 0) windows[idx].desired_w else 640;
        if (rect.h == 0) rect.h = if (windows[idx].desired_h > 0) windows[idx].desired_h else 480;
        windows[idx].rect = clampRectToArea(rect, area);
        windows[idx].z_index = 100 + @as(i32, @intCast(z));
    }

    var focused_idx: ?usize = null;
    for (windows, 0..) |window, idx| {
        if (window.is_focused and !window.is_minimized) {
            focused_idx = idx;
            break;
        }
    }
    if (focused_idx) |idx| {
        windows[idx].z_index = 1000;
    }
}

pub fn detectOutputs(allocator: std.mem.Allocator) !std.ArrayList(OutputProfile) {
    var outputs = std.ArrayList(OutputProfile).init(allocator);

    if (try detectOutputsFromEnv(allocator, &outputs)) return outputs;
    if (try detectOutputsFromWlrRandr(allocator, &outputs)) return outputs;
    if (try detectOutputsFromXrandr(allocator, &outputs)) return outputs;

    try outputs.append(try defaultOutputOwned(allocator));
    return outputs;
}

fn contentArea(output: OutputProfile, outer_gap: u8) Rect {
    const inset = @as(i32, @intCast(outer_gap));
    const total_w = @as(i32, @intCast(output.width));
    const total_h = @as(i32, @intCast(output.height));

    const w_i = @max(@as(i32, 1), total_w - inset * 2);
    const h_i = @max(@as(i32, 1), total_h - inset * 2);

    return .{
        .x = inset,
        .y = inset,
        .w = @as(u16, @intCast(w_i)),
        .h = @as(u16, @intCast(h_i)),
    };
}

fn layoutMasterStack(
    windows: []WindowState,
    tiled_indices: []const usize,
    area: Rect,
    spacing: u8,
    master_ratio_percent: u8,
) void {
    if (tiled_indices.len == 0) return;

    if (tiled_indices.len == 1) {
        const idx = tiled_indices[0];
        windows[idx].rect = area;
        windows[idx].z_index = 0;
        return;
    }

    const gap = @as(i32, @intCast(spacing));
    const total_w = @as(i32, @intCast(area.w));
    const total_h = @as(i32, @intCast(area.h));

    const ratio = @as(i32, @intCast(master_ratio_percent));
    var master_w = @divTrunc(total_w * ratio, 100);
    master_w = @max(master_w, 1);
    master_w = @min(master_w, total_w - 1);

    const stack_w = @max(@as(i32, 1), total_w - master_w - gap);

    const master_idx = tiled_indices[0];
    windows[master_idx].rect = .{
        .x = area.x,
        .y = area.y,
        .w = @as(u16, @intCast(master_w)),
        .h = area.h,
    };
    windows[master_idx].z_index = 0;

    const stack_count = tiled_indices.len - 1;
    const gaps_total = gap * @as(i32, @intCast(if (stack_count > 0) stack_count - 1 else 0));
    var usable_h = total_h - gaps_total;
    if (usable_h < @as(i32, @intCast(stack_count))) usable_h = @as(i32, @intCast(stack_count));

    var y = area.y;
    var remaining_h = usable_h;
    var remaining_n = stack_count;

    for (tiled_indices[1..], 0..) |idx, order| {
        const current_h = if (remaining_n == 1)
            remaining_h
        else
            @divTrunc(remaining_h, @as(i32, @intCast(remaining_n)));

        windows[idx].rect = .{
            .x = area.x + master_w + gap,
            .y = y,
            .w = @as(u16, @intCast(stack_w)),
            .h = @as(u16, @intCast(@max(@as(i32, 1), current_h))),
        };
        windows[idx].z_index = @as(i32, @intCast(order + 1));

        y += current_h + gap;
        remaining_h -= current_h;
        remaining_n -= 1;
    }
}

fn layoutGrid(
    windows: []WindowState,
    tiled_indices: []const usize,
    area: Rect,
    spacing: u8,
) void {
    if (tiled_indices.len == 0) return;

    const count = tiled_indices.len;
    const cols = std.math.sqrt(@as(f64, @floatFromInt(count)));
    const cols_u = @max(@as(usize, 1), @as(usize, @intFromFloat(@ceil(cols))));
    const rows_u = @divTrunc(count + cols_u - 1, cols_u);

    const gap = @as(i32, @intCast(spacing));
    const total_w = @as(i32, @intCast(area.w));
    const total_h = @as(i32, @intCast(area.h));

    const cols_i = @as(i32, @intCast(cols_u));
    const rows_i = @as(i32, @intCast(rows_u));

    const cell_w = @max(@as(i32, 1), @divTrunc(total_w - gap * (cols_i - 1), cols_i));
    const cell_h = @max(@as(i32, 1), @divTrunc(total_h - gap * (rows_i - 1), rows_i));

    for (tiled_indices, 0..) |idx, i| {
        const col = @as(i32, @intCast(i % cols_u));
        const row = @as(i32, @intCast(i / cols_u));

        windows[idx].rect = .{
            .x = area.x + col * (cell_w + gap),
            .y = area.y + row * (cell_h + gap),
            .w = @as(u16, @intCast(cell_w)),
            .h = @as(u16, @intCast(cell_h)),
        };
        windows[idx].z_index = @as(i32, @intCast(i));
    }
}

fn clampRectToArea(rect: Rect, area: Rect) Rect {
    const min_w: i32 = 120;
    const min_h: i32 = 80;

    var width = @max(min_w, @as(i32, @intCast(rect.w)));
    var height = @max(min_h, @as(i32, @intCast(rect.h)));

    const max_w = @as(i32, @intCast(area.w));
    const max_h = @as(i32, @intCast(area.h));
    width = @min(width, max_w);
    height = @min(height, max_h);

    const max_x = area.x + max_w - width;
    const max_y = area.y + max_h - height;

    const x = @max(area.x, @min(max_x, rect.x));
    const y = @max(area.y, @min(max_y, rect.y));

    return .{
        .x = x,
        .y = y,
        .w = @as(u16, @intCast(width)),
        .h = @as(u16, @intCast(height)),
    };
}

fn detectOutputsFromWlrRandr(allocator: std.mem.Allocator, outputs: *std.ArrayList(OutputProfile)) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "wlr-randr" },
        .max_output_bytes = 1024 * 1024,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return false,
        else => return false,
    }

    var any = false;
    var current_name: ?[]const u8 = null;
    var width: u16 = 1920;
    var height: u16 = 1080;
    var scale: f32 = 1.0;
    var enabled = false;

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;

        if (line[0] != ' ') {
            if (current_name) |name| {
                if (enabled) {
                    try outputs.append(.{
                        .name = try allocator.dupe(u8, name),
                        .width = width,
                        .height = height,
                        .scale = scale,
                        .primary = !any,
                    });
                    any = true;
                }
            }

            current_name = line;
            width = 1920;
            height = 1080;
            scale = 1.0;
            enabled = false;
            continue;
        }

        if (std.mem.startsWith(u8, line, "Enabled:")) {
            const value = std.mem.trim(u8, line[8..], " \t");
            enabled = std.ascii.eqlIgnoreCase(value, "yes");
            continue;
        }

        if (std.mem.startsWith(u8, line, "Current mode:")) {
            const value = std.mem.trim(u8, line[13..], " \t");
            if (std.mem.indexOfScalar(u8, value, 'x')) |x_idx| {
                const width_raw = std.mem.trim(u8, value[0..x_idx], " \t");
                var height_raw = value[x_idx + 1 ..];
                if (std.mem.indexOfScalar(u8, height_raw, '@')) |at_idx| {
                    height_raw = height_raw[0..at_idx];
                }
                if (std.mem.indexOfScalar(u8, height_raw, ' ')) |sp_idx| {
                    height_raw = height_raw[0..sp_idx];
                }

                width = std.fmt.parseUnsigned(u16, width_raw, 10) catch width;
                height = std.fmt.parseUnsigned(u16, std.mem.trim(u8, height_raw, " \t"), 10) catch height;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "Scale:")) {
            const value = std.mem.trim(u8, line[6..], " \t");
            scale = std.fmt.parseFloat(f32, value) catch scale;
            continue;
        }
    }

    if (current_name) |name| {
        if (enabled) {
            try outputs.append(.{
                .name = try allocator.dupe(u8, name),
                .width = width,
                .height = height,
                .scale = scale,
                .primary = !any,
            });
            any = true;
        }
    }

    return any;
}

pub fn freeOutputs(allocator: std.mem.Allocator, outputs: *std.ArrayList(OutputProfile)) void {
    for (outputs.items) |item| allocator.free(item.name);
    outputs.deinit();
}

pub fn fullscreenSurface(role: SurfaceRole, output: OutputProfile) SurfaceSpec {
    return .{
        .role = role,
        .app_id = appIdFor(role),
        .width = output.width,
        .height = output.height,
        .keyboard_first = role != .panel,
        .fullscreen = true,
        .output_name = output.name,
        .scale = output.scale,
        .decoration = decorationFor(role),
    };
}

pub fn renderSpecForSurface(spec: SurfaceSpec) RenderSpec {
    const safe_scale = if (spec.scale <= 0.0) 1.0 else spec.scale;
    const logical_w_f = @as(f32, @floatFromInt(spec.width)) / safe_scale;
    const logical_h_f = @as(f32, @floatFromInt(spec.height)) / safe_scale;

    return .{
        .output_name = spec.output_name,
        .physical_width = spec.width,
        .physical_height = spec.height,
        .scale = safe_scale,
        .logical_width = @as(u16, @intFromFloat(@max(logical_w_f, 1.0))),
        .logical_height = @as(u16, @intFromFloat(@max(logical_h_f, 1.0))),
    };
}

pub fn surfacesForRole(
    allocator: std.mem.Allocator,
    role: SurfaceRole,
    outputs: []const OutputProfile,
) !std.ArrayList(SurfaceSpec) {
    var surfaces = std.ArrayList(SurfaceSpec).init(allocator);
    for (outputs) |output| {
        try surfaces.append(fullscreenSurface(role, output));
    }
    return surfaces;
}

pub fn renderSpecsForRole(
    allocator: std.mem.Allocator,
    role: SurfaceRole,
    outputs: []const OutputProfile,
) !std.ArrayList(RenderSpec) {
    var specs = std.ArrayList(RenderSpec).init(allocator);
    for (outputs) |output| {
        const surface = fullscreenSurface(role, output);
        try specs.append(renderSpecForSurface(surface));
    }
    return specs;
}

pub fn panelSurface(panel_height: u8) SurfaceSpec {
    _ = panel_height;
    return fullscreenSurface(.panel, defaultOutputStatic());
}

pub fn launcherSurface(width: u16) SurfaceSpec {
    _ = width;
    return fullscreenSurface(.launcher, defaultOutputStatic());
}

pub fn settingsSurface() SurfaceSpec {
    return fullscreenSurface(.settings, defaultOutputStatic());
}

fn appIdFor(role: SurfaceRole) []const u8 {
    return switch (role) {
        .panel => "org.luminade.panel",
        .launcher => "org.luminade.launcher",
        .settings => "org.luminade.settings",
    };
}

fn appTitleForRole(role: SurfaceRole) []const u8 {
    return switch (role) {
        .panel => "Lumina Panel",
        .launcher => "Lumina Launcher",
        .settings => "Lumina Settings",
    };
}

fn decorationFor(role: SurfaceRole) WindowDecoration {
    return switch (role) {
        .panel => .{
            .enabled = false,
            .titlebar_height = 0,
            .round_corners = false,
            .shadow = false,
        },
        .launcher => .{
            .enabled = true,
            .titlebar_height = 36,
            .round_corners = true,
            .shadow = true,
        },
        .settings => .{
            .enabled = true,
            .titlebar_height = 40,
            .round_corners = true,
            .shadow = true,
        },
    };
}

fn defaultOutputOwned(allocator: std.mem.Allocator) !OutputProfile {
    return .{
        .name = try allocator.dupe(u8, "default"),
        .width = 1920,
        .height = 1080,
        .scale = 1.0,
        .primary = true,
    };
}

fn defaultOutputStatic() OutputProfile {
    return .{
        .name = "default",
        .width = 1920,
        .height = 1080,
        .scale = 1.0,
        .primary = true,
    };
}

fn detectOutputsFromEnv(allocator: std.mem.Allocator, outputs: *std.ArrayList(OutputProfile)) !bool {
    const raw = std.posix.getenv("LUMINADE_OUTPUTS") orelse return false;

    var any = false;
    var parts = std.mem.splitScalar(u8, raw, ',');
    var idx: usize = 0;
    while (parts.next()) |part_raw| : (idx += 1) {
        const part = std.mem.trim(u8, part_raw, " \t\r");
        if (part.len == 0) continue;

        const parsed = parseOutputEntry(part) orelse continue;
        const fallback_name = try std.fmt.allocPrint(allocator, "display-{d}", .{idx + 1});
        defer allocator.free(fallback_name);

        const name = if (parsed.name.len > 0)
            try allocator.dupe(u8, parsed.name)
        else
            try allocator.dupe(u8, fallback_name);

        try outputs.append(.{
            .name = name,
            .width = parsed.width,
            .height = parsed.height,
            .scale = parsed.scale,
            .primary = !any,
        });
        any = true;
    }

    return any;
}

fn parseOutputEntry(part: []const u8) ?struct { name: []const u8, width: u16, height: u16, scale: f32 } {
    var name: []const u8 = "";
    var rest = part;

    if (std.mem.indexOfScalar(u8, part, ':')) |colon| {
        name = std.mem.trim(u8, part[0..colon], " \t\r");
        rest = std.mem.trim(u8, part[colon + 1 ..], " \t\r");
    }

    var scale: f32 = 1.0;
    var size = rest;
    if (std.mem.indexOfScalar(u8, rest, '@')) |at_idx| {
        size = std.mem.trim(u8, rest[0..at_idx], " \t\r");
        const scale_raw = std.mem.trim(u8, rest[at_idx + 1 ..], " \t\r");
        scale = std.fmt.parseFloat(f32, scale_raw) catch 1.0;
    }

    const x_idx = std.mem.indexOfScalar(u8, size, 'x') orelse return null;
    const width = std.fmt.parseUnsigned(u16, size[0..x_idx], 10) catch return null;
    const height = std.fmt.parseUnsigned(u16, size[x_idx + 1 ..], 10) catch return null;

    return .{ .name = name, .width = width, .height = height, .scale = scale };
}

fn detectOutputsFromXrandr(allocator: std.mem.Allocator, outputs: *std.ArrayList(OutputProfile)) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "xrandr", "--query" },
        .max_output_bytes = 1024 * 1024,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return false,
        else => return false,
    }

    var any = false;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, " connected ") == null) continue;

        const profile = parseXrandrLine(allocator, line, !any) orelse continue;
        try outputs.append(profile);
        any = true;
    }

    return any;
}

fn parseXrandrLine(allocator: std.mem.Allocator, line: []const u8, fallback_primary: bool) ?OutputProfile {
    var words = std.mem.tokenizeAny(u8, line, " \t");
    const name = words.next() orelse return null;

    var width: u16 = 1920;
    var height: u16 = 1080;
    while (words.next()) |word| {
        if (parseResolutionToken(word)) |res| {
            width = res.width;
            height = res.height;
            break;
        }
    }

    const is_primary = std.mem.indexOf(u8, line, " primary ") != null or fallback_primary;

    return .{
        .name = allocator.dupe(u8, name) catch return null,
        .width = width,
        .height = height,
        .scale = 1.0,
        .primary = is_primary,
    };
}

fn parseResolutionToken(token: []const u8) ?struct { width: u16, height: u16 } {
    const plus_idx = std.mem.indexOfScalar(u8, token, '+') orelse return null;
    const size = token[0..plus_idx];
    const x_idx = std.mem.indexOfScalar(u8, size, 'x') orelse return null;
    const width = std.fmt.parseUnsigned(u16, size[0..x_idx], 10) catch return null;
    const height = std.fmt.parseUnsigned(u16, size[x_idx + 1 ..], 10) catch return null;
    return .{ .width = width, .height = height };
}

fn outputsEqual(a: []const OutputProfile, b: []const OutputProfile) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (!std.mem.eql(u8, left.name, right.name)) return false;
        if (left.width != right.width) return false;
        if (left.height != right.height) return false;
        if (left.primary != right.primary) return false;
        if (@abs(left.scale - right.scale) > 0.0001) return false;
    }
    return true;
}

pub fn printSurfaceSummary(spec: SurfaceSpec, tokens: ThemeTokens) void {
    std.debug.print(
        "[ui] role={s} app_id={s} output={s} size={d}x{d}@{d:.2} fullscreen={any} kbd-first={any} decor={any} radius={d} blur={d}\n",
        .{
            @tagName(spec.role),
            spec.app_id,
            spec.output_name,
            spec.width,
            spec.height,
            spec.scale,
            spec.fullscreen,
            spec.keyboard_first,
            spec.decoration.enabled,
            tokens.corner_radius,
            tokens.blur_sigma,
        },
    );
}

pub fn printRenderSpec(spec: RenderSpec) void {
    std.debug.print(
        "[render] output={s} physical={d}x{d} scale={d:.2} logical={d}x{d}\n",
        .{
            spec.output_name,
            spec.physical_width,
            spec.physical_height,
            spec.scale,
            spec.logical_width,
            spec.logical_height,
        },
    );
}
