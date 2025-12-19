//! nvhud - NVIDIA GPU Performance Overlay
//!
//! A MangoHud alternative optimized for NVIDIA GPUs.
//! Features:
//! - Direct NVML integration (no nvidia-smi subprocess)
//! - GPU-accelerated Vulkan overlay (<1% overhead)
//! - Full NVIDIA telemetry (Reflex latency, NVENC, etc.)
//! - Configurable via TOML or environment variables

const std = @import("std");

// Public modules
pub const nvml = @import("nvml.zig");
pub const metrics = @import("metrics.zig");
pub const config = @import("config.zig");
pub const overlay = @import("overlay.zig");
pub const renderer = @import("renderer.zig");

/// Library version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 3,
    .patch = 0,
};

/// Version string
pub const version_string = "0.3.0";

// Re-export key types
pub const GpuMetrics = metrics.GpuMetrics;
pub const GpuInfo = metrics.GpuInfo;
pub const FrameMetrics = metrics.FrameMetrics;
pub const FrameTimeBuffer = metrics.FrameTimeBuffer;
pub const Collector = metrics.Collector;
pub const Config = config.Config;
pub const Position = config.Position;
pub const Color = config.Color;
pub const Overlay = overlay.Overlay;
pub const RenderCommand = overlay.RenderCommand;
pub const Renderer = renderer.Renderer;
pub const Vertex = renderer.Vertex;
pub const BitmapFont = renderer.BitmapFont;

/// Quick check if NVIDIA GPU is available
pub fn isNvidiaAvailable() bool {
    return nvml.isAvailable();
}

/// Create a metrics collector
pub fn createCollector() Collector {
    return Collector.init();
}

/// Create an overlay with default config
pub fn createOverlay(allocator: std.mem.Allocator) Overlay {
    return Overlay.init(allocator, Config.default());
}

/// Create an overlay with custom config
pub fn createOverlayWithConfig(allocator: std.mem.Allocator, cfg: Config) Overlay {
    return Overlay.init(allocator, cfg);
}

/// Load config from file
pub fn loadConfig(allocator: std.mem.Allocator) Config {
    return Config.load(allocator) catch Config.default();
}

/// Environment variable to enable overlay
pub const ENV_ENABLE = "NVHUD";
pub const ENV_POSITION = "NVHUD_POSITION";
pub const ENV_FPS = "NVHUD_FPS";
pub const ENV_CONFIG = "NVHUD_CONFIG";

/// Check if overlay is enabled via environment
pub fn isOverlayEnabled() bool {
    if (std.posix.getenv(ENV_ENABLE)) |val| {
        return std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "true");
    }
    return false;
}

/// Get config from environment, falling back to defaults
pub fn getConfigFromEnv(allocator: std.mem.Allocator) Config {
    var cfg = loadConfig(allocator);

    // Override with env vars
    if (std.posix.getenv(ENV_POSITION)) |pos| {
        cfg.position = Position.fromString(pos);
    }

    if (std.posix.getenv(ENV_FPS)) |fps_str| {
        if (std.mem.eql(u8, fps_str, "0") or std.mem.eql(u8, fps_str, "false")) {
            cfg.show_fps = false;
        }
    }

    return cfg;
}

// =============================================================================
// Tests
// =============================================================================

test "version" {
    try std.testing.expectEqual(@as(u8, 0), version.major);
    try std.testing.expectEqual(@as(u8, 3), version.minor);
}

test "nvidia check" {
    // Just verify it doesn't crash
    _ = isNvidiaAvailable();
}

test "collector creation" {
    var collector = createCollector();
    defer collector.deinit();
}

test "config presets" {
    const minimal = Config.minimal();
    try std.testing.expect(minimal.show_fps);
    try std.testing.expect(!minimal.show_gpu_temp);

    const gaming = Config.gaming();
    try std.testing.expect(gaming.show_fps);
    try std.testing.expect(gaming.show_gpu_temp);
    try std.testing.expect(gaming.show_frametime_graph);

    const full = Config.full();
    try std.testing.expect(full.show_pcie);
    try std.testing.expect(full.show_encoder);
}
