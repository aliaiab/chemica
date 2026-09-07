layout(binding = 0, r16ui) uniform restrict uimage3D voxel_bit_buffer_texture;
layout(binding = 1, r32ui) uniform restrict uimage3D voxel_chunk_allocations_image;
//Stores positions as linearized indicies into the flat space of the voxel bit buffer image
layout(binding = 2, r32ui) uniform restrict uimage3D voxel_chunk_positions_image;
layout(binding = 3, r32ui) uniform restrict uimage3D voxel_temperature_image;
layout(binding = 4, r8ui) uniform restrict uimage3D voxel_deviation_image;
layout(binding = 5) uniform usampler3D voxel_bit_buffer_sampler;
layout(binding = 6) uniform usampler3D voxel_chunk_positions_sampler;
layout(binding = 7) uniform sampler3D voxel_temperature_sampler;
layout(binding = 8) uniform isampler3D voxel_deviation_sampler;
layout(binding = 9) uniform sampler2D environment_fetchVoxel;
