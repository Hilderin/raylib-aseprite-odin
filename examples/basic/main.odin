package main

import ase "../.."
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "[raylib-aseprite] basic")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	george := ase.LoadAseprite("examples/resources/george.aseprite")
	defer ase.UnloadAseprite(george)

	walking := ase.LoadAsepriteTag(george, "Walk-Down")

	scale := f32(4)
	position := rl.Vector2 {
		f32(rl.GetScreenWidth()) / 2 - f32(ase.GetAsepriteWidth(george)) * scale / 2,
		f32(rl.GetScreenHeight()) / 2 - f32(ase.GetAsepriteHeight(george)) * scale / 2,
	}

	for !rl.WindowShouldClose() {
		ase.UpdateAsepriteTag(&walking)

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		ase.DrawAseprite(george, 0, 100, 100, rl.WHITE)
		ase.DrawAseprite(george, 4, 100, 150, rl.WHITE)
		ase.DrawAseprite(george, 8, 100, 200, rl.WHITE)
		ase.DrawAsepriteFlipped(george, 12, 100, 250, false, true, rl.WHITE)
		ase.DrawAsepriteTagEx(walking, position, 0, scale, rl.WHITE)
		rl.EndDrawing()
	}


}
