#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Stamps: a stroke is a dense sequence of round stamps along the Pencil path.
// Each stamp is an instanced quad shaped into a soft disc by the fragment.
// ---------------------------------------------------------------------------

struct Stamp {
    float2 position;   // canvas pixels
    float  radius;     // canvas pixels
    float  alpha;
};

struct StampUniforms {
    float2 canvasSize; // pixels
    float4 color;      // straight alpha
    float  hard;       // 1 = pixel art: a pixel is fully in or out, no antialiased edge
};

// How much of the disc covers this fragment: a soft edge one pixel wide, or (pixel art) all or nothing
// by the pixel centre, so a one-pixel brush paints exactly one pixel.
static float stampCoverage(float2 local, float hard) {
    float d = length(local);
    if (hard > 0.5) return d <= 1.0 ? 1.0 : 0.0;
    float edge = fwidth(d) * 1.5;
    return 1.0 - smoothstep(1.0 - edge, 1.0, d);
}

struct StampVertexOut {
    float4 position [[position]];
    float2 local;     // -1...1 inside the quad
    float  alpha;
};

vertex StampVertexOut stamp_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   constant Stamp *stamps [[buffer(0)]],
                                   constant StampUniforms &u [[buffer(1)]])
{
    const float2 corners[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2( 1, -1), float2( 1,  1), float2(-1,  1)
    };
    Stamp s = stamps[iid];
    float2 corner = corners[vid];
    float2 px = s.position + corner * s.radius;

    float2 ndc = (px / u.canvasSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    StampVertexOut out;
    out.position = float4(ndc, 0, 1);
    out.local = corner;
    out.alpha = s.alpha;
    return out;
}

// Brush: premultiplied color, pipeline blends (one, oneMinusSrcAlpha).
fragment float4 stamp_fragment(StampVertexOut in [[stage_in]],
                               constant StampUniforms &u [[buffer(1)]])
{
    float coverage = stampCoverage(in.local, u.hard);
    float a = coverage * (u.hard > 0.5 ? 1.0 : in.alpha) * u.color.a;
    return float4(u.color.rgb * a, a);
}

// Eraser: outputs coverage in alpha, pipeline blends (zero, oneMinusSrcAlpha)
// so destination is multiplied by (1 - coverage).
fragment float4 eraser_fragment(StampVertexOut in [[stage_in]],
                                constant StampUniforms &u [[buffer(1)]])
{
    float coverage = stampCoverage(in.local, u.hard);
    return float4(0, 0, 0, coverage * (u.hard > 0.5 ? 1.0 : in.alpha));
}

// ---------------------------------------------------------------------------
// Composite: draw a layer texture (or checkerboard) into a quad on screen.
// The quad is origin + u * axisX + v * axisY in NDC, so it can be zoomed, panned and rotated.
// ---------------------------------------------------------------------------

struct CompositeUniforms {
    float2 origin;      // NDC of the canvas's bottom-left corner
    float2 axisX;       // NDC from bottom-left to bottom-right
    float2 axisY;       // NDC from bottom-left to top-left
    float2 pad;
    float4 tint;        // rgb used when tintAmount > 0
    float  opacity;
    float  tintAmount;  // 0 = original colors, 1 = fully tinted (onion skin)
    float2 canvasSize;  // for checkerboard cell size
    float  useMask;     // 1 = only where `mask` has paint (layer masked to the one below)
};

struct CompositeVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex CompositeVertexOut composite_vertex(uint vid [[vertex_id]],
                                           constant CompositeUniforms &u [[buffer(0)]])
{
    const float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };
    float2 c = corners[vid];
    float2 ndc = u.origin + c.x * u.axisX + c.y * u.axisY;
    CompositeVertexOut o;
    o.position = float4(ndc, 0, 1);
    o.uv = float2(c.x, 1.0 - c.y);
    return o;
}

fragment float4 composite_fragment(CompositeVertexOut in [[stage_in]],
                                   constant CompositeUniforms &u [[buffer(0)]],
                                   texture2d<float> layer [[texture(0)]],
                                   texture2d<float> mask [[texture(1)]])
{
    // Magnified (the usual case on screen) shows the sprite's real pixels, like any sprite
    // editor: blending them on the way up is what made strokes look blurry. Shrunk (thumbnails,
    // zoomed out) still blends, which is the better-looking way down.
    constexpr sampler s(mag_filter::nearest, min_filter::linear);
    float4 c = layer.sample(s, in.uv);          // premultiplied
    float3 tinted = u.tint.rgb * c.a;           // tint keeps coverage
    c.rgb = mix(c.rgb, tinted, u.tintAmount);
    if (u.useMask > 0.5) c *= mask.sample(s, in.uv).a;
    return c * u.opacity;
}

fragment float4 checker_fragment(CompositeVertexOut in [[stage_in]],
                                 constant CompositeUniforms &u [[buffer(0)]])
{
    float2 px = in.uv * u.canvasSize;
    // 32 cells across the long side, so a 64 px sprite and a 1024 px one look alike on screen.
    float cell = max(u.canvasSize.x, u.canvasSize.y) / 32.0;
    float2 q = floor(px / cell);
    float odd = fmod(q.x + q.y, 2.0);
    float g = mix(0.78, 0.88, odd);
    return float4(g, g, g, 1.0);
}
