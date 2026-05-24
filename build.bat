@echo off

echo === Find5 Win98/Dev-C++ Build ===
echo.

REM ----------------------------------------------------------------
REM  command.com on Win98 SE doesn't understand cmd.exe's `( ... )`
REM  multi-line if-blocks (the whole script silently misparses).
REM  Stick to goto-only flow control. `if exist` itself works fine
REM  with unquoted paths -- it was the parens that broke things.
REM ----------------------------------------------------------------

REM ----------------------------------------------------------------
REM  Check for OpenAL headers and import library.
REM  Files we expect in vendor/:
REM    vendor\include\AL\al.h, alc.h     (headers)
REM    vendor\lib\libOpenAL32.a OR       (MinGW import library)
REM    vendor\lib\libOpenAL32.dll.a      (OpenAL Soft MinGW variant)
REM    OpenAL32.dll                      (next to the exe, or in System)
REM ----------------------------------------------------------------
if not exist vendor\include\AL\al.h goto noheaders
if exist vendor\lib\libOpenAL32.a goto havelib
if exist vendor\lib\libOpenAL32.dll.a goto havelib
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
C:\Dev-Cpp\bin\gcc.exe -Ivendor\lua-5.1.5\src -Dluaall_c -DLUA_ANSI -O2 -c vendor\lua-5.1.5\src\lua_all.c -o raw\obj\lua.o
if errorlevel 1 goto error
:skiplua

REM ----------------------------------------------------------------
REM  stb_vorbis (cached -- delete raw\obj\vorbis.o to force rebuild)
REM ----------------------------------------------------------------
if exist raw\obj\vorbis.o goto skipvorbis
echo Compiling stb_vorbis...
C:\Dev-Cpp\bin\gcc.exe -O2 -c vendor\stb\stb_vorbis.c -o raw\obj\vorbis.o
if errorlevel 1 goto error
:skipvorbis

REM ----------------------------------------------------------------
REM  Compile main
REM ----------------------------------------------------------------
echo Compiling main...
C:\Dev-Cpp\bin\g++.exe -Ivendor\include -Ivendor\lua-5.1.5\src -O2 -c main.cpp -o raw\obj\main.o
if errorlevel 1 goto error

REM ----------------------------------------------------------------
REM  Link
REM ----------------------------------------------------------------
echo Linking...
C:\Dev-Cpp\bin\g++.exe raw\obj\main.o raw\obj\lua.o raw\obj\vorbis.o -o Find5.exe -Lvendor\lib -lmingw32 -lSDLmain -lSDL -lopengl32 -lOpenAL32
if errorlevel 1 goto error

echo.
echo === Build successful! Run Find5.exe ===
echo Make sure OpenAL32.dll is next to the exe or in the system directory.
goto end

:noheaders
echo ERROR: OpenAL headers missing.
echo Place al.h and alc.h in vendor\include\AL\.
goto error

:nolib
echo ERROR: OpenAL MinGW import library missing.
echo Expected vendor\lib\libOpenAL32.a or vendor\lib\libOpenAL32.dll.a.
goto error

:error
echo.
echo === Build FAILED ===
pause

:end
