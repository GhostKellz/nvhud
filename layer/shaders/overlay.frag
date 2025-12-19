#version 450

layout(push_constant) uniform PushConstants {
    vec4 color;   // RGBA color
} pc;

layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

void main() {
    // Output the push constant color directly
    outColor = pc.color;
}
