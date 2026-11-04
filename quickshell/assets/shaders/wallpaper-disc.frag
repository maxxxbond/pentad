// Wallpaper transition "disc": the new image grows out of a point in a round, soft-edged disc.
//
// Adapted from quickshell/Shaders/frag/wp_disc.frag in DankMaterialShell
// (https://github.com/AvengeMedia/DankMaterialShell, commit e978bae), which credits its
// wallpaper effects to Noctalia. Copyright (c) 2025 Avenge Media LLC. MIT license; the full
// text is in LICENSES/dankmaterialshell-MIT.txt.
// Changes for Pentad: no fill-mode sampling (the image layers already fill the screen), a fixed
// edge width instead of a smoothness uniform, a radius range that starts and ends outside the
// edge band (so no special case at progress 0), and the uniform block and sampler names of
// Pentad's WallpaperWindow.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress; // 0 shows the old image, 1 the new one
    float aspect;   // width / height, so the disc stays round
    float centerX;  // the disc's centre as a share of the width
    float centerY;  // and of the height
};
layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

// Half the width of the blended rim, in screen heights.
const float softness = 0.02;

void main() {
    vec2 uv = qt_TexCoord0;
    // Distances in screen heights, so the disc is a circle on any screen.
    vec2 point = vec2(uv.x * aspect, uv.y);
    vec2 origin = vec2(centerX * aspect, centerY);
    // The disc grows until it covers the corner farthest from its centre.
    float reach = length(vec2(max(origin.x, aspect - origin.x), max(origin.y, 1.0 - origin.y)));
    float radius = progress * (reach + 2.0 * softness) - softness;
    float reveal = 1.0 - smoothstep(radius - softness, radius + softness, distance(point, origin));
    fragColor = mix(texture(fromImage, uv), texture(toImage, uv), reveal) * qt_Opacity;
}
