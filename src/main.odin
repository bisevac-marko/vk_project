package main

import        "core:fmt"
import        "core:c"
import        "vendor:glfw"
import        "core:mem"
import str    "core:strings"
import        "core:runtime"
import        "core:os"
import misc   "core:math/bits"
import la     "core:math/linalg"
import math   "core:math"

Particle :: struct {
    velocity    : vec3,
    acceleration: vec3,
    position    : vec3,
}

update:: proc(using particle: ^Particle, dt: f32)
{
    velocity += acceleration * dt;

    position += velocity;

    velocity *= 0.99;

    acceleration = {};
}


glfw_framebuffer_size_callback:: proc "c" (window: glfw.WindowHandle, width, height: c.int) {

    vk_ctx : = cast(^Vulkan_Context)glfw.GetWindowUserPointer(window);
    vk_ctx.framebuffer_resized = true;
}

draw_rect:: proc(using renderer: ^Render_Context, pos: vec2, size: vec2, color: Color) {

    rect_vertices := []vec2 {
        {-0.5, -0.5},
        { 0.5, -0.5},
        { 0.5,  0.5},
        {-0.5,  0.5},
    };
    
    rect_uvs := []vec2 {
        { 0.0,  0.0},
        { 1.0,  0.0},
        { 1.0,  1.0},
        { 0.0,  1.0},
    };

    rect_indices := []u32 {
        0, 1, 2,
        0, 2, 3,
    }

    for i := 0; i < 4; i+=1 {
        vertex := &vertices[vertex_count + i];
        vertex.pos = (rect_vertices[i] * size) + pos;
        vertex.color = color;
        vertex.uv = rect_uvs[i];
    }

    for i := 0; i < 6; i+=1 {
        indices[index_count + i] = u32(vertex_count) + rect_indices[i];
    }

    index_count  += 6;
    vertex_count += 4;
}


main :: proc() {

    // Loading the renderer
    window: Window;
    
    if (glfw.Init() == 0) {
        fmt.println("Failed to init glfw.");
    }

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);

    window.handle = glfw.CreateWindow(1366, 768, "Vulkan", nil, nil);

    renderer: ^Render_Context = load_renderer(.VULKAN, window);

    glfw.SetFramebufferSizeCallback(window.handle, glfw_framebuffer_size_callback);
    glfw.SetWindowUserPointer(window.handle, renderer);

    
    if (window.handle == nil) {
        fmt.println("Failed to create glfw window.");
        glfw.Terminate();
    }
    
    if (glfw.VulkanSupported() == false) {
        fmt.println("Vulkan is unsuported.");
        glfw.Terminate();
    }

    // Read obj
    monkey_mesh := obj_read("assets/monkey.obj");
    cube_mesh := obj_read("assets/cube.obj");

    send_mesh(renderer, &monkey_mesh);
    send_mesh(renderer, &cube_mesh);
    
    append_elem(&renderer.entities, new_entity(&monkey_mesh, vec3{}));
    append_elem(&renderer.entities, new_entity(&cube_mesh, vec3{1, 0, -3}));
    
    for (!glfw.WindowShouldClose(window.handle)) {
        glfw.PollEvents();
        draw_rect(renderer, vec2{100, 100}, vec2{100, 100}, Color{1, 0, 0, 1});
        draw_rect(renderer, vec2{250, 100}, vec2{100, 100}, Color{0, 1, 0, 1});
        draw_rect(renderer, vec2{200, 300}, vec2{150, 150}, Color{0, 0, 1, 1});
        draw_frame(renderer, window);
    }

    glfw.Terminate();
}
