---
name: Dragon Knight lore
description: The canon of Dragon Knight's world (its towns, lands, peoples, monsters, magic, weather, legends), in chunks to read as needed. Use when writing or reviewing anything players read as part of the world (lore fields, monster speech, flavor lines, names and descriptions of new content), when designing new places, monsters, items or spells so they fit, and when adding to, editing or pruning the lore itself.
---

# Dragon Knight lore

The world's canon, kept in short chunks so you read only what a task needs. The game's
content files (`app/content/**`, `app/lib/weather_lines.lua`, `app/lib/terrain_lines.lua`)
are where players read the lore; these chunks are where the world's facts are kept
consistent.

## How to use it

1. Read `INDEX.md`: one line per chunk.
2. Read only the chunks your task touches (a town's, a land's, a monster family's), and
	`glossary.md` for any proper noun you are about to use.
3. Write in the voice below, and check what you write against those chunks.
4. If your work adds, changes or removes a fact of the world, update the chunks in the
	same change (see "Keeping it continuous").

## The voice

Plain and concrete: a place, a habit, a rumour, who uses it, what goes wrong. Short
sentences, dry humour, no purple prose, no exclamation marks in lore, no modern idioms.
Only the upper echelon sounds legendary: monsters from level 42, the dragons and the demon
lords, the Destiny gear and the Dragon's, Angel's, Seraph's and Demon's accessories, and the
strongest spells. Everything near Midworld is ordinary life.

## What wins

1. **The game's mechanics**: numbers, elements, behaviour and where things are sold or found
	(`app/content/**`, `app/sql/seed.sql`, the world's data `app/lib/terrain/world.lua`).
	Lore never contradicts them. When a chunk disagrees with the game, the chunk is wrong.
2. **These chunks**: the world's facts and how they connect.
3. **Older lore text in content files**: when a content file's lore disagrees with a chunk,
	fix whichever is wrong and record the decision in `continuity.md`.

## Keeping it continuous

The lore may be edited, pruned and added to as the game needs, as long as it stays one
world. Every change keeps these true:

- **One fact, one home.** A fact lives in one chunk; others link to it (`see
	towns/kalle.md`) rather than restating it. A name used in two places means the same
	thing in both.
- **Names are in the glossary.** Every proper noun a chunk introduces (a town, a guild, a
	person, a river, a legend) has one line in `glossary.md` naming its chunk. Adding a name:
	check the glossary first so you don't invent a second one for the same thing.
- **Contradictions are resolved, not left.** When two facts collide, decide which holds,
	fix the other, and add a line to `continuity.md` (what collided, what was decided, why).
	Open questions go there too until decided.
- **Pruning removes the fact everywhere.** Delete it from its chunk, its glossary line, and
	any links to it; if players read it in a content file's lore, change that too or record
	why it stays.
- **Every chunk cites its sources**: the content files (or decisions) its facts come from,
	so a later editor can check them.
- **Chunks stay small** (under about 200 lines) and about one thing. Split a chunk that
	grows past that, and update the index and the links.

Run `python3 .opencode/skills/dk-lore/scripts/check.py` after any change: it checks that
every chunk is in the index with its frontmatter, every link and glossary entry points at a
real chunk, and chunks stay within size. (`tests/lint.sh` runs it too.)

## A chunk

```markdown
---
id: towns/kalle
summary: Kalle, the mining town of the south-east; its pits, its miners, their powder.
related: [lands/diggings, peoples/trades, things/battlefield-objects]
sources: [app/content/items/explosive_barrel.lua, app/content/monsters/grey_bear.lua]
---

# Kalle

...facts, in the voice, in short sections...
```

`id` is the path under `chunks/` without `.md`; `related` lists other chunks' ids;
`sources` lists the files (or `continuity.md` decisions) its facts come from.
