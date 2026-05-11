#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;        // float 0, 1
uniform float uTime;       // float 2
uniform float uFps;        // float 3
uniform vec2 uCameraSize;  // float 4, 5

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    float scanline = sin((uv.y * uSize.y * 1.4) + uTime * 18.0) * 0.04;

    float gridX = step(0.992, fract(uv.x * 40.0));
    float gridY = step(0.992, fract(uv.y * 22.5));
    float grid = (gridX + gridY) * 0.05;

    float pulse = 0.5 + 0.5 * sin(uTime * 2.0);

    float vignette = smoothstep(
        0.95,
        0.25,
        distance(uv, vec2(0.5, 0.5))
    );

    vec3 cyanTint = vec3(0.0, 0.9, 1.0) * 0.14;
    vec3 color = cyanTint + vec3(grid) + vec3(scanline);
    color += vec3(0.0, pulse * 0.04, pulse * 0.06);

    fragColor = vec4(color * vignette, 0.30);
}