pub const PhysicalDeviceVulkan11Features = extern struct {
    s_type: StructureType = .physical_device_vulkan_1_1_features,
    p_next: ?*anyopaque = null,
    storage_buffer_16_bit_access: Bool32 = .false,
    uniform_and_storage_buffer_16_bit_access: Bool32 = .false,
    storage_push_constant_16: Bool32 = .false,
    storage_input_output_16: Bool32 = .false,
    multiview: Bool32 = .false,
    multiview_geometry_shader: Bool32 = .false,
    multiview_tessellation_shader: Bool32 = .false,
    variable_pointers_storage_buffer: Bool32 = .false,
    variable_pointers: Bool32 = .false,
    protected_memory: Bool32 = .false,
    sampler_ycbcr_conversion: Bool32 = .false,
    shader_draw_parameters: Bool32 = .false,
};

pub const PhysicalDeviceVulkan12Features = extern struct {
    s_type: StructureType = .physical_device_vulkan_1_2_features,
    p_next: ?*anyopaque = null,
    sampler_mirror_clamp_to_edge: Bool32 = .false,
    draw_indirect_count: Bool32 = .false,
    storage_buffer_8_bit_access: Bool32 = .false,
    uniform_and_storage_buffer_8_bit_access: Bool32 = .false,
    storage_push_constant_8: Bool32 = .false,
    shader_buffer_int_64_atomics: Bool32 = .false,
    shader_shared_int_64_atomics: Bool32 = .false,
    shader_float_16: Bool32 = .false,
    shader_int_8: Bool32 = .false,
    descriptor_indexing: Bool32 = .false,
    shader_input_attachment_array_dynamic_indexing: Bool32 = .false,
    shader_uniform_texel_buffer_array_dynamic_indexing: Bool32 = .false,
    shader_storage_texel_buffer_array_dynamic_indexing: Bool32 = .false,
    shader_uniform_buffer_array_non_uniform_indexing: Bool32 = .false,
    shader_sampled_image_array_non_uniform_indexing: Bool32 = .false,
    shader_storage_buffer_array_non_uniform_indexing: Bool32 = .false,
    shader_storage_image_array_non_uniform_indexing: Bool32 = .false,
    shader_input_attachment_array_non_uniform_indexing: Bool32 = .false,
    shader_uniform_texel_buffer_array_non_uniform_indexing: Bool32 = .false,
    shader_storage_texel_buffer_array_non_uniform_indexing: Bool32 = .false,
    descriptor_binding_uniform_buffer_update_after_bind: Bool32 = .false,
    descriptor_binding_sampled_image_update_after_bind: Bool32 = .false,
    descriptor_binding_storage_image_update_after_bind: Bool32 = .false,
    descriptor_binding_storage_buffer_update_after_bind: Bool32 = .false,
    descriptor_binding_uniform_texel_buffer_update_after_bind: Bool32 = .false,
    descriptor_binding_storage_texel_buffer_update_after_bind: Bool32 = .false,
    descriptor_binding_update_unused_while_pending: Bool32 = .false,
    descriptor_binding_partially_bound: Bool32 = .false,
    descriptor_binding_variable_descriptor_count: Bool32 = .false,
    runtime_descriptor_array: Bool32 = .false,
    sampler_filter_minmax: Bool32 = .false,
    scalar_block_layout: Bool32 = .false,
    imageless_framebuffer: Bool32 = .false,
    uniform_buffer_standard_layout: Bool32 = .false,
    shader_subgroup_extended_types: Bool32 = .false,
    separate_depth_stencil_layouts: Bool32 = .false,
    host_query_reset: Bool32 = .false,
    timeline_semaphore: Bool32 = .false,
    buffer_device_address: Bool32 = .false,
    buffer_device_address_capture_replay: Bool32 = .false,
    buffer_device_address_multi_device: Bool32 = .false,
    vulkan_memory_model: Bool32 = .false,
    vulkan_memory_model_device_scope: Bool32 = .false,
    vulkan_memory_model_availability_visibility_chains: Bool32 = .false,
    shader_output_viewport_index: Bool32 = .false,
    shader_output_layer: Bool32 = .false,
    subgroup_broadcast_dynamic_id: Bool32 = .false,
};

pub const PhysicalDeviceVulkan13Features = extern struct {
    s_type: StructureType = .physical_device_vulkan_1_3_features,
    p_next: ?*anyopaque = null,
    robust_image_access: Bool32 = .false,
    inline_uniform_block: Bool32 = .false,
    descriptor_binding_inline_uniform_block_update_after_bind: Bool32 = .false,
    pipeline_creation_cache_control: Bool32 = .false,
    private_data: Bool32 = .false,
    shader_demote_to_helper_invocation: Bool32 = .false,
    shader_terminate_invocation: Bool32 = .false,
    subgroup_size_control: Bool32 = .false,
    compute_full_subgroups: Bool32 = .false,
    synchronization_2: Bool32 = .false,
    texture_compression_astc_hdr: Bool32 = .false,
    shader_zero_initialize_workgroup_memory: Bool32 = .false,
    dynamic_rendering: Bool32 = .false,
    shader_integer_dot_product: Bool32 = .false,
    maintenance_4: Bool32 = .false,
};

pub const PhysicalDeviceDescriptorHeapFeaturesEXT = extern struct {
    s_type: StructureType = .physical_device_descriptor_heap_features_ext,
    p_next: ?*anyopaque = null,
    descriptor_heap: Bool32 = .false,
    descriptor_heap_capture_replay: Bool32 = .false,
};

pub const PhysicalDeviceExtendedDynamicState2FeaturesEXT = extern struct {
    s_type: StructureType = .physical_device_extended_dynamic_state_2_features_ext,
    p_next: ?*anyopaque = null,
    extended_dynamic_state_2: Bool32 = .false,
    extended_dynamic_state_2_logic_op: Bool32 = .false,
    extended_dynamic_state_2_patch_control_points: Bool32 = .false,
};

pub const PhysicalDeviceExtendedDynamicState3FeaturesEXT = extern struct {
    s_type: StructureType = .physical_device_extended_dynamic_state_3_features_ext,
    p_next: ?*anyopaque = null,
    extended_dynamic_state_3_tessellation_domain_origin: Bool32 = .false,
    extended_dynamic_state_3_depth_clamp_enable: Bool32 = .false,
    extended_dynamic_state_3_polygon_mode: Bool32 = .false,
    extended_dynamic_state_3_rasterization_samples: Bool32 = .false,
    extended_dynamic_state_3_sample_mask: Bool32 = .false,
    extended_dynamic_state_3_alpha_to_coverage_enable: Bool32 = .false,
    extended_dynamic_state_3_alpha_to_one_enable: Bool32 = .false,
    extended_dynamic_state_3_logic_op_enable: Bool32 = .false,
    extended_dynamic_state_3_color_blend_enable: Bool32 = .false,
    extended_dynamic_state_3_color_blend_equation: Bool32 = .false,
    extended_dynamic_state_3_color_write_mask: Bool32 = .false,
    extended_dynamic_state_3_rasterization_stream: Bool32 = .false,
    extended_dynamic_state_3_conservative_rasterization_mode: Bool32 = .false,
    extended_dynamic_state_3_extra_primitive_overestimation_size: Bool32 = .false,
    extended_dynamic_state_3_depth_clip_enable: Bool32 = .false,
    extended_dynamic_state_3_sample_locations_enable: Bool32 = .false,
    extended_dynamic_state_3_color_blend_advanced: Bool32 = .false,
    extended_dynamic_state_3_provoking_vertex_mode: Bool32 = .false,
    extended_dynamic_state_3_line_rasterization_mode: Bool32 = .false,
    extended_dynamic_state_3_line_stipple_enable: Bool32 = .false,
    extended_dynamic_state_3_depth_clip_negative_one_to_one: Bool32 = .false,
    extended_dynamic_state_3_viewport_w_scaling_enable: Bool32 = .false,
    extended_dynamic_state_3_viewport_swizzle: Bool32 = .false,
    extended_dynamic_state_3_coverage_to_color_enable: Bool32 = .false,
    extended_dynamic_state_3_coverage_to_color_location: Bool32 = .false,
    extended_dynamic_state_3_coverage_modulation_mode: Bool32 = .false,
    extended_dynamic_state_3_coverage_modulation_table_enable: Bool32 = .false,
    extended_dynamic_state_3_coverage_modulation_table: Bool32 = .false,
    extended_dynamic_state_3_coverage_reduction_mode: Bool32 = .false,
    extended_dynamic_state_3_representative_fragment_test_enable: Bool32 = .false,
    extended_dynamic_state_3_shading_rate_image_enable: Bool32 = .false,
};

pub const PhysicalDeviceFeatures = extern struct {
    robust_buffer_access: Bool32 = .false,
    full_draw_index_uint_32: Bool32 = .false,
    image_cube_array: Bool32 = .false,
    independent_blend: Bool32 = .false,
    geometry_shader: Bool32 = .false,
    tessellation_shader: Bool32 = .false,
    sample_rate_shading: Bool32 = .false,
    dual_src_blend: Bool32 = .false,
    logic_op: Bool32 = .false,
    multi_draw_indirect: Bool32 = .false,
    draw_indirect_first_instance: Bool32 = .false,
    depth_clamp: Bool32 = .false,
    depth_bias_clamp: Bool32 = .false,
    fill_mode_non_solid: Bool32 = .false,
    depth_bounds: Bool32 = .false,
    wide_lines: Bool32 = .false,
    large_points: Bool32 = .false,
    alpha_to_one: Bool32 = .false,
    multi_viewport: Bool32 = .false,
    sampler_anisotropy: Bool32 = .false,
    texture_compression_etc2: Bool32 = .false,
    texture_compression_astc_ldr: Bool32 = .false,
    texture_compression_bc: Bool32 = .false,
    occlusion_query_precise: Bool32 = .false,
    pipeline_statistics_query: Bool32 = .false,
    vertex_pipeline_stores_and_atomics: Bool32 = .false,
    fragment_stores_and_atomics: Bool32 = .false,
    shader_tessellation_and_geometry_point_size: Bool32 = .false,
    shader_image_gather_extended: Bool32 = .false,
    shader_storage_image_extended_formats: Bool32 = .false,
    shader_storage_image_multisample: Bool32 = .false,
    shader_storage_image_read_without_format: Bool32 = .false,
    shader_storage_image_write_without_format: Bool32 = .false,
    shader_uniform_buffer_array_dynamic_indexing: Bool32 = .false,
    shader_sampled_image_array_dynamic_indexing: Bool32 = .false,
    shader_storage_buffer_array_dynamic_indexing: Bool32 = .false,
    shader_storage_image_array_dynamic_indexing: Bool32 = .false,
    shader_clip_distance: Bool32 = .false,
    shader_cull_distance: Bool32 = .false,
    shader_float_64: Bool32 = .false,
    shader_int_64: Bool32 = .false,
    shader_int_16: Bool32 = .false,
    shader_resource_residency: Bool32 = .false,
    shader_resource_min_lod: Bool32 = .false,
    sparse_binding: Bool32 = .false,
    sparse_residency_buffer: Bool32 = .false,
    sparse_residency_image_2d: Bool32 = .false,
    sparse_residency_image_3d: Bool32 = .false,
    sparse_residency_2_samples: Bool32 = .false,
    sparse_residency_4_samples: Bool32 = .false,
    sparse_residency_8_samples: Bool32 = .false,
    sparse_residency_16_samples: Bool32 = .false,
    sparse_residency_aliased: Bool32 = .false,
    variable_multisample_rate: Bool32 = .false,
    inherited_queries: Bool32 = .false,
};

pub const PhysicalDeviceSwapchainMaintenance1FeaturesKHR = extern struct {
    s_type: StructureType = .physical_device_swapchain_maintenance_1_features_khr,
    p_next: ?*anyopaque = null,
    swapchain_maintenance_1: Bool32 = .false,
};

pub const PhysicalDeviceMutableDescriptorTypeFeaturesEXT = extern struct {
    s_type: StructureType = .physical_device_mutable_descriptor_type_features_ext,
    p_next: ?*anyopaque = null,
    mutable_descriptor_type: Bool32 = .false,
};

pub const DeviceQueueCreateInfo = extern struct {
    s_type: StructureType = .device_queue_create_info,
    p_next: ?*const anyopaque = null,
    flags: DeviceQueueCreateFlags = .{},
    queue_family_index: u32,
    queue_count: u32,
    p_queue_priorities: [*]const f32,
};

pub const Flags = u32;

pub const DeviceQueueCreateFlags = packed struct(Flags) {
    protected: bool = false,
    _reserved_bit_1: bool = false,
    internally_synchronized_khr: bool = false,
    _reserved_bit_3: bool = false,
    _reserved_bit_4: bool = false,
    _reserved_bit_5: bool = false,
    _reserved_bit_6: bool = false,
    _reserved_bit_7: bool = false,
    _reserved_bit_8: bool = false,
    _reserved_bit_9: bool = false,
    _reserved_bit_10: bool = false,
    _reserved_bit_11: bool = false,
    _reserved_bit_12: bool = false,
    _reserved_bit_13: bool = false,
    _reserved_bit_14: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    _reserved_bit_19: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const Bool32 = enum(u32) {
    false,
    true,
};

pub const DescriptorSetLayoutBindingFlagsCreateInfo = extern struct {
    s_type: StructureType = .descriptor_set_layout_binding_flags_create_info,
    p_next: ?*const anyopaque = null,
    binding_count: u32 = 0,
    p_binding_flags: ?[*]const DescriptorBindingFlags = null,
};

pub const DescriptorBindingFlags = packed struct(Flags) {
    update_after_bind: bool = false,
    update_unused_while_pending: bool = false,
    partially_bound: bool = false,
    variable_descriptor_count: bool = false,
    _reserved_bit_4: bool = false,
    _reserved_bit_5: bool = false,
    _reserved_bit_6: bool = false,
    _reserved_bit_7: bool = false,
    _reserved_bit_8: bool = false,
    _reserved_bit_9: bool = false,
    _reserved_bit_10: bool = false,
    _reserved_bit_11: bool = false,
    _reserved_bit_12: bool = false,
    _reserved_bit_13: bool = false,
    _reserved_bit_14: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    _reserved_bit_19: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const MutableDescriptorTypeCreateInfoEXT = extern struct {
    s_type: StructureType = .mutable_descriptor_type_create_info_ext,
    p_next: ?*const anyopaque = null,
    mutable_descriptor_type_list_count: u32 = 0,
    p_mutable_descriptor_type_lists: ?[*]const MutableDescriptorTypeListEXT = null,
};

pub const MutableDescriptorTypeListEXT = extern struct {
    descriptor_type_count: u32 = 0,
    p_descriptor_types: ?[*]const DescriptorType = null,
};

pub const DescriptorType = enum(c_int) {
    sampler = 0,
    combined_image_sampler = 1,
    sampled_image = 2,
    storage_image = 3,
    uniform_texel_buffer = 4,
    storage_texel_buffer = 5,
    uniform_buffer = 6,
    storage_buffer = 7,
    uniform_buffer_dynamic = 8,
    storage_buffer_dynamic = 9,
    input_attachment = 10,
    inline_uniform_block = 1000138000,
    acceleration_structure_khr = 1000150000,
    acceleration_structure_nv = 1000165000,
    sample_weight_image_qcom = 1000440000,
    block_match_image_qcom = 1000440001,
    tensor_arm = 1000460000,
    mutable_ext = 1000351000,
    partitioned_acceleration_structure_nv = 1000570000,
    _,
};

pub const DescriptorSetLayoutBinding = extern struct {
    binding: u32,
    descriptor_type: DescriptorType,
    descriptor_count: u32 = 0,
    stage_flags: ShaderStageFlags,
    p_immutable_samplers: ?[*]const Sampler = null,
};

pub const ImageViewType = enum(c_int) {
    @"1d" = 0,
    @"2d" = 1,
    @"3d" = 2,
    cube = 3,
    @"1d_array" = 4,
    @"2d_array" = 5,
    cube_array = 6,
    _,
};

pub const ImageCreateInfo = extern struct {
    s_type: StructureType = .image_create_info,
    p_next: ?*const anyopaque = null,
    /// Image creation flags
    flags: ImageCreateFlags = .{},
    image_type: ImageType,
    format: Format,
    extent: Extent3D,
    mip_levels: u32,
    array_layers: u32,
    samples: SampleCountFlags,
    tiling: ImageTiling,
    /// Image usage flags
    usage: ImageUsageFlags,
    /// Cross-queue-family sharing mode
    sharing_mode: SharingMode,
    /// Number of queue families to share across
    queue_family_index_count: u32 = 0,
    /// Array of queue family indices to share across
    p_queue_family_indices: ?[*]const u32 = null,
    /// Initial image layout for all subresources
    initial_layout: ImageLayout,
};

pub const ImageCreateFlags = packed struct(Flags) {
    sparse_binding: bool = false,
    sparse_residency: bool = false,
    sparse_aliased: bool = false,
    mutable_format: bool = false,
    cube_compatible: bool = false,
    @"2d_array_compatible": bool = false,
    split_instance_bind_regions: bool = false,
    block_texel_view_compatible: bool = false,
    extended_usage: bool = false,
    disjoint: bool = false,
    alias: bool = false,
    protected: bool = false,
    sample_locations_compatible_depth_ext: bool = false,
    corner_sampled_nv: bool = false,
    subsampled_ext: bool = false,
    fragment_density_map_offset_ext: bool = false,
    descriptor_heap_capture_replay_ext: bool = false,
    @"2d_view_compatible_ext": bool = false,
    multisampled_render_to_single_sampled_ext: bool = false,
    _reserved_bit_19: bool = false,
    video_profile_independent_khr: bool = false,
    _reserved_bit_21: bool = false,
    alias_single_layer_descriptor_khr: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const ImageUsageFlags = packed struct(Flags) {
    /// Can be used as a source of transfer operations
    transfer_src: bool = false,
    /// Can be used as a destination of transfer operations
    transfer_dst: bool = false,
    /// Can be sampled from (SAMPLED_IMAGE and COMBINED_IMAGE_SAMPLER descriptor types)
    sampled: bool = false,
    /// Can be used as storage image (STORAGE_IMAGE descriptor type)
    storage: bool = false,
    /// Can be used as framebuffer color attachment
    color_attachment: bool = false,
    /// Can be used as framebuffer depth/stencil attachment
    depth_stencil_attachment: bool = false,
    /// Image data not needed outside of rendering
    transient_attachment: bool = false,
    /// Can be used as framebuffer input attachment
    input_attachment: bool = false,
    fragment_shading_rate_attachment_khr: bool = false,
    fragment_density_map_ext: bool = false,
    video_decode_dst_khr: bool = false,
    video_decode_src_khr: bool = false,
    video_decode_dpb_khr: bool = false,
    video_encode_dst_khr: bool = false,
    video_encode_src_khr: bool = false,
    video_encode_dpb_khr: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    invocation_mask_huawei: bool = false,
    attachment_feedback_loop_ext: bool = false,
    sample_weight_qcom: bool = false,
    sample_block_match_qcom: bool = false,
    host_transfer: bool = false,
    tensor_aliasing_arm: bool = false,
    _reserved_bit_24: bool = false,
    video_encode_quantization_delta_map_khr: bool = false,
    video_encode_emphasis_map_khr: bool = false,
    tile_memory_qcom: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const Image = enum(u64) { null_handle = 0, _ };
pub const ImageView = enum(u64) { null_handle = 0, _ };
pub const ShaderModule = enum(u64) { null_handle = 0, _ };
pub const Pipeline = enum(u64) { null_handle = 0, _ };
pub const PipelineLayout = enum(u64) { null_handle = 0, _ };
pub const Sampler = enum(u64) { null_handle = 0, _ };

pub const ShaderStageFlags = packed struct(Flags) {
    vertex: bool = false,
    tessellation_control: bool = false,
    tessellation_evaluation: bool = false,
    geometry: bool = false,
    fragment: bool = false,
    compute: bool = false,
    task_ext: bool = false,
    mesh_ext: bool = false,
    raygen_khr: bool = false,
    any_hit_khr: bool = false,
    closest_hit_khr: bool = false,
    miss_khr: bool = false,
    intersection_khr: bool = false,
    callable_khr: bool = false,
    subpass_shading_huawei: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    cluster_culling_huawei: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const BufferDeviceAddressInfo = extern struct {
    s_type: StructureType = .buffer_device_address_info,
    p_next: ?*const anyopaque = null,
    buffer: Buffer,
};

pub const DescriptorSet = enum(u64) { null_handle = 0, _ };
pub const DescriptorSetLayout = enum(u64) { null_handle = 0, _ };
pub const DescriptorPool = enum(u64) { null_handle = 0, _ };
pub const Fence = enum(u64) { null_handle = 0, _ };
pub const Semaphore = enum(u64) { null_handle = 0, _ };
pub const Buffer = enum(u64) { null_handle = 0, _ };
pub const CommandPool = enum(u64) { null_handle = 0, _ };
pub const ShaderModule = enum(u64) { null_handle = 0, _ };

pub const PipelineRenderingCreateInfo = extern struct {
    s_type: StructureType = .pipeline_rendering_create_info,
    p_next: ?*const anyopaque = null,
    view_mask: u32,
    color_attachment_count: u32 = 0,
    p_color_attachment_formats: ?[*]const Format = null,
    depth_attachment_format: Format,
    stencil_attachment_format: Format,
};

pub const RenderingInfo = extern struct {
    s_type: StructureType = .rendering_info,
    p_next: ?*const anyopaque = null,
    flags: RenderingFlags = .{},
    render_area: Rect2D,
    layer_count: u32,
    view_mask: u32,
    color_attachment_count: u32 = 0,
    p_color_attachments: ?[*]const RenderingAttachmentInfo = null,
    p_depth_attachment: ?*const RenderingAttachmentInfo = null,
    p_stencil_attachment: ?*const RenderingAttachmentInfo = null,
};

pub const RenderingAttachmentInfo = extern struct {
    s_type: StructureType = .rendering_attachment_info,
    p_next: ?*const anyopaque = null,
    image_view: ImageView = .null_handle,
    image_layout: ImageLayout,
    resolve_mode: ResolveModeFlags,
    resolve_image_view: ImageView = .null_handle,
    resolve_image_layout: ImageLayout,
    load_op: AttachmentLoadOp,
    store_op: AttachmentStoreOp,
    clear_value: ClearValue,
};

pub const DynamicState = enum(c_int) {
    viewport = 0,
    scissor = 1,
    line_width = 2,
    depth_bias = 3,
    blend_constants = 4,
    depth_bounds = 5,
    stencil_compare_mask = 6,
    stencil_write_mask = 7,
    stencil_reference = 8,
    cull_mode = 1000267000,
    front_face = 1000267001,
    primitive_topology = 1000267002,
    viewport_with_count = 1000267003,
    scissor_with_count = 1000267004,
    vertex_input_binding_stride = 1000267005,
    depth_test_enable = 1000267006,
    depth_write_enable = 1000267007,
    depth_compare_op = 1000267008,
    depth_bounds_test_enable = 1000267009,
    stencil_test_enable = 1000267010,
    stencil_op = 1000267011,
    rasterizer_discard_enable = 1000377001,
    depth_bias_enable = 1000377002,
    primitive_restart_enable = 1000377004,
    line_stipple = 1000259000,
    viewport_w_scaling_nv = 1000087000,
    discard_rectangle_ext = 1000099000,
    discard_rectangle_enable_ext = 1000099001,
    discard_rectangle_mode_ext = 1000099002,
    sample_locations_ext = 1000143000,
    ray_tracing_pipeline_stack_size_khr = 1000347000,
    viewport_shading_rate_palette_nv = 1000164004,
    viewport_coarse_sample_order_nv = 1000164006,
    exclusive_scissor_enable_nv = 1000205000,
    exclusive_scissor_nv = 1000205001,
    fragment_shading_rate_khr = 1000226000,
    vertex_input_ext = 1000352000,
    patch_control_points_ext = 1000377000,
    logic_op_ext = 1000377003,
    color_write_enable_ext = 1000381000,
    depth_clamp_enable_ext = 1000455003,
    polygon_mode_ext = 1000455004,
    rasterization_samples_ext = 1000455005,
    sample_mask_ext = 1000455006,
    alpha_to_coverage_enable_ext = 1000455007,
    alpha_to_one_enable_ext = 1000455008,
    logic_op_enable_ext = 1000455009,
    color_blend_enable_ext = 1000455010,
    color_blend_equation_ext = 1000455011,
    color_write_mask_ext = 1000455012,
    tessellation_domain_origin_ext = 1000455002,
    rasterization_stream_ext = 1000455013,
    conservative_rasterization_mode_ext = 1000455014,
    extra_primitive_overestimation_size_ext = 1000455015,
    depth_clip_enable_ext = 1000455016,
    sample_locations_enable_ext = 1000455017,
    color_blend_advanced_ext = 1000455018,
    provoking_vertex_mode_ext = 1000455019,
    line_rasterization_mode_ext = 1000455020,
    line_stipple_enable_ext = 1000455021,
    depth_clip_negative_one_to_one_ext = 1000455022,
    viewport_w_scaling_enable_nv = 1000455023,
    viewport_swizzle_nv = 1000455024,
    coverage_to_color_enable_nv = 1000455025,
    coverage_to_color_location_nv = 1000455026,
    coverage_modulation_mode_nv = 1000455027,
    coverage_modulation_table_enable_nv = 1000455028,
    coverage_modulation_table_nv = 1000455029,
    shading_rate_image_enable_nv = 1000455030,
    representative_fragment_test_enable_nv = 1000455031,
    coverage_reduction_mode_nv = 1000455032,
    attachment_feedback_loop_enable_ext = 1000524000,
    depth_clamp_range_ext = 1000582000,
    _,
};

pub const GraphicsPipelineCreateInfo = extern struct {
    s_type: StructureType = .graphics_pipeline_create_info,
    p_next: ?*const anyopaque = null,
    flags: PipelineCreateFlags = .{},
    stage_count: u32 = 0,
    p_stages: ?[*]const PipelineShaderStageCreateInfo = null,
    p_vertex_input_state: ?*const PipelineVertexInputStateCreateInfo = null,
    p_input_assembly_state: ?*const PipelineInputAssemblyStateCreateInfo = null,
    p_tessellation_state: ?*const PipelineTessellationStateCreateInfo = null,
    p_viewport_state: ?*const PipelineViewportStateCreateInfo = null,
    p_rasterization_state: ?*const PipelineRasterizationStateCreateInfo = null,
    p_multisample_state: ?*const PipelineMultisampleStateCreateInfo = null,
    p_depth_stencil_state: ?*const PipelineDepthStencilStateCreateInfo = null,
    p_color_blend_state: ?*const PipelineColorBlendStateCreateInfo = null,
    p_dynamic_state: ?*const PipelineDynamicStateCreateInfo = null,
    layout: PipelineLayout = .null_handle,
    render_pass: RenderPass = .null_handle,
    subpass: u32,
    base_pipeline_handle: Pipeline = .null_handle,
    base_pipeline_index: i32,
};

pub const ImageMemoryBarrier2 = extern struct {
    s_type: StructureType = .image_memory_barrier_2,
    p_next: ?*const anyopaque = null,
    src_stage_mask: PipelineStageFlags2 = .{},
    src_access_mask: AccessFlags2 = .{},
    dst_stage_mask: PipelineStageFlags2 = .{},
    dst_access_mask: AccessFlags2 = .{},
    old_layout: ImageLayout,
    new_layout: ImageLayout,
    src_queue_family_index: u32,
    dst_queue_family_index: u32,
    image: Image,
    subresource_range: ImageSubresourceRange,
};

pub const DescriptorPoolSize = extern struct {
    type: DescriptorType,
    descriptor_count: u32,
};

pub const DescriptorPoolCreateInfo = extern struct {
    s_type: StructureType = .descriptor_pool_create_info,
    p_next: ?*const anyopaque = null,
    flags: DescriptorPoolCreateFlags = .{},
    max_sets: u32,
    pool_size_count: u32 = 0,
    p_pool_sizes: ?[*]const DescriptorPoolSize = null,
};

pub const DescriptorSetAllocateInfo = extern struct {
    s_type: StructureType = .descriptor_set_allocate_info,
    p_next: ?*const anyopaque = null,
    descriptor_pool: DescriptorPool,
    descriptor_set_count: u32,
    p_set_layouts: [*]const DescriptorSetLayout,
};

pub const PipelineStageFlags = packed struct(Flags) {
    top_of_pipe: bool = false,
    draw_indirect: bool = false,
    vertex_input: bool = false,
    vertex_shader: bool = false,
    tessellation_control_shader: bool = false,
    tessellation_evaluation_shader: bool = false,
    geometry_shader: bool = false,
    fragment_shader: bool = false,
    early_fragment_tests: bool = false,
    late_fragment_tests: bool = false,
    color_attachment_output: bool = false,
    compute_shader: bool = false,
    transfer: bool = false,
    bottom_of_pipe: bool = false,
    host: bool = false,
    all_graphics: bool = false,
    all_commands: bool = false,
    command_preprocess_ext: bool = false,
    conditional_rendering_ext: bool = false,
    task_shader_ext: bool = false,
    mesh_shader_ext: bool = false,
    ray_tracing_shader_khr: bool = false,
    fragment_shading_rate_attachment_khr: bool = false,
    fragment_density_process_ext: bool = false,
    transform_feedback_ext: bool = false,
    acceleration_structure_build_khr: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const AccessFlags = packed struct(Flags) {
    indirect_command_read: bool = false,
    index_read: bool = false,
    vertex_attribute_read: bool = false,
    uniform_read: bool = false,
    input_attachment_read: bool = false,
    shader_read: bool = false,
    shader_write: bool = false,
    color_attachment_read: bool = false,
    color_attachment_write: bool = false,
    depth_stencil_attachment_read: bool = false,
    depth_stencil_attachment_write: bool = false,
    transfer_read: bool = false,
    transfer_write: bool = false,
    host_read: bool = false,
    host_write: bool = false,
    memory_read: bool = false,
    memory_write: bool = false,
    command_preprocess_read_ext: bool = false,
    command_preprocess_write_ext: bool = false,
    color_attachment_read_noncoherent_ext: bool = false,
    conditional_rendering_read_ext: bool = false,
    acceleration_structure_read_khr: bool = false,
    acceleration_structure_write_khr: bool = false,
    fragment_shading_rate_attachment_read_khr: bool = false,
    fragment_density_map_read_ext: bool = false,
    transform_feedback_write_ext: bool = false,
    transform_feedback_counter_read_ext: bool = false,
    transform_feedback_counter_write_ext: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const AttachmentLoadOp = enum(c_int) {
    load = 0,
    clear = 1,
    dont_care = 2,
    none = 1000400000,
    _,
    pub const none_ext = AttachmentLoadOp.none;
    pub const none_khr = AttachmentLoadOp.none;
};

pub const AttachmentStoreOp = enum(c_int) {
    store = 0,
    dont_care = 1,
    none = 1000301000,
    _,
    pub const none_khr = AttachmentStoreOp.none;
    pub const none_qcom = AttachmentStoreOp.none;
    pub const none_ext = AttachmentStoreOp.none;
};

pub const ImageType = enum(c_int) {
    @"1d" = 0,
    @"2d" = 1,
    @"3d" = 2,
    _,
};

pub const CommandBufferAllocateInfo = extern struct {
    s_type: StructureType = .command_buffer_allocate_info,
    p_next: ?*const anyopaque = null,
    command_pool: CommandPool,
    level: CommandBufferLevel,
    command_buffer_count: u32,
};

pub const TimelineSemaphoreSubmitInfo = extern struct {
    s_type: StructureType = .timeline_semaphore_submit_info,
    p_next: ?*const anyopaque = null,
    wait_semaphore_value_count: u32 = 0,
    p_wait_semaphore_values: ?[*]const u64 = null,
    signal_semaphore_value_count: u32 = 0,
    p_signal_semaphore_values: ?[*]const u64 = null,
};

pub const SurfacePresentScalingCapabilitiesKHR = extern struct {
    s_type: StructureType = .surface_present_scaling_capabilities_khr,
    p_next: ?*anyopaque = null,
    supported_present_scaling: PresentScalingFlagsKHR = .{},
    supported_present_gravity_x: PresentGravityFlagsKHR = .{},
    supported_present_gravity_y: PresentGravityFlagsKHR = .{},
    /// Supported minimum image width and height for the surface when scaling is used
    min_scaled_image_extent: Extent2D,
    /// Supported maximum image width and height for the surface when scaling is used
    max_scaled_image_extent: Extent2D,
};

pub const ColorSpaceKHR = enum(c_int) {
    srgb_nonlinear_khr = 0,
    display_p3_nonlinear_ext = 1000104001,
    extended_srgb_linear_ext = 1000104002,
    display_p3_linear_ext = 1000104003,
    dci_p3_nonlinear_ext = 1000104004,
    bt709_linear_ext = 1000104005,
    bt709_nonlinear_ext = 1000104006,
    bt2020_linear_ext = 1000104007,
    hdr10_st2084_ext = 1000104008,
    dolbyvision_ext = 1000104009,
    hdr10_hlg_ext = 1000104010,
    adobergb_linear_ext = 1000104011,
    adobergb_nonlinear_ext = 1000104012,
    pass_through_ext = 1000104013,
    extended_srgb_nonlinear_ext = 1000104014,
    display_native_amd = 1000213000,
    _,
};

pub const PresentModeKHR = enum(c_int) {
    immediate_khr = 0,
    mailbox_khr = 1,
    fifo_khr = 2,
    fifo_relaxed_khr = 3,
    shared_demand_refresh_khr = 1000111000,
    shared_continuous_refresh_khr = 1000111001,
    fifo_latest_ready_khr = 1000361000,
    _,
};

pub const DebugUtilsMessengerCreateInfoEXT = extern struct {
    s_type: StructureType = .debug_utils_messenger_create_info_ext,
    p_next: ?*const anyopaque = null,
    flags: DebugUtilsMessengerCreateFlagsEXT = .{},
    message_severity: DebugUtilsMessageSeverityFlagsEXT,
    message_type: DebugUtilsMessageTypeFlagsEXT,
    pfn_user_callback: PfnDebugUtilsMessengerCallbackEXT,
    p_user_data: ?*anyopaque = null,
};

pub const DebugUtilsMessengerCallbackDataEXT = extern struct {
    s_type: StructureType = .debug_utils_messenger_callback_data_ext,
    p_next: ?*const anyopaque = null,
    flags: DebugUtilsMessengerCallbackDataFlagsEXT = .{},
    p_message_id_name: ?[*:0]const u8 = null,
    message_id_number: i32,
    p_message: ?[*:0]const u8 = null,
    queue_label_count: u32 = 0,
    p_queue_labels: ?[*]const DebugUtilsLabelEXT = null,
    cmd_buf_label_count: u32 = 0,
    p_cmd_buf_labels: ?[*]const DebugUtilsLabelEXT = null,
    object_count: u32 = 0,
    p_objects: ?[*]const DebugUtilsObjectNameInfoEXT = null,
};

pub const DebugUtilsObjectNameInfoEXT = extern struct {
    s_type: StructureType = .debug_utils_object_name_info_ext,
    p_next: ?*const anyopaque = null,
    object_type: ObjectType,
    object_handle: u64,
    p_object_name: ?[*:0]const u8 = null,
};

pub const DebugUtilsLabelEXT = extern struct {
    s_type: StructureType = .debug_utils_label_ext,
    p_next: ?*const anyopaque = null,
    p_label_name: [*:0]const u8,
    color: [4]f32,
};

pub const DebugUtilsMessageSeverityFlagsEXT = packed struct(Flags) {
    verbose_ext: bool = false,
    _reserved_bit_1: bool = false,
    _reserved_bit_2: bool = false,
    _reserved_bit_3: bool = false,
    info_ext: bool = false,
    _reserved_bit_5: bool = false,
    _reserved_bit_6: bool = false,
    _reserved_bit_7: bool = false,
    warning_ext: bool = false,
    _reserved_bit_9: bool = false,
    _reserved_bit_10: bool = false,
    _reserved_bit_11: bool = false,
    error_ext: bool = false,
    _reserved_bit_13: bool = false,
    _reserved_bit_14: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    _reserved_bit_19: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const DebugUtilsMessageTypeFlagsEXT = packed struct(Flags) {
    general_ext: bool = false,
    validation_ext: bool = false,
    performance_ext: bool = false,
    device_address_binding_ext: bool = false,
    _reserved_bit_4: bool = false,
    _reserved_bit_5: bool = false,
    _reserved_bit_6: bool = false,
    _reserved_bit_7: bool = false,
    _reserved_bit_8: bool = false,
    _reserved_bit_9: bool = false,
    _reserved_bit_10: bool = false,
    _reserved_bit_11: bool = false,
    _reserved_bit_12: bool = false,
    _reserved_bit_13: bool = false,
    _reserved_bit_14: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    _reserved_bit_19: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const SampleCountFlags = packed struct(Flags) {
    @"1": bool = false,
    @"2": bool = false,
    @"4": bool = false,
    @"8": bool = false,
    @"16": bool = false,
    @"32": bool = false,
    @"64": bool = false,
    _reserved_bit_7: bool = false,
    _reserved_bit_8: bool = false,
    _reserved_bit_9: bool = false,
    _reserved_bit_10: bool = false,
    _reserved_bit_11: bool = false,
    _reserved_bit_12: bool = false,
    _reserved_bit_13: bool = false,
    _reserved_bit_14: bool = false,
    _reserved_bit_15: bool = false,
    _reserved_bit_16: bool = false,
    _reserved_bit_17: bool = false,
    _reserved_bit_18: bool = false,
    _reserved_bit_19: bool = false,
    _reserved_bit_20: bool = false,
    _reserved_bit_21: bool = false,
    _reserved_bit_22: bool = false,
    _reserved_bit_23: bool = false,
    _reserved_bit_24: bool = false,
    _reserved_bit_25: bool = false,
    _reserved_bit_26: bool = false,
    _reserved_bit_27: bool = false,
    _reserved_bit_28: bool = false,
    _reserved_bit_29: bool = false,
    _reserved_bit_30: bool = false,
    _reserved_bit_31: bool = false,
};

pub const DebugUtilsMessengerCreateFlagsEXT = packed struct(Flags) {
    _reserved_bits: Flags = 0,
};

pub const ImageLayout = enum(c_int) {};

pub const Format = enum(c_int) {};

pub const StructureType = enum(c_int) {};

pub const Version = packed struct(u32) {
    patch: u12,
    minor: u10,
    major: u7,
    variant: u3,
    pub fn toU32(ver: Version) u32 {
        return @bitCast(ver);
    }
};

pub fn makeApiVersion(variant: u3, major: u7, minor: u10, patch: u12) Version {
    return .{ .variant = variant, .major = major, .minor = minor, .patch = patch };
}

pub const ApiInfo = struct {
    name: [:0]const u8 = "custom",
    version: Version = makeApiVersion(0, 0, 0, 0),
};

pub const vulkan_call_conv: std.builtin.CallingConvention = if (builtin.os.tag == .windows and builtin.cpu.arch == .x86)
    .winapi
else if (builtin.abi == .android and (builtin.cpu.arch.isArm() or builtin.cpu.arch.isThumb()) and std.Target.arm.featureSetHas(builtin.cpu.features, .has_v7) and builtin.cpu.arch.ptrBitWidth() == 32)
    // On Android 32-bit ARM targets, Vulkan functions use the "hardfloat"
    // calling convention, i.e. float parameters are passed in registers. This
    // is true even if the rest of the application passes floats on the stack,
    // as it does by default when compiling for the armeabi-v7a NDK ABI.
    .arm_aapcs_vfp
else
    .c;
