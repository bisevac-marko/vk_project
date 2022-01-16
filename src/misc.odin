package main

megabytes:: #force_inline proc(n: int) -> int {
    return n * 1024 * 1024;
}

gigabites:: #force_inline proc(n: int) -> int {
    return n * 1024 * 1024 * 1024;
}

terabytes:: #force_inline proc(n: int) -> int {
    return n * 1024 * 1024 * 1024 * 1024;
}
