# Find5 — Game Plan

A spot-the-difference puzzle game built on the Find5 engine. Player has to find 5 differences between two portrait images before a timer runs out. 5 single-use "joker" hints can reveal one difference each. Score is added at level-end based on unused time and unused jokers; harder levels (less time) reward more.

Images come from **categories** (e.g. Portraits, Landscapes). The player picks a category before each run from a title screen. Each category has its own image pool; within a run, images are drawn randomly from that pool without repeats. Once the pool is exhausted across runs, the "used" set resets and images can come up again.

## Title screen

The first thing the player sees after boot. Picks the category, toggles sound/music, opens a per-category highscore list, or starts the run.

```
       ┌──────────────────────────────────────────────┐
       │                  ╔══════════╗                │
       │                  ║   LOGO   ║                │
       │                  ╚══════════╝                │
       │                                              │
       │           ┌────────────────────────┐         │
       │      ◀    │                        │    ▶    │
       │           │   CATEGORY PREVIEW     │         │
       │           │   (image + title)      │         │
       │           │                        │         │
       │           └────────────────────────┘         │
       │                   "Portraits"                │
       │                                              │
       │  [🔊] [♪]              [ START ]  [ 🏆 ]     │
       └──────────────────────────────────────────────┘
```

Elements:

| Element            | Purpose                                                       |
|--------------------|---------------------------------------------------------------|
| Logo               | Top-center, decorative                                        |
| Category preview   | Region named `category_<id>` (image + title together, or two regions per category) |
| `<` `>` arrows     | Cycle previous / next category (wraps around)                 |
| Speaker icon       | Toggle sound effects on/off (persisted)                       |
| Note icon          | Toggle music on/off (persisted)                               |
| START button       | Begin run with the selected category                          |
| Highscore (trophy) | Open the highscore list for the **selected** category         |

Sound/music toggles are pure on/off — implementation: when sound is off, `snd_play` is gated in Lua (or volume set to 0); when music is off, `music_volume(0)` is called and remembered. State is read from the persisted settings file at boot.

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

## Levels & categories

Defined in `scripts/levels.lua` and loaded from `main.lua` at startup. Categories hold the image pools; level count and time curve are global (same across all categories — only the image pool varies).

```lua
return {
    level_count = 10,    -- levels played per run; same for every category
    time_start  = 60.0,  -- seconds on level 1
    time_end    = 25.0,  -- seconds on the last level (linear lerp between)

    categories = {
        {
            id    = "portraits",        -- stable string ID; used as the key in
                                        -- saved highscores and used-image state
            title = "Portraits",
            icon  = "category_1",       -- region drawn on the title-screen preview

            -- Image pool — the player draws levels randomly from here. Each
            -- entry's `pair` resolves to texture regions `image_<pair>_a` and
            -- `image_<pair>_b` (left & right portraits).
            images = {
                { pair = "p1", diffs = { {x=-200, y=-100}, {x=-120, y= 20}, {x=-40, y=100}, {x=100, y=-50}, {x=180, y=150} } },
                { pair = "p2", diffs = { ... } },
                -- ... however many images you put in the pool. The pool can be
                -- larger or smaller than level_count; if smaller, the used set
                -- resets mid-run.
            },
        },
        {
            id    = "landscapes",
            title = "Landscapes",
            icon  = "category_2",
            images = { ... },
        },
        -- ...
    },
}
```

- Time per level: `lerp(time_start, time_end, level_idx / (level_count - 1))` — linear.
- "5 differences" is a constant; diff count per image should be exactly 5 (or the game will silently consider the level complete after 5 finds regardless of how many were defined).
- `level_count` is the same across categories, so leaderboards are comparable.

**Image selection per level**: drawn randomly from the category's pool, skipping any pair listed in the persisted `used_images[category_id]` set (see "Persistence" below). If the unused subset is empty, clear the set and start over. Mark the chosen pair used immediately on selection (so quitting mid-level doesn't make the same image come back).

Use `math.random(1, #unused)` for picks — `math.random` is already seeded at boot from `srand(time(NULL))` in `main.cpp`, so no extra binding is needed.

## State machine

```
   ┌────────┐
   │  INIT  │  (load levels.lua, load saved settings, music_play("title"))
   └───┬────┘
       ▼
   ┌──────────────┐  start    ┌────────────┐  level done    ┌─────────────────┐
   │   TITLE      │ ────────▶ │  PLAYING   │ ─────────────▶ │ LEVEL_COMPLETE  │
   │ (category    │           │  (timer    │                │ (dialog scales, │
   │  selector,   │ ◀────┐    │   running) │                │  score counts)  │
   │  toggles)    │      │    └──┬────┬────┘                └──────┬──────────┘
   │   ↑          │      │       │    │                            │ continue
   │  HIGHSCORE   │      │       │    │ time = 0                   ▼
   └──────────────┘      │       │    ▼                       ┌─────────┐
                         │       │  ┌────────────┐  restart   │  NEXT   │
                         │       │  │ GAME_OVER  │ ──────────▶│ (load   │
                         │       │  │  (dialog)  │            │  next   │
                         │       │  └─────┬──────┘            │  level) │
                         │ exit  │        │ highscore         └────┬────┘
                         │       │        ▼                        │
                         │       │     TITLE                       │
                         │       │                                 │
                         │       │ pause btn                       │
                         │       ▼                                 │
                         │   ┌────────────┐  resume                │
                         │   │  PAUSED    │ ───────────────────────┤
                         │   │  (dialog)  │  restart  → PLAYING    │
                         │   │            │  highscore → TITLE     │
                         │   │            │  exit     → quit app   │
                         │   └────────────┘                        │
                         │                                         │
                         │  ┌────────────┐  (after final level     │
                         │  │  ALL_DONE  │   cleared)              │
                         │  │  (final    │ ◀───────────────────────┘
                         └──┤  score +   │
                            │  dialog)   │  restart   → TITLE
                            └────────────┘  highscore → TITLE
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

### Highscore screen

Reached from the title screen's trophy button (showing the **selected** category's scores) and from the post-game dialogs (showing the category just played). Shows top N (suggest 10) entries as `RANK. SCORE` rows; a BACK button returns to wherever you came from. Saving a new score happens automatically when GAME_OVER or ALL_DONE fires — no name entry yet (keep it simple; add initials later if you want).

## Persistence

One save file `find5.dat` next to the exe. Holds a single Lua table:

```lua
{
    settings = {
        sound_on      = true,
        music_on      = true,
        last_category = "portraits",   -- restored as the title screen's default
    },
    highscores = {
        portraits  = { 5200, 4100, 3800, 2700, 1500 },   -- sorted descending, capped
        landscapes = { 4800, 3600, 2200 },
    },
    used_images = {                                      -- which images consumed per category
        portraits  = { p1 = true, p3 = true, p7 = true },
        landscapes = { l2 = true },
    },
}
```

Loaded on boot, written after any state change that matters (toggle sound, finish a run, change category). One save = one whole-table rewrite — atomic enough for this scale (small file, infrequent writes), no need for journaling or partial updates.

**This requires a new engine binding** — `io` is sandboxed for safety, so Lua can't write files directly. See "File operations" at the bottom of this doc.

## Data model

```
assets.lua
    textures:
        background       = "assets/textures/bg.png"           -- the 640×480 base
        sprites          = "assets/textures/sprites.png"      -- one atlas for UI widgets
        category_1       = "assets/textures/category_1.png"   -- title-screen preview per cat
        category_2       = "assets/textures/category_2.png"
        ...
        image_p1_a       = "assets/textures/image_p1_a.png"   -- portrait pairs per pool entry
        image_p1_b       = "assets/textures/image_p1_b.png"
        ...

    regions:
        bg               = { tex = "background", x=0,  y=0,   w=640, h=480 }
        logo_small       = { tex = "sprites",    x=0,  y=0,   w=240, h=80  }
        time_bar_fill    = { tex = "sprites",    x=0,  y=80,  w=320, h=20  }
        time_bar_bg      = { tex = "sprites",    x=0,  y=100, w=320, h=20  }
        joker_full       = { tex = "sprites",    x=0,  y=120, w=80,  h=70  }
        joker_empty      = { tex = "sprites",    x=80, y=120, w=80,  h=70  }
        pause_btn        = { tex = "sprites",    x=160,y=120, w=30,  h=30  }
        arrow_left       = { tex = "sprites",    x=0,  y=190, w=40,  h=60  }   -- title screen
        arrow_right      = { tex = "sprites",    x=40, y=190, w=40,  h=60  }   -- title screen
        icon_sound_on    = { tex = "sprites",    x=80, y=190, w=32,  h=32  }
        icon_sound_off   = { tex = "sprites",    x=112,y=190, w=32,  h=32  }
        icon_music_on    = { tex = "sprites",    x=144,y=190, w=32,  h=32  }
        icon_music_off   = { tex = "sprites",    x=176,y=190, w=32,  h=32  }
        icon_trophy      = { tex = "sprites",    x=208,y=190, w=32,  h=32  }
        dialog_bg        = { tex = "sprites",    x=0,  y=250, w=320, h=240 }
        button_normal    = { tex = "sprites",    x=0,  y=490, w=200, h=60  }
        button_hover     = { tex = "sprites",    x=0,  y=550, w=200, h=60  }
        category_1       = { tex = "category_1", x=0,  y=0,   w=320, h=300 }
        category_2       = { tex = "category_2", x=0,  y=0,   w=320, h=300 }
        image_p1_a       = { tex = "image_p1_a", x=0,  y=0,   w=220, h=390 }
        image_p1_b       = { tex = "image_p1_b", x=0,  y=0,   w=220, h=390 }
        ...

    fonts: (already in place — orbitron / orbitron_small / default)

scripts/levels.lua
    See "Levels & categories" section above.

scripts/main.lua
    Top-level state machine + dispatch (TITLE / PLAYING / PAUSED / ...).

scripts/state/*.lua  (optional, if main.lua gets unwieldy)
    state_title.lua, state_playing.lua, state_paused.lua, state_highscore.lua

find5.dat  (next to the exe; gitignored)
    The single persistence file. Shape documented in "Persistence" above.
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
| `math.random` | Has (seeded) | Pick an image from the unused subset of a category's pool |
| `save_state / load_state` | **Adding next** | Persist settings, highscores, used-image set |

Notably **not yet** in the engine and worth keeping in mind:

- **Save / load** — needed for settings, highscores, used-images state (see "File operations" below). One pair of bindings, no path arg.
- **Rotation** on `draw_region`. Not needed for the spec above. Add when you want angled sprites.
- **Particles** / batched effects. Not needed.

## File operations

`io` and `os` are nilled by the engine's sandbox (so a buggy script can't `os.execute("rm -rf")` or open arbitrary paths). For Find5 we need exactly two operations: load the persistence table at boot, save the persistence table after state-changing actions. Recommended API — minimal, no path argument exposed:

```lua
save_state(t)         -- serialize Lua table t to "find5.dat" next to the exe
local t = load_state()  -- returns the table, or an empty table if file missing
```

**Implementation sketch** (~50 lines of C in `script.h`):
- `save_state`: walk the table recursively, write a `return { ... }` text file via `fopen`/`fprintf` on the C side (which is *not* sandboxed). Supports nested tables, strings, numbers, booleans. Skips functions and userdata (they're not persistable anyway).
- `load_state`: `luaL_loadfile("find5.dat")` + `lua_pcall` on the C side, bypassing the user-side `dofile`/`loadfile` ban. Returns the resulting table on the Lua stack.

No JSON parser needed — leaning on Lua's own evaluator is the smallest path.

**Safety notes**: 
- The path is hardcoded (`find5.dat`), so scripts can't escape the working directory.
- `load_state` runs the file as Lua code, but only the engine ever writes that file, so this is effectively trusted code. Still — a corrupted save file could crash the loader; wrap the pcall and fall back to empty table on error.
- Single file, whole-table rewrite. Tiny (a few KB at most). No need for incremental updates or backup files.

**Random number generation** — already works. `math.random` in Lua 5.1 uses the C `rand()` under the hood, and `main.cpp` already calls `srand(time(NULL))` at boot. So image picking and any other RNG works without new bindings.

## Implementation roadmap

Roughly in build order — each step is testable before moving to the next.

1. **Engine adds (shipped)**: scale + alpha + options-table on `draw_region`; `draw_text`; `draw_ellipse`; UI canvas to 480.
2. **`save_state` / `load_state` engine binding**: ~50 lines in `script.h`, see "File operations". Lands once because everything downstream needs it.
3. **Background + portraits visible**: draw `bg` full-canvas, draw one hardcoded image pair at portrait positions. Static. No input.
4. **Time bar + score/level labels**: `draw_region` with `fill_x` for the time bar; `draw_text` for the labels.
5. **Difference hit-test**: click on portrait 1 → if within 25 units of any unfound difference, mark it found and trigger the ellipse animation.
6. **Joker buttons**: 5 buttons stacked. Click reveals one unfound difference. On click: button scale-up + fade-out, empty slot fades in.
7. **Level complete**: when remaining == 0 → LEVEL_COMPLETE state. Dialog scales/fades in. Score count-up animation.
8. **Continue → next level** within a run (still one category, still one image pool).
9. **Pause dialog**: Esc or pause button → PAUSED. Dim + dialog. Restart / Highscore / Exit.
10. **Game over** (time-up): show dialog, Restart / Highscore.
11. **Level config from data**: replace hardcoded numbers with `scripts/levels.lua` (single category for now).
12. **Multi-category**: add the rest of the categories to `levels.lua`. Pick category programmatically at boot.
13. **Title screen**: logo + category preview + arrows + sound/music toggles + START + highscore button. State machine entry point. Persists `last_category` via `save_state`.
14. **Random image picking + used-images set**: pick from category's pool excluding `used_images[cat_id]`; reset when empty. Persist on each pick.
15. **Highscore screen**: per-category top-N list, reachable from title and from post-game dialogs. Saving new scores triggered automatically on GAME_OVER / ALL_DONE.
16. **Sound polish**: found / wrong / joker / tick / win SFX. Honor `settings.sound_on` / `settings.music_on` toggles.

Each step is a couple of evenings of work. Suggest committing in order so you always have a runnable build.
