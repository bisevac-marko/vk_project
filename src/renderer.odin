package    main 

import la    "core:math/linalg"

vec4 :: la.Vector4f32;
vec3 :: la.Vector3f32;
vec2 :: la.Vector2f32;
mat4 :: la.Matrix4f32;

Vertex :: struct {
    pos  : vec3,
    normal: vec3,
    uv: vec2,
    color: vec3,
}

Mesh :: struct {
    vertices: [dynamic]Vertex,
    indices: [dynamic]u32,
    
    handle: Handle,
}

PushConstants :: struct {
    data: vec4,
    render_matrix: mat4,
}

Handle :: distinct u64;