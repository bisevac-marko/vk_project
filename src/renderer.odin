package    main 

import la    "core:math/linalg"
import        "vendor:glfw"

RenderHandle :: u64;

vec4 :: la.Vector4f32;
vec3 :: la.Vector3f32;
vec2 :: la.Vector2f32;
mat4 :: la.Matrix4f32;

Color :: distinct vec4

Renderer_Backend :: enum {
    VULKAN,
}

Vertex :: struct {
    pos    : vec3,
    normal : vec3,
    uv     : vec2,
    color  : Color,
}

Vertex2D :: struct {
    pos      : vec2,
    uv       : vec2,
    color    : Color,
}

Mesh :: struct {
    vertices : [dynamic]Vertex,
    indices  :  [dynamic]u32,

    vertex_buffer: Vertex_Buffer,
    index_buffer: Index_Buffer,
}

Push_Constants :: struct {
    model           : mat4,
    view_projection : mat4,
}

Window :: struct {
    handle: glfw.WindowHandle,

    width: u32,
    height: u32,
}

Render_Context :: struct {

    entities: [dynamic]Entity,

    vertices: [4096]Vertex2D,
    vertex_count: int,

    indices: [4096]u32,
    index_count: int,

    variant: union{^Vulkan_Context},
}

Entity :: struct {

    mesh: ^Mesh,
    position: vec3,
}

new_entity:: proc(mesh: ^Mesh, position: vec3) -> Entity {
    entity: Entity;

    entity.mesh = mesh;
    entity.position = position;

    return entity;
}

new_renderer:: proc($T: typeid) -> ^T {
    r := new(T);
    r.variant = r;

    return r;
}

load_renderer:: proc(backend: Renderer_Backend, window: Window) -> ^Render_Context {
    renderer: ^Render_Context;

    switch backend {
        case .VULKAN: {
            renderer_init = vulkan_init;
            create_vertex_buffer = vulkan_create_vertex_buffer;
            create_index_buffer = vulkan_create_index_buffer;
            draw_frame = vulkan_draw_frame;
            renderer = vulkan_init(window);
        }
        case:
           assert(false);
    }

    return renderer;
}

send_mesh:: proc(renderer: ^Render_Context, using mesh: ^Mesh) {

    size := u64(len(mesh.vertices) * size_of(Vertex));
    vertex_buffer = create_vertex_buffer(renderer, &mesh.vertices[0], size);

    if (len(mesh.indices) > 0) {
        size  = u64(len(mesh.indices) * size_of(u32));
        index_buffer = create_index_buffer(renderer, &mesh.indices[0], size);
    }

}


renderer_init: proc(window: Window) -> ^Render_Context;

create_vertex_buffer: proc(renderer: ^Render_Context, data: rawptr, size: u64) -> Vertex_Buffer
create_index_buffer : proc(renderer: ^Render_Context, data: rawptr, size: u64)  -> Index_Buffer

draw_frame: proc(renderer: ^Render_Context, window: Window)

Vertex_Buffer :: distinct RenderHandle;
Index_Buffer  :: distinct RenderHandle;
