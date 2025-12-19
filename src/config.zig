//! nvhud Configuration
//!
//! Configuration management with file support.
//! Config file: ~/.config/nvhud/config.toml

const std = @import("std");
const fs = std.fs;
const mem = std.mem;

/// Overlay position
pub const Position = enum {
    top_left,
    top_right,
    bottom_left,
    bottom_right,
    top_center,
    bottom_center,

    pub fn toString(self: Position) []const u8 {
        return switch (self) {
            .top_left => "top-left",
            .top_right => "top-right",
            .bottom_left => "bottom-left",
            .bottom_right => "bottom-right",
            .top_center => "top-center",
            .bottom_center => "bottom-center",
        };
    }

    pub fn fromString(s: []const u8) Position {
        if (mem.eql(u8, s, "top-right")) return .top_right;
        if (mem.eql(u8, s, "bottom-left")) return .bottom_left;
        if (mem.eql(u8, s, "bottom-right")) return .bottom_right;
        if (mem.eql(u8, s, "top-center")) return .top_center;
        if (mem.eql(u8, s, "bottom-center")) return .bottom_center;
        return .top_left;
    }
};

/// Color in RGB
pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 255, .g = 80, .b = 80 };
    pub const green = Color{ .r = 80, .g = 255, .b = 80 };
    pub const yellow = Color{ .r = 255, .g = 200, .b = 80 };
    pub const cyan = Color{ .r = 80, .g = 200, .b = 255 };
    pub const purple = Color{ .r = 180, .g = 100, .b = 255 };

    // NVIDIA green
    pub const nvidia_green = Color{ .r = 118, .g = 185, .b = 0 };

    pub fn fromHex(hex: []const u8) Color {
        if (hex.len < 6) return white;
        const start: usize = if (hex[0] == '#') 1 else 0;
        if (hex.len < start + 6) return white;

        return Color{
            .r = std.fmt.parseInt(u8, hex[start .. start + 2], 16) catch 255,
            .g = std.fmt.parseInt(u8, hex[start + 2 .. start + 4], 16) catch 255,
            .b = std.fmt.parseInt(u8, hex[start + 4 .. start + 6], 16) catch 255,
        };
    }
};

/// HUD configuration
pub const Config = struct {
    // Display toggles
    show_fps: bool = true,
    show_frametime: bool = true,
    show_frametime_graph: bool = false,
    show_gpu_temp: bool = true,
    show_gpu_util: bool = true,
    show_gpu_clock: bool = false,
    show_gpu_power: bool = false,
    show_vram: bool = true,
    show_cpu: bool = false,
    show_ram: bool = false,
    show_fan: bool = false,
    show_pcie: bool = false,
    show_encoder: bool = false,
    show_pstate: bool = false,
    show_latency: bool = false, // NVIDIA Reflex latency (requires nvvk)

    // Overlay settings
    position: Position = .top_left,
    opacity: f32 = 0.85,
    scale: f32 = 1.0,
    font_size: u32 = 16,
    padding: u32 = 10,
    update_interval_ms: u32 = 100,

    // Colors
    background_color: Color = Color{ .r = 20, .g = 20, .b = 30, .a = 220 },
    text_color: Color = Color.white,
    label_color: Color = Color{ .r = 180, .g = 180, .b = 180 },
    accent_color: Color = Color.nvidia_green,
    warning_color: Color = Color.yellow,
    critical_color: Color = Color.red,

    // Thresholds
    temp_warning: u32 = 75,
    temp_critical: u32 = 85,
    gpu_util_warning: u32 = 95,
    vram_warning_percent: u32 = 85,
    power_warning_percent: u32 = 95,

    // Hotkeys (as scancodes)
    toggle_key: u32 = 123, // F12
    toggle_modifier: u32 = 54, // Right Shift

    /// Create default config
    pub fn default() Config {
        return .{};
    }

    /// Minimal config (FPS only)
    pub fn minimal() Config {
        return Config{
            .show_fps = true,
            .show_frametime = false,
            .show_gpu_temp = false,
            .show_gpu_util = false,
            .show_vram = false,
        };
    }

    /// Gaming config
    pub fn gaming() Config {
        return Config{
            .show_fps = true,
            .show_frametime = true,
            .show_frametime_graph = true,
            .show_gpu_temp = true,
            .show_gpu_util = true,
            .show_vram = true,
        };
    }

    /// Full config (all metrics)
    pub fn full() Config {
        return Config{
            .show_fps = true,
            .show_frametime = true,
            .show_frametime_graph = true,
            .show_gpu_temp = true,
            .show_gpu_util = true,
            .show_gpu_clock = true,
            .show_gpu_power = true,
            .show_vram = true,
            .show_cpu = true,
            .show_ram = true,
            .show_fan = true,
            .show_pcie = true,
            .show_encoder = true,
            .show_pstate = true,
            .show_latency = true,
        };
    }

    /// Benchmark config
    pub fn benchmark() Config {
        return Config{
            .show_fps = true,
            .show_frametime = true,
            .show_frametime_graph = true,
            .show_gpu_temp = true,
            .show_gpu_util = true,
            .show_gpu_clock = true,
            .show_gpu_power = true,
            .show_vram = true,
            .update_interval_ms = 50,
        };
    }

    /// Load config from file
    pub fn load(allocator: mem.Allocator) !Config {
        _ = allocator;
        const home = std.posix.getenv("HOME") orelse return Config.default();
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/.config/nvhud/config.toml", .{home}) catch return Config.default();

        const file = fs.cwd().openFile(path, .{}) catch return Config.default();
        defer file.close();

        // Read file content into a static buffer (max 64KB)
        var content_buf: [64 * 1024]u8 = undefined;
        const bytes_read = file.read(&content_buf) catch return Config.default();
        const content = content_buf[0..bytes_read];

        return parseToml(content);
    }

    /// Parse TOML config (simplified parser)
    fn parseToml(content: []const u8) Config {
        var config = Config.default();

        var lines = mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == '[') continue;

            if (mem.indexOf(u8, trimmed, "=")) |eq_idx| {
                const key = mem.trim(u8, trimmed[0..eq_idx], " \t");
                const value = mem.trim(u8, trimmed[eq_idx + 1 ..], " \t\"");

                // Parse boolean options
                if (mem.eql(u8, key, "show_fps")) config.show_fps = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_frametime")) config.show_frametime = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_frametime_graph")) config.show_frametime_graph = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_gpu_temp")) config.show_gpu_temp = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_gpu_util")) config.show_gpu_util = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_gpu_clock")) config.show_gpu_clock = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_gpu_power")) config.show_gpu_power = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_vram")) config.show_vram = mem.eql(u8, value, "true");
                if (mem.eql(u8, key, "show_fan")) config.show_fan = mem.eql(u8, value, "true");

                // Parse position
                if (mem.eql(u8, key, "position")) config.position = Position.fromString(value);

                // Parse numbers
                if (mem.eql(u8, key, "font_size")) config.font_size = std.fmt.parseInt(u32, value, 10) catch 16;
                if (mem.eql(u8, key, "update_interval_ms")) config.update_interval_ms = std.fmt.parseInt(u32, value, 10) catch 100;
                if (mem.eql(u8, key, "temp_warning")) config.temp_warning = std.fmt.parseInt(u32, value, 10) catch 75;
                if (mem.eql(u8, key, "temp_critical")) config.temp_critical = std.fmt.parseInt(u32, value, 10) catch 85;

                // Parse floats
                if (mem.eql(u8, key, "opacity")) config.opacity = std.fmt.parseFloat(f32, value) catch 0.85;
                if (mem.eql(u8, key, "scale")) config.scale = std.fmt.parseFloat(f32, value) catch 1.0;

                // Parse colors
                if (mem.eql(u8, key, "text_color")) config.text_color = Color.fromHex(value);
                if (mem.eql(u8, key, "accent_color")) config.accent_color = Color.fromHex(value);
                if (mem.eql(u8, key, "background_color")) config.background_color = Color.fromHex(value);
            }
        }

        return config;
    }

    /// Save config to file
    pub fn save(self: *const Config, allocator: mem.Allocator) !void {
        _ = allocator;
        const home = std.posix.getenv("HOME") orelse return error.NoHome;

        // Create directory if needed
        var dir_path_buf: [512]u8 = undefined;
        const dir_path = try std.fmt.bufPrint(&dir_path_buf, "{s}/.config/nvhud", .{home});
        fs.cwd().makePath(dir_path) catch {};

        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/.config/nvhud/config.toml", .{home});

        const file = try fs.cwd().createFile(path, .{});
        defer file.close();

        // Write config directly with multiple writes
        var line_buf: [256]u8 = undefined;

        _ = try file.write("# nvhud configuration\n\n[metrics]\n");

        var line = std.fmt.bufPrint(&line_buf, "show_fps = {s}\n", .{if (self.show_fps) "true" else "false"}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "show_frametime = {s}\n", .{if (self.show_frametime) "true" else "false"}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "show_frametime_graph = {s}\n", .{if (self.show_frametime_graph) "true" else "false"}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "show_gpu_temp = {s}\n", .{if (self.show_gpu_temp) "true" else "false"}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "show_gpu_util = {s}\n", .{if (self.show_gpu_util) "true" else "false"}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "show_vram = {s}\n", .{if (self.show_vram) "true" else "false"}) catch return;
        _ = try file.write(line);

        _ = try file.write("\n[overlay]\n");
        line = std.fmt.bufPrint(&line_buf, "position = \"{s}\"\n", .{self.position.toString()}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "update_interval_ms = {d}\n", .{self.update_interval_ms}) catch return;
        _ = try file.write(line);

        _ = try file.write("\n[thresholds]\n");
        line = std.fmt.bufPrint(&line_buf, "temp_warning = {d}\n", .{self.temp_warning}) catch return;
        _ = try file.write(line);
        line = std.fmt.bufPrint(&line_buf, "temp_critical = {d}\n", .{self.temp_critical}) catch return;
        _ = try file.write(line);
    }

    /// Generate default config file content
    pub fn generateDefaultConfig() []const u8 {
        return
            \\# nvhud configuration
            \\# Place this file at ~/.config/nvhud/config.toml
            \\
            \\[metrics]
            \\show_fps = true
            \\show_frametime = true
            \\show_frametime_graph = false
            \\show_gpu_temp = true
            \\show_gpu_util = true
            \\show_gpu_clock = false
            \\show_gpu_power = false
            \\show_vram = true
            \\show_cpu = false
            \\show_ram = false
            \\show_fan = false
            \\show_pcie = false
            \\show_encoder = false
            \\
            \\[overlay]
            \\position = "top-left"
            \\opacity = 0.85
            \\scale = 1.0
            \\font_size = 16
            \\padding = 10
            \\update_interval_ms = 100
            \\
            \\[colors]
            \\background_color = "#14141e"
            \\text_color = "#ffffff"
            \\label_color = "#b4b4b4"
            \\accent_color = "#76b900"
            \\warning_color = "#ffc850"
            \\critical_color = "#ff5050"
            \\
            \\[thresholds]
            \\temp_warning = 75
            \\temp_critical = 85
            \\gpu_util_warning = 95
            \\vram_warning_percent = 85
            \\power_warning_percent = 95
            \\
            \\[hotkeys]
            \\# Toggle overlay: Right Shift + F12
            \\toggle_key = 123
            \\toggle_modifier = 54
            \\
        ;
    }
};

test "config defaults" {
    const config = Config.default();
    try std.testing.expect(config.show_fps);
    try std.testing.expect(config.show_gpu_temp);
    try std.testing.expectEqual(Position.top_left, config.position);
}

test "color from hex" {
    const color = Color.fromHex("#76b900");
    try std.testing.expectEqual(@as(u8, 118), color.r);
    try std.testing.expectEqual(@as(u8, 185), color.g);
    try std.testing.expectEqual(@as(u8, 0), color.b);
}

test "position from string" {
    try std.testing.expectEqual(Position.top_right, Position.fromString("top-right"));
    try std.testing.expectEqual(Position.bottom_left, Position.fromString("bottom-left"));
    try std.testing.expectEqual(Position.top_left, Position.fromString("invalid"));
}
