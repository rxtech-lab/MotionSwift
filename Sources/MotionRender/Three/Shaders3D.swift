// Metal port of the three.js r187 (MIT) mesh shaders used by WebGLRenderer when it draws to the
// canvas: MeshBasic/Lambert/Phong/Standard/Physical/Normal materials, punctual + ambient +
// hemisphere lights, ACES filmic tone mapping, sRGB output and fog. Expressions keep three's
// operation order so ANGLE-on-Metal and native output agree as closely as possible.
let scene3DShaderSource = """
#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793
#define RECIPROCAL_PI 0.3183098861837907
#define EPSILON 1e-6

struct FrameUniforms {
  float4x4 projection;
  float3 ambient;
  float3 fogColor;
  float fogNear;
  float fogFar;
  float fogDensity;
  int fogType;
  int toneMapping;
  int pointCount;
  int spotCount;
  int directionalCount;
  int hemisphereCount;
};

struct ObjectUniforms {
  float4x4 modelView;
  float4x4 normalMatrix;
  float3 diffuse;
  float3 emissive;
  float3 specular;
  float3 specularColor;
  float opacity;
  float roughness;
  float metalness;
  float shininess;
  float specularF90;
  int material;
  int flatShading;
  int doubleSided;
  int flipSided;
  int opaque;
  int toneMapped;
  int fog;
};

struct PointLight { float3 position; float3 color; float distance; float decay; };
struct SpotLight {
  float3 position; float3 direction; float3 color; float distance; float decay; float coneCos; float penumbraCos;
};
struct DirectionalLight { float3 direction; float3 color; };
struct HemisphereLight { float3 direction; float3 skyColor; float3 groundColor; };

struct VertexOut {
  float4 position [[position, invariant]];
  float3 viewPosition;
  float3 normal;
  float fogDepth;
};

vertex VertexOut scene3d_vertex(uint vid [[vertex_id]],
                                const device packed_float3 *positions [[buffer(0)]],
                                const device packed_float3 *normals [[buffer(1)]],
                                constant ObjectUniforms &object [[buffer(2)]],
                                constant FrameUniforms &frame [[buffer(3)]]) {
  VertexOut out;
  float3 objectNormal = float3(normals[vid]);
  float3x3 normalMatrix = float3x3(object.normalMatrix[0].xyz, object.normalMatrix[1].xyz, object.normalMatrix[2].xyz);
  float3 transformedNormal = normalMatrix * objectNormal;
  if (object.flipSided != 0) transformedNormal = -transformedNormal;
  out.normal = normalize(transformedNormal);
  float4 mvPosition = object.modelView * float4(float3(positions[vid]), 1.0);
  float4 clip = frame.projection * mvPosition;
  // WebGL clip z is in [-w, w]; Metal expects [0, w] (ANGLE applies the same transform).
  clip.z = (clip.z + clip.w) * 0.5;
  // ANGLE draws WebGL's default framebuffer bottom-up (GL window space) and flips it when
  // presenting, so MSAA sample positions are mirrored vertically. Render the same way; the
  // readback flips rows back.
  clip.y = -clip.y;
  out.position = clip;
  out.viewPosition = -mvPosition.xyz;
  out.fogDepth = -mvPosition.z;
  return out;
}

static inline float pow2(float x) { return x * x; }
static inline float pow4(float x) { float x2 = x * x; return x2 * x2; }

static float3 F_Schlick(float3 f0, float f90, float dotVH) {
  float fresnel = exp2((-5.55473 * dotVH - 6.98316) * dotVH);
  return f0 * (1.0 - fresnel) + (f90 * fresnel);
}
static float3 BRDF_Lambert(float3 diffuseColor) { return RECIPROCAL_PI * diffuseColor; }

static float getDistanceAttenuation(float lightDistance, float cutoffDistance, float decayExponent) {
  float distanceFalloff = 1.0 / max(pow(lightDistance, decayExponent), 0.01);
  if (cutoffDistance > 0.0) distanceFalloff *= pow2(saturate(1.0 - pow4(lightDistance / cutoffDistance)));
  return distanceFalloff;
}

static float V_GGX_SmithCorrelated(float alpha, float dotNL, float dotNV) {
  float a2 = pow2(alpha);
  float gv = dotNL * sqrt(a2 + (1.0 - a2) * pow2(dotNV));
  float gl = dotNV * sqrt(a2 + (1.0 - a2) * pow2(dotNL));
  return 0.5 / max(gv + gl, EPSILON);
}
static float D_GGX(float alpha, float dotNH) {
  float a2 = pow2(alpha);
  float denom = pow2(dotNH) * (a2 - 1.0) + 1.0;
  return RECIPROCAL_PI * a2 / pow2(denom);
}

struct Physical {
  float3 diffuseColor;
  float3 diffuseContribution;
  float3 specularColor;
  float3 specularColorBlended;
  float roughness;
  float metalness;
  float specularF90;
  float2 dfg;
  float3 multiScatteringCompensation;
};

static float3 BRDF_GGX(float3 lightDir, float3 viewDir, float3 normal, thread const Physical &material) {
  float3 f0 = material.specularColorBlended;
  float f90 = material.specularF90;
  float roughness = max(material.roughness, 0.045);
  float alpha = pow2(roughness);
  float3 halfDir = normalize(lightDir + viewDir);
  float dotNL = saturate(dot(normal, lightDir));
  float dotNV = saturate(dot(normal, viewDir));
  float dotNH = saturate(dot(normal, halfDir));
  float dotVH = saturate(dot(viewDir, halfDir));
  float3 F = F_Schlick(f0, f90, dotVH);
  float V = V_GGX_SmithCorrelated(alpha, dotNL, dotNV);
  float D = D_GGX(alpha, dotNH);
  return F * (V * D);
}

static float3 BRDF_BlinnPhong(float3 lightDir, float3 viewDir, float3 normal, float3 specularColor, float shininess) {
  float3 halfDir = normalize(lightDir + viewDir);
  float dotNH = saturate(dot(normal, halfDir));
  float dotVH = saturate(dot(viewDir, halfDir));
  float3 F = F_Schlick(specularColor, 1.0, dotVH);
  float G = 0.25;
  float D = RECIPROCAL_PI * (shininess * 0.5 + 1.0) * pow(dotNH, shininess);
  return F * (G * D);
}

struct Reflected { float3 directDiffuse; float3 directSpecular; float3 indirectDiffuse; float3 indirectSpecular; };

static void direct(int model, float3 lightDirection, float3 lightColor, float3 normal, float3 viewDir,
                   thread const Physical &physical, constant ObjectUniforms &object, thread Reflected &reflected) {
  float dotNL = saturate(dot(normal, lightDirection));
  float3 irradiance = dotNL * lightColor;
  if (model == 3) {
    float3 specularBRDF = BRDF_GGX(lightDirection, viewDir, normal, physical);
    reflected.directSpecular += irradiance * specularBRDF * physical.multiScatteringCompensation;
    float3 halfDir = normalize(lightDirection + viewDir);
    float dotVH = saturate(dot(viewDir, halfDir));
    float3 F = F_Schlick(physical.specularColor, physical.specularF90, dotVH);
    float3 diffuseBRDF = BRDF_Lambert(physical.diffuseContribution);
    reflected.directDiffuse += irradiance * diffuseBRDF * (1.0 - F);
  } else {
    reflected.directDiffuse += irradiance * BRDF_Lambert(physical.diffuseColor);
    if (model == 2) {
      reflected.directSpecular += irradiance
        * BRDF_BlinnPhong(lightDirection, viewDir, normal, object.specular, object.shininess) * 1.0;
    }
  }
}

static void computeMultiscattering(float2 fab, float3 specularColor, float specularF90,
                                   thread float3 &singleScatter, thread float3 &multiScatter) {
  float3 Fr = specularColor;
  float3 FssEss = Fr * fab.x + specularF90 * fab.y;
  float Ess = fab.x + fab.y;
  float Ems = 1.0 - Ess;
  float3 Favg = Fr + (1.0 - Fr) * 0.047619;
  float3 Fms = FssEss * Favg / (1.0 - Ems * Favg);
  singleScatter += FssEss;
  multiScatter += Fms * Ems;
}

static float3 RRTAndODTFit(float3 v) {
  float3 a = v * (v + 0.0245786) - 0.000090537;
  float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return a / b;
}
static float3 ACESFilmicToneMapping(float3 color) {
  const float3x3 ACESInputMat = float3x3(float3(0.59719, 0.07600, 0.02840), float3(0.35458, 0.90834, 0.13383),
                                         float3(0.04823, 0.01566, 0.83777));
  const float3x3 ACESOutputMat = float3x3(float3(1.60475, -0.10208, -0.00327), float3(-0.53108, 1.10813, -0.07276),
                                          float3(-0.07367, -0.00605, 1.07602));
  color *= 1.0 / 0.6;
  color = ACESInputMat * color;
  color = RRTAndODTFit(color);
  color = ACESOutputMat * color;
  return saturate(color);
}
static float4 sRGBTransferOETF(float4 value) {
  float3 low = value.rgb * 12.92;
  float3 high = pow(value.rgb, float3(0.41666)) * 1.055 - float3(0.055);
  return float4(select(high, low, value.rgb <= float3(0.0031308)), value.a);
}

fragment float4 scene3d_fragment(VertexOut in [[stage_in]], bool frontFacing [[front_facing]],
                                 constant ObjectUniforms &object [[buffer(0)]],
                                 constant FrameUniforms &frame [[buffer(1)]],
                                 constant PointLight *pointLights [[buffer(2)]],
                                 constant SpotLight *spotLights [[buffer(3)]],
                                 constant DirectionalLight *directionalLights [[buffer(4)]],
                                 constant HemisphereLight *hemisphereLights [[buffer(5)]],
                                 texture2d<float> dfgLUT [[texture(0)]],
                                 sampler lutSampler [[sampler(0)]]) {
  float4 diffuseColor = float4(object.diffuse, object.opacity);
  float faceDirection = frontFacing ? 1.0 : -1.0;
  float3 normal;
  if (object.flatShading != 0) {
    // The flipped render makes Metal's window y point up like GLSL's.
    float3 fdx = dfdx(in.viewPosition);
    float3 fdy = dfdy(in.viewPosition);
    normal = normalize(cross(fdx, fdy));
  } else {
    normal = normalize(in.normal);
    if (object.doubleSided != 0) normal *= faceDirection;
  }
  float3 nonPerturbedNormal = normal;
  int model = object.material;
  float3 outgoingLight;
  if (model == 5) {
    float4 color = float4(normalize(normal) * 0.5 + 0.5, diffuseColor.a);
    if (object.opaque != 0) color.a = 1.0;
    return color;
  }
  if (model == 0) {
    outgoingLight = float3(1.0) * diffuseColor.rgb;
  } else {
    Reflected reflected = { float3(0.0), float3(0.0), float3(0.0), float3(0.0) };
    Physical physical;
    physical.diffuseColor = diffuseColor.rgb;
    if (model == 3) {
      physical.diffuseContribution = diffuseColor.rgb * (1.0 - object.metalness);
      physical.metalness = object.metalness;
      float3 dxy = max(abs(dfdx(nonPerturbedNormal)), abs(dfdy(nonPerturbedNormal)));
      float geometryRoughness = max(max(dxy.x, dxy.y), dxy.z);
      physical.roughness = max(object.roughness, 0.045);
      physical.roughness += geometryRoughness;
      physical.roughness = min(physical.roughness, 1.0);
      physical.specularColor = object.specularColor;
      physical.specularColorBlended = mix(physical.specularColor, diffuseColor.rgb, object.metalness);
      physical.specularF90 = object.specularF90;
    }
    float3 geometryPosition = -in.viewPosition;
    float3 geometryNormal = normal;
    float3 geometryViewDir = normalize(in.viewPosition);
    if (model == 3) {
      float dotNVms = saturate(dot(geometryNormal, geometryViewDir));
      physical.dfg = dfgLUT.sample(lutSampler, float2(physical.roughness, dotNVms)).rg;
      float EssMs = physical.dfg.x + physical.dfg.y;
      physical.multiScatteringCompensation = 1.0 + physical.specularColorBlended * (1.0 / EssMs - 1.0);
    }
    for (int i = 0; i < frame.pointCount; i++) {
      PointLight light = pointLights[i];
      float3 lVector = light.position - geometryPosition;
      float3 direction = normalize(lVector);
      float lightDistance = length(lVector);
      float3 color = light.color * getDistanceAttenuation(lightDistance, light.distance, light.decay);
      direct(model, direction, color, geometryNormal, geometryViewDir, physical, object, reflected);
    }
    for (int i = 0; i < frame.spotCount; i++) {
      SpotLight light = spotLights[i];
      float3 lVector = light.position - geometryPosition;
      float3 direction = normalize(lVector);
      float angleCos = dot(direction, light.direction);
      float spotAttenuation = smoothstep(light.coneCos, light.penumbraCos, angleCos);
      float3 color = float3(0.0);
      if (spotAttenuation > 0.0) {
        float lightDistance = length(lVector);
        color = light.color * spotAttenuation;
        color *= getDistanceAttenuation(lightDistance, light.distance, light.decay);
      }
      direct(model, direction, color, geometryNormal, geometryViewDir, physical, object, reflected);
    }
    for (int i = 0; i < frame.directionalCount; i++) {
      direct(model, directionalLights[i].direction, directionalLights[i].color, geometryNormal, geometryViewDir,
             physical, object, reflected);
    }
    float3 irradiance = frame.ambient;
    for (int i = 0; i < frame.hemisphereCount; i++) {
      HemisphereLight light = hemisphereLights[i];
      float dotNL = dot(geometryNormal, light.direction);
      float hemiDiffuseWeight = 0.5 * dotNL + 0.5;
      irradiance += mix(light.groundColor, light.skyColor, hemiDiffuseWeight);
    }
    if (model == 3) {
      float3 singleScattering = float3(0.0);
      float3 multiScattering = float3(0.0);
      computeMultiscattering(physical.dfg, physical.specularColor, physical.specularF90, singleScattering, multiScattering);
      reflected.indirectDiffuse += irradiance * BRDF_Lambert(physical.diffuseContribution)
        * (1.0 - singleScattering - multiScattering);
    } else {
      reflected.indirectDiffuse += irradiance * BRDF_Lambert(physical.diffuseColor);
    }
    float3 totalEmissiveRadiance = object.emissive;
    if (model == 3) {
      float3 totalDiffuse = reflected.directDiffuse + reflected.indirectDiffuse;
      float3 totalSpecular = reflected.directSpecular + reflected.indirectSpecular;
      outgoingLight = totalDiffuse + totalSpecular + totalEmissiveRadiance;
    } else if (model == 2) {
      outgoingLight = reflected.directDiffuse + reflected.indirectDiffuse + reflected.directSpecular
        + reflected.indirectSpecular + totalEmissiveRadiance;
    } else {
      outgoingLight = reflected.directDiffuse + reflected.indirectDiffuse + totalEmissiveRadiance;
    }
  }
  if (object.opaque != 0) diffuseColor.a = 1.0;
  float4 color = float4(outgoingLight, diffuseColor.a);
  if (frame.toneMapping != 0 && object.toneMapped != 0) color.rgb = ACESFilmicToneMapping(color.rgb);
  color = sRGBTransferOETF(color);
  if (frame.fogType != 0 && object.fog != 0) {
    float fogFactor = frame.fogType == 2
      ? 1.0 - exp(-frame.fogDensity * frame.fogDensity * in.fogDepth * in.fogDepth)
      : smoothstep(frame.fogNear, frame.fogFar, in.fogDepth);
    color.rgb = mix(color.rgb, frame.fogColor, fogFactor);
  }
  return color;
}
"""
