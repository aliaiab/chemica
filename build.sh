
glslangValidator -G -S comp --vn blackBodyComputeBinary Source/Shaders/BlackBodyCompute.glsl -o Source/Shaders/Include/BlackBodyCompute.h &
glslangValidator -G -S comp --vn thermalComputeBinary Source/Shaders/ThermalCompute.glsl -o Source/Shaders/Include/ThermalCompute.h &
glslangValidator -G -S frag --vn rendererFragmentBinary Source/Shaders/RendererFragment.glsl -o Source/Shaders/Include/RendererFragment.h &
glslangValidator -G -S vert --vn rendererVertexBinary Source/Shaders/RendererVertex.glsl -o Source/Shaders/Include/RendererVertex.h &
glslangValidator -G -S comp --vn simulationComputeBinary Source/Shaders/SimulationCompute.glsl -o Source/Shaders/Include/SimulationCompute.h &
glslangValidator -G -S comp --vn distanceFieldComputeBinary Source/Shaders/DistanceFieldCompute.glsl -o Source/Shaders/Include/DistanceFieldCompute.h
glslangValidator -G -S comp --vn grainSimulationBinary Source/Shaders/GrainSimulation.glsl -o Source/Shaders/Include/GrainSimulation.h
glslangValidator -G -S comp --vn fillRegionBinary Source/Shaders/FillRegion.glsl -o Source/Shaders/Include/FillRegion.h

glslangValidator -G -S frag --vn envMapFragmentBinary Source/Shaders/EnvMapFragment.glsl -o Source/Shaders/Include/EnvMapFragment.h
glslangValidator -G -S vert --vn envMapVertexBinary Source/Shaders/EnvMapVertex.glsl -o Source/Shaders/Include/EnvMapVertex.h

cmake -S . -B Build 

cd Build

make 

./chemica --dev