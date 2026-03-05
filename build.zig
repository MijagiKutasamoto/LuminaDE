const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_mod = b.createModule(.{
        .root_source_file = b.path("libs/luminade-core/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ui_mod = b.createModule(.{
        .root_source_file = b.path("libs/luminade-ui/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const panel_exe = b.addExecutable(.{
        .name = "luminade-panel",
        .root_source_file = b.path("apps/panel/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    panel_exe.root_module.addImport("luminade_core", core_mod);
    panel_exe.root_module.addImport("luminade_ui", ui_mod);
    b.installArtifact(panel_exe);

    const launcher_exe = b.addExecutable(.{
        .name = "luminade-launcher",
        .root_source_file = b.path("apps/launcher/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    launcher_exe.root_module.addImport("luminade_core", core_mod);
    launcher_exe.root_module.addImport("luminade_ui", ui_mod);
    b.installArtifact(launcher_exe);

    const settings_exe = b.addExecutable(.{
        .name = "luminade-settings",
        .root_source_file = b.path("apps/settings/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    settings_exe.root_module.addImport("luminade_core", core_mod);
    settings_exe.root_module.addImport("luminade_ui", ui_mod);
    b.installArtifact(settings_exe);

    const welcome_exe = b.addExecutable(.{
        .name = "luminade-welcome",
        .root_source_file = b.path("apps/welcome/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    welcome_exe.root_module.addImport("luminade_core", core_mod);
    welcome_exe.root_module.addImport("luminade_ui", ui_mod);
    b.installArtifact(welcome_exe);

    const sessiond_exe = b.addExecutable(.{
        .name = "luminade-sessiond",
        .root_source_file = b.path("apps/sessiond/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sessiond_exe);

    const run_panel = b.addRunArtifact(panel_exe);
    if (b.args) |args| run_panel.addArgs(args);
    const run_panel_step = b.step("run-panel", "Run luminade-panel");
    run_panel_step.dependOn(&run_panel.step);

    const run_launcher = b.addRunArtifact(launcher_exe);
    if (b.args) |args| run_launcher.addArgs(args);
    const run_launcher_step = b.step("run-launcher", "Run luminade-launcher");
    run_launcher_step.dependOn(&run_launcher.step);

    const run_settings = b.addRunArtifact(settings_exe);
    if (b.args) |args| run_settings.addArgs(args);
    const run_settings_step = b.step("run-settings", "Run luminade-settings");
    run_settings_step.dependOn(&run_settings.step);

    const run_welcome = b.addRunArtifact(welcome_exe);
    if (b.args) |args| run_welcome.addArgs(args);
    const run_welcome_step = b.step("run-welcome", "Run luminade-welcome");
    run_welcome_step.dependOn(&run_welcome.step);

    const run_sessiond = b.addRunArtifact(sessiond_exe);
    if (b.args) |args| run_sessiond.addArgs(args);
    const run_sessiond_step = b.step("run-sessiond", "Run luminade-sessiond");
    run_sessiond_step.dependOn(&run_sessiond.step);

}
