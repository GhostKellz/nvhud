#version 450

// Inputs from vertex shader
layout(location = 0) in vec2 inUV;
layout(location = 1) in vec4 inColor;

// Font texture sampler
layout(set = 0, binding = 0) uniform sampler2D fontTexture;

// Output color
layout(location = 0) out vec4 outColor;

void main() {
    // Sample font texture (R8 format, alpha is in the red channel)
    float texAlpha = texture(fontTexture, inUV).r;

    // For solid rectangles, UV is (0,0) where the texture should have full alpha
    // For text glyphs, use the sampled alpha from the font
    // The font texture has 1.0 at UV (0,0) for solid pixels
    outColor = vec4(inColor.rgb, inColor.a * texAlpha);
}
