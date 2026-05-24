# Makefile for Linux — Find5
# Requires libsdl1.2-dev, libopenal-dev.
CPP = g++
BIN = find5

LUA_SRC = vendor/lua-5.1.5/src
LUA_CFLAGS = -I$(LUA_SRC) -Dluaall_c -DLUA_USE_POSIX

CXXFLAGS = $(shell sdl-config --cflags) -I$(LUA_SRC) -O2
LIBS = $(shell sdl-config --libs) -lGL -lopenal

OBJ = main.o lua.o vorbis.o

all: $(BIN)

$(BIN): $(OBJ)
	$(CPP) $(OBJ) -o $(BIN) $(LIBS)

main.o: main.cpp texture.h ui.h sound.h music.h asset_registry.h script.h math.h
	$(CPP) -c main.cpp -o main.o $(CXXFLAGS)

# stb_vorbis (Ogg Vorbis decoder, public domain). Built as its own C TU
# so editing main.cpp doesn't pay its recompile cost. music.h includes
# the same file with STB_VORBIS_HEADER_ONLY for prototypes only.
vorbis.o: vendor/stb/stb_vorbis.c
	gcc -x c -c $< -o $@ -O2

# Lua 5.1.5 compiled as a single C TU via the unity-build aggregator.
lua.o: $(LUA_SRC)/lua_all.c
	gcc -x c -c $< -o $@ $(LUA_CFLAGS) -O2

clean:
	rm -f $(OBJ) $(BIN)

.PHONY: all clean
