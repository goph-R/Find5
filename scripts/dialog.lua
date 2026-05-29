-- Find5 — modal dialog system.
--
-- A single dialog at a time. Drops in from above with an easeOutBounce
-- (two visible re-impacts before settling); shoots back up out the top
-- on close with an easeInExpo (slow-start, exponential acceleration).
-- A separate dim quad behind the dialog fades in during intro and
-- snaps out faster during outro. An "open" sound plays on show(), a
-- "close" sound on close().
--
-- Dialogs are spec-driven — the spec table describes title, buttons,
-- and a draw_body callback for variable content (see show() for fields).
-- Button positions are in dialog-local coords (origin = dialog center).
--
-- Integration: main.lua keeps its existing state machine and calls
-- dialog.show()/close() at the same moments it enters/leaves modal
-- phases. While dialog.is_active() the game owner should route clicks
-- through dialog.handle_click() and call dialog.update()/render() at
-- the appropriate points in the frame.
--
-- Placeholder art: while final marble/chains/button art doesn't exist
-- yet, SHOW_PLACEHOLDERS draws flat-coloured quads underneath the
-- region calls. The region calls themselves are harmless no-ops until
-- the regions get registered in assets.lua, at which point the real
-- art covers the placeholders. Flip SHOW_PLACEHOLDERS to false (or
-- delete the placeholder lines) once the art lands.

local M = {}

-- ---- Animation phases ----------------------------------------------------
local STATE_INTRO = "intro"
local STATE_OPEN  = "open"
local STATE_OUTRO = "outro"

-- ---- Tunables ------------------------------------------------------------
local OPEN_DURATION  = 0.70   -- drop-in until rest
local CLOSE_DURATION = 0.40   -- shoot-up until off-screen
local DIM_FADE_IN    = 0.30   -- dim alpha ramps up alongside the drop
local DIM_FADE_OUT   = 0.20   -- dim alpha snaps out faster than the dialog leaves
local START_OFFSET   = 720    -- px above rest where the dialog starts (well off-screen)
local DIM_ALPHA      = 0.88   -- target dim once intro settles

-- ---- Default layout (a spec may override w / h / chains_h) ---------------
local DEFAULT_W        = 460
local DEFAULT_H        = 320
local DEFAULT_CHAINS_H = 120

local SHOW_PLACEHOLDERS = true

-- ---- Internal state ------------------------------------------------------
local current        = nil    -- { spec, state, t }
local pending_action = nil    -- fires after outro completes

-- ---- Easing --------------------------------------------------------------

-- Robert Penner's easeOutBounce. Returns 0..1 from input 0..1. The
-- canonical bouncy drop — visually reads as "land, bounce, land,
-- smaller bounce, settle".
local function easeOutBounce(p)
    if p < 1 / 2.75 then
        return 7.5625 * p * p
    elseif p < 2 / 2.75 then
        p = p - 1.5 / 2.75
        return 7.5625 * p * p + 0.75
    elseif p < 2.5 / 2.75 then
        p = p - 2.25 / 2.75
        return 7.5625 * p * p + 0.9375
    else
        p = p - 2.625 / 2.75
        return 7.5625 * p * p + 0.984375
    end
end

-- Robert Penner's easeInExpo — slow start, exponential acceleration.
-- Matches the "shoots off the top" feel the user asked for on close.
local function easeInExpo(p)
    if p <= 0 then return 0 end
    return math.pow(2, 10 * (p - 1))
end

-- ---- Frame helpers (depend on current.state / current.t) -----------------

local function yOffset()
    if current.state == STATE_INTRO then
        local p = current.t / OPEN_DURATION
        if p > 1 then p = 1 end
        return -(1 - easeOutBounce(p)) * START_OFFSET
    elseif current.state == STATE_OUTRO then
        local p = current.t / CLOSE_DURATION
        if p > 1 then p = 1 end
        return -easeInExpo(p) * START_OFFSET
    end
    return 0
end

local function dimAlpha()
    if current.state == STATE_INTRO then
        local p = current.t / DIM_FADE_IN
        if p > 1 then p = 1 end
        return DIM_ALPHA * p
    elseif current.state == STATE_OUTRO then
        local p = current.t / DIM_FADE_OUT
        if p > 1 then p = 1 end
        return DIM_ALPHA * (1 - p)
    end
    return DIM_ALPHA
end

local function introDone()
    return current.state == STATE_OPEN or current.state == STATE_OUTRO
end

-- ---- Public API ----------------------------------------------------------

function M.is_active()
    return current ~= nil
end

-- Open a dialog. spec fields (all optional unless noted):
--   title          string                — drawn near the top, large font
--   appear_sound   string  ("dialog_open")
--   close_sound    string  ("dialog_close")
--   w, h           number  — dialog size, default 460×320
--   chains_h       number  — chains region height, default 120
--   buttons        array of { x, y, w, h, label, region, action }
--                   positions in dialog-local coords (origin = dialog center).
--                   action runs AFTER the outro animation completes.
--   draw_body      function(intro_done, t, anchor_x, anchor_y)
--                   called every frame; (anchor_x, anchor_y) is the dialog's
--                   center on screen including the animation offset.
function M.show(spec)
    current = {
        spec  = spec,
        state = STATE_INTRO,
        t     = 0,
    }
    snd_play(spec.appear_sound or "dialog_open")
end

-- Begin the outro animation. If a button's action set pending_action,
-- that action runs once outro completes (so the level transition / etc
-- happens after the dialog has visibly left the screen).
function M.close()
    if not current or current.state == STATE_OUTRO then return end
    current.state = STATE_OUTRO
    current.t     = 0
    snd_play(current.spec.close_sound or "dialog_close")
end

function M.update(dt)
    if not current then return end
    current.t = current.t + dt
    if current.state == STATE_INTRO then
        if current.t >= OPEN_DURATION then
            current.state = STATE_OPEN
            current.t     = 0
        end
    elseif current.state == STATE_OUTRO then
        if current.t >= CLOSE_DURATION then
            current = nil
            if pending_action then
                local a = pending_action
                pending_action = nil
                a()
            end
        end
    end
end

function M.render()
    if not current then return end

    local spec   = current.spec
    local dlg_w  = spec.w        or DEFAULT_W
    local dlg_h  = spec.h        or DEFAULT_H
    local ch_h   = spec.chains_h or DEFAULT_CHAINS_H

    local vw, vh = view_size()
    draw_quad(-vw/2, -vh/2, vw, vh, { color = { 0, 0, 0, dimAlpha() } })

    local dy = yOffset()
    local ax = 0           -- dialog center x (canvas)
    local ay = 0 + dy      -- dialog center y (canvas, animated)

    -- Marble panel — drawn first so chains can overlap its top edge.
    if SHOW_PLACEHOLDERS then
        draw_quad(-dlg_w/2, ay - dlg_h/2, dlg_w, dlg_h,
                  { color = { 0.12, 0.10, 0.14, 1.0 } })
    end
    draw_region("dialog_bg", -dlg_w/2, ay - dlg_h/2)

    -- Chains — sit above the marble, hanging from the screen top once
    -- the dialog is at rest. They drop in together with the marble.
    if SHOW_PLACEHOLDERS then
        draw_quad(-dlg_w/2, ay - dlg_h/2 - ch_h, dlg_w, ch_h,
                  { color = { 0.22, 0.18, 0.12, 0.85 } })
    end
    draw_region("dialog_chains", -dlg_w/2, ay - dlg_h/2 - ch_h)

    -- Title — visible from frame 1 of the intro.
    if spec.title then
        draw_text(spec.title, ax, ay - dlg_h/2 + 40, {
            align = ALIGN_CENTER + ALIGN_MIDDLE,
            font  = "large",
            color = { 1, 1, 1 },
        })
    end

    -- Buttons — visible from frame 1; hit-test is against rest position.
    for _, btn in ipairs(spec.buttons or {}) do
        local bw = btn.w or 200
        local bh = btn.h or 48
        local bx = ax + (btn.x or 0) - bw/2
        local by = ay + (btn.y or 0) - bh/2
        if SHOW_PLACEHOLDERS then
            draw_quad(bx, by, bw, bh, { color = { 0.18, 0.40, 0.70, 1.0 } })
        end
        draw_region(btn.region or "button_blue_up", bx, by)
        if btn.label then
            draw_text(btn.label, ax + (btn.x or 0), ay + (btn.y or 0), {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                color = { 1, 1, 1 },
            })
        end
    end

    -- Body content — the spec drives whatever else appears. intro_done
    -- lets bodies stagger sub-animations after the dialog settles.
    if spec.draw_body then
        spec.draw_body(introDone(), current.t, ax, ay)
    end
end

-- Returns true if the click was consumed by the dialog (always true
-- while the dialog is active, so the caller knows not to fall through
-- to game logic). Hit-tests buttons against rest position only — the
-- dialog never accepts input during intro / outro.
function M.handle_click(x, y)
    if not current then return false end
    if current.state ~= STATE_OPEN then return true end

    for _, btn in ipairs(current.spec.buttons or {}) do
        local bw = btn.w or 200
        local bh = btn.h or 48
        local bx = (btn.x or 0) - bw/2     -- rest position: ay = 0
        local by = (btn.y or 0) - bh/2
        if x >= bx and x < bx + bw and y >= by and y < by + bh then
            pending_action = btn.action
            M.close()
            return true
        end
    end
    return true   -- swallow misses too — players shouldn't click "through" a modal
end

return M
