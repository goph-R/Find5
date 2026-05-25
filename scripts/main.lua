-- Find5 — game mockup.
-- Static frame matching docs/game-mockup.png: HUD top row (level / joker
-- counter / score / pause), timer bar, two portraits with image_bg
-- frames, and a couple of green "found" markers. No interactivity yet;
-- click around once the gameplay state machine is wired up.

local state = {
    level       = 3,
    level_count = 10,
    score       = 12345,
    jokers      = 3,            -- remaining
    joker_max   = 5,
    time_left   = 35,
    time_total  = 60,
    miss_flash  = 0,            -- seconds of red-overlay fade remaining (0 = idle)
    -- All 5 difference rects for the current portrait pair (image_1a / image_1b).
    -- Coords are portrait-local pixels (top-left origin, image is 285×415).
    -- Same rects apply to both portraits — that's the whole spot-the-difference
    -- premise. Authored with tools/diffs.html.
    diffs = {
        { x =  50, y =  66, w = 42, h = 44 },
        { x = 195, y = 133, w = 27, h = 24 },
        { x = 166, y = 246, w = 36, h = 40 },
        { x =  22, y = 264, w = 32, h = 31 },
        { x =   2, y = 180, w = 57, h = 36 },
    },
    -- Diffs the player has uncovered. Each entry mirrors a row from `diffs`
    -- plus a `joker` flag — false = green (player click), true = yellow
    -- (joker reveal). Two pre-filled here so the mockup shows one of each.
    found = {
        { x =  50, y =  66, w = 42, h = 44, joker = false },
        { x =   2, y = 180, w = 57, h = 36, joker = true  },
    },
}

-- Layout constants — y is down on the virtual canvas (UI_VIRTUAL_H = 480),
-- center origin, so the visible range is roughly -240..+240 vertically.
local HUD_Y       = -224     -- top-row text baseline-ish
local PAUSE_BTN_X =  272     -- pause button X
local PAUSE_BTN_Y = -232     -- pause button Y
local JOKER_BTN_X = -21      -- joker button X
local JOKER_BTN_Y =  192     -- joker button Y
local STAR_X      = -20      -- star icon x
local STAR_SIZE   =  40      -- star icon size
local BAR_X       = -133     -- timebar_bg left edge
local BAR_Y       = -224     -- timebar_bg top edge
local IMG_Y       = -183     -- portrait top y
local IMG_LEFT_X  = -314     -- left portrait top-left x
local IMG_RIGHT_X =  27      -- right portrait top-left x

local TOP_NUMBERS_Y = -220
local TOP_LABELS_Y = -236
local TOP_SLASH_LABELS_Y = -211

local LEVEL_X = -280
local FOUND_X = -190
local SCORE_X =  205
local JOKER_X =  0
local JOKER_Y =  138

local SMALL_LABEL_COLOR    = { 0.75, 0.75, 0.75 } 
local CURRENT_COLOR  = { 1.0, 1.0, 1.0 } 
local TOTAL_COLOR    = { 0.7, 0.8, 0.9 } 
local SCORE_COLOR  = { 1.0, 1.0, 0.0 } 

function on_start()
    -- music_play("title", 0.5, true)
end

local MISS_FLASH_DURATION = 0.4
local MISS_FLASH_MAX_ALPHA = 0.5

function on_update(dt)
    -- Tick the countdown. Clamp at 0 so the timebar's fill_x doesn't
    -- go negative once we run out. Game-over reveal lands in a later
    -- step; for now the bar just empties and stays empty.
    if state.time_left > 0 then
        state.time_left = state.time_left - dt
        if state.time_left < 0 then state.time_left = 0 end
    end
    -- Tick the miss-click red flash down toward 0.
    if state.miss_flash > 0 then
        state.miss_flash = state.miss_flash - dt
        if state.miss_flash < 0 then state.miss_flash = 0 end
    end
end

-- ---- Click handling ------------------------------------------------------

local PORTRAIT_W = 285
local PORTRAIT_H = 415

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px < rx + rw and py >= ry and py < ry + rh
end

-- Has this diff already been uncovered (by click or joker)? Compare on
-- rect identity since state.found rows are copies of state.diffs rows.
local function isFound(d)
    for _, f in ipairs(state.found) do
        if f.x == d.x and f.y == d.y and f.w == d.w and f.h == d.h then
            return true
        end
    end
    return false
end

-- Convert a virtual-canvas click (engine-space, center origin) into
-- portrait-local pixel coords. Returns nil if the click is outside both
-- portrait rects. Either portrait counts — the diff is in the same place
-- on both images, so clicking either side is a valid "I see it".
local function clickToPortraitLocal(x, y)
    -- Portraits are drawn 1px in from their image_bg frames.
    local left_x   = IMG_LEFT_X  + 1
    local right_x  = IMG_RIGHT_X + 1
    local top_y    = IMG_Y       + 1
    if y < top_y or y >= top_y + PORTRAIT_H then return nil end
    if x >= left_x  and x < left_x  + PORTRAIT_W then
        return x - left_x,  y - top_y
    end
    if x >= right_x and x < right_x + PORTRAIT_W then
        return x - right_x, y - top_y
    end
    return nil
end

function on_mousedown(x, y, button)
    if button ~= 1 then return end
    if #state.found >= 5 then return end
    if state.time_left <= 0 then return end

    local lx, ly = clickToPortraitLocal(x, y)
    if not lx then return end   -- click landed off-portrait — ignore for now

    for _, d in ipairs(state.diffs) do
        if not isFound(d) and pointInRect(lx, ly, d.x, d.y, d.w, d.h) then
            table.insert(state.found, {
                x = d.x, y = d.y, w = d.w, h = d.h,
                joker = false,
            })
            return
        end
    end
    -- Miss — click landed on a portrait but no unfound diff matched.
    -- Trigger the red full-screen fade, dock 1/4 of the level's total
    -- time, and play the wrong SFX (register "wrong" in assets.lua to
    -- hear it; harmlessly logs "unknown sound" until you do).
    state.miss_flash = MISS_FLASH_DURATION
    state.time_left  = state.time_left - state.time_total / 4
    if state.time_left < 0 then state.time_left = 0 end
    -- snd_play("wrong")
end

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
    draw_text("5", FOUND_X + 20, TOP_NUMBERS_Y, {
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

    -- Joker button — center-bottom
    draw_region("joker_button_up", JOKER_BTN_X, JOKER_BTN_Y)

    -- ---- Timer bar ----
    -- timebar_bg (266×24) is drawn centered; timebar (264×22) is anchored
    -- LEFT+TOP at the bg's inner-left edge (1px in from -133 → -132) so the
    -- foreground shrinks rightward as fill_x drops toward zero — the visible
    -- portion always starts flush with the bg's left edge.
    draw_region("timebar_bg", BAR_X, BAR_Y)
    draw_region("timebar", BAR_X + 1, BAR_Y + 1, {
        fill_x = state.time_left / state.time_total,
    })

    -- ---- Stars
    draw_region("star", STAR_X, IMG_Y)
    draw_region("star", STAR_X, IMG_Y + (STAR_SIZE + 8))
    draw_region("star_empty", STAR_X, IMG_Y + (STAR_SIZE + 8) * 2)
    draw_region("star_empty", STAR_X, IMG_Y + (STAR_SIZE + 8) * 3)
    draw_region("star_empty", STAR_X, IMG_Y + (STAR_SIZE + 8) * 4)


    -- ---- Portraits with frame ----
    -- image_bg is 287×417, drawn first; portrait (285×415) drawn on top
    draw_region("image_bg", IMG_LEFT_X, IMG_Y)
    draw_region("image_1a", IMG_LEFT_X + 1, IMG_Y + 1)

    draw_region("image_bg", IMG_RIGHT_X, IMG_Y)
    draw_region("image_1b", IMG_RIGHT_X + 1, IMG_Y + 1)

    -- ---- Found markers (green ellipses, mirrored on both portraits) ----
    local green = { 0.3, 1.0, 0.4, 1.0 }
    local yellow = { 1.0, 1.0, 0.0, 1.0 }
    for _, p in ipairs(state.found) do

        draw_ellipse(IMG_LEFT_X + p.x + p.w/2, IMG_Y + p.y + p.h/2, p.w/2, p.h/2, {
            thickness = 3, color = p.joker and yellow or green,
        })
        draw_ellipse(IMG_RIGHT_X + p.x + p.w/2, IMG_Y + p.y + p.h/2, p.w/2, p.h/2, {
            thickness = 3, color = p.joker and yellow or green,
        })
    end

    -- ---- Miss-click red overlay ----
    -- Drawn last so it covers HUD + portraits + ellipses. Linear fade
    -- from MISS_FLASH_MAX_ALPHA to 0 over MISS_FLASH_DURATION seconds.
    if state.miss_flash > 0 then
        local alpha = MISS_FLASH_MAX_ALPHA
                    * (state.miss_flash / MISS_FLASH_DURATION)
        local vw, vh = view_size()
        draw_quad(-vw / 2, -vh / 2, vw, vh, {
            color = { 1.0, 0.0, 0.0, alpha },
        })
    end
end




