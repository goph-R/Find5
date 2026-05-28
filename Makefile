# Makefile for Linux — Find5
# Requires libsdl1.2-dev, libopenal-dev.
CPP = g++
BIN = find5

# Shared engine lives in ../SOOB-Core/ (sibling-folder layout).
# All engine headers (texture.h, ui.h, script.h, etc.) and vendored
# libraries (Lua 5.1.5, stb) are pulled from there.
ENGINE  = ../SOOB-Core
LUA_SRC = $(ENGINE)/vendor/lua-5.1.5/src
LUA_CFLAGS = -I$(LUA_SRC) -Dluaall_c -DLUA_USE_POSIX

CXXFLAGS = $(shell sdl-config --cflags) -I$(ENGINE) -I$(LUA_SRC) -O2
LIBS = $(shell sdl-config --libs) -lGL -lopenal

OBJ = main.o lua.o vorbis.o

all: $(BIN) scripts/engine

# Mirror the engine's Lua modules next to the exe so shipped builds find
# `require "engine.scene"` via ./scripts/?.lua without needing the
# SOOB-Core repo on the player's machine.
scripts/engine: $(wildcard $(ENGINE)/scripts/engine/*.lua)
	mkdir -p scripts/engine
	cp $(ENGINE)/scripts/engine/*.lua scripts/engine/
	touch scripts/engine

$(BIN): $(OBJ)
	$(CPP) $(OBJ) -o $(BIN) $(LIBS)

main.o: main.cpp
	$(CPP) -c main.cpp -o main.o $(CXXFLAGS)

# stb_vorbis (Ogg Vorbis decoder, public domain). Built as its own C TU
# so editing main.cpp doesn't pay its recompile cost. music.h includes
# the same file with STB_VORBIS_HEADER_ONLY for prototypes only.
vorbis.o: $(ENGINE)/vendor/stb/stb_vorbis.c
	gcc -x c -c $< -o $@ -O2

# Lua 5.1.5 compiled as a single C TU via the unity-build aggregator.
lua.o: $(LUA_SRC)/lua_all.c
	gcc -x c -c $< -o $@ $(LUA_CFLAGS) -O2

clean:
	rm -f $(OBJ) $(BIN)

.PHONY: all clean
