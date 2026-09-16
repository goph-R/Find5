/* Find5 — entry point.
 *
 * Everything the game does lives in Lua (scripts/main.lua) and in the manifests
 * beside it: app.lua (identity), assets.lua (content), config.lua (display).
 * The whole C host — SDL/GL boot, the 2D frame loop, audio, screenshots,
 * shutdown — is soobRun() in ../SOOB-Core/soob_main.h, shared with every other
 * 2D SOOB game.
 *
 * Two knobs live here and nowhere else, both compile-time by nature:
 *   UI_VIRTUAL_H  virtual canvas height; Find5 uses the 480 default, matching
 *                 its 4:3 / 640x480 design target. #define it before the
 *                 include to change it.
 *   SoobApp       native Lua bindings, if a game has any. Find5 has none —
 *                 find5StartGame / find5RequestQuit are pure-Lua globals.
 */

#include "soob_main.h"

int main(int argc, char *argv[])
{
    return soobRun(argc, argv, 0);
}
