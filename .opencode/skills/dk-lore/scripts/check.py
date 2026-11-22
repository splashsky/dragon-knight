#!/usr/bin/env python3
"""check.py :: keeps the lore's chunks one consistent set (SKILL.md "Keeping it continuous").

Checks, from the skill's directory: every chunk under chunks/ has frontmatter (id = its path
without .md, a summary, related and sources lists); INDEX.md lists every chunk once and no
chunk that doesn't exist; every related id, every chunk path mentioned in a chunk's text and
every glossary entry's chunk exists; glossary names are unique; every source that is a
repository path exists; chunks stay under MAX_LINES. Exits 1 with one line per problem.
"""
import os
import re
import sys

MAX_LINES = 250
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CHUNKS = os.path.join(HERE, "chunks")
ID = r"[a-z0-9-]+(?:/[a-z0-9-]+)+"

problems = []


def problem(where, text):
	problems.append(f"{where}: {text}")


def frontmatter(path, text):
	if not text.startswith("---\n"):
		problem(path, "no frontmatter")
		return {}
	end = text.find("\n---\n", 4)
	if end < 0:
		problem(path, "frontmatter not closed")
		return {}
	meta = {}
	for line in text[4:end].splitlines():
		m = re.match(r"^([a-z_]+):\s*(.*)$", line)
		if not m:
			problem(path, f"frontmatter line not understood: {line!r}")
			continue
		key, value = m.group(1), m.group(2).strip()
		if value.startswith("[") and value.endswith("]"):
			value = [v.strip() for v in value[1:-1].split(",") if v.strip()]
		meta[key] = value
	return meta


chunks = {}
for dirpath, _, files in os.walk(CHUNKS):
	for name in sorted(files):
		if not name.endswith(".md"):
			continue
		path = os.path.join(dirpath, name)
		rel = os.path.relpath(path, CHUNKS)[:-3].replace(os.sep, "/")
		text = open(path, encoding="utf-8").read()
		chunks[rel] = (path, text, frontmatter(f"chunks/{rel}.md", text))

for cid, (path, text, meta) in sorted(chunks.items()):
	where = f"chunks/{cid}.md"
	if meta.get("id") != cid:
		problem(where, f"id is {meta.get('id')!r}, should be {cid!r}")
	if not isinstance(meta.get("summary"), str) or not meta.get("summary"):
		problem(where, "no summary")
	for key in ("related", "sources"):
		if not isinstance(meta.get(key), list):
			problem(where, f"{key} must be a list like [a, b]")
	if isinstance(meta.get("sources"), list) and not meta["sources"]:
		problem(where, "no sources: cite the files (or continuity.md decisions) its facts come from")
	for rid in meta.get("related") or []:
		if rid not in chunks:
			problem(where, f"related chunk {rid!r} doesn't exist")
	for src in meta.get("sources") or []:
		looks_like_path = "/" in src and re.search(r"\.[a-z]+$", src.split("#")[0])
		if looks_like_path and not os.path.exists(os.path.join(ROOT, src.split("#")[0])):
			problem(where, f"source {src!r} doesn't exist")
	body = text.split("\n---\n", 1)[-1]
	for ref in re.findall(rf"\b({ID})\.md\b", body):
		if ref not in chunks and not os.path.exists(os.path.join(ROOT, ref + ".md")):
			problem(where, f"mentions {ref}.md, which isn't a chunk")
	lines = text.count("\n") + 1
	if lines > MAX_LINES:
		problem(where, f"{lines} lines: split it (at most {MAX_LINES})")

index_path = os.path.join(HERE, "INDEX.md")
if not os.path.exists(index_path):
	problem("INDEX.md", "missing")
else:
	listed = re.findall(rf"^\s*-\s*`({ID})`", open(index_path, encoding="utf-8").read(), re.M)
	seen = set()
	for cid in listed:
		if cid in seen:
			problem("INDEX.md", f"{cid} listed twice")
		seen.add(cid)
		if cid not in chunks:
			problem("INDEX.md", f"{cid} isn't a chunk")
	for cid in chunks:
		if cid not in seen:
			problem("INDEX.md", f"{cid} isn't listed")

glossary_path = os.path.join(HERE, "glossary.md")
if not os.path.exists(glossary_path):
	problem("glossary.md", "missing")
else:
	names = {}
	for n, line in enumerate(open(glossary_path, encoding="utf-8"), 1):
		m = re.match(r"^\s*-\s*\*\*(.+?)\*\*", line)
		if not m:
			continue
		name = m.group(1).strip().lower()
		if name in names:
			problem(f"glossary.md:{n}", f"{m.group(1)!r} already defined on line {names[name]}")
		names[name] = n
		refs = re.findall(rf"`({ID})`", line)
		if not refs:
			problem(f"glossary.md:{n}", f"{m.group(1)!r} names no chunk (`area/chunk`)")
		for ref in refs:
			if ref not in chunks:
				problem(f"glossary.md:{n}", f"{ref} isn't a chunk")

if not os.path.exists(os.path.join(HERE, "continuity.md")):
	problem("continuity.md", "missing")

for p in problems:
	print(p)
if problems:
	print(f"lore check: {len(problems)} problem(s)", file=sys.stderr)
	sys.exit(1)
print(f"lore check: ok ({len(chunks)} chunks)")
