package raylib_aseprite

import "core:c"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"

Animation_Direction :: enum u8 {
	FORWARDS,
	BACKWORDS,
	PINGPONG,
}

Aseprite :: struct {
	impl: ^Aseprite_Impl,
}

AsepriteTag :: struct {
	name:         string,
	currentFrame: int,
	timer:        f32,
	direction:    int,
	speed:        f32,
	color:        rl.Color,
	loop:         bool,
	paused:       bool,
	aseprite:     Aseprite,
	tag_index:    int,
}

AsepriteSlice :: struct {
	name:   string,
	bounds: rl.Rectangle,
}

Ase_Mode :: enum u8 {
	RGBA,
	GRAYSCALE,
	INDEXED,
}

Layer :: struct {
	flags:        u16,
	name:         string,
	parent_index: int,
	opacity:      f32,
}

Cel :: struct {
	layer_index:        int,
	x, y:               int,
	opacity:            f32,
	w, h:               int,
	is_linked:          bool,
	linked_frame_index: int,
	pixels:             [dynamic]u8,
}

Frame :: struct {
	duration_milliseconds: int,
	cels:                  [dynamic]Cel,
	pixels:                [dynamic]u8,
}

Tag_Def :: struct {
	name:       string,
	from_frame: int,
	to_frame:   int,
	direction:  Animation_Direction,
	repeat:     int,
	color:      rl.Color,
}

Slice_Def :: struct {
	name:         string,
	frame_number: int,
	origin_x:     int,
	origin_y:     int,
	w:            int,
	h:            int,
}

Aseprite_Impl :: struct {
	is_unloaded:                     bool,
	mode:                            Ase_Mode,
	w, h:                            int,
	frame_count:                     int,
	number_of_colors:                int,
	transparent_palette_entry_index: int,
	layers:                          [dynamic]Layer,
	frames:                          [dynamic]Frame,
	tags:                            [dynamic]Tag_Def,
	slices:                          [dynamic]Slice_Def,
	texture:                         rl.Texture,
	palette:                         [256]rl.Color,
	palette_entry_count:             int,
	source_data:                     [dynamic]u8,
	atlas_pixels:                    [dynamic]u8,
}

@(private = "file")
load_empty_texture :: proc() -> rl.Texture {
	return rl.Texture{}
}

@(private = "file")
is_window_ready :: proc() -> bool {
	return rl.IsWindowReady()
}

@(private = "file")
build_texture_atlas :: proc(impl: ^Aseprite_Impl) -> bool {
	if impl.frame_count <= 0 || impl.w <= 0 || impl.h <= 0 {
		return false
	}

	atlas_width := impl.w * impl.frame_count
	atlas_height := impl.h
	impl.atlas_pixels = make([dynamic]u8, atlas_width * atlas_height * 4)

	for frame_index in 0 ..< len(impl.frames) {
		frame := impl.frames[frame_index]
		for y in 0 ..< impl.h {
			dst_off := ((y * atlas_width) + (frame_index * impl.w)) * 4
			src_off := (y * impl.w) * 4
			copy(impl.atlas_pixels[dst_off:][:impl.w * 4], frame.pixels[src_off:][:impl.w * 4])
		}
	}

	image := rl.Image {
		data    = raw_data(impl.atlas_pixels),
		width   = c.int(atlas_width),
		height  = c.int(atlas_height),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	impl.texture = rl.LoadTextureFromImage(image)
	return impl.texture.id != 0
}

@(private = "file")
parse_aseprite :: proc(data: []u8, impl: ^Aseprite_Impl) -> bool {
	r := Reader {
		data = data,
	}

	_ = read_u32(&r)
	if int(read_u16(&r)) != ASE_FILE_MAGIC {
		return false
	}

	impl.frame_count = int(read_u16(&r))
	impl.w = int(read_u16(&r))
	impl.h = int(read_u16(&r))
	color_depth := int(read_u16(&r))
	bpp := color_depth / 8
	switch bpp {
	case 4:
		impl.mode = .RGBA
	case 2:
		impl.mode = .GRAYSCALE
	case 1:
		impl.mode = .INDEXED
	case:
		return false
	}

	valid_layer_opacity := (read_u32(&r) & 1) != 0
	default_speed := int(read_u16(&r))
	_ = read_u32(&r)
	_ = read_u32(&r)
	impl.transparent_palette_entry_index = int(read_u8(&r))
	skip_bytes(&r, 3)
	impl.number_of_colors = int(read_u16(&r))
	_ = read_u8(&r)
	_ = read_u8(&r)
	_ = read_i16(&r)
	_ = read_i16(&r)
	_ = read_u16(&r)
	_ = read_u16(&r)
	skip_bytes(&r, 84)

	if r.failed || impl.frame_count <= 0 || impl.w <= 0 || impl.h <= 0 {
		return false
	}

	impl.frames = make([dynamic]Frame, impl.frame_count)
	layer_stack := make([]int, 256)
	defer delete(layer_stack)
	for i in 0 ..< len(layer_stack) {
		layer_stack[i] = -1
	}

	for frame_index in 0 ..< impl.frame_count {
		frame := &impl.frames[frame_index]
		_ = read_u32(&r)
		if int(read_u16(&r)) != ASE_FRAME_MAGIC {
			return false
		}

		chunk_count := int(read_u16(&r))
		frame.duration_milliseconds = int(read_u16(&r))
		if frame.duration_milliseconds == 0 {
			frame.duration_milliseconds = default_speed
		}
		skip_bytes(&r, 2)
		new_chunk_count := int(read_u32(&r))
		if new_chunk_count != 0 {
			chunk_count = new_chunk_count
		}

		for _ in 0 ..< chunk_count {
			chunk_payload_size := int(read_u32(&r)) - 6
			chunk_type := int(read_u16(&r))
			if chunk_payload_size < 0 {
				return false
			}
			chunk_start := r.offset
			chunk_end := chunk_start + chunk_payload_size
			if chunk_end > len(r.data) {
				return false
			}

			switch chunk_type {
			case 0x0004:
				nb_packets := int(read_u16(&r))
				for _ in 0 ..< nb_packets {
					skip := int(read_u8(&r))
					nb_colors := int(read_u8(&r))
					if nb_colors == 0 {
						nb_colors = 256
					}
					for l in 0 ..< nb_colors {
						index := skip + l
						if index >= 0 && index < len(impl.palette) {
							rc := read_u8(&r)
							gc := read_u8(&r)
							bc := read_u8(&r)
							impl.palette[index] = make_color(rc, gc, bc, 255)
							impl.palette_entry_count = max_int(impl.palette_entry_count, index + 1)
						} else {
							skip_bytes(&r, 3)
						}
					}
				}

			case 0x2004:
				layer := Layer{}
				layer.flags = read_u16(&r)
				_ = read_u16(&r)
				child_level := int(read_u16(&r))
				if child_level >= 0 && child_level < len(layer_stack) {
					layer.parent_index = -1
					if child_level > 0 {
						layer.parent_index = layer_stack[child_level - 1]
					}
					layer_stack[child_level] = len(impl.layers)
				}
				_ = read_u16(&r)
				_ = read_u16(&r)
				_ = read_u16(&r)
				opacity := read_u8(&r)
				layer.opacity = f32(opacity) / 255.0
				if !valid_layer_opacity {
					layer.opacity = 1.0
				}
				skip_bytes(&r, 3)
				layer.name = read_string(&r)
				append_elem(&impl.layers, layer)

			case 0x2005:
				cel := Cel{}
				cel.layer_index = int(read_u16(&r))
				cel.x = int(read_i16(&r))
				cel.y = int(read_i16(&r))
				cel.opacity = f32(read_u8(&r)) / 255.0
				cel_type := int(read_u16(&r))
				skip_bytes(&r, 7)

				switch cel_type {
				case 0:
					cel.w = int(read_u16(&r))
					cel.h = int(read_u16(&r))
					pixel_count := cel.w * cel.h * bpp
					if pixel_count < 0 || r.offset + pixel_count > len(r.data) {
						return false
					}
					cel.pixels = make([dynamic]u8, pixel_count)
					copy(cel.pixels[:], r.data[r.offset:][:pixel_count])
					r.offset += pixel_count

				case 1:
					cel.is_linked = true
					cel.linked_frame_index = int(read_u16(&r))

				case 2:
					cel.w = int(read_u16(&r))
					cel.h = int(read_u16(&r))
					payload := r.data[r.offset:chunk_end]
					pixel_count := cel.w * cel.h * bpp
					decoded, ok := decode_zlib(payload, pixel_count)
					if !ok {
						return false
					}
					cel.pixels = decoded
					r.offset = chunk_end

				case:
					return false
				}

				append_elem(&frame.cels, cel)

			case 0x2018:
				tag_count := int(read_u16(&r))
				skip_bytes(&r, 8)
				for _ in 0 ..< tag_count {
					tag := Tag_Def{}
					tag.from_frame = int(read_u16(&r))
					tag.to_frame = int(read_u16(&r))
					tag.direction = Animation_Direction(read_u8(&r))
					tag.repeat = int(read_u16(&r))
					skip_bytes(&r, 6)
					rc := read_u8(&r)
					gc := read_u8(&r)
					bc := read_u8(&r)
					tag.color = make_color(rc, gc, bc, 255)
					_ = read_u8(&r)
					tag.name = read_string(&r)
					append_elem(&impl.tags, tag)
				}

			case 0x2019:
				impl.palette_entry_count = int(read_u32(&r))
				first := int(read_u32(&r))
				last := int(read_u32(&r))
				skip_bytes(&r, 8)
				for k in first ..= last {
					has_name := int(read_u16(&r))
					rc := read_u8(&r)
					gc := read_u8(&r)
					bc := read_u8(&r)
					ac := read_u8(&r)
					if k >= 0 && k < len(impl.palette) {
						impl.palette[k] = make_color(rc, gc, bc, ac)
					}
					if has_name != 0 {
						_ = read_string(&r)
					}
				}

			case 0x2020:
				skip_bytes(&r, chunk_payload_size)

			case 0x2022:
				slice_count := int(read_u32(&r))
				flags := int(read_u32(&r))
				_ = read_u32(&r)
				slice_name := read_string(&r)
				for _ in 0 ..< slice_count {
					s := Slice_Def{}
					s.name = slice_name
					s.frame_number = int(read_u32(&r))
					s.origin_x = int(read_i32(&r))
					s.origin_y = int(read_i32(&r))
					s.w = int(read_u32(&r))
					s.h = int(read_u32(&r))
					if (flags & 1) != 0 {
						skip_bytes(&r, 16)
					}
					if (flags & 2) != 0 {
						skip_bytes(&r, 8)
					}
					append_elem(&impl.slices, s)
				}

			case:
				skip_bytes(&r, chunk_payload_size)
			}

			if r.failed {
				return false
			}

			r.offset = chunk_end
		}
	}

	if r.failed {
		return false
	}

	return build_flattened_frames(impl)
}

@(private = "file")
new_empty_aseprite :: proc() -> Aseprite {
	return Aseprite{}
}

@(private = "file")
get_impl :: proc(aseprite: Aseprite) -> ^Aseprite_Impl {
	if aseprite.impl == nil || aseprite.impl.is_unloaded {
		return nil
	}
	return aseprite.impl
}

LoadAsepriteFromMemoryData :: proc(file_data: []u8) -> Aseprite {
	if !is_window_ready() {
		rl.TraceLog(
			.ERROR,
			cstring("ASEPRITE: Loading an Aseprite requires a ready raylib window"),
		)
		return new_empty_aseprite()
	}

	if len(file_data) == 0 {
		return new_empty_aseprite()
	}

	impl := new(Aseprite_Impl)
	impl.texture = load_empty_texture()
	impl.source_data = make([dynamic]u8, len(file_data))
	copy(impl.source_data[:], file_data)

	if !parse_aseprite(impl.source_data[:], impl) {
		delete(impl.source_data)
		free(impl)
		rl.TraceLog(.ERROR, cstring("ASEPRITE: Failed to parse Aseprite data"))
		return new_empty_aseprite()
	}

	if !build_texture_atlas(impl) {
		for i in 0 ..< len(impl.frames) {
			frame := &impl.frames[i]
			for j in 0 ..< len(frame.cels) {
				delete(frame.cels[j].pixels)
			}
			delete(frame.cels)
			delete(frame.pixels)
		}
		delete(impl.frames)
		delete(impl.layers)
		delete(impl.tags)
		delete(impl.slices)
		delete(impl.source_data)
		free(impl)
		rl.TraceLog(.ERROR, cstring("ASEPRITE: Failed to create texture atlas"))
		return new_empty_aseprite()
	}

	return Aseprite{impl = impl}
}

LoadAsepriteFromMemoryPtr :: proc(file_data: [^]u8, size: int) -> Aseprite {
	if file_data == nil || size <= 0 {
		return new_empty_aseprite()
	}
	return LoadAsepriteFromMemoryData(file_data[:size])
}

LoadAsepriteFromMemory :: proc {
	LoadAsepriteFromMemoryData,
	LoadAsepriteFromMemoryPtr,
}

LoadAseprite :: proc(file_name: string) -> Aseprite {
	data, err := os.read_entire_file(file_name, context.allocator)
	if err != nil {
		rl.TraceLog(.ERROR, cstring("ASEPRITE: Failed to load aseprite file"))
		return new_empty_aseprite()
	}
	defer delete(data)
	return LoadAsepriteFromMemoryData(data)
}

IsAsepriteValid :: proc(aseprite: Aseprite) -> bool {
	return get_impl(aseprite) != nil
}

UnloadAseprite :: proc(aseprite: Aseprite) {
	impl := get_impl(aseprite)
	if impl == nil {
		return
	}

	if impl.texture.id != 0 {
		rl.UnloadTexture(impl.texture)
	}

	for frame_index in 0 ..< len(impl.frames) {
		frame := &impl.frames[frame_index]
		for cel_index in 0 ..< len(frame.cels) {
			delete(frame.cels[cel_index].pixels)
		}
		delete(frame.cels)
		delete(frame.pixels)
	}

	delete(impl.frames)
	delete(impl.layers)
	delete(impl.tags)
	delete(impl.slices)
	delete(impl.source_data)
	delete(impl.atlas_pixels)

	impl.is_unloaded = true
	free(impl)
}

TraceAseprite :: proc(aseprite: Aseprite) {
	impl := get_impl(aseprite)
	if impl == nil {
		fmt.println("ASEPRITE: Empty Aseprite information")
		return
	}

	fmt.printf(
		"ASEPRITE: Aseprite information: (%vx%v - %v frames)\n",
		impl.w,
		impl.h,
		impl.frame_count,
	)
	fmt.printf("    > Colors: %v\n", impl.number_of_colors)
	fmt.printf("    > Mode:   %v\n", impl.mode)
	fmt.printf("    > Layers: %v\n", len(impl.layers))
	for layer in impl.layers {
		fmt.printf("      - %v\n", layer.name)
	}

	fmt.printf("    > Tags:   %v\n", len(impl.tags))
	for tag in impl.tags {
		fmt.printf("      - %v\n", tag.name)
	}

	fmt.printf("    > Slices: %v\n", len(impl.slices))
	for slice in impl.slices {
		fmt.printf("      - %v\n", slice.name)
	}
}

GetAsepriteTexture :: proc(aseprite: Aseprite) -> rl.Texture {
	impl := get_impl(aseprite)
	if impl == nil {
		return load_empty_texture()
	}
	return impl.texture
}

GetAsepriteWidth :: proc(aseprite: Aseprite) -> int {
	impl := get_impl(aseprite)
	if impl == nil {
		return 0
	}
	return impl.w
}

GetAsepriteHeight :: proc(aseprite: Aseprite) -> int {
	impl := get_impl(aseprite)
	if impl == nil {
		return 0
	}
	return impl.h
}

DrawAseprite :: proc(aseprite: Aseprite, frame: int, posX, posY: int, tint: rl.Color) {
	DrawAsepriteFlipped(aseprite, frame, posX, posY, false, false, tint)
}

DrawAsepriteFlipped :: proc(
	aseprite: Aseprite,
	frame: int,
	posX, posY: int,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	DrawAsepriteVFlipped(
		aseprite,
		frame,
		rl.Vector2{f32(posX), f32(posY)},
		horizontalFlip,
		verticalFlip,
		tint,
	)
}

DrawAsepriteV :: proc(aseprite: Aseprite, frame: int, position: rl.Vector2, tint: rl.Color) {
	DrawAsepriteVFlipped(aseprite, frame, position, false, false, tint)
}

DrawAsepriteVFlipped :: proc(
	aseprite: Aseprite,
	frame: int,
	position: rl.Vector2,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	impl := get_impl(aseprite)
	if impl == nil || frame < 0 || frame >= impl.frame_count {
		return
	}

	source := rl.Rectangle {
		x      = f32(frame * impl.w),
		y      = 0,
		width  = f32(-impl.w) if horizontalFlip else f32(impl.w),
		height = f32(-impl.h) if verticalFlip else f32(impl.h),
	}
	rl.DrawTextureRec(impl.texture, source, position, tint)
}

DrawAsepriteEx :: proc(
	aseprite: Aseprite,
	frame: int,
	position: rl.Vector2,
	rotation, scale: f32,
	tint: rl.Color,
) {
	DrawAsepriteExFlipped(aseprite, frame, position, rotation, scale, false, false, tint)
}

DrawAsepriteExFlipped :: proc(
	aseprite: Aseprite,
	frame: int,
	position: rl.Vector2,
	rotation, scale: f32,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	impl := get_impl(aseprite)
	if impl == nil || frame < 0 || frame >= impl.frame_count {
		return
	}

	source := rl.Rectangle {
		x      = f32(frame * impl.w),
		y      = 0,
		width  = f32(-impl.w) if horizontalFlip else f32(impl.w),
		height = f32(-impl.h) if verticalFlip else f32(impl.h),
	}
	dest := rl.Rectangle {
		x      = position[0],
		y      = position[1],
		width  = f32(impl.w) * scale,
		height = f32(impl.h) * scale,
	}
	origin := rl.Vector2{0, 0}
	rl.DrawTexturePro(impl.texture, source, dest, origin, rotation, tint)
}

DrawAsepritePro :: proc(
	aseprite: Aseprite,
	frame: int,
	dest: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
	tint: rl.Color,
) {
	DrawAsepriteProFlipped(aseprite, frame, dest, origin, rotation, false, false, tint)
}

DrawAsepriteProFlipped :: proc(
	aseprite: Aseprite,
	frame: int,
	dest: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	impl := get_impl(aseprite)
	if impl == nil || frame < 0 || frame >= impl.frame_count {
		return
	}

	source := rl.Rectangle {
		x      = f32(frame * impl.w),
		y      = 0,
		width  = f32(-impl.w) if horizontalFlip else f32(impl.w),
		height = f32(-impl.h) if verticalFlip else f32(impl.h),
	}
	rl.DrawTexturePro(impl.texture, source, dest, origin, rotation, tint)
}

GetAsepriteTagCount :: proc(aseprite: Aseprite) -> int {
	impl := get_impl(aseprite)
	if impl == nil {
		return 0
	}
	return len(impl.tags)
}

GenAsepriteTagDefault :: proc() -> AsepriteTag {
	return AsepriteTag {
		tag_index = -1,
		direction = 0,
		speed = 1.0,
		color = rl.BLACK,
		loop = true,
		paused = false,
	}
}

LoadAsepriteTagFromIndex :: proc(aseprite: Aseprite, index: int) -> AsepriteTag {
	tag := GenAsepriteTagDefault()
	impl := get_impl(aseprite)
	if impl == nil {
		return tag
	}
	if index < 0 || index >= len(impl.tags) {
		return tag
	}

	def := impl.tags[index]
	tag.aseprite = aseprite
	tag.tag_index = index
	tag.name = def.name
	tag.color = def.color
	tag.direction = 1
	tag.currentFrame = def.from_frame
	if def.direction == .BACKWORDS {
		tag.currentFrame = def.to_frame
		tag.direction = -1
	}
	if def.from_frame == def.to_frame {
		tag.paused = true
	}
	if tag.currentFrame >= 0 && tag.currentFrame < len(impl.frames) {
		tag.timer = f32(impl.frames[tag.currentFrame].duration_milliseconds) / 1000.0
	}
	return tag
}

LoadAsepriteTag :: proc(aseprite: Aseprite, name: string) -> AsepriteTag {
	impl := get_impl(aseprite)
	if impl == nil {
		return GenAsepriteTagDefault()
	}

	for i in 0 ..< len(impl.tags) {
		if impl.tags[i].name == name {
			return LoadAsepriteTagFromIndex(aseprite, i)
		}
	}

	return GenAsepriteTagDefault()
}

IsAsepriteTagValid :: proc(tag: AsepriteTag) -> bool {
	impl := get_impl(tag.aseprite)
	return impl != nil && tag.tag_index >= 0 && tag.tag_index < len(impl.tags)
}

@(private)
update_aseprite_tag_by_delta :: proc(tag: ^AsepriteTag, delta_time: f32) {
	if tag == nil || !IsAsepriteTagValid(tag^) {
		return
	}
	if tag.paused {
		return
	}

	impl := get_impl(tag.aseprite)
	if impl == nil {
		return
	}
	def := impl.tags[tag.tag_index]

	tag.timer -= delta_time * tag.speed
	if tag.timer > 0 {
		return
	}

	tag.currentFrame += tag.direction
	switch def.direction {
	case .FORWARDS:
		if tag.currentFrame > def.to_frame {
			if tag.loop {
				tag.currentFrame = def.from_frame
			} else {
				tag.currentFrame = def.to_frame
				tag.paused = true
			}
		}
	case .BACKWORDS:
		if tag.currentFrame < def.from_frame {
			if tag.loop {
				tag.currentFrame = def.to_frame
			} else {
				tag.currentFrame = def.from_frame
				tag.paused = true
			}
		}
	case .PINGPONG:
		if tag.direction > 0 {
			if tag.currentFrame > def.to_frame {
				tag.direction = -1
				if tag.loop {
					tag.currentFrame = def.to_frame - 1
				} else {
					tag.currentFrame = def.to_frame
					tag.paused = true
				}
			}
		} else if tag.currentFrame < def.from_frame {
			tag.direction = 1
			if tag.loop {
				tag.currentFrame = def.from_frame + 1
			} else {
				tag.currentFrame = def.from_frame
				tag.paused = true
			}
		}
	}

	if tag.currentFrame >= 0 && tag.currentFrame < len(impl.frames) {
		tag.timer = f32(impl.frames[tag.currentFrame].duration_milliseconds) / 1000.0
	}
}

UpdateAsepriteTag :: proc(tag: ^AsepriteTag) {
	if tag == nil {
		return
	}
	update_aseprite_tag_by_delta(tag, rl.GetFrameTime())
}

SetAsepriteTagFrame :: proc(tag: ^AsepriteTag, frameNumber: int) {
	if tag == nil || !IsAsepriteTagValid(tag^) {
		return
	}
	impl := get_impl(tag.aseprite)
	def := impl.tags[tag.tag_index]

	if frameNumber >= 0 {
		tag.currentFrame = def.from_frame + frameNumber
	} else {
		tag.currentFrame = def.to_frame + frameNumber
	}

	if tag.currentFrame < def.from_frame {
		tag.currentFrame = def.from_frame
	} else if tag.currentFrame > def.to_frame {
		tag.currentFrame = def.to_frame
	}
}

GetAsepriteTagFrame :: proc(tag: AsepriteTag) -> int {
	if !IsAsepriteTagValid(tag) {
		return 0
	}
	impl := get_impl(tag.aseprite)
	def := impl.tags[tag.tag_index]
	return tag.currentFrame - def.from_frame
}

DrawAsepriteTag :: proc(tag: AsepriteTag, posX, posY: int, tint: rl.Color) {
	DrawAseprite(tag.aseprite, tag.currentFrame, posX, posY, tint)
}

DrawAsepriteTagFlipped :: proc(
	tag: AsepriteTag,
	posX, posY: int,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	DrawAsepriteFlipped(
		tag.aseprite,
		tag.currentFrame,
		posX,
		posY,
		horizontalFlip,
		verticalFlip,
		tint,
	)
}

DrawAsepriteTagV :: proc(tag: AsepriteTag, position: rl.Vector2, tint: rl.Color) {
	DrawAsepriteV(tag.aseprite, tag.currentFrame, position, tint)
}

DrawAsepriteTagVFlipped :: proc(
	tag: AsepriteTag,
	position: rl.Vector2,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	DrawAsepriteVFlipped(
		tag.aseprite,
		tag.currentFrame,
		position,
		horizontalFlip,
		verticalFlip,
		tint,
	)
}

DrawAsepriteTagEx :: proc(
	tag: AsepriteTag,
	position: rl.Vector2,
	rotation, scale: f32,
	tint: rl.Color,
) {
	DrawAsepriteEx(tag.aseprite, tag.currentFrame, position, rotation, scale, tint)
}

DrawAsepriteTagExFlipped :: proc(
	tag: AsepriteTag,
	position: rl.Vector2,
	rotation, scale: f32,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	DrawAsepriteExFlipped(
		tag.aseprite,
		tag.currentFrame,
		position,
		rotation,
		scale,
		horizontalFlip,
		verticalFlip,
		tint,
	)
}

DrawAsepriteTagPro :: proc(
	tag: AsepriteTag,
	dest: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
	tint: rl.Color,
) {
	DrawAsepritePro(tag.aseprite, tag.currentFrame, dest, origin, rotation, tint)
}

DrawAsepriteTagProFlipped :: proc(
	tag: AsepriteTag,
	dest: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
	horizontalFlip, verticalFlip: bool,
	tint: rl.Color,
) {
	DrawAsepriteProFlipped(
		tag.aseprite,
		tag.currentFrame,
		dest,
		origin,
		rotation,
		horizontalFlip,
		verticalFlip,
		tint,
	)
}

GenAsepriteSliceDefault :: proc() -> AsepriteSlice {
	return AsepriteSlice{name = "", bounds = rl.Rectangle{}}
}

LoadAsepriteSliceFromIndex :: proc(aseprite: Aseprite, index: int) -> AsepriteSlice {
	impl := get_impl(aseprite)
	if impl == nil || index < 0 || index >= len(impl.slices) {
		return GenAsepriteSliceDefault()
	}

	slice := impl.slices[index]
	return AsepriteSlice {
		name = slice.name,
		bounds = rl.Rectangle {
			x = f32(slice.origin_x),
			y = f32(slice.origin_y),
			width = f32(slice.w),
			height = f32(slice.h),
		},
	}
}

LoadAsepriteSlice :: proc(aseprite: Aseprite, name: string) -> AsepriteSlice {
	impl := get_impl(aseprite)
	if impl == nil {
		return GenAsepriteSliceDefault()
	}

	for i in 0 ..< len(impl.slices) {
		if impl.slices[i].name == name {
			return LoadAsepriteSliceFromIndex(aseprite, i)
		}
	}
	return GenAsepriteSliceDefault()
}

GetAsepriteSliceCount :: proc(aseprite: Aseprite) -> int {
	impl := get_impl(aseprite)
	if impl == nil {
		return 0
	}
	return len(impl.slices)
}

IsAsepriteSliceValid :: proc(slice: AsepriteSlice) -> bool {
	return len(slice.name) != 0
}
