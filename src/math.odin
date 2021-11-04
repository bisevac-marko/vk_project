package main

import "core:math"
import la "core:math/linalg"

/*
perspective_f32 :: proc(fovy, aspect, near, far: f32, flip_z_axis := true) -> (m: la.Matrix4f32) {
	tan_half_fovy := math.tan(0.5 * fovy)
	m[0][0] = 1 / (tan_half_fovy)
	m[1][1] = aspect / (tan_half_fovy)
	m[2][2] = (near + far) / (near - far)
	m[2][3] = -1
	m[3][2] = 2*near*far / (near - far)

	if flip_z_axis {
		m[2] = -m[2]
	}

	return
}
*/