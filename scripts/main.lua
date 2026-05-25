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
    -- Difference positions in portrait-local coords (centered on each image).
    -- Same coordinates apply to both image_1a and image_1b — that's the
    -- point of spot-the-difference; the engine just draws the marker on
    -- both portraits.    
    found       = {
        { x =  60, y = 120, w = 120, h = 40, joker = false },
        { x =  40, y =  30, w = 40, h = 60, joker = true },
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

function on_render()
    -- ---- Backdrop: blurred color summary of the left portrait. ----
    draw_blur("image_1a", { width = 16, alpha = 0.6 })

    -- ---- HUD top row ----
    draw_text("LEVEL", LEVEL_X, TOP_LABELS_Y, { align = ALIGN_CENTER, color = SMALL_LABEL_COLOR })
    draw_text(string.format("%d", state.level), LEVEL_X - 20, TOP_NUMBERS_Y, { align = ALIGN_CENTER, font = "large", color = CURRENT_COLOR })
    draw_text(string.format("%d", state.level_count), LEVEL_X + 20, TOP_NUMBERS_Y, { align = ALIGN_CENTER, font = "large", color = TOTAL_COLOR })
    draw_text("/", LEVEL_X, TOP_SLASH_LABELS_Y, { align = ALIGN_CENTER, color = SMALL_LABEL_COLOR })

    draw_text("FOUND", FOUND_X, TOP_LABELS_Y, { align = ALIGN_CENTER, color = SMALL_LABEL_COLOR })
    draw_text(string.format("%d", table.getn(state.found)), FOUND_X - 20, TOP_NUMBERS_Y, { align = ALIGN_CENTER, font = "large", color = CURRENT_COLOR })
    draw_text("5", FOUND_X + 20, TOP_NUMBERS_Y, { align = ALIGN_CENTER, font = "large", color = TOTAL_COLOR })
    draw_text("/", FOUND_X, TOP_SLASH_LABELS_Y, { align = ALIGN_CENTER, color = SMALL_LABEL_COLOR })

    draw_text("SCORE", SCORE_X, TOP_LABELS_Y, { align = ALIGN_CENTER, color = SMALL_LABEL_COLOR })
    draw_text(string.format("%d", state.score), SCORE_X, TOP_NUMBERS_Y, { align = ALIGN_CENTER, font = "large", color = SCORE_COLOR })

    draw_text("JOKER", JOKER_X, JOKER_Y, { align = ALIGN_CENTER, color = SMALL_LABEL_COLOR })
    draw_text(string.format("%d", state.jokers), JOKER_X, JOKER_Y + 16, { align = ALIGN_CENTER, font = "large", color = CURRENT_COLOR })

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
end




