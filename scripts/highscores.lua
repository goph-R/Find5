-- scripts/highscores.lua — Find5 scoreboard screen.
--
-- A scene (sibling of menu.lua) that shows the ranked high-score table from
-- scores.lua over the shared marble backdrop, with a single Back button.
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

local BACK_BTN_W   =  200
local BACK_BTN_H   =   56
local BACK_BTN_Y   =  168

local HIGHLIGHT_COLOR = { 0.45, 1.0, 0.55 }
local ROW_COLOR       = { 1.0,  1.0, 1.0  }
local TITLE_COLOR     = { 1.0,  0.95, 0.2 }

-- ---- Scene state ----------------------------------------------------------

local root = widget.panel({ x = 0, y = 0 })

local function backAction()
    scene.replace(require("menu"), transition.fadeThroughBlack(0.5))
end

local function rebuild()
    root.children     = {}
    root.focusedChild = nil

    root:add(widget.button({
        x = -BACK_BTN_W / 2, y = BACK_BTN_Y,
        width = BACK_BTN_W,  height = BACK_BTN_H,
        text = "Back", font = "large",
        bgUp = "button_up", bgDown = "button_down", bgHover = "button_hover",
        onClick = backAction,
    }))
end

-- ---- Scene table -----------------------------------------------------------
-- root is exposed so engine.scene fans input/update into it; only :enter and
-- :render are custom. highlightRank is read in :render and cleared in :exit.

local highscoresScene = { root = root, highlightRank = nil }

function highscoresScene:enter()
    rebuild()

    -- Back button pops in (same easeOutBack bounce as the menu buttons).
    for i, child in ipairs(root.children) do
        child.alpha  = 0
        child.scale  = 0.7
        child.action = anim.sequence{
            anim.delay(0.05 * (i - 1)),
            anim.parallel{
                anim.fadeIn(0.25),
                anim.scaleTo(1.0, 0.35, anim.easeOutBack),
            },
        }
    end
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

    drawText("HIGH SCORES", 0, TITLE_Y, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        font  = "large",
        color = TITLE_COLOR,
    })

    local list = scores.list()
    if #list == 0 then
        drawText("No scores yet - play a game!", 0, 0, {
            align = ALIGN_CENTER + ALIGN_MIDDLE,
            color = { 0.85, 0.85, 0.9 },
        })
    else
        for i, e in ipairs(list) do
            local y = LIST_TOP_Y + (i - 1) * ROW_STEP
            local c = (i == self.highlightRank) and HIGHLIGHT_COLOR or ROW_COLOR
            drawText(i .. ".", RANK_X, y, {
                align = ALIGN_RIGHT + ALIGN_MIDDLE, color = c,
            })
            drawText(e.name ~= "" and e.name or "-", NAME_X, y, {
                align = ALIGN_LEFT + ALIGN_MIDDLE, color = c,
            })
            drawText(tostring(e.score), SCORE_X, y, {
                align = ALIGN_RIGHT + ALIGN_MIDDLE, color = c,
            })
        end
    end

    self.root:draw()
end

return highscoresScene
