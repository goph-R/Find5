# Find5

A 2D spot-the-difference game targeting everything from Windows 98 (Pentium 4, SDL 1.2, fixed-function OpenGL) through modern Linux and Windows.

The shared engine — audio, scripting, 2D rendering, asset registry — lives in [**goph-R/SOOB-Core**](https://github.com/goph-R/SOOB-Core) and is also consumed by [goph-R/SOOB-Engine](https://github.com/goph-R/SOOB-Engine) (the 3D FPS). Find5 itself is just `main.cpp` + Lua scripts + assets.

## Depends on SOOB-Core

Clone the shared engine next to this repo before building:

```
Win98/
├── Find5/         ← this repo
├── SOOB-Core/     ← clone alongside
└── SOOB-Engine/   ← optional, shares the same engine
```

```sh
git clone git@github.com:goph-R/SOOB-Core.git
```

Build scripts add `-I../SOOB-Core/` so `#include "script.h"` etc. resolve into the shared engine. Engine-side Lua modules (e.g. `engine.scene`) are copied next to the .exe at build time.

## Building

See `CLAUDE.md` for the full build matrix and toolchain details.

Quick reference:
- **Linux**: `make` (needs `libsdl1.2-dev`, `libopenal-dev`) → `find5`
- **Windows 98 / Dev-C++**: `build.bat` → `Find5.exe`
- **Windows 10 / portable MinGW**: `build_win10.bat` → `Find5_w10.exe`
- **CMake**: `mkdir build && cd build && cmake .. && make`

## Running

Run the executable from the repo root — assets are loaded by relative path.

The game: pick 5 differences between two portrait images per level, 10 levels per run, with a timer + jokers + per-category highscores. Click either image to mark a find; the joker button reveals the first unfound difference (yellow ellipse vs. green for player finds). Miss-click penalises ¼ of the remaining time. Pause / level-complete / game-over / all-done all open animated modal dialogs (drop-in with `easeOutBounce`, shoot-up exit with `easeInExpo`). Design notes: [`docs/game-plan.md`](docs/game-plan.md), [`docs/menu-plan.md`](docs/menu-plan.md).

CLI flags: `-w <width>`, `-h <height>`, `-fullscreen`.

## Input (Lua side)

Hooks (all optional, define in `scripts/main.lua`):

```lua
function onUpdate(dt) end
function onKeyDown(name) end             -- "space", "left", "a", "f1" ...
function onKeyUp(name) end
function onMouseDown(x, y, button) end   -- 1=L, 2=M, 3=R, 4=wheel-up, 5=wheel-down
function onMouseUp(x, y, button) end
function onMouseMove(x, y, dx, dy) end
```

Polling (anywhere):
- `keyDown(name) -> bool`
- `mousePos() -> x, y`
- `mouseDown(button) -> bool`

Mouse coords are in the **virtual canvas** (center origin, Y-down, ~540 units tall) — the same coord space `drawRegion` / `drawText` draw into.

## Rendering from Lua

Draw calls go inside `onRender()`. The unit of drawing is a **region** — a named sub-rectangle of a texture, declared in `assets.lua`:

```lua
-- assets.lua
textures = { sprite = "assets/textures/logo.png" }
regions  = { logo   = { tex = "sprite", x = 0, y = 0, w = 256, h = 64 } }
```

```lua
-- scripts/main.lua
function onRender()
    drawRegion("logo", player.x, player.y, ALIGN_CENTER + ALIGN_MIDDLE)
end
```

`drawRegion(name, x, y [, align [, flip [, fillX [, fillY]]]])`:

- **align** — `ALIGN_LEFT=1 | ALIGN_CENTER=2 | ALIGN_RIGHT=4` (horizontal) OR `ALIGN_TOP=8 | ALIGN_MIDDLE=16 | ALIGN_BOTTOM=32` (vertical). Bit-OR them; default (0 or omitted) = TOP-LEFT.
- **flip** — `FLIP_H=1 | FLIP_V=2`. Default 0.
- **fillX, fillY** — fractions in `[0,1]`, default 1.0. Less than 1 clips the region from the side **opposite** the anchor — perfect for progress bars:

```lua
-- HP bar at 60%, anchored at top-left of (50, 50), drains rightward:
drawRegion("hpbar", 50, 50, ALIGN_LEFT + ALIGN_TOP, 0, hp / max_hp)
```

Drawn 1:1 (one source pixel = one virtual-canvas unit, where the canvas is 480 units tall — matching Find5's 4:3 / 640×480 design target — and width scales with aspect). Textures and regions are lazy-loaded and cached.

Other rendering bindings (all support an options-table for color/alpha/etc.):

```lua
drawText("HELLO", x, y, { scale = 3, font = "orbitron",
                          align = ALIGN_CENTER + ALIGN_MIDDLE,
                          color = { 1, 1, 0 } })

-- "Drawing" animation: tween `finish` 0 → 1 over time and the arc fills in.
drawEllipse(cx, cy, rx, ry, { finish = anim_t, thickness = 3,
                              color = { 1, 0.3, 0.3, 1 - fade_t } })
```

See `docs/game-plan.md` for the full design of the Find5 game built on this engine.

## Customizing

- Add a sprite: drop a PNG in `assets/textures/`, register it in `assets.lua` under `textures`, then in `main.cpp` look it up via `assetRegFindTexture(&assetReg, "name")` and load with `loadTextureExA`. Draw it inside the `uiBegin`/`uiEnd` block with `uiIcon`.
- Add a sound: drop a 16-bit PCM WAV in `assets/sounds/`, register it in `assets.lua` under `sounds`, then call `soundPlay("name")` from Lua or `sndPlay(&snd, sndLibPick(&sndLib, "name"))` from C.
- Add a music track: drop an OGG in `assets/music/`, register in `assets.lua` under `music`, then `musicPlay("name")` from Lua.

## Credits and licensing

### Code

Engine source (everything outside `vendor/` and `vendor_win10/`) is MIT-licensed — see [LICENSE](LICENSE). Bundled third-party libraries retain their own licenses:

| Library | License | Usage |
|---|---|---|
| SDL 1.2 | LGPL 2.1 | dynamically linked (`SDL.dll`) |
| OpenAL Soft | LGPL 2.1 | dynamically linked (`OpenAL32.dll`) |
| Lua 5.1.5 | MIT | compiled from vendored source |
| stb_image, stb_vorbis | Public Domain / MIT | compiled from vendored source |

### Assets

All assets carried over from SDLFun are **© Dynart**, all rights reserved. Exceptions:
- `assets/fonts/orbitron*.fnt` + `assets/fonts/orbitron*_0.png` — BMFont bakes of Orbitron by Matt McInerney, licensed under the SIL Open Font License 1.1.
