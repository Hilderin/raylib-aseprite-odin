package main

import ase "../.."
import "core:strings"
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "[raylib-aseprite] numbers")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	numbers := ase.LoadAseprite("examples/resources/numbers.aseprite")
	defer ase.UnloadAseprite(numbers)

	forwards := ase.LoadAsepriteTag(numbers, "Forwards")
	backwards := ase.LoadAsepriteTag(numbers, "Backwards")
	pingpong := ase.LoadAsepriteTag(numbers, "Ping-Pong")

	for !rl.WindowShouldClose() {
		ase.UpdateAsepriteTag(&forwards)
		ase.UpdateAsepriteTag(&backwards)
		ase.UpdateAsepriteTag(&pingpong)

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		width := i32(ase.GetAsepriteWidth(numbers))
		text_top := i32(140)
		number_top := int(200)
		x_forwards := int(rl.GetScreenWidth() / 4 - width)
		x_backwards := int(rl.GetScreenWidth() / 2 - width)
		x_pingpong := int(rl.GetScreenWidth() - rl.GetScreenWidth() / 4 - width)

		f_name, _ := strings.clone_to_cstring(forwards.name)
		b_name, _ := strings.clone_to_cstring(backwards.name)
		p_name, _ := strings.clone_to_cstring(pingpong.name)

		rl.DrawText(f_name, i32(x_forwards), text_top, 20, forwards.color)
		ase.DrawAsepriteTag(forwards, x_forwards, number_top, rl.WHITE)

		rl.DrawText(b_name, i32(x_backwards), text_top, 20, backwards.color)
		ase.DrawAsepriteTag(backwards, x_backwards, number_top, rl.WHITE)

		rl.DrawText(p_name, i32(x_pingpong), text_top, 20, pingpong.color)
		ase.DrawAsepriteTag(pingpong, x_pingpong, number_top, rl.WHITE)

		delete(f_name)
		delete(b_name)
		delete(p_name)

		rl.EndDrawing()
	}
}
