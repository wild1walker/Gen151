#!/bin/sh
# Build the two importable release archives.
#
#   ./tools/package.sh <gen1recomp>
#
# `modkit pack` runs `validate --strict`, so warnings are fatal and the
# archives cannot be built until the mod is clean.  It also refuses anything
# ROM-derived, which is why the derivation pipeline and the fixtures are listed
# in .modkitignore rather than shipped.
#
# The companion mod has to be packed from inside the engine's own mods/ tree:
# pack mounts one mod at a time in the headless loader, so it is the only way
# its optional dependency on gen151 resolves the same way it will for a player.
set -e

RECOMP="${1:?usage: package.sh <gen1recomp>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$HERE/dist"
mkdir -p "$DIST"

python3 "$RECOMP/tools/modkit.py" pack "$HERE" \
  -o "$DIST/gen151-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$HERE/manifest.json").modpkg"

STAGE="$RECOMP/mods/gen151_hints"
rm -rf "$STAGE"
cp -r "$HERE/gen151_hints" "$STAGE"
python3 "$RECOMP/tools/modkit.py" pack "$STAGE" \
  -o "$DIST/gen151_hints-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$HERE/gen151_hints/manifest.json").modpkg"
rm -rf "$STAGE"

echo "archives in $DIST"
