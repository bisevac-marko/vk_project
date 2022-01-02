@echo off

pushd ..\

odin build .\src\ -debug

main.exe

popd
