// Wallpaper transition "pixelate": the new image fades in as large blocks that shrink until it
// is sharp.
//
// Adapted from quickshell/Shaders/frag/wp_pixelate.frag in DankMaterialShell
// (https://github.com/AvengeMedia/DankMaterialShell, commit e978bae), which credits its
// wallpaper effects to Noctalia. Copyright (c) 2025 Avenge Media LLC. MIT license; the full
// text is in LICENSES/dankmaterialshell-MIT.txt.
// Changes for Pentad: no fill-mode sampling (the image layers already fill the screen), block
// sizes measured in screen heights from the aspect ratio instead of screen-size uniforms, a fixed
// starting block size instead of a smoothness uniform, and the uniform block and sampler names
// of Pentad's WallpaperWindow.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress; // 0 shows the old image, 1 the new one
    float aspect;   // width / height, so the blocks stay square
};
layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    // Square blocks in screen heights: about a sixth of the shorter side at first, then
    // down to roughly a pixel.
    float block = mix(0.16 * min(aspect, 1.0), 0.001, p);
    vec2 cells = vec2(aspect, 1.0) / block;
    vec2 snapped = (floor(uv * cells) + 0.5) / cells;
    // The blocks give way to the full image over the last quarter.
    vec4 incoming = mix(texture(toImage, snapped), texture(toImage, uv), smoothstep(0.75, 1.0, p));
    fragColor = mix(texture(fromImage, uv), incoming, p * p * (3.0 - 2.0 * p)) * qt_Opacity;
}
