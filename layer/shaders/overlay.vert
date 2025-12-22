#version 450

// Vertex attributes
layout(location = 0) in vec2 inPos;    // Position in screen pixels
layout(location = 1) in vec2 inUV;     // Texture coordinates
layout(location = 2) in vec4 inColor;  // RGBA color

// Push constants for screen dimensions
layout(push_constant) uniform PushConstants {
    float screenWidth;
    float screenHeight;
} pc;

// Outputs to fragment shader
layout(location = 0) out vec2 outUV;
layout(location = 1) out vec4 outColor;

void main() {
    // Convert from pixel coordinates to NDC [-1, 1]
    vec2 ndc = (inPos / vec2(pc.screenWidth, pc.screenHeight)) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);

    outUV = inUV;
    outColor = inColor;
}
