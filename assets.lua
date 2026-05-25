-- Asset manifest for Find5.
--
-- Lists logical name -> file path for every game asset. Loaded at
-- startup by scriptLoadAssets (script.h), which walks each subtable
-- and populates the engine-side registries (SoundLibrary for `sounds`,
-- MusicLibrary for `music`, AssetRegistry for `textures`, UiFontLib
-- for `fonts`).
--
-- Unknown names fall through as raw paths so one-offs still work
-- without registering. File paths are relative to the repo root.

return {
    sounds = {
        jump = "assets/sounds/jump.wav",
        -- Random-pick groups: name = { "path1", "path2", ... } picks a
        -- uniformly-random non-repeating variant each call.
        -- steps = { "assets/sounds/step1.wav", "assets/sounds/step2.wav" },
    },

    -- Streaming Ogg Vorbis tracks for music_play(name [, fade [, loop]]).
    -- Files are opened lazily on the first music_play.
    music = {
        title   = "assets/music/title.ogg",
        ambient = "assets/music/ambient_loop.ogg",
    },

    textures = {
        sprite     = "assets/textures/logo.png",
        menu_bg    = "assets/textures/menu_bg.png",
        loading_bg = "assets/textures/loading_bg.png",
    },

    -- Regions are sub-rectangles of textures, addressed by name from
    -- draw_region(). x, y, w, h are pixels of the source texture (not
    -- normalized). For a full-image region, use 0, 0 and the texture's
    -- natural size. Atlases pack many regions into one texture.
    regions = {
        logo = { tex = "sprite", x = 0, y = 0, w = 256, h = 64 },
    },

    -- BMFont (AngelCode) bitmap fonts. Each entry points at a .fnt text file;
    -- the .fnt carries the atlas filename (a 32-bit RGBA PNG in the same
    -- directory) and per-glyph metrics. "default" is the font used when a
    -- uiText call passes no explicit font name.
    fonts = {
        default = "assets/fonts/forgotten-futurist-22.fnt",
        large   = "assets/fonts/forgotten-futurist-40.fnt"        
    },
}
