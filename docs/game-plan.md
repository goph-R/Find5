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
       │ TOP ROW  (≈ 50 units tall)                               │
       │ ┌─────┐  ┌─────┐                ┌─────┐         ┌─────┐  │
       │ │LEVEL│  │FOUND│   ═══ TIME ══  │SCORE│         │ ⏸  │  │
       │ │ 3/10│  │ 2/5 │  (shrinks L→R) │12345│         │ btn │  │
       │ └─────┘  └─────┘                └─────┘         └─────┘  │
       │                                                          │
       │ BOTTOM AREA  (≈ 400 units tall)                          │
       │ ┌──────────────┐     ┌─┐     ┌──────────────┐            │
       │ │              │     │★│     │              │            │
       │ │              │     ├─┤     │              │            │
       │ │  PORTRAIT 1  │     │★│     │  PORTRAIT 2  │            │
       │ │              │     ├─┤     │              │            │
       │ │              │     │☆│     │              │            │
       │ │              │     ├─┤     │              │            │
       │ │              │     │☆│     │              │            │
       │ │              │     ├─┤     │              │            │
       │ │              │     │☆│     │              │            │
       │ └──────────────┘     └─┘     └──────────────┘            │
       │                    ┌─────┐                               │
       │                    │JOKER│   single button + remaining   │
       │                    │  3  │   counter; click reveals one  │
       │                    └─────┘   unfound diff (yellow)       │
       └──────────────────────────────────────────────────────────┘
  (-320, 240)                                                   (320, 240)
```

Stars (`★` filled = `star`; `☆` outlined = `star_empty`) are a **progress indicator**, not buttons — one fills each time a difference is found, in order top-to-bottom. They sit dead-center between the two portraits.

The single **JOKER button** lives below the star column, with the remaining-joker count beneath/inside it. Clicking it reveals one still-unfound difference with a yellow ellipse (vs. the green ellipse a player-click produces) and decrements the counter.

**Rough coordinate budget** (top-left anchored, virtual units):

| Element       | x range        | y range        | Notes                                  |
|---------------|----------------|----------------|----------------------------------------|
| Level label   | -300 .. -260   | -236 .. -200   | "3/10", current white / total muted    |
| Found label   | -210 .. -170   | -236 .. -200   | "2/5" — differences found this level   |
| Time bar      | -133 .. +133   | -224 .. -200   | uses `fill_x` to shrink (anchored L)   |
| Score label   |  +180 .. +240  | -236 .. -200   | yellow numeric, large                  |
| Pause button  |  +272 .. +314  | -232 .. -190   | 42×42 region                           |
| Portrait 1    | -314 .. -29    | -183 .. +232   | 285×415 + 1px image_bg frame           |
| Star column   |  -20 .. +20    | -183 .. +233   | 5 × 40px stacked + 8px gaps            |
| Joker button  |  -21 .. +21    | +192 .. +234   | 42×42, beneath the stars               |
| Portrait 2    |  +27 .. +312   | -183 .. +232   | mirror of portrait 1                   |

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
            -- `image_<pair>_b` (left & right portraits). Each diff is a
            -- rect in portrait-local coords: (x, y) top-left, (w, h) size.
            -- Both hit-testing and the find ellipse derive from these rects
            -- (ellipse cx, cy = x + w/2, y + h/2; rx, ry = w/2, h/2).
            images = {
                { pair = "1", diffs = {
                    { x =  60, y = 120, w = 120, h = 40 },
                    { x =  40, y =  30, w =  40, h = 60 },
                    -- ... 5 entries per image
                } },
                { pair = "2", diffs = { ... } },
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

**Per-run state** (lives in `main.lua`, not persisted):

```lua
state.found = {
    { x = 60, y = 120, w = 120, h = 40, joker = false },  -- player click
    { x = 40, y =  30, w =  40, h = 60, joker = true  },  -- joker reveal
    -- appended in order; #state.found drives the star column (filled
    -- slots = #found; the rest stay star_empty). joker = true makes
    -- on_render draw a yellow ellipse instead of green for that entry.
}
state.jokers = 3    -- remaining; decremented on each successful joker press
```

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

**Game-over reveal**: when time hits 0 the state goes `PLAYING → GAME_OVER_REVEAL → GAME_OVER`. In `GAME_OVER_REVEAL` the timer is frozen, input is ignored, and every still-unfound difference is drawn one after another with a **red** `draw_ellipse` (~0.25s stagger between starts, 0.4s draw each). After the last ellipse finishes plus ~0.8s of dwell, the GAME_OVER dialog scales/fades in as usual. This gives the player a chance to see what they missed before the dialog covers the portraits.

## Animations

All tweens live Lua-side. Drop in a small tween library via `require "tween"` (the sandbox already permits this — see `scripts/?.lua` lookup path).

Found / joker / game-over reveal all reuse the same `draw_ellipse` "drawing" animation (`finish` tweened 0 → 1) — only the color changes, so the player learns the visual language quickly. Once drawn, the find marker **stays on screen** for the rest of the level — green if it was a player click, yellow if a joker revealed it. The per-find `joker` flag (boolean stored alongside `x, y, w, h` in `state.found`) decides which color to draw on every subsequent frame.

| Trigger                         | Animation                                                  | Duration |
|---------------------------------|------------------------------------------------------------|----------|
| Difference found (player click) | **Green** ellipse, `finish` 0 → 1; stays drawn after       | 0.4s draw |
| Difference found                | Star at the next free slot in the column fills: `star_empty` → `star` (scale pop 1 → 1.3 → 1.0) | 0.25s |
| Difference found                | Found counter bumps (e.g. 1/5 → 2/5), brief scale pop      | 0.2s     |
| Difference found                | Optional fade-up score popup at the click point            | 0.6s     |
| Joker button pressed            | Button: `joker_button_up` → `joker_button_down` for 0.1s, then back; counter ticks down | 0.1s |
| Joker reveals next unfound diff | **Yellow** ellipse, `finish` 0 → 1; stays drawn after; star fills too (same pop) | 0.4s draw |
| Wrong click                     | Brief red flash on portrait (uiQuad with tweened alpha)    | 0.2s     |
| Time low (last 10s) — audio     | `snd_play("tick")` once per second (tick / tock / tick…)   | each 1.0s |
| Time low (last 10s) — visual    | Time bar fades out → in fast, **5 cycles over 10s** (one cycle every 2s; alpha 1 → 0.2 → 1, eased) | 2.0s × 5 |
| Game over reveal (time up)      | **Red** ellipses on every unfound difference, drawn one after another (~0.25s stagger) | 0.4s each + dwell |
| Game over reveal → dialog       | After last red ellipse finishes + ~0.8s dwell, dialog appears | 0.8s wait |
| Level complete                  | Dialog: scale 0.6 → 1.0, alpha 0 → 1                       | 0.3s     |
| Level complete                  | Score count-up: from current to (current + bonus)          | 1.5s     |
| Pause dialog open               | Background dim (alpha 0 → 0.5 black quad)                  | 0.15s    |
| Pause dialog open               | Dialog: scale 0.8 → 1.0, alpha 0 → 1                       | 0.2s     |
| Pause dialog close              | reverse                                                    | 0.15s    |
| Game over dialog                | same as pause dialog, plus the dim                         | 0.2s     |

Suggested ellipse colors (premultiplied / straight RGBA, pick what matches the art):

| Source      | Color (RGB)          | Meaning                                   |
|-------------|----------------------|-------------------------------------------|
| Player find | `{ 0.3, 1.0, 0.4 }`  | green — "you got it"                      |
| Joker       | `{ 1.0, 0.9, 0.3 }`  | yellow — "the game gave you this one"     |
| Game over   | `{ 1.0, 0.3, 0.3 }`  | red — "here's what you missed"            |

Score bonus formula (suggestion): `bonus = floor(time_left * 10) + jokers_left * 50`. Adjust to feel right once the loop is playable.

## Input

The engine routes SDL events to Lua hooks; the game uses:

- `on_mousedown(x, y, button)` — hit-test against:
  - Pause button rect (top-right)
  - Joker button rect (single button below the star column)
  - Portrait 1 rect (find-the-difference click)
  - Portrait 2 rect — wrong side, but valid click; treat as wrong-click
  - Dialog buttons when a dialog is up
- `on_update(dt)` — tick the timer, advance active tweens, check for time-out and level-complete.
- `on_keydown("escape")` — pause / unpause.

Difference hit-test on portrait 1: the click is in canvas coords; subtract the portrait's origin to get a local position, then check whether it falls inside any unfound difference's `{x, y, w, h}` rect. On hit: append `{ x, y, w, h, joker = false }` to `state.found`, kick off the green ellipse animation, fill the next progress star.

Joker press: pick the first **unfound** difference (e.g. first in `state.diffs` that isn't already in `state.found`), append `{ x, y, w, h, joker = true }` to `state.found`, kick off the yellow ellipse animation, fill the next star, decrement `state.jokers`. No-op (or short blip) if `state.jokers == 0`.

## Dialogs

### Pause dialog
Centered rect (background = a `dialog_bg` region tiled or stretched). Contains:
- Title "PAUSED"
- Three buttons stacked: RESTART / HIGHSCORE / EXIT
- Click outside dialog or press Esc to resume

### Game over dialog
Title "GAME OVER" (or "TIME UP"). Two buttons: RESTART / HIGHSCORE. No resume — the run is over. Shown **after** the GAME_OVER_REVEAL phase has drawn red ellipses on every unfound difference and waited a beat (see state machine notes).

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

Loaded on boot (auto, by the engine), written after any state change that matters (toggle sound, finish a run, change category) via `opt_save()`. One save = one whole-table rewrite, atomic via write-to-tmp + rename — fine for this scale (small file, infrequent writes).

The engine exposes a small **key-value options API** for this. Each `opt_get` carries its own default, so adding/removing/renaming options across versions never breaks an existing save file (orphan keys are ignored, new keys fall back to defaults). See "File operations" below.

## Data model

```
assets.lua
    textures:
        background       = "assets/textures/bg.png"           -- the 640×480 base
        sprites          = "assets/textures/sprites.png"      -- one atlas for UI widgets
        category_1       = "assets/textures/category_1.png"   -- title-screen preview per cat
        category_2       = "assets/textures/category_2.png"
        ...
        game_ui          = "assets/textures/game_ui.png"      -- HUD atlas (stars, buttons, bars, frame)
        image_1a         = "assets/textures/image_1a.png"     -- portrait pairs per pool entry
        image_1b         = "assets/textures/image_1b.png"     -- (PNG is POT-padded to 512×512, image is 285×415 top-left)
        ...

    regions:
        bg                = { tex = "background", x=0,  y=0,   w=640, h=480 }
        logo_small        = { tex = "sprites",    x=0,  y=0,   w=240, h=80  }
        -- HUD (currently in game_ui.png; final atlas may merge into sprites)
        star              = { tex = "game_ui",    x=1,   y=1,   w=40,  h=40  }  -- filled, progress
        star_empty        = { tex = "game_ui",    x=42,  y=1,   w=40,  h=40  }  -- outline, not-yet
        pause_button_up   = { tex = "game_ui",    x=83,  y=1,   w=42,  h=42  }
        pause_button_down = { tex = "game_ui",    x=126, y=1,   w=42,  h=42  }
        joker_button_up   = { tex = "game_ui",    x=169, y=1,   w=42,  h=42  }
        joker_button_down = { tex = "game_ui",    x=212, y=1,   w=42,  h=42  }
        timebar           = { tex = "game_ui",    x=1,   y=44,  w=264, h=22  }  -- shrinks via fill_x
        timebar_bg        = { tex = "game_ui",    x=1,   y=67,  w=266, h=24  }  -- 2px frame around timebar
        image_bg          = { tex = "game_ui",    x=1,   y=92,  w=287, h=417 }  -- 2px frame around portrait
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
        image_1a          = { tex = "image_1a", x=0, y=0, w=285, h=415 }
        image_1b          = { tex = "image_1b", x=0, y=0, w=285, h=415 }
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
| `opt_set / opt_get / opt_save / opt_load` | Has | Persist settings, highscores, used-image set |

Notably **not yet** in the engine:

- **Rotation** on `draw_region`. Not needed for the spec above. Add when you want angled sprites.
- **Particles** / batched effects. Not needed.

## File operations

`io` and `os` are nilled by the engine's sandbox (so a buggy script can't `os.execute("rm -rf")` or open arbitrary paths). Find5 needs persistence for settings, highscores, and the used-images set per category — exposed as a small key-value options API:

```lua
opt_set(name, value)       -- value: string | number | boolean | table
                           -- pass nil to delete the option
opt_get(name)              -- returns value, or nil
opt_get(name, default)     -- returns default if unset (the forward-compat hook)
opt_save()                 -- write all options to find5.dat (atomic via .tmp + rename)
opt_load()                 -- re-read find5.dat into memory (auto-called at boot)
```

`opt_save` is **explicit** — call it after changes you want persisted. Batches naturally: set five things in a row, save once. `opt_load` is auto-called by the engine before `scripts/main.lua` runs, so options are ready by the time your `on_start` fires; you only need to call it manually to revert to last-saved state.

**Example usage** (suggests how Find5's game state maps onto it):

```lua
-- Settings
opt_set("sound_on",     true)
opt_set("music_on",     true)
opt_set("last_category", "portraits")

-- Per-category highscores
opt_set("hs_portraits",  { 5200, 4100, 3800 })
opt_set("hs_landscapes", { 4800, 3600 })

-- Per-category used-images set
opt_set("used_portraits",  { p1 = true, p3 = true })

opt_save()                                  -- commit to disk

-- Reading with defaults — robust against schema changes:
local sound = opt_get("sound_on", true)     -- new option in a future version?
                                            -- default kicks in until first save.
local hs   = opt_get("hs_portraits", {})
```

**Implementation** (in `script.h`):
- Storage: one Lua table in the registry under `find5.opts`. `opt_set` / `opt_get` manipulate it directly — no marshalling per call.
- `opt_save`: walks the table, writes `return { ... }` via `fopen`/`fprintf`. Handles strings (escaped), numbers, booleans, nested tables (with cycle / depth cap = 16). Array-shaped tables emit compact form `{ v1, v2, v3 }`. Functions/userdata/threads are skipped (they're not persistable anyway). Atomic via tmp file + rename.
- `opt_load`: `luaL_loadfile("find5.dat")` + `lua_pcall` on the C side (bypassing the user-side `dofile`/`loadfile` ban). On error (missing / corrupt / not-a-table) the options reset to empty and a message goes to the log.

**Safety notes**:
- Path is hardcoded (`find5.dat`); scripts can't escape the working directory.
- `opt_load` runs the file as Lua code, but only the engine writes that file — so it's effectively trusted code. Corruption falls back to empty options instead of crashing.
- Single file, whole-table rewrite. Tiny (a few KB). No journaling needed.

**Random number generation** — already works. `math.random` in Lua 5.1 uses the C `rand()` under the hood, and `main.cpp` calls `srand(time(NULL))` at boot. So image picking needs no new binding.

## Implementation roadmap

Roughly in build order — each step is testable before moving to the next.

1. **Engine adds (shipped)**: scale + alpha + options-table on `draw_region`; `draw_text`; `draw_ellipse`; UI canvas to 480; `opt_set` / `opt_get` / `opt_save` / `opt_load`.
2. **Background + portraits visible**: draw `bg` full-canvas, draw one hardcoded image pair at portrait positions. Static. No input.
3. **Time bar + HUD labels + star column**: `draw_region` with `fill_x` for the time bar; `draw_text` for score / level / found counters; 5 `star_empty` regions stacked between portraits (filled per-find).
4. **Difference hit-test**: click on portrait 1 → if the click falls inside any unfound diff rect, append `{x, y, w, h, joker=false}` to `state.found`, bump the found counter, fill the next star, draw the **green** ellipse.
5. **Joker button**: single button below the star column with a remaining-counter beneath. Click → pick the first unfound diff, append `{..., joker=true}` to `state.found`, fill the next star, decrement `state.jokers`, draw the **yellow** ellipse. No-op when `state.jokers == 0`.
6. **Level complete**: when remaining == 0 → LEVEL_COMPLETE state. Dialog scales/fades in. Score count-up animation.
7. **Continue → next level** within a run (still one category, still one image pool).
8. **Pause dialog**: Esc or pause button → PAUSED. Dim + dialog. Restart / Highscore / Exit.
9. **Game over** (time-up): enter `GAME_OVER_REVEAL` → red ellipses on every unfound difference (staggered) → ~0.8s dwell → game-over dialog (Restart / Highscore).
10. **Level config from data**: replace hardcoded numbers with `scripts/levels.lua` (single category for now).
11. **Multi-category**: add the rest of the categories to `levels.lua`. Pick category programmatically at boot.
12. **Title screen**: logo + category preview + arrows + sound/music toggles + START + highscore button. State machine entry point. Persists `last_category` via `opt_set` + `opt_save`.
13. **Random image picking + used-images set**: pick from category's pool excluding `used_images[cat_id]`; reset when empty. Persist on each pick.
14. **Highscore screen**: per-category top-N list, reachable from title and from post-game dialogs. Saving new scores triggered automatically on GAME_OVER / ALL_DONE.
15. **Sound polish**: found / wrong / joker / **tick** (last-10s warning, once per second) / win SFX. Honor `settings.sound_on` / `settings.music_on` toggles.

Each step is a couple of evenings of work. Suggest committing in order so you always have a runnable build.
