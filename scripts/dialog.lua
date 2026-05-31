-- Find5 — modal dialog system (widget-based).
--
-- A single dialog at a time. Drops in from above with bounce_out (two
-- visible re-impacts before settling); shoots back up out the top on
-- close with ease_in_expo (slow start, exponential acceleration). A
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
--          ├─ widget.image  "dialog_bg_top"     (marble body; fill_y-clippable)
--          ├─ widget.image  "dialog_bg_bottom"  (static base strip below top)
--          ├─ title label   (large font, centered)
--          └─ widget.button (one per spec.buttons entry)
--
-- Spec fields:
--   title          string                — drawn near the top, large font
--   appear_sound   string  ("dialog_open")
--   close_sound    string  ("dialog_close")
--   w              number  — dialog width, default 460
--   height         number  — MARBLE BODY height (top region) in px.
--                            Capped at dialog_bg_top's native height; below
--                            that, clipped from the bottom edge via fill_y
--                            (same trick as the timebar). Total dialog
--                            visual height = height + dialog_bg_bottom's
--                            native height (the bottom strip is static).
--                            Default: top region's native height (no clip).
--   buttons        array of { x, y, w, h, label, action | replace, skip_outro }
--                   positions in dialog-local coords (origin = dialog CENTER).
--                   `action`  — function fired AFTER the outro animation
--                              completes. Latched in pending_action;
--                              dlg.on_action_done fires it. Dim fades
--                              out on close.
--                   `replace` — spec (or factory function returning a
--                              spec) for a follow-up dialog. The current
--                              dialog slides out WITHOUT fading the dim,
--                              the new one slides in without fading the
--                              dim back up — seamless dialog-to-dialog
--                              hand-off. Takes precedence over `action`.
--                   `skip_outro` — boolean. When true, on_click fires
--                              `action` IMMEDIATELY (no outro animation,
--                              no dim fade); the dialog keeps rendering
--                              at rest until something else hides it.
--                              Pair with dialog.dismiss() at the right
--                              cleanup moment (typically scene:exit())
--                              so the action's downstream effect — a
--                              scene fade-to-black, say — owns the
--                              visual hand-off without the dialog
--                              playing a redundant outro underneath.
--   draw_body      function(intro_done, t, anchor_x, anchor_y)
--                   called every frame after the widget tree draws;
--                   (anchor_x, anchor_y) is the dialog's CENTER on screen,
--                   including the animation offset.
--
-- Input contract: while is_active(), the host should route
-- handle_mousedown / handle_mouseup / handle_mousemove for every mouse
-- event — buttons need both press AND release to complete a click, and
-- mousemove drives hover. Events outside STATE_OPEN are swallowed (no
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
-- inside build_tree via region_size since region tables aren't queryable
-- at file-load time.

-- Chain horizontal anchors as fractions of dialog width — chain centres
-- land at 1/4 and 3/4 across, symmetric. Vertical: a small overlap so
-- the chain tucks under the dialog top edge (z-order does the hiding).
local CHAIN_LEFT_FRAC  = 0.2
local CHAIN_RIGHT_FRAC = 0.8
local CHAIN_OVERLAP_PX = 10

-- ---- Easing --------------------------------------------------------------
--
-- Robert Penner's ease_in_expo — slow start, exponential acceleration.
-- Matches the "shoots off the top" feel the user asked for on close.
-- Lives here rather than in engine.animation because it's the only
-- caller; promote later if anything else wants it.
local function ease_in_expo(p)
    if p <= 0 then return 0 end
    return math.pow(2, 10 * (p - 1))
end

-- ---- Internal state ------------------------------------------------------
local current         = nil    -- { spec, state, t, root, dlg, dim }
local pending_action  = nil    -- latched in on_click, fires after outro
local pending_replace = nil    -- spec to show next; dim stays at full

-- ---- Custom mini-widget: flat colour quad with animatable alpha ----------
--
-- The dim backdrop needs a draw method that engine.widget doesn't
-- ship (a fullscreen quad). Same interface as every other widget
-- (visible / alpha / scale / draw / hit / mouse* / key*) so panel:draw
-- cascades alpha through it the same way.

local function make_quad_widget(x, y, w, h, color)
    local q = {
        x = x, y = y, width = w, height = h,
        color = color,
        visible = true, disabled = false, focusable = false,
        alpha = 1.0, scale = 1.0,
    }
    function q:draw()
        if not self.visible or self.alpha <= 0 then return end
        local c = self.color
        draw_quad(self.x, self.y, self.width, self.height, {
            color = { c[1], c[2], c[3], (c[4] or 1.0) * self.alpha },
        })
    end
    function q:hit()       return false end
    function q:mousedown() return false end
    function q:mouseup()   return false end
    function q:mousemove() end
    function q:keydown()   return false end
    function q:keyup()     return false end
    return q
end

-- ---- Tree construction ---------------------------------------------------

local function build_tree(spec)
    local vw, vh = view_size()
    local dlg_w  = spec.w or DEFAULT_W

    -- Top region clips with fill_y when the requested marble height is
    -- below its native pixel height (same mechanism the timebar uses for
    -- fill_x — both source UVs and dst shrink in lockstep). Above native
    -- there's no marble pattern to extend, so we cap.
    local _, top_native_h    = region_size("dialog_bg_top")
    local _, bottom_native_h = region_size("dialog_bg_bottom")
    local top_h = spec.height or top_native_h
    if top_h > top_native_h then top_h = top_native_h end
    local top_fill = top_h / top_native_h
    -- TOTAL dialog visual height includes the static bottom strip.
    -- Animation positions and button anchors track this, not top_h alone.
    local dlg_h = top_h + bottom_native_h

    -- Dialog panel uses TOP-LEFT origin so its bbox encloses the
    -- buttons (click-to-focus needs the bbox to contain hit children).
    -- The chains hang above the bbox at negative local y; that's
    -- draw-only so the bbox doesn't matter for them.
    local rest_y  = -dlg_h * 0.5
    local start_y = rest_y - START_OFFSET

    local root = widget.panel{ x = 0, y = 0, width = vw, height = vh }

    -- Dim: black fullscreen quad. alpha tweens 0 → DIM_ALPHA on intro,
    -- back to 0 on outro. Independent of the dlg panel's transform.
    local dim = make_quad_widget(-vw * 0.5, -vh * 0.5, vw, vh, { 0, 0, 0, 1 })
    dim.alpha = 0
    root:add(dim)

    local dlg = widget.panel{
        x = -dlg_w * 0.5, y = start_y,
        width = dlg_w, height = dlg_h,
    }

    -- Chains — drawn FIRST so the marble top occludes the part that
    -- overlaps the dialog top edge (z-order does the tuck). Two copies
    -- of the single dialog_chain region, centred at CHAIN_LEFT/RIGHT
    -- across. Vertical: bottom sits CHAIN_OVERLAP_PX below the dialog
    -- top so the chain visibly anchors into the bg instead of just
    -- touching.
    local chain_w, chain_h = region_size("dialog_chain")
    local chain_y = CHAIN_OVERLAP_PX - chain_h
    dlg:add(widget.image{
        x = dlg_w * CHAIN_LEFT_FRAC  - chain_w * 0.5,
        y = chain_y, region = "dialog_chain",
    })
    dlg:add(widget.image{
        x = dlg_w * CHAIN_RIGHT_FRAC - chain_w * 0.5,
        y = chain_y, region = "dialog_chain",
    })

    -- Marble body — covers the chain tails that crossed the top edge.
    -- height stays at native; fill_y handles the actual visual clip so
    -- both source UVs and dst pixels shrink together. The widget's
    -- on-screen height ends up at top_h.
    dlg:add(widget.image{
        x = 0, y = 0, region = "dialog_bg_top",
        width = dlg_w, height = top_native_h,
        fill_y = top_fill,
    })

    -- Static bottom strip — sits flush against the bottom of the
    -- (possibly-clipped) marble. Native height, never clipped.
    dlg:add(widget.image{
        x = 0, y = top_h, region = "dialog_bg_bottom",
        width = dlg_w, height = bottom_native_h,
    })

    -- Title — visible from frame 1 of the intro.
    if spec.title then
        dlg:add(widget.label{
            x = dlg_w * 0.5, y = 40,
            width = 0, height = 0,
            text  = spec.title,
            font  = "large",
            align = ALIGN_CENTER + ALIGN_MIDDLE,
            color = { 1, 1, 1 },
        })
    end

    -- Buttons. spec.buttons[i].x/y are CENTER offsets from the dialog
    -- center; translate to panel-local top-left coords. The on_click
    -- closure either:
    --   * `replace` set → hand off to M.replace, no dim fade between
    --     dialogs (resolve a function-form replace lazily so two specs
    --     can cross-reference each other without an init cycle);
    --   * else → latch `action` into pending_action and start a normal
    --     close; dlg.on_action_done fires the action once outro lands.
    for _, btn in ipairs(spec.buttons or {}) do
        local bw    = btn.w or 200
        local bh    = btn.h or 48
        local cx    = btn.x or 0
        local cy    = btn.y or 0
        local act   = btn.action
        local repl  = btn.replace
        local skipo = btn.skip_outro
        local b = widget.button{
            x = dlg_w * 0.5 + cx - bw * 0.5,
            y = dlg_h * 0.5 + cy - bh * 0.5,
            width = bw, height = bh,
            bg_up      = "button_up",
            bg_down    = "button_down",
            bg_hover   = "button_hover",
            text       = btn.label,
            text_align = ALIGN_CENTER + ALIGN_MIDDLE,
            on_click   = function()
                if repl then
                    local next_spec = type(repl) == "function"
                                      and repl() or repl
                    M.replace(next_spec)
                elseif skipo and act then
                    -- Skip the outro: fire the action right now. The
                    -- dialog stays rendered at rest until the action's
                    -- downstream effect (typically a scene fade) covers
                    -- it; the host scene should call dialog.dismiss()
                    -- from its :exit so the dialog state doesn't leak.
                    act()
                else
                    pending_action = act
                    M.close()
                end
            end,
        }
        -- Dialogs are mouse-driven; pressing Enter / Space anywhere
        -- shouldn't fire arbitrary dialog buttons.
        b.focusable = false
        dlg:add(b)
    end

    root:add(dlg)
    return root, dlg, dim
end

-- ---- Animation kickoff ---------------------------------------------------

-- skip_dim_fade = true when handing off from a previous dialog. The dim
-- already sits at DIM_ALPHA from the outgoing dialog and we want it to
-- stay there — fading it back up would look like a flicker.
local function start_intro(c, skip_dim_fade)
    if not skip_dim_fade then
        c.dim.action = anim.fade_to(DIM_ALPHA, DIM_FADE_IN)
    end
    c.dlg.action = anim.move_to(c.dlg.x, -(c.dlg.height * 0.5),
                                OPEN_DURATION, anim.bounce_out)
    c.dlg.on_action_done = function(self)
        c.state = STATE_OPEN
        c.t     = 0
    end
end

-- When pending_replace is set we leave the dim at full alpha — the
-- next dialog's intro will be told to skip its own fade-in so the dim
-- stays visually continuous across the hand-off.
local function start_outro(c)
    local off_y = -(c.dlg.height * 0.5) - START_OFFSET
    if not pending_replace then
        c.dim.action = anim.fade_to(0.0, DIM_FADE_OUT)
    end
    c.dlg.action = anim.move_to(c.dlg.x, off_y,
                                CLOSE_DURATION, ease_in_expo)
    c.dlg.on_action_done = function(self)
        if pending_replace then
            local next_spec = pending_replace
            pending_replace = nil
            M.show(next_spec, { skip_dim_fade = true })
        else
            current = nil
            if pending_action then
                local a = pending_action
                pending_action = nil
                a()
            end
        end
    end
end

-- ---- Public API ----------------------------------------------------------

function M.is_active()
    return current ~= nil
end

-- opts.skip_dim_fade — start the dim at full alpha and skip the
-- intro fade. Used by the replace path so the dim doesn't flicker
-- when handing off between dialogs.
function M.show(spec, opts)
    opts = opts or {}
    local root, dlg, dim = build_tree(spec)
    if opts.skip_dim_fade then dim.alpha = DIM_ALPHA end
    current = {
        spec  = spec,
        state = STATE_INTRO,
        t     = 0,
        root  = root,
        dlg   = dlg,
        dim   = dim,
    }
    start_intro(current, opts.skip_dim_fade)
    snd_play(spec.appear_sound or "dialog_open")
end

function M.close()
    if not current or current.state == STATE_OUTRO then return end
    current.state = STATE_OUTRO
    current.t     = 0
    start_outro(current)
    snd_play(current.spec.close_sound or "dialog_close")
end

-- Swap the current dialog for next_spec without dropping the dim. The
-- current dialog runs its normal outro, then on completion start_outro's
-- on_action_done detects pending_replace and shows the new spec with
-- skip_dim_fade. If no dialog is active, falls back to a plain show().
function M.replace(next_spec)
    if not current then
        M.show(next_spec)
        return
    end
    pending_replace = next_spec
    M.close()
end

-- Clear all dialog state with no animation. Used when something else is
-- taking over the visual hand-off (a scene fade, e.g.) and we want the
-- dialog to vanish without playing its outro under the new effect.
-- Pair with a button's `skip_outro = true`: skip_outro fires the action
-- right away and leaves the dialog visible; the action's downstream
-- (scene transition) covers it, and the host calls dismiss() at the
-- right cleanup moment — usually scene:exit on the leaving scene.
function M.dismiss()
    current         = nil
    pending_action  = nil
    pending_replace = nil
end

function M.update(dt)
    if not current then return end
    current.t = current.t + dt
    current.root:update(dt)
end

function M.render()
    if not current then return end
    current.root:draw()
    -- Body content — the spec drives whatever else appears. intro_done
    -- lets bodies stagger sub-animations after the dialog settles. The
    -- anchor passed in is the dialog's animated CENTER (not the TL).
    if current.spec.draw_body then
        local ax = 0
        local ay = current.dlg.y + current.dlg.height * 0.5
        current.spec.draw_body(current.state ~= STATE_INTRO,
                               current.t, ax, ay)
    end
end

-- ---- Input forwarding ----------------------------------------------------
--
-- Modal: every mouse event is swallowed. Buttons only respond while
-- the dialog is at rest (STATE_OPEN); intro / outro frames freeze
-- input so a click during the drop doesn't fire a button before the
-- player can see it land.

local function input_alive()
    return current and current.state == STATE_OPEN
end

function M.handle_mousedown(x, y, button)
    if not current then return false end
    if input_alive() then
        current.root:mousedown(x, y, button)
    end
    return true   -- swallow either way
end

function M.handle_mouseup(x, y, button)
    if not current then return false end
    if input_alive() then
        current.root:mouseup(x, y, button)
    end
    return true
end

function M.handle_mousemove(x, y, dx, dy)
    if not current then return false end
    if input_alive() then
        current.root:mousemove(x, y, dx, dy)
    end
    return true
end

return M
