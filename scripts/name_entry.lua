-- scripts/name_entry.lua — "enter your name" screen for a qualifying run.
--
-- Shown (via scene.replace) when a finished run beats the high-score table.
-- The caller sets the module field `score` before replacing; this scene
-- collects a name, records it through scores.add, then hands off to the
-- scoreboard with the new row highlighted.
--
--   require("name_entry").score = finalScore
--   scene.replace(require("name_entry"), transition.fadeThroughBlack(...))
--
-- The LineEdit is added first so panel:add auto-focuses it; the scene
-- exposes `root`, so engine.scene routes textInput / keyDown straight to
-- the focused field with no per-scene plumbing.

local widget     = require "engine.widget"
local scene      = require "engine.scene"
local transition = require "engine.transition"
local scores     = require "scores"

-- ---- Layout (virtual canvas: 480 tall, origin center, Y-down) -------------
local PANEL_X    = -240
local PANEL_W    =  480
local PANEL_TOP  = -150
local PANEL_H    =  310

local FIELD_W    =  300
local FIELD_H    =   44
local FIELD_Y    =    5

local OK_W       =  180
local OK_H       =   56
local OK_Y       =   90

local root  = widget.panel({ x = 0, y = 0 })
local field                       -- the LineEdit, captured for submit

local M = { root = root, score = 0 }

-- Record the entered name and move on to the scoreboard. Trim surrounding
-- whitespace; a blank name falls back to "Player" so the row never reads as
-- empty. The rank scores.add returns drives the highlight on the board.
local function finish()
    local name = (field and field.text or "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Player" end

    local board = require "highscores"
    board.highlightRank = scores.add(name, M.score)
    scene.replace(board, transition.fadeThroughBlack(0.5))
end

local function rebuild()
    root.children     = {}
    root.focusedChild = nil

    field = widget.lineEdit({
        x = -FIELD_W / 2, y = FIELD_Y, width = FIELD_W, height = FIELD_H,
        font        = "large",
        maxLength   = scores.MAX_NAME,
        color       = { 1, 1, 1 },
        bgColor     = { enabled = { 0, 0, 0, 0.55 } },
        placeholder = "your name",
        onSubmit    = function() finish() end,
    })
    root:add(field)                -- added first -> auto-focused

    root:add(widget.button({
        x = -OK_W / 2, y = OK_Y, width = OK_W, height = OK_H,
        text = "OK", font = "large",
        bgUp = "button_up", bgDown = "button_down", bgHover = "button_hover",
        onClick = finish,
    }))
end

function M:enter()
    rebuild()
end

function M:render()
    -- Marble backdrop — cover-fit to the visible canvas, like menu.lua.
    drawBg("menu_bg")
    drawQuad(PANEL_X, PANEL_TOP, PANEL_W, PANEL_H, { color = { 0, 0, 0, 0.45 } })

    drawText("NEW HIGH SCORE!", 0, -110, {
        align = ALIGN_CENTER + ALIGN_MIDDLE, font = "large",
        color = { 1.0, 0.95, 0.2 },
    })
    drawText(string.format("Score:  %d", self.score), 0, -62, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        color = { 1, 1, 1 },
    })
    drawText("Enter your name:", 0, -26, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        color = { 0.85, 0.85, 0.9 },
    })

    self.root:draw()
end

return M
