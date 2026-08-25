#!/bin/sh
# Everything CI should run.
#
#   ./tools/check.sh <gen1recomp> [pokered] [pokeyellow] [gen1dex]
#
# With the two pret trees given it also regenerates the derived files and
# fails on a diff, which is the drift guard for placements.lua's Set B rows,
# hints.lua, SPOILERS.md and the fixtures.
set -e

RECOMP="${1:?usage: check.sh <gen1recomp> [pokered] [pokeyellow] [gen1dex]}"
POKERED="$2"
POKEYELLOW="$3"
GEN1DEX_DIR="$4"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

echo "== the roll layer, against the engine's own Encounter.lua"
GEN1RECOMP="$RECOMP" lua tests/roll_test.lua

echo "== placements.lua's invariants"
lua tests/placements_test.lua

echo "== end to end, through the engine's headless loader"
( cd "$RECOMP" \
  && GEN151="$HERE" GEN1DEX="$GEN1DEX_DIR" luajit "$HERE/tests/mod_load_test.lua" )

echo "== every box the mod prints fits the two lines a box has"
( cd "$RECOMP" && GEN151="$HERE" luajit "$HERE/tests/text_test.lua" )

echo "== the runtime features: the cable, the journals, the dex hints"
( cd "$RECOMP" && GEN151="$HERE" luajit "$HERE/tests/features_test.lua" )

echo "== modkit"
python3 "$RECOMP/tools/modkit.py" validate "$HERE"
python3 "$RECOMP/tools/modkit.py" lint "$HERE"

if [ -n "$POKERED" ] && [ -n "$POKEYELLOW" ]; then
  echo "== derived files are up to date"
  ./tools/regen.sh "$RECOMP" "$POKERED" "$POKEYELLOW" >/dev/null
  git diff --exit-code placements.lua hints.lua SPOILERS.md thumbnail.png \
    tests/fixtures
fi

echo "all green"
