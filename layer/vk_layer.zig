//! nvhud Vulkan Layer
//!
//! Implements a Vulkan layer that renders GPU metrics as an overlay.
//! Intercepts vkQueuePresentKHR to draw the HUD before presenting.

const std = @import("std");
const builtin = @import("builtin");

// Vulkan types (definitions needed for layer)
const VkResult = enum(i32) {
    VK_SUCCESS = 0,
    VK_NOT_READY = 1,
    VK_TIMEOUT = 2,
    VK_EVENT_SET = 3,
    VK_EVENT_RESET = 4,
    VK_INCOMPLETE = 5,
    VK_SUBOPTIMAL_KHR = 1000001003,
    VK_ERROR_OUT_OF_HOST_MEMORY = -1,
    VK_ERROR_OUT_OF_DEVICE_MEMORY = -2,
    VK_ERROR_INITIALIZATION_FAILED = -3,
    VK_ERROR_DEVICE_LOST = -4,
    VK_ERROR_MEMORY_MAP_FAILED = -5,
    VK_ERROR_LAYER_NOT_PRESENT = -6,
    VK_ERROR_EXTENSION_NOT_PRESENT = -7,
    VK_ERROR_OUT_OF_DATE_KHR = -1000001004,
    _,
};

const VkStructureType = enum(i32) {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1,
    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2,
    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3,
    VK_STRUCTURE_TYPE_SUBMIT_INFO = 4,
    VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO = 5,
    VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE = 6,
    VK_STRUCTURE_TYPE_BIND_SPARSE_INFO = 7,
    VK_STRUCTURE_TYPE_FENCE_CREATE_INFO = 8,
    VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO = 9,
    VK_STRUCTURE_TYPE_EVENT_CREATE_INFO = 10,
    VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO = 11,
    VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO = 12,
    VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO = 13,
    VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO = 14,
    VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO = 15,
    VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO = 16,
    VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO = 17,
    VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO = 18,
    VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19,
    VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20,
    VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO = 21,
    VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22,
    VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23,
    VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24,
    VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO = 25,
    VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26,
    VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27,
    VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO = 28,
    VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO = 29,
    VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO = 30,
    VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO = 31,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
    VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO = 33,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO = 34,
    VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET = 35,
    VK_STRUCTURE_TYPE_COPY_DESCRIPTOR_SET = 36,
    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO = 37,
    VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO = 38,
    VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO = 39,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = 40,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO = 41,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO = 42,
    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO = 43,
    VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO = 47,
    VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO = 48,
    VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = 1000001000,
    VK_STRUCTURE_TYPE_PRESENT_INFO_KHR = 1000001001,
    _,
};

const VkLayerFunction = enum(i32) {
    VK_LAYER_LINK_INFO = 0,
    VK_LOADER_DATA_CALLBACK = 1,
    VK_LOADER_LAYER_CREATE_DEVICE_CALLBACK = 2,
    VK_LOADER_FEATURES = 3,
};

// Vulkan format enum
const VkFormat = enum(i32) {
    VK_FORMAT_UNDEFINED = 0,
    VK_FORMAT_R8G8B8A8_UNORM = 37,
    VK_FORMAT_R8G8B8A8_SRGB = 43,
    VK_FORMAT_B8G8R8A8_UNORM = 44,
    VK_FORMAT_B8G8R8A8_SRGB = 50,
    VK_FORMAT_A2B10G10R10_UNORM_PACK32 = 64,
    VK_FORMAT_R16G16B16A16_SFLOAT = 97,
    _,
};

// Vulkan enums for rendering
const VkImageLayout = enum(i32) {
    VK_IMAGE_LAYOUT_UNDEFINED = 0,
    VK_IMAGE_LAYOUT_GENERAL = 1,
    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL = 2,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL = 3,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL = 4,
    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL = 5,
    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL = 6,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL = 7,
    VK_IMAGE_LAYOUT_PREINITIALIZED = 8,
    VK_IMAGE_LAYOUT_PRESENT_SRC_KHR = 1000001002,
    _,
};

const VkAttachmentLoadOp = enum(i32) {
    VK_ATTACHMENT_LOAD_OP_LOAD = 0,
    VK_ATTACHMENT_LOAD_OP_CLEAR = 1,
    VK_ATTACHMENT_LOAD_OP_DONT_CARE = 2,
};

const VkAttachmentStoreOp = enum(i32) {
    VK_ATTACHMENT_STORE_OP_STORE = 0,
    VK_ATTACHMENT_STORE_OP_DONT_CARE = 1,
};

const VkSampleCountFlagBits = enum(u32) {
    VK_SAMPLE_COUNT_1_BIT = 0x00000001,
    VK_SAMPLE_COUNT_2_BIT = 0x00000002,
    VK_SAMPLE_COUNT_4_BIT = 0x00000004,
    VK_SAMPLE_COUNT_8_BIT = 0x00000008,
};

const VkPipelineBindPoint = enum(i32) {
    VK_PIPELINE_BIND_POINT_GRAPHICS = 0,
    VK_PIPELINE_BIND_POINT_COMPUTE = 1,
};

const VkImageViewType = enum(i32) {
    VK_IMAGE_VIEW_TYPE_1D = 0,
    VK_IMAGE_VIEW_TYPE_2D = 1,
    VK_IMAGE_VIEW_TYPE_3D = 2,
    VK_IMAGE_VIEW_TYPE_CUBE = 3,
    VK_IMAGE_VIEW_TYPE_1D_ARRAY = 4,
    VK_IMAGE_VIEW_TYPE_2D_ARRAY = 5,
    VK_IMAGE_VIEW_TYPE_CUBE_ARRAY = 6,
};

const VkComponentSwizzle = enum(i32) {
    VK_COMPONENT_SWIZZLE_IDENTITY = 0,
    VK_COMPONENT_SWIZZLE_ZERO = 1,
    VK_COMPONENT_SWIZZLE_ONE = 2,
    VK_COMPONENT_SWIZZLE_R = 3,
    VK_COMPONENT_SWIZZLE_G = 4,
    VK_COMPONENT_SWIZZLE_B = 5,
    VK_COMPONENT_SWIZZLE_A = 6,
};

const VkImageAspectFlags = u32;
const VK_IMAGE_ASPECT_COLOR_BIT: VkImageAspectFlags = 0x00000001;

const VkCommandBufferLevel = enum(i32) {
    VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0,
    VK_COMMAND_BUFFER_LEVEL_SECONDARY = 1,
};

const VkSubpassContents = enum(i32) {
    VK_SUBPASS_CONTENTS_INLINE = 0,
    VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS = 1,
};

const VkPipelineStageFlags = u32;
const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: VkPipelineStageFlags = 0x00000400;
const VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT: VkPipelineStageFlags = 0x00002000;

const VkAccessFlags = u32;
const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: VkAccessFlags = 0x00000100;

const VkDependencyFlags = u32;
const VK_DEPENDENCY_BY_REGION_BIT: VkDependencyFlags = 0x00000001;

const VkShaderStageFlagBits = enum(u32) {
    VK_SHADER_STAGE_VERTEX_BIT = 0x00000001,
    VK_SHADER_STAGE_FRAGMENT_BIT = 0x00000010,
};

const VkPrimitiveTopology = enum(i32) {
    VK_PRIMITIVE_TOPOLOGY_POINT_LIST = 0,
    VK_PRIMITIVE_TOPOLOGY_LINE_LIST = 1,
    VK_PRIMITIVE_TOPOLOGY_LINE_STRIP = 2,
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = 3,
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = 4,
};

const VkPolygonMode = enum(i32) {
    VK_POLYGON_MODE_FILL = 0,
    VK_POLYGON_MODE_LINE = 1,
    VK_POLYGON_MODE_POINT = 2,
};

const VkCullModeFlags = u32;
const VK_CULL_MODE_NONE: VkCullModeFlags = 0;
const VK_CULL_MODE_BACK_BIT: VkCullModeFlags = 0x00000002;

const VkFrontFace = enum(i32) {
    VK_FRONT_FACE_COUNTER_CLOCKWISE = 0,
    VK_FRONT_FACE_CLOCKWISE = 1,
};

const VkBlendFactor = enum(i32) {
    VK_BLEND_FACTOR_ZERO = 0,
    VK_BLEND_FACTOR_ONE = 1,
    VK_BLEND_FACTOR_SRC_COLOR = 2,
    VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR = 3,
    VK_BLEND_FACTOR_DST_COLOR = 4,
    VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR = 5,
    VK_BLEND_FACTOR_SRC_ALPHA = 6,
    VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA = 7,
    VK_BLEND_FACTOR_DST_ALPHA = 8,
    VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA = 9,
};

const VkBlendOp = enum(i32) {
    VK_BLEND_OP_ADD = 0,
    VK_BLEND_OP_SUBTRACT = 1,
    VK_BLEND_OP_REVERSE_SUBTRACT = 2,
    VK_BLEND_OP_MIN = 3,
    VK_BLEND_OP_MAX = 4,
};

const VkColorComponentFlags = u32;
const VK_COLOR_COMPONENT_R_BIT: VkColorComponentFlags = 0x00000001;
const VK_COLOR_COMPONENT_G_BIT: VkColorComponentFlags = 0x00000002;
const VK_COLOR_COMPONENT_B_BIT: VkColorComponentFlags = 0x00000004;
const VK_COLOR_COMPONENT_A_BIT: VkColorComponentFlags = 0x00000008;
const VK_COLOR_COMPONENT_ALL: VkColorComponentFlags = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

const VkLogicOp = enum(i32) {
    VK_LOGIC_OP_CLEAR = 0,
    VK_LOGIC_OP_COPY = 3,
};

const VkDynamicState = enum(i32) {
    VK_DYNAMIC_STATE_VIEWPORT = 0,
    VK_DYNAMIC_STATE_SCISSOR = 1,
};

const VkInstance = ?*anyopaque;
const VkPhysicalDevice = ?*anyopaque;
const VkDevice = ?*anyopaque;
const VkQueue = ?*anyopaque;
const VkSemaphore = ?*anyopaque;
const VkSwapchainKHR = u64;
const VkFence = u64;
const VkImage = u64;
const VkImageView = u64;
const VkRenderPass = u64;
const VkFramebuffer = u64;
const VkCommandPool = u64;
const VkCommandBuffer = ?*anyopaque;
const VkPipeline = u64;
const VkPipelineLayout = u64;
const VkShaderModule = u64;
const VkBuffer = u64;
const VkDeviceMemory = u64;

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

// Extent structures
const VkExtent2D = extern struct {
    width: u32,
    height: u32,
};

const VkExtent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32,
};

const VkOffset2D = extern struct {
    x: i32,
    y: i32,
};

const VkRect2D = extern struct {
    offset: VkOffset2D,
    extent: VkExtent2D,
};

const VkViewport = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    minDepth: f32,
    maxDepth: f32,
};

// Swapchain create info
const VkSwapchainCreateInfoKHR = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    surface: u64, // VkSurfaceKHR
    minImageCount: u32,
    imageFormat: VkFormat,
    imageColorSpace: i32,
    imageExtent: VkExtent2D,
    imageArrayLayers: u32,
    imageUsage: u32,
    imageSharingMode: i32,
    queueFamilyIndexCount: u32,
    pQueueFamilyIndices: ?[*]const u32,
    preTransform: u32,
    compositeAlpha: u32,
    presentMode: i32,
    clipped: u32,
    oldSwapchain: VkSwapchainKHR,
};

// Component mapping for image views
const VkComponentMapping = extern struct {
    r: VkComponentSwizzle,
    g: VkComponentSwizzle,
    b: VkComponentSwizzle,
    a: VkComponentSwizzle,
};

// Image subresource range
const VkImageSubresourceRange = extern struct {
    aspectMask: VkImageAspectFlags,
    baseMipLevel: u32,
    levelCount: u32,
    baseArrayLayer: u32,
    layerCount: u32,
};

// Image view create info
const VkImageViewCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    image: VkImage,
    viewType: VkImageViewType,
    format: VkFormat,
    components: VkComponentMapping,
    subresourceRange: VkImageSubresourceRange,
};

// Attachment description for render pass
const VkAttachmentDescription = extern struct {
    flags: u32,
    format: VkFormat,
    samples: VkSampleCountFlagBits,
    loadOp: VkAttachmentLoadOp,
    storeOp: VkAttachmentStoreOp,
    stencilLoadOp: VkAttachmentLoadOp,
    stencilStoreOp: VkAttachmentStoreOp,
    initialLayout: VkImageLayout,
    finalLayout: VkImageLayout,
};

// Attachment reference
const VkAttachmentReference = extern struct {
    attachment: u32,
    layout: VkImageLayout,
};

// Subpass description
const VkSubpassDescription = extern struct {
    flags: u32,
    pipelineBindPoint: VkPipelineBindPoint,
    inputAttachmentCount: u32,
    pInputAttachments: ?[*]const VkAttachmentReference,
    colorAttachmentCount: u32,
    pColorAttachments: ?[*]const VkAttachmentReference,
    pResolveAttachments: ?[*]const VkAttachmentReference,
    pDepthStencilAttachment: ?*const VkAttachmentReference,
    preserveAttachmentCount: u32,
    pPreserveAttachments: ?[*]const u32,
};

// Subpass dependency
const VkSubpassDependency = extern struct {
    srcSubpass: u32,
    dstSubpass: u32,
    srcStageMask: VkPipelineStageFlags,
    dstStageMask: VkPipelineStageFlags,
    srcAccessMask: VkAccessFlags,
    dstAccessMask: VkAccessFlags,
    dependencyFlags: VkDependencyFlags,
};

// Render pass create info
const VkRenderPassCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    attachmentCount: u32,
    pAttachments: ?[*]const VkAttachmentDescription,
    subpassCount: u32,
    pSubpasses: ?[*]const VkSubpassDescription,
    dependencyCount: u32,
    pDependencies: ?[*]const VkSubpassDependency,
};

// Framebuffer create info
const VkFramebufferCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    renderPass: VkRenderPass,
    attachmentCount: u32,
    pAttachments: ?[*]const VkImageView,
    width: u32,
    height: u32,
    layers: u32,
};

// Command pool create info
const VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    queueFamilyIndex: u32,
};

const VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: u32 = 0x00000002;

// Command buffer allocate info
const VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    commandPool: VkCommandPool,
    level: VkCommandBufferLevel,
    commandBufferCount: u32,
};

// Command buffer begin info
const VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    pInheritanceInfo: ?*const anyopaque,
};

const VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: u32 = 0x00000001;

// Clear value union
const VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

const VkClearDepthStencilValue = extern struct {
    depth: f32,
    stencil: u32,
};

const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

// Render pass begin info
const VkRenderPassBeginInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    renderPass: VkRenderPass,
    framebuffer: VkFramebuffer,
    renderArea: VkRect2D,
    clearValueCount: u32,
    pClearValues: ?[*]const VkClearValue,
};

// Submit info
const VkSubmitInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    waitSemaphoreCount: u32,
    pWaitSemaphores: ?[*]const VkSemaphore,
    pWaitDstStageMask: ?[*]const VkPipelineStageFlags,
    commandBufferCount: u32,
    pCommandBuffers: ?[*]const VkCommandBuffer,
    signalSemaphoreCount: u32,
    pSignalSemaphores: ?[*]const VkSemaphore,
};

// Shader module create info
const VkShaderModuleCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    codeSize: usize,
    pCode: [*]const u32,
};

// Pipeline shader stage create info
const VkPipelineShaderStageCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    stage: VkShaderStageFlagBits,
    module: VkShaderModule,
    pName: [*:0]const u8,
    pSpecializationInfo: ?*const anyopaque,
};

// Vertex input state
const VkVertexInputBindingDescription = extern struct {
    binding: u32,
    stride: u32,
    inputRate: u32,
};

const VkVertexInputAttributeDescription = extern struct {
    location: u32,
    binding: u32,
    format: VkFormat,
    offset: u32,
};

const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    vertexBindingDescriptionCount: u32,
    pVertexBindingDescriptions: ?[*]const VkVertexInputBindingDescription,
    vertexAttributeDescriptionCount: u32,
    pVertexAttributeDescriptions: ?[*]const VkVertexInputAttributeDescription,
};

// Input assembly state
const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    topology: VkPrimitiveTopology,
    primitiveRestartEnable: u32,
};

// Viewport state
const VkPipelineViewportStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    viewportCount: u32,
    pViewports: ?[*]const VkViewport,
    scissorCount: u32,
    pScissors: ?[*]const VkRect2D,
};

// Rasterization state
const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    depthClampEnable: u32,
    rasterizerDiscardEnable: u32,
    polygonMode: VkPolygonMode,
    cullMode: VkCullModeFlags,
    frontFace: VkFrontFace,
    depthBiasEnable: u32,
    depthBiasConstantFactor: f32,
    depthBiasClamp: f32,
    depthBiasSlopeFactor: f32,
    lineWidth: f32,
};

// Multisample state
const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    rasterizationSamples: VkSampleCountFlagBits,
    sampleShadingEnable: u32,
    minSampleShading: f32,
    pSampleMask: ?[*]const u32,
    alphaToCoverageEnable: u32,
    alphaToOneEnable: u32,
};

// Color blend attachment state
const VkPipelineColorBlendAttachmentState = extern struct {
    blendEnable: u32,
    srcColorBlendFactor: VkBlendFactor,
    dstColorBlendFactor: VkBlendFactor,
    colorBlendOp: VkBlendOp,
    srcAlphaBlendFactor: VkBlendFactor,
    dstAlphaBlendFactor: VkBlendFactor,
    alphaBlendOp: VkBlendOp,
    colorWriteMask: VkColorComponentFlags,
};

// Color blend state
const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    logicOpEnable: u32,
    logicOp: VkLogicOp,
    attachmentCount: u32,
    pAttachments: ?[*]const VkPipelineColorBlendAttachmentState,
    blendConstants: [4]f32,
};

// Dynamic state
const VkPipelineDynamicStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    dynamicStateCount: u32,
    pDynamicStates: ?[*]const VkDynamicState,
};

// Push constant range
const VkPushConstantRange = extern struct {
    stageFlags: u32,
    offset: u32,
    size: u32,
};

// Pipeline layout create info
const VkPipelineLayoutCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    setLayoutCount: u32,
    pSetLayouts: ?[*]const u64, // VkDescriptorSetLayout
    pushConstantRangeCount: u32,
    pPushConstantRanges: ?[*]const VkPushConstantRange,
};

// Graphics pipeline create info
const VkGraphicsPipelineCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
    stageCount: u32,
    pStages: [*]const VkPipelineShaderStageCreateInfo,
    pVertexInputState: *const VkPipelineVertexInputStateCreateInfo,
    pInputAssemblyState: *const VkPipelineInputAssemblyStateCreateInfo,
    pTessellationState: ?*const anyopaque,
    pViewportState: *const VkPipelineViewportStateCreateInfo,
    pRasterizationState: *const VkPipelineRasterizationStateCreateInfo,
    pMultisampleState: *const VkPipelineMultisampleStateCreateInfo,
    pDepthStencilState: ?*const anyopaque,
    pColorBlendState: *const VkPipelineColorBlendStateCreateInfo,
    pDynamicState: ?*const VkPipelineDynamicStateCreateInfo,
    layout: VkPipelineLayout,
    renderPass: VkRenderPass,
    subpass: u32,
    basePipelineHandle: VkPipeline,
    basePipelineIndex: i32,
};

// Additional function pointer types for rendering
const PFN_vkCreateSwapchainKHR = *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const anyopaque, *VkSwapchainKHR) callconv(.c) VkResult;
const PFN_vkDestroySwapchainKHR = *const fn (VkDevice, VkSwapchainKHR, ?*const anyopaque) callconv(.c) void;
const PFN_vkGetSwapchainImagesKHR = *const fn (VkDevice, VkSwapchainKHR, *u32, ?[*]VkImage) callconv(.c) VkResult;
const PFN_vkCreateImageView = *const fn (VkDevice, *const VkImageViewCreateInfo, ?*const anyopaque, *VkImageView) callconv(.c) VkResult;
const PFN_vkDestroyImageView = *const fn (VkDevice, VkImageView, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateRenderPass = *const fn (VkDevice, *const VkRenderPassCreateInfo, ?*const anyopaque, *VkRenderPass) callconv(.c) VkResult;
const PFN_vkDestroyRenderPass = *const fn (VkDevice, VkRenderPass, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateFramebuffer = *const fn (VkDevice, *const VkFramebufferCreateInfo, ?*const anyopaque, *VkFramebuffer) callconv(.c) VkResult;
const PFN_vkDestroyFramebuffer = *const fn (VkDevice, VkFramebuffer, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateCommandPool = *const fn (VkDevice, *const VkCommandPoolCreateInfo, ?*const anyopaque, *VkCommandPool) callconv(.c) VkResult;
const PFN_vkDestroyCommandPool = *const fn (VkDevice, VkCommandPool, ?*const anyopaque) callconv(.c) void;
const PFN_vkAllocateCommandBuffers = *const fn (VkDevice, *const VkCommandBufferAllocateInfo, [*]VkCommandBuffer) callconv(.c) VkResult;
const PFN_vkFreeCommandBuffers = *const fn (VkDevice, VkCommandPool, u32, [*]const VkCommandBuffer) callconv(.c) void;
const PFN_vkBeginCommandBuffer = *const fn (VkCommandBuffer, *const VkCommandBufferBeginInfo) callconv(.c) VkResult;
const PFN_vkEndCommandBuffer = *const fn (VkCommandBuffer) callconv(.c) VkResult;
const PFN_vkResetCommandBuffer = *const fn (VkCommandBuffer, u32) callconv(.c) VkResult;
const PFN_vkCmdBeginRenderPass = *const fn (VkCommandBuffer, *const VkRenderPassBeginInfo, VkSubpassContents) callconv(.c) void;
const PFN_vkCmdEndRenderPass = *const fn (VkCommandBuffer) callconv(.c) void;
const PFN_vkCmdBindPipeline = *const fn (VkCommandBuffer, VkPipelineBindPoint, VkPipeline) callconv(.c) void;
const PFN_vkCmdSetViewport = *const fn (VkCommandBuffer, u32, u32, [*]const VkViewport) callconv(.c) void;
const PFN_vkCmdSetScissor = *const fn (VkCommandBuffer, u32, u32, [*]const VkRect2D) callconv(.c) void;
const PFN_vkCmdDraw = *const fn (VkCommandBuffer, u32, u32, u32, u32) callconv(.c) void;
const PFN_vkCmdPushConstants = *const fn (VkCommandBuffer, VkPipelineLayout, u32, u32, u32, *const anyopaque) callconv(.c) void;
const PFN_vkQueueSubmit = *const fn (VkQueue, u32, [*]const VkSubmitInfo, VkFence) callconv(.c) VkResult;
const PFN_vkQueueWaitIdle = *const fn (VkQueue) callconv(.c) VkResult;
const PFN_vkDeviceWaitIdle = *const fn (VkDevice) callconv(.c) VkResult;
const PFN_vkCreateShaderModule = *const fn (VkDevice, *const VkShaderModuleCreateInfo, ?*const anyopaque, *VkShaderModule) callconv(.c) VkResult;
const PFN_vkDestroyShaderModule = *const fn (VkDevice, VkShaderModule, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreatePipelineLayout = *const fn (VkDevice, *const VkPipelineLayoutCreateInfo, ?*const anyopaque, *VkPipelineLayout) callconv(.c) VkResult;
const PFN_vkDestroyPipelineLayout = *const fn (VkDevice, VkPipelineLayout, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateGraphicsPipelines = *const fn (VkDevice, u64, u32, [*]const VkGraphicsPipelineCreateInfo, ?*const anyopaque, [*]VkPipeline) callconv(.c) VkResult;
const PFN_vkDestroyPipeline = *const fn (VkDevice, VkPipeline, ?*const anyopaque) callconv(.c) void;
const PFN_vkGetDeviceQueue = *const fn (VkDevice, u32, u32, *VkQueue) callconv(.c) void;

// Instance data storage
const InstanceData = struct {
    instance: VkInstance,
    get_instance_proc_addr: PFN_vkGetInstanceProcAddr,
    destroy_instance: ?PFN_vkDestroyInstance,
};

// Maximum swapchain images we support
const MAX_SWAPCHAIN_IMAGES = 8;

// Swapchain data - tracks all resources needed for overlay rendering
const SwapchainData = struct {
    swapchain: VkSwapchainKHR = 0,
    format: VkFormat = .VK_FORMAT_UNDEFINED,
    extent: VkExtent2D = .{ .width = 0, .height = 0 },
    image_count: u32 = 0,
    images: [MAX_SWAPCHAIN_IMAGES]VkImage = [_]VkImage{0} ** MAX_SWAPCHAIN_IMAGES,
    image_views: [MAX_SWAPCHAIN_IMAGES]VkImageView = [_]VkImageView{0} ** MAX_SWAPCHAIN_IMAGES,
    framebuffers: [MAX_SWAPCHAIN_IMAGES]VkFramebuffer = [_]VkFramebuffer{0} ** MAX_SWAPCHAIN_IMAGES,
    command_buffers: [MAX_SWAPCHAIN_IMAGES]VkCommandBuffer = [_]VkCommandBuffer{null} ** MAX_SWAPCHAIN_IMAGES,
    render_pass: VkRenderPass = 0,
    pipeline: VkPipeline = 0,
    pipeline_layout: VkPipelineLayout = 0,
    command_pool: VkCommandPool = 0,
    graphics_queue: VkQueue = null,
    graphics_queue_family: u32 = 0,
    initialized: bool = false,
};

// Device data storage - includes all function pointers and swapchain data
const DeviceData = struct {
    device: VkDevice,
    physical_device: VkPhysicalDevice,
    instance_data: *InstanceData,
    get_device_proc_addr: PFN_vkGetDeviceProcAddr,
    destroy_device: ?PFN_vkDestroyDevice,
    queue_present: ?PFN_vkQueuePresentKHR,

    // Swapchain functions
    create_swapchain: ?PFN_vkCreateSwapchainKHR = null,
    destroy_swapchain: ?PFN_vkDestroySwapchainKHR = null,
    get_swapchain_images: ?PFN_vkGetSwapchainImagesKHR = null,

    // Rendering functions
    create_image_view: ?PFN_vkCreateImageView = null,
    destroy_image_view: ?PFN_vkDestroyImageView = null,
    create_render_pass: ?PFN_vkCreateRenderPass = null,
    destroy_render_pass: ?PFN_vkDestroyRenderPass = null,
    create_framebuffer: ?PFN_vkCreateFramebuffer = null,
    destroy_framebuffer: ?PFN_vkDestroyFramebuffer = null,
    create_command_pool: ?PFN_vkCreateCommandPool = null,
    destroy_command_pool: ?PFN_vkDestroyCommandPool = null,
    allocate_command_buffers: ?PFN_vkAllocateCommandBuffers = null,
    free_command_buffers: ?PFN_vkFreeCommandBuffers = null,
    begin_command_buffer: ?PFN_vkBeginCommandBuffer = null,
    end_command_buffer: ?PFN_vkEndCommandBuffer = null,
    reset_command_buffer: ?PFN_vkResetCommandBuffer = null,
    cmd_begin_render_pass: ?PFN_vkCmdBeginRenderPass = null,
    cmd_end_render_pass: ?PFN_vkCmdEndRenderPass = null,
    cmd_bind_pipeline: ?PFN_vkCmdBindPipeline = null,
    cmd_set_viewport: ?PFN_vkCmdSetViewport = null,
    cmd_set_scissor: ?PFN_vkCmdSetScissor = null,
    cmd_draw: ?PFN_vkCmdDraw = null,
    cmd_push_constants: ?PFN_vkCmdPushConstants = null,
    queue_submit: ?PFN_vkQueueSubmit = null,
    queue_wait_idle: ?PFN_vkQueueWaitIdle = null,
    device_wait_idle: ?PFN_vkDeviceWaitIdle = null,
    create_shader_module: ?PFN_vkCreateShaderModule = null,
    destroy_shader_module: ?PFN_vkDestroyShaderModule = null,
    create_pipeline_layout: ?PFN_vkCreatePipelineLayout = null,
    destroy_pipeline_layout: ?PFN_vkDestroyPipelineLayout = null,
    create_graphics_pipelines: ?PFN_vkCreateGraphicsPipelines = null,
    destroy_pipeline: ?PFN_vkDestroyPipeline = null,
    get_device_queue: ?PFN_vkGetDeviceQueue = null,

    // Swapchain data (one per swapchain, but we only track one for simplicity)
    swapchain_data: SwapchainData = .{},
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

    // Load swapchain functions
    device_data.create_swapchain = @ptrCast(next_gdpa(pDevice.*, "vkCreateSwapchainKHR"));
    device_data.destroy_swapchain = @ptrCast(next_gdpa(pDevice.*, "vkDestroySwapchainKHR"));
    device_data.get_swapchain_images = @ptrCast(next_gdpa(pDevice.*, "vkGetSwapchainImagesKHR"));

    // Load rendering functions
    device_data.create_image_view = @ptrCast(next_gdpa(pDevice.*, "vkCreateImageView"));
    device_data.destroy_image_view = @ptrCast(next_gdpa(pDevice.*, "vkDestroyImageView"));
    device_data.create_render_pass = @ptrCast(next_gdpa(pDevice.*, "vkCreateRenderPass"));
    device_data.destroy_render_pass = @ptrCast(next_gdpa(pDevice.*, "vkDestroyRenderPass"));
    device_data.create_framebuffer = @ptrCast(next_gdpa(pDevice.*, "vkCreateFramebuffer"));
    device_data.destroy_framebuffer = @ptrCast(next_gdpa(pDevice.*, "vkDestroyFramebuffer"));
    device_data.create_command_pool = @ptrCast(next_gdpa(pDevice.*, "vkCreateCommandPool"));
    device_data.destroy_command_pool = @ptrCast(next_gdpa(pDevice.*, "vkDestroyCommandPool"));
    device_data.allocate_command_buffers = @ptrCast(next_gdpa(pDevice.*, "vkAllocateCommandBuffers"));
    device_data.free_command_buffers = @ptrCast(next_gdpa(pDevice.*, "vkFreeCommandBuffers"));
    device_data.begin_command_buffer = @ptrCast(next_gdpa(pDevice.*, "vkBeginCommandBuffer"));
    device_data.end_command_buffer = @ptrCast(next_gdpa(pDevice.*, "vkEndCommandBuffer"));
    device_data.reset_command_buffer = @ptrCast(next_gdpa(pDevice.*, "vkResetCommandBuffer"));
    device_data.cmd_begin_render_pass = @ptrCast(next_gdpa(pDevice.*, "vkCmdBeginRenderPass"));
    device_data.cmd_end_render_pass = @ptrCast(next_gdpa(pDevice.*, "vkCmdEndRenderPass"));
    device_data.cmd_bind_pipeline = @ptrCast(next_gdpa(pDevice.*, "vkCmdBindPipeline"));
    device_data.cmd_set_viewport = @ptrCast(next_gdpa(pDevice.*, "vkCmdSetViewport"));
    device_data.cmd_set_scissor = @ptrCast(next_gdpa(pDevice.*, "vkCmdSetScissor"));
    device_data.cmd_draw = @ptrCast(next_gdpa(pDevice.*, "vkCmdDraw"));
    device_data.cmd_push_constants = @ptrCast(next_gdpa(pDevice.*, "vkCmdPushConstants"));
    device_data.queue_submit = @ptrCast(next_gdpa(pDevice.*, "vkQueueSubmit"));
    device_data.queue_wait_idle = @ptrCast(next_gdpa(pDevice.*, "vkQueueWaitIdle"));
    device_data.device_wait_idle = @ptrCast(next_gdpa(pDevice.*, "vkDeviceWaitIdle"));
    device_data.create_shader_module = @ptrCast(next_gdpa(pDevice.*, "vkCreateShaderModule"));
    device_data.destroy_shader_module = @ptrCast(next_gdpa(pDevice.*, "vkDestroyShaderModule"));
    device_data.create_pipeline_layout = @ptrCast(next_gdpa(pDevice.*, "vkCreatePipelineLayout"));
    device_data.destroy_pipeline_layout = @ptrCast(next_gdpa(pDevice.*, "vkDestroyPipelineLayout"));
    device_data.create_graphics_pipelines = @ptrCast(next_gdpa(pDevice.*, "vkCreateGraphicsPipelines"));
    device_data.destroy_pipeline = @ptrCast(next_gdpa(pDevice.*, "vkDestroyPipeline"));
    device_data.get_device_queue = @ptrCast(next_gdpa(pDevice.*, "vkGetDeviceQueue"));

    debugLog("Device created, loaded {} rendering functions", .{@as(u32, if (device_data.create_swapchain != null) 1 else 0) + @as(u32, if (device_data.create_render_pass != null) 1 else 0)});

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

/// Record overlay rendering commands for a frame
fn recordOverlayCommands(data: *DeviceData, image_index: u32) bool {
    const sd = &data.swapchain_data;
    if (!sd.initialized or image_index >= sd.image_count) return false;

    const cmd = sd.command_buffers[image_index] orelse return false;

    // Reset and begin command buffer
    if (data.reset_command_buffer) |reset| {
        if (reset(cmd, 0) != .VK_SUCCESS) return false;
    }

    const begin_info = VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };

    if (data.begin_command_buffer) |begin| {
        if (begin(cmd, &begin_info) != .VK_SUCCESS) return false;
    } else return false;

    // Begin render pass
    const render_pass_info = VkRenderPassBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = sd.render_pass,
        .framebuffer = sd.framebuffers[image_index],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = sd.extent,
        },
        .clearValueCount = 0, // Don't clear - we're using LOAD_OP_LOAD
        .pClearValues = null,
    };

    if (data.cmd_begin_render_pass) |begin_rp| {
        begin_rp(cmd, &render_pass_info, .VK_SUBPASS_CONTENTS_INLINE);
    } else return false;

    // Bind pipeline
    if (data.cmd_bind_pipeline) |bind| {
        bind(cmd, .VK_PIPELINE_BIND_POINT_GRAPHICS, sd.pipeline);
    }

    // Set viewport and scissor
    const viewport = VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(sd.extent.width),
        .height = @floatFromInt(sd.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = sd.extent,
    };

    if (data.cmd_set_viewport) |set_vp| {
        set_vp(cmd, 0, 1, @ptrCast(&viewport));
    }
    if (data.cmd_set_scissor) |set_sc| {
        set_sc(cmd, 0, 1, @ptrCast(&scissor));
    }

    // Push constants for a solid colored rectangle
    // Draw HUD background rectangle in top-left
    const push_constants = OverlayPushConstants{
        .color = .{ 0.1, 0.1, 0.1, 0.85 }, // Dark semi-transparent background
    };

    if (data.cmd_push_constants) |push| {
        push(cmd, sd.pipeline_layout, @intFromEnum(VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT), 0, @sizeOf(OverlayPushConstants), @ptrCast(&push_constants));
    }

    // Draw fullscreen triangle (shader will clip to overlay area)
    if (data.cmd_draw) |draw| {
        draw(cmd, 3, 1, 0, 0);
    }

    // End render pass
    if (data.cmd_end_render_pass) |end_rp| {
        end_rp(cmd);
    }

    // End command buffer
    if (data.end_command_buffer) |end| {
        if (end(cmd) != .VK_SUCCESS) return false;
    } else return false;

    return true;
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

    // Find device data and render overlay
    var it = device_map.iterator();
    while (it.next()) |entry| {
        const data = entry.value_ptr.*;

        // Render overlay if initialized
        if (data.swapchain_data.initialized) {
            // Get the image index from present info
            if (pPresentInfo.pImageIndices) |indices| {
                const image_index = indices[0];

                // Record overlay commands
                if (recordOverlayCommands(data, image_index)) {
                    // Submit overlay commands before present
                    const cmd = data.swapchain_data.command_buffers[image_index];
                    const wait_stage: VkPipelineStageFlags = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

                    const submit_info = VkSubmitInfo{
                        .sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
                        .pNext = null,
                        .waitSemaphoreCount = 0,
                        .pWaitSemaphores = null,
                        .pWaitDstStageMask = @ptrCast(&wait_stage),
                        .commandBufferCount = 1,
                        .pCommandBuffers = @ptrCast(&cmd),
                        .signalSemaphoreCount = 0,
                        .pSignalSemaphores = null,
                    };

                    if (data.queue_submit) |submit| {
                        const submit_result = submit(queue, 1, @ptrCast(&submit_info), 0);
                        if (submit_result != .VK_SUCCESS) {
                            debugLog("Failed to submit overlay commands: {}", .{@intFromEnum(submit_result)});
                        }
                    }

                    // Wait for overlay to finish
                    if (data.queue_wait_idle) |wait_idle| {
                        _ = wait_idle(queue);
                    }
                }
            }
        }

        // Call original present
        if (data.queue_present) |present_fn| {
            return present_fn(queue, pPresentInfo);
        }
    }

    return .VK_ERROR_DEVICE_LOST;
}

// ============================================================================
// Swapchain Hooks and Rendering Infrastructure
// ============================================================================

// Vertex shader: Fullscreen triangle (no vertex buffer needed)
// Compiled from shaders/overlay.vert with glslangValidator
const vertex_shader_spv = [_]u32{
    0x07230203, 0x00010000, 0x0008000b, 0x0000002b, 0x00000000, 0x00020011, 0x00000001, 0x0006000b,
    0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001,
    0x0008000f, 0x00000000, 0x00000004, 0x6e69616d, 0x00000000, 0x00000009, 0x0000000c, 0x0000001d,
    0x00030003, 0x00000002, 0x000001c2, 0x00040005, 0x00000004, 0x6e69616d, 0x00000000, 0x00040005,
    0x00000009, 0x5574756f, 0x00000056, 0x00060005, 0x0000000c, 0x565f6c67, 0x65747265, 0x646e4978,
    0x00007865, 0x00060005, 0x0000001b, 0x505f6c67, 0x65567265, 0x78657472, 0x00000000, 0x00060006,
    0x0000001b, 0x00000000, 0x505f6c67, 0x7469736f, 0x006e6f69, 0x00070006, 0x0000001b, 0x00000001,
    0x505f6c67, 0x746e696f, 0x657a6953, 0x00000000, 0x00070006, 0x0000001b, 0x00000002, 0x435f6c67,
    0x4470696c, 0x61747369, 0x0065636e, 0x00070006, 0x0000001b, 0x00000003, 0x435f6c67, 0x446c6c75,
    0x61747369, 0x0065636e, 0x00030005, 0x0000001d, 0x00000000, 0x00040047, 0x00000009, 0x0000001e,
    0x00000000, 0x00040047, 0x0000000c, 0x0000000b, 0x0000002a, 0x00030047, 0x0000001b, 0x00000002,
    0x00050048, 0x0000001b, 0x00000000, 0x0000000b, 0x00000000, 0x00050048, 0x0000001b, 0x00000001,
    0x0000000b, 0x00000001, 0x00050048, 0x0000001b, 0x00000002, 0x0000000b, 0x00000003, 0x00050048,
    0x0000001b, 0x00000003, 0x0000000b, 0x00000004, 0x00020013, 0x00000002, 0x00030021, 0x00000003,
    0x00000002, 0x00030016, 0x00000006, 0x00000020, 0x00040017, 0x00000007, 0x00000006, 0x00000002,
    0x00040020, 0x00000008, 0x00000003, 0x00000007, 0x0004003b, 0x00000008, 0x00000009, 0x00000003,
    0x00040015, 0x0000000a, 0x00000020, 0x00000001, 0x00040020, 0x0000000b, 0x00000001, 0x0000000a,
    0x0004003b, 0x0000000b, 0x0000000c, 0x00000001, 0x0004002b, 0x0000000a, 0x0000000e, 0x00000001,
    0x0004002b, 0x0000000a, 0x00000010, 0x00000002, 0x00040017, 0x00000017, 0x00000006, 0x00000004,
    0x00040015, 0x00000018, 0x00000020, 0x00000000, 0x0004002b, 0x00000018, 0x00000019, 0x00000001,
    0x0004001c, 0x0000001a, 0x00000006, 0x00000019, 0x0006001e, 0x0000001b, 0x00000017, 0x00000006,
    0x0000001a, 0x0000001a, 0x00040020, 0x0000001c, 0x00000003, 0x0000001b, 0x0004003b, 0x0000001c,
    0x0000001d, 0x00000003, 0x0004002b, 0x0000000a, 0x0000001e, 0x00000000, 0x0004002b, 0x00000006,
    0x00000020, 0x40000000, 0x0004002b, 0x00000006, 0x00000022, 0x3f800000, 0x0004002b, 0x00000006,
    0x00000025, 0x00000000, 0x00040020, 0x00000029, 0x00000003, 0x00000017, 0x00050036, 0x00000002,
    0x00000004, 0x00000000, 0x00000003, 0x000200f8, 0x00000005, 0x0004003d, 0x0000000a, 0x0000000d,
    0x0000000c, 0x000500c4, 0x0000000a, 0x0000000f, 0x0000000d, 0x0000000e, 0x000500c7, 0x0000000a,
    0x00000011, 0x0000000f, 0x00000010, 0x0004006f, 0x00000006, 0x00000012, 0x00000011, 0x0004003d,
    0x0000000a, 0x00000013, 0x0000000c, 0x000500c7, 0x0000000a, 0x00000014, 0x00000013, 0x00000010,
    0x0004006f, 0x00000006, 0x00000015, 0x00000014, 0x00050050, 0x00000007, 0x00000016, 0x00000012,
    0x00000015, 0x0003003e, 0x00000009, 0x00000016, 0x0004003d, 0x00000007, 0x0000001f, 0x00000009,
    0x0005008e, 0x00000007, 0x00000021, 0x0000001f, 0x00000020, 0x00050050, 0x00000007, 0x00000023,
    0x00000022, 0x00000022, 0x00050083, 0x00000007, 0x00000024, 0x00000021, 0x00000023, 0x00050051,
    0x00000006, 0x00000026, 0x00000024, 0x00000000, 0x00050051, 0x00000006, 0x00000027, 0x00000024,
    0x00000001, 0x00070050, 0x00000017, 0x00000028, 0x00000026, 0x00000027, 0x00000025, 0x00000022,
    0x00050041, 0x00000029, 0x0000002a, 0x0000001d, 0x0000001e, 0x0003003e, 0x0000002a, 0x00000028,
    0x000100fd, 0x00010038,
};

// Fragment shader: Solid color from push constants
// Compiled from shaders/overlay.frag with glslangValidator
const fragment_shader_spv = [_]u32{
    0x07230203, 0x00010000, 0x0008000b, 0x00000015, 0x00000000, 0x00020011, 0x00000001, 0x0006000b,
    0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001,
    0x0007000f, 0x00000004, 0x00000004, 0x6e69616d, 0x00000000, 0x00000009, 0x00000014, 0x00030010,
    0x00000004, 0x00000007, 0x00030003, 0x00000002, 0x000001c2, 0x00040005, 0x00000004, 0x6e69616d,
    0x00000000, 0x00050005, 0x00000009, 0x4374756f, 0x726f6c6f, 0x00000000, 0x00060005, 0x0000000a,
    0x68737550, 0x736e6f43, 0x746e6174, 0x00000073, 0x00050006, 0x0000000a, 0x00000000, 0x6f6c6f63,
    0x00000072, 0x00030005, 0x0000000c, 0x00006370, 0x00040005, 0x00000014, 0x56556e69, 0x00000000,
    0x00040047, 0x00000009, 0x0000001e, 0x00000000, 0x00030047, 0x0000000a, 0x00000002, 0x00050048,
    0x0000000a, 0x00000000, 0x00000023, 0x00000000, 0x00040047, 0x00000014, 0x0000001e, 0x00000000,
    0x00020013, 0x00000002, 0x00030021, 0x00000003, 0x00000002, 0x00030016, 0x00000006, 0x00000020,
    0x00040017, 0x00000007, 0x00000006, 0x00000004, 0x00040020, 0x00000008, 0x00000003, 0x00000007,
    0x0004003b, 0x00000008, 0x00000009, 0x00000003, 0x0003001e, 0x0000000a, 0x00000007, 0x00040020,
    0x0000000b, 0x00000009, 0x0000000a, 0x0004003b, 0x0000000b, 0x0000000c, 0x00000009, 0x00040015,
    0x0000000d, 0x00000020, 0x00000001, 0x0004002b, 0x0000000d, 0x0000000e, 0x00000000, 0x00040020,
    0x0000000f, 0x00000009, 0x00000007, 0x00040017, 0x00000012, 0x00000006, 0x00000002, 0x00040020,
    0x00000013, 0x00000001, 0x00000012, 0x0004003b, 0x00000013, 0x00000014, 0x00000001, 0x00050036,
    0x00000002, 0x00000004, 0x00000000, 0x00000003, 0x000200f8, 0x00000005, 0x00050041, 0x0000000f,
    0x00000010, 0x0000000c, 0x0000000e, 0x0004003d, 0x00000007, 0x00000011, 0x00000010, 0x0003003e,
    0x00000009, 0x00000011, 0x000100fd, 0x00010038,
};

// Push constants for overlay rendering (just color - 16 bytes)
const OverlayPushConstants = extern struct {
    color: [4]f32, // RGBA color
};

/// Create render pass for overlay (preserves game content)
fn createOverlayRenderPass(data: *DeviceData) bool {
    if (data.create_render_pass == null) return false;

    const color_attachment = VkAttachmentDescription{
        .flags = 0,
        .format = data.swapchain_data.format,
        .samples = .VK_SAMPLE_COUNT_1_BIT,
        .loadOp = .VK_ATTACHMENT_LOAD_OP_LOAD, // Preserve game content!
        .storeOp = .VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = .VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .finalLayout = .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = VkAttachmentReference{
        .attachment = 0,
        .layout = .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = .VK_PIPELINE_BIND_POINT_GRAPHICS,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .colorAttachmentCount = 1,
        .pColorAttachments = @ptrCast(&color_attachment_ref),
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    const dependency = VkSubpassDependency{
        .srcSubpass = 0xFFFFFFFF, // VK_SUBPASS_EXTERNAL
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT,
    };

    const render_pass_info = VkRenderPassCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = @ptrCast(&color_attachment),
        .subpassCount = 1,
        .pSubpasses = @ptrCast(&subpass),
        .dependencyCount = 1,
        .pDependencies = @ptrCast(&dependency),
    };

    const result = data.create_render_pass.?(data.device, &render_pass_info, null, &data.swapchain_data.render_pass);
    if (result != .VK_SUCCESS) {
        debugLog("Failed to create render pass: {}", .{@intFromEnum(result)});
        return false;
    }

    debugLog("Created render pass", .{});
    return true;
}

/// Create image views for swapchain images
fn createImageViews(data: *DeviceData) bool {
    if (data.create_image_view == null) return false;

    for (0..data.swapchain_data.image_count) |i| {
        const view_info = VkImageViewCreateInfo{
            .sType = .VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = data.swapchain_data.images[i],
            .viewType = .VK_IMAGE_VIEW_TYPE_2D,
            .format = data.swapchain_data.format,
            .components = .{
                .r = .VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = .VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = .VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = .VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const result = data.create_image_view.?(data.device, &view_info, null, &data.swapchain_data.image_views[i]);
        if (result != .VK_SUCCESS) {
            debugLog("Failed to create image view {}: {}", .{ i, @intFromEnum(result) });
            return false;
        }
    }

    debugLog("Created {} image views", .{data.swapchain_data.image_count});
    return true;
}

/// Create framebuffers for each swapchain image
fn createFramebuffers(data: *DeviceData) bool {
    if (data.create_framebuffer == null) return false;

    for (0..data.swapchain_data.image_count) |i| {
        const attachments = [_]VkImageView{data.swapchain_data.image_views[i]};

        const fb_info = VkFramebufferCreateInfo{
            .sType = .VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = data.swapchain_data.render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = data.swapchain_data.extent.width,
            .height = data.swapchain_data.extent.height,
            .layers = 1,
        };

        const result = data.create_framebuffer.?(data.device, &fb_info, null, &data.swapchain_data.framebuffers[i]);
        if (result != .VK_SUCCESS) {
            debugLog("Failed to create framebuffer {}: {}", .{ i, @intFromEnum(result) });
            return false;
        }
    }

    debugLog("Created {} framebuffers", .{data.swapchain_data.image_count});
    return true;
}

/// Create command pool and allocate command buffers
fn createCommandBuffers(data: *DeviceData) bool {
    if (data.create_command_pool == null or data.allocate_command_buffers == null) return false;

    // Create command pool
    const pool_info = VkCommandPoolCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = data.swapchain_data.graphics_queue_family,
    };

    var result = data.create_command_pool.?(data.device, &pool_info, null, &data.swapchain_data.command_pool);
    if (result != .VK_SUCCESS) {
        debugLog("Failed to create command pool: {}", .{@intFromEnum(result)});
        return false;
    }

    // Allocate command buffers
    const alloc_info = VkCommandBufferAllocateInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = data.swapchain_data.command_pool,
        .level = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = data.swapchain_data.image_count,
    };

    result = data.allocate_command_buffers.?(data.device, &alloc_info, &data.swapchain_data.command_buffers);
    if (result != .VK_SUCCESS) {
        debugLog("Failed to allocate command buffers: {}", .{@intFromEnum(result)});
        return false;
    }

    debugLog("Created command pool and {} command buffers", .{data.swapchain_data.image_count});
    return true;
}

/// Create shader module from SPIR-V bytecode
fn createShaderModule(data: *DeviceData, code: []const u32) ?VkShaderModule {
    if (data.create_shader_module == null) return null;

    const create_info = VkShaderModuleCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = code.len * @sizeOf(u32),
        .pCode = code.ptr,
    };

    var module: VkShaderModule = 0;
    const result = data.create_shader_module.?(data.device, &create_info, null, &module);
    if (result != .VK_SUCCESS) {
        debugLog("Failed to create shader module: {}", .{@intFromEnum(result)});
        return null;
    }

    return module;
}

/// Create graphics pipeline for overlay rendering
fn createOverlayPipeline(data: *DeviceData) bool {
    if (data.create_pipeline_layout == null or data.create_graphics_pipelines == null) return false;

    // Create shader modules
    const vert_module = createShaderModule(data, &vertex_shader_spv) orelse return false;
    const frag_module = createShaderModule(data, &fragment_shader_spv) orelse {
        if (data.destroy_shader_module) |destroy| destroy(data.device, vert_module, null);
        return false;
    };

    defer {
        if (data.destroy_shader_module) |destroy| {
            destroy(data.device, vert_module, null);
            destroy(data.device, frag_module, null);
        }
    }

    // Shader stages
    const shader_stages = [_]VkPipelineShaderStageCreateInfo{
        .{
            .sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = .VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        .{
            .sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = .VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
    };

    // Vertex input (empty - fullscreen triangle)
    const vertex_input_info = VkPipelineVertexInputStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    // Input assembly
    const input_assembly = VkPipelineInputAssemblyStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = 0,
    };

    // Viewport state (dynamic)
    const viewport_state = VkPipelineViewportStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null, // Dynamic
        .scissorCount = 1,
        .pScissors = null, // Dynamic
    };

    // Rasterization
    const rasterizer = VkPipelineRasterizationStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = 0,
        .rasterizerDiscardEnable = 0,
        .polygonMode = .VK_POLYGON_MODE_FILL,
        .cullMode = VK_CULL_MODE_NONE,
        .frontFace = .VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = 0,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    // Multisampling
    const multisampling = VkPipelineMultisampleStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = .VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = 0,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = 0,
        .alphaToOneEnable = 0,
    };

    // Color blending (alpha blending for overlay)
    const color_blend_attachment = VkPipelineColorBlendAttachmentState{
        .blendEnable = 1,
        .srcColorBlendFactor = .VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = .VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = .VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = .VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = .VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = .VK_BLEND_OP_ADD,
        .colorWriteMask = VK_COLOR_COMPONENT_ALL,
    };

    const color_blending = VkPipelineColorBlendStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = 0,
        .logicOp = .VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = @ptrCast(&color_blend_attachment),
        .blendConstants = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    // Dynamic state
    const dynamic_states = [_]VkDynamicState{ .VK_DYNAMIC_STATE_VIEWPORT, .VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state = VkPipelineDynamicStateCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = 2,
        .pDynamicStates = &dynamic_states,
    };

    // Pipeline layout (with push constants)
    const push_constant_range = VkPushConstantRange{
        .stageFlags = @intFromEnum(VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT),
        .offset = 0,
        .size = @sizeOf(OverlayPushConstants),
    };

    const pipeline_layout_info = VkPipelineLayoutCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = @ptrCast(&push_constant_range),
    };

    var result = data.create_pipeline_layout.?(data.device, &pipeline_layout_info, null, &data.swapchain_data.pipeline_layout);
    if (result != .VK_SUCCESS) {
        debugLog("Failed to create pipeline layout: {}", .{@intFromEnum(result)});
        return false;
    }

    // Graphics pipeline
    const pipeline_info = VkGraphicsPipelineCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = data.swapchain_data.pipeline_layout,
        .renderPass = data.swapchain_data.render_pass,
        .subpass = 0,
        .basePipelineHandle = 0,
        .basePipelineIndex = -1,
    };

    result = data.create_graphics_pipelines.?(data.device, 0, 1, @ptrCast(&pipeline_info), null, @ptrCast(&data.swapchain_data.pipeline));
    if (result != .VK_SUCCESS) {
        debugLog("Failed to create graphics pipeline: {}", .{@intFromEnum(result)});
        return false;
    }

    debugLog("Created graphics pipeline", .{});
    return true;
}

/// Initialize overlay rendering for a swapchain
fn initOverlayRendering(data: *DeviceData) bool {
    if (data.swapchain_data.initialized) return true;

    // Get graphics queue (use queue family 0 for simplicity)
    if (data.get_device_queue) |get_queue| {
        get_queue(data.device, 0, 0, &data.swapchain_data.graphics_queue);
        data.swapchain_data.graphics_queue_family = 0;
    }

    if (!createOverlayRenderPass(data)) return false;
    if (!createImageViews(data)) return false;
    if (!createFramebuffers(data)) return false;
    if (!createCommandBuffers(data)) return false;
    if (!createOverlayPipeline(data)) return false;

    data.swapchain_data.initialized = true;
    debugLog("Overlay rendering initialized for {}x{}", .{ data.swapchain_data.extent.width, data.swapchain_data.extent.height });
    return true;
}

/// Cleanup overlay resources
fn cleanupOverlayRendering(data: *DeviceData) void {
    if (!data.swapchain_data.initialized) return;

    // Wait for device to be idle
    if (data.device_wait_idle) |wait| {
        _ = wait(data.device);
    }

    // Destroy pipeline
    if (data.destroy_pipeline) |destroy| {
        if (data.swapchain_data.pipeline != 0) {
            destroy(data.device, data.swapchain_data.pipeline, null);
        }
    }

    // Destroy pipeline layout
    if (data.destroy_pipeline_layout) |destroy| {
        if (data.swapchain_data.pipeline_layout != 0) {
            destroy(data.device, data.swapchain_data.pipeline_layout, null);
        }
    }

    // Free command buffers and destroy pool
    if (data.destroy_command_pool) |destroy| {
        if (data.swapchain_data.command_pool != 0) {
            destroy(data.device, data.swapchain_data.command_pool, null);
        }
    }

    // Destroy framebuffers
    if (data.destroy_framebuffer) |destroy| {
        for (0..data.swapchain_data.image_count) |i| {
            if (data.swapchain_data.framebuffers[i] != 0) {
                destroy(data.device, data.swapchain_data.framebuffers[i], null);
            }
        }
    }

    // Destroy image views
    if (data.destroy_image_view) |destroy| {
        for (0..data.swapchain_data.image_count) |i| {
            if (data.swapchain_data.image_views[i] != 0) {
                destroy(data.device, data.swapchain_data.image_views[i], null);
            }
        }
    }

    // Destroy render pass
    if (data.destroy_render_pass) |destroy| {
        if (data.swapchain_data.render_pass != 0) {
            destroy(data.device, data.swapchain_data.render_pass, null);
        }
    }

    data.swapchain_data = .{};
    debugLog("Overlay rendering cleaned up", .{});
}

/// Hook: vkCreateSwapchainKHR
export fn nvhud_CreateSwapchainKHR(
    device: VkDevice,
    pCreateInfo: *const VkSwapchainCreateInfoKHR,
    pAllocator: ?*const anyopaque,
    pSwapchain: *VkSwapchainKHR,
) callconv(.c) VkResult {
    const key = @intFromPtr(device);
    const data = device_map.get(key) orelse return .VK_ERROR_DEVICE_LOST;

    // Cleanup old swapchain resources if any
    cleanupOverlayRendering(data);

    // Create the swapchain through the next layer
    const create_fn = data.create_swapchain orelse return .VK_ERROR_INITIALIZATION_FAILED;
    const result = create_fn(device, pCreateInfo, pAllocator, pSwapchain);
    if (result != .VK_SUCCESS) return result;

    // Store swapchain info
    data.swapchain_data.swapchain = pSwapchain.*;
    data.swapchain_data.format = pCreateInfo.imageFormat;
    data.swapchain_data.extent = pCreateInfo.imageExtent;

    debugLog("Swapchain created: {}x{} format={}", .{
        pCreateInfo.imageExtent.width,
        pCreateInfo.imageExtent.height,
        @intFromEnum(pCreateInfo.imageFormat),
    });

    // Get swapchain images
    if (data.get_swapchain_images) |get_images| {
        var image_count: u32 = 0;
        _ = get_images(device, pSwapchain.*, &image_count, null);
        if (image_count > MAX_SWAPCHAIN_IMAGES) image_count = MAX_SWAPCHAIN_IMAGES;
        _ = get_images(device, pSwapchain.*, &image_count, &data.swapchain_data.images);
        data.swapchain_data.image_count = image_count;
        debugLog("Got {} swapchain images", .{image_count});
    }

    // Initialize overlay rendering
    _ = initOverlayRendering(data);

    return .VK_SUCCESS;
}

/// Hook: vkDestroySwapchainKHR
export fn nvhud_DestroySwapchainKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pAllocator: ?*const anyopaque,
) callconv(.c) void {
    const key = @intFromPtr(device);
    if (device_map.get(key)) |data| {
        // Cleanup our overlay resources
        cleanupOverlayRendering(data);

        // Destroy the swapchain through next layer
        if (data.destroy_swapchain) |destroy| {
            destroy(device, swapchain, pAllocator);
        }
    }
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

    // Intercept swapchain functions
    if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) return @ptrCast(&nvhud_CreateSwapchainKHR);
    if (std.mem.eql(u8, name, "vkDestroySwapchainKHR")) return @ptrCast(&nvhud_DestroySwapchainKHR);

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
