-- Find5 — main game loop.
-- One level plays end-to-end now: pick the diffs from levels.lua, run a
-- timer, accept clicks / jokers, and resolve into LEVEL_COMPLETE or
-- GAME_OVER (with a staggered red-ellipse reveal of the missed diffs).
-- Clicking in either terminal state restarts the level.

local LEVELS     = require "levels"
local dialog     = require "dialog"
local scene      = require "engine.scene"
local transition = require "engine.transition"

-- Pick a single image pair to play for now. Multi-image / multi-category
-- rotation lands with the title screen.
local current_pair  = LEVELS.categories[1].images[1]
local current_diffs = current_pair.diffs

-- ---- State-machine modes ----
local STATE_PLAYING          = "playing"
local STATE_PAUSED           = "paused"
local STATE_LEVEL_COMPLETE   = "level_complete"
local STATE_GAME_OVER_REVEAL = "game_over_reveal"
local STATE_GAME_OVER        = "game_over"
local STATE_ALL_DONE         = "all_done"

-- ---- Tunables -------------------------------------------------------------
local DIFF_COUNT             = LEVELS.diff_count
local MISS_FLASH_DURATION    = 0.4
local MISS_FLASH_MAX_ALPHA   = 0.5
local ELLIPSE_DRAW_DURATION  = 0.4
local REVEAL_STAGGER         = 0.25  -- delay between consecutive red ellipses
local REVEAL_DWELL           = 0.8   -- pause after the last reveal before GAME_OVER text
local LOW_TIME_THRESHOLD     = 10.0  -- seconds at which the timebar starts pulsing
local LOW_TIME_CYCLE         = 2.0   -- one fade cycle (1.0 → 0.2 → 1.0) takes this long
local FIND_POINTS            = 100   -- per-diff bonus on find (click or joker)
local SCORE_COUNT_DURATION   = 1.5   -- level-end bonus count-up
local SCORE_POPUP_DURATION   = 0.9   -- "+N" float-and-fade
local SCORE_POPUP_RISE       = 30    -- virtual px the "+N" floats upward

-- ---- State ----------------------------------------------------------------
local state = {
    level        = 1,
    level_count  = LEVELS.level_count,
    score        = 0,
    jokers       = LEVELS.joker_max,
    joker_max    = LEVELS.joker_max,
    time_total   = LEVELS.time_start,   -- set per-level by startLevel()
    time_left    = LEVELS.time_start,
    diffs        = current_diffs,
    found        = {},
    miss_flash   = 0,
    mode         = STATE_PLAYING,
    reveal_t     = 0,                   -- secs in GAME_OVER_REVEAL
    score_popups = {},                  -- floating "+N" texts: { x, y, value, t }
    score_anim   = nil,                 -- level-end count-up: { from, to, t }
}

-- ---- Layout (virtual canvas: UI_VIRTUAL_H = 480, center origin, Y-down) ----
local HUD_Y       = -224
local PAUSE_BTN_X =  272
local PAUSE_BTN_Y = -232
local JOKER_BTN_X = -21
local JOKER_BTN_Y =  192
local STAR_X      = -20
local STAR_SIZE   =  40
local BAR_X       = -133
local BAR_Y       = -224
local IMG_Y       = -183
local IMG_LEFT_X  = -314
local IMG_RIGHT_X =  27

local TOP_NUMBERS_Y      = -220
local TOP_LABELS_Y       = -236
local TOP_SLASH_LABELS_Y = -211

local LEVEL_X = -280
local FOUND_X = -190
local SCORE_X =  205
local JOKER_X =  0
local JOKER_Y =  138

local SMALL_LABEL_COLOR = { 0.75, 0.75, 0.75 }
local CURRENT_COLOR     = { 1.0,  1.0,  1.0  }
local TOTAL_COLOR       = { 0.7,  0.8,  0.9  }
local SCORE_COLOR       = { 1.0,  1.0,  0.0  }

local PORTRAIT_W = 285
local PORTRAIT_H = 415

-- ---- Helpers --------------------------------------------------------------

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px < rx + rw and py >= ry and py < ry + rh
end

local function isFound(d)
    for _, f in ipairs(state.found) do
        if f.x == d.x and f.y == d.y and f.w == d.w and f.h == d.h then
            return true
        end
    end
    return false
end

-- Returns (lx, ly, base_x) where lx/ly are portrait-local px and base_x
-- is the canvas x of the clicked portrait's top-left (so popups can be
-- placed on the actual side the player clicked).
local function clickToPortraitLocal(x, y)
    local left_x  = IMG_LEFT_X  + 1
    local right_x = IMG_RIGHT_X + 1
    local top_y   = IMG_Y       + 1
    if y < top_y or y >= top_y + PORTRAIT_H then return nil end
    if x >= left_x  and x < left_x  + PORTRAIT_W then
        return x - left_x,  y - top_y, left_x
    end
    if x >= right_x and x < right_x + PORTRAIT_W then
        return x - right_x, y - top_y, right_x
    end
    return nil
end

local function firstUnfound()
    for _, d in ipairs(state.diffs) do
        if not isFound(d) then return d end
    end
    return nil
end

local function unfoundCount()
    return DIFF_COUNT - #state.found
end

-- Time budget for level `n` lerped linearly from LEVELS.time_start at level 1
-- to LEVELS.time_end at level_count. Single-level runs just use time_start.
local function levelTimeBudget(n)
    if LEVELS.level_count <= 1 then return LEVELS.time_start end
    local f = (n - 1) / (LEVELS.level_count - 1)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return LEVELS.time_start + (LEVELS.time_end - LEVELS.time_start) * f
end

-- Per-level reset. Doesn't touch state.score or state.jokers — both
-- persist across levels for the whole session. Jokers reset only on
-- newRun().
local function startLevel(n)
    state.level        = n
    state.time_total   = levelTimeBudget(n)
    state.time_left    = state.time_total
    state.found        = {}
    state.miss_flash   = 0
    state.reveal_t     = 0
    state.score_popups = {}
    state.score_anim   = nil
    state.mode         = STATE_PLAYING
end

local function settleScoreAnim()
    if state.score_anim then
        state.score = state.score_anim.to
        state.score_anim = nil
    end
end

-- Forward-declared so enterAllDone / enterGameOver can capture it as
-- an upvalue for their Retry / Play-again button actions. The body
-- comes further down; everything in between can refer to it.
local newRun

-- Forward decls for the symbols the HUD widgets' on_click closures
-- need. The actual function bodies are assigned further down (after
-- the helpers they each use are defined).
local enterPaused, joker_action

local function enterAllDone()
    state.mode = STATE_ALL_DONE
    -- Session-end joker bonus: 50 per unused joker. Per-level was wrong
    -- once jokers became persistent — same jokers would have been counted
    -- every level. Awarded once, here. The dialog body renders the count-up
    -- via state.score_anim once intro_done.
    local joker_bonus = state.jokers * 50
    state.joker_bonus = joker_bonus     -- snapshot for the dialog body
    if joker_bonus > 0 then
        state.score_anim = {
            from = state.score, to = state.score + joker_bonus, t = 0,
        }
    end

    dialog.show({
        title = "RUN COMPLETE!",
        buttons = {
            {
                x = 0, y = 110, w = 240, h = 56,
                region = "button_blue_up",
                label  = "Play again",
                action = newRun,
            },
        },
        draw_body = function(intro_done, t, ax, ay)
            if not intro_done then return end
            draw_text(string.format("Joker bonus:  %d", state.joker_bonus or 0),
                      ax, ay - 30, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                color = { 1.0, 0.95, 0.5 },
            })
            draw_text(string.format("Final score:  %d", state.score),
                      ax, ay + 30, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                font  = "large",
                color = { 1.0, 0.95, 0.2 },
            })
        end,
    })
end

local function enterGameOver()
    state.mode = STATE_GAME_OVER

    dialog.show({
        title = "GAME OVER",
        buttons = {
            {
                x = 0, y = 110, w = 240, h = 56,
                region = "button_blue_up",
                label  = "Retry",
                action = newRun,
            },
        },
        draw_body = function(intro_done, t, ax, ay)
            if not intro_done then return end
            draw_text(string.format("Score:  %d", state.score),
                      ax, ay, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                font  = "large",
                color = { 1.0, 0.95, 0.2 },
            })
        end,
    })
end

-- Continue past LEVEL_COMPLETE. Wraps to STATE_ALL_DONE after the final
-- level; otherwise advances and resets.
local function continueToNextLevel()
    settleScoreAnim()
    if state.level >= LEVELS.level_count then
        enterAllDone()
    else
        startLevel(state.level + 1)
    end
end

-- Reset back to level 1 fresh. Used by GAME_OVER → retry and ALL_DONE → play
-- again. Wipes score AND jokers (the session ended).
newRun = function()
    state.score  = 0
    state.jokers = state.joker_max
    startLevel(1)
end

local function enterLevelComplete()
    state.mode = STATE_LEVEL_COMPLETE
    -- Only time bonus per level; joker bonus is held until session end
    -- (see enterAllDone). Avoids paying out unused jokers every level.
    local time_bonus = math.floor(state.time_left * 10)
    state.time_bonus = time_bonus    -- snapshot for the dialog body
    state.score_anim = {
        from = state.score, to = state.score + time_bonus, t = 0,
    }

    dialog.show({
        title = "COMPLETED!",
        buttons = {
            {
                x = 0, y = 110, w = 240, h = 56,
                region = "button_blue_up",
                label  = "Next level >",
                action = continueToNextLevel,
            },
        },
        draw_body = function(intro_done, t, ax, ay)
            -- Score breakdown. Hidden until the dialog settles so the
            -- bouncing entrance reads as a unit; once settled the score
            -- counts up via the existing state.score_anim.
            if not intro_done then return end
            draw_text(string.format("Time bonus:  %d", state.time_bonus or 0),
                      ax, ay - 30, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                color = { 1.0, 0.95, 0.5 },
            })
            draw_text(string.format("Total:  %d", state.score),
                      ax, ay + 30, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                font  = "large",
                color = { 1.0, 0.95, 0.2 },
            })
        end,
    })
end

local function enterGameOverReveal()
    state.mode     = STATE_GAME_OVER_REVEAL
    state.reveal_t = 0
end

local function resumePlaying() state.mode = STATE_PLAYING end

-- Assigning to the forward-declared upvalue (NOT `local function`) so
-- the HUD widgets' on_click closure resolves to this body.
enterPaused = function()
    state.mode = STATE_PAUSED
    dialog.show({
        title = "PAUSED",
        buttons = {
            {
                x = 0, y = 110, w = 240, h = 56,
                region = "button_blue_up",
                label  = "Resume",
                action = resumePlaying,
            },
        },
    })
end

-- Add a "+N" floating text at canvas (x, y) tied to the next on_render.
local function pushScorePopup(x, y, value)
    table.insert(state.score_popups, { x = x, y = y, value = value, t = 0 })
end

-- Common path for both player-click finds and joker reveals. Pushes the
-- ellipse animation, awards FIND_POINTS, and (for player finds only)
-- spawns the "+N" popup at the actual click position on the side the
-- player clicked. Joker reveals get no popup since FIND_POINTS feels
-- like a reward for *finding*, not for spending a joker.
-- click_lx/ly are portrait-local px; base_x is the canvas x of the
-- clicked portrait's top-left. All three are nil for joker reveals.
local function awardFind(d, by_joker, click_lx, click_ly, base_x)
    table.insert(state.found, {
        x = d.x, y = d.y, w = d.w, h = d.h,
        joker = by_joker, t = 0,
    })
    if not by_joker then
        state.score = state.score + FIND_POINTS
        pushScorePopup(base_x + click_lx, IMG_Y + 1 + click_ly, FIND_POINTS)
    end
end

-- Joker button on_click: if any jokers are left, reveal the next
-- unfound diff. The press flash comes for free from widget.button's
-- mousedown/mouseup cycle — no timer needed.
joker_action = function()
    if state.jokers > 0 then
        local d = firstUnfound()
        if d then
            awardFind(d, true)
            state.jokers = state.jokers - 1
        end
    else
        snd_play("wrong")
    end
end

-- ---- HUD widget tree ------------------------------------------------------
--
-- Static UI lives in a root panel so it participates in scene
-- transitions (a fade/slide on root cascades through every child). The
-- highly-dynamic stuff (blur backdrop, find / reveal ellipses, score
-- popups, miss flash, dialog) stays in custom render — its state
-- changes every tick and doesn't map onto stable widget fields.

local widget = require "engine.widget"

local root = widget.panel({ x = 0, y = 0 })

-- Layer 1: portrait frames + portraits. Painted first; the dynamic
-- ellipses / popups / overlays paint on top in game_render.
root:add(widget.image{ x = IMG_LEFT_X,      y = IMG_Y,     region = "image_bg" })
root:add(widget.image{ x = IMG_LEFT_X + 1,  y = IMG_Y + 1, region = "image_1a" })
root:add(widget.image{ x = IMG_RIGHT_X,     y = IMG_Y,     region = "image_bg" })
root:add(widget.image{ x = IMG_RIGHT_X + 1, y = IMG_Y + 1, region = "image_1b" })

-- Layer 2: timebar. The fg's fill_x and alpha get rewritten each
-- frame by sync_hud — fill from time_left, alpha pulses on low time.
root:add(widget.image{ x = BAR_X, y = BAR_Y, region = "timebar_bg" })
local timebar_fg = widget.image{
    x = BAR_X + 1, y = BAR_Y + 1, region = "timebar",
}
root:add(timebar_fg)

-- Layer 3: stars. Region of each is swapped between "star" and
-- "star_empty" in sync_hud based on how many diffs have been found.
local star_widgets = {}
for i = 1, DIFF_COUNT do
    star_widgets[i] = widget.image{
        x = STAR_X, y = IMG_Y + (STAR_SIZE + 8) * (i - 1),
        region = "star_empty",
    }
    root:add(star_widgets[i])
end

-- Layer 4: HUD text. Width 0 + align CENTER+TOP reproduces the
-- original "draw text centred on this point" semantics — anchor_in
-- on a zero-size bbox lands at (x, y) regardless of horizontal align.
local function add_text(x, y, text, opts)
    opts = opts or {}
    local lbl = widget.label{
        x = x, y = y, width = 0, height = 0,
        text = text,
        align = opts.align or (ALIGN_CENTER + ALIGN_TOP),
        font  = opts.font,
        color = opts.color or SMALL_LABEL_COLOR,
    }
    root:add(lbl)
    return lbl
end

-- LEVEL column — current / total with "/" between.
add_text(LEVEL_X,      TOP_LABELS_Y,       "LEVEL")
local level_current = add_text(LEVEL_X - 20, TOP_NUMBERS_Y, "1",
                               { font = "large", color = CURRENT_COLOR })
local level_total   = add_text(LEVEL_X + 20, TOP_NUMBERS_Y, "1",
                               { font = "large", color = TOTAL_COLOR })
add_text(LEVEL_X,      TOP_SLASH_LABELS_Y, "/")

-- FOUND column — current / DIFF_COUNT (total is static).
add_text(FOUND_X,      TOP_LABELS_Y,       "FOUND")
local found_current = add_text(FOUND_X - 20, TOP_NUMBERS_Y, "0",
                               { font = "large", color = CURRENT_COLOR })
add_text(FOUND_X + 20, TOP_NUMBERS_Y,      tostring(DIFF_COUNT),
         { font = "large", color = TOTAL_COLOR })
add_text(FOUND_X,      TOP_SLASH_LABELS_Y, "/")

-- SCORE column — single number, no /total.
add_text(SCORE_X, TOP_LABELS_Y,  "SCORE")
local score_label  = add_text(SCORE_X, TOP_NUMBERS_Y, "0",
                              { font = "large", color = SCORE_COLOR })

-- JOKER badge (label above the count, count above the button).
add_text(JOKER_X, JOKER_Y,      "JOKER")
local joker_count  = add_text(JOKER_X, JOKER_Y + 16, "0",
                              { font = "large", color = CURRENT_COLOR })

-- Layer 5: buttons. pause (top-right) and joker (center-bottom). Both
-- use bg_up / bg_down regions; the 9-patch fallback degrades to a
-- stretched single draw_region when the region has no slice, so at
-- native size (42x42) they paint pixel-identical to the old direct
-- draw_region calls.
local pause_button = widget.button{
    x = PAUSE_BTN_X, y = PAUSE_BTN_Y, width = 42, height = 42,
    bg_up = "pause_button_up", bg_down = "pause_button_down",
    on_click = function() enterPaused() end,
}
-- HUD buttons are mouse-only. Mark non-focusable BEFORE :add so the
-- panel's auto-focus walk skips them — otherwise pressing Enter or
-- Space during gameplay would fire pause / joker via dispatch_keydown.
pause_button.focusable = false
root:add(pause_button)

local joker_button = widget.button{
    x = JOKER_BTN_X, y = JOKER_BTN_Y, width = 42, height = 42,
    bg_up = "joker_button_up", bg_down = "joker_button_down",
    on_click = function() joker_action() end,
}
joker_button.focusable = false
root:add(joker_button)

-- Per-frame: pull labels / regions / fills / alphas from game state.
local function sync_hud()
    level_current.text = tostring(state.level)
    level_total.text   = tostring(state.level_count)
    found_current.text = tostring(#state.found)
    score_label.text   = tostring(state.score)
    joker_count.text   = tostring(state.jokers)

    for i = 1, DIFF_COUNT do
        star_widgets[i].region = (i <= #state.found) and "star" or "star_empty"
    end

    timebar_fg.fill_x = state.time_left / state.time_total

    -- Last-10s warning: cosine alpha pulse, 5 cycles over the final 10s.
    -- Only pulses while PLAYING — pause/game-over freeze it.
    local bar_alpha = 1.0
    if state.mode == STATE_PLAYING and state.time_left <= LOW_TIME_THRESHOLD then
        local phase = (LOW_TIME_THRESHOLD - state.time_left) / LOW_TIME_CYCLE
        bar_alpha = 0.6 + 0.4 * math.cos(2 * math.pi * phase)
    end
    timebar_fg.alpha = bar_alpha
end

-- ---- Hooks ----------------------------------------------------------------
--
-- Hooks are routed through engine.scene. The menu scene is the first
-- thing pushed; clicking its "Start game" button calls
-- find5_start_game(), which replaces the menu with the game_scene
-- defined at the bottom of this file.

local function game_update(dt)
    -- Dialog animations must always run — they own the intro/outro
    -- timing, including the deferred button action.
    dialog.update(dt)

    -- Pause freezes everything: timer, animations, the lot. State just
    -- sits at whatever it was when the player hit the pause button.
    if state.mode == STATE_PAUSED then return end

    -- Animations always tick — the last find ellipse should finish drawing
    -- even after we transition to LEVEL_COMPLETE.
    for _, f in ipairs(state.found) do
        if f.t < ELLIPSE_DRAW_DURATION then
            f.t = f.t + dt
            if f.t > ELLIPSE_DRAW_DURATION then f.t = ELLIPSE_DRAW_DURATION end
        end
    end
    if state.miss_flash > 0 then
        state.miss_flash = state.miss_flash - dt
        if state.miss_flash < 0 then state.miss_flash = 0 end
    end

    -- Score count-up animation (set by enterLevelComplete). Updates the
    -- displayed state.score; settles to .to once the duration elapses.
    if state.score_anim then
        state.score_anim.t = state.score_anim.t + dt
        if state.score_anim.t >= SCORE_COUNT_DURATION then
            state.score = state.score_anim.to
            state.score_anim = nil
        else
            local f = state.score_anim.t / SCORE_COUNT_DURATION
            state.score = math.floor(state.score_anim.from
                                  + (state.score_anim.to - state.score_anim.from) * f)
        end
    end

    -- "+N" floating popups: walk in reverse so removal-by-index is safe.
    for i = #state.score_popups, 1, -1 do
        local p = state.score_popups[i]
        p.t = p.t + dt
        if p.t > SCORE_POPUP_DURATION then
            table.remove(state.score_popups, i)
        end
    end

    if state.mode == STATE_PLAYING then
        if state.time_left > 0 then
            state.time_left = state.time_left - dt
            if state.time_left < 0 then state.time_left = 0 end
        end
        if #state.found >= DIFF_COUNT then
            enterLevelComplete()
        elseif state.time_left <= 0 then
            enterGameOverReveal()
        end

    elseif state.mode == STATE_GAME_OVER_REVEAL then
        state.reveal_t = state.reveal_t + dt
        local n = unfoundCount()
        -- Reveal i starts at i*STAGGER (0-indexed), runs for DURATION,
        -- then we hold for DWELL before opening the GAME_OVER dialog.
        local need = (n > 0)
                     and ((n - 1) * REVEAL_STAGGER + ELLIPSE_DRAW_DURATION + REVEAL_DWELL)
                     or  REVEAL_DWELL
        if state.reveal_t >= need then
            enterGameOver()
        end
    end

    -- Push the latest game state into the HUD widgets so they render
    -- with up-to-date text / colors / fills / press flags this frame.
    sync_hud()
end

local function game_mousedown(x, y, button)
    if button ~= 1 then return end

    -- An active dialog owns clicks entirely — its button hit-tests run
    -- inside handle_click, and misses are swallowed (no fall-through
    -- to game logic underneath the modal). PAUSE / LEVEL_COMPLETE /
    -- GAME_OVER / ALL_DONE all route through here.
    if dialog.is_active() then
        dialog.handle_click(x, y)
        return
    end

    if state.mode ~= STATE_PLAYING then return end  -- game_over_reveal: input locked

    -- Forward to the HUD panel — pause / joker buttons own their own
    -- hit-tests and fire on_click on mouseup. Pause and joker bbox
    -- live entirely outside the portrait area, so a click that lands
    -- on a button never falls through to a portrait hit-test below.
    root:mousedown(x, y, button)

    local lx, ly, base_x = clickToPortraitLocal(x, y)
    if not lx then return end

    for _, d in ipairs(state.diffs) do
        if not isFound(d) and pointInRect(lx, ly, d.x, d.y, d.w, d.h) then
            awardFind(d, false, lx, ly, base_x)
            return
        end
    end
    -- Miss — click was on a portrait but no unfound diff matched.
    state.miss_flash = MISS_FLASH_DURATION
    state.time_left  = state.time_left - state.time_total / 4
    if state.time_left < 0 then state.time_left = 0 end
    -- snd_play("wrong")
end

-- ---- Render ---------------------------------------------------------------

local function game_render()
    -- ---- Backdrop: blurred color summary of the left portrait. ----
    -- Multiply by root.alpha so the blur fades in / out with the rest
    -- of the scene during a transition — otherwise it pops in at full
    -- opacity while the HUD widgets are still fading.
    draw_blur("image_1a", { width = 16, alpha = 0.6 * root.alpha })

    -- HUD panel — portrait frames + portraits, timebar, stars, text
    -- labels, pause + joker buttons. Sync_hud (called at end of
    -- game_update) refreshes labels / regions / fills / press flags
    -- from game state. Paints before the dynamic overlays below so
    -- ellipses and popups land on top of the portraits.
    root:draw()

    -- ---- Found markers (green / yellow ellipses, mirrored) ----
    local green  = { 0.3, 1.0, 0.4, 1.0 }
    local yellow = { 1.0, 1.0, 0.0, 1.0 }
    local red    = { 1.0, 0.3, 0.3, 1.0 }
    for _, p in ipairs(state.found) do
        local finish = p.t / ELLIPSE_DRAW_DURATION
        if finish > 1 then finish = 1 end
        local color  = p.joker and yellow or green
        draw_ellipse(IMG_LEFT_X + p.x + p.w/2, IMG_Y + p.y + p.h/2, p.w/2, p.h/2, {
            finish = finish, thickness = 3, color = color,
        })
        draw_ellipse(IMG_RIGHT_X + p.x + p.w/2, IMG_Y + p.y + p.h/2, p.w/2, p.h/2, {
            finish = finish, thickness = 3, color = color,
        })
    end

    -- ---- Floating "+N" score popups (one per find) ----
    for _, p in ipairs(state.score_popups) do
        local f = p.t / SCORE_POPUP_DURATION
        if f > 1 then f = 1 end
        local alpha = 1 - f
        local dy    = -SCORE_POPUP_RISE * f
        draw_text(string.format("+%d", p.value), p.x, p.y + dy, {
	      align = ALIGN_CENTER + ALIGN_MIDDLE,
	      color = { 0.4, 1.0, 0.5, alpha }
	    })
    end

    -- ---- Game-over reveal: red ellipses on unfound diffs, staggered ----
    if state.mode == STATE_GAME_OVER_REVEAL or state.mode == STATE_GAME_OVER then
        local i = 0
        for _, d in ipairs(state.diffs) do
            if not isFound(d) then
                local elapsed = state.reveal_t - i * REVEAL_STAGGER
                if elapsed > 0 then
                    local finish = elapsed / ELLIPSE_DRAW_DURATION
                    if finish > 1 then finish = 1 end
                    draw_ellipse(IMG_LEFT_X + d.x + d.w/2, IMG_Y + d.y + d.h/2, d.w/2, d.h/2, {
                        finish = finish, thickness = 3, color = red,
                    })
                    draw_ellipse(IMG_RIGHT_X + d.x + d.w/2, IMG_Y + d.y + d.h/2, d.w/2, d.h/2, {
                        finish = finish, thickness = 3, color = red,
                    })
                end
                i = i + 1
            end
        end
    end

    -- ---- Miss-click red overlay ----
    if state.miss_flash > 0 then
        local alpha = MISS_FLASH_MAX_ALPHA
                    * (state.miss_flash / MISS_FLASH_DURATION)
        local vw, vh = view_size()
        draw_quad(-vw / 2, -vh / 2, vw, vh, {
            color = { 1.0, 0.0, 0.0, alpha },
        })
    end

    -- Dialog renders last so it sits above everything (HUD, portraits,
    -- diff ellipses). All terminal states are dialogs now.
    dialog.render()
end

-- ---- Scene wrapper --------------------------------------------------------
-- The game runs as one scene; the title screen runs as another. Bodies
-- of game_update / game_mousedown / game_render are unchanged from when
-- they were top-level on_* hooks — only the dispatch path changed.

local game_scene = { root = root }

function game_scene:enter()
    -- The current_pair / current_diffs / state table at the top of this
    -- file are already initialised to level-1 fresh, so nothing extra to
    -- do for the first run. A "play again" path through enterAllDone /
    -- enterGameOver re-uses newRun() which already resets everything.
end

function game_scene:update(dt)     game_update(dt)         end
function game_scene:mousedown(x, y, b) game_mousedown(x, y, b) end
function game_scene:render()        game_render()           end

-- Menu hands off to the game by calling this global. category arg is the
-- entry from levels.lua's `categories` array; not used yet (the engine
-- still plays the single hard-coded portrait pair) but the plumbing is
-- in place for when image selection lands.
function _G.find5_start_game(category)
    scene.replace(game_scene, transition.fade(0.4))
end

-- Menu's close button signals quit. SDL has no Lua-side quit binding, so
-- we use a flag the engine polls each frame; the simplest portable shim
-- is to push an SDL_QUIT via a future binding. For the draft we just log.
function _G.find5_request_quit()
    ui_show_message("Press Esc to quit (Lua quit binding: TODO)", 2.0)
end

-- Wire the on_* engine hooks to scene dispatchers. on_start stays
-- custom so we can push the menu on first frame.
scene.install_hooks(_G)

function on_start()
    scene.push(require("menu"))
end
