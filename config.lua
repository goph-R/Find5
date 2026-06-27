-- config.lua — read once at startup, before SDL / OpenGL init.
--
-- Precedence: built-in defaults < config.lua < command-line args.
-- Command-line flags that override these:
--   -w N         set width
--   -h N         set height
--   -fullscreen  force fullscreen on
--   -windowed    force fullscreen off
--   -opengl      force the GL renderer
--   -software    force the CPU renderer
--
-- render = "opengl" | "software"
--   "opengl"   — hardware (default); needs a 3D accelerator / GL driver.
--   "software" — pure-CPU rasterizer for machines with no 3D acceleration
--                (Pentium-class). Always 640x480, no UI stretching. Sprite
--                rotation is not yet implemented in this path (draws upright).
--
-- depth = 16 | 32  (software only; ignored under OpenGL)
--   16 — RGB565 backbuffer. Halves the per-frame copy to the screen — the real
--        bottleneck on a Pentium — at a small colour-banding cost. Recommended
--        for the P166 target.
--   32 — full colour (default).
--
-- Set width or height to 0 to use the current desktop resolution.
-- That sentinel is only honored when fullscreen = true; in windowed
-- mode the engine falls back to the minimum (320×240).
--
-- The UI virtual canvas is 480 units tall; virtual width adapts to
-- the window's aspect ratio. At 16:9 the visible area is wider than
-- the 640×480 design rect — UI elements stay center-anchored and the
-- background covers the full view (use drawBg in Lua for the cover
-- math).

return {
    display = {
        width      = 1024,
        height     = 768,
        fullscreen = false,
        render     = "opengl",   -- or "software"
        depth      = 32,         -- or 16
    },
}
