# raylib-aseprite-odin

A fully native Odin package to load [Aseprite](https://www.aseprite.org/) files (`.aseprite` / `.ase`) and use them directly with [`vendor:raylib`](https://pkg.odin-lang.org/vendor/raylib/) (Odin builtin binding).

This project is an Odin port of the [`raylib-aseprite`](https://github.com/RobLoach/raylib-aseprite) API, without binding to the original C implementation.

## Features

- Load Aseprite sprites from file or memory
- Build a texture atlas for frame-by-frame rendering
- Handle Aseprite tags (forwards, backwards, ping-pong)
- Handle Aseprite slices
- Rendering helpers equivalent to the C library (`DrawAseprite*`, `DrawAsepriteTag*`)
- Unit tests + runnable examples

## Installation

Clone [this repository](.), then import the package either with a relative import or an Odin collection.

### Simple option (relative import)

```odin
import ase "../path/to/raylib-aseprite-odin"
```

### Recommended option (collection)

```bash
odin run . -collection:raylib_aseprite=/path/to/raylib-aseprite-odin
```

Then in your code:

```odin
import ase "raylib_aseprite"
```

## Quick Start

```odin
package main

import ase "../.."
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "Aseprite + raylib + Odin")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	sprite := ase.LoadAseprite("examples/resources/george.aseprite")
	defer ase.UnloadAseprite(sprite)

	anim := ase.LoadAsepriteTag(sprite, "Walk-Down")

	for !rl.WindowShouldClose() {
		ase.UpdateAsepriteTag(&anim)

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		ase.DrawAsepriteTagEx(anim, rl.Vector2{200, 120}, 0, 4, rl.WHITE)
		rl.EndDrawing()
	}
}
```

## API

Detailed method-by-method documentation: [`DOCUMENTATION.md`](./DOCUMENTATION.md)

### Aseprite

- `LoadAseprite`
- `LoadAsepriteFromMemory`
- `IsAsepriteValid`
- `UnloadAseprite`
- `TraceAseprite`
- `GetAsepriteTexture`
- `GetAsepriteWidth`
- `GetAsepriteHeight`
- `DrawAseprite`, `DrawAsepriteFlipped`, `DrawAsepriteV`, `DrawAsepriteVFlipped`
- `DrawAsepriteEx`, `DrawAsepriteExFlipped`, `DrawAsepritePro`, `DrawAsepriteProFlipped`

### Tags

- `LoadAsepriteTag`
- `LoadAsepriteTagFromIndex`
- `GetAsepriteTagCount`
- `IsAsepriteTagValid`
- `UpdateAsepriteTag`
- `SetAsepriteTagFrame`
- `GetAsepriteTagFrame`
- `DrawAsepriteTag*`

### Slices

- `LoadAsepriteSlice`
- `LoadAsepriteSliceFromIndex`
- `GetAsepriteSliceCount`
- `IsAsepriteSliceValid`
- `GenAsepriteSliceDefault`

## Examples

Two examples are included:

- `examples/basic/main.odin`
- `examples/numbers/main.odin`

Run:

```bash
odin run examples/basic
odin run examples/numbers
```

## Tests

```bash
odin test .
```

The main test file is [`raylib_aseprite_test.odin`](./raylib_aseprite_test.odin).

## Project Structure

- [`raylib_aseprite.odin`](./raylib_aseprite.odin): main implementation (parser + rendering + API)
- [`raylib_aseprite_test.odin`](./raylib_aseprite_test.odin): unit tests
- [`examples/`](./examples/): raylib demos
- [`resources/`](./resources/): assets used by tests

## Notes

- The parser supports the main chunks used by the original library (layers, cels, tags, palette, slices).
- Animation playback uses `rl.GetFrameTime()` in `UpdateAsepriteTag`.
- The package requires an initialized raylib window before loading (`InitWindow`).
- Important: always register `defer rl.CloseWindow()` in `main`.
- Important: register `defer rl.CloseWindow()` before any `defer ase.UnloadAseprite(...)`.
  Odin executes `defer` in reverse order, so this guarantees `UnloadAseprite` runs while the raylib context is still valid.

Correct defer order:

```odin
// Wrong: can crash on exit (CloseWindow runs before UnloadAseprite)
sprite := ase.LoadAseprite("assets/player.aseprite")
defer ase.UnloadAseprite(sprite)
defer rl.CloseWindow()

// Correct: UnloadAseprite runs first, then CloseWindow
defer rl.CloseWindow()
defer ase.UnloadAseprite(sprite)
```

## Credits

- Original API: [`raylib-aseprite`](https://github.com/RobLoach/raylib-aseprite) by [Rob Loach](https://github.com/RobLoach)
- Reference format/parser: [`cute_aseprite`](https://github.com/RandyGaul/cute_headers/blob/master/cute_aseprite.h) by [Randy Gaul](https://github.com/RandyGaul)
- Odin port: [this repository](.)

## License

This project is licensed under the same zlib/libpng license used by the original
[`raylib-aseprite`](https://github.com/RobLoach/raylib-aseprite) project.

- Original project: [`raylib-aseprite`](https://github.com/RobLoach/raylib-aseprite) by [Rob Loach](https://github.com/RobLoach)
- This repository is an altered source version (a 100% Odin port)
- Full license text: [`LICENSE`](./LICENSE)
