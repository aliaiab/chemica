

#ifndef CAROL_API
#define CAROL_API

#define f32 float
#define u8 unsigned char
#define u32 unsigned int
#define u64 long unsigned int

typedef enum
{
    CPU,
    DEVICE,
    DEVICE_CPU_WRITABLE,
    READBACK,
} CrlMemoryType;

typedef enum
{
    CRL_MEMORY_DOMAIN_CPU,
    CRL_MEMORY_DOMAIN_GPU,
} CrlMemoryDomain;

typedef enum
{
} CrlQueue;

typedef enum
{
} CrlStateCull;

typedef enum
{
} CrlStatePolygonMode;

typedef struct
{
} CrlStateDepthStencil;

typedef struct
{
} CrlStateBlend;

typedef struct CrlStateRasterization
{
};

typedef struct CrlTextureDescription
{
};

typedef struct CrlRasterPipelineDescription
{
};

typedef struct CrlMemorySlice
{
    u8 *ptr;
    u64 len;
};

typedef struct CrlTextureDescriptor
{
    u64 value[4];
};

#define CrlCommandBuffer void
#define CrlPipeline void
#define CrlSemaphore void
#define CrlSwapchain void

void crlSelectDevice(void);
void crlFreeDevice(void);
void *crlMemAlloc(u64 size, u64 alignment, CrlMemoryType memory_type);
void crlMemFree(void *memory);
void *crlMemToAccessiblePointer(void *memory, CrlMemoryDomain memory_domain);
void crlMemCopyToTexture(CrlCommandBuffer *command_buffer, void *dest_slice,
                         CrlMemorySlice dest, CrlMemorySlice src);
void crlMemClearTexture(CrlCommandBuffer *command_buffer, CrlMemorySlice dest,
                        CrlMemorySlice src);
CrlPipeline *crlCreateComputePipeline(CrlMemorySlice compute_ir);
CrlPipeline *
crlCreateRasterVertexPipeline(CrlMemorySlice vertex_ir,
                              CrlMemorySlice fragment_ir,
                              CrlRasterPipelineDescription description);
CrlPipeline *
crlCreateRasterMeshPipeline(CrlMemorySlice mesh_ir, CrlMemorySlice fragment_ir,
                            CrlRasterPipelineDescription description);
CrlPipeline *crlCreateRayTracingPipeline(void);
void crlFreePipeline(CrlPipeline *pipeline);
void crlTextureMemoryDescription(CrlTextureDescription description);
void crlSamplerHeapMemoryDescription(CrlTextureDescription description);
void crlFormatTextureMemory(CrlMemorySlice memory);
void crlFormatAccelerationStructureMemory(CrlMemorySlice memory);
void crlUnformatTextureMemory(CrlMemorySlice memory);
void crlUnformatAccelerationStructureMemory(CrlMemorySlice memory);
void crlCreateTextureDescriptor(void *texture_memory,
                                CrlTextureDescriptor *out_descriptor);
void crlCreateTextureSliceDescriptor(void *texture_memory,
                                     CrlTextureDescriptor *out_descriptor);
void crlCreateTextureSamplerDescriptor(void *texture_memory,
                                       CrlTextureDescriptor *out_descriptor);
void crlSetStateDepthStencil(CrlCommandBuffer *command_buffer,
                             CrlStateDepthStencil state);
void crlSetStateBlend(CrlCommandBuffer *command_buffer, CrlStateBlend state);
void crlSetStateRasterization(CrlCommandBuffer *command_buffer,
                              CrlStateRasterization state);
void crlSetStateCull(CrlCommandBuffer *command_buffer, CrlStateCull state);
void crlSetStatePolygonMode(CrlCommandBuffer *command_buffer,
                            CrlStatePolygonMode state);
void crlSetStateViewport(CrlCommandBuffer *command_buffer, const f32 *state);
void crlSetStateScissor(CrlCommandBuffer *command_buffer, const u32 *state);
void crlBarrier(CrlCommandBuffer *command_buffer);
void crlRasterPassBegin(CrlCommandBuffer *command_buffer);
void crlRasterPassEnd(CrlCommandBuffer *command_buffer);
void crlLaunchCompute(CrlCommandBuffer *command_buffer, CrlPipeline *pipeline,
                      CrlMemorySlice root_arguments, CrlMemorySlice commands);
void crlLaunchRasterDraw(CrlCommandBuffer *command_buffer,
                         CrlPipeline *pipeline, CrlMemorySlice root_arguments,
                         CrlMemorySlice commands);
void crlLaunchRasterDrawIndexed(CrlCommandBuffer *command_buffer,
                                CrlPipeline *pipeline,
                                CrlMemorySlice root_arguments,
                                CrlMemorySlice commands);
void crlLaunchRasterDrawMeshes(CrlCommandBuffer *command_buffer,
                               CrlMemorySlice root_arguments,
                               CrlMemorySlice commands);
void crlLaunchTraceRays(CrlCommandBuffer *command_buffer,
                        CrlMemorySlice root_arguments, CrlMemorySlice commands);
void crlLaunchBuildAccelerationStructures(CrlCommandBuffer *command_buffer,
                                          CrlMemorySlice commands);
void crlLaunchCommandSequences(CrlCommandBuffer *command_buffer);
CrlCommandBuffer *crlStartCommandRecording(CrlQueue queue);
void crlQueueSubmit(CrlQueue queue, CrlCommandBuffer *command_buffer);
void crlCommandsAddSignalSemaphore(CrlSemaphore *semaphore, u64 signal_value);
void crlWaitIdle(void);
void crlQueueWaitIdle(CrlQueue queue);
void crlCreateSemaphore(u64 initial_value);
void crlFreeSemaphore(CrlSemaphore *semaphore);
void crlSemaphoreWait(CrlSemaphore *semaphore, u64 wait_value);
u64 crlSemaphoreValue(CrlSemaphore *semaphore);
CrlSwapchain *crlCreateSwapchain(void *platform_surface);
void crlFreeSwapchain(CrlSwapchain *swapchain);
void *crlSwapchainObtainTexture(CrlSwapchain *swapchain);
void crlSwapchainPresent(CrlSwapchain *swapchain,
                         CrlSemaphore *signal_semaphore,
                         u64 signal_semaphore_value);

#endif
