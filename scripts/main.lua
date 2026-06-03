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
local currentPair  = LEVELS.categories[1].images[1]
local currentDiffs = currentPair.diffs

-- ---- State-machine modes ----
local STATE_PLAYING               = "playing"
local STATE_PAUSED                = "paused"
local STATE_LEVEL_COMPLETE_WAIT   = "level_complete_wait"
local STATE_LEVEL_COMPLETE        = "level_complete"
local STATE_GAME_OVER_REVEAL      = "game_over_reveal"
local STATE_GAME_OVER             = "game_over"
local STATE_ALL_DONE              = "all_done"

-- ---- Tunables -------------------------------------------------------------
local DIFF_COUNT             = LEVELS.diffCount
local MISS_FLASH_DURATION    = 0.4
local MISS_FLASH_MAX_ALPHA   = 0.5
local ELLIPSE_DRAW_DURATION  = 0.4
local REVEAL_STAGGER         = 0.25  -- delay between consecutive red ellipses
local REVEAL_DWELL           = 0.8   -- pause after the last reveal before GAME_OVER text
local LEVEL_COMPLETE_DWELL   = 0.6   -- pause AFTER the last ellipse finishes before COMPLETED dialog
local LOW_TIME_THRESHOLD     = 10.0  -- seconds at which the timebar starts pulsing
local LOW_TIME_CYCLE         = 2.0   -- one fade cycle (1.0 → 0.2 → 1.0) takes this long
local FIND_POINTS            = 100   -- per-diff bonus on find (click or joker)
local SCORE_COUNT_DURATION   = 1.5   -- level-end bonus count-up
local SCORE_POPUP_DURATION   = 0.9   -- "+N" float-and-fade
local SCORE_POPUP_RISE       = 30    -- virtual px the "+N" floats upward

-- ---- State ----------------------------------------------------------------
local state = {
    level        = 1,
    levelCount  = LEVELS.levelCount,
    score        = 0,
    jokers       = LEVELS.jokerMax,
    jokerMax    = LEVELS.jokerMax,
    timeTotal   = LEVELS.timeStart,   -- set per-level by startLevel()
    timeLeft    = LEVELS.timeStart,
    diffs        = currentDiffs,
    found        = {},
    missFlash   = 0,
    mode         = STATE_PLAYING,
    revealT     = 0,                   -- secs in GAME_OVER_REVEAL
    waitT       = 0,                   -- secs in LEVEL_COMPLETE_WAIT
    scorePopups = {},                  -- floating "+N" texts: { x, y, value, t }
    scoreAnim   = nil,                 -- level-end count-up: { from, to, t }
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

-- Returns (lx, ly, baseX) where lx/ly are portrait-local px and baseX
-- is the canvas x of the clicked portrait's top-left (so popups can be
-- placed on the actual side the player clicked).
local function clickToPortraitLocal(x, y)
    local leftX  = IMG_LEFT_X  + 1
    local rightX = IMG_RIGHT_X + 1
    local topY   = IMG_Y       + 1
    if y < topY or y >= topY + PORTRAIT_H then return nil end
    if x >= leftX  and x < leftX  + PORTRAIT_W then
        return x - leftX,  y - topY, leftX
    end
    if x >= rightX and x < rightX + PORTRAIT_W then
        return x - rightX, y - topY, rightX
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

-- Time budget for level `n` lerped linearly from LEVELS.timeStart at level 1
-- to LEVELS.timeEnd at levelCount. Single-level runs just use timeStart.
local function levelTimeBudget(n)
    if LEVELS.levelCount <= 1 then return LEVELS.timeStart end
    local f = (n - 1) / (LEVELS.levelCount - 1)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return LEVELS.timeStart + (LEVELS.timeEnd - LEVELS.timeStart) * f
end

-- Per-level reset. Doesn't touch state.score or state.jokers — both
-- persist across levels for the whole session. Jokers reset only on
-- newRun().
local function startLevel(n)
    state.level        = n
    state.timeTotal   = levelTimeBudget(n)
    state.timeLeft    = state.timeTotal
    state.found        = {}
    state.missFlash   = 0
    state.revealT     = 0
    state.waitT       = 0
    state.scorePopups = {}
    state.scoreAnim   = nil
    state.mode         = STATE_PLAYING
end

local function settleScoreAnim()
    if state.scoreAnim then
        state.score = state.scoreAnim.to
        state.scoreAnim = nil
    end
end

-- Forward-declared so enterAllDone / enterGameOver can capture it as
-- an upvalue for their Retry / Play-again button actions. The body
-- comes further down; everything in between can refer to it.
local newRun

-- Forward decls for the symbols the HUD widgets' onClick closures
-- need. The actual function bodies are assigned further down (after
-- the helpers they each use are defined).
local enterPaused, jokerAction

local function enterAllDone()
    state.mode = STATE_ALL_DONE
    -- Session-end joker bonus: 50 per unused joker. Per-level was wrong
    -- once jokers became persistent — same jokers would have been counted
    -- every level. Awarded once, here. The dialog body renders the count-up
    -- via state.scoreAnim once introDone.
    local jokerBonus = state.jokers * 50
    state.jokerBonus = jokerBonus     -- snapshot for the dialog body
    if jokerBonus > 0 then
        state.scoreAnim = {
            from = state.score, to = state.score + jokerBonus, t = 0,
        }
    end

    dialog.show({
        title = "RUN COMPLETE!",
        buttons = {
            {
                x = 0, y = 110, w = 240, h = 56,
                label  = "Play again",
                action = newRun,
            },
        },
        drawBody = function(introDone, t, ax, ay)
            if not introDone then return end
            drawText(string.format("Joker bonus:  %d", state.jokerBonus or 0),
                      ax, ay - 30, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                color = { 1.0, 0.95, 0.5 },
            })
            drawText(string.format("Final score:  %d", state.score),
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
                label  = "Retry",
                action = newRun,
            },
        },
        drawBody = function(introDone, t, ax, ay)
            if not introDone then return end
            drawText(string.format("Score:  %d", state.score),
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
    if state.level >= LEVELS.levelCount then
        enterAllDone()
    else
        startLevel(state.level + 1)
    end
end

-- Reset back to level 1 fresh. Used by GAME_OVER → retry and ALL_DONE → play
-- again. Wipes score AND jokers (the session ended).
newRun = function()
    state.score  = 0
    state.jokers = state.jokerMax
    startLevel(1)
end

local function enterLevelComplete()
    state.mode = STATE_LEVEL_COMPLETE
    -- Only time bonus per level; joker bonus is held until session end
    -- (see enterAllDone). Avoids paying out unused jokers every level.
    local timeBonus = math.floor(state.timeLeft * 10)
    state.timeBonus = timeBonus    -- snapshot for the dialog body
    state.scoreAnim = {
        from = state.score, to = state.score + timeBonus, t = 0,
    }

    dialog.show({
        title = "COMPLETED!",
        buttons = {
            {
                x = 0, y = 110, w = 240, h = 56,
                label  = "Next level >",
                action = continueToNextLevel,
            },
        },
        drawBody = function(introDone, t, ax, ay)
            -- Score breakdown. Hidden until the dialog settles so the
            -- bouncing entrance reads as a unit; once settled the score
            -- counts up via the existing state.scoreAnim.
            if not introDone then return end
            drawText(string.format("Time bonus:  %d", state.timeBonus or 0),
                      ax, ay - 30, {
                align = ALIGN_CENTER + ALIGN_MIDDLE,
                color = { 1.0, 0.95, 0.5 },
            })
            drawText(string.format("Total:  %d", state.score),
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
    state.revealT = 0
end

local function resumePlaying() state.mode = STATE_PLAYING end

-- Exit-to-menu: reset state so a new game starts fresh next time the
-- player picks "Start game" from the menu, then transition out. Action
-- fires AFTER the confirm dialog's outro (the normal action path), so
-- the dim has already faded by the time scene.replace runs.
local function exitToMainMenu()
    scene.replace(require("menu"), transition.fadeThroughBlack(0.6))
end

-- Pause + confirm specs cross-reference each other (Exit → confirm,
-- No → back to pause), so both are factory functions sharing a forward
-- declaration. The dialog module resolves a function-form `replace`
-- lazily at click time — no init cycle, no stale closures.
local pauseSpecFn, confirmExitSpecFn

pauseSpecFn = function()
    return {
        title = "PAUSED",
        height = 230,		
        buttons = {
            { x = 0, y = -10, w = 240, h = 56,
              label = "Resume", 
			  action = resumePlaying },
            { x = 0, y = 55, w = 240, h = 56,
              label = "Exit to main menu",
			  replace = confirmExitSpecFn },
        },
    }
end

confirmExitSpecFn = function()
    return {
        title = "Exit to main menu?",
		height = 170,
        buttons = {
            { x = -60, y = 25, w = 100, h = 56,
              label = "No",
			  replace = pauseSpecFn },
            -- skipOutro so the dialog doesn't slide+fade FIRST and
            -- THEN the scene fade-to-black starts. The dialog stays
            -- at rest visually while the overlay grows over it; the
            -- game scene's :exit dismisses the dialog state at swap.
            { x =  60, y = 25, w = 100, h = 56,
              label = "Yes",
			  action = exitToMainMenu,
              skipOutro = true },
        },
    }
end

-- Assigning to the forward-declared upvalue (NOT `local function`) so
-- the HUD widgets' onClick closure resolves to this body.
enterPaused = function()
    state.mode = STATE_PAUSED
    dialog.show(pauseSpecFn())
end

-- Add a "+N" floating text at canvas (x, y) tied to the next onRender.
local function pushScorePopup(x, y, value)
    table.insert(state.scorePopups, { x = x, y = y, value = value, t = 0 })
end

-- Common path for both player-click finds and joker reveals. Pushes the
-- ellipse animation, awards FIND_POINTS, and (for player finds only)
-- spawns the "+N" popup at the actual click position on the side the
-- player clicked. Joker reveals get no popup since FIND_POINTS feels
-- like a reward for *finding*, not for spending a joker.
-- clickLx/ly are portrait-local px; baseX is the canvas x of the
-- clicked portrait's top-left. All three are nil for joker reveals.
local function awardFind(d, byJoker, clickLx, clickLy, baseX)
    table.insert(state.found, {
        x = d.x, y = d.y, w = d.w, h = d.h,
        joker = byJoker, t = 0,
    })
    if not byJoker then
        state.score = state.score + FIND_POINTS
        pushScorePopup(baseX + clickLx, IMG_Y + 1 + clickLy, FIND_POINTS)
    end
end

-- Joker button onClick: if any jokers are left, reveal the next
-- unfound diff. The press flash comes for free from widget.button's
-- mouseDown/mouseUp cycle — no timer needed.
jokerAction = function()
    if state.jokers > 0 then
        local d = firstUnfound()
        if d then
            awardFind(d, true)
            state.jokers = state.jokers - 1
        end
    else
        soundPlay("wrong")
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
local anim   = require "engine.animation"

local root = widget.panel({ x = 0, y = 0 })

-- Layer 1: portrait frames + portraits. Painted first; the dynamic
-- ellipses / popups / overlays paint on top in gameRender.
root:add(widget.image{ x = IMG_LEFT_X,      y = IMG_Y,     region = "image_bg" })
root:add(widget.image{ x = IMG_LEFT_X + 1,  y = IMG_Y + 1, region = "image_1a" })
root:add(widget.image{ x = IMG_RIGHT_X,     y = IMG_Y,     region = "image_bg" })
root:add(widget.image{ x = IMG_RIGHT_X + 1, y = IMG_Y + 1, region = "image_1b" })

-- Layer 2: timebar. The fg's fillX and alpha get rewritten each
-- frame by syncHud — fill from timeLeft, alpha pulses on low time.
root:add(widget.image{ x = BAR_X, y = BAR_Y, region = "timebar_bg" })
local timebarFg = widget.image{
    x = BAR_X + 1, y = BAR_Y + 1, region = "timebar",
}
root:add(timebarFg)

-- Layer 3: stars. Each slot is two widgets — star_bg is always
-- visible, star (the gold graphic) sits on top and starts invisible
-- (alpha = 0, scale = 1.5). When a diff is found, syncHud kicks off
-- a pop animation on the matching star (scale 1.5 → 1.0, alpha 0 → 1,
-- 0.5 s). Two passes: ALL bgs first, then ALL stars on top — so a
-- popping star scaling out past its own slot doesn't get covered by
-- the next slot's bg.
local starBgWidgets = {}
local starWidgets    = {}
local function starPos(i)
    return STAR_X, IMG_Y + (STAR_SIZE + 8) * (i - 1)
end
for i = 1, DIFF_COUNT do
    local sx, sy = starPos(i)
    starBgWidgets[i] = widget.image{ x = sx, y = sy, region = "star_bg" }
    root:add(starBgWidgets[i])
end
for i = 1, DIFF_COUNT do
    local sx, sy = starPos(i)
    starWidgets[i] = widget.image{
        x = sx, y = sy, region = "star",
        alpha = 0, scale = 1.5,
    }
    root:add(starWidgets[i])
end

-- Layer 4: HUD text. Width 0 + align CENTER+TOP reproduces the
-- original "draw text centred on this point" semantics — anchorIn
-- on a zero-size bbox lands at (x, y) regardless of horizontal align.
local function addText(x, y, text, opts)
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
addText(LEVEL_X,      TOP_LABELS_Y,       "LEVEL")
local levelCurrent = addText(LEVEL_X - 20, TOP_NUMBERS_Y, "1", {
    font = "large",
    color = CURRENT_COLOR
})
local levelTotal = addText(LEVEL_X + 20, TOP_NUMBERS_Y, "1", {
    font = "large",
	color = TOTAL_COLOR
})
addText(LEVEL_X, TOP_SLASH_LABELS_Y, "/")

-- FOUND column — current / DIFF_COUNT (total is static).
addText(FOUND_X,  TOP_LABELS_Y, "FOUND")
local foundCurrent = addText(FOUND_X - 20, TOP_NUMBERS_Y, "0", {
    font = "large",
	color = CURRENT_COLOR
})
addText(FOUND_X + 20, TOP_NUMBERS_Y, tostring(DIFF_COUNT), {
    font = "large",
	color = TOTAL_COLOR
})
addText(FOUND_X, TOP_SLASH_LABELS_Y, "/")

-- SCORE column — single number, no /total.
addText(SCORE_X, TOP_LABELS_Y, "SCORE")
local scoreLabel  = addText(SCORE_X, TOP_NUMBERS_Y, "0", {
    font = "large",
	color = SCORE_COLOR
})

-- JOKER badge (label above the count, count above the button).
addText(JOKER_X, JOKER_Y, "JOKER")
local jokerCount  = addText(JOKER_X, JOKER_Y + 16, "0", {
    font = "large",
	color = CURRENT_COLOR
})

-- Layer 5: buttons. pause (top-right) and joker (center-bottom). Both
-- use the standard button trio (button_up / button_down / button_hover)
-- with pause_icon / joker_icon centered over them.
local pauseButton = widget.button{
    x = PAUSE_BTN_X, y = PAUSE_BTN_Y, width = 42, height = 42,
    bgUp      = "button_up",
    bgDown    = "button_down",
    bgHover   = "button_hover",
    icon      = "pause_icon",
    iconAlign = ALIGN_CENTER + ALIGN_MIDDLE,
    onClick   = function() enterPaused() end,
}
-- HUD buttons are mouse-only. Mark non-focusable BEFORE :add so the
-- panel's auto-focus walk skips them — otherwise pressing Enter or
-- Space during gameplay would fire pause / joker via dispatchKeyDown.
pauseButton.focusable = false
root:add(pauseButton)

local jokerButton = widget.button{
    x = JOKER_BTN_X, y = JOKER_BTN_Y, width = 42, height = 42,
    bgUp      = "button_up",
    bgDown    = "button_down",
    bgHover   = "button_hover",
    icon      = "joker_icon",
    iconAlign = ALIGN_CENTER + ALIGN_MIDDLE,
    onClick   = function() jokerAction() end,
}
jokerButton.focusable = false
root:add(jokerButton)

-- Watch state.found's length across frames so we can fire the pop
-- animation on whichever stars just lit up (growth) and snap stars
-- back to the empty visual on level reset (shrink).
local prevFoundCount = 0
-- Fade is short so the star snaps visible; scale runs longer with
-- bounceOut so the settle has multiple visible bounces (lands at
-- 1.0, bounces up to ~1.125, settles, smaller bounce, etc.).
local STAR_FADE_DURATION  = 0.15
local STAR_SCALE_DURATION = 0.5

-- Per-frame: pull labels / regions / fills / alphas from game state.
local function syncHud()
    levelCurrent.text = tostring(state.level)
    levelTotal.text   = tostring(state.levelCount)
    foundCurrent.text = tostring(#state.found)
    scoreLabel.text   = tostring(state.score)
    jokerCount.text   = tostring(state.jokers)

    local foundCount = #state.found
    if foundCount > prevFoundCount then
        -- One or more diffs just resolved. Animate each newly-lit star
        -- in from scale 1.5 / alpha 0 to its rest state in parallel.
        for i = prevFoundCount + 1, foundCount do
            local s = starWidgets[i]
            s.alpha = 0
            s.scale = 1.5
            s.action = anim.parallel{
                anim.fadeTo(1.0, STAR_FADE_DURATION,  anim.easeOut),
                anim.scaleTo(1.0, STAR_SCALE_DURATION, anim.bounceOut),
            }
        end
    elseif foundCount < prevFoundCount then
        -- Reset (level / run restart). Snap every star to its empty
        -- visual; cancel any animation in flight.
        for i = 1, DIFF_COUNT do
            local s = starWidgets[i]
            s.action = nil
            if i <= foundCount then
                s.alpha, s.scale = 1.0, 1.0
            else
                s.alpha, s.scale = 0.0, 1.5
            end
        end
    end
    prevFoundCount = foundCount

    timebarFg.fillX = state.timeLeft / state.timeTotal

    -- Last-10s warning: cosine alpha pulse, 5 cycles over the final 10s.
    -- Only pulses while PLAYING — pause/game-over freeze it.
    local barAlpha = 1.0
    if state.mode == STATE_PLAYING and state.timeLeft <= LOW_TIME_THRESHOLD then
        local phase = (LOW_TIME_THRESHOLD - state.timeLeft) / LOW_TIME_CYCLE
        barAlpha = 0.6 + 0.4 * math.cos(2 * math.pi * phase)
    end
    timebarFg.alpha = barAlpha
end

-- ---- Hooks ----------------------------------------------------------------
--
-- Hooks are routed through engine.scene. The menu scene is the first
-- thing pushed; clicking its "Start game" button calls
-- find5StartGame(), which replaces the menu with the gameScene
-- defined at the bottom of this file.

local function gameUpdate(dt)
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
    if state.missFlash > 0 then
        state.missFlash = state.missFlash - dt
        if state.missFlash < 0 then state.missFlash = 0 end
    end

    -- Score count-up animation (set by enterLevelComplete). Updates the
    -- displayed state.score; settles to .to once the duration elapses.
    if state.scoreAnim then
        state.scoreAnim.t = state.scoreAnim.t + dt
        if state.scoreAnim.t >= SCORE_COUNT_DURATION then
            state.score = state.scoreAnim.to
            state.scoreAnim = nil
        else
            local f = state.scoreAnim.t / SCORE_COUNT_DURATION
            state.score = math.floor(state.scoreAnim.from
                                  + (state.scoreAnim.to - state.scoreAnim.from) * f)
        end
    end

    -- "+N" floating popups: walk in reverse so removal-by-index is safe.
    for i = #state.scorePopups, 1, -1 do
        local p = state.scorePopups[i]
        p.t = p.t + dt
        if p.t > SCORE_POPUP_DURATION then
            table.remove(state.scorePopups, i)
        end
    end

    if state.mode == STATE_PLAYING then
        if state.timeLeft > 0 then
            state.timeLeft = state.timeLeft - dt
            if state.timeLeft < 0 then state.timeLeft = 0 end
        end
        if #state.found >= DIFF_COUNT then
            -- Defer the dialog: wait for the last ellipse to finish
            -- drawing, plus LEVEL_COMPLETE_DWELL extra so the win
            -- registers before the modal drops in.
            state.mode   = STATE_LEVEL_COMPLETE_WAIT
            state.waitT = 0
        elseif state.timeLeft <= 0 then
            enterGameOverReveal()
        end

    elseif state.mode == STATE_LEVEL_COMPLETE_WAIT then
        state.waitT = state.waitT + dt
        if state.waitT >= ELLIPSE_DRAW_DURATION + LEVEL_COMPLETE_DWELL then
            enterLevelComplete()
        end

    elseif state.mode == STATE_GAME_OVER_REVEAL then
        state.revealT = state.revealT + dt
        local n = unfoundCount()
        -- Reveal i starts at i*STAGGER (0-indexed), runs for DURATION,
        -- then we hold for DWELL before opening the GAME_OVER dialog.
        local need = (n > 0)
                     and ((n - 1) * REVEAL_STAGGER + ELLIPSE_DRAW_DURATION + REVEAL_DWELL)
                     or  REVEAL_DWELL
        if state.revealT >= need then
            enterGameOver()
        end
    end

    -- Push the latest game state into the HUD widgets so they render
    -- with up-to-date text / colors / fills / press flags this frame.
    syncHud()

    -- Tick the HUD panel so children's actions (e.g. the star pop-in
    -- attached by syncHud) advance. scene.dispatchUpdate only ticks
    -- t.root.action — children's actions need root:update to run.
    root:update(dt)
end

local function gameMouseDown(x, y, button)
    if button ~= 1 then return end

    -- An active dialog owns clicks entirely — its button hit-tests run
    -- inside handleMouseDown / handleMouseUp, and misses are
    -- swallowed (no fall-through to game logic underneath the modal).
    -- PAUSE / LEVEL_COMPLETE / GAME_OVER / ALL_DONE all route through
    -- here. NB: widget buttons fire onClick on RELEASE, so we also
    -- need to route mouseUp (see gameMouseUp) and mouseMove (for
    -- hover feedback while the dialog is up).
    if dialog.isActive() then
        dialog.handleMouseDown(x, y, button)
        return
    end

    if state.mode ~= STATE_PLAYING then return end  -- game_over_reveal: input locked

    -- Forward to the HUD panel — pause / joker buttons own their own
    -- hit-tests and fire onClick on mouseUp. Pause and joker bbox
    -- live entirely outside the portrait area, so a click that lands
    -- on a button never falls through to a portrait hit-test below.
    root:mouseDown(x, y, button)

    local lx, ly, baseX = clickToPortraitLocal(x, y)
    if not lx then return end

    for _, d in ipairs(state.diffs) do
        if not isFound(d) and pointInRect(lx, ly, d.x, d.y, d.w, d.h) then
            awardFind(d, false, lx, ly, baseX)
            return
        end
    end
    -- Miss — click was on a portrait but no unfound diff matched.
    state.missFlash = MISS_FLASH_DURATION
    state.timeLeft  = state.timeLeft - state.timeTotal / 4
    if state.timeLeft < 0 then state.timeLeft = 0 end
    -- soundPlay("wrong")
end

-- Dialog needs mouseUp (widget buttons fire on release) and mouseMove
-- (button hover) while it's modally active. When no dialog, fan these
-- straight to the HUD panel so pause / joker hover + release still work
-- — we'd otherwise lose the scene's auto-forward path by declaring
-- mouseUp / mouseMove on gameScene at all.

local function gameMouseUp(x, y, button)
    if dialog.isActive() then
        dialog.handleMouseUp(x, y, button)
        return
    end
    root:mouseUp(x, y, button)
end

local function gameMouseMove(x, y, dx, dy)
    if dialog.isActive() then
        dialog.handleMouseMove(x, y, dx, dy)
        return
    end
    root:mouseMove(x, y, dx, dy)
end

-- ---- Render ---------------------------------------------------------------

local function gameRender()
    -- ---- Backdrop: blurred color summary of the left portrait. ----
    -- Multiply by root.alpha so the blur fades in / out with the rest
    -- of the scene during a transition — otherwise it pops in at full
    -- opacity while the HUD widgets are still fading.
    drawBlur("image_1a", { width = 16, alpha = 0.6 * root.alpha })

    -- HUD panel — portrait frames + portraits, timebar, stars, text
    -- labels, pause + joker buttons. Sync_hud (called at end of
    -- gameUpdate) refreshes labels / regions / fills / press flags
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
        drawEllipse(IMG_LEFT_X + p.x + p.w/2, IMG_Y + p.y + p.h/2, p.w/2, p.h/2, {
            finish = finish, thickness = 3, color = color,
        })
        drawEllipse(IMG_RIGHT_X + p.x + p.w/2, IMG_Y + p.y + p.h/2, p.w/2, p.h/2, {
            finish = finish, thickness = 3, color = color,
        })
    end

    -- ---- Floating "+N" score popups (one per find) ----
    for _, p in ipairs(state.scorePopups) do
        local f = p.t / SCORE_POPUP_DURATION
        if f > 1 then f = 1 end
        local alpha = 1 - f
        local dy    = -SCORE_POPUP_RISE * f
        drawText(string.format("+%d", p.value), p.x, p.y + dy, {
	      align = ALIGN_CENTER + ALIGN_MIDDLE,
	      color = { 0.4, 1.0, 0.5, alpha }
	    })
    end

    -- ---- Game-over reveal: red ellipses on unfound diffs, staggered ----
    if state.mode == STATE_GAME_OVER_REVEAL or state.mode == STATE_GAME_OVER then
        local i = 0
        for _, d in ipairs(state.diffs) do
            if not isFound(d) then
                local elapsed = state.revealT - i * REVEAL_STAGGER
                if elapsed > 0 then
                    local finish = elapsed / ELLIPSE_DRAW_DURATION
                    if finish > 1 then finish = 1 end
                    drawEllipse(IMG_LEFT_X + d.x + d.w/2, IMG_Y + d.y + d.h/2, d.w/2, d.h/2, {
                        finish = finish, thickness = 3, color = red,
                    })
                    drawEllipse(IMG_RIGHT_X + d.x + d.w/2, IMG_Y + d.y + d.h/2, d.w/2, d.h/2, {
                        finish = finish, thickness = 3, color = red,
                    })
                end
                i = i + 1
            end
        end
    end

    -- ---- Miss-click red overlay ----
    if state.missFlash > 0 then
        local alpha = MISS_FLASH_MAX_ALPHA
                    * (state.missFlash / MISS_FLASH_DURATION)
        local vw, vh = viewSize()
        drawQuad(-vw / 2, -vh / 2, vw, vh, {
            color = { 1.0, 0.0, 0.0, alpha },
        })
    end

    -- Dialog renders last so it sits above everything (HUD, portraits,
    -- diff ellipses). All terminal states are dialogs now.
    dialog.render()
end

-- ---- Scene wrapper --------------------------------------------------------
-- The game runs as one scene; the title screen runs as another. Bodies
-- of gameUpdate / gameMouseDown / gameRender are unchanged from when
-- they were top-level on_* hooks — only the dispatch path changed.

local gameScene = { root = root }

function gameScene:enter()
    -- The currentPair / currentDiffs / state table at the top of this
    -- file are already initialised to level-1 fresh, so nothing extra to
    -- do for the first run. A "play again" path through enterAllDone /
    -- enterGameOver re-uses newRun() which already resets everything.
end

function gameScene:update(dt)     gameUpdate(dt)         end
function gameScene:mouseDown(x, y, b) gameMouseDown(x, y, b) end
function gameScene:mouseUp(x, y, b)   gameMouseUp(x, y, b)   end
function gameScene:mouseMove(x, y, dx, dy) gameMouseMove(x, y, dx, dy) end
function gameScene:render()        gameRender()           end

-- Clean up the dialog state when leaving the game scene. The Yes /
-- Exit-to-main-menu path uses skipOutro on the dialog button — it
-- fires exitToMainMenu immediately and the dialog stays rendered
-- at rest underneath the scene fade-to-black. Once the scene swap
-- pops gameScene mid-overlay, this exit clears the orphaned dialog
-- state so a fresh gameScene later starts with no leftover modal.
function gameScene:exit()
    dialog.dismiss()
end

-- Menu hands off to the game by calling this global. category arg is the
-- entry from levels.lua's `categories` array; not used yet (the engine
-- still plays the single hard-coded portrait pair) but the plumbing is
-- in place for when image selection lands.
function _G.find5StartGame(category)
    -- Reset state before the transition kicks in. The newRun sets
    -- state from PAUSED / GAME_OVER / wherever back to a fresh PLAYING
    -- level 1; the overlay covers the menu while this happens, and by
    -- the time gameScene:enter fires at the swap midpoint the game is
    -- ready to render fresh.
    newRun()
    scene.replace(gameScene, transition.fadeThroughBlack(0.6))
end

-- Menu's close button signals quit. requestQuit() (SOOB-Core binding)
-- sets a flag the host loop polls after each update, then runs the
-- normal shutdown path — a graceful exit, not an abort.
function _G.find5RequestQuit()
    requestQuit()
end

-- Wire the on_* engine hooks to scene dispatchers. onStart stays
-- custom so we can push the menu on first frame.
scene.installHooks(_G)

function onStart()
    scene.push(require("menu"))
end
