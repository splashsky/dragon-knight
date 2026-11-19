# Dragon Knight (C + Lua) — single binary, two vendored deps (Lua 5.5, SQLite 3).
#
#   make                 build ./dk (objects in $(BUILD))
#   make test            lint + C unit tests + Lua tests + end-to-end tests
#   make lint            check tab indentation (tests/lint.sh)
#   make BUILD=build/x   use a separate object dir (parallel builds/CI)
#   make DEBUG=1         -O0 -g with ASan/UBSan

BUILD   ?= build
BIN     ?= dk
CC      ?= cc
DEBUG   ?= 0

WARN    := -Wall -Wextra -Wshadow -Wno-unused-parameter -Wstrict-prototypes -Wmissing-prototypes
CSTD    := -std=c11 -D_GNU_SOURCE
INCS    := -Isrc -Ivendor/lua/src -Ivendor/sqlite

ifeq ($(DEBUG),1)
	OPT     := -O0 -g3 -fsanitize=address,undefined -fno-omit-frame-pointer
	LDOPT   := -fsanitize=address,undefined
else
	OPT     := -O2 -g
	LDOPT   :=
endif

CFLAGS_APP    := $(CSTD) $(OPT) $(WARN) $(INCS) -pthread
CFLAGS_LUA    := -std=gnu99 $(OPT) -DLUA_USE_POSIX -w
CFLAGS_SQLITE := $(OPT) -w \
	-DSQLITE_THREADSAFE=1 -DSQLITE_DQS=0 -DSQLITE_OMIT_LOAD_EXTENSION \
	-DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
	-DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_OMIT_DEPRECATED -DSQLITE_USE_ALLOCA
LDLIBS        := -pthread -lm $(LDOPT)

LUA_SRCS  := $(filter-out vendor/lua/src/lua.c vendor/lua/src/luac.c,$(wildcard vendor/lua/src/*.c))
LUA_OBJS  := $(patsubst vendor/lua/src/%.c,$(BUILD)/lua/%.o,$(LUA_SRCS))
SQL_OBJS  := $(BUILD)/sqlite/sqlite3.o
APP_SRCS  := $(wildcard src/*.c)
APP_OBJS  := $(patsubst src/%.c,$(BUILD)/src/%.o,$(APP_SRCS))
LIB_OBJS  := $(filter-out $(BUILD)/src/main.o,$(APP_OBJS))

TEST_SRCS := $(wildcard tests/c/*.c)
TEST_BINS := $(patsubst tests/c/%.c,$(BUILD)/tests/%,$(TEST_SRCS))

.PHONY: all test lint clean distclean
all: $(BIN)

$(BIN): $(APP_OBJS) $(LUA_OBJS) $(SQL_OBJS)
	$(CC) -o $@ $^ $(LDLIBS)

$(BUILD)/src/%.o: src/%.c $(wildcard src/*.h) | $(BUILD)/src
	$(CC) $(CFLAGS_APP) -c -o $@ $<

$(BUILD)/lua/%.o: vendor/lua/src/%.c | $(BUILD)/lua
	$(CC) $(CFLAGS_LUA) -c -o $@ $<

$(BUILD)/sqlite/sqlite3.o: vendor/sqlite/sqlite3.c | $(BUILD)/sqlite
	$(CC) $(CFLAGS_SQLITE) -c -o $@ $<

$(BUILD)/tests/%: tests/c/%.c $(LIB_OBJS) $(LUA_OBJS) $(SQL_OBJS) | $(BUILD)/tests
	$(CC) $(CFLAGS_APP) -Itests/c -o $@ $^ $(LDLIBS)

lint:
	@tests/lint.sh

test: lint $(BIN) $(TEST_BINS)
	@set -e; for t in $(TEST_BINS); do echo "== $$t"; $$t; done
	@if [ -x tests/run.sh ]; then BIN=./$(BIN) tests/run.sh; fi

$(BUILD)/src $(BUILD)/lua $(BUILD)/sqlite $(BUILD)/tests:
	mkdir -p $@

clean:
	rm -rf $(BUILD)/src $(BUILD)/tests $(BIN)

distclean:
	rm -rf build $(BIN)
