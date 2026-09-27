
#ifndef CAROL_API
#define CAROL_API

#define f32 float
#define f64 double 
#define u8 unsigned char
#define u16 unsigned short 
#define u32 unsigned int
#define u64 long unsigned int

typedef enum
{
    CRL_MEMORY_TYPE_CPU = 0,
    CRL_MEMORY_TYPE_DEVICE = 1,
    CRL_MEMORY_TYPE_DEVICE_CPU_WRITABLE = 2,
    CRL_MEMORY_TYPE_READBACK = 3,
} CrlMemoryType;

typedef enum {
    CRL_MEMORY_FORMAT_UNFORMATTED = 0,
    CRL_MEMORY_FORMAT_TEXTURE = 1,
    CRL_MEMORY_FORMAT_ACCELERATION_STRUCTURE = 2,
} CrlMemoryFormat;

typedef enum
{
    CRL_MEMORY_DOMAIN_CPU = 0,
    CRL_MEMORY_DOMAIN_DEVICE = 1,
} CrlMemoryDomain;

typedef enum
{
} CrlQueue;

#define CRL_QUEUE_DEFAULT 0xff

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

typedef struct 
{
} CrlStateRasterization;

typedef struct 
{
} CrlTextureDescription;

typedef struct 
{
} CrlAccelerationStructureDescription;

typedef struct 
{
} CrlRasterPipelineDescription;

typedef struct 
{
} CrlRasterPassDescription;

typedef struct 
{
    void *ptr;
    u64 len;
} CrlMemorySlice;

typedef struct {
    u64 size;
    u64 alignment;
    CrlMemoryType memory_type;
} CrlResourceDescription;

typedef struct 
{
    u64 value[4];
} CrlTextureDescriptor;

#define CrlCommandBuffer void
#define CrlPipeline void
#define CrlSemaphore void
#define CrlSwapchain void

typedef struct {
    u32 width;
    u32 height;
} CrlSurface;

//Core Device API

//Selects a physical device which can support the api
void crdSelectDevice(void);
//Free the resources associated with the device
void crdFreeDevice(void);
//Allocate memory from the device
//The resulting memory will be of type memory_type, and aligned to alignment 
void *crdMemAlloc(u64 size, u64 alignment, CrlMemoryType memory_type);
//Free device memory
//Unformats any formatted memory regions within the allocation 
void crdMemFree(void *memory);
//Returns the memory type of the pointer
ClrMemoryType crdMemGetMemoryType(void *memory);
//Returns the memory format of the pointer
ClrMemoryFormat crdMemGetMemoryFormat(void *memory);
//Returns a pointer which is readable/writable for the given access domain
void *crdMemToAccessiblePointer(void *memory, CrlMemoryDomain memory_domain);
//Copy device memory from src to dst
void crdMemCopy(CrlCommandBuffer *commands, CrlMemorySlice dest, CrlMemorySlice src);
//Set the memory to the contents of src 
//dest.len must be an integer multiple of src.len
void crdMemSet(CrlCommandBuffer *commands, CrlMemorySlice dest, CrlMemorySlice src);
//Copy device memory from source memory to a destination texture
void crdMemCopyToTexture(CrlCommandBuffer *commands, void *dest_slice, CrlMemorySlice dest, CrlMemorySlice src);
//Set each texel of a texture to the contents src_gpu
void crdMemClearTexture(CrlCommandBuffer *commands, CrlMemorySlice dest, CrlMemorySlice src);
//Create a compute kernel pipeline
CrlPipeline *crdCreateComputePipeline(CrlMemorySlice compute_ir);
//Create a raster pipeline that uses vertex and fragment kernel stages
CrlPipeline *crdCreateRasterVertexPipeline(CrlMemorySlice vertex_ir, CrlMemorySlice fragment_ir, CrlRasterPipelineDescription description);
//Create a raster pipeline that uses mesh and fragment kernel stages
CrlPipeline *crdCreateRasterMeshPipeline(CrlMemorySlice mesh_ir, CrlMemorySlice fragment_ir, CrlRasterPipelineDescription description);
//Create a ray tracing pipeline
CrlPipeline *crdCreateRayTracingPipeline(CrlMemorySlice ir_list);
//Free the pipeline memory
void crdFreePipeline(CrlPipeline *pipeline);
//Returns the size, alignment and memory type for the given texture description
CrlResourceDescription crdTextureMemoryDescription(CrlTextureDescription description);
//Returns the size, alignment and memory type for the given acceleration structure description
CrlResourceDescription crdAccelerationStructureMemoryDescription(CrlTextureDescription description);
//Returns the size, alignment and memory type for the given sampler heap size 
CrlResourceDescription crdSamplerHeapMemoryDescription(u64 size);
//Returns the size, alignment and memory type for the given texture heap size 
CrlResourceDescription crdTextureHeapMemoryDescription(u64 size);
//Formats the specified memory region as a texture
//The specified memory region must be device local memory
//It is then illegal behaviour to directly modify or read the specified memory
void crdFormatTextureMemory(CrlMemorySlice memory, CrlTextureDescription description);
//Formats the specified memory region as an acceleration structure
//The specified memory region must be device local memory
//It is then illegal behaviour to directly modify or read the specified memory
void crdFormatAccelerationStructureMemory(CrlMemorySlice memory, CrlAccelerationStructureDescription description);
//Unformats the specified memory region 
//It is then illegal behaviour to use the memory as formatted
//This is a no-op if memory is unformatted
void crdUnformatMemory(void *memory); 
//Create an opaque texture descriptor. The resulting descriptor is a combined texture sampler
void crdCreateTextureDescriptors(void **textures, CrlTextureDescriptor *out_descriptors, u64 descriptor_count);
//Create an opaque texture descriptor from the texture slice. The resulting descriptor is a combined texture sampler
void crdCreateTextureSliceDescriptors(void **textures, CrlTextureDescriptor *out_descriptors, u64 descriptor_count);
//Create an opaque sampler descriptor from the texture slice. The resulting descriptor is a sampler
void crdCreateTextureSamplerDescriptors(void **textures, CrlTextureDescriptor *out_descriptors, u64 descriptor_count);
//Sets the rasterizer depth and stencil state
void crdSetStateDepthStencil(CrlCommandBuffer *commands, CrlStateDepthStencil state);
//Sets the rasterizer blending state 
void crdSetStateBlend(CrlCommandBuffer *commands, CrlStateBlend state);
//Sets the rasterizer rasterization state 
void crdSetStateRasterization(CrlCommandBuffer *commands, CrlStateRasterization state);
//Sets the rasterizer primitive culling state 
void crdSetStateCull(CrlCommandBuffer *commands, CrlStateCull state);
//Sets the rasterizer polygon mode state 
void crdSetStatePolygonMode(CrlCommandBuffer *commands, CrlStatePolygonMode state);
//Sets the rasterizer viewport transformation state 
void crdSetStateViewportTransform(CrlCommandBuffer *commands, const f32 *state);
//Sets the rasterizer scissor region state 
void crdSetStateScissorRegion(CrlCommandBuffer *commands, const u32 *state);
//Place a synchronisation barrier
void crdBarrier(CrlCommandBuffer *commands);
//Begin a raster pass
void crdRasterPassBegin(CrlCommandBuffer *commands, CrlRasterPassDescription description);
//End a raster pass
void crdRasterPassEnd(CrlCommandBuffer *commands);
//Launch a set of compute commands
void crdLaunchCompute(CrlCommandBuffer *commands, CrlPipeline *pipeline, CrlMemorySlice root_arguments, CrlMemorySlice command_arguments);
//Launch a set of rasterization draw commands using a vertex pipeline
void crdLaunchRasterDraw(CrlCommandBuffer *commands, CrlPipeline *pipeline, CrlMemorySlice root_arguments, CrlMemorySlice command_arguments);
//Launch a set of rasterization draw commands using a vertex pipeline, with indices
void crdLaunchRasterDrawIndexed(CrlCommandBuffer *commands, CrlPipeline *pipeline, CrlMemorySlice root_arguments, CrlMemorySlice command_arguments, CrlMemorySlice indices);
//Launch a set of rasterization draw commands using a mesh pipeline 
void crdLaunchRasterDrawMeshes(CrlCommandBuffer *commands, CrlMemorySlice root_arguments, CrlMemorySlice command_arguments);
//Launch a set of ray tracing commands using a ray tracing pipeline 
void crdLaunchTraceRays(CrlCommandBuffer *commands, CrlMemorySlice root_arguments, CrlMemorySlice command_arguments);
//Launch a set of acceleration structure build commands  
void crdLaunchBuildAccelerationStructures(CrlCommandBuffer *commands, CrlMemorySlice command_arguments);
//Launch a set of command sequences   
void crdLaunchCommandSequences(CrlCommandBuffer *commands, CrlMemorySlice command_sequences);
//Start recording on the specified queue, returning a command buffer   
CrlCommandBuffer *crdStartCommandRecording(CrlQueue queue);
//Submit work to the specified queue to be executed   
void crdQueueSubmit(CrlQueue queue, CrlCommandBuffer *commands);
//Attach a wait semaphore to command_buffer which will be waited on before excecution   
void crdCommandsWaitSemaphore(CrlCommandBuffer *commands, CrlSemaphore *semaphore, u64 wait_value);
//Attach a wait semaphore to command_buffer which will be signaled on completion 
void crdCommandsSignalSemaphore(CrlCommandBuffer *commands, CrlSemaphore *semaphore, u64 signal_value);
//Wait for all pending work to be completed on the device
void crdWaitIdle(void);
//Wait for all pending work to be completed on the queue 
void crdQueueWaitIdle(CrlQueue queue);
//Create a timeline semaphore synchronisation primitive
CrlSemaphore *crdCreateSemaphore(u64 initial_value);
//Free memory associated with the semaphore
void crdFreeSemaphore(CrlSemaphore *semaphore);
//Wait for the semaphore value to reach wait_value
void crdSemaphoreWait(CrlSemaphore *semaphore, u64 wait_value);
//Sample the semaphore value
u64 crdSemaphoreValue(CrlSemaphore *semaphore);
//Create an image swapchain from the surface
CrlSwapchain *crdCreateSwapchain(CrlSurface *surface);
//Free memory associated with the swapchain
void crdFreeSwapchain(CrlSwapchain *swapchain);
//Obtain the next presentable texture from the swapchain 
void *crdSwapchainObtainTexture(CrlSwapchain *swapchain);
//Present the last obtained swapchain texture
void crdSwapchainPresent(CrlSwapchain *swapchain, CrlSemaphore *signal_semaphore, u64 signal_semaphore_value);

#define CrlMemAllocator void
#define CrlPipelinesCompiler void

//Memory Allocator Interface API

CrlMemorySlice crlMemAllocatorAlloc(CrlMemAllocator *allocator, u64 size, u64 alignment, CrlMemoryType memory_type);
CrlMemorySlice crlMemAllocatorAllocTexture(CrlMemAllocator *allocator, CrlTextureDescription description);
u32 crlMemAllocatorAllocTextureDescriptor(CrlMemAllocator *allocator, void *sampler_heap, void *texture);
void crlMemAllocatorFree(CrlMemAllocator *allocator, CrlMemorySlice memory);

#define CrlMemHeapFixedBufferAllocator void
#define CrlMemHeapArenaAllocator void
#define CrlMemHeapPoolAllocator void

CrlMemHeapFixedBufferAllocator *crlMemHeapFixedBufferAllocatorCreate(CrlMemorySlice buffer);
CrlMemAllocator *crlMemHeapFixedBufferAllocatorInterface(CrlMemHeapFixedBufferAllocator *fba);

//Pipeline Compiler Interface API

#define CrlPipelinesCompiler void

u64 crlPipelinesCompilerCompileComputePipeline();
u64 crlPipelinesCompilerCompileRasterVertexPipeline();
u64 crlPipelinesCompilerCompileRasterMeshPipeline();
u64 crlPipelinesCompilerCompileRayTracingPipeline();
void crlPipelinesCompilerFreePipeline(u64 pipeline);

#define CrlSurfaceCommandBuffer void
#define CrlInputState void

typedef enum {
    CRL_INPUT_KEY_NONE,
} CrlInputKey;

typedef struct {
    u8 *label;
} CrlSurfaceDescription;

typedef struct {
    CrlInputState *input_state;
    CrlMemorySlice clipboard_data;
} CrlSurfacePollResult;

typedef enum {
    CRL_SURFACE_CURSOR_DEFAULT,
    CRL_SURFACE_CURSOR_ARROW,
    CRL_SURFACE_CURSOR_IBEAM,
    CRL_SURFACE_CURSOR_CROSSHAIR,
    CRL_SURFACE_CURSOR_HAND,
    CRL_SURFACE_CURSOR_RESIZE_HORIZONTAL,
    CRL_SURFACE_CURSOR_RESIZE_VERTICAL,
} CrlSurfaceCursor;

typedef enum {
    CRL_SURFACE_CURSOR_MODE_DEFAULT,
    CRL_SURFACE_CURSOR_MODE_HIDDEN,
    CRL_SURFACE_CURSOR_MODE_CAPTURED,
} CrlSurfaceCursorMode;

typedef enum {
    CRL_INPUT_ACTION_RELEASE,
    CRL_INPUT_ACTION_DOWN,
    CRL_INPUT_ACTION_PRESS,
} CrlInputActionState;

//Surface API

//Selects a surface device 
void crlSurfaceDeviceSelect(void);
//Free memory associated with a surface device
void crlSurfaceDeviceFree(void);
//Create a new display surface from the description
CrlSurface *crlSurfaceCreate(CrlSurfaceDescription description);
//Create a display surface handle from a platform handle
CrlSurface *crlSurfaceCreateFromSystemHandle(void *handle);
//Return the native platform handle for the surface
void *crlSurfaceGetSystemHandle(CrlSurface *surface);
//Free the memory associated with the surface
void crlSurfaceFree(CrlSurface *surface);
//Poll the surface for input states and other data
//Returns NULL when the surface has been shutdown by the system
CrlSurfacePollResult *crlSurfacePoll(CrlSurface *surface);
//Start recording commands which can be submitted to the surface
CrlSurfaceCommandBuffer *crlSurfaceCommandsStartRecording(CrlSurface *surface);
//Submit commands to the surface to eventuall be applied
void crlSurfaceSubmitCommands(CrlSurface *surface, CrlSurfaceCommandBuffer *commands);
//Encode a command to maximize/minimize the surface
void crlSurfaceSetMaximized(CrlSurfaceCommandBuffer *commands, u8 maximized);
//Encode a command to enable/disable fullscreen
void crlSurfaceSetFullscreen(CrlSurfaceCommandBuffer *commands, u8 fullscreen);
//Encode a command to set the cursor
void crlSurfaceSetCursor(CrlSurfaceCommandBuffer *commands, CrlSurfaceCursor cursor);
//Encode a command to set the cursor mode
void crlSurfaceSetCursorMode(CrlSurfaceCommandBuffer *commands, CrlSurfaceCursorMode mode);
//Encode a command to set the clipboard data 
void crlSurfaceSetClipboard(CrlSurfaceCommandBuffer *commands, CrlMemorySlice data);
//Encode a command to launch a message box 
void crlSurfaceLaunchMessageBox(CrlSurfaceCommandBuffer *commands, CrlMemorySlice title, CrlMemorySlice message);

//Input API

//Atomically load input key action state
CrlInputActionState crlInputGetKey(CrlInputState *state, CrlInputKey key);
//Atomically load input mouse button action state
CrlInputActionState crlInputGetMouseButton(CrlInputState *state, CrlInputKey button);
//Returns the mouse position
f32 *crlInputGetMousePosition(CrlInputState *state);
//Returns the mouse velocity 
f32 *crlInputGetMouseVelocity(CrlInputState *state);
//Returns the cursor position
f32 *crlInputGetCursorPosition(CrlInputState *state);
//Returns the cursor velocity 
f32 *crlInputGetCursorVelocity(CrlInputState *state);

//Audio API

//Select an audio device
void crlAudioDeviceSelect(void);
//Free the memory associated with the audio device
void crlAudioDeviceFree(void);
//Launch a render buffer procedure into its own thread
void crlAudioDeviceLaunchBufferRenderProcedure(void);

#endif
