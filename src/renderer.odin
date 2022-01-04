package    main 

import la    "core:math/linalg"

vec4 :: la.Vector4f32;
vec3 :: la.Vector3f32;
vec2 :: la.Vector2f32;
mat4 :: la.Matrix4f32;

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
}

Push_Constants :: struct {
    model           : mat4,
    view_projection : mat4,
}


Color :: distinct vec4

draw_rect : proc(pos: vec2, size: vec2, color: Color)

