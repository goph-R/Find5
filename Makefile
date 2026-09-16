# Find5 — Linux build. Everything is in ../SOOB-Core/build/soob.mk.
# Requires libsdl1.2-dev, libopenal-dev.
BIN     = find5
ENGINE ?= ../SOOB-Core

# Optional per-game additions, set before the include:
#   SOOB_DEFS += -DMY_FLAG      SOOB_INCS += -Ithird_party
#   SOOB_OBJ  += extra.o        SOOB_LIBS += -lfoo

include $(ENGINE)/build/soob.mk
