// Wallpaper transition "iris": the new image opens from the centre as a narrow slit that
// rounds out while it grows, like an eye or a camera iris opening.
//
// Adapted from quickshell/Shaders/frag/wp_iris_bloom.frag in DankMaterialShell
// (https://github.com/AvengeMedia/DankMaterialShell, commit e978bae), which credits its
// wallpaper effects to Noctalia. Copyright (c) 2025 Avenge Media LLC. MIT license; the full
// text is in LICENSES/dankmaterialshell-MIT.txt.
// Changes for Pentad: no fill-mode sampling (the image layers already fill the screen), a fixed
// centre and edge width instead of uniforms, a radius range that starts and ends outside the
// edge band (so no special cases at progress 0 and 1), and the uniform block and sampler names
// of Pentad's WallpaperWindow.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress; // 0 shows the old image, 1 the new one
    float aspect;   // width / height, so the opening ends as a circle
};
layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

// Half the width of the blended rim, in screen heights.
const float softness = 0.02;

void main() {
    vec2 uv = qt_TexCoord0;
    float p = progress * progress * (3.0 - 2.0 * progress);
    // From the screen's centre, in screen heights; the opening must reach the corners.
    vec2 offset = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float reach = length(vec2(0.5 * aspect, 0.5));
    // Squashed vertically at first, so the opening starts as a slit.
    offset.y /= mix(0.2, 1.0, p);
    float radius = p * (reach + 2.0 * softness) - softness;
    float reveal = 1.0 - smoothstep(radius - softness, radius + softness, length(offset));
    fragColor = mix(texture(fromImage, uv), texture(toImage, uv), reveal) * qt_Opacity;
}
