//! nvhud Vulkan Layer
//!
//! Implements a Vulkan layer that renders GPU metrics as an overlay.
//! Intercepts vkQueuePresentKHR to draw the HUD before presenting.

const std = @import("std");
const builtin = @import("builtin");

// Vulkan types (minimal definitions needed for layer)
const VkResult = enum(i32) {
    VK_SUCCESS = 0,
    VK_NOT_READY = 1,
    VK_TIMEOUT = 2,
    VK_EVENT_SET = 3,
    VK_EVENT_RESET = 4,
    VK_INCOMPLETE = 5,
    VK_ERROR_OUT_OF_HOST_MEMORY = -1,
    VK_ERROR_OUT_OF_DEVICE_MEMORY = -2,
    VK_ERROR_INITIALIZATION_FAILED = -3,
    VK_ERROR_DEVICE_LOST = -4,
    VK_ERROR_MEMORY_MAP_FAILED = -5,
    VK_ERROR_LAYER_NOT_PRESENT = -6,
    VK_ERROR_EXTENSION_NOT_PRESENT = -7,
    _,
};

const VkStructureType = enum(i32) {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1,
    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2,
    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3,
    VK_STRUCTURE_TYPE_SUBMIT_INFO = 4,
    VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO = 47,
    VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO = 48,
    _,
};

const VkLayerFunction = enum(i32) {
    VK_LAYER_LINK_INFO = 0,
    VK_LOADER_DATA_CALLBACK = 1,
    VK_LOADER_LAYER_CREATE_DEVICE_CALLBACK = 2,
    VK_LOADER_FEATURES = 3,
};

const VkInstance = ?*anyopaque;
const VkPhysicalDevice = ?*anyopaque;
const VkDevice = ?*anyopaque;
const VkQueue = ?*anyopaque;
const VkSemaphore = ?*anyopaque;
const VkSwapchainKHR = u64;
const VkFence = u64;

// Function pointer types
const PFN_vkVoidFunction = ?*const fn () callconv(.c) void;
const PFN_vkGetInstanceProcAddr = *const fn (VkInstance, [*:0]const u8) callconv(.c) PFN_vkVoidFunction;
const PFN_vkGetDeviceProcAddr = *const fn (VkDevice, [*:0]const u8) callconv(.c) PFN_vkVoidFunction;
const PFN_vkCreateInstance = *const fn (*const VkInstanceCreateInfo, ?*const anyopaque, *VkInstance) callconv(.c) VkResult;
const PFN_vkDestroyInstance = *const fn (VkInstance, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateDevice = *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const anyopaque, *VkDevice) callconv(.c) VkResult;
const PFN_vkDestroyDevice = *const fn (VkDevice, ?*const anyopaque) callconv(.c) void;
const PFN_vkQueuePresentKHR = *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) VkResult;

// Structures
const VkApplicationInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    pApplicationName: ?[*:0]const u8,
    applicationVersion: u32,
    pEngineName: ?[*:0]const u8,
    engineVersion: u32,
    apiVersion: u32,
};

const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    pApplicationInfo: ?*const VkApplicationInfo,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ?[*]const [*:0]const u8,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
};

const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    queueCreateInfoCount: u32,
    pQueueCreateInfos: ?*const anyopaque,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ?[*]const [*:0]const u8,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
    pEnabledFeatures: ?*const anyopaque,
};

const VkLayerInstanceLink = extern struct {
    pNext: ?*VkLayerInstanceLink,
    pfnNextGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnNextGetPhysicalDeviceProcAddr: ?*const anyopaque,
};

const VkLayerDeviceLink = extern struct {
    pNext: ?*VkLayerDeviceLink,
    pfnNextGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnNextGetDeviceProcAddr: PFN_vkGetDeviceProcAddr,
};

const VkLayerInstanceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    function: VkLayerFunction,
    u: extern union {
        pLayerInfo: *VkLayerInstanceLink,
        pfnSetInstanceLoaderData: ?*const anyopaque,
        layerDevice: extern struct {
            pfnLayerCreateDevice: ?*const anyopaque,
            pfnLayerDestroyDevice: ?*const anyopaque,
        },
        loaderFeatures: u32,
    },
};

const VkLayerDeviceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    function: VkLayerFunction,
    u: extern union {
        pLayerInfo: *VkLayerDeviceLink,
        pfnSetDeviceLoaderData: ?*const anyopaque,
    },
};

const VkPresentInfoKHR = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    waitSemaphoreCount: u32,
    pWaitSemaphores: ?[*]const VkSemaphore,
    swapchainCount: u32,
    pSwapchains: ?[*]const VkSwapchainKHR,
    pImageIndices: ?[*]const u32,
    pResults: ?[*]VkResult,
};

// Instance data storage
const InstanceData = struct {
    instance: VkInstance,
    get_instance_proc_addr: PFN_vkGetInstanceProcAddr,
    destroy_instance: ?PFN_vkDestroyInstance,
};

// Device data storage
const DeviceData = struct {
    device: VkDevice,
    physical_device: VkPhysicalDevice,
    instance_data: *InstanceData,
    get_device_proc_addr: PFN_vkGetDeviceProcAddr,
    destroy_device: ?PFN_vkDestroyDevice,
    queue_present: ?PFN_vkQueuePresentKHR,
};

// Global state
var instance_map: std.AutoHashMap(usize, *InstanceData) = undefined;
var device_map: std.AutoHashMap(usize, *DeviceData) = undefined;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var initialized = false;

// NVML imports from our nvml module
extern fn dlopen(filename: ?[*:0]const u8, flags: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;

const RTLD_NOW: c_int = 0x00002;
const RTLD_GLOBAL: c_int = 0x00100;

// NVML state
var nvml_handle: ?*anyopaque = null;
var nvml_initialized = false;
var nvml_device: ?*anyopaque = null;

const nvmlInit_fn = *const fn () callconv(.c) c_uint;
const nvmlShutdown_fn = *const fn () callconv(.c) c_uint;
const nvmlDeviceGetHandleByIndex_fn = *const fn (c_uint, **anyopaque) callconv(.c) c_uint;
const nvmlDeviceGetTemperature_fn = *const fn (*anyopaque, c_uint, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetUtilizationRates_fn = *const fn (*anyopaque, *NvmlUtilization) callconv(.c) c_uint;
const nvmlDeviceGetMemoryInfo_fn = *const fn (*anyopaque, *NvmlMemory) callconv(.c) c_uint;
const nvmlDeviceGetPowerUsage_fn = *const fn (*anyopaque, *c_uint) callconv(.c) c_uint;

const NvmlUtilization = extern struct { gpu: c_uint, memory: c_uint };
const NvmlMemory = extern struct { total: u64, free: u64, used: u64 };

var fn_nvml_init: ?nvmlInit_fn = null;
var fn_nvml_shutdown: ?nvmlShutdown_fn = null;
var fn_nvml_get_handle: ?nvmlDeviceGetHandleByIndex_fn = null;
var fn_nvml_get_temp: ?nvmlDeviceGetTemperature_fn = null;
var fn_nvml_get_util: ?nvmlDeviceGetUtilizationRates_fn = null;
var fn_nvml_get_mem: ?nvmlDeviceGetMemoryInfo_fn = null;
var fn_nvml_get_power: ?nvmlDeviceGetPowerUsage_fn = null;

// Metrics cache (updated periodically)
var cached_temp: u32 = 0;
var cached_gpu_util: u32 = 0;
var cached_mem_util: u32 = 0;
var cached_power: u32 = 0;
var cached_vram_used: u64 = 0;
var cached_vram_total: u64 = 0;
var frame_count: u64 = 0;
var fps: u32 = 0;
var fps_frame_count: u64 = 0;
var last_fps_update: u64 = 0;

// Debug output
var debug_enabled: bool = false;

fn debugLog(comptime fmt: []const u8, args: anytype) void {
    if (debug_enabled) {
        std.debug.print("[nvhud] " ++ fmt ++ "\n", args);
    }
}

extern fn getenv(name: [*:0]const u8) ?[*:0]const u8;

fn initGlobalState() void {
    if (initialized) return;

    // Check for debug mode
    if (getenv("NVHUD_DEBUG")) |_| {
        debug_enabled = true;
    }

    debugLog("Initializing nvhud layer", .{});

    const allocator = gpa.allocator();
    instance_map = std.AutoHashMap(usize, *InstanceData).init(allocator);
    device_map = std.AutoHashMap(usize, *DeviceData).init(allocator);
    initialized = true;

    // Initialize NVML
    initNvml();

    debugLog("Layer initialized, NVML: {s}", .{if (nvml_initialized) "OK" else "FAILED"});
}

fn initNvml() void {
    if (nvml_initialized) return;

    nvml_handle = dlopen("libnvidia-ml.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (nvml_handle == null) {
        nvml_handle = dlopen("libnvidia-ml.so", RTLD_NOW | RTLD_GLOBAL);
    }
    if (nvml_handle == null) return;

    const h = nvml_handle.?;
    fn_nvml_init = @ptrCast(dlsym(h, "nvmlInit_v2"));
    fn_nvml_shutdown = @ptrCast(dlsym(h, "nvmlShutdown"));
    fn_nvml_get_handle = @ptrCast(dlsym(h, "nvmlDeviceGetHandleByIndex_v2"));
    fn_nvml_get_temp = @ptrCast(dlsym(h, "nvmlDeviceGetTemperature"));
    fn_nvml_get_util = @ptrCast(dlsym(h, "nvmlDeviceGetUtilizationRates"));
    fn_nvml_get_mem = @ptrCast(dlsym(h, "nvmlDeviceGetMemoryInfo"));
    fn_nvml_get_power = @ptrCast(dlsym(h, "nvmlDeviceGetPowerUsage"));

    if (fn_nvml_init) |init_fn| {
        if (init_fn() == 0) {
            nvml_initialized = true;
            // Get device handle
            if (fn_nvml_get_handle) |get_handle| {
                var dev: *anyopaque = undefined;
                if (get_handle(0, &dev) == 0) {
                    nvml_device = dev;
                }
            }
        }
    }
}

fn updateMetrics() void {
    if (!nvml_initialized or nvml_device == null) return;

    const dev = nvml_device.?;

    // Temperature
    if (fn_nvml_get_temp) |f| {
        var temp: c_uint = 0;
        if (f(dev, 0, &temp) == 0) {
            cached_temp = temp;
        }
    }

    // Utilization
    if (fn_nvml_get_util) |f| {
        var util: NvmlUtilization = undefined;
        if (f(dev, &util) == 0) {
            cached_gpu_util = util.gpu;
            cached_mem_util = util.memory;
        }
    }

    // Memory
    if (fn_nvml_get_mem) |f| {
        var mem: NvmlMemory = undefined;
        if (f(dev, &mem) == 0) {
            cached_vram_used = mem.used;
            cached_vram_total = mem.total;
        }
    }

    // Power
    if (fn_nvml_get_power) |f| {
        var power: c_uint = 0;
        if (f(dev, &power) == 0) {
            cached_power = power / 1000; // mW to W
        }
    }
}

fn getLayerInstanceLink(pCreateInfo: *const VkInstanceCreateInfo) ?*VkLayerInstanceLink {
    var chain_info: ?*const VkLayerInstanceCreateInfo = @ptrCast(@alignCast(pCreateInfo.pNext));
    while (chain_info != null) {
        if (chain_info.?.sType == .VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO and
            chain_info.?.function == .VK_LAYER_LINK_INFO)
        {
            return chain_info.?.u.pLayerInfo;
        }
        chain_info = @ptrCast(@alignCast(chain_info.?.pNext));
    }
    return null;
}

fn getLayerDeviceLink(pCreateInfo: *const VkDeviceCreateInfo) ?*VkLayerDeviceLink {
    var chain_info: ?*const VkLayerDeviceCreateInfo = @ptrCast(@alignCast(pCreateInfo.pNext));
    while (chain_info != null) {
        if (chain_info.?.sType == .VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO and
            chain_info.?.function == .VK_LAYER_LINK_INFO)
        {
            return chain_info.?.u.pLayerInfo;
        }
        chain_info = @ptrCast(@alignCast(chain_info.?.pNext));
    }
    return null;
}

// Layer entry points
export fn nvhud_CreateInstance(
    pCreateInfo: *const VkInstanceCreateInfo,
    pAllocator: ?*const anyopaque,
    pInstance: *VkInstance,
) callconv(.c) VkResult {
    initGlobalState();

    const layer_info = getLayerInstanceLink(pCreateInfo) orelse
        return .VK_ERROR_INITIALIZATION_FAILED;

    const next_gipa = layer_info.pfnNextGetInstanceProcAddr;
    layer_info.pNext = layer_info.pNext;

    // Get vkCreateInstance from next layer
    const create_instance_fn: ?PFN_vkCreateInstance = @ptrCast(next_gipa(null, "vkCreateInstance"));
    if (create_instance_fn == null) return .VK_ERROR_INITIALIZATION_FAILED;

    // Advance the link for the next layer
    if (layer_info.pNext) |next| {
        layer_info.* = next.*;
    }

    // Call the next layer's vkCreateInstance
    const result = create_instance_fn.?(pCreateInfo, pAllocator, pInstance);
    if (result != .VK_SUCCESS) return result;

    // Store instance data
    const allocator = gpa.allocator();
    const instance_data = allocator.create(InstanceData) catch return .VK_ERROR_OUT_OF_HOST_MEMORY;
    instance_data.* = .{
        .instance = pInstance.*,
        .get_instance_proc_addr = next_gipa,
        .destroy_instance = @ptrCast(next_gipa(pInstance.*, "vkDestroyInstance")),
    };

    instance_map.put(@intFromPtr(pInstance.*), instance_data) catch
        return .VK_ERROR_OUT_OF_HOST_MEMORY;

    return .VK_SUCCESS;
}

export fn nvhud_DestroyInstance(
    instance: VkInstance,
    pAllocator: ?*const anyopaque,
) callconv(.c) void {
    const key = @intFromPtr(instance);
    if (instance_map.get(key)) |data| {
        if (data.destroy_instance) |destroy| {
            destroy(instance, pAllocator);
        }
        const allocator = gpa.allocator();
        allocator.destroy(data);
        _ = instance_map.remove(key);
    }
}

export fn nvhud_CreateDevice(
    physicalDevice: VkPhysicalDevice,
    pCreateInfo: *const VkDeviceCreateInfo,
    pAllocator: ?*const anyopaque,
    pDevice: *VkDevice,
) callconv(.c) VkResult {
    const layer_info = getLayerDeviceLink(pCreateInfo) orelse
        return .VK_ERROR_INITIALIZATION_FAILED;

    const next_gipa = layer_info.pfnNextGetInstanceProcAddr;
    const next_gdpa = layer_info.pfnNextGetDeviceProcAddr;

    // Get vkCreateDevice from instance
    const create_device_fn: ?PFN_vkCreateDevice = @ptrCast(next_gipa(null, "vkCreateDevice"));
    if (create_device_fn == null) return .VK_ERROR_INITIALIZATION_FAILED;

    // Advance the link
    if (layer_info.pNext) |next| {
        layer_info.* = next.*;
    }

    const result = create_device_fn.?(physicalDevice, pCreateInfo, pAllocator, pDevice);
    if (result != .VK_SUCCESS) return result;

    // Store device data
    const allocator = gpa.allocator();
    const device_data = allocator.create(DeviceData) catch return .VK_ERROR_OUT_OF_HOST_MEMORY;
    device_data.* = .{
        .device = pDevice.*,
        .physical_device = physicalDevice,
        .instance_data = undefined, // TODO: link to instance
        .get_device_proc_addr = next_gdpa,
        .destroy_device = @ptrCast(next_gdpa(pDevice.*, "vkDestroyDevice")),
        .queue_present = @ptrCast(next_gdpa(pDevice.*, "vkQueuePresentKHR")),
    };

    device_map.put(@intFromPtr(pDevice.*), device_data) catch
        return .VK_ERROR_OUT_OF_HOST_MEMORY;

    return .VK_SUCCESS;
}

export fn nvhud_DestroyDevice(
    device: VkDevice,
    pAllocator: ?*const anyopaque,
) callconv(.c) void {
    const key = @intFromPtr(device);
    if (device_map.get(key)) |data| {
        if (data.destroy_device) |destroy| {
            destroy(device, pAllocator);
        }
        const allocator = gpa.allocator();
        allocator.destroy(data);
        _ = device_map.remove(key);
    }
}

fn getTimeNs() u64 {
    const ts = std.posix.clock_gettime(.MONOTONIC) catch return 0;
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

export fn nvhud_QueuePresentKHR(
    queue: VkQueue,
    pPresentInfo: *const VkPresentInfoKHR,
) callconv(.c) VkResult {
    // Update frame counter
    frame_count += 1;
    fps_frame_count += 1;

    const now = getTimeNs();

    // Update FPS every second
    if (now - last_fps_update >= 1_000_000_000) {
        fps = @intCast(fps_frame_count);
        fps_frame_count = 0;
        last_fps_update = now;

        // Update NVML metrics once per second
        updateMetrics();

        // Debug output
        if (debug_enabled) {
            std.debug.print("[nvhud] FPS: {} | Temp: {}C | GPU: {}% | Power: {}W | VRAM: {}/{} MB\n", .{
                fps,
                cached_temp,
                cached_gpu_util,
                cached_power,
                cached_vram_used / (1024 * 1024),
                cached_vram_total / (1024 * 1024),
            });
        }
    }

    // TODO: Render overlay here before presenting
    // This requires creating command buffers, pipelines, etc.
    // For now, we just pass through to the real present

    // Find the device data to get the real vkQueuePresentKHR
    // For simplicity, iterate through devices (in practice, map queue -> device)
    var it = device_map.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.*.queue_present) |present_fn| {
            return present_fn(queue, pPresentInfo);
        }
    }

    return .VK_ERROR_DEVICE_LOST;
}

// Main entry points for the layer
export fn nvhud_GetInstanceProcAddr(instance: VkInstance, pName: [*:0]const u8) callconv(.c) PFN_vkVoidFunction {
    const name = std.mem.span(pName);

    // Return our intercept functions
    if (std.mem.eql(u8, name, "vkCreateInstance")) return @ptrCast(&nvhud_CreateInstance);
    if (std.mem.eql(u8, name, "vkDestroyInstance")) return @ptrCast(&nvhud_DestroyInstance);
    if (std.mem.eql(u8, name, "vkCreateDevice")) return @ptrCast(&nvhud_CreateDevice);
    if (std.mem.eql(u8, name, "vkDestroyDevice")) return @ptrCast(&nvhud_DestroyDevice);
    if (std.mem.eql(u8, name, "vkGetInstanceProcAddr")) return @ptrCast(&nvhud_GetInstanceProcAddr);
    if (std.mem.eql(u8, name, "vkGetDeviceProcAddr")) return @ptrCast(&nvhud_GetDeviceProcAddr);

    // For other functions, pass through to the next layer
    if (instance) |inst| {
        const key = @intFromPtr(inst);
        if (instance_map.get(key)) |data| {
            return data.get_instance_proc_addr(instance, pName);
        }
    }

    return null;
}

export fn nvhud_GetDeviceProcAddr(device: VkDevice, pName: [*:0]const u8) callconv(.c) PFN_vkVoidFunction {
    const name = std.mem.span(pName);

    // Intercept presentation
    if (std.mem.eql(u8, name, "vkQueuePresentKHR")) return @ptrCast(&nvhud_QueuePresentKHR);
    if (std.mem.eql(u8, name, "vkDestroyDevice")) return @ptrCast(&nvhud_DestroyDevice);
    if (std.mem.eql(u8, name, "vkGetDeviceProcAddr")) return @ptrCast(&nvhud_GetDeviceProcAddr);

    // Pass through to next layer
    if (device) |dev| {
        const key = @intFromPtr(dev);
        if (device_map.get(key)) |data| {
            return data.get_device_proc_addr(device, pName);
        }
    }

    return null;
}

// Negotiate layer interface version
const VkNegotiateLayerInterface = extern struct {
    sType: u32,
    pLayerName: [*:0]const u8,
    specVersion: u32,
    implementationVersion: u32,
    pfnGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnGetDeviceProcAddr: ?PFN_vkGetDeviceProcAddr,
    pfnGetPhysicalDeviceProcAddr: ?*const anyopaque,
};

const LAYER_NEGOTIATE_INTERFACE_STRUCT = 1;
const CURRENT_LOADER_LAYER_INTERFACE_VERSION = 2;

export fn vkNegotiateLoaderLayerInterfaceVersion(pVersionStruct: *VkNegotiateLayerInterface) callconv(.c) VkResult {
    // Enable debug early if env is set
    if (getenv("NVHUD_DEBUG")) |_| {
        debug_enabled = true;
    }

    debugLog("vkNegotiateLoaderLayerInterfaceVersion called", .{});

    if (pVersionStruct.sType != LAYER_NEGOTIATE_INTERFACE_STRUCT) {
        debugLog("Invalid sType: {}", .{pVersionStruct.sType});
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    pVersionStruct.pfnGetInstanceProcAddr = nvhud_GetInstanceProcAddr;
    pVersionStruct.pfnGetDeviceProcAddr = nvhud_GetDeviceProcAddr;
    pVersionStruct.pfnGetPhysicalDeviceProcAddr = null;

    if (pVersionStruct.specVersion > CURRENT_LOADER_LAYER_INTERFACE_VERSION) {
        pVersionStruct.specVersion = CURRENT_LOADER_LAYER_INTERFACE_VERSION;
    }

    debugLog("Layer negotiation successful", .{});
    return .VK_SUCCESS;
}
