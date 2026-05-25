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
        { x = -60, y = -120 },
        { x =  40, y =   30 },
    },
}

-- Layout constants — y is down on the virtual canvas (UI_VIRTUAL_H = 480),
-- center origin, so the visible range is roughly -240..+240 vertically.
local HUD_Y       = -224     -- top-row text baseline-ish
local HUD_TOP_Y   = -228     -- icon top edge (anchored TOP)
local BAR_Y       = -192     -- timebar_bg top edge
local IMG_Y       =   38     -- portrait center y
local IMG_LEFT_X  = -148     -- left portrait center x
local IMG_RIGHT_X =  148     -- right portrait center x

function on_start()
    music_play("title", 0.5, true)
end

function on_render()
    -- ---- Backdrop: blurred color summary of the left portrait. ----
    draw_blur("image_1a", { width = 16, alpha = 0.6 })

    -- ---- HUD top row ----
    -- Level "3/10" — top-left.
    draw_text(string.format("%d/%d", state.level, state.level_count),
              -300, HUD_Y)

    -- Joker star + "remaining/max" counter, left of center.
    draw_region("joker", -130, HUD_TOP_Y, {
        align = ALIGN_CENTER + ALIGN_TOP,
    })
    draw_text(string.format("%d/%d", state.jokers, state.joker_max),
              -100, HUD_Y)

    -- Score, right-aligned, sits just left of the pause button.
    draw_text(tostring(state.score), 232, HUD_Y, { align = ALIGN_RIGHT })

    -- Pause button — top-right corner.
    draw_region("pause_button_up", 295, HUD_TOP_Y, {
        align = ALIGN_CENTER + ALIGN_TOP,
    })

    -- ---- Timer bar ----
    -- timebar_bg (266×24) is drawn centered; timebar (264×22) is anchored
    -- LEFT+TOP at the bg's inner-left edge (1px in from -133 → -132) so the
    -- foreground shrinks rightward as fill_x drops toward zero — the visible
    -- portion always starts flush with the bg's left edge.
    draw_region("timebar_bg", 0, BAR_Y, {
        align = ALIGN_CENTER + ALIGN_TOP,
    })
    draw_region("timebar", -132, BAR_Y + 1, {
        align = ALIGN_LEFT + ALIGN_TOP,
        fill_x = state.time_left / state.time_total,
    })

    -- ---- Portraits with frame ----
    -- image_bg is 287×417, drawn first; portrait (285×415) drawn on top
    -- centered at the same point → image_bg shows as a 1px frame around it.
    draw_region("image_bg", IMG_LEFT_X, IMG_Y, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
    })
    draw_region("image_1a", IMG_LEFT_X, IMG_Y, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
    })

    draw_region("image_bg", IMG_RIGHT_X, IMG_Y, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
    })
    draw_region("image_1b", IMG_RIGHT_X, IMG_Y, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
    })

    -- ---- Found markers (green ellipses, mirrored on both portraits) ----
    local green = { 0.3, 1.0, 0.4, 1.0 }
    for _, p in ipairs(state.found) do
        draw_ellipse(IMG_LEFT_X  + p.x, IMG_Y + p.y, 26, 19, {
            thickness = 3, color = green,
        })
        draw_ellipse(IMG_RIGHT_X + p.x, IMG_Y + p.y, 26, 19, {
            thickness = 3, color = green,
        })
    end
end
