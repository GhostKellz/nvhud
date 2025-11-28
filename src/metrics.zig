//! GPU Metrics Collection
//!
//! High-level metrics collection using NVML directly.
//! Falls back to nvidia-smi parsing if NVML isn't available.

const std = @import("std");
const nvml = @import("nvml.zig");

/// GPU metrics snapshot
pub const GpuMetrics = struct {
    /// GPU temperature (Celsius)
    temperature: u32 = 0,
    /// GPU utilization (0-100%)
    gpu_util: u32 = 0,
    /// Memory utilization (0-100%)
    mem_util: u32 = 0,
    /// GPU clock (MHz)
    gpu_clock: u32 = 0,
    /// Memory clock (MHz)
    mem_clock: u32 = 0,
    /// Power draw (Watts)
    power_draw: u32 = 0,
    /// Power limit (Watts)
    power_limit: u32 = 0,
    /// Fan speed (0-100%)
    fan_speed: u32 = 0,
    /// VRAM used (MB)
    vram_used: u32 = 0,
    /// VRAM total (MB)
    vram_total: u32 = 0,
    /// PCIe generation
    pcie_gen: u32 = 0,
    /// PCIe link width
    pcie_width: u32 = 0,
    /// Encoder utilization (0-100%)
    encoder_util: u32 = 0,
    /// Decoder utilization (0-100%)
    decoder_util: u32 = 0,
    /// Performance state (P0-P15)
    pstate: u32 = 0,

    pub fn vramUsagePercent(self: *const GpuMetrics) f32 {
        if (self.vram_total == 0) return 0;
        return @as(f32, @floatFromInt(self.vram_used)) / @as(f32, @floatFromInt(self.vram_total)) * 100.0;
    }

    pub fn powerUsagePercent(self: *const GpuMetrics) f32 {
        if (self.power_limit == 0) return 0;
        return @as(f32, @floatFromInt(self.power_draw)) / @as(f32, @floatFromInt(self.power_limit)) * 100.0;
    }

    pub fn vramFree(self: *const GpuMetrics) u32 {
        if (self.vram_total > self.vram_used) {
            return self.vram_total - self.vram_used;
        }
        return 0;
    }
};

/// GPU static information
pub const GpuInfo = struct {
    name: [96]u8 = [_]u8{0} ** 96,
    name_len: usize = 0,
    driver_version: [32]u8 = [_]u8{0} ** 32,
    driver_len: usize = 0,
    architecture: [32]u8 = [_]u8{0} ** 32,
    arch_len: usize = 0,
    vram_total_mb: u32 = 0,
    pcie_gen_max: u32 = 0,
    pcie_width_max: u32 = 0,

    pub fn getName(self: *const GpuInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getDriver(self: *const GpuInfo) []const u8 {
        return self.driver_version[0..self.driver_len];
    }

    pub fn getArchitecture(self: *const GpuInfo) []const u8 {
        return self.architecture[0..self.arch_len];
    }
};

/// Frame timing metrics
pub const FrameMetrics = struct {
    /// Current FPS
    fps: f32 = 0,
    /// Average frame time (ms)
    frame_time_ms: f32 = 0,
    /// 1% low FPS
    fps_1_low: f32 = 0,
    /// 0.1% low FPS
    fps_01_low: f32 = 0,
    /// Frame count
    frame_count: u64 = 0,
    /// Max frame time in window (ms)
    frame_time_max: f32 = 0,
    /// Min frame time in window (ms)
    frame_time_min: f32 = 0,
};

/// Rolling frame time buffer for statistics
pub const FrameTimeBuffer = struct {
    const SIZE = 300; // ~5 seconds at 60fps

    times: [SIZE]f32 = [_]f32{0} ** SIZE,
    index: usize = 0,
    count: usize = 0,
    frame_count: u64 = 0,

    pub fn push(self: *FrameTimeBuffer, frame_time_ms: f32) void {
        self.times[self.index] = frame_time_ms;
        self.index = (self.index + 1) % SIZE;
        if (self.count < SIZE) self.count += 1;
        self.frame_count += 1;
    }

    pub fn getMetrics(self: *const FrameTimeBuffer) FrameMetrics {
        if (self.count == 0) return .{};

        var sum: f32 = 0;
        var min_time: f32 = self.times[0];
        var max_time: f32 = self.times[0];

        for (self.times[0..self.count]) |t| {
            sum += t;
            if (t < min_time) min_time = t;
            if (t > max_time) max_time = t;
        }

        const avg = sum / @as(f32, @floatFromInt(self.count));
        const fps = if (avg > 0) 1000.0 / avg else 0;

        // Calculate percentiles
        var sorted: [SIZE]f32 = undefined;
        @memcpy(sorted[0..self.count], self.times[0..self.count]);
        std.mem.sort(f32, sorted[0..self.count], {}, std.sort.asc(f32));

        const idx_99 = (self.count * 99) / 100;
        const idx_999 = (self.count * 999) / 1000;

        const time_99 = sorted[@min(idx_99, self.count - 1)];
        const time_999 = sorted[@min(idx_999, self.count - 1)];

        return FrameMetrics{
            .fps = fps,
            .frame_time_ms = avg,
            .fps_1_low = if (time_99 > 0) 1000.0 / time_99 else 0,
            .fps_01_low = if (time_999 > 0) 1000.0 / time_999 else 0,
            .frame_count = self.frame_count,
            .frame_time_max = max_time,
            .frame_time_min = min_time,
        };
    }
};

/// Metrics collector
pub const Collector = struct {
    device: ?nvml.Device = null,
    nvml_available: bool = false,
    gpu_info: GpuInfo = .{},

    pub fn init() Collector {
        var self = Collector{};

        // Try to initialize NVML
        if (nvml.init()) {
            self.nvml_available = true;

            // Get first device
            if (nvml.getDevice(0)) |dev| {
                self.device = dev;
                self.loadGpuInfo();
            } else |_| {}
        } else |_| {}

        return self;
    }

    pub fn deinit(self: *Collector) void {
        if (self.nvml_available) {
            nvml.shutdown();
        }
    }

    fn loadGpuInfo(self: *Collector) void {
        const dev = self.device orelse return;

        // GPU name
        if (nvml.getDeviceName(dev)) |name| {
            const len = @min(name.len, self.gpu_info.name.len);
            @memcpy(self.gpu_info.name[0..len], name[0..len]);
            self.gpu_info.name_len = len;
        } else |_| {}

        // Driver version
        if (nvml.getDriverVersion()) |ver| {
            const len = @min(ver.len, self.gpu_info.driver_version.len);
            @memcpy(self.gpu_info.driver_version[0..len], ver[0..len]);
            self.gpu_info.driver_len = len;
        } else |_| {}

        // Architecture
        const arch = nvml.getArchitectureName(dev);
        const arch_len = @min(arch.len, self.gpu_info.architecture.len);
        @memcpy(self.gpu_info.architecture[0..arch_len], arch[0..arch_len]);
        self.gpu_info.arch_len = arch_len;

        // VRAM
        if (nvml.getMemoryInfo(dev)) |mem| {
            self.gpu_info.vram_total_mb = @intCast(mem.total / (1024 * 1024));
        } else |_| {}
    }

    /// Collect current GPU metrics
    pub fn collect(self: *Collector) GpuMetrics {
        var metrics = GpuMetrics{};

        const dev = self.device orelse return metrics;

        // Temperature
        if (nvml.getTemperature(dev)) |t| {
            metrics.temperature = t;
        } else |_| {}

        // Utilization
        if (nvml.getGpuUtilization(dev)) |u| {
            metrics.gpu_util = u;
        } else |_| {}

        if (nvml.getMemoryUtilization(dev)) |u| {
            metrics.mem_util = u;
        } else |_| {}

        // Clocks
        if (nvml.getClock(dev, nvml.CLOCK_GRAPHICS)) |c| {
            metrics.gpu_clock = c;
        } else |_| {}

        if (nvml.getClock(dev, nvml.CLOCK_MEM)) |c| {
            metrics.mem_clock = c;
        } else |_| {}

        // Power
        if (nvml.getPowerUsage(dev)) |p| {
            metrics.power_draw = p / 1000; // mW to W
        } else |_| {}

        if (nvml.getPowerLimit(dev)) |p| {
            metrics.power_limit = p / 1000; // mW to W
        } else |_| {}

        // Fan
        if (nvml.getFanSpeed(dev)) |f| {
            metrics.fan_speed = f;
        } else |_| {}

        // Memory
        if (nvml.getMemoryInfo(dev)) |mem| {
            metrics.vram_used = @intCast(mem.used / (1024 * 1024));
            metrics.vram_total = @intCast(mem.total / (1024 * 1024));
        } else |_| {}

        // PCIe
        if (nvml.getPcieGeneration(dev)) |g| {
            metrics.pcie_gen = g;
        } else |_| {}

        if (nvml.getPcieWidth(dev)) |w| {
            metrics.pcie_width = w;
        } else |_| {}

        // Encoder/Decoder
        if (nvml.getEncoderUtilization(dev)) |e| {
            metrics.encoder_util = e;
        } else |_| {}

        if (nvml.getDecoderUtilization(dev)) |d| {
            metrics.decoder_util = d;
        } else |_| {}

        // P-state
        if (nvml.getPerformanceState(dev)) |p| {
            metrics.pstate = p;
        } else |_| {}

        return metrics;
    }

    /// Get GPU info
    pub fn getInfo(self: *const Collector) GpuInfo {
        return self.gpu_info;
    }

    /// Check if NVIDIA GPU is available
    pub fn isAvailable(self: *const Collector) bool {
        return self.nvml_available and self.device != null;
    }
};

test "frame time buffer" {
    var buf = FrameTimeBuffer{};
    buf.push(16.6);
    buf.push(16.7);
    buf.push(16.5);

    const metrics = buf.getMetrics();
    try std.testing.expect(metrics.fps > 59.0);
    try std.testing.expect(metrics.fps < 61.0);
}

test "gpu metrics calculations" {
    const metrics = GpuMetrics{
        .vram_used = 8000,
        .vram_total = 16000,
        .power_draw = 200,
        .power_limit = 400,
    };

    try std.testing.expectEqual(@as(f32, 50.0), metrics.vramUsagePercent());
    try std.testing.expectEqual(@as(f32, 50.0), metrics.powerUsagePercent());
}
