@echo off


REM set compiler_flags= -Gm- -GR- -EHa- -O2 -Oi -WX -W3 -wd4996 -wd4311 -wd4302 -wd4201 -wd4100 -wd4189 -wd4129 -FC -Z7 -MTd -nologo

REM cl %compiler_flags% -DVMA_DYNAMIC_VULKAN_FUNCTIONS /c /EHsc .\src\vma.cpp 

pushd ..\

C:\VulkanSDK\1.2.189.2\Bin\glslc.exe .\src\shaders\shader.vert -o vert.spv
C:\VulkanSDK\1.2.189.2\Bin\glslc.exe .\src\shaders\shader.frag -o frag.spv

odin build .\src\ -debug

popd