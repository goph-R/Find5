/* Find5 — minimal 2D game engine starter.
 *
 * Forked from SDLFun with all 3D / FPS / physics / model-loading code
 * stripped. What's left: SDL 1.2, OpenGL (fixed-function, 2D ortho),
 * OpenAL (sound effects + streaming OGG music), Lua 5.1 (asset manifest
 * + onStart hook), stb_image (PNG loader).
 *
 * Target span — same as SDLFun: from Windows 98 / Dev-C++ MinGW 3.4 up
 * through modern Linux & Win10. No C++11. No shaders.
 *
 * Demo: loads a sprite via the Lua asset manifest, draws it centered
 * with a slow vertical bob, plays the title OGG, shows a UI message.
 */

#ifdef _WIN32
#include <SDL/SDL.h>
#else
#include <SDL.h>
#endif
#include <GL/gl.h>
#include <cstdlib>
#include <cstdio>
#include <cstdarg>
#include <ctime>
#include <math.h>

/* 4:3 / 480p default — matches Find5's 640x480 design target. */
static int SCREEN_W = 640;
static int SCREEN_H = 480;
static const int SAMPLE_RATE = 44100;

/* Forward-declared logger used throughout the engine headers (texture.h,
   ui.h, sound.h, music.h, script.h all call conLogf). Definition below
   the includes — just a printf wrapper here; no Quake-style dev console
   in this minimal build. */
static void conLogf(const char *fmt, ...);

#include "texture.h"
#include "ui.h"
#include "sound.h"
#include "music.h"
#include "asset_registry.h"
#include "script.h"
#include "config.h"

static void conLogf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
    fflush(stdout);
}

/* ---- Win32 fullscreen refresh-rate workaround ----
 * SDL 1.2's fullscreen path calls ChangeDisplaySettings without a
 * frequency, dropping the monitor to 60Hz. Sample the desktop rate
 * before SDL_Init and reapply it with ChangeDisplaySettingsEx after
 * SDL_SetVideoMode. Same fix as SDLFun. No-op on Linux. */
#ifdef _WIN32
#include <windows.h>
static int g_desktopHz = 0;
static void saveDesktopRefreshHz(void)
{
    DEVMODE dm;
    ZeroMemory(&dm, sizeof(dm));
    dm.dmSize = sizeof(dm);
    if (EnumDisplaySettings(NULL, ENUM_REGISTRY_SETTINGS, &dm)) {
        g_desktopHz = (int)dm.dmDisplayFrequency;
    }
}
static void applyFullscreenRefreshHz(int width, int height)
{
    if (g_desktopHz <= 0) return;
    DEVMODE dm;
    ZeroMemory(&dm, sizeof(dm));
    dm.dmSize = sizeof(dm);
    dm.dmPelsWidth        = width;
    dm.dmPelsHeight       = height;
    dm.dmBitsPerPel       = 32;
    dm.dmDisplayFrequency = g_desktopHz;
    dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFREQUENCY;
    LONG r = ChangeDisplaySettingsEx(NULL, &dm, NULL, CDS_FULLSCREEN, NULL);
    if (r != DISP_CHANGE_SUCCESSFUL) {
        conLogf("refresh: ChangeDisplaySettingsEx(%dHz) failed: %ld\n", g_desktopHz, (long)r);
    }
}
#else
static void saveDesktopRefreshHz(void) {}
static void applyFullscreenRefreshHz(int, int) {}
#endif

/* DPI awareness — included after <windows.h> so its careful late ordering is
   preserved; self-guarded and a no-op on non-Win32. */
#include "dpi.h"

int main(int argc, char *argv[])
{
    /* Tell modern Windows we render in real pixels, before SDL touches the
       display — otherwise a non-100% display scale makes SDL_GetVideoInfo
       report a virtualised desktop and fullscreen oversizes. Safe no-op on
       old Windows (and Linux): see dpi.h. */
    dpiSetProcessAware();

    /* Display config: built-in defaults → config.lua → CLI args → clamp.
       Width/height of 0 is a sentinel for "use desktop resolution",
       resolved below once SDL knows the desktop size. */
    Config cfg = configLoadDefaults();
    configLoadFromFile(&cfg, "config.lua");
    configApplyArgs(&cfg, argc, argv);
    configClamp(&cfg);
    SCREEN_W = cfg.width;
    SCREEN_H = cfg.height;
    int fullscreen = cfg.fullscreen;

    saveDesktopRefreshHz();
    srand((unsigned)time(NULL));

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        conLogf("SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    /* Resolve the "0 = desktop" sentinel for fullscreen mode.
       SDL_GetVideoInfo()->current_w/h returns the desktop size BEFORE
       SDL_SetVideoMode has been called (SDL 1.2.10+). */
    if (fullscreen) {
        const SDL_VideoInfo *vi = SDL_GetVideoInfo();
        if (vi) {
            if (SCREEN_W == 0) SCREEN_W = vi->current_w;
            if (SCREEN_H == 0) SCREEN_H = vi->current_h;
        }
    }
    /* Final clamp: catches any 0-sentinel that survived (e.g. windowed
       mode with width=0 in config.lua) and any out-of-range desktop value. */
    if (SCREEN_W < CONFIG_W_MIN) SCREEN_W = CONFIG_W_MIN;
    if (SCREEN_W > CONFIG_W_MAX) SCREEN_W = CONFIG_W_MAX;
    if (SCREEN_H < CONFIG_H_MIN) SCREEN_H = CONFIG_H_MIN;
    if (SCREEN_H > CONFIG_H_MAX) SCREEN_H = CONFIG_H_MAX;
    conLogf("Resolution: %dx%d%s\n", SCREEN_W, SCREEN_H, fullscreen ? " fullscreen" : "");

    SoundSystem snd;
    if (!sndInit(&snd, SAMPLE_RATE)) {
        SDL_Quit();
        return 1;
    }
    SoundLibrary sndLib;
    sndLibInit(&sndLib);

    MusicSystem mus;
    musicInit(&mus);
    MusicLibrary musLib;
    musicLibInit(&musLib);

    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    /* No depth buffer needed for pure 2D, but a tiny one doesn't hurt
       and keeps the SDL/GL attribute set close to typical defaults. */
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    /* Request vsync before SDL_SetVideoMode (SDL 1.2.10+). Only a request:
       some old drivers ignore it and there's no read-back in 1.2, so we just
       log what we asked for. */
    SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, cfg.vsync);
    conLogf("VSync: %s\n", cfg.vsync ? "on (requested)" : "off");

    Uint32 videoFlags = SDL_OPENGL;
    if (fullscreen) videoFlags |= SDL_FULLSCREEN;
    SDL_Surface *screen = SDL_SetVideoMode(SCREEN_W, SCREEN_H, 32, videoFlags);
    if (!screen) {
        conLogf("SDL_SetVideoMode failed: %s\n", SDL_GetError());
        sndShutdown(&snd);
        SDL_Quit();
        return 1;
    }

    if (fullscreen) applyFullscreenRefreshHz(SCREEN_W, SCREEN_H);

    SDL_EnableUNICODE(1);
    SDL_WM_SetCaption("Find5", NULL);

    /* 2D GL state. uiBegin/uiEnd manages its own state per-frame, but
       set sensible defaults so non-UI draws also behave. */
    glViewport(0, 0, SCREEN_W, SCREEN_H);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glClearColor(0.08f, 0.08f, 0.12f, 1.0f);

    UiState ui;
    uiInit(&ui, SCREEN_W, SCREEN_H);

    AssetRegistry assetReg;
    assetRegInit(&assetReg);
    TexCache texCache;
    texCacheInit(&texCache);
    TexBlurCache blurCache;
    texBlurInit(&blurCache);
    ScriptSystem script;
    /* Per-user persistence path: AppData\Find5\find5.dat (Windows) or
       ~/.config/Find5/find5.dat (Unix). Falls back to "find5.dat" next
       to the exe when no user-config dir is reachable (e.g. Win98).
       optPath is static so the buffer outlives ScriptSystem's borrowed
       pointer. */
    static char optPath[512];
    scriptResolveConfigPath("Find5", "find5.dat", optPath, sizeof(optPath));
    scriptInit(&script, &ui, &snd, &sndLib, &mus, &musLib, &assetReg,
               &texCache, &blurCache, optPath);
    scriptLoadAssets(&script, "assets.lua");
    scriptInstallConsolePrint(&script);

    /* Run the entry script, then fire onStart. Scripts can call
       musicPlay, soundPlay, uiShowMessage at this point. */
    scriptRunFile(&script, "scripts/main.lua");
    scriptCall(&script, "onStart");

    int running = 1;
    Uint32 lastTime = SDL_GetTicks();

    SDL_Event event;
    while (running) {
        Uint32 now = SDL_GetTicks();
        float dt = (now - lastTime) / 1000.0f;
        if (dt > 0.15f) dt = 0.15f;
        lastTime = now;

        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = 0;
                break;
            }
            if (event.type == SDL_KEYDOWN) {
                SDLKey sym = event.key.keysym.sym;
                /* Esc is a hardcoded kill-switch so a buggy Lua script
                   can't lock the user in. Lua still sees the event so
                   game code can react if it wants. */
                if (sym == SDLK_ESCAPE) running = 0;
                const char *name = SDL_GetKeyName(sym);
                scriptCallKeyDown(&script, name ? name : "");
                /* Fire onTextInput after onKeyDown when the key
                   produced a printable ASCII character. Editor widgets
                   handle character insertion here; navigation keys
                   stay in onKeyDown. ASCII only for v1. */
                Uint16 uni = event.key.keysym.unicode;
                if (uni >= 0x20 && uni <= 0x7E) {
                    char buf[2] = { (char)uni, '\0' };
                    scriptCallTextInput(&script, buf);
                }
            }
            if (event.type == SDL_KEYUP) {
                const char *name = SDL_GetKeyName(event.key.keysym.sym);
                scriptCallKeyUp(&script, name ? name : "");
            }
            if (event.type == SDL_MOUSEBUTTONDOWN) {
                float vx = 0.0f, vy = 0.0f;
                uiMouseToVirtual(&ui, event.button.x, event.button.y, &vx, &vy);
                scriptCallMouseDown(&script, vx, vy, event.button.button);
            }
            if (event.type == SDL_MOUSEBUTTONUP) {
                float vx = 0.0f, vy = 0.0f;
                uiMouseToVirtual(&ui, event.button.x, event.button.y, &vx, &vy);
                scriptCallMouseUp(&script, vx, vy, event.button.button);
            }
            if (event.type == SDL_MOUSEMOTION) {
                /* xrel/yrel are pixels; convert by scaling against the
                   virtual canvas (no offset, since they're deltas). */
                float vx = 0.0f, vy = 0.0f;
                uiMouseToVirtual(&ui, event.motion.x, event.motion.y, &vx, &vy);
                float scale = (ui.virtualH > 0) ? (ui.virtualH / (float)SCREEN_H) : 1.0f;
                float dvx = event.motion.xrel * scale;
                float dvy = event.motion.yrel * scale;
                scriptCallMouseMove(&script, vx, vy, dvx, dvy);
            }
        }

        scriptCallUpdate(&script, dt);
        /* A script (e.g. the menu's "Exit to system?" dialog) can ask to
           quit via requestQuit(); honor it after the frame's update so
           any dialog outro / action that set it has already run. */
        if (script.quitRequested) running = 0;
        musicUpdate(&mus, dt);
        uiUpdateMessage(&ui, dt);

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        uiBegin(&ui);

        /* Game-side rendering — scripts call draw_sprite etc. from here. */
        scriptCallRender(&script);

        /* Engine HUD overlay — drawn after game so it always sits on top. */
        uiDrawMessage(&ui);

        uiEnd(&ui);

        SDL_GL_SwapBuffers();
        SDL_Delay(1);
    }

    scriptShutdown(&script);
    musicShutdown(&mus);
    sndShutdown(&snd);
    uiShutdown(&ui);
    SDL_Quit();
    return 0;
}
