-- config.lua — read once at startup, before SDL / OpenGL init.
--
-- Precedence: built-in defaults < config.lua < command-line args.
-- Command-line flags that override these:
--   -w N         set width
--   -h N         set height
--   -fullscreen  force fullscreen on
--   -windowed    force fullscreen off
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
        width      = 640,
        height     = 480,
        fullscreen = false,
    },
}
