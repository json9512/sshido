#include <metal_stdlib>
using namespace metal;

struct CellInstance {
    float2 origin;
    float2 size;
    float4 fg;
    float4 bg;
    float2 atlasOrigin;
    float2 atlasSize;
};

struct Uniforms {
    float2 viewport;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
    float4 fg;
    float4 bg;
};

vertex VOut cell_vertex(uint vid [[vertex_id]],
                        uint iid [[instance_id]],
                        const device CellInstance* cells [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    float2 corners[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
    float2 c = corners[vid];
    CellInstance ci = cells[iid];
    float2 px = ci.origin + c * ci.size;
    float2 ndc = float2((px.x / u.viewport.x) * 2.0 - 1.0,
                        1.0 - (px.y / u.viewport.y) * 2.0);
    VOut o;
    o.position = float4(ndc, 0, 1);
    o.uv = ci.atlasOrigin + c * ci.atlasSize;
    o.fg = ci.fg;
    o.bg = ci.bg;
    return o;
}

fragment float4 cell_fragment(VOut in [[stage_in]],
                              texture2d<float> atlas [[texture(0)]],
                              sampler s [[sampler(0)]]) {
    float a = atlas.sample(s, in.uv).a;
    return mix(in.bg, in.fg, a);
}
