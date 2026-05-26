-- Find5 — main game loop.
-- One level plays end-to-end now: pick the diffs from levels.lua, run a
-- timer, accept clicks / jokers, and resolve into LEVEL_COMPLETE or
-- GAME_OVER (with a staggered red-ellipse reveal of the missed diffs).
-- Clicking in either terminal state restarts the level.

local LEVELS = require "levels"

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
local JOKER_PRESS_DURATION   = 0.1
local REVEAL_STAGGER         = 0.25  -- delay between consecutive red ellipses
local REVEAL_DWELL           = 0.8   -- pause after the last reveal before GAME_OVER text
local POST_WIN_DELAY         = 0.5   -- swallow the click that triggered LEVEL_COMPLETE
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
    joker_press  = 0,
    mode         = STATE_PLAYING,
    reveal_t     = 0,                   -- secs in GAME_OVER_REVEAL
    win_t        = 0,                   -- secs in LEVEL_COMPLETE
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
    state.joker_press  = 0
    state.reveal_t     = 0
    state.win_t        = 0
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

local function enterAllDone()
    state.mode = STATE_ALL_DONE
    -- Session-end joker bonus: 50 per unused joker. Per-level was wrong
    -- once jokers became persistent — same jokers would have been counted
    -- every level. Awarded once, here.
    local joker_bonus = state.jokers * 50
    if joker_bonus > 0 then
        state.score_anim = {
            from = state.score, to = state.score + joker_bonus, t = 0,
        }
    end
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
local function newRun()
    state.score  = 0
    state.jokers = state.joker_max
    startLevel(1)
end

local function enterLevelComplete()
    state.mode  = STATE_LEVEL_COMPLETE
    state.win_t = 0
    -- Only time bonus per level; joker bonus is held until session end
    -- (see enterAllDone). Avoids paying out unused jokers every level.
    local time_bonus = math.floor(state.time_left * 10)
    state.score_anim = {
        from = state.score, to = state.score + time_bonus, t = 0,
    }
end

local function enterGameOverReveal()
    state.mode     = STATE_GAME_OVER_REVEAL
    state.reveal_t = 0
end

local function enterPaused()   state.mode = STATE_PAUSED  end
local function resumePlaying() state.mode = STATE_PLAYING end

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

-- ---- Hooks ----------------------------------------------------------------

function on_start()
    -- music_play("title", 0.5, true)
end

function on_update(dt)
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
    if state.joker_press > 0 then
        state.joker_press = state.joker_press - dt
        if state.joker_press < 0 then state.joker_press = 0 end
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

    elseif state.mode == STATE_LEVEL_COMPLETE then
        state.win_t = state.win_t + dt

    elseif state.mode == STATE_GAME_OVER_REVEAL then
        state.reveal_t = state.reveal_t + dt
        local n = unfoundCount()
        -- Reveal i starts at i*STAGGER (0-indexed), runs for DURATION,
        -- then we hold for DWELL before showing the GAME_OVER text.
        local need = (n > 0)
                     and ((n - 1) * REVEAL_STAGGER + ELLIPSE_DRAW_DURATION + REVEAL_DWELL)
                     or  REVEAL_DWELL
        if state.reveal_t >= need then
            state.mode = STATE_GAME_OVER
        end
    end
end

function on_mousedown(x, y, button)
    if button ~= 1 then return end

    -- Paused: any click resumes the game, nothing else fires.
    if state.mode == STATE_PAUSED then
        resumePlaying()
        return
    end

    -- Terminal states swallow clicks. LEVEL_COMPLETE advances to the next
    -- level (or to ALL_DONE after the final one); GAME_OVER and ALL_DONE
    -- restart the run from level 1 with score = 0.
    if state.mode == STATE_LEVEL_COMPLETE then
        if state.win_t >= POST_WIN_DELAY then continueToNextLevel() end
        return
    end
    if state.mode == STATE_GAME_OVER or state.mode == STATE_ALL_DONE then
        newRun()
        return
    end
    if state.mode ~= STATE_PLAYING then return end  -- game_over_reveal: input locked

    -- Pause button — top-right, 42×42 at (PAUSE_BTN_X, PAUSE_BTN_Y). Tested
    -- before everything else in PLAYING so it can't double as a missclick.
    if pointInRect(x, y, PAUSE_BTN_X, PAUSE_BTN_Y, 42, 42) then
        enterPaused()
        return
    end

    -- Joker button — tested first so a button click never falls through
    -- to portrait hit-testing. Press flash registers regardless.
    if pointInRect(x, y, JOKER_BTN_X, JOKER_BTN_Y, 42, 42) then
        state.joker_press = JOKER_PRESS_DURATION
        if state.jokers > 0 then
            local d = firstUnfound()
            if d then
                awardFind(d, true)
                state.jokers = state.jokers - 1
            end
        else
            snd_play("wrong")
        end
        return
    end

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

function on_render()
    -- ---- Backdrop: blurred color summary of the left portrait. ----
    draw_blur("image_1a", { width = 16, alpha = 0.6 })

    -- ---- HUD top row ----
    draw_text("LEVEL", LEVEL_X, TOP_LABELS_Y, {
	  align = ALIGN_CENTER,
	  color = SMALL_LABEL_COLOR
	})
    draw_text(string.format("%d", state.level), LEVEL_X - 20, TOP_NUMBERS_Y, {
	  align = ALIGN_CENTER,
	  font = "large",
	  color = CURRENT_COLOR
	})
    draw_text(string.format("%d", state.level_count), LEVEL_X + 20, TOP_NUMBERS_Y, {
	  align = ALIGN_CENTER,
	  font = "large",
	  color = TOTAL_COLOR
	})
    draw_text("/", LEVEL_X, TOP_SLASH_LABELS_Y, {
	  align = ALIGN_CENTER,
	  color = SMALL_LABEL_COLOR
	})

    draw_text("FOUND", FOUND_X, TOP_LABELS_Y, {
	  align = ALIGN_CENTER,
	  color = SMALL_LABEL_COLOR
	})
    draw_text(string.format("%d", table.getn(state.found)), FOUND_X - 20, TOP_NUMBERS_Y, {
	  align = ALIGN_CENTER,
	  font = "large",
	  color = CURRENT_COLOR
	})
    draw_text(string.format("%d", DIFF_COUNT), FOUND_X + 20, TOP_NUMBERS_Y, {
	  align = ALIGN_CENTER,
	  font = "large",
	  color = TOTAL_COLOR
	})
    draw_text("/", FOUND_X, TOP_SLASH_LABELS_Y, {
	  align = ALIGN_CENTER,
	  color = SMALL_LABEL_COLOR
	})

    draw_text("SCORE", SCORE_X, TOP_LABELS_Y, {
	  align = ALIGN_CENTER,
	  color = SMALL_LABEL_COLOR
	})
    draw_text(string.format("%d", state.score), SCORE_X, TOP_NUMBERS_Y, {
	  align = ALIGN_CENTER,
	  font = "large",
	  color = SCORE_COLOR
	})

    draw_text("JOKER", JOKER_X, JOKER_Y, {
	  align = ALIGN_CENTER,
	  color = SMALL_LABEL_COLOR
	})
    draw_text(string.format("%d", state.jokers), JOKER_X, JOKER_Y + 16, {
	  align = ALIGN_CENTER,
	  font = "large",
	  color = CURRENT_COLOR
	})

    -- Pause button — top-right corner.
    draw_region("pause_button_up", PAUSE_BTN_X, PAUSE_BTN_Y)

    -- Joker button — center-bottom. Press flash swaps to the "_down" art
    -- briefly after each click; otherwise the "_up" art sits idle.
    local joker_btn = (state.joker_press > 0) and "joker_button_down"
                                              or  "joker_button_up"
    draw_region(joker_btn, JOKER_BTN_X, JOKER_BTN_Y)

    -- ---- Timer bar ----
    -- Last-10s warning: foreground alpha pulses 1.0 → 0.2 → 1.0 once per
    -- LOW_TIME_CYCLE seconds (5 cycles over the final 10s). Cosine gives
    -- a smoother shape than a triangle wave. Stops when not in PLAYING.
    local bar_alpha = 1.0
    if state.mode == STATE_PLAYING and state.time_left <= LOW_TIME_THRESHOLD then
        local phase = (LOW_TIME_THRESHOLD - state.time_left) / LOW_TIME_CYCLE
        bar_alpha = 0.6 + 0.4 * math.cos(2 * math.pi * phase)
    end
    draw_region("timebar_bg", BAR_X, BAR_Y)
    draw_region("timebar", BAR_X + 1, BAR_Y + 1, {
        fill_x = state.time_left / state.time_total,
        alpha  = bar_alpha,
    })

    -- ---- Stars ----
    for i = 1, DIFF_COUNT do
        local kind = (i <= #state.found) and "star" or "star_empty"
        draw_region(kind, STAR_X, IMG_Y + (STAR_SIZE + 8) * (i - 1))
    end

    -- ---- Portraits with frame ----
    draw_region("image_bg", IMG_LEFT_X, IMG_Y)
    draw_region("image_1a", IMG_LEFT_X + 1, IMG_Y + 1)
    draw_region("image_bg", IMG_RIGHT_X, IMG_Y)
    draw_region("image_1b", IMG_RIGHT_X + 1, IMG_Y + 1)

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

    -- ---- Terminal-state overlays ----
    -- Placeholder text until the real dialogs land. Dim the whole view,
    -- then center a title in the large font; show a "click to ..." hint
    -- under it once the input is unlocked.
    if state.mode == STATE_LEVEL_COMPLETE or state.mode == STATE_GAME_OVER
       or state.mode == STATE_PAUSED or state.mode == STATE_ALL_DONE then
        local vw, vh = view_size()
        draw_quad(-vw / 2, -vh / 2, vw, vh, {
            color = { 0, 0, 0, 0.6 },
        })

        local title, hint
        if state.mode == STATE_LEVEL_COMPLETE then
            title = "LEVEL COMPLETE!"
            if state.win_t >= POST_WIN_DELAY then hint = "click to continue" end
        elseif state.mode == STATE_GAME_OVER then
            title = "GAME OVER"
            hint  = "click to retry"
        elseif state.mode == STATE_ALL_DONE then
            title = "RUN COMPLETE!"
            hint  = string.format("Final score: %d  -  click to play again",
                                  state.score)
        else  -- STATE_PAUSED
            title = "PAUSED"
            hint  = "click to resume"
        end

        draw_text(title, 0, -20, {
	      align = ALIGN_CENTER + ALIGN_MIDDLE,
	      font  = "large",
	      color = { 1, 1, 1 }
	    })
        if hint then
            draw_text(hint, 0, 30, {
	          align = ALIGN_CENTER + ALIGN_MIDDLE,
	          color = { 0.85, 0.85, 0.85 }
	        })
        end
    end
end
