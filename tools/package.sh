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
# Two details worth knowing:
#
#   * the archive is built OUTSIDE the mod directory and moved in afterwards.
#     modkit walks the whole tree, so writing straight into dist/ makes the
#     archive contain the previous archive.
#   * the companion mod is packed from inside the engine's own mods/ tree,
#     because pack mounts one mod at a time and that is where its optional
#     dependency on gen151 resolves the way it will for a player.
set -e

RECOMP="${1:?usage: package.sh <gen1recomp>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$HERE/dist"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$RECOMP/mods/gen151_hints"' EXIT
mkdir -p "$DIST"

version() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$1"
}

rm -f "$DIST"/*.modpkg

python3 "$RECOMP/tools/modkit.py" pack "$HERE" \
  -o "$TMP/gen151-$(version "$HERE/manifest.json").modpkg"

cp -r "$HERE/gen151_hints" "$RECOMP/mods/gen151_hints"
python3 "$RECOMP/tools/modkit.py" pack "$RECOMP/mods/gen151_hints" \
  -o "$TMP/gen151_hints-$(version "$HERE/gen151_hints/manifest.json").modpkg"


mv "$TMP"/*.modpkg "$DIST/"
echo "archives in $DIST"
