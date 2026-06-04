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
		placholder  = "assets/sounds/jump.wav",
        -- Random-pick groups: name = { "path1", "path2", ... } picks a
        -- uniformly-random non-repeating variant each call.
        -- steps = { "assets/sounds/step1.wav", "assets/sounds/step2.wav" },
    },

    -- Streaming Ogg Vorbis tracks for musicPlay(name [, fade [, loop]]).
    -- Files are opened lazily on the first musicPlay.
    music = {
        title = "assets/music/title.ogg"
    },

    textures = {
        menu_ui    = "assets/textures/menu_ui.png",
        menu_bg    = "assets/textures/menu_bg.png",
        game_ui    = "assets/textures/game_ui.png",
		dialog_bg  = "assets/textures/dialog_bg.png",
		categories = "assets/textures/categories.png",
		numbers    = "assets/textures/numbers.png",
        image_1a   = "assets/textures/image_1a.png",
        image_1b   = "assets/textures/image_1b.png",
    },

    -- Regions are sub-rectangles of textures, addressed by name from
    -- drawRegion(). x, y, w, h are pixels of the source texture (not
    -- normalized). For a full-image region, use 0, 0 and the texture's
    -- natural size. Atlases pack many regions into one texture.
    regions = {
	
		menu_bg = { tex = "menu_bg", x = 0, y = 0, w = 512, h = 512 },
		
		logo                = { tex = "menu_ui", x = 0, y = 0, w = 442, h = 148 },
		category_box        = { tex = "menu_ui", x = 0, y = 150, w = 177, h = 177 },
		button2_up          = { tex = "menu_ui", x = 178, y = 150, w = 90, h = 91 },
		button2_down        = { tex = "menu_ui", x = 269, y = 150, w = 90, h = 91 },
		button2_hover       = { tex = "menu_ui", x = 360, y = 150, w = 90, h = 91 },
		button_up           = { tex = "menu_ui", x = 451, y = 150, w = 41, h = 42,
		                        slice = { x1 = 8, x2 = 33, y1 = 8, y2 = 34 } },
		button_down         = { tex = "menu_ui", x = 451, y = 193, w = 41, h = 42,
		                        slice = { x1 = 8, x2 = 33, y1 = 8, y2 = 34 } },
		button_hover        = { tex = "menu_ui", x = 451, y = 236, w = 41, h = 42,
		                        slice = { x1 = 8, x2 = 33, y1 = 8, y2 = 34 } },
		close_icon          = { tex = "menu_ui", x = 451, y = 279, w = 21, h = 23 },
		joker_icon          = { tex = "menu_ui", x = 451, y = 302, w = 22, h = 23 },
		pause_icon          = { tex = "menu_ui", x = 454, y = 327, w = 16, h = 15 },
		left_icon           = { tex = "menu_ui", x = 178, y = 242, w = 27, h = 46 },
		left_disabled_icon  = { tex = "menu_ui", x = 178, y = 289, w = 27, h = 46 },
		right_icon          = { tex = "menu_ui", x = 206, y = 242, w = 27, h = 46 },
		right_disabled_icon = { tex = "menu_ui", x = 206, y = 289, w = 27, h = 46 },
		sound_on_icon       = { tex = "menu_ui", x = 234, y = 242, w = 53, h = 62 },
		sound_off_icon      = { tex = "menu_ui", x = 234, y = 305, w = 53, h = 62 },
		music_on_icon       = { tex = "menu_ui", x = 287, y = 242, w = 67, h = 50 },
		music_off_icon      = { tex = "menu_ui", x = 287, y = 293, w = 67, h = 50 },
		
		category_medieval   = { tex = "categories", x = 0, y = 0, w = 175, h = 175 },
		
		dialog_bg_top    = { tex = "dialog_bg", x = 0, y = 0, w = 461, h = 279 },
		dialog_bg_bottom = { tex = "dialog_bg", x = 0, y = 279, w = 461, h = 24 },
		dialog_chain     = { tex = "dialog_bg", x = 461, y = 0, w = 43, h = 512 },
		
        star       = { tex = "game_ui", x = 1, y = 1, w = 40, h = 40 },
        star_bg    = { tex = "game_ui", x = 42, y = 1, w = 40, h = 40 },
        timebar    = { tex = "game_ui", x = 1, y = 44, w = 264, h = 22 },
        timebar_bg = { tex = "game_ui", x = 1, y = 67, w = 266, h = 24 },
        image_bg   = { tex = "game_ui", x = 1, y = 92, w = 287, h = 417 },
		
		number_1 = { tex = "numbers", x =   0, y = 0, w = 111, h = 185 },
		number_2 = { tex = "numbers", x = 112, y = 0, w = 152, h = 185 },
		number_3 = { tex = "numbers", x = 265, y = 0, w = 151, h = 185 },
		
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
