#version 460

#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#include "Common.glsl"
#include "PBR.glsl"

layout(location = 0) in Out
{
    vec3 position;
    vec3 eye;
} vIn;

layout(location = 0) out vec4 aColor;

layout(std430, binding = 0) restrict readonly buffer Materials
{
    VoxelMaterial uMaterials[];
};

layout(std430, binding = 23) restrict readonly buffer VoxelMaterialsVisual {
    VoxelMaterialVisual voxel_materials_visual[];
};

layout(std430, binding = 1) restrict readonly buffer VoxelMaterials
{
    uint16_t uVoxelMaterials[];
};

layout(std430, binding = 2) restrict readonly buffer VoxelTemperature
{
    float uVoxelTemperatures[];
};

layout(std430, binding = 21) restrict buffer OutDeviationBuffer {
    int8_t out_deviation_buffer[];
};

layout(binding = 22) uniform sampler2D environment_map;

layout(std430, binding = 22) restrict readonly buffer PointLights {
    PointLight point_lights[];
};

layout(std430, binding = 32) restrict readonly buffer SpotLights {
    SpotLight spot_lights[];
};

vec2 SampleSphericalMap(vec3 v)
{
    const vec2 invAtan = vec2(0.1591, 0.3183);
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    uv *= invAtan;
    uv += 0.5;
    uv.y = 1 - uv.y;
    return uv;
}

float srgbXYZ2RGBPostprocess(float c)
{
    c = clamp(c, 0, 1);

    c = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1. / 2.4) - 0.055;

    return c;
}

vec3 srgbXYZ2RGB(vec3 xyz)
{
    float rl = 3.2406255 * xyz.x + -1.537208 * xyz.y + -0.4986286 * xyz.z;
    float gl = -0.9689307 * xyz.x + 1.8757561 * xyz.y + 0.0415175 * xyz.z;
    float bl = 0.0557101 * xyz.x + -0.2040211 * xyz.y + 1.0569959 * xyz.z;

    return vec3(srgbXYZ2RGBPostprocess(rl), srgbXYZ2RGBPostprocess(gl), srgbXYZ2RGBPostprocess(bl));
}

const vec3 cie_colour_match[81] =
    {
    vec3(0.0014, 0.0000, 0.0065), vec3(0.0022, 0.0001, 0.0105), vec3(0.0042, 0.0001, 0.0201),
    vec3(0.0076, 0.0002, 0.0362), vec3(0.0143, 0.0004, 0.0679), vec3(0.0232, 0.0006, 0.1102),
    vec3(0.0435, 0.0012, 0.2074), vec3(0.0776, 0.0022, 0.3713), vec3(0.1344, 0.0040, 0.6456),
    vec3(0.2148, 0.0073, 1.0391), vec3(0.2839, 0.0116, 1.3856), vec3(0.3285, 0.0168, 1.6230),
    vec3(0.3483, 0.0230, 1.7471), vec3(0.3481, 0.0298, 1.7826), vec3(0.3362, 0.0380, 1.7721),
    vec3(0.3187, 0.0480, 1.7441), vec3(0.2908, 0.0600, 1.6692), vec3(0.2511, 0.0739, 1.5281),
    vec3(0.1954, 0.0910, 1.2876), vec3(0.1421, 0.1126, 1.0419), vec3(0.0956, 0.1390, 0.8130),
    vec3(0.0580, 0.1693, 0.6162), vec3(0.0320, 0.2080, 0.4652), vec3(0.0147, 0.2586, 0.3533),
    vec3(0.0049, 0.3230, 0.2720), vec3(0.0024, 0.4073, 0.2123), vec3(0.0093, 0.5030, 0.1582),
    vec3(0.0291, 0.6082, 0.1117), vec3(0.0633, 0.7100, 0.0782), vec3(0.1096, 0.7932, 0.0573),
    vec3(0.1655, 0.8620, 0.0422), vec3(0.2257, 0.9149, 0.0298), vec3(0.2904, 0.9540, 0.0203),
    vec3(0.3597, 0.9803, 0.0134), vec3(0.4334, 0.9950, 0.0087), vec3(0.5121, 1.0000, 0.0057),
    vec3(0.5945, 0.9950, 0.0039), vec3(0.6784, 0.9786, 0.0027), vec3(0.7621, 0.9520, 0.0021),
    vec3(0.8425, 0.9154, 0.0018), vec3(0.9163, 0.8700, 0.0017), vec3(0.9786, 0.8163, 0.0014),
    vec3(1.0263, 0.7570, 0.0011), vec3(1.0567, 0.6949, 0.0010), vec3(1.0622, 0.6310, 0.0008),
    vec3(1.0456, 0.5668, 0.0006), vec3(1.0026, 0.5030, 0.0003), vec3(0.9384, 0.4412, 0.0002),
    vec3(0.8544, 0.3810, 0.0002), vec3(0.7514, 0.3210, 0.0001), vec3(0.6424, 0.2650, 0.0000),
    vec3(0.5419, 0.2170, 0.0000), vec3(0.4479, 0.1750, 0.0000), vec3(0.3608, 0.1382, 0.0000),
    vec3(0.2835, 0.1070, 0.0000), vec3(0.2187, 0.0816, 0.0000), vec3(0.1649, 0.0610, 0.0000),
    vec3(0.1212, 0.0446, 0.0000), vec3(0.0874, 0.0320, 0.0000), vec3(0.0636, 0.0232, 0.0000),
    vec3(0.0468, 0.0170, 0.0000), vec3(0.0329, 0.0119, 0.0000), vec3(0.0227, 0.0082, 0.0000),
    vec3(0.0158, 0.0057, 0.0000), vec3(0.0114, 0.0041, 0.0000), vec3(0.0081, 0.0029, 0.0000),
    vec3(0.0058, 0.0021, 0.0000), vec3(0.0041, 0.0015, 0.0000), vec3(0.0029, 0.0010, 0.0000),
    vec3(0.0020, 0.0007, 0.0000), vec3(0.0014, 0.0005, 0.0000), vec3(0.0010, 0.0004, 0.0000),
    vec3(0.0007, 0.0002, 0.0000), vec3(0.0005, 0.0002, 0.0000), vec3(0.0003, 0.0001, 0.0000),
    vec3(0.0002, 0.0001, 0.0000), vec3(0.0002, 0.0001, 0.0000), vec3(0.0001, 0.0000, 0.0000),
    vec3(0.0001, 0.0000, 0.0000), vec3(0.0001, 0.0000, 0.0000), vec3(0.0000, 0.0000, 0.0000)
    };

float bb_spectrum(float temp, float wavelength)
{
    float wlm = wavelength * 1e-9; /* Wavelength in meters */

    return (3.74183e-16 * pow(wlm, -5.0)) / (exp(1.4388e-2 / (wlm * (temp - 273))) - 1.0);
}

vec3 spectrum(float temperature)
{
    vec3 xyz = vec3(0.0);

    float lambda = 0;

    for (int i = 0, lambda = 380; lambda < 780.1; i++, lambda += 5)
    {
        float Me = bb_spectrum(temperature, lambda);

        xyz += cie_colour_match[i] * Me;
    }

    return srgbXYZ2RGB(normalize(xyz));
}

struct RayCastResult {
    uint voxel_index;
    //How far along the ray is the hit
    float t;
    vec3 normal;
    vec2 uv;
};

float raycastChunks(
    in vec3 ro,
    in vec3 rd,
    out vec3 oVos,
    out vec3 oDir,
    out uint chunk_index
) {
    vec3 pos = floor(ro);
    vec3 ri = length(rd) / rd;
    vec3 rs = CHUNK_SIZE * sign(rd);
    vec3 delta_dis = CHUNK_SIZE * abs(length(rd) / rd);
    vec3 dis = (pos - ro + 0.5 + rs * 0.5) * ri;

    float res = -1;
    vec3 mm = vec3(0);

    uvec3 size_in_chunks = uSize / CHUNK_SIZE;

    for (int i = 0; i < size_in_chunks.x + size_in_chunks.y + size_in_chunks.z; i++) {
        uvec3 position = uvec3(pos + 0.5);

        if (!isInBounds(ivec3(position))) {
            res = -1;
            chunk_index = 0;
            break;
        }

        uint index = (position.x / CHUNK_SIZE) + size_in_chunks.x * (position.y / CHUNK_SIZE) + size_in_chunks.x * size_in_chunks.y * (position.z / CHUNK_SIZE);
        uint chunk_bit_count = voxel_chunks_allocation[index].bit_count;

        if (chunk_bit_count != 0) {
            res = 1.0;
            chunk_index = index;
            break;
        }

        mm = step(dis.xyz, dis.yzx) * step(dis.xyz, dis.zxy);
        mm = vec3(lessThanEqual(dis.xyz, min(dis.yzx, dis.zxy)));
        dis += mm * delta_dis;
        pos += mm * rs;
    }

    vec3 nor = -mm * rs;
    vec3 vos = pos;

    //intersect the cube
    vec3 mini = (pos - ro + 0.5 - 0.5 * vec3(rs)) * ri;
    float t = max(mini.x, max(mini.y, mini.z));

    oDir = mm;
    oVos = vos;

    return t * res;
}

float raycastVoxels(
    in uint chunk_index,
    in uint medium_material,
    in vec3 ro,
    in vec3 rd,
    out vec3 oVos,
    out vec3 oDir,
    out uint voxel_index
) {
    vec3 pos = floor(ro);
    vec3 ri = length(rd) / rd;
    vec3 rs = sign(rd);
    vec3 delta_dis = abs(length(rd) / rd);
    vec3 dis = (pos - ro + 0.5 + rs * 0.5) * ri;

    float res = -1;
    vec3 mm = vec3(0);

    for (int i = 0; i < uSize.x + uSize.y + uSize.z; i++) {
        uvec3 position = uvec3(pos + 0.5);

        if (!isInBounds(ivec3(position))) {
            res = -1;
            voxel_index = 0;
            break;
        }

        uint index = position.x + uSize.x * position.y + uSize.x * uSize.y * position.z;
        uint type = loadVoxelMaterial(ivec3(position));

        if (type != medium_material) {
            res = 1.0;
            voxel_index = index;
            break;
        }

        mm = step(dis.xyz, dis.yzx) * step(dis.xyz, dis.zxy);
        mm = vec3(lessThanEqual(dis.xyz, min(dis.yzx, dis.zxy)));
        dis += mm * delta_dis;
        pos += mm * rs;
    }

    vec3 nor = -mm * rs;
    vec3 vos = pos;

    //intersect the cube
    vec3 mini = (pos - ro + 0.5 - 0.5 * vec3(rs)) * ri;
    float t = max(mini.x, max(mini.y, mini.z));

    oDir = mm;
    oVos = vos;

    return t * res;
}

float raycastVoxelsOld(
    in uint medium_material,
    in vec3 ro,
    in vec3 rd,
    out vec3 oVos,
    out vec3 oDir,
    out uint voxel_index
) {
    vec3 pos = floor(ro);
    vec3 ri = length(rd) / rd;
    vec3 rs = sign(rd);
    vec3 delta_dis = abs(length(rd) / rd);
    vec3 dis = (pos - ro + 0.5 + rs * 0.5) * ri;

    float res = -1;
    vec3 mm = vec3(0);

    for (int i = 0; i < uSize.x + uSize.y + uSize.z; i++) {
        uvec3 position = uvec3(pos + 0.5);

        if (!isInBoundsInclusive(ivec3(position))) {
            res = -1;
            voxel_index = 0;
            break;
        }

        uint index = position.x + uSize.x * position.y + uSize.x * uSize.y * position.z;
        uint type = uVoxelMaterials[index];

        /*
                if (position.y > index % (uSize.x * uSize.z)) {
                    res = -1;
                    voxel_index = 0;
                    break;
                }
                */

        if (false) {
            type = loadVoxelMaterial(ivec3(position));
        }

        if (type != medium_material) {
            res = 1.0;
            voxel_index = index;
            break;
        }

        mm = step(dis.xyz, dis.yzx) * step(dis.xyz, dis.zxy);
        mm = vec3(lessThanEqual(dis.xyz, min(dis.yzx, dis.zxy)));
        dis += mm * delta_dis;
        pos += mm * rs;
    }

    vec3 nor = -mm * rs;
    vec3 vos = pos;

    //intersect the cube
    vec3 mini = (pos - ro + 0.5 - 0.5 * vec3(rs)) * ri;
    float t = max(mini.x, max(mini.y, mini.z));

    oDir = mm;
    oVos = vos;

    return t * res;
}

float raycast(
    in uint medium_material,
    in vec3 ro,
    in vec3 rd,
    out vec3 oVos,
    out vec3 oDir,
    out uint voxel_index
) {
    if (true) {
        return raycastVoxelsOld(medium_material, ro, rd, oVos, oDir, voxel_index);
    }

    vec3 ray_origin = ro;

    for (int i = 0; i < 100; i++) {
        vec3 chunk_dir;
        uint chunk_index;

        float chunk_t = raycastChunks(ray_origin, rd, ray_origin, chunk_dir, chunk_index);

        if (chunk_t > 0) {
            ray_origin += chunk_t * rd;
            float voxel_t = raycastVoxels(chunk_index, medium_material, ray_origin, rd, oVos, oDir, voxel_index);

            if (voxel_t > 0) {
                return voxel_t;
            }
        }
        else {
            break;
        }
    }

    return -1;
}

vec3 computeLightRadiance(
    PointLight light,
    vec3 ray_origin,
    vec3 ray_direction,
    uint medium_material
) {
    vec3 pos = ray_origin;

    vec3 out_radiance = unpackUnorm4x8(light.colour).rgb * light.radiance;

    for (int i = 0; i < 10; i++) {
        vec3 def_dir;
        uint voxel_index;

        float light_occlusion = raycast(
                medium_material,
                pos + 0.5,
                ray_direction,
                ray_origin,
                def_dir,
                voxel_index
            );

        if (light_occlusion > 0) {
            vec4 albedo = unpackUnorm4x8(voxel_materials_visual[uVoxelMaterials[voxel_index]].albedo);
            medium_material = voxel_index;

            if (albedo.a < 1.0) {
                out_radiance.rgb *= albedo.rgb * (1 - albedo.a);
            }
            else {
                out_radiance.rgb *= 0;
                break;
            }

            pos = ray_origin;
        }
        else {
            break;
        }
    }

    return out_radiance;
}

//Compute the incoming light reflecting off a voxel
vec4 computeVoxelLight(
    vec3 ray_origin,
    vec3 ray_direction,
    vec3 out_ray_origin,
    vec3 out_ray_direction,
    float ray_cast_t,
    //TODO: just sample this on the fly
    uint voxel_index,
    uint medium_material
) {
    vec3 normal = -out_ray_direction * sign(ray_direction);
    vec3 pos = ray_origin + ray_direction * ray_cast_t;
    vec3 uvw = pos - out_ray_origin;

    vec2 uv = vec2(dot(out_ray_direction.yzx, uvw), dot(out_ray_direction.zxy, uvw));

    float voxel_deviation = float(out_deviation_buffer[voxel_index]) / 255;

    float position_variation = (voxel_deviation) * 0.1;
    vec4 raw_color = unpackUnorm4x8(voxel_materials_visual[uVoxelMaterials[voxel_index]].albedo);

    vec4 albedo_vec4 = vec4(0.5 * (raw_color.rgb + raw_color.rgb * position_variation), raw_color.a) + vec4(spectrum(uVoxelTemperatures[voxel_index]), 0);
    vec3 albedo = albedo_vec4.xyz;

    uint roughness_metalness_packed = voxel_materials_visual[uVoxelMaterials[voxel_index]].roughness_metalness;
    vec4 roughness_metalness = unpackUnorm4x8(roughness_metalness_packed);
    float roughness = roughness_metalness.r + position_variation * 1;
    float metallic = roughness_metalness.g + position_variation * 1;

    vec3 F0 = vec3(0.04);
    F0 = mix(F0, albedo, metallic);

    vec3 out_radiance = vec3(0);

    for (int i = 0; i < point_lights.length(); i++) {
        PointLight point_light = point_lights[i];
        vec3 light_pos = point_light.position;

        vec3 displacement_to_light = light_pos - pos;
        vec3 dir_to_light = normalize(displacement_to_light);

        vec3 light_radiance = computeLightRadiance(
                point_light,
                pos,
                dir_to_light,
                medium_material
            );

        //Dodgy
        vec3 V = normalize(-ray_direction);

        vec3 H = normalize(V + dir_to_light);
        float distance_to_light_sqr = dot(displacement_to_light, displacement_to_light);
        float attentuation = 1.0 / (distance_to_light_sqr);

        vec3 radiance = light_radiance * attentuation;

        // cook-torrance brdf
        float NDF = DistributionGGX(normal, H, roughness);
        float G = GeometrySmith(normal, V, dir_to_light, roughness);
        vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

        vec3 kS = F;
        vec3 kD = vec3(1.0) - kS;
        kD *= 1.0 - metallic;

        vec3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(normal, ray_direction), 0.0) * max(dot(normal, dir_to_light), 0.0) + 0.0001;
        vec3 specular = numerator / denominator;

        // add to outgoing radiance Lo
        float NdotL = max(dot(normal, displacement_to_light), 0.0);

        out_radiance += (kD * albedo / PI + specular) * radiance * NdotL;
    }

    vec3 ambient = vec3(0.03) * albedo;
    vec3 final_radiance = ambient + out_radiance;

    return vec4(final_radiance, albedo_vec4.a);
}

const float positive_infinity = 1.0 / 0.0;

vec2 intersection(vec3 ray_origin, vec3 ray_dir, vec3 box_min, vec3 box_max) {
    float tmin = 0.0, tmax = positive_infinity;

    for (int d = 0; d < 3; ++d) {
        float t1 = (box_min[d] - ray_origin[d]) / ray_dir[d];
        float t2 = (box_max[d] - ray_origin[d]) / ray_dir[d];

        tmin = min(max(t1, tmin), max(t2, tmin));
        tmax = max(min(t1, tmax), min(t2, tmax));
    }

    return vec2(tmin, tmax);
}

vec2 intersectAABB(vec3 rayOrigin, vec3 rayDir, vec3 boxMin, vec3 boxMax) {
    vec3 tMin = (boxMin - rayOrigin) / rayDir;
    vec3 tMax = (boxMax - rayOrigin) / rayDir;
    vec3 t1 = min(tMin, tMax);
    vec3 t2 = max(tMin, tMax);
    float tNear = max(max(t1.x, t1.y), t1.z);
    float tFar = min(min(t2.x, t2.y), t2.z);
    return vec2(tNear, tFar);
};

void main()
{
    vec3 vos;
    vec3 dir;
    uint voxel_index;

    vec3 eye = vIn.eye;
    vec3 end_pos = vIn.position;

    if (true) {
        //eye = vec3(inverse(uProjection * uView * uModel) * vec4(gl_FragCoord.x, gl_FragCoord.y, 0, 1));
    }

    vec3 ray_origin = eye;
    vec3 ray_end = end_pos;

    vec3 ray_direction = normalize(ray_end - ray_origin);

    vec2 box_intersection = intersection(ray_origin, ray_direction, vec3(0), uSize);

    uint medium_material = 0;

    if (!isInBoundsInclusive(ivec3(ray_origin))) {
        ray_origin += ray_direction * box_intersection.x;
    }
    else {
        uint start_index = uvec3(ray_origin).x + uSize.x * uvec3(ray_origin).y + uSize.x * uSize.y * uvec3(ray_origin).z;
        medium_material = uVoxelMaterials[start_index];
    }

    vec4 total_radiance = vec4(0);
    bool hit = false;
    vec3 hit_position = vec3(0);
    float refractive_index = 1;

    for (int i = 0; i < 10; i++) {
        float ray_cast_t = raycast(
                medium_material,
                ray_origin,
                ray_direction,
                vos,
                dir,
                voxel_index
            );

        if (ray_cast_t > 0) {
            vec3 normal = -dir * sign(ray_direction);
            vec3 pos = ray_origin + ray_direction * ray_cast_t;

            hit_position = pos;

            vec4 voxel_radiance = computeVoxelLight(
                    ray_origin,
                    ray_direction,
                    vos,
                    dir,
                    ray_cast_t,
                    voxel_index,
                    medium_material
                );

            if (!isInBoundsInclusive(ivec3(vos))) {
                break;
            }

            hit = true;

            vec3 reflected_dir = reflect(ray_direction, normal);

            float reflectivity = voxel_materials_visual[uVoxelMaterials[voxel_index]].reflectivity;

            if (reflectivity > 0) {
                float t = raycast(
                        medium_material,
                        pos,
                        normalize(reflected_dir),
                        vos,
                        dir,
                        voxel_index
                    );

                //sky colour
                vec4 reflected_material = unpackUnorm4x8(0xFF9B7C70);

                vec2 env_map_uv = SampleSphericalMap(normalize(reflected_dir));
                reflected_material = texture(environment_map, env_map_uv);

                if (t > 0) {
                    reflected_material = computeVoxelLight(
                            pos,
                            normalize(reflected_dir),
                            vos,
                            dir,
                            t,
                            voxel_index,
                            medium_material
                        );
                }

                voxel_radiance.xyz += reflected_material.xyz;
            }

            total_radiance += voxel_radiance * (1 - total_radiance.a);

            medium_material = uVoxelMaterials[voxel_index];
            ray_origin = pos;

            if (voxel_radiance.a >= 1) {
                break;
            }
            else {
                //Refraction
                ray_direction = refract(ray_direction, normal, refractive_index / voxel_materials_visual[medium_material].refractive_index);
                refractive_index = voxel_materials_visual[medium_material].refractive_index;
            }
        }
        else {
            vec2 env_map_uv = SampleSphericalMap(normalize(ray_direction));
            total_radiance += texture(environment_map, env_map_uv);
            break;
        }
    }

    if (hit) {
        aColor.xyz = total_radiance.xyz / (total_radiance.xyz + vec3(1));
        aColor.xyz = pow(aColor.xyz, vec3(1.0 / 2.2));
        aColor.a = 1;

        vec4 clip_pos = uProjection * uView * uModel * vec4(hit_position, 1);
        float ndc_z = clip_pos.z / clip_pos.w;

        gl_FragDepth = (ndc_z + 1.0f) / 2.0f;
    }
}
