-- app.lua — who this game is, read by every SOOB-Core host.
--
-- The single place a game names itself. The desktop build titles its window
-- and picks its per-user save path from this; the web build feeds its <title>,
-- its PWA manifest and its localStorage key from it; the Android player names
-- its options file and picks its screen orientation from it. Nothing else is
-- per-game — assets live in assets.lua, display settings in config.lua.
--
--   name        window title / app label / PWA name
--   id          persistence stem: find5.dat, and the localStorage key on web
--   orientation "landscape" | "portrait" — a hint for mobile hosts; desktop
--               ignores it (config.lua sizes the window there)
--   description one line, used by the web app manifest

return {
    name        = "Find5",
    id          = "find5",
    orientation = "landscape",
    description = "Spot the difference — a SOOB-Core game.",
}
