//! NVML (NVIDIA Management Library) Bindings for nvhud
//!
//! Direct bindings to libnvidia-ml for GPU metrics - no nvidia-smi subprocess.
//! Uses dlopen with RTLD_GLOBAL to avoid NVML internal symbol resolution issues.

const std = @import("std");

// Use explicit dlopen for proper NVML loading (needs RTLD_GLOBAL)
extern fn dlopen(filename: ?[*:0]const u8, flags: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;

const RTLD_NOW: c_int = 0x00002;
const RTLD_GLOBAL: c_int = 0x00100;

pub const NvmlError = error{
    Uninitialized,
    InvalidArgument,
    NotSupported,
    NoPermission,
    NotFound,
    InsufficientSize,
    DriverNotLoaded,
    LibraryNotFound,
    Unknown,
};

// NVML return codes
const NVML_SUCCESS: c_uint = 0;
const NVML_ERROR_UNINITIALIZED: c_uint = 1;
const NVML_ERROR_INVALID_ARGUMENT: c_uint = 2;
const NVML_ERROR_NOT_SUPPORTED: c_uint = 3;
const NVML_ERROR_NO_PERMISSION: c_uint = 4;
const NVML_ERROR_NOT_FOUND: c_uint = 6;
const NVML_ERROR_INSUFFICIENT_SIZE: c_uint = 7;
const NVML_ERROR_DRIVER_NOT_LOADED: c_uint = 9;
const NVML_ERROR_LIBRARY_NOT_FOUND: c_uint = 12;

fn mapReturn(ret: c_uint) NvmlError!void {
    return switch (ret) {
        NVML_SUCCESS => {},
        NVML_ERROR_UNINITIALIZED => error.Uninitialized,
        NVML_ERROR_INVALID_ARGUMENT => error.InvalidArgument,
        NVML_ERROR_NOT_SUPPORTED => error.NotSupported,
        NVML_ERROR_NO_PERMISSION => error.NoPermission,
        NVML_ERROR_NOT_FOUND => error.NotFound,
        NVML_ERROR_INSUFFICIENT_SIZE => error.InsufficientSize,
        NVML_ERROR_DRIVER_NOT_LOADED => error.DriverNotLoaded,
        NVML_ERROR_LIBRARY_NOT_FOUND => error.LibraryNotFound,
        else => error.Unknown,
    };
}

pub const Device = *anyopaque;

// Constants
pub const CLOCK_GRAPHICS: c_uint = 0;
pub const CLOCK_MEM: c_uint = 2;
pub const CLOCK_SM: c_uint = 1;
pub const CLOCK_VIDEO: c_uint = 3;
pub const TEMPERATURE_GPU: c_uint = 0;

// Architecture IDs
const NVML_DEVICE_ARCH_KEPLER: c_uint = 2;
const NVML_DEVICE_ARCH_MAXWELL: c_uint = 3;
const NVML_DEVICE_ARCH_PASCAL: c_uint = 4;
const NVML_DEVICE_ARCH_VOLTA: c_uint = 5;
const NVML_DEVICE_ARCH_TURING: c_uint = 6;
const NVML_DEVICE_ARCH_AMPERE: c_uint = 7;
const NVML_DEVICE_ARCH_ADA: c_uint = 8;
const NVML_DEVICE_ARCH_HOPPER: c_uint = 9;
const NVML_DEVICE_ARCH_BLACKWELL: c_uint = 10;

// Function pointer types (Zig 0.16: .c not .C)
const nvmlInit_fn = *const fn () callconv(.c) c_uint;
const nvmlShutdown_fn = *const fn () callconv(.c) c_uint;
const nvmlDeviceGetCount_fn = *const fn (*c_uint) callconv(.c) c_uint;
const nvmlDeviceGetHandleByIndex_fn = *const fn (c_uint, *Device) callconv(.c) c_uint;
const nvmlDeviceGetName_fn = *const fn (Device, [*]u8, c_uint) callconv(.c) c_uint;
const nvmlDeviceGetTemperature_fn = *const fn (Device, c_uint, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetUtilizationRates_fn = *const fn (Device, *nvmlUtilization_t) callconv(.c) c_uint;
const nvmlDeviceGetMemoryInfo_fn = *const fn (Device, *nvmlMemory_t) callconv(.c) c_uint;
const nvmlDeviceGetClockInfo_fn = *const fn (Device, c_uint, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetPowerUsage_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetPowerManagementLimit_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetFanSpeed_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetCurrPcieLinkGeneration_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetCurrPcieLinkWidth_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetPerformanceState_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetEncoderUtilization_fn = *const fn (Device, *c_uint, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetDecoderUtilization_fn = *const fn (Device, *c_uint, *c_uint) callconv(.c) c_uint;
const nvmlDeviceGetArchitecture_fn = *const fn (Device, *c_uint) callconv(.c) c_uint;
const nvmlSystemGetDriverVersion_fn = *const fn ([*]u8, c_uint) callconv(.c) c_uint;

// Structs
const nvmlUtilization_t = extern struct {
    gpu: c_uint,
    memory: c_uint,
};

const nvmlMemory_t = extern struct {
    total: u64,
    free: u64,
    used: u64,
};

// Library handle and functions
var lib_handle: ?*anyopaque = null;
var initialized = false;

// Function pointers
var fn_init: ?nvmlInit_fn = null;
var fn_shutdown: ?nvmlShutdown_fn = null;
var fn_getCount: ?nvmlDeviceGetCount_fn = null;
var fn_getHandle: ?nvmlDeviceGetHandleByIndex_fn = null;
var fn_getName: ?nvmlDeviceGetName_fn = null;
var fn_getTemp: ?nvmlDeviceGetTemperature_fn = null;
var fn_getUtil: ?nvmlDeviceGetUtilizationRates_fn = null;
var fn_getMem: ?nvmlDeviceGetMemoryInfo_fn = null;
var fn_getClock: ?nvmlDeviceGetClockInfo_fn = null;
var fn_getPower: ?nvmlDeviceGetPowerUsage_fn = null;
var fn_getPowerLimit: ?nvmlDeviceGetPowerManagementLimit_fn = null;
var fn_getFan: ?nvmlDeviceGetFanSpeed_fn = null;
var fn_getPcieGen: ?nvmlDeviceGetCurrPcieLinkGeneration_fn = null;
var fn_getPcieWidth: ?nvmlDeviceGetCurrPcieLinkWidth_fn = null;
var fn_getPstate: ?nvmlDeviceGetPerformanceState_fn = null;
var fn_getEncoder: ?nvmlDeviceGetEncoderUtilization_fn = null;
var fn_getDecoder: ?nvmlDeviceGetDecoderUtilization_fn = null;
var fn_getArch: ?nvmlDeviceGetArchitecture_fn = null;
var fn_getDriver: ?nvmlSystemGetDriverVersion_fn = null;

// Static buffers for string returns
var driver_version_buf: [80]u8 = undefined;
var device_name_buf: [96]u8 = undefined;

fn lookup(comptime T: type, name: [*:0]const u8) ?T {
    if (lib_handle) |h| {
        const sym = dlsym(h, name);
        if (sym) |s| {
            return @ptrCast(s);
        }
    }
    return null;
}

fn loadLibrary() bool {
    if (lib_handle != null) return true;

    // NVML requires RTLD_GLOBAL for its internal symbol resolution
    lib_handle = dlopen("libnvidia-ml.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (lib_handle == null) {
        lib_handle = dlopen("libnvidia-ml.so", RTLD_NOW | RTLD_GLOBAL);
        if (lib_handle == null) {
            return false;
        }
    }

    fn_init = lookup(nvmlInit_fn, "nvmlInit_v2");
    fn_shutdown = lookup(nvmlShutdown_fn, "nvmlShutdown");
    fn_getCount = lookup(nvmlDeviceGetCount_fn, "nvmlDeviceGetCount_v2");
    fn_getHandle = lookup(nvmlDeviceGetHandleByIndex_fn, "nvmlDeviceGetHandleByIndex_v2");
    fn_getName = lookup(nvmlDeviceGetName_fn, "nvmlDeviceGetName");
    fn_getTemp = lookup(nvmlDeviceGetTemperature_fn, "nvmlDeviceGetTemperature");
    fn_getUtil = lookup(nvmlDeviceGetUtilizationRates_fn, "nvmlDeviceGetUtilizationRates");
    fn_getMem = lookup(nvmlDeviceGetMemoryInfo_fn, "nvmlDeviceGetMemoryInfo");
    fn_getClock = lookup(nvmlDeviceGetClockInfo_fn, "nvmlDeviceGetClockInfo");
    fn_getPower = lookup(nvmlDeviceGetPowerUsage_fn, "nvmlDeviceGetPowerUsage");
    fn_getPowerLimit = lookup(nvmlDeviceGetPowerManagementLimit_fn, "nvmlDeviceGetPowerManagementLimit");
    fn_getFan = lookup(nvmlDeviceGetFanSpeed_fn, "nvmlDeviceGetFanSpeed");
    fn_getPcieGen = lookup(nvmlDeviceGetCurrPcieLinkGeneration_fn, "nvmlDeviceGetCurrPcieLinkGeneration");
    fn_getPcieWidth = lookup(nvmlDeviceGetCurrPcieLinkWidth_fn, "nvmlDeviceGetCurrPcieLinkWidth");
    fn_getPstate = lookup(nvmlDeviceGetPerformanceState_fn, "nvmlDeviceGetPerformanceState");
    fn_getEncoder = lookup(nvmlDeviceGetEncoderUtilization_fn, "nvmlDeviceGetEncoderUtilization");
    fn_getDecoder = lookup(nvmlDeviceGetDecoderUtilization_fn, "nvmlDeviceGetDecoderUtilization");
    fn_getArch = lookup(nvmlDeviceGetArchitecture_fn, "nvmlDeviceGetArchitecture");
    fn_getDriver = lookup(nvmlSystemGetDriverVersion_fn, "nvmlSystemGetDriverVersion");

    return fn_init != null;
}

/// Initialize NVML
pub fn init() NvmlError!void {
    if (initialized) return;
    if (!loadLibrary()) return error.LibraryNotFound;
    if (fn_init) |f| {
        try mapReturn(f());
        initialized = true;
    } else {
        return error.LibraryNotFound;
    }
}

/// Shutdown NVML
pub fn shutdown() void {
    if (!initialized) return;
    if (fn_shutdown) |f| _ = f();
    initialized = false;
}

/// Check if NVML is available
pub fn isAvailable() bool {
    if (init()) {
        return true;
    } else |_| {
        return false;
    }
}

/// Get driver version string
pub fn getDriverVersion() NvmlError![]const u8 {
    if (fn_getDriver) |f| {
        try mapReturn(f(&driver_version_buf, driver_version_buf.len));
        const len = std.mem.indexOfScalar(u8, &driver_version_buf, 0) orelse driver_version_buf.len;
        return driver_version_buf[0..len];
    }
    return error.NotSupported;
}

/// Get device count
pub fn getDeviceCount() NvmlError!u32 {
    var count: c_uint = 0;
    if (fn_getCount) |f| {
        try mapReturn(f(&count));
        return count;
    }
    return error.NotSupported;
}

/// Get device by index
pub fn getDevice(index: u32) NvmlError!Device {
    var device: Device = undefined;
    if (fn_getHandle) |f| {
        try mapReturn(f(index, &device));
        return device;
    }
    return error.NotSupported;
}

/// Get device name
pub fn getDeviceName(device: Device) NvmlError![]const u8 {
    if (fn_getName) |f| {
        try mapReturn(f(device, &device_name_buf, device_name_buf.len));
        const len = std.mem.indexOfScalar(u8, &device_name_buf, 0) orelse device_name_buf.len;
        return device_name_buf[0..len];
    }
    return error.NotSupported;
}

/// Get GPU temperature (Celsius)
pub fn getTemperature(device: Device) NvmlError!u32 {
    var temp: c_uint = 0;
    if (fn_getTemp) |f| {
        try mapReturn(f(device, TEMPERATURE_GPU, &temp));
        return temp;
    }
    return error.NotSupported;
}

/// Get GPU utilization (0-100%)
pub fn getGpuUtilization(device: Device) NvmlError!u32 {
    var util: nvmlUtilization_t = undefined;
    if (fn_getUtil) |f| {
        try mapReturn(f(device, &util));
        return util.gpu;
    }
    return error.NotSupported;
}

/// Get memory utilization (0-100%)
pub fn getMemoryUtilization(device: Device) NvmlError!u32 {
    var util: nvmlUtilization_t = undefined;
    if (fn_getUtil) |f| {
        try mapReturn(f(device, &util));
        return util.memory;
    }
    return error.NotSupported;
}

/// Memory info
pub const MemoryInfo = struct {
    total: u64,
    used: u64,
    free: u64,
};

/// Get memory info (bytes)
pub fn getMemoryInfo(device: Device) NvmlError!MemoryInfo {
    var mem: nvmlMemory_t = undefined;
    if (fn_getMem) |f| {
        try mapReturn(f(device, &mem));
        return MemoryInfo{
            .total = mem.total,
            .used = mem.used,
            .free = mem.free,
        };
    }
    return error.NotSupported;
}

/// Get clock speed (MHz)
pub fn getClock(device: Device, clock_type: c_uint) NvmlError!u32 {
    var clock: c_uint = 0;
    if (fn_getClock) |f| {
        try mapReturn(f(device, clock_type, &clock));
        return clock;
    }
    return error.NotSupported;
}

/// Get power usage (milliwatts)
pub fn getPowerUsage(device: Device) NvmlError!u32 {
    var power: c_uint = 0;
    if (fn_getPower) |f| {
        try mapReturn(f(device, &power));
        return power;
    }
    return error.NotSupported;
}

/// Get power limit (milliwatts)
pub fn getPowerLimit(device: Device) NvmlError!u32 {
    var limit: c_uint = 0;
    if (fn_getPowerLimit) |f| {
        try mapReturn(f(device, &limit));
        return limit;
    }
    return error.NotSupported;
}

/// Get fan speed (0-100%)
pub fn getFanSpeed(device: Device) NvmlError!u32 {
    var speed: c_uint = 0;
    if (fn_getFan) |f| {
        try mapReturn(f(device, &speed));
        return speed;
    }
    return error.NotSupported;
}

/// Get PCIe generation
pub fn getPcieGeneration(device: Device) NvmlError!u32 {
    var gen: c_uint = 0;
    if (fn_getPcieGen) |f| {
        try mapReturn(f(device, &gen));
        return gen;
    }
    return error.NotSupported;
}

/// Get PCIe link width
pub fn getPcieWidth(device: Device) NvmlError!u32 {
    var width: c_uint = 0;
    if (fn_getPcieWidth) |f| {
        try mapReturn(f(device, &width));
        return width;
    }
    return error.NotSupported;
}

/// Get performance state (P-state)
pub fn getPerformanceState(device: Device) NvmlError!u32 {
    var pstate: c_uint = 0;
    if (fn_getPstate) |f| {
        try mapReturn(f(device, &pstate));
        return pstate;
    }
    return error.NotSupported;
}

/// Get encoder utilization
pub fn getEncoderUtilization(device: Device) NvmlError!u32 {
    var util: c_uint = 0;
    var period: c_uint = 0;
    if (fn_getEncoder) |f| {
        try mapReturn(f(device, &util, &period));
        return util;
    }
    return error.NotSupported;
}

/// Get decoder utilization
pub fn getDecoderUtilization(device: Device) NvmlError!u32 {
    var util: c_uint = 0;
    var period: c_uint = 0;
    if (fn_getDecoder) |f| {
        try mapReturn(f(device, &util, &period));
        return util;
    }
    return error.NotSupported;
}

/// Architecture names
pub fn getArchitectureName(device: Device) []const u8 {
    var arch: c_uint = 0;
    if (fn_getArch) |f| {
        if (mapReturn(f(device, &arch))) {
            return switch (arch) {
                NVML_DEVICE_ARCH_KEPLER => "Kepler",
                NVML_DEVICE_ARCH_MAXWELL => "Maxwell",
                NVML_DEVICE_ARCH_PASCAL => "Pascal",
                NVML_DEVICE_ARCH_VOLTA => "Volta",
                NVML_DEVICE_ARCH_TURING => "Turing",
                NVML_DEVICE_ARCH_AMPERE => "Ampere",
                NVML_DEVICE_ARCH_ADA => "Ada Lovelace",
                NVML_DEVICE_ARCH_HOPPER => "Hopper",
                NVML_DEVICE_ARCH_BLACKWELL => "Blackwell",
                else => "Unknown",
            };
        } else |_| {}
    }
    return "Unknown";
}

test "nvml constants" {
    _ = CLOCK_GRAPHICS;
    _ = CLOCK_MEM;
    _ = TEMPERATURE_GPU;
}
