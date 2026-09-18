instructions: []InstructionRegister,

pub const InstructionRegister = packed struct(u32) {
    op: Opcode,
    register_target: Register,
    register_1: Register,
    register_2: Register,
    register_3: Register,
};

pub const InstructionImmediate = packed struct(u32) {
    op: Opcode,
    register_target: Register,
    immediate: u16,
};

pub const InstructionRegisterBlock = packed struct(u32) {
    op: Opcode,
    register_block: RegisterBlock,
};

pub const InstructionBranch = packed struct(u32) {
    op: Opcode,
    condition: Register,
    target: u16,
};

pub const Register = packed struct(u6) {
    index: u6,
    tag: Tag,

    pub const Tag = enum(u1) {
        scalar,
        vector,
    };
};

pub const RegisterBlock = packed struct(u25) {
    bit_width: BitWidth,
    index: u23,

    pub const BitWidth = enum(u2) {
        @"16",
        @"32",
        @"64",
        mask,
    };
};

pub const Opcode = enum(u8) {
    terminate,
    branch,
    branch_relative,
    proc_call,
    proc_return,
    register_rename,
    register_block,
    register_mask,
    load_immediate_lower,
    load_immediate_upper,
    load8_root_argument,
    load16_root_argument,
    load32_root_argument,
    load64_root_argument,
    load8_input,
    load16_input,
    load32_input,
    load64_input,
    load8,
    load16,
    load32,
    load64,
    store8_output,
    store16_output,
    store32_output,
    store64_output,
    store8,
    store16,
    store32,
    store64,
    compare,
    select,
    addf,
    subf,
    mulf,
    maddf,
    negf,
    divf,
    addi,
    subi,
    muli,
    negi,
    divi,
    mulu,
    divu,
    recipf,
    sqrtf,
    invsqrtf,
    sinf,
    cosf,
    tanf,
    asinf,
    acosf,
    atanf,
    expf,
    logf,
    exp2f,
    log2f,
    quad_derivative_coarse,
    quad_derivative_fine,
    sampler_derivative,
    sampler_coordinates,
    sampler_dimensions,
    sampler_sample,
    sampler_sample_lod,
    sampler_fetch,
    sampler_load,
    sampler_store,
};
