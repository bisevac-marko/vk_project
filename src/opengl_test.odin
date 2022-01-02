package main

import glfw   "vendor:glfw"
import gl     "vendor:opengl"
import        "core:fmt"

main :: proc()
{
    window_width  :i32= 1366;
    window_height :i32= 768;


    window: glfw.WindowHandle;

    if (glfw.Init() == 0)
    {
        fmt.println("[GLFW] Failed to initialized!");
    }

    window = glfw.CreateWindow(window_width, window_height, "Window", nil, nil);

    if (window == nil)
    {
        glfw.Terminate();
        fmt.println("[GLFW] Failed to create window!");
    }

    gl.load_3_0(glfw.gl_set_proc_address);

    gl.Viewport(0, 0, window_width, window_height);
    gl.ClearColor(0.3, 0.3, 0.3, 1.0);

    glfw.MakeContextCurrent(window);

    for (!glfw.WindowShouldClose(window))
    {
        glfw.PollEvents();

        gl.Clear(gl.COLOR_BUFFER_BIT);
        glfw.SwapBuffers(window);
    }
}
