// Wallpaper transition "wipe": the new image comes in from one side behind a soft straight edge.
//
// Adapted from quickshell/Shaders/frag/wp_wipe.frag in DankMaterialShell
// (https://github.com/AvengeMedia/DankMaterialShell, commit e978bae), which credits its
// wallpaper effects to Noctalia. Copyright (c) 2025 Avenge Media LLC. MIT license; the full
// text is in LICENSES/dankmaterialshell-MIT.txt.
// Changes for Pentad: no fill-mode sampling (the image layers already fill the screen), a fixed
// edge width instead of a smoothness uniform, one edge formula for all four sides, and the
// uniform block and sampler names of Pentad's WallpaperWindow.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;  // 0 shows the old image, 1 the new one
    float direction; // the side the new image enters from: 0 left, 1 right, 2 top, 3 bottom
};
layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

// Half the width of the blended band, as a share of the screen.
const float softness = 0.02;

void main() {
    vec2 uv = qt_TexCoord0;
    float along = direction < 0.5 ? uv.x : direction < 1.5 ? 1.0 - uv.x : direction < 2.5 ? uv.y : 1.0 - uv.y;
    // The edge starts just outside the entry side and ends just past the far side.
    float edge = progress * (1.0 + 2.0 * softness) - softness;
    float reveal = 1.0 - smoothstep(edge - softness, edge + softness, along);
    fragColor = mix(texture(fromImage, uv), texture(toImage, uv), reveal) * qt_Opacity;
}
