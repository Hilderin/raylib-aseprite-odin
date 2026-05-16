#+private
package raylib_aseprite

import "core:bytes"
import "core:compress/zlib"
import rl "vendor:raylib"

Reader :: struct {
	data:   []u8,
	offset: int,
	failed: bool,
}

ASE_FILE_MAGIC :: 0xA5E0
ASE_FRAME_MAGIC :: 0xF1FA

LAYER_VISIBLE_FLAG :: u16(0x01)

min_int :: proc(a, b: int) -> int {
	if a < b {
		return a
	}
	return b
}

max_int :: proc(a, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

make_color :: proc(r, g, b, a: u8) -> rl.Color {
	return rl.Color{r, g, b, a}
}

mul_un8 :: proc(a, b: int) -> int {
	t := (a * b) + 0x80
	return ((t >> 8) + t) >> 8
}

blend_color :: proc(src, dst: rl.Color, opacity: u8) -> rl.Color {
	final_src := src
	final_src[3] = u8(mul_un8(int(final_src[3]), int(opacity)))

	a := int(final_src[3]) + int(dst[3]) - mul_un8(int(final_src[3]), int(dst[3]))
	r := 0
	g := 0
	b := 0
	if a != 0 {
		r = int(dst[0]) + (int(final_src[0]) - int(dst[0])) * int(final_src[3]) / a
		g = int(dst[1]) + (int(final_src[1]) - int(dst[1])) * int(final_src[3]) / a
		b = int(dst[2]) + (int(final_src[2]) - int(dst[2])) * int(final_src[3]) / a
	}

	return make_color(u8(r), u8(g), u8(b), u8(a))
}

read_u8 :: proc(r: ^Reader) -> u8 {
	if r.failed || r.offset + 1 > len(r.data) {
		r.failed = true
		return 0
	}
	v := r.data[r.offset]
	r.offset += 1
	return v
}

read_u16 :: proc(r: ^Reader) -> u16 {
	b0 := u16(read_u8(r))
	b1 := u16(read_u8(r))
	return b0 | (b1 << 8)
}

read_i16 :: proc(r: ^Reader) -> i16 {
	return cast(i16)read_u16(r)
}

read_u32 :: proc(r: ^Reader) -> u32 {
	b0 := u32(read_u8(r))
	b1 := u32(read_u8(r))
	b2 := u32(read_u8(r))
	b3 := u32(read_u8(r))
	return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

read_i32 :: proc(r: ^Reader) -> i32 {
	return cast(i32)read_u32(r)
}

skip_bytes :: proc(r: ^Reader, count: int) {
	if r.failed || count < 0 || r.offset + count > len(r.data) {
		r.failed = true
		return
	}
	r.offset += count
}

read_string :: proc(r: ^Reader) -> string {
	length := int(read_u16(r))
	if r.failed || r.offset + length > len(r.data) {
		r.failed = true
		return ""
	}
	s := string(r.data[r.offset:][:length])
	r.offset += length
	return s
}

decode_zlib :: proc(compressed: []u8, expected_size: int) -> ([dynamic]u8, bool) {
	buf := bytes.Buffer{}
	defer bytes.buffer_destroy(&buf)
	err := zlib.inflate(compressed, &buf, false, expected_size)
	if err != nil {
		return nil, false
	}
	out := bytes.buffer_to_bytes(&buf)
	if expected_size >= 0 && len(out) != expected_size {
		return nil, false
	}
	res := make([dynamic]u8, len(out))
	copy(res[:], out)
	return res, true
}

get_source_color :: proc(impl: ^Aseprite_Impl, src: []u8, index: int) -> rl.Color {
	switch impl.mode {
	case .RGBA:
		off := index * 4
		return make_color(src[off], src[off + 1], src[off + 2], src[off + 3])
	case .GRAYSCALE:
		off := index * 2
		sat := src[off]
		alpha := src[off + 1]
		return make_color(sat, sat, sat, alpha)
	case .INDEXED:
		palette_index := int(src[index])
		if palette_index == impl.transparent_palette_entry_index {
			return make_color(0, 0, 0, 0)
		}
		if palette_index < 0 || palette_index >= len(impl.palette) {
			return make_color(0, 0, 0, 0)
		}
		return impl.palette[palette_index]
	}
	return make_color(0, 0, 0, 0)
}

set_pixel_rgba :: proc(pixels: []u8, index: int, color: rl.Color) {
	off := index * 4
	pixels[off] = color[0]
	pixels[off + 1] = color[1]
	pixels[off + 2] = color[2]
	pixels[off + 3] = color[3]
}

get_pixel_rgba :: proc(pixels: []u8, index: int) -> rl.Color {
	off := index * 4
	return make_color(pixels[off], pixels[off + 1], pixels[off + 2], pixels[off + 3])
}

resolve_linked_cel :: proc(impl: ^Aseprite_Impl, frame_index: int, source_cel: ^Cel) -> ^Cel {
	cel := source_cel
	for cel.is_linked {
		if cel.linked_frame_index < 0 || cel.linked_frame_index >= len(impl.frames) {
			return nil
		}
		linked_frame := &impl.frames[cel.linked_frame_index]
		found := false
		for i in 0 ..< len(linked_frame.cels) {
			if linked_frame.cels[i].layer_index == cel.layer_index {
				cel = &linked_frame.cels[i]
				found = true
				break
			}
		}
		if !found {
			return nil
		}
	}
	_ = frame_index
	return cel
}

build_flattened_frames :: proc(impl: ^Aseprite_Impl) -> bool {
	for frame_index in 0 ..< len(impl.frames) {
		frame := &impl.frames[frame_index]
		frame.pixels = make([dynamic]u8, impl.w * impl.h * 4)

		for cel_index in 0 ..< len(frame.cels) {
			cel_ref := &frame.cels[cel_index]
			if cel_ref.layer_index < 0 || cel_ref.layer_index >= len(impl.layers) {
				continue
			}
			layer := impl.layers[cel_ref.layer_index]
			if (layer.flags & LAYER_VISIBLE_FLAG) == 0 {
				continue
			}
			if layer.parent_index >= 0 && layer.parent_index < len(impl.layers) {
				parent := impl.layers[layer.parent_index]
				if (parent.flags & LAYER_VISIBLE_FLAG) == 0 {
					continue
				}
			}

			cel := resolve_linked_cel(impl, frame_index, cel_ref)
			if cel == nil || cel.w <= 0 || cel.h <= 0 || len(cel.pixels) == 0 {
				continue
			}

			opacity := u8(int(cel.opacity * layer.opacity * 255.0))

			cl := -min_int(cel.x, 0)
			ct := -min_int(cel.y, 0)
			dl := max_int(cel.x, 0)
			dt := max_int(cel.y, 0)
			dr := min_int(impl.w, cel.w + cel.x)
			db := min_int(impl.h, cel.h + cel.y)

			for dx, sx := dl, cl; dx < dr; dx, sx = dx + 1, sx + 1 {
				for dy, sy := dt, ct; dy < db; dy, sy = dy + 1, sy + 1 {
					dst_index := impl.w * dy + dx
					src_index := cel.w * sy + sx
					src_color := get_source_color(impl, cel.pixels[:], src_index)
					dst_color := get_pixel_rgba(frame.pixels[:], dst_index)
					result := blend_color(src_color, dst_color, opacity)
					set_pixel_rgba(frame.pixels[:], dst_index, result)
				}
			}
		}
	}

	return true
}
