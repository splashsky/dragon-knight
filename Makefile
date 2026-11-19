# Dragon Knight (C + Lua) — single binary, two vendored deps (Lua 5.5, SQLite 3).
#
#   make                 build ./dk (objects in $(BUILD))
#   make test            lint + C unit tests + Lua tests + end-to-end tests
#   make lint            check tab indentation (tests/lint.sh)
#   make BUILD=build/x   use a separate object dir (parallel builds/CI)
#   make DEBUG=1         -O0 -g with ASan/UBSan (and malloc counting for dk stats)
#   make TSAN=1 CC=clang BUILD=build/tsan BIN=build/tsan/dk ctest
#                        C unit tests under ThreadSanitizer (make ctest: C tests only)
#   make bench           release build + tools/dkbench, then tools/bench.sh against a temp
#                        install (BENCH_SCENARIO=pages|fights|static|mixed|idle|realtime|all,
#                        see docs/PERF.md)
#   make run [PORT=8080] [BIND=addr] [CONFIG=config.lua]
#                        build and serve in the foreground; on first use creates CONFIG
#                        (random secret) and installs the game with ADMIN_USER/ADMIN_PASS
#                        (admin/admin); migrates an out-of-date database (scripts/run.sh)
#
# Releases, deployment and migrations (CONFIG defaults to config.lua):
#   make release         optimized build in build/release/dk (-O2, no sanitizers)
#   make dist            dist/dk-VERSION-OS-ARCH.tar.gz: binary, app/, templates/, public/,
#                        config.example.lua, README.md, LICENSE (never config.lua or data/)
#   make backup [CONFIG=path]           ./dk backup: online copy to <db dir>/backups/
#   make migrate [CONFIG=path]          ./dk check, then a backup, then ./dk migrate
#   make migrate-status [CONFIG=path]   ./dk migrate --status
#   make deploy DEST=dir|[user@]host:dir [CONFIG=config.lua] [RESTART='command']
#                        release build + check, sync to DEST (never its config.lua or
#                        data/), then check, backup and migrate there (scripts/deploy.sh)

BUILD   ?= build
BIN     ?= dk
CC      ?= cc
DEBUG   ?= 0
TSAN    ?= 0
DEFS    ?=
RELEASE ?= 0
CONFIG  ?= config.lua
DIST    ?= dist
PORT    ?= 8080
BIND    ?=
ADMIN_USER  ?= admin
ADMIN_EMAIL ?= admin@example.com
ADMIN_PASS  ?= admin

WARN    := -Wall -Wextra -Wshadow -Wno-unused-parameter -Wstrict-prototypes -Wmissing-prototypes
CSTD    := -std=c11 -D_GNU_SOURCE
INCS    := -Isrc -Ivendor/lua/src -Ivendor/sqlite

ifeq ($(TSAN),1)
	OPT     := -O1 -g -fsanitize=thread -fno-omit-frame-pointer
	LDOPT   := -fsanitize=thread
else ifeq ($(DEBUG),1)
	OPT     := -O0 -g3 -fsanitize=address,undefined -fno-omit-frame-pointer
	LDOPT   := -fsanitize=address,undefined -Wl,--wrap=malloc,--wrap=calloc,--wrap=realloc
	DEFS    := -DDK_COUNT_MALLOC
else ifeq ($(RELEASE),1)
	OPT     := -O2
	LDOPT   :=
else
	OPT     := -O2 -g
	LDOPT   :=
endif

CFLAGS_APP    := $(CSTD) $(OPT) $(DEFS) $(WARN) $(INCS) -pthread
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

RELEASE_BUILD := build/release
RELEASE_BIN   := $(RELEASE_BUILD)/dk
VERSION       := $(shell sed -n 's/^view\.GAME_VERSION = "\(.*\)"$$/\1/p' app/lib/view.lua)
PLATFORM      := $(shell uname -s | tr A-Z a-z)-$(shell uname -m | tr A-Z a-z)
DIST_NAME     := dk-$(VERSION)
DIST_TARBALL  := $(DIST)/$(DIST_NAME)-$(PLATFORM).tar.gz
DIST_FILES    := app templates public config.example.lua README.md LICENSE

.PHONY: all test ctest lint clean distclean run release dist backup migrate migrate-status deploy bench
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

ctest: $(TEST_BINS)
	@set -e; for t in $(TEST_BINS); do echo "== $$t"; $$t; done

test: lint $(BIN) $(TEST_BINS)
	@set -e; for t in $(TEST_BINS); do echo "== $$t"; $$t; done
	@if [ -x tests/run.sh ]; then BIN=./$(BIN) tests/run.sh; fi

run: export DK_BIN := ./$(BIN)
run: export CONFIG := $(CONFIG)
run: export PORT := $(PORT)
run: export BIND := $(BIND)
run: export ADMIN_USER := $(ADMIN_USER)
run: export ADMIN_EMAIL := $(ADMIN_EMAIL)
run: export ADMIN_PASS := $(ADMIN_PASS)
run: $(BIN)
	@scripts/run.sh

# release builds have their own object dir, so they never clobber the dev build
release:
	@echo "release: building $(RELEASE_BIN)"
	@$(MAKE) -s --no-print-directory BUILD=$(RELEASE_BUILD) BIN=$(RELEASE_BIN) DEBUG=0 RELEASE=1 $(RELEASE_BIN)

$(BUILD)/dkbench: tools/dkbench.c | $(BUILD)/src
	$(CC) $(CSTD) $(OPT) $(WARN) -pthread -o $@ $< -lm $(LDOPT)

bench: release
	@$(MAKE) -s --no-print-directory BUILD=$(RELEASE_BUILD) BIN=$(RELEASE_BIN) DEBUG=0 RELEASE=1 $(RELEASE_BUILD)/dkbench
	@BIN=$(RELEASE_BIN) DKBENCH=$(RELEASE_BUILD)/dkbench tools/bench.sh

dist: release
	@test -n "$(VERSION)" || { echo "dist: no view.GAME_VERSION in app/lib/view.lua" >&2; exit 1; }
	rm -rf $(DIST)/.stage $(DIST_TARBALL)
	mkdir -p $(DIST)/.stage/$(DIST_NAME)
	cp $(RELEASE_BIN) $(DIST)/.stage/$(DIST_NAME)/dk
	cp -R $(DIST_FILES) $(DIST)/.stage/$(DIST_NAME)/
	tar -C $(DIST)/.stage -czf $(DIST_TARBALL) $(DIST_NAME)
	rm -rf $(DIST)/.stage
	@echo "dist: $(DIST_TARBALL)"

backup: $(BIN)
	./$(BIN) backup --config $(CONFIG)

migrate: $(BIN)
	./$(BIN) check --config $(CONFIG)
	./$(BIN) backup --config $(CONFIG)
	./$(BIN) migrate --config $(CONFIG)

migrate-status: $(BIN)
	./$(BIN) migrate --config $(CONFIG) --status

deploy: export DEST := $(DEST)
deploy: export CONFIG := $(CONFIG)
deploy: export RESTART := $(RESTART)
deploy: export DK_BIN := $(RELEASE_BIN)
deploy:
	@scripts/deploy.sh --preflight
	@$(MAKE) --no-print-directory release
	@scripts/deploy.sh

$(BUILD)/src $(BUILD)/lua $(BUILD)/sqlite $(BUILD)/tests:
	mkdir -p $@

clean:
	rm -rf $(BUILD)/src $(BUILD)/tests $(BIN)

distclean:
	rm -rf build $(DIST) $(BIN)
