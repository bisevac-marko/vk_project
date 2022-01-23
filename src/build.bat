@echo off

pushd ..\

glslc src\shader.vert -o vert.spv
glslc src\shader.frag -o frag.spv

glslc src\shader2D.vert -o vert2D.spv
glslc src\shader2D.frag -o frag2D.spv

odin build .\src\ -debug -opt:0 -show-timings

popd
