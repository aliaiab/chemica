#version 450
#extension GL_GOOGLE_include_directive : enable

#include "Common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 0) readonly buffer Input
{
    float uInput[];
};

layout(std430, binding = 1) readonly buffer VoxelMaterials
{
    uint uVoxelMaterials[];
};

layout(rgba8, binding = 2) uniform image3D uOutput;

float srgbXYZ2RGBPostprocess(float c) 
{
    c = clamp(c, 0, 1);
    
    c = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1. / 2.4) - 0.055;

    return c;
}

vec3 srgbXYZ2RGB(vec3 xyz) 
{
    float rl = 3.2406255 * xyz.x + -1.537208  * xyz.y + -0.4986286 * xyz.z;
    float gl = -0.9689307 * xyz.x +  1.8757561 * xyz.y +  0.0415175 * xyz.z;
    float bl = 0.0557101 * xyz.x + -0.2040211 * xyz.y +  1.0569959 * xyz.z;

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
    float wlm = wavelength * 1e-9;   /* Wavelength in meters */

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

void main()
{
    ivec3 size = ivec3(imageSize(uOutput)); 
    ivec3 position = ivec3(gl_GlobalInvocationID);
    
    int index = position.z * size.x * size.y + position.y * size.x + position.x;

    if (uVoxelMaterials[index] == 0) 
    {
        return;  
    }

    float temperature = uInput[index];

    vec3 color = spectrum(temperature);

    imageStore(uOutput, position, vec4(color, 0.0));                                                                                                                               
}