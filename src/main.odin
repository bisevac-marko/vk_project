package main

import        "core:fmt"
import        "core:c"
import        "vendor:glfw"
import vk     "vendor:vulkan"
import        "core:mem"
import str    "core:strings"
import        "core:runtime"
import        "core:dynlib"
import        "core:os"
import        "core:reflect"
import misc   "core:math/bits"
import la     "core:math/linalg"
import math   "core:math"

Vertex_Description :: struct {
    bindings: [dynamic]vk.VertexInputBindingDescription,
    attributes: [dynamic]vk.VertexInputAttributeDescription,
    flags: vk.PipelineVertexInputStateCreateFlags,
}

GPU_Device :: struct {
    device: vk.Device,
    physical_device: vk.PhysicalDevice,
}

Buffer :: struct {
    memory: vk.DeviceMemory,
    buffer: vk.Buffer,
}

Image :: struct {
    memory: vk.DeviceMemory,
    image: vk.Image,
}

Vulkan_State :: struct {
    
    instance: vk.Instance,
    
    gpu: GPU_Device,
    
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    
    surface: vk.SurfaceKHR,
    
    swap_chain: vk.SwapchainKHR,
    swap_chain_images: [dynamic]vk.Image,
    window_extent: vk.Extent2D, 
    swap_chain_format: vk.Format,
    swap_chain_image_views: [dynamic]vk.ImageView,
    
    vertex_module: vk.ShaderModule, 
    fragment_module: vk.ShaderModule, 
    
    pipeline_layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    graphics_pipeline: vk.Pipeline,
    
    swap_chain_framebuffers: [dynamic]vk.Framebuffer,
    command_pool: vk.CommandPool,
    command_buffers: [dynamic]vk.CommandBuffer,
    
    framebuffer_resized: bool,

    present_semaphore: vk.Semaphore,
    render_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
    
    debug_messenger: vk.DebugUtilsMessengerEXT,

    depth_image: Image,
    depth_image_view: vk.ImageView,
    depth_format: vk.Format,
    
    triangle_mesh: Mesh,
    some_mesh: Mesh,
}

Swap_Chain_Support_Info :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: [dynamic]vk.SurfaceFormatKHR,
    present_modes: [dynamic]vk.PresentModeKHR,
}

Queue_Family_Index :: struct {
    index: u32,
    valid: b32,
}

Queue_Family_Indicies :: struct {
    graphics_family: Queue_Family_Index,
    present_family: Queue_Family_Index,
}

device_extensions := [?]cstring{
    "VK_KHR_swapchain",
};


debug_message_callback:: proc "system" (message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, pUserData: rawptr) -> b32 {
    
    
    context = runtime.default_context();
    fmt.printf("[Vulkan] {}.\n", callback_data.pMessage);
    return false;
}

populate_debug_messenger_create_info:: proc (create_info: ^vk.DebugUtilsMessengerCreateInfoEXT) {
    
    create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    create_info.messageSeverity = {.WARNING, .ERROR};
    create_info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE};
    create_info.pfnUserCallback = debug_message_callback;
    create_info.pUserData = nil; // Optional
}

setup_debug_messenger:: proc(debug_messenger: ^vk.DebugUtilsMessengerEXT, instance: vk.Instance) {
    create_info: vk.DebugUtilsMessengerCreateInfoEXT;
    populate_debug_messenger_create_info(&create_info);
    
    if vk.CreateDebugUtilsMessengerEXT == nil {
        vk.CreateDebugUtilsMessengerEXT = cast(vk.ProcCreateDebugUtilsMessengerEXT)vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    }
    assert(vk.CreateDebugUtilsMessengerEXT != nil);
    
    result := vk.CreateDebugUtilsMessengerEXT(instance, &create_info, nil, debug_messenger);
    assert(result == .SUCCESS);
}

find_queue_families:: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> Queue_Family_Indicies {
    result: Queue_Family_Indicies;
    queue_family_count: u32 = 0;
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil);
    
    queue_families := make([dynamic]vk.QueueFamilyProperties, 
                                            queue_family_count,
                                            queue_family_count, 
                                            context.temp_allocator);
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, &queue_families[0]);
    
    for i: u32 = 0; i < queue_family_count; i += 1 {
        if vk.QueueFlag.GRAPHICS in queue_families[i].queueFlags {
            result.graphics_family.index = i;
            result.graphics_family.valid = true;
        }
        
        present_support: b32 = false;
        vk.GetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &present_support);
        
        if present_support == true {
            result.present_family.index = i;
            result.present_family.valid = true;
        }
    }
    
    return result;
}

check_device_extensions:: proc(device: vk.PhysicalDevice) -> b32{
    result: b32 = true;
    
    extension_count: u32;
    vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil);
    available_extensions := make([dynamic]vk.ExtensionProperties, 
                                                   extension_count, 
                                                   extension_count,
                                                   context.temp_allocator);
    vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, &available_extensions[0]);
    
    for i: u32 = 0; i < len(device_extensions); i += 1 {
        
        requested := string(device_extensions[i]);
        length := len(requested);
        has_extension: b32;
        for j : u32 = 0; j < extension_count; j += 1 {
            available := str.string_from_nul_terminated_ptr(&available_extensions[j].extensionName[0], length);
            if str.compare(requested, available) == 0 {
                has_extension = true;
                break;
            }
            has_extension = false;
        }
        
        result = has_extension;
    }
    return result;
}

get_swap_chain_support_info:: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> Swap_Chain_Support_Info {
    result: Swap_Chain_Support_Info;
    format_count: u32;
    present_mode_count: u32;
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil);
    
    if format_count != 0 {
        result.formats = make([dynamic]vk.SurfaceFormatKHR, 
                                                format_count,
                                                format_count,
                                                context.temp_allocator);
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, &result.formats[0]);
    }
    
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, nil);
    
    if present_mode_count != 0 {
        result.present_modes = make([dynamic]vk.PresentModeKHR, 
                                                      present_mode_count,
                                                      present_mode_count,
                                                      context.temp_allocator);
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, &result.present_modes[0]);
    }
    
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &result.capabilities);
    
    return result;
}

create_shader_module:: proc(device: vk.Device, shader_code: []byte) -> vk.ShaderModule {
    
    shader_module: vk.ShaderModule;
    create_info := vk.ShaderModuleCreateInfo {
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(shader_code),
        pCode    = cast(^u32)&shader_code[0],
    };
    
    if vk.CreateShaderModule(device, &create_info, nil, &shader_module) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create shader module");
        assert(false);
    }
    return shader_module;
}

create_render_pass:: proc(vulkan_state: ^Vulkan_State) {
    
    color_attachment: vk.AttachmentDescription = {
        format  = vulkan_state.swap_chain_format,
        samples = {._1},
        loadOp =  .CLEAR,
        storeOp = .STORE,
        stencilLoadOp =  .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .PRESENT_SRC_KHR,
    };
    

    color_attachment_ref: vk.AttachmentReference = {
        attachment = 0,
        layout = .COLOR_ATTACHMENT_OPTIMAL,
    };

    
    dependency: vk.SubpassDependency = {
        srcSubpass = vk.SUBPASS_EXTERNAL,
        srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
        dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
        dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
    };
    

    depth_attachment: vk.AttachmentDescription = {
        format = vulkan_state.depth_format,
        samples = {._1},
        loadOp = .CLEAR,
        storeOp = .STORE,
        stencilLoadOp = .CLEAR,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };

    depth_attachment_ref: vk.AttachmentReference = {
        attachment = 1,
        layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    }


    subpass: vk.SubpassDescription = {
        pipelineBindPoint = .GRAPHICS,
        colorAttachmentCount = 1,
        pColorAttachments = &color_attachment_ref,
        pDepthStencilAttachment = &depth_attachment_ref,
    };
    
    attachments : []vk.AttachmentDescription = {color_attachment, depth_attachment};

    render_pass_info: vk.RenderPassCreateInfo = {
        sType = .RENDER_PASS_CREATE_INFO,
        attachmentCount = 2,
        pAttachments = &attachments[0],
        subpassCount = 1,
        pSubpasses = &subpass,
        dependencyCount = 1,
        pDependencies = &dependency,
    };
    
    if vk.CreateRenderPass(vulkan_state.gpu.device, &render_pass_info, nil, &vulkan_state.render_pass) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create render pass!");
    }
}

create_graphics_pipeline:: proc(vulkan_state: ^Vulkan_State) {
    // Vertex shader
    {
        vert_code, success := os.read_entire_file("vert.spv");
        
        if success {
            vulkan_state.vertex_module = create_shader_module(vulkan_state.gpu.device, vert_code);
        } else {
            fmt.println("[Vulkan] Failed to read shader file!");
        }
    }
    // Fragment shader
    {
        frag_code, success := os.read_entire_file("frag.spv");
        
        if success {
            vulkan_state.fragment_module = create_shader_module(vulkan_state.gpu.device, frag_code);
        } else {
            fmt.println("[Vulkan] Failed to read shader file!");
        }
    }
    
    vert_create_info: vk.PipelineShaderStageCreateInfo = {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.VERTEX},
        module = vulkan_state.vertex_module,
        pName = "main", // Entry point
        pSpecializationInfo = nil, // This field allow to specify values for shader constants
    };
    
    frag_create_info: vk.PipelineShaderStageCreateInfo = {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.FRAGMENT},
        module = vulkan_state.fragment_module,
        pName = "main", // Entry point
        pSpecializationInfo = nil, // This field allow to specify values for shader constants
    };
    
    vertex_desc := get_vertex_description();
    
    vertex_input_state_create_info: vk.PipelineVertexInputStateCreateInfo = {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        pVertexBindingDescriptions      = &vertex_desc.bindings[0], // Optional
        vertexBindingDescriptionCount   = u32(len(vertex_desc.bindings)),
        pVertexAttributeDescriptions    = &vertex_desc.attributes[0], // Optional
        vertexAttributeDescriptionCount = u32(len(vertex_desc.attributes)),
    };
    
    pipeline_input_asm_create_info: vk.PipelineInputAssemblyStateCreateInfo = {
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    };
    
    viewport: vk.Viewport = {
        x = 0.0,
        y = 0.0,
        width  = f32(vulkan_state.window_extent.width),
        height = f32(vulkan_state.window_extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    };
    
    scissor: vk.Rect2D = {
        offset = {0, 0},
        extent = vulkan_state.window_extent,
    };
    
    
    // It is possible to use multiple viewports and scissor rectangles on some graphics cards, 
    // so its members reference an array of them. Using multiple requires enabling
    // a GPU feature (see logical device creation).
    viewport_state_create_info: vk.PipelineViewportStateCreateInfo = {
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports = &viewport,
        scissorCount = 1,
        pScissors = &scissor,
    };
    
    rasterizer: vk.PipelineRasterizationStateCreateInfo = {
        sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable = false,
        rasterizerDiscardEnable = false,
        // Using any mode other than fill requires enabling a GPU feature.
        polygonMode = .FILL,
        lineWidth = 1.0,
        cullMode = {.BACK},
        frontFace = .CLOCKWISE,
        depthBiasEnable = false,
        depthBiasConstantFactor = 0.0, // Optional
        depthBiasClamp = 0.0, // Optional
        depthBiasSlopeFactor = 0.0, // Optional
    };
    
    multisampling: vk.PipelineMultisampleStateCreateInfo = {
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = {._1},
        minSampleShading = 1.0, // Optional
        pSampleMask = nil, // Optional
        alphaToCoverageEnable = false, // Optional
        alphaToOneEnable = false, // Optional
    };
    
    color_blend_attachement_state: vk.PipelineColorBlendAttachmentState = {
        colorWriteMask = {.R, .G, .B, .A},
        blendEnable = false,
        srcColorBlendFactor = .ONE, // Optional
        dstColorBlendFactor = .ZERO, // Optional
        colorBlendOp = .ADD, // Optional
        srcAlphaBlendFactor = .ONE, // Optional
        dstAlphaBlendFactor = .ZERO, // Optional
        alphaBlendOp = .ADD, // Optional
    };
    
    color_blend_state_create_info: vk.PipelineColorBlendStateCreateInfo = {
        sType             = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable     = false,
        logicOp           = .COPY,
        attachmentCount   = 1,
        pAttachments      = &color_blend_attachement_state,
        blendConstants    = {0, 0, 0, 0},
    };
    
    // Push constants
    push_constant: vk.PushConstantRange = {
        size       = size_of(Push_Constants),
        stageFlags = {.VERTEX},
    };

    // This struct is for passing dynamic information to shaders
    pipeline_layout_create_info: vk.PipelineLayoutCreateInfo = {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pSetLayouts            = nil, // Optional
        setLayoutCount         = 0, // Optional
        pPushConstantRanges    = &push_constant, // Optional
        pushConstantRangeCount = 1, // Optional
    };
    
    
    if vk.CreatePipelineLayout(vulkan_state.gpu.device, &pipeline_layout_create_info, nil, &vulkan_state.pipeline_layout) != .SUCCESS {
        
        fmt.println("[Vulkan] Failed to create pipeline layout!");
    }
    
    shader_stages := []vk.PipelineShaderStageCreateInfo {frag_create_info, vert_create_info};

    // Depth testing
    depth_stencil_info: vk.PipelineDepthStencilStateCreateInfo = {
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable = true,
        depthWriteEnable = true,
        depthCompareOp = .LESS_OR_EQUAL,
        depthBoundsTestEnable = false,
        minDepthBounds = 0.0, // Optional
        maxDepthBounds = 1.0, // Optional
        stencilTestEnable = false,
    }
    
    
    pipeline_create_info: vk.GraphicsPipelineCreateInfo = {
        sType                  = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount             = 2,
        pStages                = &shader_stages[0],
        pVertexInputState      = &vertex_input_state_create_info,
        pInputAssemblyState    = &pipeline_input_asm_create_info,
        pViewportState         = &viewport_state_create_info,
        pRasterizationState    = &rasterizer,
        pMultisampleState      = &multisampling,
        pDepthStencilState     = &depth_stencil_info, // Optional
        pColorBlendState       = &color_blend_state_create_info,
        pDynamicState          = nil, // Optional
        
        layout                 = vulkan_state.pipeline_layout,
        
        renderPass             = vulkan_state.render_pass,
        subpass                = 0,
        
        basePipelineHandle     = 0, // Optional
        basePipelineIndex      = -1, // Optional
    };
    
    if vk.CreateGraphicsPipelines(vulkan_state.gpu.device, 0, 1, &pipeline_create_info, nil, &vulkan_state.graphics_pipeline) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create graphics pipeline!");
        assert(false);
    }
}

create_framebuffers:: proc(using vulkan_state: ^Vulkan_State) {
    
    count:= len(swap_chain_images);
    swap_chain_framebuffers = make([dynamic]vk.Framebuffer, count, count);
    
    for  i := 0; i < count; i += 1 {
        
        attachments: []vk.ImageView = {
            swap_chain_image_views[i],
            depth_image_view,
        };
        
        framebuffer_info: vk.FramebufferCreateInfo = {
            sType           = .FRAMEBUFFER_CREATE_INFO,
            renderPass      = render_pass,
            attachmentCount = 2,
            pAttachments    = &attachments[0],
            width           = window_extent.width,
            height          = window_extent.height,
            layers          = 1,
        };
        
        if vk.CreateFramebuffer(gpu.device, &framebuffer_info, nil, &swap_chain_framebuffers[i]) != .SUCCESS {
            fmt.println("[Vulkan] Failed to create framebuffer!");
        }
    }
}

create_command_pool:: proc(vulkan_state: ^Vulkan_State) {
    
    queue_family_indices := find_queue_families(vulkan_state.gpu.physical_device, vulkan_state.surface);
    
    pool_info: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = queue_family_indices.graphics_family.index,
        flags = {.RESET_COMMAND_BUFFER}, // Optional
    };
    
    using vulkan_state;
    
    if vk.CreateCommandPool(gpu.device, &pool_info, nil, &command_pool) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create command pool!");
    }
}

create_command_buffers:: proc(vulkan_state: ^Vulkan_State) {
    
    framebuffer_count := len(vulkan_state.swap_chain_framebuffers);
    vulkan_state.command_buffers = make([dynamic]vk.CommandBuffer, framebuffer_count, framebuffer_count);
    
    alloc_info: vk.CommandBufferAllocateInfo = {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = vulkan_state.command_pool,
        level = .PRIMARY,
        commandBufferCount = u32(framebuffer_count),
    };
    
    if vk.AllocateCommandBuffers(vulkan_state.gpu.device, &alloc_info, &vulkan_state.command_buffers[0]) != .SUCCESS {
        fmt.println("[Vulkan] Failed to allocate command buffers!");
    }
    
}

create_sync_stuff:: proc(vulkan_state: ^Vulkan_State) {
    
    semaphore_create_info: vk.SemaphoreCreateInfo = {
        sType = .SEMAPHORE_CREATE_INFO,
    };
    
    fence_create_info: vk.FenceCreateInfo = {
        sType = .FENCE_CREATE_INFO,
        flags = {.SIGNALED},
    };
    using vulkan_state;
    /*
    image_available_semaphore = make([dynamic]vk.Semaphore, ,0 MAX_FRAMES_IN_FLIGHT);
    render_finished_semaphore = make([dynamic]vk.Semaphore, ,0 MAX_FRAMES_IN_FLIGHT);
    fences                    = make([dynamic]vk.Fence, ,0 MAX_FRAMES_IN_FLIGHT);
*/
    
    if (vk.CreateSemaphore(gpu.device, &semaphore_create_info, nil, &render_semaphore) != .SUCCESS ||
        vk.CreateSemaphore(gpu.device, &semaphore_create_info, nil, &present_semaphore) != .SUCCESS) {
        
        
        fmt.println("[Vulkan] Failed to create semaphores!");
    }
    
    if (vk.CreateFence(gpu.device, &fence_create_info, nil, &render_fence) != .SUCCESS) {
        
        fmt.println("[Vulkan] Failed to create fence!!");
    }
}

create_swapchain:: proc(using vulkan_state: ^Vulkan_State, window: glfw.WindowHandle) {
    // Creating swap chain
    {
        swap_chain_support_info := get_swap_chain_support_info(gpu.physical_device, surface);
        
        if (swap_chain_support_info.formats == nil ||
            swap_chain_support_info.present_modes == nil) {
            // Unsupported swapchain
            vk.DestroyDevice(gpu.device, nil);
            assert(false);
        }
        
        // Choose swap surface format
        chosen_format: vk.SurfaceFormatKHR;
        
        for fmt, index in swap_chain_support_info.formats {
            if (fmt.format == .B8G8R8A8_SRGB &&
                fmt.colorSpace == .COLORSPACE_SRGB_NONLINEAR) {
                chosen_format = swap_chain_support_info.formats[index];
                break;
            }
        }
        
        // Choose swap presentation mode
        chosen_present_mode: vk.PresentModeKHR = .FIFO;
        
        for mode, index in swap_chain_support_info.present_modes {
            if mode == .MAILBOX { 
                chosen_present_mode = .MAILBOX;
                break;
            }
        }
        
        // Choose width and height of vulkan surface and image_count
        extent: vk.Extent2D;
        image_count: u32;
        {
            using swap_chain_support_info;
            extent = capabilities.currentExtent;
            
            if extent.width != misc.U32_MAX {
                width, height := glfw.GetFramebufferSize(window);
                
                extent.width = u32(width);
                extent.height = u32(height);
                
                extent.width = clamp(extent.width, 
                                     capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
                extent.height = clamp(extent.height, 
                                      capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
            }
            
            image_count = capabilities.minImageCount + 1;
            
            if (capabilities.maxImageCount > 0 && 
                image_count > capabilities.maxImageCount) {
                image_count = capabilities.maxImageCount;
            }
            
        }
        
        create_info := vk.SwapchainCreateInfoKHR {
            sType = .SWAPCHAIN_CREATE_INFO_KHR,
            surface = surface,
            minImageCount = image_count,
            imageFormat = chosen_format.format,
            imageColorSpace = chosen_format.colorSpace,
            imageExtent = extent,
            imageArrayLayers = 1,
            imageUsage = {.COLOR_ATTACHMENT},
            preTransform = swap_chain_support_info.capabilities.currentTransform,
            compositeAlpha = {.OPAQUE},
            presentMode = chosen_present_mode,
            clipped = true,
            oldSwapchain = 0,
        };
        
        // vulkan_state fields
        window_extent = extent; 
        swap_chain_format = chosen_format.format;
        
        queue_family_indices := find_queue_families(gpu.physical_device, surface);
        
        
        if (queue_family_indices.present_family.index != 
            queue_family_indices.graphics_family.index) {
            
            indices: []u32 =  {
                queue_family_indices.graphics_family.index,
                queue_family_indices.present_family.index,
            };
            create_info.imageSharingMode = .CONCURRENT;
            create_info.queueFamilyIndexCount = 2;
            create_info.pQueueFamilyIndices = &indices[0];
            
        } else {
            
            create_info.imageSharingMode = .EXCLUSIVE;
            create_info.queueFamilyIndexCount = 0; // Optional
            create_info.pQueueFamilyIndices = nil; // Optional
        }
        
        if vk.CreateSwapchainKHR(gpu.device, &create_info, nil, &swap_chain) != .SUCCESS {
            fmt.println("[Vulkan] Failed to create swap chain.");
            assert(false);
        }
        
        the_image_count: u32;
        vk.GetSwapchainImagesKHR(gpu.device, swap_chain, &the_image_count, nil);
        swap_chain_images = make([dynamic]vk.Image, the_image_count, the_image_count);
        vk.GetSwapchainImagesKHR(gpu.device, swap_chain, &image_count, &swap_chain_images[0]);
    }
    // Creating image views
    {
        vulkan_state.swap_chain_image_views = make([dynamic]vk.ImageView, len(swap_chain_images), len(swap_chain_images));
        for image_idx := 0; image_idx < len(swap_chain_images); image_idx += 1 {
            create_info := vk.ImageViewCreateInfo {
                sType                 = .IMAGE_VIEW_CREATE_INFO,
                image                 = swap_chain_images[image_idx], 
                viewType              = .D2,
                format                = swap_chain_format,
                components            = {
                    r = .IDENTITY, 
                    g = .IDENTITY, 
                    b = .IDENTITY, 
                    a = .IDENTITY,
                },
                subresourceRange     = {
                    aspectMask     = {.COLOR}, 
                    baseMipLevel   = 0, 
                    levelCount     = 1, 
                    baseArrayLayer = 0, 
                    layerCount     = 1,
                },
            }
            
            if vk.CreateImageView(gpu.device, &create_info, nil, &swap_chain_image_views[image_idx]) != .SUCCESS {
                fmt.println("[Vulkan] Failed to create image views!");
            }
        }
    }
}

recreate_swap_chain:: proc(using vulkan_state: ^Vulkan_State, window: glfw.WindowHandle) {
    // Need to wait so that all the resources are not beign used before destroying/freeing.
    vk.DeviceWaitIdle(gpu.device);

    for framebuffer in swap_chain_framebuffers {
        vk.DestroyFramebuffer(gpu.device, framebuffer, nil);
    }

    vk.FreeCommandBuffers(gpu.device, command_pool, u32(len(command_buffers)), &command_buffers[0]);

    vk.DestroyPipeline(gpu.device, graphics_pipeline, nil);
    vk.DestroyPipelineLayout(gpu.device, pipeline_layout, nil);
    vk.DestroyRenderPass(gpu.device, render_pass, nil);

    for image_view in swap_chain_image_views {
        vk.DestroyImageView(gpu.device, image_view, nil);
    }

    vk.DestroySwapchainKHR(gpu.device, swap_chain, nil);

    create_sutable_device(vulkan_state);
    create_swapchain(vulkan_state, window);
    create_depthbuffer(vulkan_state, {.DEPTH});
    create_render_pass(vulkan_state);
    create_graphics_pipeline(vulkan_state);
    create_framebuffers(vulkan_state);
    create_command_pool(vulkan_state);
    create_command_buffers(vulkan_state);
}

create_image:: proc(using vulkan_state: ^Vulkan_State, frmat: vk.Format, width, height: u32, usage_flags: vk.ImageUsageFlags, memory_flags: vk.MemoryPropertyFlags) -> (image: Image) {

    image_info: vk.ImageCreateInfo = {
        sType = .IMAGE_CREATE_INFO,
        pNext = nil,
        imageType = vk.ImageType.D2,
        format = frmat,
        extent = {width, height, 1},
        mipLevels = 1,
        arrayLayers = 1,
        samples = {._1},
        tiling = .OPTIMAL,
        usage = usage_flags,
    };


   if vk.CreateImage(gpu.device, &image_info, nil, &image.image) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create image!");
    }

    mem_requirements: vk.MemoryRequirements;
    vk.GetImageMemoryRequirements(gpu.device, image.image, &mem_requirements);
    memory := allocate_gpu_memory(&gpu, mem_requirements, memory_flags);

    image.memory = memory
    vk.BindImageMemory(gpu.device, image.image, image.memory, 0);

    return image;
}

create_depthbuffer:: proc(using vulkan_state: ^Vulkan_State, aspect_flags: vk.ImageAspectFlags) {

    // Depth format is hardcoded to 32 bit float now, may need to check for supported
    // format if this one is unsupported?
    depth_format = .D32_SFLOAT;

    // For depth buffer, local memory should be used for performance reasons
    depth_image = create_image(vulkan_state, depth_format, window_extent.width, window_extent.height, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL})

    image_view_info : vk.ImageViewCreateInfo = {
        sType = .IMAGE_VIEW_CREATE_INFO,
        pNext = nil,
        viewType = .D2,
        image = depth_image.image,
        format = depth_format,
        subresourceRange     = {
            baseMipLevel   = 0, 
            levelCount     = 1, 
            baseArrayLayer = 0, 
            layerCount     = 1,
            aspectMask     = aspect_flags,
        },
    };

    if vk.CreateImageView(gpu.device, &image_view_info, nil, &depth_image_view) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create image view!");
    }

}

get_vertex_description:: proc() -> Vertex_Description {
    
	description: Vertex_Description;
    description.bindings   = make([dynamic]vk.VertexInputBindingDescription, context.temp_allocator);   
    description.attributes = make([dynamic]vk.VertexInputAttributeDescription, context.temp_allocator);   
	//we will have just 1 vertex buffer binding, with a per-vertex rate
	main_binding: vk.VertexInputBindingDescription = {
        binding   = 0,
        stride    = size_of(Vertex),
        inputRate = .VERTEX,
    };
    
    append_elem(&description.bindings, main_binding);
    
    using reflect;
    type_info := type_info_base(type_info_of(Vertex));
    struct_info := type_info.variant.(Type_Info_Struct);
    
    // position - normal - uv - color
    for offset, idx in struct_info.offsets {
        attribute : vk.VertexInputAttributeDescription = {
            binding = 0,
            location = u32(idx),
            format = .R32G32B32_SFLOAT,
            offset = u32(struct_info.offsets[idx]),
        };
        append_elem(&description.attributes, attribute);
    }

	return description;
}

create_sutable_device:: proc(vulkan_state: ^Vulkan_State) {
    using vulkan_state;
    
    device_count: u32;
    vk.EnumeratePhysicalDevices(instance, &device_count, nil);
    
    if device_count == 0
    {
        fmt.println("[Vulkan] No GPU with Vulkan support!");
        assert(false);
    }
    
    devices := make([dynamic]vk.PhysicalDevice,
                                      device_count,
                                      device_count,
                                      context.temp_allocator);
    vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0]);
    
    // Check devices if they are sutable
    for i: u32 = 0; i < device_count; i += 1 {
        // Device stability checks
        gpu.physical_device = devices[i];
        
        if check_device_extensions(gpu.physical_device) == false {
            continue;
        }
        
        device_properties: vk.PhysicalDeviceProperties;
        vk.GetPhysicalDeviceProperties(gpu.physical_device, &device_properties);
        
        // The support for optional features like texture compression, 64 bit floats and multi viewport 
        // rendering (useful for VR) can be queried using vkGetPhysicalDeviceFeatures
        device_features: vk.PhysicalDeviceFeatures;
        vk.GetPhysicalDeviceFeatures(gpu.physical_device, &device_features);
        
        queue_family_indices := find_queue_families(gpu.physical_device, surface);
        
        if (queue_family_indices.graphics_family.valid != true ||
            queue_family_indices.present_family.valid != true) {
            continue;
        }
        
        unique_queue_family_count: u32;
        unique_queue_family_indices: [2]u32;
        device_queue_infos: [2]vk.DeviceQueueCreateInfo;
        
        // Create separate queue if indicies are not the same
        if (queue_family_indices.present_family.index != 
            queue_family_indices.graphics_family.index) {
            
            unique_queue_family_count = 2;
            unique_queue_family_indices[0] = queue_family_indices.graphics_family.index;
            unique_queue_family_indices[1] = queue_family_indices.present_family.index;
        } else {
            
            unique_queue_family_count = 1;
            unique_queue_family_indices[0] = queue_family_indices.graphics_family.index;
        }
        
        for f: u32 = 0; f < unique_queue_family_count; f += 1 {
            queue_priority: f32 = 1.0;
            device_queue_infos[f] =  {
                sType            = .DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex = unique_queue_family_indices[f],
                queueCount       = 1,
                pQueuePriorities = &queue_priority,
            };
        }
        
        device_create_info: vk.DeviceCreateInfo = {
            sType                   = .DEVICE_CREATE_INFO,
            pQueueCreateInfos       = &device_queue_infos[0],
            queueCreateInfoCount    = unique_queue_family_count,
            pEnabledFeatures        = &device_features,
            ppEnabledExtensionNames = &device_extensions[0],
            enabledExtensionCount   = len(device_extensions),
        };
        
        result := vk.CreateDevice(gpu.physical_device, &device_create_info, nil, &gpu.device);
        assert(result == .SUCCESS);
        
        vk.GetDeviceQueue(gpu.device, queue_family_indices.graphics_family.index, 0, &graphics_queue);
        vk.GetDeviceQueue(gpu.device, queue_family_indices.present_family.index, 0, &present_queue);
        
        // TODO(mb): Right now we just quit the loop of first compatible physical device 
        // instead of selecting the best device for the job.
        break;
    }
}

get_memory_type_index:: proc(gpu: ^GPU_Device, mem_requirements: vk.MemoryRequirements, property_flags: vk.MemoryPropertyFlags) -> u32 {
    
    mem_properties :vk.PhysicalDeviceMemoryProperties; 
    vk.GetPhysicalDeviceMemoryProperties(gpu.physical_device, &mem_properties);
    
    index : u32 = misc.U32_MAX;
    
    for i : u32 = 0; i < mem_properties.memoryTypeCount; i += 1 {
        can_use := bool(mem_requirements.memoryTypeBits & (1 << i));
        can_use &= mem_properties.memoryTypes[i].propertyFlags & property_flags != {};
        
        if can_use {
            index = i;
            break;
        }
    }
    
    assert(index != misc.U32_MAX);
    
    return index;
}

allocate_gpu_memory:: proc(gpu: ^GPU_Device, mem_requirements: vk.MemoryRequirements, memory_flags: vk.MemoryPropertyFlags) -> vk.DeviceMemory {
    
    result: vk.DeviceMemory;
    
    mem_type_index := get_memory_type_index(gpu, mem_requirements, memory_flags);
    
    alloc_info: vk.MemoryAllocateInfo = {
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = mem_requirements.size,
        memoryTypeIndex = mem_type_index,
    };
    
    if vk.AllocateMemory(gpu.device, &alloc_info, nil, &result) != .SUCCESS {
        fmt.println("[Vulkan] Failed to allocate buffer!");
    }
    
    return result;
}


create_buffer:: proc(using vulkan_state: ^Vulkan_State, data: rawptr, size: vk.DeviceSize, usage: vk.BufferUsageFlag) -> (buffer: Buffer) {
    
    buffer_info: vk.BufferCreateInfo = {
        sType       = .BUFFER_CREATE_INFO,
        size        = size,
        usage       = {usage},
    };

    if vk.CreateBuffer(gpu.device, &buffer_info, nil, &buffer.buffer) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create buffer!");
    }
    
    mem_requirements: vk.MemoryRequirements;
    vk.GetBufferMemoryRequirements(gpu.device, buffer.buffer, &mem_requirements);
    
    buffer.memory = allocate_gpu_memory(&gpu, mem_requirements, {.HOST_VISIBLE, .HOST_COHERENT});
    
    vk.BindBufferMemory(gpu.device, buffer.buffer, buffer.memory, 0);
    
    gpu_data: rawptr;
    vk.MapMemory(gpu.device, buffer.memory, 0, buffer_info.size, {}, &gpu_data);
    
    mem.copy(gpu_data, data, int(buffer_info.size));
    
    vk.UnmapMemory(gpu.device, buffer.memory);

    return buffer;
}

vulkan_init:: proc(using vulkan_state: ^Vulkan_State, window: glfw.WindowHandle) {
    
    // Instance creation
    {
        app_info := vk.ApplicationInfo {
            sType               = .APPLICATION_INFO,
            pApplicationName    = "??",
            applicationVersion  = vk.MAKE_VERSION(1, 0, 0),
            pEngineName         = "IDK",
            engineVersion       = vk.MAKE_VERSION(1, 0, 0),
            apiVersion          = vk.API_VERSION_1_0,
        };
        
        when ODIN_OS == "windows" {
            instance_extensions := [?]cstring{
                "VK_KHR_surface",
                "VK_KHR_win32_surface",
                "VK_EXT_debug_utils",
            };
        } else when ODIN_OS == "linux" {
            instance_extensions := [?]cstring{
                "VK_KHR_surface",
                // TODO(mb): Linux surface extension
                "VK_EXT_debug_utils",
            };
        }
        // Load all the function ptrs from the dll
        {
            lib, ok := dynlib.load_library("vulkan-1.dll", true);
            assert(ok);
            
            context.user_ptr = &lib;
            vk.load_proc_addresses(proc(p: rawptr, name: cstring) {
                                       lib := (cast(^dynlib.Library)context.user_ptr)^;
                                       
                                       ptr, found := dynlib.symbol_address(lib, runtime.cstring_to_string(name));
                                       if !found {
                                           //fmt.printf("[Vulkan] Could not find symbol {}\n", name);
                                           return;
                                       }
                                       
                                       casted := cast(^rawptr)p;
                                       casted^ = ptr;
                                   });
            
        }
        layer_count: u32;
        vk.EnumerateInstanceLayerProperties(&layer_count, nil);
        
        available_layers := make([dynamic]vk.LayerProperties, 
                                                   layer_count,
                                                   layer_count,
                                                   context.temp_allocator);
        
        vk.EnumerateInstanceLayerProperties(&layer_count, &available_layers[0]);
        
        when ODIN_DEBUG {
            validation_layers := [?]cstring{
                "VK_LAYER_KHRONOS_validation",
            };
            
            layer_found := false;
            for i := 0; i < len(validation_layers); i += 1 {
                layer: string = string(validation_layers[i]);
                
                for j := 0; j < len(available_layers); j += 1 {
                    length := len(validation_layers[i]);
                    if mem.compare_byte_ptrs(&available_layers[j].layerName[0], transmute(^byte)validation_layers[i], length) == 0{
                        layer_found = true;
                    }
                    
                }
            }
            assert(layer_found);
        } else {
            validation_layers := nil;
        }
        
        create_info: vk.InstanceCreateInfo = {
            sType                   = .INSTANCE_CREATE_INFO,
            pApplicationInfo        = &app_info,
            enabledExtensionCount   = u32(len(instance_extensions)),
            ppEnabledExtensionNames = &instance_extensions[0],
            enabledLayerCount       = u32(len(validation_layers)),
            ppEnabledLayerNames     = &validation_layers[0],
        };
        
        // This debug info is is necessery to be able to debug vkCreateInstance and
        // vkDestroyIstance calls since setup_debug_messenger requires instance to
        // be already created to send the debug messages
        debug_create_info: vk.DebugUtilsMessengerCreateInfoEXT;
        populate_debug_messenger_create_info(&debug_create_info);
        create_info.pNext = &debug_create_info;
        
        result: vk.Result = vk.CreateInstance(&create_info, nil, &instance);
        assert(result == .SUCCESS);
    } 
    
    
    setup_debug_messenger(&debug_messenger, instance);
    
    
    // Surface creation
    
    if glfw.CreateWindowSurface(instance, window, nil, &surface) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create window surface!");
        assert(false);
    }
    
    create_sutable_device(vulkan_state);
    create_swapchain(vulkan_state, window);
    create_depthbuffer(vulkan_state, {.DEPTH});
    create_render_pass(vulkan_state);
    create_graphics_pipeline(vulkan_state);
    create_framebuffers(vulkan_state);
    create_command_pool(vulkan_state);
    create_command_buffers(vulkan_state);
    create_sync_stuff(vulkan_state);
    // triangle_mesh.vertices = make([dynamic]Vertex, 3);
    // triangle_mesh.vertices[0].pos = { 1,  1, 0}; 
    // triangle_mesh.vertices[1].pos = {-1,  1, 0}; 
    // triangle_mesh.vertices[2].pos = { 0, -1, 0}; 
    // triangle_mesh.vertices[0].color = {0.1, 0.2, 0.0};
    // triangle_mesh.vertices[1].color = {0.1, 0.2, 0.0};
    // triangle_mesh.vertices[2].color = {0.1, 0.2, 0.0};
    
    some_mesh = obj_read("assets/monkey.obj");

    for vertex, idx in some_mesh.vertices {
        some_mesh.vertices[idx].color = vertex.normal;
    }

    size := vk.DeviceSize(len(some_mesh.vertices) * size_of(Vertex));
    vertex_buffer = create_buffer(vulkan_state, &some_mesh.vertices[0], size, .VERTEX_BUFFER);

    size  = vk.DeviceSize(len(some_mesh.indices) * size_of(u32));
    index_buffer = create_buffer(vulkan_state, &some_mesh.indices[0], size, .INDEX_BUFFER);
}

draw_frame:: proc(using vulkan_state: ^Vulkan_State, window: glfw.WindowHandle) {
    
    vk.WaitForFences(gpu.device, 1, &render_fence, true, misc.U64_MAX);
    vk.ResetFences(gpu.device, 1, &render_fence);
    
    image_index: u32;
    image_result := vk.AcquireNextImageKHR(gpu.device, swap_chain, misc.U64_MAX, present_semaphore, 0, &image_index);  

    if framebuffer_resized {
        recreate_swap_chain(vulkan_state, window)
    }
    
    cmd_buffer := command_buffers[image_index];
    vk.ResetCommandBuffer(cmd_buffer, {.RELEASE_RESOURCES});
    
    begin_info: vk.CommandBufferBeginInfo = {
        sType            = .COMMAND_BUFFER_BEGIN_INFO,
        pInheritanceInfo = nil, // Optional
        flags            = {.ONE_TIME_SUBMIT}, 
    };
    
    if vk.BeginCommandBuffer(cmd_buffer, &begin_info) != .SUCCESS {
        fmt.println("[Vulkan] Failed to begin recording command buffer!");
    }
    
    
    color_clear_value : vk.ClearValue;
    color_clear_value.color.float32 = {
        0.2, 0.2, 0.2, 1.0,
    };

    depth_clear_value : vk.ClearValue;
    depth_clear_value.depthStencil.depth = 1.0;
    
    clear_values : []vk.ClearValue = {color_clear_value, depth_clear_value};
    render_pass_info: vk.RenderPassBeginInfo = { 
        sType            = .RENDER_PASS_BEGIN_INFO,
        renderPass       = vulkan_state.render_pass,
        framebuffer      = vulkan_state.swap_chain_framebuffers[image_index],
        
        renderArea       = {
            offset = {0, 0},
            extent = vulkan_state.window_extent,
        },
        clearValueCount  = 2,
        pClearValues     = &clear_values[0],
    };
    
    vk.CmdBeginRenderPass(cmd_buffer, &render_pass_info, .INLINE);
    
    vk.CmdBindPipeline(cmd_buffer, .GRAPHICS, graphics_pipeline);
    
    offset: []vk.DeviceSize = {0};
    vk.CmdBindVertexBuffers(cmd_buffer, 0, 1, &vertex_buffer.buffer, &offset[0]);

    vk.CmdBindIndexBuffer(cmd_buffer, index_buffer.buffer, 0, .UINT32);

    // Computing push constants
    cam_pos: vec3 = {0, 0, -2};

    view := la.matrix4_translate(cam_pos)
    projection := la.matrix4_perspective_f32(math.to_radians_f32(90), 640.0/480.0, 0.1, 1000);
    model := la.matrix4_rotate(math.to_radians_f32(20.0), vec3{0, 1, 0});
    mesh_matrix := la.matrix_mul(la.matrix_mul(projection, view), model);


    push_constants: Push_Constants;
    push_constants.render_matrix = mesh_matrix;


    vk.CmdPushConstants(cmd_buffer, pipeline_layout, {.VERTEX}, 0, size_of(Push_Constants), &push_constants)
    
    vk.CmdDrawIndexed(cmd_buffer, u32(len(some_mesh.indices)), 1, 0, 0, 0);
    
    vk.CmdEndRenderPass(cmd_buffer);
    
    if vk.EndCommandBuffer(cmd_buffer) != .SUCCESS {
        fmt.println("[Vulkan] Failed to record command buffer!");
    }
    wait_stage_mask : vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT};
    
    submit_info: vk.SubmitInfo = {
        sType = .SUBMIT_INFO,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &present_semaphore,
        pWaitDstStageMask = &wait_stage_mask,
        commandBufferCount = 1,
        pCommandBuffers = &cmd_buffer,
        signalSemaphoreCount = 1,
        pSignalSemaphores = &render_semaphore,
    };
    
    
    if (vk.QueueSubmit(graphics_queue, 1, &submit_info, render_fence) != .SUCCESS) {
        fmt.println("[Vulkan] Failed to submit draw command buffer!");
    }
    
    
    present_info: vk.PresentInfoKHR = {
        sType              = .PRESENT_INFO_KHR,
        pWaitSemaphores    = &render_semaphore,
        waitSemaphoreCount = 1,
        pSwapchains        = &swap_chain,
        swapchainCount     = 1,
        pImageIndices      = &image_index,
        pResults           = nil,
    };
    
    vk.QueuePresentKHR(present_queue, &present_info);
}

megabytes:: proc(n: int) -> int {
    return n * 1024 * 1024;
}

glfw_framebuffer_size_callback:: proc "c" (window: glfw.WindowHandle, width, height: c.int) {

    vulkan_state : = cast(^Vulkan_State)glfw.GetWindowUserPointer(window);
    vulkan_state.framebuffer_resized = true;
}

main :: proc() {
    
    main_arena: mem.Arena;
    temp_arena: mem.Arena;
    memory, err := mem.alloc_bytes(megabytes(12));
    mem.init_arena(&main_arena, memory);
    memory, err  = mem.alloc_bytes(megabytes(32));
    mem.init_arena(&temp_arena, memory);
    
    context.allocator = mem.arena_allocator(&main_arena);
    context.temp_allocator = mem.arena_allocator(&temp_arena);
    
    temp_memory: mem.Arena_Temp_Memory = mem.begin_arena_temp_memory(&temp_arena);
    
    vulkan_state : ^Vulkan_State = new(Vulkan_State);
    window: glfw.WindowHandle;
    
    mem.end_arena_temp_memory(temp_memory);
    
    if glfw.Init() == 0 {
        fmt.println("Failed to init glfw.");
    }

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    //glfw.WindowHint(glfw.RESIZABLE, 0);

    window = glfw.CreateWindow(640, 480, "Vulkan", nil, nil);
    glfw.SetFramebufferSizeCallback(window, glfw_framebuffer_size_callback);
    glfw.SetWindowUserPointer(window, vulkan_state);

    vulkan_init(vulkan_state, window);
    
    if window == nil {
        fmt.println("Failed to create glfw window.");
        glfw.Terminate();
    }
    
    if glfw.VulkanSupported() == false {
        fmt.println("Vulkan is unsuported.");
        glfw.Terminate();
    }
    
    for ;!glfw.WindowShouldClose(window); {
        glfw.PollEvents();
        draw_frame(vulkan_state, window);
    }

    glfw.Terminate();
}
