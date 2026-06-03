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
-- The scene plugs into engine.scene; main.lua pushes it from onStart
-- and the Start game button calls back into _G.find5StartGame to swap
-- this scene for the game scene.

local widget = require "engine.widget"
local anim   = require "engine.animation"
local dialog = require "dialog"
local LEVELS = require "levels"

-- ---- Layout (virtual canvas: 480 tall, origin center, Y-down) -------------
local LOGO_Y       = -232

local CLOSE_X      =  264
local CLOSE_Y      = -232
local CLOSE_SIZE   =   48

local SIDE_BTN_W   =   90
local SIDE_BTN_H   =   91

local CAT_BOX_W    =  177
local CAT_BOX_H    =  177
local CAT_BOX_X    =  -88            -- top-left (centered horizontally)
local CAT_BOX_Y    =  -88

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
local START_BTN_Y  =  110

local SUB_BTN_W    =  110
local SUB_BTN_Y    =  180
local HISC_BTN_X   = -115
local CRED_BTN_X   =    5

-- ---- Scene state ----------------------------------------------------------

local currentCat = 1

-- Top-level panel at scene origin (0,0). Children use scene-space coords
-- directly — the panel adds zero offset, it just fans events out.
local root = widget.panel({ x = 0, y = 0 })

-- Categories list. Pulled from levels.lua so adding a category there
-- shows up in the picker. Each entry surfaces a display name plus a
-- preview region (defaults to "category_1" for the draft assets).
local categories = {}
for i, c in ipairs(LEVELS.categories or {}) do
    categories[i] = {
        name    = c.title or c.id or ("Category " .. i),
        region  = c.region or "category_" .. c.id,
        source  = c,
    }
end

local function atFirst() return currentCat <= 1 end
local function atLast()  return currentCat >= #categories end

-- ---- Action handlers ------------------------------------------------------

local rebuild  -- forward decl

local function startGameAction()
    if _G.find5StartGame then
        _G.find5StartGame(categories[currentCat].source)
    end
end

local function highscoresAction() uiShowMessage("Highscores — TODO", 1.2) end
local function creditsAction()    uiShowMessage("Credits — TODO",    1.2) end

-- Quit the whole app. Fired AFTER the confirm dialog's outro (the
-- normal action path) — no scene fade is taking over here, unlike the
-- in-game "Exit to main menu" dialog, so we let the dialog play its
-- outro cleanly and quit on completion (no skipOutro).
local function quitAction()
    if _G.find5RequestQuit then _G.find5RequestQuit() end
end

-- Modeled on main.lua's confirmExitSpecFn (same height / button
-- geometry). The menu has no pause screen to fall back to, so "No"
-- carries neither `replace` nor `action`: clicking it just runs the
-- normal close, dropping back to the live menu underneath.
local function confirmExitSpecFn()
    return {
        title = "Exit to system?",
        height = 170,
        buttons = {
            { x = -60, y = 25, w = 100, h = 56,
              label = "No" },
            { x =  60, y = 25, w = 100, h = 56,
              label = "Yes",
              action = quitAction },
        },
    }
end

local function closeAction()
    dialog.show(confirmExitSpecFn())
end

local function prevCatAction()
    if not atFirst() then currentCat = currentCat - 1; rebuild() end
end
local function nextCatAction()
    if not atLast()  then currentCat = currentCat + 1; rebuild() end
end

local function soundToggleAction()
    optSet("sound_on", not optGet("sound_on", true)); optSave(); rebuild()
end

local function musicToggleAction()
    local on = not optGet("music_on", true)
    optSet("music_on", on); optSave()
    if on then musicPlay("title", 0.3, true) else musicStop(0.3) end
    rebuild()
end

-- ---- Widget factories ------------------------------------------------------

local function makeTextButton(spec)
    return widget.button({
        x        = spec.x,        y        = spec.y,
        width    = spec.width,    height   = spec.height or TEXT_BTN_H,
        text     = spec.text,     font     = spec.font,
        bgUp    = "button_up",   bgDown  = "button_down",
        bgHover = "button_hover",
        onClick = spec.onClick,
    })
end

local function makeIconButton(spec)
    return widget.button({
        x         = spec.x,        y          = spec.y,
        width     = SIDE_BTN_W,    height     = SIDE_BTN_H,
        icon      = spec.icon,
        iconAlign = ALIGN_CENTER + ALIGN_MIDDLE,
        bgUp     = "button2_up",  bgDown    = "button2_down",
        bgHover  = "button2_hover",
        onClick  = spec.onClick,
        disabled  = spec.disabled or false,
    })
end

-- ---- Widget list -----------------------------------------------------------
-- Rebuilt on any state change that affects icons or disabled state
-- (category index, sound/music toggle). Focus is preserved across rebuilds
-- by remembering which slot was focused before — same slot on the new list
-- gets focus back, which works because the slot order is stable.

local FOCUS_SLOT_START = 7   -- Start game is children[7] (logo at [1])

rebuild = function()
    local prevSlot
    if root.focusedChild then
        for i, w in ipairs(root.children) do
            if w == root.focusedChild then prevSlot = i; break end
        end
    end

    root.children = {}
    root.focusedChild = nil

    -- 1. Logo (top-center). Non-focusable so the panel skips it for
    -- focus claims; drawn first so it sits behind everything that
    -- follows.
    root:add(widget.image({
        x = 0, y = LOGO_Y, region = "logo",
        align = ALIGN_CENTER + ALIGN_TOP,
    }))

    -- 2. Close (top-right). A small button_up 9-patch with the X icon.
    root:add(widget.button({
        x = CLOSE_X, y = CLOSE_Y, width = CLOSE_SIZE, height = CLOSE_SIZE,
        bgUp = "button_up", bgDown = "button_down",
        bgHover = "button_hover",
        icon = "close_icon", iconAlign = ALIGN_CENTER + ALIGN_MIDDLE,
        onClick = closeAction,
    }))

    -- 3-4. Category picker arrows.
    root:add(makeIconButton({
        x = LEFT_BTN_X, y = PICKER_Y_TL,
        icon = atFirst() and "left_disabled_icon" or "left_icon",
        disabled = atFirst(),
        onClick = prevCatAction,
    }))
    root:add(makeIconButton({
        x = RIGHT_BTN_X, y = PICKER_Y_TL,
        icon = atLast() and "right_disabled_icon" or "right_icon",
        disabled = atLast(),
        onClick = nextCatAction,
    }))

    -- 5-6. Audio toggles.
    root:add(makeIconButton({
        x = SOUND_BTN_X, y = TOGGLE_BTN_Y,
        icon = optGet("sound_on", true) and "sound_on_icon" or "sound_off_icon",
        onClick = soundToggleAction,
    }))
    root:add(makeIconButton({
        x = MUSIC_BTN_X, y = TOGGLE_BTN_Y,
        icon = optGet("music_on", true) and "music_on_icon" or "music_off_icon",
        onClick = musicToggleAction,
    }))

    -- 7. Start game — primary action, large font, default focus target.
    root:add(makeTextButton({
        x = START_BTN_X, y = START_BTN_Y,
        width = START_BTN_W, height = START_BTN_H,
        text = "Start game", font = "large",
        onClick = startGameAction,
    }))

    -- 8-9. Secondary buttons.
    root:add(makeTextButton({
        x = HISC_BTN_X, y = SUB_BTN_Y, width = SUB_BTN_W,
        text = "Highscores", onClick = highscoresAction,
    }))
    root:add(makeTextButton({
        x = CRED_BTN_X, y = SUB_BTN_Y, width = SUB_BTN_W,
        text = "Credits", onClick = creditsAction,
    }))

    -- Restore focus to the same slot if it's still focusable, otherwise
    -- default to Start game. :add() auto-focused the first focusable
    -- child (the close button); override here.
    local slot = prevSlot or FOCUS_SLOT_START
    local target = root.children[slot]
    if not (target and target.focusable and not target.disabled) then
        target = root.children[FOCUS_SLOT_START]
    end
    if root.focusedChild and root.focusedChild ~= target then
        root.focusedChild.focused = false
    end
    root.focusedChild = target
    target.focused = true
end

-- ---- Scene table -----------------------------------------------------------
--
-- root is exposed on the scene so engine.scene's dispatchers auto-
-- forward update / mouse / key events into it — no per-method
-- boilerplate. Only :enter and :render are needed: enter builds the
-- widget tree, render paints the scene-specific bg art and then asks
-- root to draw the widgets on top.

local menuScene = { root = root }

-- The exit-confirm dialog is modal: while it's active it owns every
-- mouse event (its button hit-tests run inside the handle* calls and
-- misses are swallowed, so clicks never fall through to the menu
-- widgets underneath). When idle, events fan out to the widget tree as
-- before. Mirrors the game scene's dialog plumbing in main.lua.
function menuScene:update(dt)
    root:update(dt)
    dialog.update(dt)
end

function menuScene:mouseDown(x, y, button)
    if dialog.isActive() then dialog.handleMouseDown(x, y, button); return end
    root:mouseDown(x, y, button)
end

function menuScene:mouseUp(x, y, button)
    if dialog.isActive() then dialog.handleMouseUp(x, y, button); return end
    root:mouseUp(x, y, button)
end

function menuScene:mouseMove(x, y, dx, dy)
    if dialog.isActive() then dialog.handleMouseMove(x, y, dx, dy); return end
    root:mouseMove(x, y, dx, dy)
end

function menuScene:enter()
    rebuild()
    if optGet("music_on", true) then
        musicPlay("title", 0.5, true)
    end

    -- Staggered pop-in: each button fades + scales from 0.7 to 1.0
    -- around its own center, 50 ms apart in declaration order. The
    -- easeOutBack overshoots a touch and snaps back so the buttons
    -- have a bit of bounce on arrival.
    for i, child in ipairs(root.children) do
        child.alpha = 0
        child.scale = 0.7
        child.action = anim.sequence{
            anim.delay(0.05 * (i - 1)),
            anim.parallel{
                anim.fadeIn(0.25),
                anim.scaleTo(1.0, 0.35, anim.easeOutBack),
            },
        }
    end
end

function menuScene:render()
    -- Marble backdrop — stretch the 512² texture across the actual visible
    -- canvas (handles aspect ratios other than 4:3 cleanly).
    local vw, vh = viewSize()
    drawRegion("menu_bg", -vw / 2, -vh / 2, {
        scaleX = vw / 512, scaleY = vh / 512,
    })

    -- Category preview: category image inset 1 px, then frame (over image)
    -- the title caption near the bottom of the frame.
    drawRegion(categories[currentCat].region,
                CAT_BOX_X + 1, CAT_BOX_Y + 1)
    drawRegion("category_box", CAT_BOX_X, CAT_BOX_Y)
    drawText(categories[currentCat].name,
              CAT_BOX_X + CAT_BOX_W / 2,
              CAT_BOX_Y + CAT_BOX_H - 15, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        color = { 1.0, 1.0, 1.0 },
    })

    self.root:draw()

    -- Dialog renders last so the modal (dim + panel) sits above the
    -- whole title screen, including the direct drawRegion bg/category art.
    dialog.render()
end

return menuScene
