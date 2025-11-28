//! nvhud - NVIDIA GPU Metrics & HUD for Linux
//!
//! GPU metrics collection and overlay system using NVML (NVIDIA Management Library).
//! Provides real-time GPU statistics for monitoring and gaming overlays.

const std = @import("std");
const posix = std.posix;
const fs = std.fs;
const mem = std.mem;

/// Library version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

/// GPU metrics snapshot
pub const GpuMetrics = struct {
    /// GPU temperature in Celsius
    temperature: u32,
    /// GPU utilization percentage (0-100)
    gpu_utilization: u32,
    /// Memory utilization percentage (0-100)
    memory_utilization: u32,
    /// Current GPU clock in MHz
    gpu_clock: u32,
    /// Current memory clock in MHz
    memory_clock: u32,
    /// Power draw in watts
    power_draw: u32,
    /// Power limit in watts
    power_limit: u32,
    /// Fan speed percentage (0-100)
    fan_speed: u32,
    /// Total VRAM in MB
    vram_total: u32,
    /// Used VRAM in MB
    vram_used: u32,
    /// Free VRAM in MB
    vram_free: u32,
    /// PCIe generation
    pcie_gen: u32,
    /// PCIe link width
    pcie_width: u32,

    pub fn vramUsagePercent(self: *const GpuMetrics) f64 {
        if (self.vram_total == 0) return 0;
        return @as(f64, @floatFromInt(self.vram_used)) / @as(f64, @floatFromInt(self.vram_total)) * 100.0;
    }

    pub fn powerUsagePercent(self: *const GpuMetrics) f64 {
        if (self.power_limit == 0) return 0;
        return @as(f64, @floatFromInt(self.power_draw)) / @as(f64, @floatFromInt(self.power_limit)) * 100.0;
    }
};

/// Frame timing metrics
pub const FrameMetrics = struct {
    /// Current FPS
    fps: f32,
    /// Average frame time in ms
    frame_time_ms: f32,
    /// 1% low FPS
    fps_1_low: f32,
    /// 0.1% low FPS
    fps_01_low: f32,
    /// Frame count
    frame_count: u64,
};

/// GPU information (static)
pub const GpuInfo = struct {
    allocator: mem.Allocator,
    name: []const u8,
    driver_version: []const u8,
    cuda_version: []const u8,
    vbios_version: []const u8,
    architecture: []const u8,
    pcie_info: []const u8,

    pub fn deinit(self: *GpuInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.driver_version);
        self.allocator.free(self.cuda_version);
        self.allocator.free(self.vbios_version);
        self.allocator.free(self.architecture);
        self.allocator.free(self.pcie_info);
    }
};

/// GPU metrics collector - uses nvidia-smi for real-time metrics
pub const MetricsCollector = struct {
    allocator: mem.Allocator,
    nvidia_detected: bool,

    // Cached info
    gpu_name: ?[]const u8,
    driver_version: ?[]const u8,

    pub fn init(allocator: mem.Allocator) MetricsCollector {
        var collector = MetricsCollector{
            .allocator = allocator,
            .nvidia_detected = false,
            .gpu_name = null,
            .driver_version = null,
        };

        // Detect NVIDIA GPU
        collector.nvidia_detected = isNvidiaGpu();

        if (collector.nvidia_detected) {
            collector.driver_version = getNvidiaDriverVersion(allocator);
            collector.gpu_name = getGpuName(allocator);
        }

        return collector;
    }

    pub fn deinit(self: *MetricsCollector) void {
        if (self.gpu_name) |n| self.allocator.free(n);
        if (self.driver_version) |v| self.allocator.free(v);
    }

    /// Collect current GPU metrics via nvidia-smi
    pub fn collect(self: *MetricsCollector) GpuMetrics {
        var metrics = GpuMetrics{
            .temperature = 0,
            .gpu_utilization = 0,
            .memory_utilization = 0,
            .gpu_clock = 0,
            .memory_clock = 0,
            .power_draw = 0,
            .power_limit = 0,
            .fan_speed = 0,
            .vram_total = 0,
            .vram_used = 0,
            .vram_free = 0,
            .pcie_gen = 0,
            .pcie_width = 0,
        };

        if (!self.nvidia_detected) return metrics;

        // Query nvidia-smi for all metrics in one call
        self.queryNvidiaSmi(&metrics);

        return metrics;
    }

    /// Query nvidia-smi for GPU metrics
    fn queryNvidiaSmi(self: *MetricsCollector, metrics: *GpuMetrics) void {
        // Run nvidia-smi with specific query format
        var child = std.process.Child.init(
            &[_][]const u8{
                "nvidia-smi",
                "--query-gpu=temperature.gpu,utilization.gpu,utilization.memory,clocks.gr,clocks.mem,power.draw,power.limit,fan.speed,memory.used,memory.total,pcie.link.gen.current,pcie.link.width.current",
                "--format=csv,noheader,nounits",
            },
            self.allocator,
        );
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return;

        // Read all output - keep reading until EOF
        const stdout = child.stdout orelse return;
        var buf: [512]u8 = undefined;
        var total_read: usize = 0;

        while (total_read < buf.len) {
            const bytes_read = stdout.read(buf[total_read..]) catch break;
            if (bytes_read == 0) break; // EOF
            total_read += bytes_read;
        }

        // Wait for process to complete
        _ = child.wait() catch return;

        if (total_read == 0) return;

        const output = buf[0..total_read];
        const trimmed = mem.trim(u8, output, &[_]u8{ '\n', '\r', ' ' });

        // Parse CSV: temp, gpu_util, mem_util, gpu_clock, mem_clock, power, power_limit, fan, vram_used, vram_total, pcie_gen, pcie_width
        var parts = mem.splitSequence(u8, trimmed, ", ");

        // Temperature
        if (parts.next()) |val| {
            metrics.temperature = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // GPU utilization
        if (parts.next()) |val| {
            metrics.gpu_utilization = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // Memory utilization
        if (parts.next()) |val| {
            metrics.memory_utilization = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // GPU clock
        if (parts.next()) |val| {
            metrics.gpu_clock = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // Memory clock
        if (parts.next()) |val| {
            metrics.memory_clock = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // Power draw
        if (parts.next()) |val| {
            // Power can be float like "108.20"
            const power_f = std.fmt.parseFloat(f32, val) catch 0;
            metrics.power_draw = @intFromFloat(power_f);
        }
        // Power limit
        if (parts.next()) |val| {
            const limit_f = std.fmt.parseFloat(f32, val) catch 0;
            metrics.power_limit = @intFromFloat(limit_f);
        }
        // Fan speed
        if (parts.next()) |val| {
            metrics.fan_speed = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // VRAM used
        if (parts.next()) |val| {
            metrics.vram_used = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // VRAM total
        if (parts.next()) |val| {
            metrics.vram_total = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // PCIe gen
        if (parts.next()) |val| {
            metrics.pcie_gen = std.fmt.parseInt(u32, val, 10) catch 0;
        }
        // PCIe width
        if (parts.next()) |val| {
            metrics.pcie_width = std.fmt.parseInt(u32, val, 10) catch 0;
        }

        // Calculate free VRAM
        if (metrics.vram_total > metrics.vram_used) {
            metrics.vram_free = metrics.vram_total - metrics.vram_used;
        }
    }

    /// Get GPU info
    pub fn getInfo(self: *MetricsCollector) GpuInfo {
        return GpuInfo{
            .allocator = self.allocator,
            .name = self.allocator.dupe(u8, self.gpu_name orelse "Unknown") catch "Unknown",
            .driver_version = self.allocator.dupe(u8, self.driver_version orelse "Unknown") catch "Unknown",
            .cuda_version = self.allocator.dupe(u8, "12.0") catch "Unknown",
            .vbios_version = self.allocator.dupe(u8, "Unknown") catch "Unknown",
            .architecture = self.allocator.dupe(u8, detectArchitecture(self.gpu_name)) catch "Unknown",
            .pcie_info = self.allocator.dupe(u8, "Gen4 x16") catch "Unknown",
        };
    }
};


/// Check if NVIDIA GPU is present
pub fn isNvidiaGpu() bool {
    fs.cwd().access("/proc/driver/nvidia/version", .{}) catch return false;
    return true;
}

/// Get NVIDIA driver version
pub fn getNvidiaDriverVersion(allocator: mem.Allocator) ?[]const u8 {
    const content = fs.cwd().readFileAlloc("/proc/driver/nvidia/version", allocator, .unlimited) catch return null;
    defer allocator.free(content);

    if (mem.indexOf(u8, content, "Kernel Module")) |idx| {
        const rest_raw = content[idx + 13 ..];
        const rest = mem.trim(u8, rest_raw, &[_]u8{ ' ', '\t', '\n', '\r' });

        var end: usize = 0;
        for (rest, 0..) |c, i| {
            if (c == ' ' or c == '\n' or c == '\r') {
                end = i;
                break;
            }
            end = i + 1;
        }

        if (end > 0) {
            return allocator.dupe(u8, rest[0..end]) catch null;
        }
    }

    return null;
}

/// Get GPU name
fn getGpuName(allocator: mem.Allocator) ?[]const u8 {
    // Try to read from nvidia-smi output or PCI info
    var dir = fs.cwd().openDir("/proc/driver/nvidia/gpus", .{ .iterate = true }) catch return null;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        var path_buf: [256]u8 = undefined;
        const info_path = std.fmt.bufPrint(&path_buf, "/proc/driver/nvidia/gpus/{s}/information", .{entry.name}) catch return null;

        const info = fs.cwd().readFileAlloc(info_path, allocator, .unlimited) catch return null;
        defer allocator.free(info);

        var lines = mem.splitSequence(u8, info, "\n");
        while (lines.next()) |line| {
            if (mem.indexOf(u8, line, "Model:")) |_| {
                if (mem.indexOf(u8, line, ":")) |colon_idx| {
                    const name = mem.trim(u8, line[colon_idx + 1 ..], " \t");
                    return allocator.dupe(u8, name) catch null;
                }
            }
        }
    }

    return null;
}

/// Detect architecture from GPU name
fn detectArchitecture(gpu_name: ?[]const u8) []const u8 {
    const name = gpu_name orelse return "Unknown";

    if (mem.indexOf(u8, name, "5090") != null or mem.indexOf(u8, name, "5080") != null or
        mem.indexOf(u8, name, "5070") != null or mem.indexOf(u8, name, "5060") != null)
    {
        return "Blackwell";
    } else if (mem.indexOf(u8, name, "4090") != null or mem.indexOf(u8, name, "4080") != null or
        mem.indexOf(u8, name, "4070") != null or mem.indexOf(u8, name, "4060") != null)
    {
        return "Ada Lovelace";
    } else if (mem.indexOf(u8, name, "3090") != null or mem.indexOf(u8, name, "3080") != null or
        mem.indexOf(u8, name, "3070") != null or mem.indexOf(u8, name, "3060") != null)
    {
        return "Ampere";
    } else if (mem.indexOf(u8, name, "2080") != null or mem.indexOf(u8, name, "2070") != null or
        mem.indexOf(u8, name, "2060") != null)
    {
        return "Turing";
    } else if (mem.indexOf(u8, name, "1080") != null or mem.indexOf(u8, name, "1070") != null or
        mem.indexOf(u8, name, "1060") != null)
    {
        return "Pascal";
    }

    return "Unknown";
}

/// HUD configuration
pub const HudConfig = struct {
    /// Show FPS counter
    show_fps: bool = true,
    /// Show GPU temperature
    show_temperature: bool = true,
    /// Show GPU utilization
    show_gpu_util: bool = true,
    /// Show VRAM usage
    show_vram: bool = true,
    /// Show power draw
    show_power: bool = false,
    /// Show frame time graph
    show_frametime_graph: bool = false,
    /// Position on screen
    position: Position = .top_left,
    /// Update interval in ms
    update_interval_ms: u32 = 500,

    pub const Position = enum {
        top_left,
        top_right,
        bottom_left,
        bottom_right,
    };

    pub fn default() HudConfig {
        return .{};
    }
};

// =============================================================================
// Tests
// =============================================================================

test "version" {
    try std.testing.expectEqual(@as(u8, 0), version.major);
    try std.testing.expectEqual(@as(u8, 1), version.minor);
}

test "GpuMetrics vram percent" {
    const metrics = GpuMetrics{
        .temperature = 65,
        .gpu_utilization = 80,
        .memory_utilization = 50,
        .gpu_clock = 2100,
        .memory_clock = 10000,
        .power_draw = 300,
        .power_limit = 450,
        .fan_speed = 60,
        .vram_total = 24000,
        .vram_used = 12000,
        .vram_free = 12000,
        .pcie_gen = 4,
        .pcie_width = 16,
    };

    try std.testing.expectEqual(@as(f64, 50.0), metrics.vramUsagePercent());
}

test "HudConfig default" {
    const config = HudConfig.default();
    try std.testing.expect(config.show_fps);
    try std.testing.expect(config.show_temperature);
}
