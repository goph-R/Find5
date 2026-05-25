-- scripts/levels.lua
-- Level / category / diff data for Find5. Diff rects are authored with
-- tools/diffs.html; everything else (run shape, joker budget, etc.) is
-- global and shared across categories so highscores stay comparable.
--
-- Currently a single category with a single image pair. Multi-category
-- and randomised image pools land alongside the title screen.

return {
    -- Run shape — same across all categories.
    level_count = 10,             -- levels played per run
    time_start  = 60.0,           -- seconds budgeted on level 1
    time_end    = 25.0,           -- seconds budgeted on the last level (linear lerp)
    diff_count  = 5,              -- diffs per image pair (matches the star slots)
    joker_max   = 5,              -- jokers per run

    categories = {
        {
            id    = "portraits",
            title = "Portraits",
            images = {
                {
                    -- `pair` resolves to texture regions image_<pair>a / image_<pair>b.
                    pair  = "1",
                    diffs = {
                        { x =  50, y =  66, w = 42, h = 44 },
                        { x = 195, y = 133, w = 27, h = 24 },
                        { x = 166, y = 246, w = 36, h = 40 },
                        { x =  22, y = 264, w = 32, h = 31 },
                        { x =   2, y = 180, w = 57, h = 36 },
                    },
                },
            },
        },
    },
}
