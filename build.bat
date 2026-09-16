@echo off

REM  The one per-game line in this file.
set NAME=Find5

echo === %NAME% Win98/Dev-C++ Build ===
echo.

REM ----------------------------------------------------------------
REM  command.com on Win98 SE doesn't understand cmd.exe's `( ... )`
REM  multi-line if-blocks (the whole script silently misparses).
REM  Stick to goto-only flow control. `if exist` itself works fine
REM  with unquoted paths -- it was the parens that broke things.
REM ----------------------------------------------------------------

REM ----------------------------------------------------------------
REM  Shared engine lives at ..\SOOB-Core\ (sibling-folder layout).
REM  All engine headers (texture.h, ui.h, script.h, etc.) and vendored
REM  libraries (SDL 1.2, Lua 5.1.5, stb, OpenAL libs) come from there.
REM ----------------------------------------------------------------

REM ----------------------------------------------------------------
REM  Check for OpenAL headers and import library in the shared engine.
REM    ..\SOOB-Core\vendor\include\AL\al.h, alc.h     (headers)
REM    ..\SOOB-Core\vendor\lib\libOpenAL32.a OR
REM    ..\SOOB-Core\vendor\lib\libOpenAL32.dll.a      (import library)
REM    OpenAL32.dll                                   (next to the exe)
REM ----------------------------------------------------------------
if not exist ..\SOOB-Core\vendor\include\AL\al.h goto noheaders
if exist ..\SOOB-Core\vendor\lib\libOpenAL32.a goto havelib
if exist ..\SOOB-Core\vendor\lib\libOpenAL32.dll.a goto havelib
goto nolib
:havelib

REM ----------------------------------------------------------------
REM  Object output directory
REM ----------------------------------------------------------------
if not exist raw\obj mkdir raw\obj

REM ----------------------------------------------------------------
REM  Lua 5.1.5 -- unity-build aggregator. -DLUA_ANSI disables loadlib
REM  dlopen / Win32 branches that Dev-C++ 3.4 can't satisfy.
REM  Cached -- delete raw\obj\lua.o to force rebuild.
REM ----------------------------------------------------------------
if exist raw\obj\lua.o goto skiplua
echo Compiling Lua...
C:\Dev-Cpp\bin\gcc.exe -I..\SOOB-Core\vendor\lua-5.1.5\src -Dluaall_c -DLUA_ANSI -O2 -c ..\SOOB-Core\vendor\lua-5.1.5\src\lua_all.c -o raw\obj\lua.o
if errorlevel 1 goto error
:skiplua

REM ----------------------------------------------------------------
REM  stb_vorbis (cached -- delete raw\obj\vorbis.o to force rebuild)
REM ----------------------------------------------------------------
if exist raw\obj\vorbis.o goto skipvorbis
echo Compiling stb_vorbis...
C:\Dev-Cpp\bin\gcc.exe -O2 -c ..\SOOB-Core\vendor\stb\stb_vorbis.c -o raw\obj\vorbis.o
if errorlevel 1 goto error
:skipvorbis

REM ----------------------------------------------------------------
REM  Compile main.  -I..\SOOB-Core lets #include "script.h" etc.
REM  resolve to the shared headers.
REM ----------------------------------------------------------------
echo Compiling main...
C:\Dev-Cpp\bin\g++.exe -I..\SOOB-Core -I..\SOOB-Core\vendor\include -I..\SOOB-Core\vendor\lua-5.1.5\src -O2 -DSOOB_SOFTWARE_BACKEND -c main.cpp -o raw\obj\main.o
if errorlevel 1 goto error

REM ----------------------------------------------------------------
REM  Link
REM ----------------------------------------------------------------
echo Linking...
C:\Dev-Cpp\bin\g++.exe raw\obj\main.o raw\obj\lua.o raw\obj\vorbis.o -o %NAME%.exe -mwindows -L..\SOOB-Core\vendor\lib -lmingw32 -lSDLmain -lSDL -lopengl32 -lOpenAL32
if errorlevel 1 goto error

REM ----------------------------------------------------------------
REM  Runtime DLLs live in the shared engine so each game repo does
REM  not carry its own copy. Flat `if exist` lines only -- no parens.
REM ----------------------------------------------------------------
if exist SDL.dll goto havesdldll
copy ..\SOOB-Core\vendor\SDL.dll . >nul
:havesdldll
if exist OpenAL32.dll goto haveopenaldll
copy ..\SOOB-Core\vendor\OpenAL32.dll . >nul
:haveopenaldll

REM ----------------------------------------------------------------
REM  Mirror SOOB-Core's Lua engine modules next to the exe so
REM  require "engine.scene" resolves via ./scripts/?.lua in shipped
REM  builds without needing the SOOB-Core repo on the player's machine.
REM ----------------------------------------------------------------
if not exist scripts\engine mkdir scripts\engine
copy /Y ..\SOOB-Core\scripts\engine\*.lua scripts\engine\ >nul

echo.
echo === Build successful! Run %NAME%.exe ===
goto end

:noheaders
echo ERROR: OpenAL headers missing.
echo Place al.h and alc.h in ..\SOOB-Core\vendor\include\AL\.
goto error

:nolib
echo ERROR: OpenAL MinGW import library missing.
echo Expected ..\SOOB-Core\vendor\lib\libOpenAL32.a or libOpenAL32.dll.a.
goto error

:error
echo.
echo === Build FAILED ===
pause

:end
