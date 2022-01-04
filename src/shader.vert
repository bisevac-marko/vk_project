#version 450

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_color;

layout(location = 0) out vec4 color;
layout(location = 1) out vec3 frag_pos;
layout(location = 2) out vec3 normal;

layout(push_constant) uniform constants
{
	mat4 model;
	mat4 view_projection;
} PC;

void main() {
    frag_pos = vec3(PC.model * vec4(a_pos, 1.0f));
    gl_Position = PC.view_projection * vec4(frag_pos, 1.0f);
    color = a_color;
    normal = a_normal;
}
   
