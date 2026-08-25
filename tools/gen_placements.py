"""Derive the Set B (version-exclusive) rows of placements.lua.

The rule, and the reason it is a rule rather than a judgement call:

    A species missing from one version is almost always present on another,
    and that other version already answered every question a placement has to
    answer -- which maps, which levels, which company.  Re-using its answer is
    the most defensible source there is (SPEC 4, "where to look for
    precedent"), and it makes the addition feel like it was always there,
    because on two thirds of the cartridges it was.

So: for every species with no renewable source on version V, find the maps
where a version that does have it puts it, keep the ones that exist on V with
a live encounter rate, and take that donor's level.

Emits Lua rows for placements.lua.  tests/placements_test.lua re-runs this
derivation and asserts the checked-in rows still match, so the table stays a
readable source of truth without being able to drift from the disassembly.

    python3 tools/gen_placements.py [--fixture tests/fixtures/vanilla.lua]
"""

import argparse
import json
import os
import re

VERSIONS = ("red", "blue", "yellow")

# Tier is decided by WHY the species is missing, not by where it lands, so it
# is not derivable from the tables.  Default UNCOMMON: a version exclusive in
# its natural habitat should read as a resident.  The exceptions are the two
# species Red and Blue charge an NPC trade for and only Yellow puts in the
# grass -- Yellow's tables give the location, but Red's price gives the tier.
TIER_OVERRIDES = {
    "FARFETCHD": "RARE",
    "LICKITUNG": "RARE",
}

# Donor preference: the sibling cartridge first, Yellow last, so a Red gap is
# answered by Blue where Blue has an answer.  Purely cosmetic -- it only
# decides which donor is named in the justification when both agree.
DONOR_ORDER = {
    "red": ("blue", "yellow"),
    "blue": ("red", "yellow"),
    "yellow": ("red", "blue"),
}


def load_fixture(path):
    """Read the generated Lua fixture without a Lua interpreter.

    The fixture is emitted by tools/gapset.py in one fixed shape, so the JSON
    sibling it writes alongside is the honest thing to read here.
    """
    sibling = os.path.join(os.path.dirname(path), "gapset.json")
    with open(sibling, encoding="utf-8") as handle:
        return json.load(handle)


def encounters_for(version, root):
    """Rebuild the per-version tables the gapset script derived."""
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gapset  # noqa: E402
    import tempfile
    sys.path.insert(0, os.path.join(root["recomp"], "tools"))
    from extract import constants  # noqa: E402
    tree, defines, yellow = root[version]
    with tempfile.TemporaryDirectory() as tmp:
        consts = constants.extract(tree, tmp)
    return (gapset.build_encounters(tree, defines, consts["mapOrder"]),
            gapset.parse_super_rod_yellow(tree, defines) if yellow
            else gapset.parse_super_rod(tree, defines))


def slots_of(encounters, species):
    """map -> the donor's own levels for this species, per terrain."""
    out = {}
    for map_id, record in encounters.items():
        for terrain in ("grass", "water"):
            group = record.get(terrain)
            if not group or group["rate"] == 0:
                continue
            levels = sorted({slot["level"] for slot in group["slots"]
                             if slot["species"] == species})
            if levels:
                out.setdefault((map_id, terrain), []).extend(levels)
    return out


def live_terrain(encounters, map_id, terrain):
    record = encounters.get(map_id)
    if not record:
        return False
    group = record.get(terrain)
    return bool(group) and group["rate"] > 0


def derive(report, tables):
    """version -> list of rows, each a placements.lua entry."""
    rows = {}
    for version in VERSIONS:
        missing = set(report["versions"][version]["missing"])
        setA = set(report["versions"][version]["setA"])
        out = []
        for species in report["dex"]:
            # Set C follows from its parent; only place the base stage.
            if species not in setA or species not in missing:
                continue
            donors = [d for d in DONOR_ORDER[version]
                      if species not in set(report["versions"][d]["missing"])]
            if not donors:
                continue
            chosen = None
            for donor in donors:
                found = slots_of(tables[donor][0], species)
                keep = {key: levels for key, levels in found.items()
                        if live_terrain(tables[version][0], key[0], key[1])}
                if keep:
                    chosen = (donor, keep)
                    break
            if not chosen:
                continue
            donor, keep = chosen
            for (map_id, terrain), levels in sorted(keep.items()):
                # One row per map, carrying the donor's whole level SPREAD.
                # Keeping the spread is what makes the addition read like a
                # native band rather than a single stamped-in level, and
                # keeping it in ONE row means the tier is the species' share
                # of that map rather than the tier times however many levels
                # the donor happened to list.
                out.append({
                    "species": species,
                    "map": map_id,
                    "method": terrain,
                    "levels": sorted(set(levels)),
                    "tier": TIER_OVERRIDES.get(species, "UNCOMMON"),
                    "donor": donor,
                })
        rows[version] = out
    return rows


def union(rows):
    """One table for all three versions, deduped.

    A row is applied at load time only when its species has no renewable
    source in the tables actually merged on this install, which is the same
    question the derivation asked -- so a Red row cannot fire on Blue, no
    version has to be detected, and a species another encounter mod already
    provided is left alone.  Two target versions deriving the same species
    from the same donor produce byte-identical rows, so the dedupe is exact
    rather than a merge; a genuine disagreement is a bug and raises.
    """
    seen, out = {}, []
    for version in VERSIONS:
        for row in rows[version]:
            key = (row["species"], row["map"], row["method"])
            existing = seen.get(key)
            if existing is None:
                seen[key] = row
                out.append(row)
                continue
            if (existing["levels"] != row["levels"]
                    or existing["tier"] != row["tier"]):
                raise SystemExit(
                    "derivation disagrees for %s on %s: %r vs %r"
                    % (key, version, existing, row))
    out.sort(key=lambda r: (r["species"], r["map"], r["method"]))
    return out


def wrap_comment(text, indent, width=76):
    words, lines, current = text.split(), [], indent + "--"
    for word in words:
        if len(current) + 1 + len(word) > width:
            lines.append(current)
            current = indent + "--"
        current += " " + word
    lines.append(current)
    return lines


def lua_rows(version, rows):
    by_species = {}
    for row in rows:
        by_species.setdefault(row["species"], []).append(row)
    out = []
    for species in sorted(by_species):
        group = by_species[species]
        donor = group[0]["donor"]
        maps = sorted({row["map"] for row in group})
        out.extend(wrap_comment(
            "%s: %s puts it on %s. Gen151 gives %s the same maps at the "
            "substitution rate, carrying %s's own levels."
            % (species, donor.upper(), ", ".join(maps), version,
               donor.upper()), "  "))
        for row in group:
            levels = ", ".join(str(n) for n in row["levels"])
            out.append(
                '  { species = "%s", map = "%s", method = "%s",\n'
                '    levels = { %s }, tier = "%s", feature = "exclusives",\n'
                '    why = "%s\'s own %s table" },'
                % (row["species"], row["map"], row["method"], levels,
                   row["tier"], row["donor"].upper(), row["method"]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", default="tests/fixtures/vanilla.lua")
    ap.add_argument("--recomp", required=True)
    ap.add_argument("--pokered", required=True)
    ap.add_argument("--pokeyellow", required=True)
    ap.add_argument("--json", help="emit the derived rows as JSON instead")
    args = ap.parse_args()

    report = load_fixture(args.fixture)
    root = {
        "recomp": args.recomp,
        "red": (args.pokered, {"_RED"}, False),
        "blue": (args.pokered, {"_BLUE"}, False),
        "yellow": (args.pokeyellow, {"_YELLOW"}, True),
    }
    tables = {v: encounters_for(v, root) for v in VERSIONS}
    rows = derive(report, tables)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(rows, handle, indent=1, sort_keys=True)
        print("wrote " + args.json)
        return

    for line in lua_rows("every version that is missing it", union(rows)):
        print(line)


if __name__ == "__main__":
    main()
