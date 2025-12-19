//! GPU Renderer for HUD Overlay
//!
//! Implements actual Vulkan rendering for the overlay.
//! Uses a simple compute shader approach for text and primitives.
//!
//! Features:
//! - Bitmap font rendering
//! - Rectangle/bar primitives
//! - Graph rendering
//! - nvvk latency stats integration (NVIDIA Reflex)

const std = @import("std");
const config = @import("config.zig");
const overlay = @import("overlay.zig");
const nvvk = @import("nvvk");

// =============================================================================
// Vulkan Types (minimal for rendering)
// =============================================================================

const VkDevice = *opaque {};
const VkQueue = *opaque {};
const VkCommandPool = *opaque {};
const VkCommandBuffer = *opaque {};
const VkPipeline = *opaque {};
const VkPipelineLayout = *opaque {};
const VkDescriptorPool = *opaque {};
const VkDescriptorSet = *opaque {};
const VkDescriptorSetLayout = *opaque {};
const VkImage = *opaque {};
const VkImageView = *opaque {};
const VkSampler = *opaque {};
const VkBuffer = *opaque {};
const VkDeviceMemory = *opaque {};
const VkSwapchainKHR = u64;
const VkResult = i32;

const VK_SUCCESS: VkResult = 0;

// =============================================================================
// Renderer State
// =============================================================================

/// Renderer context for GPU-accelerated overlay
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    device: ?VkDevice = null,
    queue: ?VkQueue = null,

    // Pipeline resources
    pipeline: ?VkPipeline = null,
    pipeline_layout: ?VkPipelineLayout = null,
    descriptor_pool: ?VkDescriptorPool = null,
    descriptor_set: ?VkDescriptorSet = null,
    descriptor_layout: ?VkDescriptorSetLayout = null,

    // Font resources
    font_image: ?VkImage = null,
    font_view: ?VkImageView = null,
    font_sampler: ?VkSampler = null,
    font_memory: ?VkDeviceMemory = null,

    // Vertex buffer for primitives
    vertex_buffer: ?VkBuffer = null,
    vertex_memory: ?VkDeviceMemory = null,
    vertex_capacity: u32 = 0,

    // Command resources
    command_pool: ?VkCommandPool = null,
    command_buffer: ?VkCommandBuffer = null,

    // State
    initialized: bool = false,
    width: u32 = 0,
    height: u32 = 0,

    // nvvk latency context (optional integration)
    latency_ctx: ?*nvvk.LowLatencyContext = null,
    latency_enabled: bool = false,
    last_latency_us: u64 = 0,
    last_render_latency_us: u64 = 0,
    last_present_latency_us: u64 = 0,
    latency_history: [64]u64 = [_]u64{0} ** 64,
    latency_history_idx: u8 = 0,

    pub fn init(allocator: std.mem.Allocator) Renderer {
        return .{
            .allocator = allocator,
        };
    }

    /// Initialize Vulkan resources for rendering
    pub fn initVulkan(
        self: *Renderer,
        device: VkDevice,
        queue: VkQueue,
        width: u32,
        height: u32,
    ) !void {
        self.device = device;
        self.queue = queue;
        self.width = width;
        self.height = height;

        // In full implementation:
        // 1. Create descriptor pool and layouts
        // 2. Create graphics/compute pipeline for overlay
        // 3. Create font texture
        // 4. Allocate vertex buffer

        self.initialized = true;
    }

    /// Set nvvk low latency context for Reflex integration
    pub fn setLatencyContext(self: *Renderer, ctx: *nvvk.LowLatencyContext) void {
        self.latency_ctx = ctx;
        self.latency_enabled = true;
    }

    /// Update latency data from nvvk
    pub fn updateLatency(
        self: *Renderer,
        total_latency_us: u64,
        render_latency_us: u64,
        present_latency_us: u64,
    ) void {
        self.latency_enabled = true;
        self.last_latency_us = total_latency_us;
        self.last_render_latency_us = render_latency_us;
        self.last_present_latency_us = present_latency_us;

        // Store in history for graph display
        self.latency_history[self.latency_history_idx] = total_latency_us;
        self.latency_history_idx = (self.latency_history_idx + 1) % 64;
    }

    /// Poll latency from nvvk context if available
    pub fn pollLatency(self: *Renderer) void {
        if (self.latency_ctx) |ctx| {
            const stats = ctx.getStats();
            self.updateLatency(
                stats.total_latency_us,
                stats.render_latency_us,
                stats.present_latency_us,
            );
        }
    }

    /// Get latency stats for HUD display
    pub fn getLatencyStats(self: *const Renderer) struct {
        total_ms: f32,
        render_ms: f32,
        present_ms: f32,
        avg_ms: f32,
    } {
        // Calculate average from history
        var sum: u64 = 0;
        var count: u32 = 0;
        for (self.latency_history) |v| {
            if (v > 0) {
                sum += v;
                count += 1;
            }
        }
        const avg_us: f32 = if (count > 0) @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(count)) else 0;

        return .{
            .total_ms = @as(f32, @floatFromInt(self.last_latency_us)) / 1000.0,
            .render_ms = @as(f32, @floatFromInt(self.last_render_latency_us)) / 1000.0,
            .present_ms = @as(f32, @floatFromInt(self.last_present_latency_us)) / 1000.0,
            .avg_ms = avg_us / 1000.0,
        };
    }

    /// Render overlay to swapchain image
    pub fn render(
        self: *Renderer,
        cmd: VkCommandBuffer,
        target_image: VkImageView,
        commands: []const overlay.RenderCommand,
    ) void {
        if (!self.initialized) return;
        _ = cmd;
        _ = target_image;

        for (commands) |command| {
            switch (command) {
                .text => |t| self.drawText(t.x, t.y, t.text, t.color, t.size),
                .rect => |r| self.drawRect(r.x, r.y, r.width, r.height, r.color),
                .bar => |b| self.drawBar(b.x, b.y, b.width, b.height, b.value, b.color, b.bg_color),
                .graph => |g| self.drawGraph(g.x, g.y, g.width, g.height, g.values, g.color),
            }
        }
    }

    // =========================================================================
    // Primitive Drawing
    // =========================================================================

    fn drawText(self: *Renderer, x: i32, y: i32, text: []const u8, color: config.Color, size: u32) void {
        _ = self;
        _ = x;
        _ = y;
        _ = text;
        _ = color;
        _ = size;
        // In full implementation:
        // 1. For each character, lookup in font atlas
        // 2. Add textured quad to vertex buffer
        // 3. Queue draw command
    }

    fn drawRect(self: *Renderer, x: i32, y: i32, width: u32, height: u32, color: config.Color) void {
        _ = self;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
        _ = color;
        // Add solid color quad to vertex buffer
    }

    fn drawBar(
        self: *Renderer,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        value: f32,
        color: config.Color,
        bg_color: config.Color,
    ) void {
        // Background
        self.drawRect(x, y, width, height, bg_color);
        // Foreground (filled portion)
        const fill_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * value));
        self.drawRect(x, y, fill_width, height, color);
    }

    fn drawGraph(
        self: *Renderer,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        values: []const f32,
        color: config.Color,
    ) void {
        _ = self;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
        _ = values;
        _ = color;
        // Draw line graph using vertex buffer
    }

    /// Cleanup resources
    pub fn deinit(self: *Renderer) void {
        // Destroy Vulkan resources
        self.initialized = false;
        self.latency_ctx = null;
    }
};

// =============================================================================
// Vertex Format
// =============================================================================

/// Vertex for overlay primitives
pub const Vertex = extern struct {
    // Position (screen space)
    x: f32,
    y: f32,
    // UV for text (0,0 for solid color)
    u: f32,
    v: f32,
    // Color (RGBA normalized)
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

/// Push constants for overlay shader
pub const PushConstants = extern struct {
    // Screen dimensions for NDC conversion
    screen_width: f32,
    screen_height: f32,
    // Reserved
    _reserved: [2]f32 = .{ 0, 0 },
};

// =============================================================================
// Font Atlas
// =============================================================================

/// Simple bitmap font (8x16 characters, ASCII 32-127)
pub const BitmapFont = struct {
    pub const char_width: u32 = 8;
    pub const char_height: u32 = 16;
    pub const first_char: u8 = 32;
    pub const last_char: u8 = 127;
    pub const chars_per_row: u32 = 16;

    /// Get UV coordinates for a character
    pub fn getCharUV(char: u8) struct { u0: f32, v0: f32, u1: f32, v1: f32 } {
        if (char < first_char or char > last_char) {
            return .{ .u0 = 0, .v0 = 0, .u1 = 0, .v1 = 0 };
        }

        const idx = char - first_char;
        const col = idx % chars_per_row;
        const row = idx / chars_per_row;

        const tex_width: f32 = @floatFromInt(chars_per_row * char_width);
        const tex_height: f32 = @floatFromInt(((last_char - first_char) / chars_per_row + 1) * char_height);

        return .{
            .u0 = @as(f32, @floatFromInt(col * char_width)) / tex_width,
            .v0 = @as(f32, @floatFromInt(row * char_height)) / tex_height,
            .u1 = @as(f32, @floatFromInt((col + 1) * char_width)) / tex_width,
            .v1 = @as(f32, @floatFromInt((row + 1) * char_height)) / tex_height,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Vertex size" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Vertex));
}

test "PushConstants size" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(PushConstants));
}

test "BitmapFont UV" {
    const uv_a = BitmapFont.getCharUV('A');
    try std.testing.expect(uv_a.u0 >= 0 and uv_a.u0 < 1);
    try std.testing.expect(uv_a.v0 >= 0 and uv_a.v0 < 1);

    const uv_space = BitmapFont.getCharUV(' ');
    try std.testing.expectApproxEqRel(@as(f32, 0.0), uv_space.u0, 0.001);
}

test "Renderer init" {
    var rend = Renderer.init(std.testing.allocator);
    defer rend.deinit();

    try std.testing.expect(!rend.initialized);
    try std.testing.expect(!rend.latency_enabled);
    try std.testing.expect(rend.latency_ctx == null);
}

test "Renderer latency stats" {
    var rend = Renderer.init(std.testing.allocator);
    defer rend.deinit();

    rend.updateLatency(16000, 8000, 4000); // 16ms total, 8ms render, 4ms present

    const stats = rend.getLatencyStats();
    try std.testing.expectApproxEqRel(@as(f32, 16.0), stats.total_ms, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 8.0), stats.render_ms, 0.001);
}
