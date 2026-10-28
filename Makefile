# Build patch16.exe, GNU patch 2.2 for 16-bit MS-DOS, with Open Watcom and
# libc16, in the compact memory model (docs/DESIGN.md, section 14).
#   make                         build patch16.exe
#   make test                    run the tests (tests/run.sh) under DOSBox-X
#   make LIBC16_ROOT=DIR         use another libc16 tree
#
# libc16 0.05 (rename, unlink, fseek, ftell) is not released yet, so
# LIBC16_ROOT defaults to a libc16 checkout next to this one, built with
# its make. Once 0.05 is released, scripts/fetch-libc16 will pin it.
#
# The Open Watcom toolchain is the one libc16 was built with: the libc16
# tree's tools/fetch-watcom fetches it into build/tools.

LIBC16_ROOT ?= ../libc16
LIBC16_DIR  := $(if $(wildcard $(LIBC16_ROOT)/build/stage/VERSION),$(LIBC16_ROOT)/build/stage,$(LIBC16_ROOT))
LIBC16      := $(LIBC16_DIR)/lib/LIBC16C.LIB
TOOLS_ENV   := build/tools.env
WATCOM_ENV   = . ./$(TOOLS_ENV) && PATH=$$WATCOM/binl64:$$PATH

VERSION := $(shell cat VERSION)

CC     = wcc
CFLAGS = -q -zq -zl -zld -x -mc -0 -os -s -bt=dos -w1 \
         -DHAVE_CONFIG_H -Icompat/include -Isrc -Ibuild/include \
         -I$(LIBC16_DIR)/include

# GNU patch 2.2's sources (src/, docs/PROVENANCE.md) and patch16's own
# (compat/).
SRCS = src/patch.c src/pch.c src/inp.c src/util.c src/version.c \
       src/addext.c src/argmatch.c src/backupfile.c src/basename.c \
       src/getopt.c src/getopt1.c src/memchr.c \
       compat/dos.c compat/fmt.c compat/install.c
OBJS = $(patsubst %.c,build/obj/%.obj,$(SRCS))
HDRS = $(wildcard src/*.h compat/include/*.h) build/include/patchlevel.h

patch16.exe: $(OBJS) $(LIBC16) $(TOOLS_ENV)
	$(WATCOM_ENV) && wlink option quiet, nodefaultlibs, map=patch16.map \
	  format dos name $@ $(foreach o,$(OBJS),file $(o)) library $(LIBC16)

build/obj/%.obj: %.c $(HDRS) $(LIBC16) $(TOOLS_ENV)
	mkdir -p $(@D)
	$(WATCOM_ENV) && $(CC) $(CFLAGS) -fo=$@ $<

# As GNU patch's Makefile.in makes it, from patch16's version.
build/include/patchlevel.h: VERSION
	mkdir -p $(@D)
	echo '#define PATCH_VERSION "$(VERSION) (GNU patch 2.2)"' > $@

# The Open Watcom snapshot libc16 names, as shell assignments.
$(TOOLS_ENV): $(LIBC16)
	mkdir -p build
	watcom=$$(sh $(LIBC16_DIR)/tools/fetch-watcom $(CURDIR)/build/tools) \
	  && printf 'WATCOM=%s\nexport WATCOM\n' "$$watcom" > $@

test: patch16.exe
	sh tests/run.sh $(CURDIR)/patch16.exe

clean:
	rm -rf build/obj build/include patch16.exe patch16.map

.PHONY: test clean
