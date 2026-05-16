package raylib_aseprite

import "core:testing"
import rl "vendor:raylib"

test_aseprite_api :: proc(t: ^testing.T) {
	rl.SetConfigFlags({.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "raylib-aseprite-odin tests")
	defer rl.CloseWindow()

	ase := LoadAseprite("resources/numbers.aseprite")
	defer UnloadAseprite(ase)

	testing.expect(t, IsAsepriteValid(ase))
	testing.expect_value(t, GetAsepriteWidth(ase), 64)
	testing.expect_value(t, GetAsepriteHeight(ase), 64)
	testing.expect_value(t, GetAsepriteTagCount(ase), 3)
	testing.expect_value(t, GetAsepriteSliceCount(ase), 2)

	TraceAseprite(ase)

	tag := LoadAsepriteTag(ase, "Backwards")
	testing.expect(t, IsAsepriteTagValid(tag))
	testing.expect(t, tag.timer > 0)
	testing.expect_value(t, int(tag.color[0]), 0)
	testing.expect_value(t, int(tag.color[1]), 135)
	testing.expect_value(t, int(tag.color[2]), 81)
	testing.expect_value(t, int(tag.color[3]), 255)
	testing.expect_value(t, tag.name, "Backwards")

	tag2 := LoadAsepriteTagFromIndex(ase, 2)
	testing.expect(t, IsAsepriteTagValid(tag2))
	testing.expect_value(t, tag2.name, "Ping-Pong")
	testing.expect(t, tag2.speed == 1.0)

	SetAsepriteTagFrame(&tag2, 4)
	testing.expect_value(t, GetAsepriteTagFrame(tag2), 4)
	SetAsepriteTagFrame(&tag2, -3)
	testing.expect_value(t, GetAsepriteTagFrame(tag2), 6)

	texture := GetAsepriteTexture(ase)
	testing.expect(t, texture.width > 50)
	testing.expect(t, texture.height > 50)

	rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)
	DrawAseprite(ase, 3, 10, 10, rl.WHITE)
	DrawAsepriteV(ase, 5, rl.Vector2{10, 20}, rl.WHITE)
	DrawAsepriteEx(ase, 6, rl.Vector2{10, 30}, 20, 2, rl.WHITE)
	DrawAsepritePro(
		ase,
		7,
		rl.Rectangle{x = 30, y = 30, width = 20, height = 20},
		rl.Vector2{0, 0},
		0.5,
		rl.WHITE,
	)
	DrawAsepriteTag(tag, 10, 10, rl.WHITE)
	DrawAsepriteTagV(tag, rl.Vector2{10, 20}, rl.WHITE)
	DrawAsepriteTagEx(tag, rl.Vector2{10, 30}, 20, 2, rl.WHITE)
	DrawAsepriteTagPro(
		tag,
		rl.Rectangle{x = 30, y = 30, width = 20, height = 20},
		rl.Vector2{0, 0},
		0.5,
		rl.WHITE,
	)
	rl.EndDrawing()

	before := tag.currentFrame
	update_aseprite_tag_by_delta(&tag, tag.timer + 0.05)
	testing.expect(t, tag.currentFrame != before || tag.paused)

	slice := LoadAsepriteSlice(ase, "Label")
	testing.expect(t, IsAsepriteSliceValid(slice))
	testing.expect_value(t, slice.name, "Label")
	testing.expect(t, slice.bounds.width > 0)
	testing.expect(t, slice.bounds.height > 0)

	slice2 := LoadAsepriteSliceFromIndex(ase, 1)
	testing.expect_value(t, slice2.name, "Number")

	missing := LoadAsepriteSliceFromIndex(ase, 100)
	testing.expect(t, !IsAsepriteSliceValid(missing))

	default_slice := GenAsepriteSliceDefault()
	testing.expect(t, !IsAsepriteSliceValid(default_slice))
}

@(test)
test_all_methods :: proc(t: ^testing.T) {
	test_aseprite_api(t)
}
