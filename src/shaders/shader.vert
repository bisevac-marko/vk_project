#version 450

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec3 a_color;

layout(location = 0) out vec3 out_color;

layout(push_constant) uniform constants
{
	vec4 data;
	mat4 render_matrix;
} PC;

void main() {
    gl_Position = PC.render_matrix * vec4(a_pos, 1.0f);
    out_color = a_color;
}
   