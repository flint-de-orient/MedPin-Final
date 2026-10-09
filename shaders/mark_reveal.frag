#version 460 core

// Splash mark reveal: shows one layer of the MedPin mark along its strokes.
// The flow map's red channel says when each pixel appears (0 = first, 1 = last);
// pixels fade in over 1/k of the timeline, giving a soft leading edge.
// Done in a shader so it renders the same on Impeller and Skia.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // size of the drawn rect, in local pixels
uniform float uReveal;  // timeline position
uniform float uK;       // edge softness
uniform sampler2D uImage;
uniform sampler2D uFlow;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 color = texture(uImage, uv);  // premultiplied
  float when = texture(uFlow, uv).r;
  float alpha = clamp(uK * (uReveal - when), 0.0, 1.0);
  fragColor = color * alpha;
}
