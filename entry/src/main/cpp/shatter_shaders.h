#ifndef PETRELGRAM_SHATTER_SHADERS_H
#define PETRELGRAM_SHATTER_SHADERS_H

namespace shatter {
constexpr const char *kVertexShader = R"GLSL(#version 300 es
precision highp float;
precision highp int;
layout(location = 0) in vec4 rect;
layout(location = 1) in vec4 motion;
uniform vec2 viewportSize;
uniform float topPadding;
uniform float progress;
uniform int moving;
out vec2 sourcePixel;
out vec2 localPixel;
flat out vec4 sourceRect;
flat out vec2 tileSize;
flat out float opacity;
const vec2 corners[6] = vec2[6](vec2(0,0), vec2(1,0), vec2(0,1),
                               vec2(0,1), vec2(1,0), vec2(1,1));
void main() {
    bool startedTile = progress > motion.z;
    if ((moving == 0 && startedTile) || (moving == 1 && (!startedTile || progress >= 1.0))) {
        gl_Position = vec4(2, 2, 0, 1);
        sourcePixel = localPixel = tileSize = vec2(0);
        sourceRect = rect;
        opacity = 0.0;
        return;
    }
    float t = moving == 0 ? 0.0 : clamp((progress - motion.z) / (1.0 - motion.z), 0.0, 1.0);
    float scale = 1.0 - 0.45 * t;
    float travel = 0.35 * t + 0.65 * t * t;
    vec2 origin = rect.xy + rect.zw * (1.0 - scale) * 0.5 + vec2(motion.x, -motion.y) * travel;
    tileSize = rect.zw * scale;
    // 静止块严格贴合整数像素；运动块在边缘留半像素做解析抗锯齿。
    float edge = moving == 0 ? 0.0 : 0.5;
    localPixel = corners[gl_VertexID] * (tileSize + 2.0 * edge) - edge;
    vec2 position = origin + localPixel + vec2(0, topPadding);
    gl_Position = vec4(position.x / viewportSize.x * 2.0 - 1.0,
                       1.0 - position.y / viewportSize.y * 2.0, 0, 1);
    sourcePixel = rect.xy + localPixel / scale;
    sourceRect = rect;
    opacity = moving == 0 ? 1.0 : pow(1.0 - t, motion.w);
}
)GLSL";

constexpr const char *kFragmentShader = R"GLSL(#version 300 es
precision highp float;
precision highp int;
uniform sampler2D snapshot;
uniform vec2 imageSize;
uniform int moving;
in vec2 sourcePixel;
in vec2 localPixel;
flat in vec4 sourceRect;
flat in vec2 tileSize;
flat in float opacity;
out vec4 color;
void main() {
    vec2 samplePixel = clamp(sourcePixel, sourceRect.xy + 0.5,
                            sourceRect.xy + sourceRect.zw - 0.5);
    float coverage = 1.0;
    if (moving == 1) {
        vec2 edges = clamp(min(localPixel, tileSize - localPixel) + 0.5, 0.0, 1.0);
        // 与 Canvas 的 quad 边缘 AA 一样取最近边，避免四角相乘导致碎片变淡。
        coverage = min(edges.x, edges.y);
    }
    // 纹理在 worker 上统一为预乘 RGBA，淡出同时乘 RGB 和 alpha。
    color = texture(snapshot, samplePixel / imageSize) * (opacity * coverage);
}
)GLSL";
} // namespace shatter
#endif
