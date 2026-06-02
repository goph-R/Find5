# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Find5 is a minimal 2D game engine starter forked from SDLFun. Same retro target span: **Windows 98** (Dev-C++ / MinGW 3.4, SDL 1.2, fixed-function OpenGL, OpenAL Soft 1.9.563) up to modern Linux/Windows. The "runs on a Pentium 4" constraint is deliberate — no C++11 features, no shaders, no modern GL, header-only modules, static-libgcc linking for the Win10 build.

**Minimum GPU: GeForce 4 MX 440 32MB.** DX7-class, 2 TMUs, 32-bit color, GL 1.3, no programmable shaders.

Compared to SDLFun (the parent project), this fork removes: Bullet physics, FPS controls, OBJ/MTL/IQM model loading, dynamic lightmap / flashlight, nav graph, level entity system, Quake-style dev console, menu/dialog screen stack. What's left is the audio/scripting/2D-rendering core.

## Build commands

There are **four** independent build systems, each for a different target. They all compile `main.cpp` + Lua + stb_vorbis.

| Target | Command | Output |
|---|---|---|
| Linux (system SDL) | `make` (needs `libsdl1.2-dev`, `libopenal-dev`) | `find5` |
| Windows 98 / Dev-C++ | `build.bat` (uses `C:\Dev-Cpp\bin\g++.exe`) | `Find5.exe` |
| Windows 10 (portable WinLibs MinGW in `vendor_win10/`) | `build_win10.bat` | `Find5_w10.exe` |
| CMake | `mkdir build && cd build && cmake .. && make` — add `-DUSE_VENDOR_SDL=ON` to use vendored SDL | `Find5` |

Audio is OpenAL 1.1 / OpenAL Soft via the header-only wrapper in `sound.h`. The repo vendors `OpenAL32.dll` (1.25.1, used on Win10) — for the Win98 target, swap in `OpenAL32-win98.dll` (1.9.563, the only release tested working on Win98) and rename it to `OpenAL32.dll` next to the exe.

There are no tests and no lint step.

## Running

Run the built executable from the repo root — it reads everything under `assets/` and `scripts/` as **relative paths**. `cd build && ./find5` will fail to find assets.

Flow: app boots, loads `assets.lua` (sounds/music/textures/fonts manifest), runs `scripts/main.lua`, calls `onStart()`. The starter `onStart` plays the title OGG and shows a transient HUD message. Window stays open until Esc or close-button. F2 retriggers the `jump` sound for audio sanity-check.

Windows-specific: SDL 1.2's fullscreen path drops the monitor's refresh rate to 60Hz because it calls `ChangeDisplaySettings` without a frequency. `main.cpp` samples the configured desktop rate via `EnumDisplaySettings(ENUM_REGISTRY_SETTINGS)` before `SDL_Init` and re-applies it with `ChangeDisplaySettingsEx` after `SDL_SetVideoMode` when `-fullscreen` is passed. No-op on Linux.

### Headless sanity-check (CI / no audio device)

To boot the game in an environment with no audio device — typical for the harness running these tasks — three pieces matter, in order:

1. **OpenAL needs a backend that doesn't require hardware.** `SDL_AUDIODRIVER=dummy` is **not enough**: OpenAL Soft has its own backend chain independent of SDL. Set `ALSOFT_DRIVERS=null` (or `ALSOFT_DRIVERS=oss,alsa,null` if you want a real device when available, with null as fallback). Without this, `sndInit` returns 1 and `main` exits before Lua loads — you'll see `OpenAL: alcOpenDevice failed` and never reach `scripts/main.lua`.
2. **Pipe stdout to a file**, not to `| head` or similar. `conLogf` writes to stdout, which goes block-buffered the moment it's not a terminal. A `SIGTERM` from `timeout` (or anything else) kills the process **without flushing libc's stdout buffer**, so the captured pipe is empty even though the program ran fine. Redirecting to a file lets the kernel surface whatever has been flushed; in practice all the boot-time `conLogf` lines have flushed by the first frame.
3. **Bound the run with `timeout`** and use `-windowed` so SDL doesn't try to change video modes. SDL 1.2 creates a window but does not need one to be visible to render — boot-time asset registration, Lua require, and `onStart` all run.

The incantation that has worked reliably:

```bash
env ALSOFT_DRIVERS=null timeout 1.5 ./find5 -windowed > /tmp/find5.out 2>&1
sed -n '1,40p' /tmp/find5.out      # or grep for what you're checking
```

A clean boot prints, in order: `Resolution: …`, font atlas built, `optLoad` reading or skipping `find5.dat`, `script: Lua 5.1 initialised`, each asset's load line, `assets: N sound(s), M music, …`, then nothing more until you SIGTERM it. Anything else (e.g. `script:` followed by a Lua traceback, `texBlur: cannot load …`) is a real error worth reading.

This is enough to confirm "did my Lua syntax compile, did `require` resolve, did the assets register", which covers most refactor regressions. For anything that actually needs to render — colors / layout / animation timing — open it on the dev box; there's no headless visual check.

## Architecture

### Header-only modules included from main.cpp

The whole engine is `main.cpp` plus header-only modules with `static` functions. Include order in `main.cpp` matters — `script.h` depends on `ui.h`, `sound.h`, `music.h`, and `asset_registry.h` already being included.

- `texture.h` — PNG loader (wraps `stb_image` from `vendor/stb/stb_image.h`; the `STB_IMAGE_IMPLEMENTATION` lives here, so any other module that needs `stbi_load` must be included after texture.h). `loadTextureExA(path, wrapMode, keepAlpha)` is the single entry point. Paired with a `TexCache` keyed by `(path, wrapMode, keepAlpha)`.
- `ui.h` — 2D/HUD primitives. Draws on a **virtual canvas**: 540 units tall, width scales with aspect ratio, origin at screen center with Y growing down. The 2D engine renders entirely within `uiBegin`/`uiEnd` — calls between them assume ortho-mode GL state (depth off, blend on, GL_MODULATE). `uiQuad` (flat color), `uiIcon` (textured), `uiText` (BMFont + 8x8 fallback). Sprite drawing in this engine is just `uiIcon` with a loaded texture.
- `sound.h` — OpenAL wrapper. `sndInit` opens the device, `sndLoadWav` reads a 16-bit PCM WAV, `SoundLibrary` is the named registry (groups of variants picked randomly), `sndPlay` fires on a free source.
- `music.h` — Streaming Ogg Vorbis via stb_vorbis (compiled as its own C TU in `vorbis.o`). `MusicLibrary` is a name→path map; files open lazily on `musicPlay`. Crossfade-capable across 2 simultaneous tracks. Call `musicUpdate(&mus, dt)` once per frame.
- `asset_registry.h` — name → path lookup for textures (and unused model slots inherited from SDLFun). `assets.lua` populates it via `scriptLoadAssets`.
- `script.h` — Lua 5.1 glue. `ScriptSystem` holds the `lua_State` plus borrowed pointers to UiState/SoundSystem/SoundLibrary/MusicSystem/MusicLibrary/AssetRegistry/TexCache. Bindings exposed to Lua: `uiShowMessage`, `soundPlay`, `musicPlay`, `musicStop`, `musicVolume`, `keyDown`, `mousePos`, `mouseDown`, `drawRegion`, `drawText`, `drawEllipse`, `optSet`, `optGet`, `optSave`, `optLoad`. Lua globals set at init: `ALIGN_LEFT/CENTER/RIGHT/TOP/MIDDLE/BOTTOM`, `FLIP_H/FLIP_V`. `scriptLoadAssets` walks the manifest's `sounds` / `music` / `textures` / `fonts` / `regions` subtables and registers each. `scriptCall(s, "onStart")` invokes a nullary global Lua function if defined; `scriptCallUpdate` / `scriptCallKeyDown` / `scriptCallKeyUp` / `scriptCallMouseDown` / `scriptCallMouseUp` / `scriptCallMouseMove` / `scriptCallRender` call the corresponding `on_*` hooks. Missing hooks are no-ops. Two-phase `scriptBeginHook`/`scriptEndHook` is exposed for callers that need to push custom argument types. Reusable options-table helpers (`scrOptfieldNum/int/str/color`) for any binding that wants `{ k = v }` style args. The options store auto-loads from `find5.dat` during `scriptInit` (see "Persistence" below).
- `math.h` — Vec2/Vec3 type definitions. Engine-wide API boundary types.

`main.cpp` defines `conLogf` as a printf wrapper near the top (forward-declared before any module include so headers can call it). This replaces SDLFun's dev-console scrollback — Find5's "console" is just stdout.

### Rendering pipeline

There is no 3D pipeline. Each frame:
1. `glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)`
2. `uiBegin(&ui)` — sets ortho projection (center origin, Y-down, 540-unit virtual height), disables depth/lighting/cull, enables alpha blend.
3. Draw calls — `uiIcon`, `uiText`, `uiQuad`, `uiBar` in any order.
4. `uiEnd(&ui)` — pops projection, restores depth/cull state.
5. `SDL_GL_SwapBuffers()`.

To add a sprite: load the texture once via `loadTextureExA` (or look it up by name from the `AssetRegistry` populated from `assets.lua`), keep the `GLuint` somewhere, then call `uiIcon({x, y, w, h}, tex)` inside the uiBegin/uiEnd block each frame.

### Asset flow

1. `assets.lua` declares logical names → file paths for sounds, music, textures, fonts.
2. At startup, `scriptLoadAssets("assets.lua")` walks it: sounds are preloaded into `SoundLibrary`, music paths are registered (decode happens lazily on first play), texture paths are stored in `AssetRegistry`, fonts are loaded into the UI font library.
3. Texture decoding is on-demand: call `assetRegFindTexture(&reg, "name")` to get the path, then `loadTextureExA` to upload. Use `TexCache` (in `texture.h`) if you want dedup across multiple resolve sites.
4. `scripts/main.lua` runs once after asset load; `onStart()` is the conventional entry point for opening music and showing a welcome message.

### Input

Lua game code reacts to input via callback hooks (transient events) and polling helpers (continuous state). Both are wired up by `main.cpp`'s event loop.

**Hooks** — all optional; missing hooks are no-ops:
- `onUpdate(dt)` — fired every frame before render, `dt` in seconds.
- `onKeyDown(name)` / `onKeyUp(name)` — `name` is `SDL_GetKeyName`'s lowercase form (`"space"`, `"escape"`, `"left"`, `"a"`, `"1"`, `"f1"`). Use `print(name)` to discover names empirically.
- `onMouseDown(x, y, button)` / `onMouseUp(x, y, button)` — `x, y` in **virtual canvas** coords (center origin, Y-down, ~540 units tall — same coords you draw into with `uiIcon`/`uiText`). Button: 1=left, 2=middle, 3=right, 4=wheel-up, 5=wheel-down.
- `onMouseMove(x, y, dx, dy)` — virtual-canvas coords + deltas. Deltas are scaled from raw SDL pixel deltas (`event.motion.xrel`) by the virtual-canvas ratio so they match the coord space.

**Polling** (call any time, including from `onUpdate`):
- `keyDown(name)` → bool.
- `mousePos()` → x, y (virtual coords).
- `mouseDown(button)` → bool.

Esc is hardcoded in `main.cpp` as a quit kill-switch (so a buggy script can't lock the user in). The Lua `onKeyDown` still receives `"escape"` so game code can react if it wants.

Key-name lookup in `keyDown` is a linear scan of `SDLK_FIRST..SDLK_LAST` via `SDL_GetKeyName` (no reverse map in SDL 1.2). It's ~300 strcmps per call — cheap enough for typical games but worth a small cache if a script polls hundreds of keys per frame.

### Rendering from Lua

The engine drives the frame: clears the GL buffer, calls `uiBegin`, fires `onRender()`, calls `uiDrawMessage` (engine HUD overlay), calls `uiEnd`, swaps buffers. All Lua draw calls happen inside `onRender`, where the ortho virtual canvas is already set up.

**Regions**: drawable units are *regions* (sub-rectangles of a texture, declared in `assets.lua` under `regions = { name = { tex="texname", x=N, y=N, w=N, h=N } }`). `x, y, w, h` are source-texture pixels. Atlases live by packing many regions into one texture.

```lua
drawRegion(name, x, y [, align [, flip [, fillX [, fillY]]]])
```

- `name` — region key. No fallback path lookup; the region must be registered.
- `x, y` — anchor point in virtual-canvas coords. Which corner/edge/center the anchor refers to is set by `align`.
- `align` — bitmask, horizontal+vertical OR'd: `ALIGN_LEFT=1 | ALIGN_CENTER=2 | ALIGN_RIGHT=4`, `ALIGN_TOP=8 | ALIGN_MIDDLE=16 | ALIGN_BOTTOM=32`. Default (0 in either axis) = `TOP+LEFT`.
- `flip` — bitmask: `FLIP_H=1 | FLIP_V=2`. Implemented by swapping UVs, no GL state cost.
- `fillX, fillY` — fractions in `[0,1]`, default 1.0. Less than 1 clips the region **from the edge opposite the anchor** (LEFT-anchored + `fillX=0.5` keeps the left half; RIGHT keeps the right half; CENTER clips both sides equally). Both source UVs and destination size shrink in lockstep — no stretching.

Drawn 1:1 — one source pixel = one virtual-canvas unit. (Scaling is a future param, not exposed yet.)

**Texture UV math** needs the source texture's pixel dimensions, so `TexCacheEntry` carries `w, h` and `texCacheGetA` surfaces them via optional out-params. `loadTextureExA` also has matching out-params for callers that bypass the cache. The shared `TexCache` lives in `main.cpp` and is plumbed into `scriptInit` so C and Lua share one cache — no duplicate uploads.

**Options-table form** for `drawRegion` / `drawText` / `drawEllipse`: when the next-to-required arg is a table, fields are read by name. Backward-compat positional form still works for the simple cases.

```lua
drawRegion("logo", x, y, {
    align = ALIGN_CENTER + ALIGN_MIDDLE,
    flip  = FLIP_H,
    fillX = 0.5, fillY = 1.0,
    scale = 1.5,                    -- uniform; scaleX and scaleY override per-axis
    alpha = 0.8,
    color = { 1, 0.7, 0.7 },        -- RGB tint, optional alpha as 4th
})

drawText("HELLO", x, y, {
    scale = 3.0,
    font  = "orbitron",
    align = ALIGN_CENTER + ALIGN_MIDDLE,
    color = { 1, 1, 0 },
})

drawEllipse(cx, cy, rx, ry, {
    start     = 0.0, finish = 0.5,  -- tween `finish` 0..1 for the "drawing" animation
    segments  = 80,
    thickness = 2.5,
    color     = { 1, 0.3, 0.3, fade_alpha },
})
```

**`drawText` align mapping**: the Lua-facing `ALIGN_*` bits differ from `ui.h`'s internal `UI_ALIGN_*` (different historical layout). `scrDrawText` translates between them, so scripts only ever see one convention. If you add another text-drawing binding later, reuse the same translation.

**`drawEllipse` thickness**: implemented via `glLineWidth`. Old Mesa/DRI drivers and very old GPUs may clamp to 1.0 — on a real GeForce 4 MX 440 it works up to ~10. If you need consistently thick strokes across all targets, the next step is to draw quad-strips instead of `GL_LINE_STRIP`.

### Canvas size

`UI_VIRTUAL_H = 480` for Find5 — matches the 4:3 / 640×480 game design target so one source pixel maps 1:1 to one virtual unit at the reference resolution. If you fork the engine for a different art scale, change that constant in `ui.h` (everything else in the renderer derives from it).

### Persistence

Key-value options store backed by a single file `find5.dat` next to the exe. `io` is sandboxed so scripts can't write files directly — this is the supported path.

```lua
optSet("sound_on", true)            -- value can be string/number/boolean/table
optSet("hs_portraits", { 5200, 4100 })
optSave()                           -- explicit; call after batched changes

local sound = optGet("sound_on", true)   -- default applies if unset (forward-compat)
```

Auto-loaded by `scriptInit` before the entry script runs, so options are ready at `onStart`. `optLoad()` can be called manually to revert to last-saved state. Atomic save via write-to-tmp + rename. The serializer (`opt_writeValue` / `opt_writeTable` in `script.h`) handles nested tables, escapes strings, detects array-shaped tables for compact output, brackets non-identifier and Lua-keyword keys, and caps recursion depth at 16 to avoid cycles. Functions / userdata / threads / mixed-type keys are silently skipped — not persistable.

The file format is `return { ... }` and is loaded via `luaL_loadfile` + `lua_pcall` on the C side (bypassing the user-side `dofile` ban). Corruption falls back to empty options with a log message; it never crashes.

## Lua naming convention

Case depends on *where the name sits*, not what it means:

- **camelCase** — code identifiers (functions, locals, table fields):
  `drawRegion`, `rectContains`, `onUpdate`.
- **snake_case** — string-literal IDs typed in quotes (asset / sound /
  region names, option keys, state tags), including every `assets.lua` key:
  `drawRegion("close_icon")`, `soundPlay("wrong")`, `optGet("music_on")`,
  `local STATE_GAME_OVER = "game_over"`.
- **UPPER_SNAKE_CASE** — constants (`ALIGN_CENTER`, `STATE_PLAYING`);
  **CamelCase** — classes.

So one logical name may appear in two casings by role, e.g.
`local musicOn = optGet("music_on")`. Event hooks are `on` + CamelCase event,
single- or multi-word alike (`onUpdate`, `onRender`, `onMouseDown`,
`onKeyDown`, `onTextInput`); scene methods drop the `on` (`:update(dt)`,
`:mouseDown(x, y, b)`, `:keyDown(name)`), kept in lockstep with the C hook
strings. Region IDs are built by string
(`region = "category_" .. c.id`), so they must stay snake_case. C bindings
expose a camelCase name (`lua_register(L, "drawText", scrDrawText)`) while
the C wrapper is named `scrCamelCase` — rename both sides together. Full rule
lives in `../SOOB-Core/CLAUDE.md`.

## Constraints worth knowing before editing

- **No C++11.** Dev-C++ 4.x ships GCC 3.4. No `auto`, no `nullptr`, no range-for, no `<cstdint>`. Use C-style `NULL`, explicit types, classic `for (int i = 0; ...)`. C-style casts and `malloc`/`free` are used consistently rather than `new`/`delete`.
- **No shaders.** Fixed-function only.
- **Assets are relative-pathed.** Don't add `chdir` calls or absolute-path asset lookups.
- **Header-only modules with `static` functions.** Don't split a module into .h/.cpp — every target compiles a single TU (`main.cpp`) plus Lua plus stb_vorbis. If you add a new module, follow the header-only `static` convention.
- **Forward-declare conLogf before any module include.** Every engine header calls it; main.cpp provides the printf-wrapper definition after the includes.
