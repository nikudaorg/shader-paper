#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; float2 uv; };
vertex V vertex_main(uint id [[vertex_id]]) {
    float2 uv=float2(float((id<<1u)&2u),float(id&2u));
    return {float4(uv*2.0-1.0,0,1),uv};
}
// An original still image, evaluated once in Metal. Broad blue folds and a
// restrained warm horizon recall macOS's abstract landscapes without an asset.
fragment half4 fragment_main(V in [[stage_in]],constant float& time [[buffer(0)]],
                            constant uint& presentationMode [[buffer(2)]]) {
    float2 p=float2(in.uv.x,1.0-in.uv.y);
    float3 c=mix(float3(0.48,0.66,0.86),float3(0.11,0.21,0.42),smoothstep(0.0,1.0,p.y));
    float ridge=0.38+0.16*sin(p.x*2.7-0.7)+0.12*p.x;
    float edge=p.y-ridge;
    float3 front=mix(float3(0.22,0.36,0.65),float3(0.045,0.10,0.25),smoothstep(0.1,0.9,p.y));
    c=mix(c,front,smoothstep(-0.045,0.07,edge));
    float second=0.72+0.13*sin(p.x*3.3+0.8);
    c=mix(c,float3(0.045,0.11,0.26),smoothstep(-0.025,0.075,p.y-second));
    float highlight=exp(-pow((edge+0.045)/0.10,2.0))*0.24;
    c+=highlight*float3(0.28,0.36,0.55);
    float warmth=exp(-dot((p-float2(0.08,0.21))*float2(1.8,3.2),(p-float2(0.08,0.21))*float2(1.8,3.2)))*0.36;
    c=mix(c,float3(0.88,0.72,0.66),warmth);
    return half4(half3(clamp(c,0.0,1.0)),1);
}
