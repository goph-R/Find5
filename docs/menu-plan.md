# Main menu — plan

Pickup doc for the next session. State of play at end of 2026-05-27.

## Where we are

Dialog system is **done** on branch `dialogs` (not merged to main yet).
All four terminal states are dialogs: pause / level_complete /
game_over / all_done. Same chrome (marble + chains + blue button),
same intro (bounce-in over 0.7s), same outro (shoot-up exp accel over
0.4s), with `dialog_open` / `dialog_close` sounds played on each.

Placeholder art (flat-colored quads) is in place via
`SHOW_PLACEHOLDERS = true` in `scripts/dialog.lua`. When the marble /
chains / button artwork lands as regions in `assets.lua`, the
placeholders are covered automatically; flip the flag to false to
remove them entirely.

User feedback after first try: "Very cool! ... I really like how the
dialogs works." → the chrome + animation approach is approved. The
menu reuses the same visual language (marble, blue button, button
animations TBD), so most of the styling is paid for already.

## What the mockup shows

`docs/game-mainmenu-mockup.png`:

- "Find5" logo at top (gold with magnifying glass through the 5)
- Marble + cracks background (matches dialog)
- "X" close button top-right
- Centre: category preview card with title strip ("Medieval" in the
  mockup) + dark band beneath
- Yellow side-arrow buttons left/right of the card → prev/next category
- Big blue "Start game" button (same style as dialog primary button)
- Two smaller secondary buttons: "Highscore", "Credits"
- Round speaker icon bottom-left → sfx toggle
- Round music-note icon bottom-right → music toggle

## Open design questions to settle first

1. **Scene structure** — recommended: extract `scripts/menu.lua` as
   its own module with `update/render/handle_click` (mirroring
   `dialog.lua`). `main.lua` becomes a scene router that flips between
   `menu` and the gameplay loop. Alternative: another `STATE_MENU`
   inside `main.lua`'s existing state machine. The module split scales
   better (highscore screen, credits, options all become their own
   modules with the same interface).

2. **First slice** — recommended: shell-only first. Logo + background
   + Start game button that flips into the existing game with the
   single existing category. Side-arrows can be dead. This gets the
   scene-router working end-to-end before category data, persistence,
   sub-screens, etc.

   The full menu is roughly: shell → category browser data → category
   preview rendering → highscore screen → credits screen → audio
   toggles → persistence. Each is independent once the shell exists.

3. **Highscore / Credits screens** — full sub-scenes (their own
   modules) or dialogs (reusing the dialog system)? Credits probably
   wants to be a dialog (small content, single dismiss). Highscore
   depends on layout — if it's a long list per category, sub-scene
   makes more sense.

## What needs to grow in `levels.lua`

Currently one category with one image pair. Menu needs at least:

- `id` — already there
- `title` — already there
- `preview` — new field: region name for the card image (each category
  needs a thumbnail texture)

```lua
{ id = "medieval", title = "Medieval", preview = "preview_medieval",
  images = { ... } },
```

The category list drives the prev/next browser. Number of available
categories = `#LEVELS.categories`.

## Assets to register when art lands

New regions in `assets.lua`:

- `logo` — Find5 logo (top of menu)
- `menu_bg` — marble background (or reuse the dialog's marble if it's
  the same texture; check `docs/game-dialog-mockup.png` vs the menu
  mockup — they look identical)
- `close_button` — the X top-right
- `arrow_left` / `arrow_right` — yellow side arrows
- `button_blue_up` / `button_blue_down` — already mentioned in
  dialog.lua; same region shared between menu and dialogs
- `button_secondary_up` / `_down` — smaller dark buttons for
  Highscore / Credits
- `icon_speaker` — sfx toggle
- `icon_music` — music toggle
- `preview_<category>` — one per category for the card image
- `card_bg` — marble frame around the preview card if it's a separate
  region (the mockup looks like the preview image sits in a darker
  inset on the marble)

New sounds:

- `button_click` (or `menu_select` / `menu_back`) — UI feedback
- `category_switch` — when prev/next is pressed

## Persistence (find5.dat via opt_get/opt_set)

Things the menu reads/writes:

- `selected_category` (int) — last category the user browsed to
- `sfx_enabled` (bool)
- `music_enabled` (bool)
- highscore data is a follow-up; per-category `{ score, date }` list

## What to do first thing tomorrow

1. Re-read this doc (it points to the dialog branch state).
2. Decide on scene structure (recommended: extract `scripts/menu.lua`).
3. Implement the shell slice: logo + bg + "Start game" button that
   transitions into the game. Side arrows / secondary buttons /
   toggles all as placeholder no-ops, just visible.
4. Verify with the headless boot recipe in `CLAUDE.md`.

The dialog branch is up at `origin/dialogs`; merge to `main` first, or
branch the menu work off `dialogs` so it inherits the dialog system.
The dialog module is reused for Credits at minimum, and the close
button on the menu probably wants the same "are you sure you want to
quit?" dialog pattern.
