//! Metal error types

pub const MetalError = error{
    DeviceNotFound,
    LibraryCreationFailed,
    FunctionNotFound,
    PipelineCreationFailed,
    BufferCreationFailed,
    TextureCreationFailed,
    CommandBufferCreationFailed,
    ShaderCompilationFailed,
};
