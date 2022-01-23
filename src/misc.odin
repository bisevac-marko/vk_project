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

to_megabytes:: #force_inline proc(bytes: u64) -> u64 {
    return bytes / 1024 / 1024;
}
