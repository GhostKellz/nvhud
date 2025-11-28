//! nvhud CLI - NVIDIA GPU Metrics & HUD for Linux
//!
//! MangoHud alternative for NVIDIA fans - real-time GPU monitoring.

const std = @import("std");
const nvhud = @import("nvhud");
const posix = std.posix;
const fs = std.fs;
const mem = std.mem;

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

    if (std.mem.eql(u8, command, "status")) {
        try statusCommand(allocator);
    } else if (std.mem.eql(u8, command, "info")) {
        try infoCommand(allocator);
    } else if (std.mem.eql(u8, command, "metrics")) {
        try metricsCommand(allocator);
    } else if (std.mem.eql(u8, command, "watch")) {
        try watchCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "config")) {
        try configCommand(args[2..]);
    } else if (std.mem.eql(u8, command, "json")) {
        try jsonCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        printVersion();
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\nvhud - NVIDIA GPU Metrics & HUD v{d}.{d}.{d}
        \\
        \\A MangoHud alternative for NVIDIA enthusiasts.
        \\
        \\USAGE:
        \\    nvhud <command> [options]
        \\
        \\COMMANDS:
        \\    status              Show GPU status summary
        \\    info                Show detailed GPU information
        \\    metrics             Show current GPU metrics
        \\    watch [interval]    Monitor GPU metrics in real-time
        \\    config [preset]     Show/set HUD configuration
        \\    json <subcommand>   Output as JSON (status, metrics, info)
        \\    help                Show this help message
        \\    version             Show version information
        \\
        \\EXAMPLES:
        \\    nvhud status
        \\    nvhud metrics
        \\    nvhud watch 1
        \\    nvhud json metrics
        \\
        \\OVERLAY (coming soon):
        \\    nvhud will provide a Vulkan overlay layer for in-game monitoring.
        \\    Use NVHUD=1 game to enable the overlay.
        \\
    , .{
        nvhud.version.major,
        nvhud.version.minor,
        nvhud.version.patch,
    });
}

fn printVersion() void {
    std.debug.print("nvhud v{d}.{d}.{d}\n", .{
        nvhud.version.major,
        nvhud.version.minor,
        nvhud.version.patch,
    });
}

fn statusCommand(allocator: mem.Allocator) !void {
    std.debug.print("nvhud - NVIDIA GPU Status\n", .{});
    std.debug.print("=========================\n\n", .{});

    var collector = nvhud.MetricsCollector.init(allocator);
    defer collector.deinit();

    if (!collector.nvidia_detected) {
        std.debug.print("NVIDIA GPU: Not detected\n", .{});
        std.debug.print("\nMake sure NVIDIA drivers are installed and loaded.\n", .{});
        return;
    }

    std.debug.print("NVIDIA GPU: Detected\n", .{});
    if (collector.gpu_name) |name| {
        std.debug.print("Model:      {s}\n", .{name});
    }
    if (collector.driver_version) |ver| {
        std.debug.print("Driver:     {s}\n", .{ver});
    }

    const metrics = collector.collect();
    std.debug.print("\nCurrent Status:\n", .{});
    if (metrics.temperature > 0) {
        std.debug.print("  Temperature: {d}°C\n", .{metrics.temperature});
    }
    if (metrics.gpu_utilization > 0) {
        std.debug.print("  GPU Usage:   {d}%\n", .{metrics.gpu_utilization});
    }
    if (metrics.power_draw > 0) {
        std.debug.print("  Power Draw:  {d}W\n", .{metrics.power_draw});
    }
    if (metrics.fan_speed > 0) {
        std.debug.print("  Fan Speed:   {d}%\n", .{metrics.fan_speed});
    }
    if (metrics.vram_total > 0) {
        std.debug.print("  VRAM:        {d}/{d} MB ({d:.1}%)\n", .{
            metrics.vram_used,
            metrics.vram_total,
            metrics.vramUsagePercent(),
        });
    }
}

fn infoCommand(allocator: mem.Allocator) !void {
    std.debug.print("nvhud GPU Information\n", .{});
    std.debug.print("=====================\n\n", .{});

    var collector = nvhud.MetricsCollector.init(allocator);
    defer collector.deinit();

    if (!collector.nvidia_detected) {
        std.debug.print("NVIDIA GPU not detected.\n", .{});
        return;
    }

    var info = collector.getInfo();
    defer info.deinit();

    std.debug.print("GPU:\n", .{});
    std.debug.print("  Name:         {s}\n", .{info.name});
    std.debug.print("  Architecture: {s}\n", .{info.architecture});
    std.debug.print("  Driver:       {s}\n", .{info.driver_version});
    std.debug.print("  PCIe:         {s}\n", .{info.pcie_info});

    std.debug.print("\nnvhud Version:\n", .{});
    std.debug.print("  {d}.{d}.{d}\n", .{
        nvhud.version.major,
        nvhud.version.minor,
        nvhud.version.patch,
    });

    std.debug.print("\nSupported Features:\n", .{});
    std.debug.print("  - GPU temperature monitoring\n", .{});
    std.debug.print("  - Power draw monitoring\n", .{});
    std.debug.print("  - Fan speed monitoring\n", .{});
    std.debug.print("  - VRAM usage tracking\n", .{});
    std.debug.print("  - JSON output for scripting\n", .{});
    std.debug.print("\nComing Soon:\n", .{});
    std.debug.print("  - Vulkan overlay layer\n", .{});
    std.debug.print("  - FPS/Frame time graphs\n", .{});
    std.debug.print("  - Integration with nvcontrol\n", .{});
}

fn metricsCommand(allocator: mem.Allocator) !void {
    var collector = nvhud.MetricsCollector.init(allocator);
    defer collector.deinit();

    if (!collector.nvidia_detected) {
        std.debug.print("NVIDIA GPU not detected.\n", .{});
        return;
    }

    const m = collector.collect();

    std.debug.print("GPU Metrics\n", .{});
    std.debug.print("===========\n\n", .{});

    // Temperature
    if (m.temperature > 0) {
        const temp_bar = makeBar(m.temperature, 100, 20);
        std.debug.print("Temperature: {d:>3}°C [{s}]\n", .{ m.temperature, temp_bar });
    } else {
        std.debug.print("Temperature: --\n", .{});
    }

    // GPU Utilization
    if (m.gpu_utilization > 0) {
        const util_bar = makeBar(m.gpu_utilization, 100, 20);
        std.debug.print("GPU Usage:   {d:>3}%  [{s}]\n", .{ m.gpu_utilization, util_bar });
    } else {
        std.debug.print("GPU Usage:   --\n", .{});
    }

    // Power
    if (m.power_draw > 0 and m.power_limit > 0) {
        const power_pct: u32 = @intFromFloat(m.powerUsagePercent());
        const power_bar = makeBar(power_pct, 100, 20);
        std.debug.print("Power:       {d:>3}W  [{s}] ({d}W limit)\n", .{ m.power_draw, power_bar, m.power_limit });
    } else if (m.power_draw > 0) {
        std.debug.print("Power:       {d}W\n", .{m.power_draw});
    } else {
        std.debug.print("Power:       --\n", .{});
    }

    // Fan
    if (m.fan_speed > 0) {
        const fan_bar = makeBar(m.fan_speed, 100, 20);
        std.debug.print("Fan Speed:   {d:>3}%  [{s}]\n", .{ m.fan_speed, fan_bar });
    } else {
        std.debug.print("Fan Speed:   --\n", .{});
    }

    // VRAM
    if (m.vram_total > 0) {
        const vram_pct: u32 = @intFromFloat(m.vramUsagePercent());
        const vram_bar = makeBar(vram_pct, 100, 20);
        std.debug.print("VRAM:        {d:>5}/{d} MB [{s}]\n", .{ m.vram_used, m.vram_total, vram_bar });
    } else {
        std.debug.print("VRAM:        --\n", .{});
    }

    // Clocks
    if (m.gpu_clock > 0 or m.memory_clock > 0) {
        std.debug.print("\nClocks:\n", .{});
        if (m.gpu_clock > 0) {
            std.debug.print("  GPU:    {d} MHz\n", .{m.gpu_clock});
        }
        if (m.memory_clock > 0) {
            std.debug.print("  Memory: {d} MHz\n", .{m.memory_clock});
        }
    }

    // PCIe
    if (m.pcie_gen > 0) {
        std.debug.print("\nPCIe:        Gen{d} x{d}\n", .{ m.pcie_gen, m.pcie_width });
    }
}

fn watchCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    const interval_ms: u64 = if (args.len > 0)
        (std.fmt.parseInt(u64, args[0], 10) catch 1) * 1000
    else
        1000;

    var collector = nvhud.MetricsCollector.init(allocator);
    defer collector.deinit();

    if (!collector.nvidia_detected) {
        std.debug.print("NVIDIA GPU not detected.\n", .{});
        return;
    }

    // Hide cursor
    std.debug.print("\x1b[?25l", .{});

    std.debug.print("nvhud - Real-time GPU Monitor\n", .{});
    std.debug.print("Press Ctrl+C to stop.\n\n", .{});

    // Print header
    std.debug.print("  Temp   GPU    Power    Fan     VRAM          Clocks\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────────\n", .{});

    while (true) {
        const m = collector.collect();

        // Move cursor to beginning of line and clear
        std.debug.print("\x1b[2K\r", .{});

        // Fixed-width format for stable display
        std.debug.print("  {d:>3}°C  {d:>3}%   {d:>4}W   {d:>3}%   {d:>5}/{d:<5} MB   {d:>4}/{d:<5} MHz", .{
            m.temperature,
            m.gpu_utilization,
            m.power_draw,
            m.fan_speed,
            m.vram_used,
            m.vram_total,
            m.gpu_clock,
            m.memory_clock,
        });

        // Sleep
        posix.nanosleep(0, interval_ms * 1_000_000);
    }
}

fn configCommand(args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("HUD Configuration\n", .{});
        std.debug.print("=================\n\n", .{});

        const config = nvhud.HudConfig.default();
        std.debug.print("Current Settings:\n", .{});
        std.debug.print("  show_fps:            {s}\n", .{if (config.show_fps) "true" else "false"});
        std.debug.print("  show_temperature:    {s}\n", .{if (config.show_temperature) "true" else "false"});
        std.debug.print("  show_gpu_util:       {s}\n", .{if (config.show_gpu_util) "true" else "false"});
        std.debug.print("  show_vram:           {s}\n", .{if (config.show_vram) "true" else "false"});
        std.debug.print("  show_power:          {s}\n", .{if (config.show_power) "true" else "false"});
        std.debug.print("  show_frametime_graph:{s}\n", .{if (config.show_frametime_graph) "true" else "false"});
        std.debug.print("  position:            top_left\n", .{});
        std.debug.print("  update_interval_ms:  {d}\n", .{config.update_interval_ms});

        std.debug.print("\nPresets:\n", .{});
        std.debug.print("  minimal   - FPS only\n", .{});
        std.debug.print("  gaming    - FPS, temp, GPU usage\n", .{});
        std.debug.print("  full      - All metrics\n", .{});
        std.debug.print("  benchmark - FPS, frame time, 1% lows\n", .{});
    } else {
        const preset = args[0];
        std.debug.print("Applying preset: {s}\n", .{preset});
        std.debug.print("\nNote: Overlay presets will be configurable in future versions.\n", .{});
        std.debug.print("Config file: ~/.config/nvhud/config.toml\n", .{});
    }
}

fn jsonCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("{{\"error\":\"No subcommand specified\"}}\n", .{});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "status")) {
        var collector = nvhud.MetricsCollector.init(allocator);
        defer collector.deinit();

        std.debug.print(
            \\{{"version":"{d}.{d}.{d}","nvidia":{s},"gpu":"{s}","driver":"{s}"}}
        ++ "\n", .{
            nvhud.version.major,
            nvhud.version.minor,
            nvhud.version.patch,
            if (collector.nvidia_detected) "true" else "false",
            collector.gpu_name orelse "unknown",
            collector.driver_version orelse "unknown",
        });
    } else if (std.mem.eql(u8, subcommand, "metrics")) {
        var collector = nvhud.MetricsCollector.init(allocator);
        defer collector.deinit();

        const m = collector.collect();
        std.debug.print(
            \\{{"temperature":{d},"gpu_util":{d},"power":{d},"fan":{d},"vram_used":{d},"vram_total":{d},"pcie_gen":{d},"pcie_width":{d}}}
        ++ "\n", .{
            m.temperature,
            m.gpu_utilization,
            m.power_draw,
            m.fan_speed,
            m.vram_used,
            m.vram_total,
            m.pcie_gen,
            m.pcie_width,
        });
    } else if (std.mem.eql(u8, subcommand, "info")) {
        var collector = nvhud.MetricsCollector.init(allocator);
        defer collector.deinit();

        var info = collector.getInfo();
        defer info.deinit();

        std.debug.print(
            \\{{"name":"{s}","architecture":"{s}","driver":"{s}","pcie":"{s}"}}
        ++ "\n", .{
            info.name,
            info.architecture,
            info.driver_version,
            info.pcie_info,
        });
    } else {
        std.debug.print("{{\"error\":\"Unknown subcommand: {s}\"}}\n", .{subcommand});
    }
}

/// Create a simple progress bar
fn makeBar(value: u32, max_value: u32, width: u32) [20]u8 {
    var bar: [20]u8 = [_]u8{'.'} ** 20;
    const filled = (value * width) / max_value;
    for (0..@min(filled, width)) |i| {
        bar[i] = '#';
    }
    return bar;
}

test "main compiles" {
    _ = nvhud.version;
}
