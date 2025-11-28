//! nvhud CLI - NVIDIA GPU Performance Monitor
//!
//! A MangoHud alternative for NVIDIA enthusiasts.
//! Real-time GPU monitoring with direct NVML integration.

const std = @import("std");
const nvhud = @import("nvhud");
const posix = std.posix;
const fs = std.fs;
const mem = std.mem;

// ANSI color codes
const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";

    const black = "\x1b[30m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const cyan = "\x1b[36m";
    const white = "\x1b[37m";

    const bright_black = "\x1b[90m";
    const bright_red = "\x1b[91m";
    const bright_green = "\x1b[92m";
    const bright_yellow = "\x1b[93m";
    const bright_blue = "\x1b[94m";
    const bright_magenta = "\x1b[95m";
    const bright_cyan = "\x1b[96m";
    const bright_white = "\x1b[97m";

    const bg_black = "\x1b[40m";
    const bg_green = "\x1b[42m";

    // NVIDIA green
    const nvidia = "\x1b[38;2;118;185;0m";
};

/// Sleep for nanoseconds (Zig 0.16 API)
fn sleep(ns: u64) void {
    const secs = ns / std.time.ns_per_s;
    const nanos = ns % std.time.ns_per_s;
    std.posix.nanosleep(secs, nanos);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (mem.eql(u8, command, "status")) {
        try statusCommand(allocator);
    } else if (mem.eql(u8, command, "info")) {
        try infoCommand(allocator);
    } else if (mem.eql(u8, command, "metrics")) {
        try metricsCommand(allocator);
    } else if (mem.eql(u8, command, "watch")) {
        try watchCommand(allocator, args[2..]);
    } else if (mem.eql(u8, command, "config")) {
        try configCommand(allocator, args[2..]);
    } else if (mem.eql(u8, command, "json")) {
        try jsonCommand(allocator, args[2..]);
    } else if (mem.eql(u8, command, "benchmark")) {
        try benchmarkCommand(allocator, args[2..]);
    } else if (mem.eql(u8, command, "help") or mem.eql(u8, command, "--help") or mem.eql(u8, command, "-h")) {
        printUsage();
    } else if (mem.eql(u8, command, "version") or mem.eql(u8, command, "--version") or mem.eql(u8, command, "-v")) {
        printVersion();
    } else {
        std.debug.print("{s}Unknown command: {s}{s}\n\n", .{ Color.red, command, Color.reset });
        printUsage();
    }
}

fn printUsage() void {
    const c = Color.nvidia;
    const r = Color.reset;
    const h = Color.bright_cyan;
    const g = Color.green;
    const y = Color.yellow;
    const d = Color.dim;

    std.debug.print("{s}nvhud{s} - NVIDIA GPU Performance Monitor {s}v{s}{s}\n\n", .{ c, r, d, nvhud.version_string, r });

    std.debug.print("{s}USAGE:{s}\n    nvhud <command> [options]\n\n", .{ h, r });

    std.debug.print("{s}COMMANDS:{s}\n", .{ h, r });
    std.debug.print("    {s}status{s}              Show GPU status summary\n", .{ g, r });
    std.debug.print("    {s}info{s}                Show detailed GPU information\n", .{ g, r });
    std.debug.print("    {s}metrics{s}             Show current GPU metrics with bars\n", .{ g, r });
    std.debug.print("    {s}watch{s} [interval]    Monitor GPU metrics in real-time\n", .{ g, r });
    std.debug.print("    {s}benchmark{s} [secs]    Record metrics for benchmarking\n", .{ g, r });
    std.debug.print("    {s}config{s} [preset]     Show/set HUD configuration\n", .{ g, r });
    std.debug.print("    {s}json{s} <subcommand>   Output as JSON (status, metrics, info)\n", .{ g, r });
    std.debug.print("    {s}help{s}                Show this help message\n", .{ g, r });
    std.debug.print("    {s}version{s}             Show version information\n\n", .{ g, r });

    std.debug.print("{s}EXAMPLES:{s}\n", .{ h, r });
    std.debug.print("    nvhud status\n    nvhud metrics\n    nvhud watch 1\n", .{});
    std.debug.print("    nvhud benchmark 60\n    nvhud config gaming\n    nvhud json metrics\n\n", .{});

    std.debug.print("{s}OVERLAY:{s}\n", .{ h, r });
    std.debug.print("    Enable the Vulkan overlay for in-game monitoring:\n", .{});
    std.debug.print("    {s}NVHUD=1{s} ./game\n\n", .{ y, r });
    std.debug.print("    Or add to Steam launch options:\n    {s}NVHUD=1 %command%{s}\n\n", .{ y, r });

    std.debug.print("{s}ENVIRONMENT:{s}\n", .{ h, r });
    std.debug.print("    NVHUD=1              Enable overlay\n", .{});
    std.debug.print("    NVHUD_POSITION=...   Set position (top-left, top-right, etc.)\n", .{});
    std.debug.print("    NVHUD_CONFIG=...     Path to config file\n\n", .{});
}

fn printVersion() void {
    const c = Color.nvidia;
    const r = Color.reset;
    const g = Color.green;

    std.debug.print("{s}nvhud{s} v{s}\n", .{ c, r, nvhud.version_string });
    std.debug.print("NVIDIA GPU Performance Overlay\n\n", .{});
    std.debug.print("Features:\n", .{});
    std.debug.print("  {s}+{s} Direct NVML integration (no nvidia-smi)\n", .{ g, r });
    std.debug.print("  {s}+{s} GPU-accelerated Vulkan overlay\n", .{ g, r });
    std.debug.print("  {s}+{s} <1% performance overhead\n", .{ g, r });
    std.debug.print("  {s}+{s} Full NVIDIA telemetry\n\n", .{ g, r });
}

fn statusCommand(allocator: mem.Allocator) !void {
    _ = allocator;

    std.debug.print("\n{s}--- nvhud GPU Status ---{s}\n\n", .{ Color.nvidia, Color.reset });

    var collector = nvhud.createCollector();
    defer collector.deinit();

    if (!collector.isAvailable()) {
        std.debug.print("{s}X{s} NVIDIA GPU not detected\n", .{ Color.red, Color.reset });
        std.debug.print("\n  Make sure NVIDIA drivers are installed and loaded.\n", .{});
        return;
    }

    const info = collector.getInfo();
    const m = collector.collect();

    std.debug.print("{s}+{s} NVIDIA GPU Detected\n\n", .{ Color.green, Color.reset });

    // GPU Info
    if (info.name_len > 0) {
        std.debug.print("  {s}Model:{s}       {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.bright_white, info.getName(), Color.reset });
    }
    if (info.driver_len > 0) {
        std.debug.print("  {s}Driver:{s}      {s}\n", .{ Color.dim, Color.reset, info.getDriver() });
    }
    if (info.arch_len > 0) {
        std.debug.print("  {s}Architecture:{s} {s}\n", .{ Color.dim, Color.reset, info.getArchitecture() });
    }

    std.debug.print("\n", .{});

    // Current metrics
    if (m.temperature > 0) {
        const temp_color = if (m.temperature >= 85) Color.red else if (m.temperature >= 75) Color.yellow else Color.green;
        std.debug.print("  {s}Temperature:{s}  {s}{d}C{s}\n", .{ Color.dim, Color.reset, temp_color, m.temperature, Color.reset });
    }

    if (m.gpu_util > 0) {
        std.debug.print("  {s}GPU Usage:{s}    {s}{d}%{s}\n", .{ Color.dim, Color.reset, Color.cyan, m.gpu_util, Color.reset });
    }

    if (m.power_draw > 0) {
        std.debug.print("  {s}Power:{s}        {d}W / {d}W\n", .{ Color.dim, Color.reset, m.power_draw, m.power_limit });
    }

    if (m.vram_total > 0) {
        const vram_pct = m.vramUsagePercent();
        const vram_color = if (vram_pct >= 90) Color.red else if (vram_pct >= 75) Color.yellow else Color.reset;
        std.debug.print("  {s}VRAM:{s}         {s}{d}{s} / {d} MB ({d:.1}%)\n", .{
            Color.dim,
            Color.reset,
            vram_color,
            m.vram_used,
            Color.reset,
            m.vram_total,
            vram_pct,
        });
    }

    std.debug.print("\n", .{});
}

fn infoCommand(allocator: mem.Allocator) !void {
    _ = allocator;

    std.debug.print("\n{s}--- nvhud GPU Information ---{s}\n\n", .{ Color.nvidia, Color.reset });

    var collector = nvhud.createCollector();
    defer collector.deinit();

    if (!collector.isAvailable()) {
        std.debug.print("{s}X{s} NVIDIA GPU not detected.\n", .{ Color.red, Color.reset });
        return;
    }

    const info = collector.getInfo();
    const m = collector.collect();

    std.debug.print("{s}GPU Hardware{s}\n", .{ Color.bright_cyan, Color.reset });
    std.debug.print("  Name:          {s}{s}{s}\n", .{ Color.bright_white, info.getName(), Color.reset });
    std.debug.print("  Architecture:  {s}\n", .{info.getArchitecture()});
    std.debug.print("  VRAM:          {d} MB\n", .{info.vram_total_mb});
    std.debug.print("  PCIe:          Gen{d} x{d}\n", .{ m.pcie_gen, m.pcie_width });

    std.debug.print("\n{s}Driver{s}\n", .{ Color.bright_cyan, Color.reset });
    std.debug.print("  Version:       {s}\n", .{info.getDriver()});

    std.debug.print("\n{s}Current Clocks{s}\n", .{ Color.bright_cyan, Color.reset });
    std.debug.print("  GPU:           {d} MHz\n", .{m.gpu_clock});
    std.debug.print("  Memory:        {d} MHz\n", .{m.mem_clock});
    std.debug.print("  P-State:       P{d}\n", .{m.pstate});

    std.debug.print("\n{s}nvhud{s}\n", .{ Color.bright_cyan, Color.reset });
    std.debug.print("  Version:       {s}\n", .{nvhud.version_string});
    std.debug.print("  NVML:          {s}Available{s}\n", .{ Color.green, Color.reset });

    std.debug.print("\n{s}Capabilities{s}\n", .{ Color.bright_cyan, Color.reset });
    std.debug.print("  {s}+{s} Temperature monitoring\n", .{ Color.green, Color.reset });
    std.debug.print("  {s}+{s} Power monitoring\n", .{ Color.green, Color.reset });
    std.debug.print("  {s}+{s} Clock monitoring\n", .{ Color.green, Color.reset });
    std.debug.print("  {s}+{s} VRAM tracking\n", .{ Color.green, Color.reset });
    std.debug.print("  {s}+{s} Encoder/Decoder usage\n", .{ Color.green, Color.reset });
    std.debug.print("  {s}o{s} Vulkan overlay (use NVHUD=1)\n", .{ Color.yellow, Color.reset });

    std.debug.print("\n", .{});
}

fn metricsCommand(allocator: mem.Allocator) !void {
    _ = allocator;

    var collector = nvhud.createCollector();
    defer collector.deinit();

    if (!collector.isAvailable()) {
        std.debug.print("{s}X{s} NVIDIA GPU not detected.\n", .{ Color.red, Color.reset });
        return;
    }

    const m = collector.collect();

    std.debug.print("\n{s}--- GPU Metrics ---{s}\n\n", .{ Color.nvidia, Color.reset });

    // Temperature
    if (m.temperature > 0) {
        const temp_color = if (m.temperature >= 85) Color.red else if (m.temperature >= 75) Color.yellow else Color.green;
        const bar = makeColorBar(m.temperature, 100, 25, temp_color);
        std.debug.print("  {s}Temp{s}    {s}{d:>3}C{s}   {s}\n", .{ Color.dim, Color.reset, temp_color, m.temperature, Color.reset, bar });
    }

    // GPU Utilization
    if (m.gpu_util > 0) {
        const bar = makeColorBar(m.gpu_util, 100, 25, Color.nvidia);
        std.debug.print("  {s}GPU{s}     {s}{d:>3}%{s}   {s}\n", .{ Color.dim, Color.reset, Color.cyan, m.gpu_util, Color.reset, bar });
    }

    // Power
    if (m.power_draw > 0 and m.power_limit > 0) {
        const pct: u32 = @intFromFloat(m.powerUsagePercent());
        const power_color = if (pct >= 95) Color.yellow else Color.reset;
        const bar = makeColorBar(pct, 100, 25, Color.nvidia);
        std.debug.print("  {s}Power{s}   {s}{d:>3}W{s}   {s}  ({d}W limit)\n", .{ Color.dim, Color.reset, power_color, m.power_draw, Color.reset, bar, m.power_limit });
    }

    // Fan
    if (m.fan_speed > 0) {
        const bar = makeColorBar(m.fan_speed, 100, 25, Color.cyan);
        std.debug.print("  {s}Fan{s}     {d:>3}%   {s}\n", .{ Color.dim, Color.reset, m.fan_speed, bar });
    }

    // VRAM
    if (m.vram_total > 0) {
        const vram_pct: u32 = @intFromFloat(m.vramUsagePercent());
        const vram_color = if (vram_pct >= 90) Color.red else if (vram_pct >= 75) Color.yellow else Color.nvidia;
        const bar = makeColorBar(vram_pct, 100, 25, vram_color);
        const used_gb = @as(f32, @floatFromInt(m.vram_used)) / 1024.0;
        const total_gb = @as(f32, @floatFromInt(m.vram_total)) / 1024.0;
        std.debug.print("  {s}VRAM{s}    {d:.1}/{d:.0}G {s}\n", .{ Color.dim, Color.reset, used_gb, total_gb, bar });
    }

    // Clocks
    std.debug.print("\n  {s}Clocks{s}\n", .{ Color.bright_cyan, Color.reset });
    if (m.gpu_clock > 0) {
        std.debug.print("    GPU:     {s}{d:>4} MHz{s}\n", .{ Color.bright_white, m.gpu_clock, Color.reset });
    }
    if (m.mem_clock > 0) {
        std.debug.print("    Memory:  {d:>4} MHz\n", .{m.mem_clock});
    }

    // PCIe
    if (m.pcie_gen > 0) {
        std.debug.print("\n  {s}PCIe{s}      Gen{d} x{d}\n", .{ Color.dim, Color.reset, m.pcie_gen, m.pcie_width });
    }

    // Encoder/Decoder
    if (m.encoder_util > 0 or m.decoder_util > 0) {
        std.debug.print("\n  {s}Video{s}\n", .{ Color.bright_cyan, Color.reset });
        if (m.encoder_util > 0) {
            std.debug.print("    NVENC:   {d}%\n", .{m.encoder_util});
        }
        if (m.decoder_util > 0) {
            std.debug.print("    NVDEC:   {d}%\n", .{m.decoder_util});
        }
    }

    std.debug.print("\n", .{});
}

fn watchCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    _ = allocator;

    const interval_secs: u64 = if (args.len > 0)
        std.fmt.parseInt(u64, args[0], 10) catch 1
    else
        1;

    var collector = nvhud.createCollector();
    defer collector.deinit();

    if (!collector.isAvailable()) {
        std.debug.print("{s}X{s} NVIDIA GPU not detected.\n", .{ Color.red, Color.reset });
        return;
    }

    // Hide cursor
    std.debug.print("\x1b[?25l", .{});
    defer std.debug.print("\x1b[?25h", .{}); // Show cursor on exit

    // Clear screen and move to top
    std.debug.print("\x1b[2J\x1b[H", .{});

    std.debug.print("{s}nvhud{s} - Real-time GPU Monitor (Ctrl+C to stop)\n", .{ Color.nvidia, Color.reset });
    std.debug.print("{s}----------------------------------------------------------------{s}\n", .{ Color.dim, Color.reset });
    std.debug.print("  {s}Temp    GPU     Power    Fan     VRAM            Clocks{s}\n", .{ Color.bright_cyan, Color.reset });
    std.debug.print("{s}----------------------------------------------------------------{s}\n", .{ Color.dim, Color.reset });

    while (true) {
        const m = collector.collect();

        // Move to line 5
        std.debug.print("\x1b[5;1H\x1b[2K", .{});

        const temp_color = if (m.temperature >= 85) Color.red else if (m.temperature >= 75) Color.yellow else Color.green;
        const used_gb = @as(f32, @floatFromInt(m.vram_used)) / 1024.0;
        const total_gb = @as(f32, @floatFromInt(m.vram_total)) / 1024.0;

        std.debug.print("  {s}{d:>3}C{s}   {d:>3}%    {d:>4}W   {d:>3}%   {d:>5.1}/{d:<4.0}G    {d:>4}/{d:<5}MHz", .{
            temp_color,
            m.temperature,
            Color.reset,
            m.gpu_util,
            m.power_draw,
            m.fan_speed,
            used_gb,
            total_gb,
            m.gpu_clock,
            m.mem_clock,
        });

        // Sleep using our wrapper
        sleep(interval_secs * std.time.ns_per_s);
    }
}

fn benchmarkCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    const duration_secs: u64 = if (args.len > 0)
        std.fmt.parseInt(u64, args[0], 10) catch 60
    else
        60;

    var collector = nvhud.createCollector();
    defer collector.deinit();

    if (!collector.isAvailable()) {
        std.debug.print("{s}X{s} NVIDIA GPU not detected.\n", .{ Color.red, Color.reset });
        return;
    }

    std.debug.print("\n{s}--- nvhud Benchmark ---{s}\n\n", .{ Color.nvidia, Color.reset });
    std.debug.print("Recording for {d} seconds...\n\n", .{duration_secs});

    // Use static buffers - max 10 samples per second for up to 120 seconds
    const MAX_SAMPLES = 1200;
    var temps: [MAX_SAMPLES]u32 = undefined;
    var powers: [MAX_SAMPLES]u32 = undefined;
    var utils: [MAX_SAMPLES]u32 = undefined;
    var sample_count: usize = 0;

    // Track samples using simple counter (10 samples per sec * duration)
    const target_samples = @min(duration_secs * 10, MAX_SAMPLES);

    while (sample_count < target_samples) {
        const m = collector.collect();
        temps[sample_count] = m.temperature;
        powers[sample_count] = m.power_draw;
        utils[sample_count] = m.gpu_util;
        sample_count += 1;

        std.debug.print("\r  Samples: {d}  Temp: {d}C  Power: {d}W  GPU: {d}%    ", .{
            sample_count,
            m.temperature,
            m.power_draw,
            m.gpu_util,
        });

        sleep(100 * std.time.ns_per_ms);
    }

    std.debug.print("\n\n{s}Results:{s}\n", .{ Color.bright_cyan, Color.reset });

    // Calculate stats
    if (sample_count > 0) {
        var temp_sum: u64 = 0;
        var temp_max: u32 = 0;
        var power_sum: u64 = 0;
        var power_max: u32 = 0;
        var util_sum: u64 = 0;

        for (0..sample_count) |i| {
            temp_sum += temps[i];
            if (temps[i] > temp_max) temp_max = temps[i];
            power_sum += powers[i];
            if (powers[i] > power_max) power_max = powers[i];
            util_sum += utils[i];
        }

        const temp_avg = temp_sum / sample_count;
        const power_avg = power_sum / sample_count;
        const util_avg = util_sum / sample_count;

        std.debug.print("  Temperature:  avg {d}C, max {d}C\n", .{ temp_avg, temp_max });
        std.debug.print("  Power:        avg {d}W, max {d}W\n", .{ power_avg, power_max });
        std.debug.print("  GPU Usage:    avg {d}%\n", .{util_avg});
    }

    std.debug.print("\n  Total samples: {d}\n\n", .{sample_count});
}

fn configCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        // Show current config
        std.debug.print("\n{s}--- nvhud Configuration ---{s}\n\n", .{ Color.nvidia, Color.reset });

        const cfg = nvhud.loadConfig(allocator);

        std.debug.print("{s}Display{s}\n", .{ Color.bright_cyan, Color.reset });
        std.debug.print("  show_fps:            {s}\n", .{if (cfg.show_fps) "true" else "false"});
        std.debug.print("  show_frametime:      {s}\n", .{if (cfg.show_frametime) "true" else "false"});
        std.debug.print("  show_frametime_graph:{s}\n", .{if (cfg.show_frametime_graph) "true" else "false"});
        std.debug.print("  show_gpu_temp:       {s}\n", .{if (cfg.show_gpu_temp) "true" else "false"});
        std.debug.print("  show_gpu_util:       {s}\n", .{if (cfg.show_gpu_util) "true" else "false"});
        std.debug.print("  show_vram:           {s}\n", .{if (cfg.show_vram) "true" else "false"});

        std.debug.print("\n{s}Overlay{s}\n", .{ Color.bright_cyan, Color.reset });
        std.debug.print("  position:            {s}\n", .{cfg.position.toString()});
        std.debug.print("  update_interval_ms:  {d}\n", .{cfg.update_interval_ms});

        std.debug.print("\n{s}Presets{s}\n", .{ Color.bright_cyan, Color.reset });
        std.debug.print("  {s}minimal{s}   - FPS only\n", .{ Color.green, Color.reset });
        std.debug.print("  {s}gaming{s}    - FPS, temp, GPU, VRAM + graph\n", .{ Color.green, Color.reset });
        std.debug.print("  {s}full{s}      - All metrics\n", .{ Color.green, Color.reset });
        std.debug.print("  {s}benchmark{s} - For benchmarking runs\n", .{ Color.green, Color.reset });

        std.debug.print("\n{s}Config file:{s} ~/.config/nvhud/config.toml\n\n", .{ Color.dim, Color.reset });
    } else {
        const preset = args[0];

        if (mem.eql(u8, preset, "generate")) {
            std.debug.print("{s}", .{nvhud.Config.generateDefaultConfig()});
            return;
        }

        const cfg = if (mem.eql(u8, preset, "minimal"))
            nvhud.Config.minimal()
        else if (mem.eql(u8, preset, "gaming"))
            nvhud.Config.gaming()
        else if (mem.eql(u8, preset, "full"))
            nvhud.Config.full()
        else if (mem.eql(u8, preset, "benchmark"))
            nvhud.Config.benchmark()
        else {
            std.debug.print("{s}Unknown preset: {s}{s}\n", .{ Color.red, preset, Color.reset });
            std.debug.print("Available: minimal, gaming, full, benchmark\n", .{});
            return;
        };

        cfg.save(allocator) catch |err| {
            std.debug.print("{s}Failed to save config: {}{s}\n", .{ Color.red, err, Color.reset });
            return;
        };

        std.debug.print("{s}+{s} Applied preset: {s}{s}{s}\n", .{ Color.green, Color.reset, Color.bright_white, preset, Color.reset });
        std.debug.print("  Config saved to ~/.config/nvhud/config.toml\n", .{});
    }
}

fn jsonCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (args.len == 0) {
        std.debug.print("{{\"error\":\"No subcommand specified\"}}\n", .{});
        return;
    }

    const subcommand = args[0];

    var collector = nvhud.createCollector();
    defer collector.deinit();

    if (mem.eql(u8, subcommand, "status")) {
        const info = collector.getInfo();
        std.debug.print("{{\"version\":\"{s}\",\"nvidia\":{s},\"gpu\":\"{s}\",\"driver\":\"{s}\",\"architecture\":\"{s}\"}}\n", .{
            nvhud.version_string,
            if (collector.isAvailable()) "true" else "false",
            info.getName(),
            info.getDriver(),
            info.getArchitecture(),
        });
    } else if (mem.eql(u8, subcommand, "metrics")) {
        const m = collector.collect();
        std.debug.print("{{\"temperature\":{d},\"gpu_util\":{d},\"mem_util\":{d},\"gpu_clock\":{d},\"mem_clock\":{d},\"power_draw\":{d},\"power_limit\":{d},\"fan_speed\":{d},\"vram_used\":{d},\"vram_total\":{d},\"pcie_gen\":{d},\"pcie_width\":{d},\"encoder_util\":{d},\"decoder_util\":{d},\"pstate\":{d}}}\n", .{
            m.temperature,
            m.gpu_util,
            m.mem_util,
            m.gpu_clock,
            m.mem_clock,
            m.power_draw,
            m.power_limit,
            m.fan_speed,
            m.vram_used,
            m.vram_total,
            m.pcie_gen,
            m.pcie_width,
            m.encoder_util,
            m.decoder_util,
            m.pstate,
        });
    } else if (mem.eql(u8, subcommand, "info")) {
        const info = collector.getInfo();
        std.debug.print("{{\"name\":\"{s}\",\"architecture\":\"{s}\",\"driver\":\"{s}\",\"vram_mb\":{d}}}\n", .{
            info.getName(),
            info.getArchitecture(),
            info.getDriver(),
            info.vram_total_mb,
        });
    } else {
        std.debug.print("{{\"error\":\"Unknown subcommand: {s}\"}}\n", .{subcommand});
    }
}

/// Create a colored progress bar
fn makeColorBar(value: u32, max_value: u32, width: u32, color: []const u8) [80]u8 {
    var bar: [80]u8 = undefined;
    const actual_width = @min(width, 40);

    const filled = (value * actual_width) / max_value;
    var i: usize = 0;

    // Color start
    for (color) |c| {
        if (i < bar.len) {
            bar[i] = c;
            i += 1;
        }
    }

    // Filled portion
    var f: u32 = 0;
    while (f < filled and i < bar.len) : (f += 1) {
        bar[i] = '=';
        i += 1;
    }

    // Color reset
    for (Color.reset) |c| {
        if (i < bar.len) {
            bar[i] = c;
            i += 1;
        }
    }

    // Empty portion
    while (f < actual_width and i < bar.len) : (f += 1) {
        bar[i] = '-';
        i += 1;
    }

    // Null terminate
    while (i < bar.len) {
        bar[i] = 0;
        i += 1;
    }

    return bar;
}

test "main compiles" {
    _ = nvhud.version;
}
