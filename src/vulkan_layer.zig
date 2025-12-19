//! Vulkan Implicit Layer Implementation
//!
//! This implements the actual Vulkan layer hooks for in-game overlay.
//! Works similar to MangoHud's layer - intercepts vkQueuePresentKHR to render overlay.

const std = @import("std");
const nvhud = @import("nvhud");
const config = nvhud.config;
const metrics = nvhud.metrics;
const overlay_mod = nvhud.overlay;

// Vulkan type definitions
const VkInstance = *anyopaque;
const VkDevice = *anyopaque;
const VkPhysicalDevice = *anyopaque;
const VkQueue = *anyopaque;
const VkSwapchainKHR = *anyopaque;
const VkCommandBuffer = *anyopaque;
const VkFence = *anyopaque;
const VkSemaphore = *anyopaque;
const VkResult = i32;
const VkBool32 = u32;

// Vulkan constants
const VK_SUCCESS: VkResult = 0;
const VK_TRUE: VkBool32 = 1;
const VK_FALSE: VkBool32 = 0;

// Layer name
pub const layer_name = "VK_LAYER_NVHUD_overlay";

// Function pointer types for Vulkan functions
const PFN_vkVoidFunction = *const fn () callconv(.c) void;
const PFN_vkGetInstanceProcAddr = *const fn (VkInstance, [*:0]const u8) callconv(.c) ?PFN_vkVoidFunction;
const PFN_vkGetDeviceProcAddr = *const fn (VkDevice, [*:0]const u8) callconv(.c) ?PFN_vkVoidFunction;

// Present info struct
const VkPresentInfoKHR = extern struct {
    sType: u32 = 1000001001, // VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    swapchainCount: u32 = 0,
    pSwapchains: ?[*]const VkSwapchainKHR = null,
    pImageIndices: ?[*]const u32 = null,
    pResults: ?[*]VkResult = null,
};

// Hooked function types
const PFN_vkQueuePresentKHR = *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) VkResult;
const PFN_vkCreateInstance = *const fn (*const anyopaque, ?*const anyopaque, *VkInstance) callconv(.c) VkResult;
const PFN_vkDestroyInstance = *const fn (VkInstance, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateDevice = *const fn (VkPhysicalDevice, *const anyopaque, ?*const anyopaque, *VkDevice) callconv(.c) VkResult;
const PFN_vkDestroyDevice = *const fn (VkDevice, ?*const anyopaque) callconv(.c) void;

// Global state
var g_allocator: std.mem.Allocator = undefined;
var g_overlay: ?overlay_mod.Overlay = null;
var g_collector: ?metrics.Collector = null;
var g_initialized = false;
var g_enabled = false;

// Original function pointers (from next layer)
var g_vkGetInstanceProcAddr: ?PFN_vkGetInstanceProcAddr = null;
var g_vkGetDeviceProcAddr: ?PFN_vkGetDeviceProcAddr = null;
var g_vkQueuePresentKHR: ?PFN_vkQueuePresentKHR = null;
var g_vkCreateInstance: ?PFN_vkCreateInstance = null;
var g_vkDestroyInstance: ?PFN_vkDestroyInstance = null;
var g_vkCreateDevice: ?PFN_vkCreateDevice = null;
var g_vkDestroyDevice: ?PFN_vkDestroyDevice = null;

// Frame counter for metrics updates
var g_frame_count: u64 = 0;
var g_last_update: i64 = 0;

/// Initialize the layer
fn initLayer() void {
    if (g_initialized) return;

    // Check if layer is enabled
    if (std.posix.getenv("NVHUD")) |val| {
        g_enabled = !std.mem.eql(u8, val, "0");
    } else {
        g_enabled = false;
        g_initialized = true;
        return;
    }

    // Use page allocator for layer (needs to be stable)
    g_allocator = std.heap.page_allocator;

    // Load config
    var cfg = config.Config.default();
    if (std.posix.getenv("NVHUD_CONFIG")) |preset| {
        if (std.mem.eql(u8, preset, "minimal")) {
            cfg = config.Config.minimal();
        } else if (std.mem.eql(u8, preset, "gaming")) {
            cfg = config.Config.gaming();
        } else if (std.mem.eql(u8, preset, "benchmark")) {
            cfg = config.Config.benchmark();
        }
    }

    // Parse position override
    if (std.posix.getenv("NVHUD_POSITION")) |pos| {
        if (std.mem.eql(u8, pos, "top-left")) {
            cfg.position = .top_left;
        } else if (std.mem.eql(u8, pos, "top-right")) {
            cfg.position = .top_right;
        } else if (std.mem.eql(u8, pos, "bottom-left")) {
            cfg.position = .bottom_left;
        } else if (std.mem.eql(u8, pos, "bottom-right")) {
            cfg.position = .bottom_right;
        }
    }

    // Initialize overlay
    g_overlay = overlay_mod.Overlay.init(g_allocator, cfg);
    g_collector = metrics.Collector.init();

    g_initialized = true;
}

/// Cleanup the layer
fn deinitLayer() void {
    if (!g_initialized) return;

    if (g_overlay) |*o| o.deinit();
    if (g_collector) |*c| c.deinit();

    g_overlay = null;
    g_collector = null;
    g_initialized = false;
}

/// Hook: vkQueuePresentKHR - Main overlay render point
fn hook_vkQueuePresentKHR(queue: VkQueue, present_info: *const VkPresentInfoKHR) callconv(.c) VkResult {
    // Record frame time
    if (g_overlay) |*o| {
        o.recordFrame();
    }

    g_frame_count += 1;

    // Update metrics periodically (not every frame)
    const instant = std.time.Instant.now() catch {
        if (g_vkQueuePresentKHR) |present| return present(queue, present_info);
        return VK_SUCCESS;
    };
    const now: i64 = @as(i64, @intCast(instant.timestamp.sec)) * 1000 + @divFloor(@as(i64, @intCast(instant.timestamp.nsec)), 1_000_000);
    if (now - g_last_update >= 100) { // 100ms interval
        if (g_overlay) |*o| {
            if (g_collector) |*c| {
                o.last_metrics = c.collect();
            }
            o.buildHud();
            // Note: Actual rendering would need Vulkan command buffers
            // This is a simplified version - full implementation would
            // inject commands into the present queue
        }
        g_last_update = now;
    }

    // Call original present
    if (g_vkQueuePresentKHR) |present| {
        return present(queue, present_info);
    }
    return VK_SUCCESS;
}

/// Hook: vkCreateInstance
fn hook_vkCreateInstance(create_info: *const anyopaque, allocator: ?*const anyopaque, instance: *VkInstance) callconv(.c) VkResult {
    initLayer();

    if (g_vkCreateInstance) |create| {
        return create(create_info, allocator, instance);
    }
    return -1; // VK_ERROR_INITIALIZATION_FAILED
}

/// Hook: vkDestroyInstance
fn hook_vkDestroyInstance(instance: VkInstance, allocator: ?*const anyopaque) callconv(.c) void {
    if (g_vkDestroyInstance) |destroy| {
        destroy(instance, allocator);
    }
    deinitLayer();
}

/// Hook: vkCreateDevice
fn hook_vkCreateDevice(physicalDevice: VkPhysicalDevice, create_info: *const anyopaque, allocator: ?*const anyopaque, device: *VkDevice) callconv(.c) VkResult {
    if (g_vkCreateDevice) |create| {
        return create(physicalDevice, create_info, allocator, device);
    }
    return -1;
}

/// Hook: vkDestroyDevice
fn hook_vkDestroyDevice(device: VkDevice, allocator: ?*const anyopaque) callconv(.c) void {
    if (g_vkDestroyDevice) |destroy| {
        destroy(device, allocator);
    }
}

/// Layer entry point: vkGetInstanceProcAddr
export fn nvhud_vkGetInstanceProcAddr(instance: VkInstance, name: [*:0]const u8) callconv(.c) ?PFN_vkVoidFunction {
    const name_slice = std.mem.span(name);

    // Intercept specific functions
    if (std.mem.eql(u8, name_slice, "vkCreateInstance")) {
        return @ptrCast(&hook_vkCreateInstance);
    }
    if (std.mem.eql(u8, name_slice, "vkDestroyInstance")) {
        return @ptrCast(&hook_vkDestroyInstance);
    }
    if (std.mem.eql(u8, name_slice, "vkGetInstanceProcAddr")) {
        return @ptrCast(&nvhud_vkGetInstanceProcAddr);
    }

    // Pass through to next layer
    if (g_vkGetInstanceProcAddr) |getProc| {
        return getProc(instance, name);
    }
    return null;
}

/// Layer entry point: vkGetDeviceProcAddr
export fn nvhud_vkGetDeviceProcAddr(device: VkDevice, name: [*:0]const u8) callconv(.c) ?PFN_vkVoidFunction {
    const name_slice = std.mem.span(name);

    // Intercept device functions
    if (std.mem.eql(u8, name_slice, "vkQueuePresentKHR")) {
        return @ptrCast(&hook_vkQueuePresentKHR);
    }
    if (std.mem.eql(u8, name_slice, "vkCreateDevice")) {
        return @ptrCast(&hook_vkCreateDevice);
    }
    if (std.mem.eql(u8, name_slice, "vkDestroyDevice")) {
        return @ptrCast(&hook_vkDestroyDevice);
    }
    if (std.mem.eql(u8, name_slice, "vkGetDeviceProcAddr")) {
        return @ptrCast(&nvhud_vkGetDeviceProcAddr);
    }

    // Pass through to next layer
    if (g_vkGetDeviceProcAddr) |getProc| {
        return getProc(device, name);
    }
    return null;
}

/// Layer negotiation interface (Vulkan 1.1+)
const VkNegotiateLayerInterface = extern struct {
    sType: u32, // LAYER_NEGOTIATE_INTERFACE_STRUCT
    pLayerName: [*:0]const u8,
    specVersion: u32,
    implementationVersion: u32,
    pfnGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnGetDeviceProcAddr: ?PFN_vkGetDeviceProcAddr,
    pfnGetPhysicalDeviceProcAddr: ?*const anyopaque,
};

/// VK_LAYER_EXPORT vkNegotiateLoaderLayerInterfaceVersion
export fn vkNegotiateLoaderLayerInterfaceVersion(pVersionStruct: *anyopaque) callconv(.c) VkResult {
    // This is the modern loader interface for Vulkan 1.1+
    _ = pVersionStruct;
    initLayer();
    return VK_SUCCESS;
}

/// Generate layer manifest JSON
pub fn generateManifest() []const u8 {
    return
        \\{
        \\  "file_format_version": "1.2.0",
        \\  "layer": {
        \\    "name": "VK_LAYER_NVHUD_overlay",
        \\    "type": "GLOBAL",
        \\    "library_path": "./libnvhud_layer.so",
        \\    "api_version": "1.3.283",
        \\    "implementation_version": "1",
        \\    "description": "nvhud - NVIDIA GPU Performance Overlay",
        \\    "functions": {
        \\      "vkGetInstanceProcAddr": "nvhud_vkGetInstanceProcAddr",
        \\      "vkGetDeviceProcAddr": "nvhud_vkGetDeviceProcAddr",
        \\      "vkNegotiateLoaderLayerInterfaceVersion": "vkNegotiateLoaderLayerInterfaceVersion"
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

/// Print manifest to stdout (for installation)
pub fn printManifest() void {
    std.io.getStdOut().writeAll(generateManifest()) catch {};
}

test "layer name" {
    try std.testing.expectEqualStrings("VK_LAYER_NVHUD_overlay", layer_name);
}
