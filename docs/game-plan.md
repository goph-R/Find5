# Find5 — Game Plan

A spot-the-difference puzzle game built on the Find5 engine. Player has to find 5 differences between two portrait images before a timer runs out. 5 single-use "joker" hints can reveal one difference each. Score is added at level-end based on unused time and unused jokers; harder levels (less time) reward more.

## Visual layout

- **Aspect ratio**: fixed 4:3.
- **Virtual canvas**: 640 × 480 (so `UI_VIRTUAL_H = 480`, center origin, Y-down).
- **Background**: one 640×480 PNG, drawn full-canvas as the bottom layer of every screen (level, dialog, etc.). All other UI sits on top.

```
  (-320, -240)                                                  (320, -240)
       ┌──────────────────────────────────────────────────────────┐
       │  TOP ROW  (≈ 60 units tall)                              │
       │  ┌──────┐  ┌────────────────────────┐  ┌──────┐  ┌─────┐ │
       │  │SCORE │  │  ════════ TIME ═══     │  │LEVEL │  │ ⏸  │ │
       │  │ 4280 │  │  (shrinks left→right)  │  │ 3/10 │  │ btn │ │
       │  └──────┘  └────────────────────────┘  └──────┘  └─────┘ │
       │                                                          │
       │  BOTTOM ROW  (≈ 400 units tall)                          │
       │  ┌──────────────┐    ┌───┐     ┌──────────────┐          │
       │  │              │    │ J │     │              │          │
       │  │              │    ├───┤     │              │          │
       │  │  PORTRAIT 1  │    │ J │     │  PORTRAIT 2  │          │
       │  │              │    ├───┤     │              │          │
       │  │              │    │ J │     │              │          │
       │  └──────────────┘    ├───┤     └──────────────┘          │
       │                      │ J │                               │
       │                      ├───┤                               │
       │                      │ J │                               │
       │                      └───┘                               │
       └──────────────────────────────────────────────────────────┘
  (-320, 240)                                                   (320, 240)
```

**Rough coordinate budget** (top-left anchored, virtual units):

| Element       | x range        | y range        | Notes                                  |
|---------------|----------------|----------------|----------------------------------------|
| Score label   | -300 .. -240   | -230 .. -200   | text, right-padded numeric             |
| Time bar      | -180 .. +180   | -225 .. -205   | uses `fill_x` to shrink                |
| Level label   | +200 .. +260   | -230 .. -200   | "3/10" style                           |
| Pause button  | +280 .. +310   | -230 .. -200   | 30×30 icon                             |
| Portrait 1    | -310 .. -90    | -170 .. +220   | 220×390 (or whatever your art is)      |
| Joker column  | -80 .. +80     | -170 .. +220   | 5 buttons stacked vertically           |
| Portrait 2    | +90 .. +310    | -170 .. +220   | mirror of portrait 1                   |

Exact numbers can shift once the art is in; this is just the spatial intent.

## Levels

Defined in `scripts/levels.lua` and loaded from `main.lua` at startup. Conceptually:

```lua
return {
    count       = 10,    -- total levels
    time_start  = 60.0,  -- seconds at level 1
    time_end    = 25.0,  -- seconds at the last level (linear lerp between)

    -- Per-level data: image pair + difference positions on portrait 1
    -- (positions are virtual-canvas coords inside portrait 1's rect).
    levels = {
        { pair = "1", diffs = { {x=-220, y=-100}, {x=-180, y= -20}, ... } },
        { pair = "2", diffs = { ... } },
        -- ...
    },
}
```

- Image pair `"1"` resolves to texture regions `image_1a` (left portrait) + `image_1b` (right portrait) declared in `assets.lua`. Position-by-name, like the rest of the asset system.
- Time per level: `lerp(time_start, time_end, idx / (count - 1))` — linear, simple to read in the data.
- "5 differences" is a constant for now (the name says so). If you ever want variable, store the count per level too.

## State machine

```
   ┌────────┐
   │  INIT  │  (main.lua loads levels.lua, music_play("title"), boot to first level)
   └───┬────┘
       ▼
   ┌────────────┐   level done   ┌────────────────────┐  continue   ┌────────┐
   │  PLAYING   │ ─────────────▶ │  LEVEL_COMPLETE    │ ──────────▶ │  NEXT  │
   │  (timer    │                │  (dialog scales/   │             └───┬────┘
   │   running) │                │   fades in, score  │                 │
   └─┬─────┬────┘                │   counts up)       │                 │
     │     │ time = 0            └────────────────────┘                 │ (back to PLAYING
     │     ▼                                                            │  with next level)
     │ ┌────────────┐                                                   │
     │ │ GAME_OVER  │   restart                                         │
     │ │  (dialog)  │ ─────────────────────────────────────────────────▶│
     │ └────────────┘                                                   │
     │                                                                  │
     │ pause btn                                                        │
     ▼                                                                  │
   ┌────────────┐   resume                                              │
   │  PAUSED    │ ─────────────────────────────────────────────────────▶│
   │  (dialog)  │   restart    ─▶ restart current level                 │
   │            │   highscore  ─▶ open highscore screen                 │
   │            │   exit       ─▶ quit application                      │
   └────────────┘                                                       │
                                                                        │
   ┌────────────┐  (after last level cleared)                           │
   │  ALL_DONE  │ ◀─────────────────────────────────────────────────────┘
   │  (game     │
   │   over     │   restart    ─▶ INIT
   │   won)     │   highscore  ─▶ open highscore screen
   └────────────┘
```

Held as a single `state` variable in `main.lua`. `on_update` dispatches by state; `on_render` draws the active layer(s) (e.g. PAUSED draws PLAYING dimmed underneath + the dialog on top).

## Animations

All tweens live Lua-side. Drop in a small tween library via `require "tween"` (the sandbox already permits this — see `scripts/?.lua` lookup path).

| Trigger                         | Animation                                                  | Duration |
|---------------------------------|------------------------------------------------------------|----------|
| Difference found                | `draw_ellipse` with `finish` tween 0 → 1 (the "drawing")   | 0.4s     |
| Difference found                | Optional fade-up score popup at the click point            | 0.6s     |
| Joker button pressed            | Button: scale 1 → 1.3, alpha 1 → 0                         | 0.25s    |
| Joker button pressed            | Empty-slot region underneath: alpha 0 → 1                  | 0.25s    |
| Wrong click                     | Brief red flash on portrait (uiQuad with tweened alpha)    | 0.2s     |
| Time low (last 5s)              | Time bar tint pulses to red                                | 0.5s loop |
| Level complete                  | Dialog: scale 0.6 → 1.0, alpha 0 → 1                       | 0.3s     |
| Level complete                  | Score count-up: from current to (current + bonus)          | 1.5s     |
| Pause dialog open               | Background dim (alpha 0 → 0.5 black quad)                  | 0.15s    |
| Pause dialog open               | Dialog: scale 0.8 → 1.0, alpha 0 → 1                       | 0.2s     |
| Pause dialog close              | reverse                                                    | 0.15s    |
| Game over dialog                | same as pause dialog, plus the dim                         | 0.2s     |

Score bonus formula (suggestion): `bonus = floor(time_left * 10) + jokers_left * 50`. Adjust to feel right once the loop is playable.

## Input

The engine routes SDL events to Lua hooks; the game uses:

- `on_mousedown(x, y, button)` — hit-test against:
  - Pause button rect (top-right)
  - Joker buttons (5 stacked rects)
  - Portrait 1 rect (find-the-difference click)
  - Portrait 2 rect — wrong side, but valid click; treat as wrong-click
  - Dialog buttons when a dialog is up
- `on_update(dt)` — tick the timer, advance active tweens, check for time-out and level-complete.
- `on_keydown("escape")` — pause / unpause.

Difference hit-test on portrait 1: the click is in canvas coords; subtract the portrait's origin to get a local position, then check against each difference's `{x, y}` (with a per-difference radius — call it 25 units). Mark found, kick off the ellipse animation, decrement remaining count.

## Dialogs

### Pause dialog
Centered rect (background = a `dialog_bg` region tiled or stretched). Contains:
- Title "PAUSED"
- Three buttons stacked: RESTART / HIGHSCORE / EXIT
- Click outside dialog or press Esc to resume

### Game over dialog
Title "GAME OVER" (or "TIME UP"). Two buttons: RESTART / HIGHSCORE. No resume — the run is over.

### Level complete dialog
Title "LEVEL N COMPLETE". Lines for "Time bonus: +XXX", "Joker bonus: +XXX", "Total score: XXXX" (animated count-up). One button: CONTINUE.

Dialogs are drawn after the playing-state render with a 50% black dim quad behind them, mirroring how SDLFun's menu.h handled overlay screens.

## Data model

```
assets.lua
    textures:
        background       = "assets/textures/bg.png"           -- the 640×480 base
        sprites          = "assets/textures/sprites.png"      -- one atlas for UI widgets
        image_1a         = "assets/textures/image_1a.png"     -- portraits per level
        image_1b         = "assets/textures/image_1b.png"
        image_2a         = ...
        ...

    regions:
        bg               = { tex = "background", x=0,  y=0,   w=640, h=480 }
        time_bar_fill    = { tex = "sprites",    x=0,  y=0,   w=320, h=20  }
        time_bar_bg      = { tex = "sprites",    x=0,  y=20,  w=320, h=20  }
        joker_full       = { tex = "sprites",    x=0,  y=40,  w=80,  h=70  }
        joker_empty      = { tex = "sprites",    x=80, y=40,  w=80,  h=70  }
        pause_btn        = { tex = "sprites",    x=160,y=40,  w=30,  h=30  }
        dialog_bg        = { tex = "sprites",    x=0,  y=120, w=320, h=240 }
        button_normal    = { tex = "sprites",    x=0,  y=360, w=200, h=60  }
        button_hover     = { tex = "sprites",    x=0,  y=420, w=200, h=60  }
        image_1a         = { tex = "image_1a",   x=0,  y=0,   w=220, h=390 }
        image_1b         = { tex = "image_1b",   x=0,  y=0,   w=220, h=390 }
        ...

    fonts: (already in place — orbitron / orbitron_small / default)

scripts/levels.lua
    See "Levels" section above.

scripts/main.lua
    State machine + dispatch.

scripts/state/*.lua  (optional, if main.lua gets unwieldy)
    state_playing.lua, state_paused.lua, state_dialog.lua
```

## Engine bindings used

What we already have and what's landing alongside this plan:

| Binding | Status | Used for |
|---|---|---|
| `draw_region(name, x, y, opts)` | Has + extending | All sprite drawing — portraits, time bar (`fill_x`), joker buttons, dialog background, buttons |
| `draw_text(text, x, y, opts)` | Adding | Score label, level label, dialog titles, button captions, score count-up |
| `draw_ellipse(cx, cy, rx, ry, opts)` | Adding | "Drawing" animation around a found difference (`finish` tweened 0 → 1) |
| `key_down / mouse_pos / mouse_down` | Has | Polling (continuous state) |
| `on_keydown / on_mousedown / on_update / on_render` | Has | Event dispatch + per-frame logic |
| `snd_play("found")` etc. | Has | Sound effects on found / wrong / joker / level-complete |
| `music_play("title" / "ingame")` | Has | Music switching |
| `ui_show_message` | Has (optional) | Minor on-screen messages — could be replaced by `draw_text` |
| `require "tween"` | Has | Tweening library for all animations |

Notably **not yet** in the engine and worth keeping in mind for later:

- **Save / load** (high-score persistence). Right now `io` is sandboxed. Add a small `save("key", value)` / `load("key")` binding that writes to a single JSON-ish file next to the exe. Simplest path: one Lua-table-as-string per slot.
- **Rotation** on `draw_region`. Not needed for the spec above. Add when you want angled sprites.
- **Particles** / batched effects. Not needed.

## Implementation roadmap

Roughly in build order — each step is testable before moving to the next.

1. **Engine adds (this PR)**: scale + alpha + options-table on `draw_region`; `draw_text`; `draw_ellipse`. UI canvas to 480.
2. **Background + portraits visible**: draw `bg` full-canvas, draw `image_1a` and `image_1b` at portrait positions. Static. No input.
3. **Time bar + score/level labels**: `draw_region` with `fill_x` for the time bar; `draw_text` for the labels. Hardcoded values first.
4. **Difference hit-test**: click on portrait 1 → if within 25 units of any unfound difference, mark it found and trigger ellipse animation. Use `draw_ellipse` with `finish` tweened.
5. **Joker buttons**: 5 buttons stacked. Click reveals one unfound difference (same ellipse animation as a normal find). On click: button scale-up + fade-out, empty slot fades in.
6. **Level complete**: when remaining == 0 → LEVEL_COMPLETE state. Dialog scales/fades in. Score count-up animation.
7. **Continue → next level**: load next level's data, reset timer, back to PLAYING.
8. **Pause dialog**: Esc or pause button → PAUSED. Dim + dialog. Restart / Highscore (stub) / Exit.
9. **Game over** (time-up): show dialog, Restart / Highscore.
10. **Level config from data**: replace hardcoded numbers with `scripts/levels.lua`.
11. **Sound polish**: found / wrong / joker / tick / win.
12. **High scores**: add save/load binding, build the highscore screen.
13. **Title screen** (optional): a screen before INIT, with PLAY / HIGHSCORE / EXIT.

Each step is a couple of evenings of work. Suggest committing in order so you always have a runnable build.
