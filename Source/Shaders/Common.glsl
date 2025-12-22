
#define VOXEL_PHASE_SOLID 0
#define VOXEL_PHASE_LIQUID 1
#define VOXEL_PHASE_GAS 2

//TODO: Make material data SOA/data oriented
struct VoxelMaterial
{
    uint color;
    uint density;
    float heat_conductivity;
    float heat_capacity;
    float melting_point;
    float boiling_point;
    float reflectivity;
};

struct Voxel
{
    uint type;
    float temperature;
    //TODO: just use int8_t here
    int deviation;
};

struct RigidTransform {
    //TODO: store inverse position, inverse rotation and inverse scale(maybe)
    vec3 position;
    float uniform_scale;
    //Quaternion rotation
    vec4 rotation;
};

layout(std140, binding = 0) uniform Uniforms
{
    //Rendering Parameters
    mat4 uModel;
    mat4 uView;
    mat4 uProjection;

    //Simulation Parameters
    uvec3 uSize;
    ivec3 uBaseVelocity;
    uint substep_index;

    //CSG parameters
    RigidTransform root_transform;
    ivec3 csg_bounding_min;
    ivec3 csg_bounding_max;
    float delta_time;
    uvec2 window_size;
};

bool isInBounds(ivec3 position) {
    return all(greaterThanEqual(position, ivec3(0))) && all(lessThan(position, uSize));
}

bool isInBoundsInclusive(ivec3 position) {
    return all(greaterThanEqual(position, ivec3(0))) && all(lessThanEqual(position, uSize));
}

bool isInBlock(ivec3 local_position) {
    return all(greaterThanEqual(local_position, ivec3(0))) && all(lessThan(local_position, ivec3(2)));
}
