#!/bin/sh
# Regenerate everything derived, in dependency order.
#
#   ./tools/regen.sh <gen1recomp> <pokered> <pokeyellow>
#
# Then `git diff --exit-code` is the drift guard: if the disassembly, the
# derivation rules or the Set A table moved, the generated files move with
# them and the diff says so.  CI should run exactly these two commands.
set -e

RECOMP="${1:?usage: regen.sh <gen1recomp> <pokered> <pokeyellow>}"
POKERED="${2:?usage: regen.sh <gen1recomp> <pokered> <pokeyellow>}"
POKEYELLOW="${3:?usage: regen.sh <gen1recomp> <pokered> <pokeyellow>}"

# 1. the gap set and the vanilla fixture, straight off the disassembly
python3 tools/gapset.py --recomp "$RECOMP" --pokered "$POKERED" \
  --pokeyellow "$POKEYELLOW" \
  --json tests/fixtures/gapset.json --lua tests/fixtures/vanilla.lua

# 2. placements.lua: hand-authored Set A plus derived Set B
python3 tools/build_placements.py --recomp "$RECOMP" --pokered "$POKERED" \
  --pokeyellow "$POKEYELLOW"

# 3. the hint vocabulary, from the placements
python3 tools/build_hints.py

# 4. the spoiler table, through the resolver the mod itself runs
luajit tools/dump_placements.lua > SPOILERS.md

# 5. the thumbnails -- original artwork, drawn rather than shipped
python3 tools/make_thumbnail.py
python3 tools/make_thumbnail.py --out gen151_hints/thumbnail.png
python3 tools/make_thumbnail.py --out gen151_debug/thumbnail.png

echo "regenerated; now run: git diff --exit-code"
