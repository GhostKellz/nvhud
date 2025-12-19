//! Vulkan Overlay Layer
//!
//! GPU-accelerated overlay rendering for in-game HUD.
//! Implements a Vulkan implicit layer that hooks into game rendering.

const std = @import("std");
const config = @import("config.zig");
const metrics = @import("metrics.zig");

/// Overlay state
pub const State = enum {
    disabled,
    initializing,
    ready,
    rendering,
    error_state,
};

/// Text alignment
pub const Align = enum {
    left,
    center,
    right,
};

/// Render command for overlay
pub const RenderCommand = union(enum) {
    text: struct {
        x: i32,
        y: i32,
        text: []const u8,
        color: config.Color,
        size: u32,
    },
    rect: struct {
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        color: config.Color,
    },
    graph: struct {
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        values: []const f32,
        color: config.Color,
    },
    bar: struct {
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        value: f32, // 0.0 - 1.0
        color: config.Color,
        bg_color: config.Color,
    },
};

/// HUD line item
pub const HudLine = struct {
    label: []const u8,
    value: []const u8,
    color: config.Color = config.Color.white,
    bar_value: ?f32 = null, // Optional progress bar
};

/// Overlay renderer
pub const Overlay = struct {
    allocator: std.mem.Allocator,
    cfg: config.Config,
    state: State = .disabled,
    visible: bool = true,

    // Render state
    commands: std.ArrayListUnmanaged(RenderCommand) = .{},
    lines: std.ArrayListUnmanaged(HudLine) = .{},

    // Frame timing
    frame_times: metrics.FrameTimeBuffer = .{},
    last_frame_time: u64 = 0,

    // Metrics collector
    collector: ?metrics.Collector = null,
    last_metrics: metrics.GpuMetrics = .{},
    last_collect_time: u64 = 0,

    // String buffers for rendering
    str_buf: [32][64]u8 = undefined,
    str_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator, cfg: config.Config) Overlay {
        return Overlay{
            .allocator = allocator,
            .cfg = cfg,
            .collector = metrics.Collector.init(),
        };
    }

    pub fn deinit(self: *Overlay) void {
        if (self.collector) |*c| c.deinit();
        self.commands.deinit(self.allocator);
        self.lines.deinit(self.allocator);
        self.* = undefined;
    }

    /// Toggle visibility
    pub fn toggle(self: *Overlay) void {
        self.visible = !self.visible;
    }

    /// Record frame time for FPS calculation
    pub fn recordFrame(self: *Overlay) void {
        const now = getCurrentTimeNs();
        if (self.last_frame_time > 0) {
            const delta_ns = now - self.last_frame_time;
            const delta_ms = @as(f32, @floatFromInt(delta_ns)) / 1_000_000.0;
            self.frame_times.push(delta_ms);
        }
        self.last_frame_time = now;
    }

    /// Update metrics (call periodically, not every frame)
    pub fn updateMetrics(self: *Overlay) void {
        const now = getCurrentTimeNs();
        const interval_ns = @as(u64, self.cfg.update_interval_ms) * 1_000_000;

        if (now - self.last_collect_time >= interval_ns) {
            if (self.collector) |*c| {
                self.last_metrics = c.collect();
            }
            self.last_collect_time = now;
        }
    }

    /// Build HUD content
    pub fn buildHud(self: *Overlay) void {
        self.lines.clearRetainingCapacity();
        self.str_idx = 0;

        const m = self.last_metrics;
        const frame = self.frame_times.getMetrics();

        // FPS
        if (self.cfg.show_fps) {
            const fps_str = self.fmtBuf("{d:.0}", .{frame.fps});
            const color = if (frame.fps < 30) self.cfg.critical_color else if (frame.fps < 60) self.cfg.warning_color else self.cfg.accent_color;
            self.lines.append(self.allocator, .{ .label = "FPS", .value = fps_str, .color = color }) catch {};
        }

        // Frame time
        if (self.cfg.show_frametime) {
            const ft_str = self.fmtBuf("{d:.1}ms", .{frame.frame_time_ms});
            self.lines.append(self.allocator, .{ .label = "Frame", .value = ft_str }) catch {};
        }

        // GPU temp
        if (self.cfg.show_gpu_temp and m.temperature > 0) {
            const temp_str = self.fmtBuf("{d}°C", .{m.temperature});
            const color = if (m.temperature >= self.cfg.temp_critical) self.cfg.critical_color else if (m.temperature >= self.cfg.temp_warning) self.cfg.warning_color else self.cfg.text_color;
            self.lines.append(self.allocator, .{ .label = "GPU", .value = temp_str, .color = color }) catch {};
        }

        // GPU utilization
        if (self.cfg.show_gpu_util and m.gpu_util > 0) {
            const util_str = self.fmtBuf("{d}%", .{m.gpu_util});
            const bar_val = @as(f32, @floatFromInt(m.gpu_util)) / 100.0;
            self.lines.append(self.allocator, .{ .label = "Load", .value = util_str, .bar_value = bar_val }) catch {};
        }

        // GPU clock
        if (self.cfg.show_gpu_clock and m.gpu_clock > 0) {
            const clock_str = self.fmtBuf("{d}MHz", .{m.gpu_clock});
            self.lines.append(self.allocator, .{ .label = "Clock", .value = clock_str }) catch {};
        }

        // Power
        if (self.cfg.show_gpu_power and m.power_draw > 0) {
            const power_str = self.fmtBuf("{d}W", .{m.power_draw});
            const pct = m.powerUsagePercent();
            const color = if (pct >= 95) self.cfg.warning_color else self.cfg.text_color;
            self.lines.append(self.allocator, .{ .label = "Power", .value = power_str, .color = color }) catch {};
        }

        // VRAM
        if (self.cfg.show_vram and m.vram_total > 0) {
            const vram_gb = @as(f32, @floatFromInt(m.vram_used)) / 1024.0;
            const total_gb = @as(f32, @floatFromInt(m.vram_total)) / 1024.0;
            const vram_str = self.fmtBuf("{d:.1}/{d:.0}G", .{ vram_gb, total_gb });
            const bar_val = @as(f32, @floatFromInt(m.vram_used)) / @as(f32, @floatFromInt(m.vram_total));
            self.lines.append(self.allocator, .{ .label = "VRAM", .value = vram_str, .bar_value = bar_val }) catch {};
        }

        // Fan
        if (self.cfg.show_fan and m.fan_speed > 0) {
            const fan_str = self.fmtBuf("{d}%", .{m.fan_speed});
            self.lines.append(self.allocator, .{ .label = "Fan", .value = fan_str }) catch {};
        }

        // PCIe
        if (self.cfg.show_pcie and m.pcie_gen > 0) {
            const pcie_str = self.fmtBuf("Gen{d}x{d}", .{ m.pcie_gen, m.pcie_width });
            self.lines.append(self.allocator, .{ .label = "PCIe", .value = pcie_str }) catch {};
        }

        // Encoder
        if (self.cfg.show_encoder and m.encoder_util > 0) {
            const enc_str = self.fmtBuf("{d}%", .{m.encoder_util});
            self.lines.append(self.allocator, .{ .label = "NVENC", .value = enc_str }) catch {};
        }

        // P-state
        if (self.cfg.show_pstate) {
            const pstate_str = self.fmtBuf("P{d}", .{m.pstate});
            self.lines.append(self.allocator, .{ .label = "State", .value = pstate_str }) catch {};
        }
    }

    /// Generate render commands for current HUD state
    pub fn generateCommands(self: *Overlay, screen_width: u32, screen_height: u32) void {
        if (!self.visible) return;

        self.commands.clearRetainingCapacity();

        const padding = self.cfg.padding;
        const line_height: u32 = self.cfg.font_size + 4;
        const hud_width: u32 = 180;
        const hud_height: u32 = @as(u32, @intCast(self.lines.items.len)) * line_height + padding * 2;

        // Calculate position
        var x: i32 = @intCast(padding);
        var y: i32 = @intCast(padding);

        switch (self.cfg.position) {
            .top_left => {},
            .top_right => x = @as(i32, @intCast(screen_width)) - @as(i32, @intCast(hud_width)) - @as(i32, @intCast(padding)),
            .bottom_left => y = @as(i32, @intCast(screen_height)) - @as(i32, @intCast(hud_height)) - @as(i32, @intCast(padding)),
            .bottom_right => {
                x = @as(i32, @intCast(screen_width)) - @as(i32, @intCast(hud_width)) - @as(i32, @intCast(padding));
                y = @as(i32, @intCast(screen_height)) - @as(i32, @intCast(hud_height)) - @as(i32, @intCast(padding));
            },
            .top_center => x = @as(i32, @intCast(screen_width / 2)) - @as(i32, @intCast(hud_width / 2)),
            .bottom_center => {
                x = @as(i32, @intCast(screen_width / 2)) - @as(i32, @intCast(hud_width / 2));
                y = @as(i32, @intCast(screen_height)) - @as(i32, @intCast(hud_height)) - @as(i32, @intCast(padding));
            },
        }

        // Background
        self.commands.append(self.allocator, .{ .rect = .{
            .x = x,
            .y = y,
            .width = hud_width,
            .height = hud_height,
            .color = self.cfg.background_color,
        } }) catch {};

        // Lines
        var line_y = y + @as(i32, @intCast(padding));
        for (self.lines.items) |line| {
            // Label
            self.commands.append(self.allocator, .{ .text = .{
                .x = x + @as(i32, @intCast(padding)),
                .y = line_y,
                .text = line.label,
                .color = self.cfg.label_color,
                .size = self.cfg.font_size,
            } }) catch {};

            // Value
            self.commands.append(self.allocator, .{ .text = .{
                .x = x + @as(i32, @intCast(hud_width)) - @as(i32, @intCast(padding)) - 60,
                .y = line_y,
                .text = line.value,
                .color = line.color,
                .size = self.cfg.font_size,
            } }) catch {};

            // Optional bar
            if (line.bar_value) |val| {
                self.commands.append(self.allocator, .{ .bar = .{
                    .x = x + @as(i32, @intCast(hud_width)) - @as(i32, @intCast(padding)) - 50,
                    .y = line_y + @as(i32, @intCast(self.cfg.font_size)) - 4,
                    .width = 45,
                    .height = 3,
                    .value = val,
                    .color = self.cfg.accent_color,
                    .bg_color = config.Color{ .r = 60, .g = 60, .b = 60, .a = 255 },
                } }) catch {};
            }

            line_y += @as(i32, @intCast(line_height));
        }

        // Frame time graph
        if (self.cfg.show_frametime_graph and self.frame_times.count > 10) {
            const graph_height: u32 = 40;
            self.commands.append(self.allocator, .{ .graph = .{
                .x = x,
                .y = line_y,
                .width = hud_width,
                .height = graph_height,
                .values = self.frame_times.times[0..self.frame_times.count],
                .color = self.cfg.accent_color,
            } }) catch {};
        }
    }

    /// Get render commands
    pub fn getCommands(self: *const Overlay) []const RenderCommand {
        return self.commands.items;
    }

    /// Format into reusable buffer
    fn fmtBuf(self: *Overlay, comptime fmt: []const u8, args: anytype) []const u8 {
        if (self.str_idx >= self.str_buf.len) self.str_idx = 0;
        const buf = &self.str_buf[self.str_idx];
        self.str_idx += 1;
        const result = std.fmt.bufPrint(buf, fmt, args) catch return "";
        return result;
    }
};

/// Get current time in nanoseconds
fn getCurrentTimeNs() u64 {
    const now = std.time.Instant.now() catch return 0;
    const sec: u64 = @intCast(now.timestamp.sec);
    const nsec: u64 = @intCast(now.timestamp.nsec);
    return sec * 1_000_000_000 + nsec;
}

/// Vulkan layer entry points (for implicit layer)
pub const LayerManifest = struct {
    pub const name = "VK_LAYER_NVHUD_overlay";
    pub const description = "nvhud Performance Overlay";
    pub const api_version = "1.3.0";
    pub const implementation_version = "1";

    pub fn generateJson() []const u8 {
        return
            \\{
            \\  "file_format_version": "1.0.0",
            \\  "layer": {
            \\    "name": "VK_LAYER_NVHUD_overlay",
            \\    "type": "GLOBAL",
            \\    "library_path": "./libnvhud_layer.so",
            \\    "api_version": "1.3.0",
            \\    "implementation_version": "1",
            \\    "description": "nvhud Performance Overlay - NVIDIA GPU monitoring",
            \\    "functions": {
            \\      "vkGetInstanceProcAddr": "nvhud_vkGetInstanceProcAddr",
            \\      "vkGetDeviceProcAddr": "nvhud_vkGetDeviceProcAddr"
            \\    },
            \\    "enable_environment": {
            \\      "NVHUD": "1"
            \\    },
            \\    "disable_environment": {
            \\      "NVHUD": "0"
            \\    }
            \\  }
            \\}
        ;
    }
};

test "overlay init" {
    const cfg = config.Config.default();
    var overlay = Overlay.init(std.testing.allocator, cfg);
    defer overlay.deinit();

    try std.testing.expectEqual(State.disabled, overlay.state);
    try std.testing.expect(overlay.visible);
}

test "hud line building" {
    const cfg = config.Config.gaming();
    var overlay = Overlay.init(std.testing.allocator, cfg);
    defer overlay.deinit();

    overlay.buildHud();
    // Should have lines for FPS, frametime, temp, util, vram at minimum
    try std.testing.expect(overlay.lines.items.len >= 1);
}
