#include <metal_stdlib>
using namespace metal;

struct ChromeUniforms {
    float2 viewport;
    float  time;
};

struct ChromeVOut {
    float4 position [[position]];
    float2 uv;
};

vertex ChromeVOut chrome_vertex(uint vid [[vertex_id]],
                                constant ChromeUniforms& u [[buffer(0)]]) {
    float2 corners[4] = { float2(-1,1), float2(1,1), float2(-1,-1), float2(1,-1) };
    float2 uvs[4]     = { float2(0,0),  float2(1,0), float2(0,1),   float2(1,1)  };
    ChromeVOut o;
    o.position = float4(corners[vid], 0, 1);
    o.uv = uvs[vid];
    return o;
}

fragment float4 chrome_fragment(ChromeVOut in [[stage_in]],
                                constant ChromeUniforms& u [[buffer(0)]]) {
    // Base surface color: DS.Color.surface1 = #1A1A1F
    float3 base = float3(0.102, 0.102, 0.122);

    // Diagonal coordinate for the shimmer band
    float d = dot(in.uv, float2(0.7071, 0.7071));

    // Slow sweep: ~14s full cycle
    float band = fract(u.time * 0.07);

    // Smooth band with soft edges (0.06 half-width)
    float lo = smoothstep(band - 0.10, band - 0.02, d);
    float hi = smoothstep(band + 0.02, band + 0.10, d);
    float highlight = lo * (1.0 - hi);

    // Titanium light highlight: subtle 5% max brightness boost
    float3 lit = base + float3(0.05) * highlight;

    return float4(lit, 1.0);
}
