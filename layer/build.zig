const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the Vulkan layer as a shared library
    const layer = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "nvhud_layer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("vk_layer.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Install the library
    b.installArtifact(layer);

    // Install the layer manifest
    b.installFile("nvhud_layer.json", "share/vulkan/implicit_layer.d/nvhud_layer.json");
}
