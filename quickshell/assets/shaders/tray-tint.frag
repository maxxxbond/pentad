#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 pixel = texture(source, qt_TexCoord0);
    vec3 rgb = pixel.rgb / max(pixel.a, 0.000001);
    float luminance = floor(dot(rgb, vec3(0.299, 0.587, 0.114)) * 255.0 + 0.5) / 255.0;
    vec3 desaturated = mix(rgb, vec3(luminance), 0.8);
    vec3 target = tint.rgb / max(tint.a, 0.000001);
    vec3 tinted = floor(clamp(desaturated * target, 0.0, 1.0) * 255.0 + 0.5) / 255.0;
    float alpha = pixel.a * tint.a;
    fragColor = vec4(tinted * alpha, alpha) * qt_Opacity;
}
