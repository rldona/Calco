#include <metal_stdlib>
using namespace metal;

// A stroke is rendered as a dense sequence of round stamps along the
// Pencil path. Each stamp is an instanced quad; the fragment shader
// shapes it into a soft disc. Simple, fast, and good enough to judge
// latency and feel. Real brushes come later.

struct Stamp {
    float2 position;   // canvas pixels
    float  radius;     // canvas pixels
    float  alpha;
};

struct Uniforms {
    float2 canvasSize; // pixels
    float4 color;      // straight alpha
};

struct VertexOut {
    float4 position [[position]];
    float2 local;     // -1...1 inside the quad
    float  alpha;
};

vertex VertexOut stamp_vertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              constant Stamp *stamps [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]])
{
    // Two triangles, 6 vertices, covering -1...1
    const float2 corners[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2( 1, -1), float2( 1,  1), float2(-1,  1)
    };
    Stamp s = stamps[iid];
    float2 corner = corners[vid];
    float2 px = s.position + corner * s.radius;

    // Canvas pixels -> clip space (y down in canvas, y up in clip)
    float2 ndc = (px / u.canvasSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    VertexOut out;
    out.position = float4(ndc, 0, 1);
    out.local = corner;
    out.alpha = s.alpha;
    return out;
}

fragment float4 stamp_fragment(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(1)]])
{
    float d = length(in.local);
    // Hard-ish edge with ~1px antialias
    float edge = fwidth(d) * 1.5;
    float coverage = 1.0 - smoothstep(1.0 - edge, 1.0, d);
    float a = coverage * in.alpha * u.color.a;
    // Premultiplied output; pipeline uses (one, oneMinusSrcAlpha)
    return float4(u.color.rgb * a, a);
}

// Blit the canvas texture to the drawable, fitting it on screen.
struct BlitOut {
    float4 position [[position]];
    float2 uv;
};

vertex BlitOut blit_vertex(uint vid [[vertex_id]],
                           constant float4 &rect [[buffer(0)]]) // x, y, w, h in NDC
{
    const float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };
    float2 c = corners[vid];
    float2 ndc = rect.xy + c * rect.zw;
    BlitOut o;
    o.position = float4(ndc, 0, 1);
    o.uv = float2(c.x, 1.0 - c.y);
    return o;
}

fragment float4 blit_fragment(BlitOut in [[stage_in]],
                              texture2d<float> canvas [[texture(0)]])
{
    constexpr sampler s(filter::linear);
    return canvas.sample(s, in.uv);
}
