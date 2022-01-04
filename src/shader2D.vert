#version 450

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;

layout(location = 0) out vec4 color;

layout(push_constant) uniform constants
{
	mat4 model;
	mat4 view_projection;
} PC;

void main() {
    color = a_color;
    gl_Position = PC.model * vec4(a_pos, 0.0f, 1.0f);
}
   
