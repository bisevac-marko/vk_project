package main

import        "core:fmt"
import vk     "vendor:vulkan"
import misc   "core:math/bits"
import        "core:mem"

Memory_Type :: enum
{
    IMAGE,
    BUFFER,
}

Memory :: struct {
    id : vk.DeviceMemory,
    size: int,
    offset : vk.DeviceSize,
    alignment_offset: int,
    block: ^MemoryBlock,
}

MemoryBlock :: struct {
    memory : vk.DeviceMemory,
    size   : int,
    offset : int,
    mem_type_index: u32,
    type : Memory_Type,

    next: ^MemoryBlock,
}

Buffer_Type :: enum {
    VERTEX,
    INDEX,
}

Buffer :: struct {
    memory : Memory,
    buffer : vk.Buffer,
    type   : Buffer_Type,
}

Image :: struct {
    memory: Memory,
    image: vk.Image,
}

vulkan_create_vertex_buffer:: proc(using renderer: ^Render_Context, data: rawptr, size: u64) -> Vertex_Buffer {

    result: Vertex_Buffer = 0;

    switch api in renderer.variant {
        case ^Vulkan_Context: {

            buffer := create_buffer(api, data, vk.DeviceSize(size), .VERTEX);
            append_elem(&api.vertex_buffers, buffer);

            result =  Vertex_Buffer(len(api.vertex_buffers) - 1);

        }
        case:
            assert(false);
    }

    return result;
}

vulkan_create_index_buffer:: proc(using renderer: ^Render_Context, data: rawptr, size: u64) -> Index_Buffer {
    result: Index_Buffer = 0;

    switch api in renderer.variant {
        case ^Vulkan_Context: {

            buffer := create_buffer(api, data, vk.DeviceSize(size), .VERTEX);
            append_elem(&api.index_buffers, buffer);

            result =  Index_Buffer(len(api.index_buffers) - 1);

        }
        case:
            assert(false);
    }

    return result;
}

create_buffer:: proc(using vk_ctx: ^Vulkan_Context, data: rawptr, size: vk.DeviceSize, type: Buffer_Type) -> (buffer: Buffer) {

    buffer_info      : vk.BufferCreateInfo;
    mem_requirements : vk.MemoryRequirements;

    // Main buffer info
    buffer_info = {
        sType       = .BUFFER_CREATE_INFO,
        size        = size,
        usage       = {buffer_type_to_usage_flag(type), .TRANSFER_DST},
        sharingMode = .EXCLUSIVE,
    };

    // Create main buffer
    if vk.CreateBuffer(gpu.device, &buffer_info, nil, &buffer.buffer) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create buffer!");
    }
    
    vk.GetBufferMemoryRequirements(gpu.device, buffer.buffer, &mem_requirements);
    
    // Allocate gpu local memory
    buffer.memory = gpu_alloc_buffer(&gpu, mem_requirements, {.DEVICE_LOCAL});

    vk.BindBufferMemory(gpu.device, buffer.buffer, buffer.memory.id, buffer.memory.offset);
    // ----------------------------------------
    buffer.type = type;

    // If not passed a nil we copy the device local memory to gpu
    if (data != nil) {
        send_buffer(vk_ctx, &buffer, data, int(size));
    }

    return buffer;
}

get_memory_type_index:: proc(gpu: ^GPU, mem_requirements: vk.MemoryRequirements, property_flags: vk.MemoryPropertyFlags) -> u32 {
    
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

gpu_alloc_buffer:: proc(gpu: ^GPU, mem_requirements: vk.MemoryRequirements, memory_flags: vk.MemoryPropertyFlags) -> (result: Memory) {
    result = gpu_allocate(gpu, mem_requirements, memory_flags, .BUFFER);
    return result;
}

gpu_alloc_image:: proc(gpu: ^GPU, mem_requirements: vk.MemoryRequirements, memory_flags: vk.MemoryPropertyFlags) -> (result: Memory) {
    result = gpu_allocate(gpu, mem_requirements, memory_flags, .IMAGE);
    return result;
}

_alloc:: proc(gpu: ^GPU, mem_type_index: u32, size: vk.DeviceSize) -> vk.DeviceMemory {

    alloc_info: vk.MemoryAllocateInfo = {
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type_index,
    };

    memory: vk.DeviceMemory;
    if vk.AllocateMemory(gpu.device, &alloc_info, nil, &memory) != .SUCCESS {
        fmt.println("[Vulkan] Failed to allocate buffer!");
    }

    return memory;
}

// Allocates VRAM in 64mb chunks where each chunk is divided into smaller sub allocations
gpu_allocate:: proc(gpu: ^GPU, mem_requirements: vk.MemoryRequirements, memory_flags: vk.MemoryPropertyFlags, mem_type: Memory_Type) -> (result: Memory) {
    
    mem_type_index := get_memory_type_index(gpu, mem_requirements, memory_flags);
    size := int(mem_requirements.size);
    block_size := megabytes(64);

    assert(size < megabytes(64));

    mem_block := &gpu.memory;

    if (mem_block.size == 0)
    {
        memory := _alloc(gpu, mem_type_index, vk.DeviceSize(block_size));

        mem_block.memory = memory;
        mem_block.type = mem_type;
        mem_block.offset = 0;
        mem_block.size = block_size;
        mem_block.mem_type_index = mem_type_index;
    }

    for ;; {
        if (mem_block.mem_type_index == mem_type_index && mem_block.type == mem_type) {

                alignment := int(mem_requirements.alignment);
                alignment_offset := alignment - (mem_block.offset % alignment);
                available_size := mem_block.size - (alignment_offset + mem_block.offset);

                if (available_size >= size) {

                    if (alignment_offset != 0) {
                        mem_block.offset += alignment_offset;
                    }

                    result.id = mem_block.memory;
                    result.size = size;
                    result.offset = vk.DeviceSize(mem_block.offset);
                    result.alignment_offset = alignment_offset;
                    result.block = mem_block;


                    mem_block.offset += size;
                    break;
                }
        }

        if (mem_block.next == nil) {

            mem_block.next = new(MemoryBlock);

            memory := _alloc(gpu, mem_type_index, vk.DeviceSize(block_size));

            mem_block.next.memory = memory;
            mem_block.next.type = mem_type;
            mem_block.next.offset = 0;
            mem_block.next.size = block_size;
            mem_block.next.mem_type_index = mem_type_index;
        }
        mem_block = mem_block.next;
    }


    return result;
}

buffer_type_to_usage_flag:: proc(type: Buffer_Type) -> (result: vk.BufferUsageFlag) {
    switch type {
        case .INDEX:
            return .INDEX_BUFFER;
        case .VERTEX:
            return .VERTEX_BUFFER;
        case:
            fmt.println("[Vulkan] Unsuported buffer type!");
    }

    return result;
}

send_buffer:: proc(using vk_ctx: ^Vulkan_Context, buffer: ^Buffer, data: rawptr, size: int) {

    buffer_info      : vk.BufferCreateInfo;
    mem_requirements : vk.MemoryRequirements;
    staging_buffer   : vk.Buffer;
    staging_memory   : vk.DeviceMemory;

    // Staging buffer info
    buffer_info = {
        sType       = .BUFFER_CREATE_INFO,
        size        = vk.DeviceSize(size),
        usage       = {.TRANSFER_SRC},
        sharingMode = .EXCLUSIVE,
    };

    // Create staging buffer
    if vk.CreateBuffer(gpu.device, &buffer_info, nil, &staging_buffer) != .SUCCESS {
        fmt.println("[Vulkan] Failed to create buffer!");
    }
    
    vk.GetBufferMemoryRequirements(gpu.device, staging_buffer, &mem_requirements);
    
    mem_type_index := get_memory_type_index(&gpu, mem_requirements, {.HOST_VISIBLE, .HOST_COHERENT});

    staging_memory = _alloc(&gpu, mem_type_index, buffer_info.size);
    
    vk.BindBufferMemory(gpu.device, staging_buffer, staging_memory, 0);
    
    gpu_data: rawptr;
    vk.MapMemory(gpu.device, staging_memory, 0, buffer_info.size, {}, &gpu_data);
    
    mem.copy(gpu_data, data, int(buffer_info.size));
    
    vk.UnmapMemory(gpu.device, staging_memory);

    // ------------------------------------------

    // Copy staging buffer to gpu local buffer

    alloc_info: vk.CommandBufferAllocateInfo = {
        sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
        level              = .PRIMARY,
        commandPool        = upload_command_pool,
        commandBufferCount = 1,
    };

    temp_cmd_buffer: vk.CommandBuffer;
    vk.AllocateCommandBuffers(gpu.device, &alloc_info, &temp_cmd_buffer);

    begin_info: vk.CommandBufferBeginInfo = {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    };

    vk.BeginCommandBuffer(temp_cmd_buffer, &begin_info);

    copy_region: vk.BufferCopy = {
        srcOffset = 0,
        dstOffset = 0,
        size      = buffer_info.size,
    }

    vk.CmdCopyBuffer(temp_cmd_buffer, staging_buffer, buffer.buffer, 1, &copy_region);

    vk.EndCommandBuffer(temp_cmd_buffer);

    submit_info: vk.SubmitInfo = {
        sType              = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers    = &temp_cmd_buffer,
    };

    vk.QueueSubmit(graphics_queue, 1, &submit_info, 0);

    vk.QueueWaitIdle(graphics_queue);

    // Reset command buffers in command pool
    vk.ResetCommandPool(gpu.device, upload_command_pool, {.RELEASE_RESOURCES});
    vk.DestroyBuffer(gpu.device, staging_buffer, nil);

    vk.FreeMemory(gpu.device, staging_memory, nil);
}
