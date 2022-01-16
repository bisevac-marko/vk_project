#version 450

layout(location = 0) in vec4 color;
layout(location = 1) in vec3 frag_pos;
layout(location = 2) in vec3 normal;

layout(location = 0) out vec4 out_color;

vec3 light_pos = vec3(3, 3, -1);

void main() {
    vec3 light_dir = normalize(frag_pos - light_pos);

    float diffuse = max(dot(light_dir, normal), 0.0f);
    out_color = vec4(color.rgb * (diffuse + 0.01f), 1.0);
}
