package main

import        "core:os"
import str    "core:strings"
import        "core:strconv"

ivec3 :: distinct [3]i32;

OBJ_File_Info :: struct {
    vertex_count: u32,
    face_count: u32,
    normal_count: u32,
    uv_count: u32,
}

OBJ_Reader :: struct {
    s: string,
    i: u64,
}

OBJ_Face :: struct {
    position_indices: [3]u64,
    normal_indices  : [3]u64,
    uv_indices      : [3]u64,
}

obj_read:: proc(file_name: string) -> (mesh: Mesh) {
    
    buf, ok := os.read_entire_file(file_name, context.temp_allocator);
    assert(ok);
    info := get_info(buf);
    
    mesh.vertices = make([dynamic]Vertex, info.face_count * 3);
    mesh.indices  = make([dynamic]u32, info.face_count * 3);
    
    obj_positions := make([dynamic]vec3, info.vertex_count, context.temp_allocator);
    obj_normals   := make([dynamic]vec3, info.normal_count, context.temp_allocator);
    obj_uvs       := make([dynamic]vec2, info.uv_count,     context.temp_allocator);
    index_map     := make_map(map[ivec3]u32, info.face_count, context.temp_allocator);
    
    
    reader := create_reader(string(buf));
    
    for ;; {
        word, eof  := next_word(&reader);
        switch word {
            case "v": {
                v: vec3;
                v, eof = next_vec(&reader, vec3);
                append_elem(&obj_positions, v);
            }
            case "vn": {
                v: vec3;
                v, eof = next_vec(&reader, vec3);
                append_elem(&obj_normals, v);
            }
            case "vt": {
                v: vec2;
                v, eof = next_vec(&reader, vec2);
                append_elem(&obj_uvs, v);
            }
            case "f": {
                face: OBJ_Face;
                face, eof = parse_face(&reader);
                
                for i in 0..2 {
                    key: ivec3 = {
                        i32(face.position_indices[i]),
                        i32(face.normal_indices[i]),
                        i32(face.uv_indices[i]),
                    };
                    
                    index, ok := index_map[key];
                    
                    if (!ok) {
                        index = u32(len(mesh.vertices));
                        index_map[key] = index;
                        vertex: Vertex;
                        vertex.pos = obj_positions[face.position_indices[i]];
                        vertex.normal = obj_normals[face.normal_indices[i]]; 
                        vertex.uv = obj_uvs[face.uv_indices[i]];
                        vertex.color = {1,1,1};
                        
                        append_elem(&mesh.vertices, vertex);
                    }
                    append_elem(&mesh.indices, index);
                    
                    
                }
            }
        }
        
        if eof {
            break;
        }
    }
    
    return mesh;
}

@(private)
is_whitespace:: proc(c: u8) -> b32 {
    return (c == ' ' ||
            c == '\n');
}

@(private)
increment_reader:: proc(r: ^OBJ_Reader) -> b32 {
    if r.i < u64(len(r.s)) - 1 {
        r.i += 1;
        return true;
    }
    return false;
}

@(private)
next_word:: proc(r: ^OBJ_Reader) -> (str: string, eof: bool) {
    // Skip whitespace
    eof = false;
    for ;is_whitespace(r.s[r.i]); {
        if !increment_reader(r) {
            eof = true;
            break;
        }
    }
    
    start := r.i;
    
    for ;!is_whitespace(r.s[r.i]); {
        if !increment_reader(r) {
            eof = true;
            break;
        }
    }
    str = r.s[start:r.i];
    
    return str, eof;
}


@(private)
create_reader:: proc(s: string) -> (r: OBJ_Reader) {
    r.s = s;
    return;
}

@(private)
get_info:: proc(buf: []byte) -> (info: OBJ_File_Info) {
    
    reader := create_reader(string(buf));
    for ;; {
        word, eof := next_word(&reader);
        
        switch word {
            case "v":
                info.vertex_count += 1;
            case "vn":
                info.normal_count += 1;
            case "vt":
                info.uv_count     += 1;
            case "f":
                info.face_count   += 1;
        }
        
        if eof {
            break;
        }
    }
    
    return info;
}

@(private)
next_float:: proc(r: ^OBJ_Reader) -> (f: f32, eof: bool) {
    s: string;
    s, eof = next_word(r);
    ok: bool;
    f, ok = strconv.parse_f32(s);
    assert(ok);
    
    return f, eof;
}

@(private)
next_vec:: proc(r: ^OBJ_Reader, $T: typeid) -> (v: T, eof: bool) {
    for i in 0..<(size_of(T)/size_of(f32)) {
        v[i], eof = next_float(r);
    }
    return v, eof;
}

@(private)
parse_face:: proc(r: ^OBJ_Reader) -> (face: OBJ_Face, eof: bool) {
    
    for i in 0..2 {
        word: string;
        word, eof = next_word(r);
        split := str.split(word, "/", context.temp_allocator);
        assert(len(split) == 3);
        
        //NOTE(mb): we subtract -1 because .obj file is indexed from 1
        // Face = position/texture/normal * 3
        ok: bool;
        face.position_indices[i], ok = strconv.parse_u64(split[0]);
        face.uv_indices[i], ok       = strconv.parse_u64(split[1]);
        face.normal_indices[i], ok   = strconv.parse_u64(split[2]);   
        
        face.position_indices[i] -= 1;
        face.uv_indices[i]       -= 1;
        face.normal_indices[i]   -= 1;
        
    }
    
    return face, eof;
}
