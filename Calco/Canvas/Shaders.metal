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
    float  hardness;   // brush edge: 1 = crisp (one antialiased pixel), 0 = soft all the way in
    float  grain;      // paper grain strength, 0–1
    float  grainScale; // grain size in canvas pixels
};

// How much of the disc covers this fragment: a soft edge one pixel wide (or wider for soft brushes),
// or (pixel art) all or nothing by the pixel centre, so a one-pixel brush paints exactly one pixel.
static float stampCoverage(float2 local, float hard, float hardness) {
    float d = length(local);
    // Pixel art: a square block of whole pixels (a round one comes out as a "+" when small).
    if (hard > 0.5) return max(abs(local.x), abs(local.y)) <= 1.0 ? 1.0 : 0.0;
    float edge = fwidth(d) * 1.5;
    float inner = clamp(hardness, 0.0, 1.0) * (1.0 - edge);
    return 1.0 - smoothstep(inner, 1.0, d);
}

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Paper tooth at this canvas pixel: fixed to the canvas, so going over it shows the same grain.
static float paperGrain(float2 px, float scale, float strength) {
    if (strength <= 0.0) return 1.0;
    float n = valueNoise(px / scale) * 0.65 + valueNoise(px / (scale * 0.45) + 17.0) * 0.35;
    return mix(1.0, smoothstep(0.28, 0.72, n), strength);
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
    float coverage = stampCoverage(in.local, u.hard, u.hardness);
    if (u.hard < 0.5) coverage *= paperGrain(in.position.xy, u.grainScale, u.grain);
    float a = coverage * (u.hard > 0.5 ? 1.0 : in.alpha) * u.color.a;
    return float4(u.color.rgb * a, a);
}

// Eraser: outputs coverage in alpha, pipeline blends (zero, oneMinusSrcAlpha)
// so destination is multiplied by (1 - coverage).
fragment float4 eraser_fragment(StampVertexOut in [[stage_in]],
                                constant StampUniforms &u [[buffer(1)]])
{
    float coverage = stampCoverage(in.local, u.hard, u.hardness);
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
    float2 pad;         // pad.x > 0.5: magnify smoothly (drawing, not pixel art)
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
    // Pixel art keeps every pixel crisp; a drawing, blown up, reads better smooth.
    constexpr sampler s(mag_filter::nearest, min_filter::linear);
    constexpr sampler smooth(mag_filter::linear, min_filter::linear);
    float4 c = u.pad.x > 0.5 ? layer.sample(smooth, in.uv) : layer.sample(s, in.uv);   // premultiplied
    float3 tinted = u.tint.rgb * c.a;           // tint keeps coverage
    c.rgb = mix(c.rgb, tinted, u.tintAmount);
    if (u.useMask > 0.5) c *= mask.sample(s, in.uv).a;
    return c * u.opacity;
}

// The workspace around the canvas: a faint grid, like a cutting mat. `canvasSize` carries the
// cell size in drawable pixels (x) and whether to draw it (y).
fragment float4 workspace_fragment(CompositeVertexOut in [[stage_in]],
                                   constant CompositeUniforms &u [[buffer(0)]])
{
    float3 base = float3(0.106, 0.106, 0.114);
    if (u.canvasSize.y < 0.5) return float4(base, 1.0);
    float cell = u.canvasSize.x;
    float2 p = in.position.xy;
    float2 g = abs(fract(p / cell + 0.5) - 0.5) * cell;        // distance to the nearest line, px
    float2 G = abs(fract(p / (cell * 4.0) + 0.5) - 0.5) * cell * 4.0;
    float minor = 1.0 - smoothstep(0.0, 1.2, min(g.x, g.y));
    float major = 1.0 - smoothstep(0.0, 1.5, min(G.x, G.y));
    float3 c = base + minor * 0.05 + major * 0.05;
    return float4(c, 1.0);
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

// ---------------------------------------------------------------------------
// Smudge: each dab redraws its disc from a copy of the layer under it, mixed by coverage and
// strength with: the paint where the finger came from (smudge), the paint around (blur), or the
// paint along the way it's moving (motion).
// ---------------------------------------------------------------------------

struct SmudgeUniforms {
    float2 canvasSize;
    float2 delta;      // canvas pixels the finger moved since the last dab
    float  strength;   // 0–1
    float  hardness;
    float  reach;      // blur / motion length in canvas pixels
    int    mode;       // 0 smudge, 1 blur, 2 motion
};

fragment float4 smudge_fragment(StampVertexOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                constant SmudgeUniforms &u [[buffer(1)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_zero);
    float2 px = in.position.xy;
    float4 here = src.sample(s, px / u.canvasSize);
    float4 other = here;
    if (u.mode == 0) {
        other = src.sample(s, (px - u.delta) / u.canvasSize);
    } else if (u.mode == 1) {
        // A soft disc of 25 taps.
        float4 sum = 0; float total = 0;
        for (int y = -2; y <= 2; y++) {
            for (int x = -2; x <= 2; x++) {
                float2 o = float2(x, y) * (u.reach * 0.5);
                float w = exp(-dot(float2(x, y), float2(x, y)) * 0.35);
                sum += src.sample(s, (px + o) / u.canvasSize) * w;
                total += w;
            }
        }
        other = sum / total;
    } else {
        // Along the way the finger moves, behind it: a trail.
        float len = length(u.delta);
        float2 dir = len > 0.001 ? u.delta / len : float2(1, 0);
        float4 sum = 0;
        for (int k = 0; k < 12; k++) {
            sum += src.sample(s, (px - dir * (u.reach * float(k) / 11.0)) / u.canvasSize);
        }
        other = sum / 12.0;
    }
    float cov = stampCoverage(in.local, 0.0, u.hardness) * in.alpha;
    return mix(here, other, clamp(u.strength * cov, 0.0, 1.0));
}
