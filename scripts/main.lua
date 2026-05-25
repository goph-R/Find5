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
local STATE_LEVEL_COMPLETE   = "level_complete"
local STATE_GAME_OVER_REVEAL = "game_over_reveal"
local STATE_GAME_OVER        = "game_over"

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

-- ---- State ----------------------------------------------------------------
local state = {
    level       = 1,
    level_count = LEVELS.level_count,
    score       = 0,
    jokers      = LEVELS.joker_max,
    joker_max   = LEVELS.joker_max,
    time_total  = LEVELS.time_start,
    time_left   = LEVELS.time_start,
    diffs       = current_diffs,
    found       = {},
    miss_flash  = 0,
    joker_press = 0,
    mode        = STATE_PLAYING,
    reveal_t    = 0,    -- secs elapsed since entering GAME_OVER_REVEAL
    win_t       = 0,    -- secs elapsed since entering LEVEL_COMPLETE
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

local function clickToPortraitLocal(x, y)
    local left_x  = IMG_LEFT_X  + 1
    local right_x = IMG_RIGHT_X + 1
    local top_y   = IMG_Y       + 1
    if y < top_y or y >= top_y + PORTRAIT_H then return nil end
    if x >= left_x  and x < left_x  + PORTRAIT_W then
        return x - left_x,  y - top_y
    end
    if x >= right_x and x < right_x + PORTRAIT_W then
        return x - right_x, y - top_y
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

local function resetLevel()
    state.found       = {}
    state.time_left   = state.time_total
    state.jokers      = state.joker_max
    state.miss_flash  = 0
    state.joker_press = 0
    state.reveal_t    = 0
    state.win_t       = 0
    state.mode        = STATE_PLAYING
end

local function enterLevelComplete()
    state.mode  = STATE_LEVEL_COMPLETE
    state.win_t = 0
end

local function enterGameOverReveal()
    state.mode     = STATE_GAME_OVER_REVEAL
    state.reveal_t = 0
end

-- ---- Hooks ----------------------------------------------------------------

function on_start()
    -- music_play("title", 0.5, true)
end

function on_update(dt)
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

    -- Terminal states swallow clicks to restart, no other action runs.
    if state.mode == STATE_LEVEL_COMPLETE then
        if state.win_t >= POST_WIN_DELAY then resetLevel() end
        return
    end
    if state.mode == STATE_GAME_OVER then
        resetLevel()
        return
    end
    if state.mode ~= STATE_PLAYING then return end  -- game_over_reveal: input locked

    -- Joker button — tested first so a button click never falls through
    -- to portrait hit-testing. Press flash registers regardless.
    if pointInRect(x, y, JOKER_BTN_X, JOKER_BTN_Y, 42, 42) then
        state.joker_press = JOKER_PRESS_DURATION
        if state.jokers > 0 then
            local d = firstUnfound()
            if d then
                table.insert(state.found, {
                    x = d.x, y = d.y, w = d.w, h = d.h,
                    joker = true, t = 0,
                })
                state.jokers = state.jokers - 1
            end
        else
            snd_play("wrong")
        end
        return
    end

    local lx, ly = clickToPortraitLocal(x, y)
    if not lx then return end

    for _, d in ipairs(state.diffs) do
        if not isFound(d) and pointInRect(lx, ly, d.x, d.y, d.w, d.h) then
            table.insert(state.found, {
                x = d.x, y = d.y, w = d.w, h = d.h,
                joker = false, t = 0,
            })
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
    if state.mode == STATE_LEVEL_COMPLETE or state.mode == STATE_GAME_OVER then
        local vw, vh = view_size()
        draw_quad(-vw / 2, -vh / 2, vw, vh, {
            color = { 0, 0, 0, 0.6 },
        })

        local title, hint
        if state.mode == STATE_LEVEL_COMPLETE then
            title = "LEVEL COMPLETE!"
            if state.win_t >= POST_WIN_DELAY then hint = "click to continue" end
        else
            title = "GAME OVER"
            hint = "click to retry"
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
