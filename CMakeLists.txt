cmake_minimum_required(VERSION 2.8)
project(Find5)

# Shared engine lives at ../SOOB-Core/ (sibling-folder layout).
set(ENGINE ${CMAKE_SOURCE_DIR}/../SOOB-Core)

option(USE_VENDOR_SDL "Use vendored SDL from the shared engine" OFF)

if(USE_VENDOR_SDL)
    set(SDL_INCLUDE_DIR ${ENGINE}/vendor/include)
    set(SDL_LIBRARY ${ENGINE}/vendor/lib/libSDL.dll.a)
    set(SDLMAIN_LIBRARY ${ENGINE}/vendor/lib/libSDLmain.a)
    set(SDL_LIBS mingw32 ${SDLMAIN_LIBRARY} ${SDL_LIBRARY})
else()
    find_package(SDL REQUIRED)
    set(SDL_LIBS ${SDL_LIBRARY})
endif()

find_package(OpenGL REQUIRED)
find_package(OpenAL REQUIRED)

include_directories(${ENGINE} ${SDL_INCLUDE_DIR} ${OPENAL_INCLUDE_DIR}
                    ${ENGINE}/vendor/lua-5.1.5/src)

# Lua 5.1.5 unity-build aggregator and stb_vorbis are C TUs.
set_source_files_properties(
    ${ENGINE}/vendor/lua-5.1.5/src/lua_all.c
    PROPERTIES COMPILE_DEFINITIONS "luaall_c;LUA_USE_POSIX"
)

add_executable(Find5
    main.cpp
    ${ENGINE}/vendor/stb/stb_vorbis.c
    ${ENGINE}/vendor/lua-5.1.5/src/lua_all.c
)
target_link_libraries(Find5 ${SDL_LIBS} ${OPENGL_LIBRARIES} ${OPENAL_LIBRARY})

# Mirror the engine's Lua modules next to the exe so shipped builds find
# require "engine.scene" via ./scripts/?.lua without needing SOOB-Core
# on the player's machine.
add_custom_command(TARGET Find5 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            ${CMAKE_SOURCE_DIR}/scripts/engine
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${ENGINE}/scripts/engine
            ${CMAKE_SOURCE_DIR}/scripts/engine)
