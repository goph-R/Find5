-- Find5 engine demo — exercises every binding so it's clear what works.
-- The actual difference-finder game is laid out in docs/game-plan.md;
-- when you start building it, replace this file.
--
-- Hooks (all optional):
--   on_start(), on_update(dt), on_render(),
--   on_keydown(name), on_keyup(name),
--   on_mousedown(x, y, button), on_mouseup(x, y, button),
--   on_mousemove(x, y, dx, dy)
--
-- Bindings:
--   draw_region(name, x, y [, opts])    -- opts: align, flip, fill_x/y, scale, alpha, color
--   draw_text(text, x, y [, opts])      -- opts: scale, font, align, color, alpha
--   draw_ellipse(cx, cy, rx, ry [, opts])  -- opts: start, finish, segments, thickness, color, alpha
--   key_down(name), mouse_pos(), mouse_down(button)
--   snd_play(name)
--   music_play(name [, fade [, loop]]), music_stop([fade]), music_volume(g)
--   ui_show_message(text [, seconds])

local player = { x = 0, y = 0, speed = 220 }
local t = 0                  -- demo timer
local found_t = nil          -- ellipse-drawing animation timer (nil = not active)

function on_start()
    ui_show_message("WASD/arrows move. Space = fade. F = find anim.", 5)
    music_play("title", 0.5, true)
end

function on_update(dt)
    t = t + dt
    if key_down("left")  or key_down("a") then player.x = player.x - player.speed * dt end
    if key_down("right") or key_down("d") then player.x = player.x + player.speed * dt end
    if key_down("up")    or key_down("w") then player.y = player.y - player.speed * dt end
    if key_down("down")  or key_down("s") then player.y = player.y + player.speed * dt end

    if found_t then
        found_t = found_t + dt
        if found_t > 1.5 then found_t = nil end
    end
end

function on_render()
    -- Logo with a slow pulse (scale wobble) and a sinking alpha while space is held.
    local pulse = 1.0 + 0.05 * math.sin(t * 3)
    local alpha = key_down("space") and (0.3 + 0.7 * (math.sin(t * 8) * 0.5 + 0.5)) or 1.0

    draw_region("logo", player.x, player.y, {
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        scale = pulse,
        alpha = alpha,
    })

    -- HUD-style label, top-left. White, default font.
    draw_text("Find5 engine demo", -310, -230, { scale = 1.5 })

    -- Centered title, orbitron font, semi-transparent.
    draw_text("press F to trigger find animation", 0, 200, {
        scale = 1.5,
        align = ALIGN_CENTER + ALIGN_MIDDLE,
        color = { 1.0, 1.0, 0.6, 0.8 },
    })

    -- Ellipse "drawing" animation: when found_t is active, sweep finish from 0 to 1.
    if found_t then
        local p = found_t / 0.6                  -- 0..1 over 0.6 seconds
        if p > 1 then p = 1 end
        local fade = 1 - math.max(0, (found_t - 0.8) / 0.7)  -- fade after 0.8s
        draw_ellipse(player.x, player.y, 80, 30, {
            finish    = p,
            thickness = 3.0,
            color     = { 1.0, 0.3, 0.3, fade },
            segments  = 80,
        })
    end
end

function on_keydown(name)
    if name == "space" then snd_play("jump") end
    if name == "f"     then found_t = 0 end       -- kick off ellipse animation
end

function on_mousedown(x, y, button)
    if button == 1 then
        found_t = 0
        player.x, player.y = x, y                  -- teleport sprite to click
    end
end
