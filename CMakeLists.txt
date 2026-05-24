cmake_minimum_required(VERSION 2.8)
project(Find5)

option(USE_VENDOR_SDL "Use vendored SDL from vendor/ directory" OFF)

if(USE_VENDOR_SDL)
    set(SDL_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/vendor/include)
    set(SDL_LIBRARY ${CMAKE_SOURCE_DIR}/vendor/lib/libSDL.dll.a)
    set(SDLMAIN_LIBRARY ${CMAKE_SOURCE_DIR}/vendor/lib/libSDLmain.a)
    set(SDL_LIBS mingw32 ${SDLMAIN_LIBRARY} ${SDL_LIBRARY})
else()
    find_package(SDL REQUIRED)
    set(SDL_LIBS ${SDL_LIBRARY})
endif()

find_package(OpenGL REQUIRED)
find_package(OpenAL REQUIRED)

include_directories(${SDL_INCLUDE_DIR} ${OPENAL_INCLUDE_DIR} vendor/lua-5.1.5/src)

# Lua 5.1.5 unity-build aggregator and stb_vorbis are C TUs.
set_source_files_properties(
    vendor/lua-5.1.5/src/lua_all.c
    PROPERTIES COMPILE_DEFINITIONS "luaall_c;LUA_USE_POSIX"
)

add_executable(Find5
    main.cpp
    vendor/stb/stb_vorbis.c
    vendor/lua-5.1.5/src/lua_all.c
)
target_link_libraries(Find5 ${SDL_LIBS} ${OPENGL_LIBRARIES} ${OPENAL_LIBRARY})
