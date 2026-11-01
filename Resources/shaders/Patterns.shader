#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; float2 uv; };
struct Tile { float4 bounds; uint4 motif; };
struct PatternUniforms { float4 viewport; uint4 lattice; };
vertex V vertex_main(uint id [[vertex_id]]) {
    float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
    return {float4(uv*2.0-1.0,0,1),uv};
}
float3 hsl(float hue, float saturation, float lightness) {
    float3 c = clamp(abs(fract(hue+float3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0)-1.0,0.0,1.0);
    return lightness+saturation*(c-0.5)*(1.0-abs(2.0*lightness-1.0));
}
float3 palette(uint index,float hue) {
    if(index==0u)return hsl(hue,0.64,0.70);
    if(index==1u)return hsl(hue,0.38,0.26);
    if(index==2u)return float3(250,250,244)/255.0;
    return float3(16,21,14)/255.0;
}
fragment half4 fragment_main(V in [[stage_in]], constant float& time [[buffer(0)]],
    constant uint& presentationMode [[buffer(2)]], constant PatternUniforms& config [[buffer(3)]],
    constant Tile* tiles [[buffer(4)]], texture2d<uint,access::read> grid [[texture(1)]]) {
    // Unknown presentation has a conservative held appearance. Appearance
    // routing itself is driven by the host's explicit mode, not the clock.
    if(presentationMode==0u)return half4(0.06,0.08,0.055,1);
    float2 world=in.position.xy/config.viewport.z;
    uint2 cell=min(uint2(world*36.0),config.lattice.xy-uint2(1));
    Tile tile=tiles[grid.read(cell).r];
    float2 p=(world-tile.bounds.xy)/tile.bounds.z;
    uint rotation=tile.motif.w;
    if(rotation==3u)p=float2(1.0-p.y,p.x);
    else if(rotation==2u)p=1.0-p;
    else if(rotation==1u)p=float2(p.y,1.0-p.x);
    uint motif=tile.motif.z;
    float radius=length(p-float2(0.5)), edge=0;
    if(motif==0u)edge=length(p)-1.0;
    else if(motif==1u)edge=max(length(p)-1.0,0.7-length(p));
    else if(motif==2u)edge=max(length(p-float2(0,1))-1.0,length(p-float2(1,0))-1.0);
    else if(motif==3u)edge=radius-0.5;
    else if(motif==4u)edge=max(radius-0.5,0.35-radius);
    else edge=(p.x-p.y)*0.70710678;
    float width=max(fwidth(edge),0.000001);
    float coverage=1.0-smoothstep(-width*0.5,width*0.5,edge);
    float hue=config.viewport.w/360.0;
    float3 color=mix(palette(tile.motif.x,hue),palette(tile.motif.y,hue),coverage);
    float3 linear=select(color/12.92,pow((color+0.055)/1.055,float3(2.4)),color>0.04045);
    return half4(half3(linear),1);
}
