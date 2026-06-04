-- scripts/highscores.lua — Find5 scoreboard screen.
--
-- A scene (sibling of menu.lua) that shows the ranked high-score table from
-- scores.lua over the shared marble backdrop. Title, score rows and the Back
-- button are all widgets, so the whole board pops in with a staggered
-- fade + scale rather than appearing flat.
--
-- Navigation mirrors the menu <-> game idiom: reached by
--   scene.replace(require("highscores"), transition.fadeThroughBlack(...))
-- and Back returns the same way. fadeThroughBlack is overlay-based, so it
-- covers the directly-drawn bg / list (a root-alpha fade would miss them).
-- Because replace pops the outgoing scene, the stack never grows — there's
-- only ever one of menu / highscores live at a time.
--
-- `highlightRank` (module field) lets the run-end record flow open this
-- screen with the freshly-added row tinted; cleared on exit so a later plain
-- visit from the menu shows no highlight.

local widget     = require "engine.widget"
local anim       = require "engine.animation"
local scene      = require "engine.scene"
local transition = require "engine.transition"
local scores     = require "scores"

-- ---- Layout (virtual canvas: 480 tall, origin center, Y-down) -------------
local TITLE_Y      = -200

local PANEL_X      = -250
local PANEL_W      =  500
local PANEL_TOP    = -168
local PANEL_H      =  316

local LIST_TOP_Y   = -148        -- baseline of row 1 (ALIGN_MIDDLE)
local ROW_STEP     =   30

local RANK_X       = -208        -- right edge of the "N." rank column
local NAME_X       = -184        -- left edge of the name column
local SCORE_X      =  208        -- right edge of the score column

local BACK_BTN_W   =  150
local BACK_BTN_H   =   42
local BACK_BTN_Y   =  164

local HIGHLIGHT_COLOR = { 0.45, 1.0, 0.55 }
local ROW_COLOR       = { 1.0,  1.0, 1.0  }
local TITLE_COLOR     = { 1.0,  0.95, 0.2 }

-- ---- Scene state ----------------------------------------------------------

local root = widget.panel({ x = 0, y = 0 })

local function backAction()
    scene.replace(require("menu"), transition.fadeThroughBlack(0.5))
end

-- Seed a widget with a staggered fade + scale pop-in (same easeOutBack
-- bounce as the menu buttons). Returns the widget so it composes with
-- root:add. Per-widget so each row can carry its own delay.
local function popIn(w, delay)
    w.alpha  = 0
    w.scale  = 0.7
    w.action = anim.sequence{
        anim.delay(delay),
        anim.parallel{
            anim.fadeIn(0.25),
            anim.scaleTo(1.0, 0.35, anim.easeOutBack),
        },
    }
    return w
end

-- A score-cell label. The zero-size bbox makes it position and scale exactly
-- like the raw drawText it replaces: anchorIn collapses to the (x, y) align
-- point and stays there as the text scales, so the columns keep their
-- alignment while the pop-in plays (a sized bbox would scale about its centre
-- and drift the anchored edge).
local function cell(x, y, text, align, color, font)
    return widget.label({
        x = x, y = y, width = 0, height = 0,
        text = text, align = align, color = color, font = font,
    })
end

-- Build the title, one label per score cell, and the Back button — each
-- seeded with a pop-in so the whole board animates in. Rows stagger by row
-- (the three cells of a row share a delay); the Back button trails the last
-- row. highlightRank tints its row.
local function rebuild(highlightRank)
    root.children     = {}
    root.focusedChild = nil

    popIn(root:add(cell(0, TITLE_Y, "HIGH SCORES",
        ALIGN_CENTER + ALIGN_MIDDLE, TITLE_COLOR, "large")), 0.0)

    local list = scores.list()
    if #list == 0 then
        popIn(root:add(cell(0, 0, "No scores yet - play a game!",
            ALIGN_CENTER + ALIGN_MIDDLE, { 0.85, 0.85, 0.9 })), 0.12)
    else
        for i, e in ipairs(list) do
            local y = LIST_TOP_Y + (i - 1) * ROW_STEP
            local c = (i == highlightRank) and HIGHLIGHT_COLOR or ROW_COLOR
            local d = 0.10 + (i - 1) * 0.04
            popIn(root:add(cell(RANK_X, y, i .. ".",
                ALIGN_RIGHT + ALIGN_MIDDLE, c)), d)
            popIn(root:add(cell(NAME_X, y, e.name ~= "" and e.name or "-",
                ALIGN_LEFT + ALIGN_MIDDLE, c)), d)
            popIn(root:add(cell(SCORE_X, y, tostring(e.score),
                ALIGN_RIGHT + ALIGN_MIDDLE, c)), d)
        end
    end

    -- Back button last (focusable, so panel:add auto-focuses it).
    local backDelay = 0.10 + math.max(#list, 1) * 0.04 + 0.05
    popIn(root:add(widget.button({
        x = -BACK_BTN_W / 2, y = BACK_BTN_Y,
        width = BACK_BTN_W,  height = BACK_BTN_H,
        text = "Back", font = "small",
        bgUp = "button_up", bgDown = "button_down", bgHover = "button_hover",
        onClick = backAction,
    })), backDelay)
end

-- ---- Scene table -----------------------------------------------------------
-- root is exposed so engine.scene fans input/update into it; only :enter and
-- :render are custom. highlightRank is baked into the row colours by rebuild
-- at :enter, then cleared in :exit so a later plain visit shows no highlight.

local highscoresScene = { root = root, highlightRank = nil }

function highscoresScene:enter()
    rebuild(self.highlightRank)
end

function highscoresScene:exit()
    self.highlightRank = nil
end

function highscoresScene:render()
    -- Marble backdrop, stretched to the visible canvas (matches menu.lua).
    local vw, vh = viewSize()
    drawRegion("menu_bg", -vw / 2, -vh / 2, {
        scaleX = vw / 512, scaleY = vh / 512,
    })

    -- Translucent slab behind the list for legibility over the marble.
    drawQuad(PANEL_X, PANEL_TOP, PANEL_W, PANEL_H, { color = { 0, 0, 0, 0.45 } })

    -- Title, rows and Back button are all widgets now, so the panel draws
    -- them with their pop-in transforms applied.
    self.root:draw()
end

return highscoresScene
