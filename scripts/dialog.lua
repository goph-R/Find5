-- Find5 — modal dialog system (widget-based).
--
-- A single dialog at a time. Drops in from above with bounceOut (two
-- visible re-impacts before settling); shoots back up out the top on
-- close with easeInExpo (slow start, exponential acceleration). A
-- separate dim quad behind the dialog fades in during intro and snaps
-- out faster during outro. An "open" sound plays on show(), a "close"
-- sound on close().
--
-- Tree shape:
--
--   root (panel; covers the full canvas)
--     ├─ dim       (fullscreen quad; alpha tweens 0 ↔ DIM_ALPHA)
--     └─ dlg       (panel; y tweens between off-screen and rest)
--          ├─ left  dialog_chain     (drawn first → tucked under bg)
--          ├─ right dialog_chain     (likewise)
--          ├─ widget.image  "dialog_bg_top"     (marble body; fillY-clippable)
--          ├─ widget.image  "dialog_bg_bottom"  (static base strip below top)
--          ├─ title label   (large font, centered)
--          └─ widget.button (one per spec.buttons entry)
--
-- Spec fields:
--   title          string                — drawn near the top, large font
--   appearSound   string  ("dialog_open")
--   closeSound    string  ("dialog_close")
--   w              number  — dialog width, default 460
--   height         number  — MARBLE BODY height (top region) in px.
--                            Capped at dialog_bg_top's native height; below
--                            that, clipped from the bottom edge via fillY
--                            (same trick as the timebar). Total dialog
--                            visual height = height + dialog_bg_bottom's
--                            native height (the bottom strip is static).
--                            Default: top region's native height (no clip).
--   buttons        array of { x, y, w, h, label, action | replace, skipOutro }
--                   positions in dialog-local coords (origin = dialog CENTER).
--                   `action`  — function fired AFTER the outro animation
--                              completes. Latched in pendingAction;
--                              dlg.onActionDone fires it. Dim fades
--                              out on close.
--                   `replace` — spec (or factory function returning a
--                              spec) for a follow-up dialog. The current
--                              dialog slides out WITHOUT fading the dim,
--                              the new one slides in without fading the
--                              dim back up — seamless dialog-to-dialog
--                              hand-off. Takes precedence over `action`.
--                   `skipOutro` — boolean. When true, onClick fires
--                              `action` IMMEDIATELY (no outro animation,
--                              no dim fade); the dialog keeps rendering
--                              at rest until something else hides it.
--                              Pair with dialog.dismiss() at the right
--                              cleanup moment (typically scene:exit())
--                              so the action's downstream effect — a
--                              scene fade-to-black, say — owns the
--                              visual hand-off without the dialog
--                              playing a redundant outro underneath.
--   drawBody      function(introDone, t, anchor_x, anchor_y)
--                   called every frame after the widget tree draws;
--                   (anchor_x, anchor_y) is the dialog's CENTER on screen,
--                   including the animation offset.
--
-- Input contract: while isActive(), the host should route
-- handleMouseDown / handleMouseUp / handleMouseMove for every mouse
-- event — buttons need both press AND release to complete a click, and
-- mouseMove drives hover. Events outside STATE_OPEN are swallowed (no
-- input during intro / outro).

local widget = require "engine.widget"
local anim   = require "engine.animation"

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

-- ---- Default layout (a spec may override w / height) -------------------
local DEFAULT_W = 460
-- DEFAULT marble body height = dialog_bg_top's native height; resolved
-- inside buildTree via regionSize since region tables aren't queryable
-- at file-load time.

-- Chain horizontal anchors as fractions of dialog width — chain centres
-- land at 1/4 and 3/4 across, symmetric. Vertical: a small overlap so
-- the chain tucks under the dialog top edge (z-order does the hiding).
local CHAIN_LEFT_FRAC  = 0.2
local CHAIN_RIGHT_FRAC = 0.8
local CHAIN_OVERLAP_PX = 10

-- ---- Easing --------------------------------------------------------------
--
-- Robert Penner's easeInExpo — slow start, exponential acceleration.
-- Matches the "shoots off the top" feel the user asked for on close.
-- Lives here rather than in engine.animation because it's the only
-- caller; promote later if anything else wants it.
local function easeInExpo(p)
    if p <= 0 then return 0 end
    return math.pow(2, 10 * (p - 1))
end

-- ---- Internal state ------------------------------------------------------
local current         = nil    -- { spec, state, t, root, dlg, dim }
local pendingAction  = nil    -- latched in onClick, fires after outro
local pendingReplace = nil    -- spec to show next; dim stays at full

-- ---- Custom mini-widget: flat colour quad with animatable alpha ----------
--
-- The dim backdrop needs a draw method that engine.widget doesn't
-- ship (a fullscreen quad). Same interface as every other widget
-- (visible / alpha / scale / draw / hit / mouse* / key*) so panel:draw
-- cascades alpha through it the same way.

local function makeQuadWidget(x, y, w, h, color)
    local q = {
        x = x, y = y, width = w, height = h,
        color = color,
        visible = true, disabled = false, focusable = false,
        alpha = 1.0, scale = 1.0,
    }
    function q:draw()
        if not self.visible or self.alpha <= 0 then return end
        local c = self.color
        drawQuad(self.x, self.y, self.width, self.height, {
            color = { c[1], c[2], c[3], (c[4] or 1.0) * self.alpha },
        })
    end
    function q:hit()       return false end
    function q:mouseDown() return false end
    function q:mouseUp()   return false end
    function q:mouseMove() end
    function q:keyDown()   return false end
    function q:keyUp()     return false end
    return q
end

-- ---- Tree construction ---------------------------------------------------

local function buildTree(spec)
    local vw, vh = viewSize()
    local dlgW  = spec.w or DEFAULT_W

    -- Top region clips with fillY when the requested marble height is
    -- below its native pixel height (same mechanism the timebar uses for
    -- fillX — both source UVs and dst shrink in lockstep). Above native
    -- there's no marble pattern to extend, so we cap.
    local _, topNativeH    = regionSize("dialog_bg_top")
    local _, bottomNativeH = regionSize("dialog_bg_bottom")
    local topH = spec.height or topNativeH
    if topH > topNativeH then topH = topNativeH end
    local topFill = topH / topNativeH
    -- TOTAL dialog visual height includes the static bottom strip.
    -- Animation positions and button anchors track this, not topH alone.
    local dlgH = topH + bottomNativeH

    -- Dialog panel uses TOP-LEFT origin so its bbox encloses the
    -- buttons (click-to-focus needs the bbox to contain hit children).
    -- The chains hang above the bbox at negative local y; that's
    -- draw-only so the bbox doesn't matter for them.
    local restY  = -dlgH * 0.5
    local startY = restY - START_OFFSET

    local root = widget.panel{ x = 0, y = 0, width = vw, height = vh }

    -- Dim: black fullscreen quad. alpha tweens 0 → DIM_ALPHA on intro,
    -- back to 0 on outro. Independent of the dlg panel's transform.
    local dim = makeQuadWidget(-vw * 0.5, -vh * 0.5, vw, vh, { 0, 0, 0, 1 })
    dim.alpha = 0
    root:add(dim)

    local dlg = widget.panel{
        x = -dlgW * 0.5, y = startY,
        width = dlgW, height = dlgH,
    }

    -- Chains — drawn FIRST so the marble top occludes the part that
    -- overlaps the dialog top edge (z-order does the tuck). Two copies
    -- of the single dialog_chain region, centred at CHAIN_LEFT/RIGHT
    -- across. Vertical: bottom sits CHAIN_OVERLAP_PX below the dialog
    -- top so the chain visibly anchors into the bg instead of just
    -- touching.
    local chainW, chainH = regionSize("dialog_chain")
    local chainY = CHAIN_OVERLAP_PX - chainH
    dlg:add(widget.image{
        x = dlgW * CHAIN_LEFT_FRAC  - chainW * 0.5,
        y = chainY, region = "dialog_chain",
    })
    dlg:add(widget.image{
        x = dlgW * CHAIN_RIGHT_FRAC - chainW * 0.5,
        y = chainY, region = "dialog_chain",
    })

    -- Marble body — covers the chain tails that crossed the top edge.
    -- height stays at native; fillY handles the actual visual clip so
    -- both source UVs and dst pixels shrink together. The widget's
    -- on-screen height ends up at topH.
    dlg:add(widget.image{
        x = 0, y = 0, region = "dialog_bg_top",
        width = dlgW, height = topNativeH,
        fillY = topFill,
    })

    -- Static bottom strip — sits flush against the bottom of the
    -- (possibly-clipped) marble. Native height, never clipped.
    dlg:add(widget.image{
        x = 0, y = topH, region = "dialog_bg_bottom",
        width = dlgW, height = bottomNativeH,
    })

    -- Title — visible from frame 1 of the intro.
    if spec.title then
        dlg:add(widget.label{
            x = dlgW * 0.5, y = 40,
            width = 0, height = 0,
            text  = spec.title,
            font  = "large",
            align = ALIGN_CENTER + ALIGN_MIDDLE,
            color = { 1, 1, 1 },
        })
    end

    -- Buttons. spec.buttons[i].x/y are CENTER offsets from the dialog
    -- center; translate to panel-local top-left coords. The onClick
    -- closure either:
    --   * `replace` set → hand off to M.replace, no dim fade between
    --     dialogs (resolve a function-form replace lazily so two specs
    --     can cross-reference each other without an init cycle);
    --   * else → latch `action` into pendingAction and start a normal
    --     close; dlg.onActionDone fires the action once outro lands.
    -- Collected so M.revealButtons can animate them in later. When
    -- spec.buttonsStartHidden is set, each button starts visible=false
    -- (panel skips hidden children for both draw AND hit) until a body
    -- animation finishes and calls dialog.revealButtons().
    local buttons = {}
    for _, btn in ipairs(spec.buttons or {}) do
        local bw    = btn.w or 200
        local bh    = btn.h or 48
        local cx    = btn.x or 0
        local cy    = btn.y or 0
        local act   = btn.action
        local repl  = btn.replace
        local skipo = btn.skipOutro
        local b = widget.button{
            x = dlgW * 0.5 + cx - bw * 0.5,
            y = dlgH * 0.5 + cy - bh * 0.5,
            width = bw, height = bh,
            bgUp      = "button_up",
            bgDown    = "button_down",
            bgHover   = "button_hover",
            text       = btn.label,
            textAlign = ALIGN_CENTER + ALIGN_MIDDLE,
            onClick   = function()
                if repl then
                    local nextSpec = type(repl) == "function"
                                      and repl() or repl
                    M.replace(nextSpec)
                elseif skipo and act then
                    -- Skip the outro: fire the action right now. The
                    -- dialog stays rendered at rest until the action's
                    -- downstream effect (typically a scene fade) covers
                    -- it; the host scene should call dialog.dismiss()
                    -- from its :exit so the dialog state doesn't leak.
                    act()
                else
                    pendingAction = act
                    M.close()
                end
            end,
        }
        -- Dialogs are mouse-driven; pressing Enter / Space anywhere
        -- shouldn't fire arbitrary dialog buttons.
        b.focusable = false
        if spec.buttonsStartHidden then b.visible = false end
        buttons[#buttons + 1] = b
        dlg:add(b)
    end

    root:add(dlg)
    return root, dlg, dim, buttons
end

-- ---- Animation kickoff ---------------------------------------------------

-- skipDimFade = true when handing off from a previous dialog. The dim
-- already sits at DIM_ALPHA from the outgoing dialog and we want it to
-- stay there — fading it back up would look like a flicker.
local function startIntro(c, skipDimFade)
    if not skipDimFade then
        c.dim.action = anim.fadeTo(DIM_ALPHA, DIM_FADE_IN)
    end
    c.dlg.action = anim.moveTo(c.dlg.x, -(c.dlg.height * 0.5),
                                OPEN_DURATION, anim.bounceOut)
    c.dlg.onActionDone = function(self)
        c.state = STATE_OPEN
        c.t     = 0
    end
end

-- When pendingReplace is set we leave the dim at full alpha — the
-- next dialog's intro will be told to skip its own fade-in so the dim
-- stays visually continuous across the hand-off.
local function startOutro(c)
    local offY = -(c.dlg.height * 0.5) - START_OFFSET
    if not pendingReplace then
        c.dim.action = anim.fadeTo(0.0, DIM_FADE_OUT)
    end
    c.dlg.action = anim.moveTo(c.dlg.x, offY,
                                CLOSE_DURATION, easeInExpo)
    c.dlg.onActionDone = function(self)
        if pendingReplace then
            local nextSpec = pendingReplace
            pendingReplace = nil
            M.show(nextSpec, { skipDimFade = true })
        else
            current = nil
            if pendingAction then
                local a = pendingAction
                pendingAction = nil
                a()
            end
        end
    end
end

-- ---- Public API ----------------------------------------------------------

function M.isActive()
    return current ~= nil
end

-- opts.skipDimFade — start the dim at full alpha and skip the
-- intro fade. Used by the replace path so the dim doesn't flicker
-- when handing off between dialogs.
function M.show(spec, opts)
    opts = opts or {}
    local root, dlg, dim, buttons = buildTree(spec)
    if opts.skipDimFade then dim.alpha = DIM_ALPHA end
    current = {
        spec    = spec,
        state   = STATE_INTRO,
        t       = 0,
        root    = root,
        dlg     = dlg,
        dim     = dim,
        buttons = buttons,
    }
    startIntro(current, opts.skipDimFade)
    soundPlay(spec.appearSound or "dialog_open")
end

function M.close()
    if not current or current.state == STATE_OUTRO then return end
    current.state = STATE_OUTRO
    current.t     = 0
    startOutro(current)
    soundPlay(current.spec.closeSound or "dialog_close")
end

-- Swap the current dialog for nextSpec without dropping the dim. The
-- current dialog runs its normal outro, then on completion startOutro's
-- onActionDone detects pendingReplace and shows the new spec with
-- skipDimFade. If no dialog is active, falls back to a plain show().
function M.replace(nextSpec)
    if not current then
        M.show(nextSpec)
        return
    end
    pendingReplace = nextSpec
    M.close()
end

-- Clear all dialog state with no animation. Used when something else is
-- taking over the visual hand-off (a scene fade, e.g.) and we want the
-- dialog to vanish without playing its outro under the new effect.
-- Pair with a button's `skipOutro = true`: skipOutro fires the action
-- right away and leaves the dialog visible; the action's downstream
-- (scene transition) covers it, and the host calls dismiss() at the
-- right cleanup moment — usually scene:exit on the leaving scene.
function M.dismiss()
    current         = nil
    pendingAction  = nil
    pendingReplace = nil
end

-- Animate the dialog's buttons in (alpha 0→1, scale 0.7→1.0 with a small
-- overshoot). For specs built with buttonsStartHidden = true that defer
-- the button until a body animation finishes — e.g. the COMPLETED dialog
-- only offers "Next level >" once the score breakdown has counted up.
-- Idempotent-ish: safe to gate behind a one-shot flag in the caller.
function M.revealButtons()
    if not current or not current.buttons then return end
    for _, b in ipairs(current.buttons) do
        b.visible = true
        b.alpha   = 0
        b.scale   = 0.7
        b.action  = anim.parallel{
            anim.fadeIn(0.25),
            anim.scaleTo(1.0, 0.35, anim.easeOutBack),
        }
    end
end

function M.update(dt)
    if not current then return end
    current.t = current.t + dt
    current.root:update(dt)
end

function M.render()
    if not current then return end
    current.root:draw()
    -- Body content — the spec drives whatever else appears. introDone
    -- lets bodies stagger sub-animations after the dialog settles. The
    -- anchor passed in is the dialog's animated CENTER (not the TL).
    if current.spec.drawBody then
        local ax = 0
        local ay = current.dlg.y + current.dlg.height * 0.5
        current.spec.drawBody(current.state ~= STATE_INTRO,
                               current.t, ax, ay)
    end
end

-- ---- Input forwarding ----------------------------------------------------
--
-- Modal: every mouse event is swallowed. Buttons only respond while
-- the dialog is at rest (STATE_OPEN); intro / outro frames freeze
-- input so a click during the drop doesn't fire a button before the
-- player can see it land.

local function inputAlive()
    return current and current.state == STATE_OPEN
end

function M.handleMouseDown(x, y, button)
    if not current then return false end
    if inputAlive() then
        current.root:mouseDown(x, y, button)
    end
    return true   -- swallow either way
end

function M.handleMouseUp(x, y, button)
    if not current then return false end
    if inputAlive() then
        current.root:mouseUp(x, y, button)
    end
    return true
end

function M.handleMouseMove(x, y, dx, dy)
    if not current then return false end
    if inputAlive() then
        current.root:mouseMove(x, y, dx, dy)
    end
    return true
end

return M
