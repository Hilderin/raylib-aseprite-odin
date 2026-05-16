# API Documentation - raylib-aseprite-odin

This document explains how to use every public method from the `raylib_aseprite` package.

## Prerequisites

- Initialize raylib before loading any `.aseprite` file:

```odin
rl.InitWindow(800, 450, "My Game")
defer rl.CloseWindow()
```

- `defer` order matters: declare `defer rl.CloseWindow()` before any
  `defer ase.UnloadAseprite(...)` so sprite unloading happens first while the
  raylib context is still alive.
- `defer rl.CloseWindow()` is mandatory in `main`. If it is missing, unloading
  sprite textures at shutdown can hit an invalid raylib/GL context.

```odin
// Wrong: can crash on exit (CloseWindow runs before UnloadAseprite)
sprite := ase.LoadAseprite("assets/player.aseprite")
defer ase.UnloadAseprite(sprite)
defer rl.CloseWindow()

// Wrong: can crash on exit (CloseWindow missing)
sprite2 := ase.LoadAseprite("assets/enemy.aseprite")
defer ase.UnloadAseprite(sprite2)

// Correct: UnloadAseprite runs first, then CloseWindow
defer rl.CloseWindow()
defer ase.UnloadAseprite(sprite)
```

- Imports:

```odin
import ase "raylib_aseprite"
import rl "vendor:raylib"
```

## Public Types

- `Aseprite`: loaded sprite + texture atlas.
- `AsepriteTag`: animation based on an Aseprite tag.
- `AsepriteSlice`: slice rectangle (collision, hitbox, UI area, etc.).

---

## 1) Loading and Lifecycle

### `LoadAseprite(file_name: string) -> Aseprite`
Loads a `.aseprite`/`.ase` file from disk.

Example:

```odin
player := ase.LoadAseprite("assets/player.aseprite")
if !ase.IsAsepriteValid(player) {
    return
}
defer ase.UnloadAseprite(player)
```

### `LoadAsepriteFromMemory(file_data: []u8) -> Aseprite`
Loads an Aseprite file from an Odin memory buffer.

### `LoadAsepriteFromMemory(file_data: [^]u8, size: int) -> Aseprite`
Pointer + size overload (low-level interop).

Example:

```odin
data, err := os.read_entire_file("assets/player.aseprite", context.allocator)
if err == nil {
    defer delete(data)
    player := ase.LoadAsepriteFromMemory(data)
    defer ase.UnloadAseprite(player)
}
```

### `IsAsepriteValid(aseprite: Aseprite) -> bool`
Returns `true` if the sprite was loaded successfully.

### `UnloadAseprite(aseprite: Aseprite)`
Frees GPU texture data and all parsed sprite data.

### `TraceAseprite(aseprite: Aseprite)`
Prints parsed sprite information (size, frames, layers, tags, slices).

---

## 2) Sprite Info + Frame Rendering

### `GetAsepriteTexture(aseprite: Aseprite) -> rl.Texture`
Returns the texture atlas created at load time.

### `GetAsepriteWidth(aseprite: Aseprite) -> int`
Returns single-frame width.

### `GetAsepriteHeight(aseprite: Aseprite) -> int`
Returns single-frame height.

### `DrawAseprite(aseprite, frame, posX, posY, tint)`
Draws one frame at a pixel position.

### `DrawAsepriteFlipped(aseprite, frame, posX, posY, horizontalFlip, verticalFlip, tint)`
Horizontal/vertical flip variant.

### `DrawAsepriteV(aseprite, frame, position, tint)`
Same as above but uses `rl.Vector2`.

### `DrawAsepriteVFlipped(aseprite, frame, position, horizontalFlip, verticalFlip, tint)`
`Vector2` variant with flipping.

### `DrawAsepriteEx(aseprite, frame, position, rotation, scale, tint)`
Draw with rotation + scale.

### `DrawAsepriteExFlipped(aseprite, frame, position, rotation, scale, horizontalFlip, verticalFlip, tint)`
`Ex` variant with flipping.

### `DrawAsepritePro(aseprite, frame, dest, origin, rotation, tint)`
Draw using a destination rectangle (like `DrawTexturePro`).

### `DrawAsepriteProFlipped(aseprite, frame, dest, origin, rotation, horizontalFlip, verticalFlip, tint)`
`Pro` variant with flipping.

Example:

```odin
ase.DrawAseprite(player, 0, 100, 100, rl.WHITE)
ase.DrawAsepriteFlipped(player, 1, 140, 100, true, false, rl.WHITE)
ase.DrawAsepriteEx(player, 2, rl.Vector2{220, 120}, 0, 3, rl.WHITE)
```

---

## 3) Tags (Animations)

### `GetAsepriteTagCount(aseprite: Aseprite) -> int`
Returns number of tags in the sprite.

### `GenAsepriteTagDefault() -> AsepriteTag`
Creates an empty/default tag.

### `LoadAsepriteTagFromIndex(aseprite: Aseprite, index: int) -> AsepriteTag`
Loads a tag by index.

### `LoadAsepriteTag(aseprite: Aseprite, name: string) -> AsepriteTag`
Loads a tag by name.

### `IsAsepriteTagValid(tag: AsepriteTag) -> bool`
Returns whether the tag is valid.

### `UpdateAsepriteTag(tag: ^AsepriteTag)`
Updates animation using `rl.GetFrameTime()`.

### `SetAsepriteTagFrame(tag: ^AsepriteTag, frameNumber: int)`
Sets the current frame relative to the tag range.
- `frameNumber >= 0`: from tag start
- `frameNumber < 0`: from tag end

### `GetAsepriteTagFrame(tag: AsepriteTag) -> int`
Returns the current frame index relative to the tag start.

### Tag Rendering

- `DrawAsepriteTag`
- `DrawAsepriteTagFlipped`
- `DrawAsepriteTagV`
- `DrawAsepriteTagVFlipped`
- `DrawAsepriteTagEx`
- `DrawAsepriteTagExFlipped`
- `DrawAsepriteTagPro`
- `DrawAsepriteTagProFlipped`

Behavior is the same as `DrawAseprite*` variants, but uses `tag.currentFrame`.

Example:

```odin
walk := ase.LoadAsepriteTag(player, "Walk-Down")
walk.speed = 1.5
walk.loop = true

for !rl.WindowShouldClose() {
    ase.UpdateAsepriteTag(&walk)

    rl.BeginDrawing()
    rl.ClearBackground(rl.RAYWHITE)
    ase.DrawAsepriteTagEx(walk, rl.Vector2{200, 120}, 0, 4, rl.WHITE)
    rl.EndDrawing()
}
```

---

## 4) Slices

### `GenAsepriteSliceDefault() -> AsepriteSlice`
Returns an empty slice (`name == ""`).

### `LoadAsepriteSliceFromIndex(aseprite: Aseprite, index: int) -> AsepriteSlice`
Loads a slice by index.

### `LoadAsepriteSlice(aseprite: Aseprite, name: string) -> AsepriteSlice`
Loads a slice by name.

### `GetAsepriteSliceCount(aseprite: Aseprite) -> int`
Returns number of defined slices.

### `IsAsepriteSliceValid(slice: AsepriteSlice) -> bool`
Returns `true` when a slice is valid.

Example:

```odin
hitbox := ase.LoadAsepriteSlice(player, "Hitbox")
if ase.IsAsepriteSliceValid(hitbox) {
    // hitbox.bounds: x, y, width, height
}
```

---

## Full Example

```odin
package main

import ase "raylib_aseprite"
import rl "vendor:raylib"

main :: proc() {
    rl.InitWindow(800, 450, "Aseprite Example")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    sprite := ase.LoadAseprite("assets/george.aseprite")
    if !ase.IsAsepriteValid(sprite) {
        return
    }
    defer ase.UnloadAseprite(sprite)

    walk := ase.LoadAsepriteTag(sprite, "Walk-Down")
    walk.speed = 2.0

    for !rl.WindowShouldClose() {
        ase.UpdateAsepriteTag(&walk)

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        // Static frame
        ase.DrawAseprite(sprite, 0, 80, 100, rl.WHITE)

        // Tag animation
        ase.DrawAsepriteTagEx(walk, rl.Vector2{220, 120}, 0, 4, rl.WHITE)

        rl.EndDrawing()
    }
}
```

## Best Practices

- Always call `UnloadAseprite`.
- Always call `CloseWindow` (usually with `defer rl.CloseWindow()`).
- Declare `defer rl.CloseWindow()` before `defer ase.UnloadAseprite(...)` (defer is LIFO).
- Check `IsAsepriteValid` after loading.
- Call `UpdateAsepriteTag` every frame for animated tags.
- Load only after `InitWindow` (texture creation needs a valid raylib context).
