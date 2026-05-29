-- scripts/menu.lua — Find5 title screen (draft).
--
-- Matches the layout from docs/game-mainmenu-mockup.png:
--   * "Find5" logo top-center
--   * close (X) button top-right (small button_up 9-patch + close_icon)
--   * category picker in the middle — square button2 buttons (◀ ▶)
--     flank the 177-px square category_box; caption underneath
--   * sound / music toggles in the bottom corners (button2 + on/off icon)
--   * Start game (wide), Highscores, Credits — 9-patched button_up
--
-- Backgrounds:
--   button_up / button_down  : 9-patch, slice {5,36,5,37} of the 41×42 art
--   button2_up / button2_down: drawn 1:1 at native 90×91 (no slice fields)
--
-- The scene plugs into engine.scene; main.lua pushes it from on_start
-- and the Start game button calls back into _G.find5_start_game to swap
-- this scene for the game scene.

local widget = require "engine.widget"
local LEVELS = require "levels"

-- ---- Layout (virtual canvas: 480 tall, origin center, Y-down) -------------
local LOGO_Y       = -222

local CLOSE_X      =  274
local CLOSE_Y      = -232
local CLOSE_SIZE   =   48

local SIDE_BTN_W   =   90
local SIDE_BTN_H   =   91

local CAT_BOX_W    =  177
local CAT_BOX_H    =  177
local CAT_BOX_X    =  -88            -- top-left (centered horizontally)
local CAT_BOX_Y    =  -98

local PICKER_Y_TL  = CAT_BOX_Y + (CAT_BOX_H - SIDE_BTN_H) / 2
local LEFT_BTN_X   = CAT_BOX_X - SIDE_BTN_W - 24
local RIGHT_BTN_X  = CAT_BOX_X + CAT_BOX_W  + 24

local SOUND_BTN_X  = -300
local MUSIC_BTN_X  =  210
local TOGGLE_BTN_Y =  130

local TEXT_BTN_H   =   42       -- secondary buttons (default font)
local START_BTN_H  =   60       -- primary "Start game" (large font)
local START_BTN_W  =  260
local START_BTN_X  = -130
local START_BTN_Y  =   85

local SUB_BTN_W    =  110
local SUB_BTN_Y    =  155
local HISC_BTN_X   = -115
local CRED_BTN_X   =    5

-- ---- Scene state ----------------------------------------------------------

local current_cat = 1
local widgets     = {}
local focused     = nil

-- Categories list. Pulled from levels.lua so adding a category there
-- shows up in the picker. Each entry surfaces a display name plus a
-- preview region (defaults to "category_1" for the draft assets).
local categories = {}
for i, c in ipairs(LEVELS.categories or {}) do
    categories[i] = {
        name    = c.title or c.id or ("Category " .. i),
        region  = c.region or "category_1",
        source  = c,
    }
end
if #categories == 0 then
    categories = { { name = "Medieval", region = "category_1" } }
end

local function at_first() return current_cat <= 1 end
local function at_last()  return current_cat >= #categories end

-- ---- Action handlers ------------------------------------------------------

local rebuild  -- forward decl

local function start_game_action()
    if _G.find5_start_game then
        _G.find5_start_game(categories[current_cat].source)
    end
end

local function highscores_action() ui_show_message("Highscores — TODO", 1.2) end
local function credits_action()    ui_show_message("Credits — TODO",    1.2) end

local function close_action()
    if _G.find5_request_quit then _G.find5_request_quit() end
end

local function prev_cat_action()
    if not at_first() then current_cat = current_cat - 1; rebuild() end
end
local function next_cat_action()
    if not at_last()  then current_cat = current_cat + 1; rebuild() end
end

local function sound_toggle_action()
    opt_set("sound_on", not opt_get("sound_on", true)); opt_save(); rebuild()
end

local function music_toggle_action()
    local on = not opt_get("music_on", true)
    opt_set("music_on", on); opt_save()
    if on then music_play("title", 0.3, true) else music_stop(0.3) end
    rebuild()
end

-- ---- Widget factories ------------------------------------------------------

local function make_text_button(spec)
    return widget.button({
        x        = spec.x,        y        = spec.y,
        width    = spec.width,    height   = spec.height or TEXT_BTN_H,
        text     = spec.text,     font     = spec.font,
        bg_up    = "button_up",   bg_down  = "button_down",
        on_click = spec.on_click,
    })
end

local function make_icon_button(spec)
    return widget.button({
        x         = spec.x,        y          = spec.y,
        width     = SIDE_BTN_W,    height     = SIDE_BTN_H,
        icon      = spec.icon,
        icon_align = ALIGN_CENTER + ALIGN_MIDDLE,
        bg_up     = "button2_up",  bg_down    = "button2_down",
        on_click  = spec.on_click,
        disabled  = spec.disabled or false,
    })
end

-- ---- Widget list -----------------------------------------------------------
-- Rebuilt on any state change that affects icons or disabled state
-- (category index, sound/music toggle). Focus is preserved across rebuilds
-- by remembering which slot was focused before — same slot on the new list
-- gets focus back, which works because the slot order is stable.

local FOCUS_SLOT_START = 6   -- Start game is widgets[6]

rebuild = function()
    local prev_slot
    if focused then
        for i, w in ipairs(widgets) do if w == focused then prev_slot = i; break end end
    end
    widgets = {}

    -- 1. Close (top-right). A small button_up 9-patch with the X icon.
    widgets[1] = widget.button({
        x = CLOSE_X, y = CLOSE_Y, width = CLOSE_SIZE, height = CLOSE_SIZE,
        bg_up = "button_up", bg_down = "button_down",
        icon = "close_icon", icon_align = ALIGN_CENTER + ALIGN_MIDDLE,
        on_click = close_action,
    })

    -- 2-3. Category picker arrows.
    widgets[2] = make_icon_button({
        x = LEFT_BTN_X, y = PICKER_Y_TL,
        icon = at_first() and "left_disabled_icon" or "left_icon",
        disabled = at_first(),
        on_click = prev_cat_action,
    })
    widgets[3] = make_icon_button({
        x = RIGHT_BTN_X, y = PICKER_Y_TL,
        icon = at_last() and "right_disabled_icon" or "right_icon",
        disabled = at_last(),
        on_click = next_cat_action,
    })

    -- 4-5. Audio toggles.
    widgets[4] = make_icon_button({
        x = SOUND_BTN_X, y = TOGGLE_BTN_Y,
        icon = opt_get("sound_on", true) and "sound_on_icon" or "sound_off_icon",
        on_click = sound_toggle_action,
    })
    widgets[5] = make_icon_button({
        x = MUSIC_BTN_X, y = TOGGLE_BTN_Y,
        icon = opt_get("music_on", true) and "music_on_icon" or "music_off_icon",
        on_click = music_toggle_action,
    })

    -- 6. Start game — primary action, large font, default focus target.
    widgets[6] = make_text_button({
        x = START_BTN_X, y = START_BTN_Y,
        width = START_BTN_W, height = START_BTN_H,
        text = "Start game", font = "large",
        on_click = start_game_action,
    })

    -- 7-8. Secondary buttons.
    widgets[7] = make_text_button({
        x = HISC_BTN_X, y = SUB_BTN_Y, width = SUB_BTN_W,
        text = "Highscores", on_click = highscores_action,
    })
    widgets[8] = make_text_button({
        x = CRED_BTN_X, y = SUB_BTN_Y, width = SUB_BTN_W,
        text = "Credits", on_click = credits_action,
    })

    -- Restore focus to the same slot if it's still focusable, otherwise
    -- default to Start game.
    local slot = prev_slot or FOCUS_SLOT_START
    local target = widgets[slot]
    if not (target and target.focusable and not target.disabled) then
        target = widgets[FOCUS_SLOT_START]
    end
    focused = target
    focused.focused = true
end

-- ---- Scene table -----------------------------------------------------------

local menu_scene = {}

function menu_scene:enter()
    rebuild()
    if opt_get("music_on", true) then
        music_play("title", 0.5, true)
    end
end

function menu_scene:exit() end

function menu_scene:update(dt)
    widget.dispatch_update(widgets, dt)
end

function menu_scene:render()
    -- Marble backdrop — stretch the 512² texture across the actual visible
    -- canvas (handles aspect ratios other than 4:3 cleanly).
    local vw, vh = view_size()
    draw_region("menu_bg", -vw / 2, -vh / 2, {
        scale_x = vw / 512, scale_y = vh / 512,
    })

    -- Logo: anchored to its top edge.
    draw_region("logo", 0, LOGO_Y, { align = ALIGN_CENTER + ALIGN_TOP })

    -- Category preview: frame, then the category image inset 1 px, then
    -- the title caption near the bottom of the frame.
    draw_region("category_box", CAT_BOX_X, CAT_BOX_Y)
    draw_region(categories[current_cat].region,
                CAT_BOX_X + 1, CAT_BOX_Y + 1)
    draw_text(categories[current_cat].name,
              CAT_BOX_X + CAT_BOX_W / 2,
              CAT_BOX_Y + CAT_BOX_H - 18, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        color = { 1.0, 1.0, 1.0 },
    })

    for _, w in ipairs(widgets) do w:draw() end
end

function menu_scene:mousedown(x, y, button)
    if button ~= 1 then return end
    -- Click-to-focus: whichever focusable widget the click landed in
    -- claims focus before the press registers.
    for _, w in ipairs(widgets) do
        if w.focusable and not w.disabled and w:hit(x, y) then
            if focused and focused ~= w then focused.focused = false end
            focused = w
            focused.focused = true
            break
        end
    end
    for _, w in ipairs(widgets) do
        if w.mousedown then w:mousedown(x, y, button) end
    end
end

function menu_scene:mouseup(x, y, button)
    for _, w in ipairs(widgets) do
        if w.mouseup then w:mouseup(x, y, button) end
    end
end

function menu_scene:mousemove(x, y, dx, dy)
    for _, w in ipairs(widgets) do
        if w.mousemove then w:mousemove(x, y, dx, dy) end
    end
end

function menu_scene:keydown(name)
    focused = widget.dispatch_keydown(widgets, focused, name) or focused
end

return menu_scene
