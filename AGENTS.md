# Agents' notes for Dragon Knight

Read `README.md` (building, running, the CLI), `docs/APP.md` (how the app works and its
conventions) and `PLAN.md` (the plans by release) before changing anything. The world's
lore is the `dk-lore` skill (`.opencode/skills/dk-lore/`).

## Versioning

The version is `MAJOR.MINOR.PATCH`, in `app/lib/view.lua` (`view.GAME_VERSION`) and
`src/main.c` (`DK_VERSION`); the player-facing history is `app/community/changelog.lua`
(`changelog.RELEASES`, newest first, in the original changelog's style: `m.d.yyyy` dates,
plain past or present tense, one entry a change players notice).

- **A session is a minor version.** The session's first change opens the next minor:
	`X.(Y+1).0-dev` in both version strings, a new changelog entry `X.(Y+1).0` dated
	`"unreleased"`, and `tests/e2e/community.sh`'s two version checks (the entry's
	`(unreleased)` date and the footer's `Version X.(Y+1).0-dev`). If the session has a plan,
	`PLAN.md` gets its item and `docs/plans/` its file in the same commit ("Plan: ...; start
	X.(Y+1).0-dev").
- **A logical group of bug fixes is a patch.** When a request is a group of fixes (one
	cause, or one area, fixed together), it opens the next patch of the session's version:
	`X.Y.(Z+1)-dev`, a new changelog entry `X.Y.(Z+1)` above the previous one, dated
	`"unreleased"`, with the fixes' lines, and `community.sh` follows. Later work in the
	session goes into the newest open entry.
- **After every request is complete**, before reporting it done:
	1. the changelog's open entry has a line for every change players will notice (changes
		they won't, such as tooling, tests and docs, get none);
	2. the version strings and `community.sh` name the open version;
	3. `make test` (or the relevant subsets, then the full suite) is green;
	4. the work is committed in the history's style (`X.Y: what changed`, one cohesive
		milestone a commit).
- **One release per session**, when the owner says the session is done: date every open
	entry (`m.d.yyyy`), drop `-dev` from the version strings, update `community.sh`, run the
	full checks (`./dk check`, `tests/lint.sh`, `make ctest`, `tests/run.sh`, and the sanitizer
	build: `make DEBUG=1 BUILD=build/dbg BIN=build/dbg/dk build/dbg/dk && BIN=build/dbg/dk
	tests/run.sh`), commit "Release X.Y.Z" (the newest number) and tag it
	`git tag -a vX.Y.Z -m "Dragon Knight X.Y.Z"`. Push only when the owner asks.
- Schema changes are separate from versions: a schema step (`app/lib/migrations.lua`) is
	named in the changelog line of the change that needs it ("schema version N, run dk
	migrate").
