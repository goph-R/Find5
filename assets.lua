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
        menu_ui    = "assets/textures/menu_ui.png",
        menu_bg    = "assets/textures/menu_bg.png",
        game_ui    = "assets/textures/game_ui.png",
		dialog_bg  = "assets/textures/dialog_bg.png",
		categories = "assets/textures/categories.png",
        image_1a   = "assets/textures/image_1a.png",
        image_1b   = "assets/textures/image_1b.png",
    },

    -- Regions are sub-rectangles of textures, addressed by name from
    -- draw_region(). x, y, w, h are pixels of the source texture (not
    -- normalized). For a full-image region, use 0, 0 and the texture's
    -- natural size. Atlases pack many regions into one texture.
    regions = {
	
		menu_bg = { tex = "menu_bg", x = 0, y = 0, w = 512, h = 512 },
		
		logo                = { tex = "menu_ui", x = 0, y = 0, w = 442, h = 148 },
		category_box        = { tex = "menu_ui", x = 0, y = 148, w = 177, h = 177 },
		button2_up          = { tex = "menu_ui", x = 178, y = 148, w = 90, h = 91 },
		button2_down        = { tex = "menu_ui", x = 269, y = 148, w = 90, h = 91 },
		button2_hover       = { tex = "menu_ui", x = 360, y = 148, w = 90, h = 91 },
		button_up           = { tex = "menu_ui", x = 451, y = 148, w = 41, h = 42,
		                        slice = { x1 = 8, x2 = 33, y1 = 8, y2 = 34 } },
		button_down         = { tex = "menu_ui", x = 451, y = 191, w = 41, h = 42,
		                        slice = { x1 = 8, x2 = 33, y1 = 8, y2 = 34 } },
		button_hover        = { tex = "menu_ui", x = 451, y = 234, w = 41, h = 42,
		                        slice = { x1 = 8, x2 = 33, y1 = 8, y2 = 34 } },
		close_icon          = { tex = "menu_ui", x = 451, y = 277, w = 21, h = 23 },
		left_icon           = { tex = "menu_ui", x = 178, y = 240, w = 27, h = 46 },
		left_disabled_icon  = { tex = "menu_ui", x = 178, y = 287, w = 27, h = 46 },
		right_icon          = { tex = "menu_ui", x = 206, y = 240, w = 27, h = 46 },
		right_disabled_icon = { tex = "menu_ui", x = 206, y = 287, w = 27, h = 46 },
		sound_on_icon       = { tex = "menu_ui", x = 234, y = 240, w = 53, h = 62 },
		sound_off_icon      = { tex = "menu_ui", x = 234, y = 303, w = 53, h = 62 },
		music_on_icon       = { tex = "menu_ui", x = 287, y = 240, w = 67, h = 50 },
		music_off_icon      = { tex = "menu_ui", x = 287, y = 291, w = 67, h = 50 },
		
		category_medieval   = { tex = "categories", x = 0, y = 0, w = 175, h = 175 },
		
		dialog_bg    = { tex = "dialog_bg", x = 0, y = 0, w = 461, h = 307 },
		dialog_chain = { tex = "dialog_bg", x = 0, y = 303, w = 43, h = 168 },
		
        star              = { tex = "game_ui", x = 1, y = 1, w = 40, h = 40 },
        star_empty        = { tex = "game_ui", x = 42, y = 1, w = 40, h = 40 },
        pause_button_up   = { tex = "game_ui", x = 83, y = 1, w = 42, h = 42 },
        pause_button_down = { tex = "game_ui", x = 126, y = 1, w = 42, h = 42 },
        joker_button_up   = { tex = "game_ui", x = 169, y = 1, w = 42, h = 42 },
        joker_button_down = { tex = "game_ui", x = 212, y = 1, w = 42, h = 42 },
        timebar           = { tex = "game_ui", x = 1, y = 44, w = 264, h = 22 },
        timebar_bg        = { tex = "game_ui", x = 1, y = 67, w = 266, h = 24 },
        image_bg          = { tex = "game_ui", x = 1, y = 92, w = 287, h = 417 },
		
        image_1a  = { tex = "image_1a", x = 0, y = 0, w = 285, h = 415 },
        image_1b  = { tex = "image_1b", x = 0, y = 0, w = 285, h = 415 },
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
