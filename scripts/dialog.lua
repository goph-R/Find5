-- Find5's dialog theme.
--
-- engine.dialog owns the machinery (drop-in bounce, shoot-up exit, the dim
-- backdrop, the pendingAction / replace / skipOutro hand-offs). This file only
-- names Find5's marble artwork and hands the module straight back, so every
-- `require "dialog"` in this repo keeps working unchanged.
--
-- The marble background is a clippable body region above a fixed base strip:
-- a spec's `height` is the BODY height, and the two chains hang above the top
-- edge with 10px tucked under it. That composition is a property of this
-- artwork, which is why it lives here and not in the engine.
--
-- Sounds and button regions need no override — assets.lua already registers
-- them under engine.dialog's default names (dialog_open / dialog_close /
-- button_up / button_down / button_hover).

local dialog = require "engine.dialog"

dialog.setDefaults{
    width      = 460,
    background = { kind   = "top_bottom",
                   top    = "dialog_bg_top",
                   bottom = "dialog_bg_bottom" },
    decor      = { { region = "dialog_chain", xFrac = 0.2, overlap = 10 },
                   { region = "dialog_chain", xFrac = 0.8, overlap = 10 } },
}

return dialog
