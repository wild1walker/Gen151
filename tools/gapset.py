"""Derive the Gen151 gap set from ground truth (SPEC 2a/2b, 4 step 1).

Nothing here is hand-written content.  Every fact comes from either
gen1recomp's own extractor (tools/extract), which is the code that produces
the `data/generated/encounters.lua` the engine rolls against, or from the
pret disassembly those extractors parse.

Usage:
    python3 tools/gapset.py --recomp <gen1recomp> --pokered <pokered>
                            --pokeyellow <pokeyellow> [--json out.json]

Output: Sets A / B / C per version, plus the vanilla acquisition method for
every Set A member, read out of the pret scripts rather than asserted.
"""

import argparse
import json
import os
import re
import sys
import tempfile


# ------------------------------------------------------------------ helpers

def load_extractors(recomp):
    sys.path.insert(0, os.path.join(recomp, "tools"))
    from extract import constants, encounters, util  # noqa: E402
    return constants, encounters, util


def read_asm_lines(path, defines):
    """A local copy of util.read_asm's conditional resolution.

    gen1recomp's util hardcodes ASM_DEFINES = {"_RED"} at import time and
    several extractors read it through the module global, so rather than
    mutate that from underneath them we resolve conditionals ourselves
    wherever this script parses asm directly.
    """
    lines = []
    stack = []
    with open(path, encoding="utf-8") as handle:
        for lineno, raw in enumerate(handle, 1):
            line = strip_comment(raw.rstrip("\n"))
            s = line.strip()
            m = re.match(r"IF\s+DEF\((\w+)\)\s*\|\|\s*DEF\((\w+)\)\s*$", s, re.I)
            if m:
                stack.append([any(n in defines for n in m.groups()), True])
                continue
            m = re.match(r"IF\s+(!)?DEF\((\w+)\)\s*$", s, re.I)
            if m:
                defined = m.group(2) in defines
                stack.append([(not defined) if m.group(1) else defined, True])
                continue
            if re.match(r"IF\b", s):
                stack.append([True, False])
                continue
            if re.match(r"ELSE\s*$", s, re.I) and stack:
                if stack[-1][1]:
                    stack[-1][0] = not stack[-1][0]
                continue
            if re.match(r"ENDC\s*$", s, re.I) and stack:
                stack.pop()
                continue
            if any(not frame[0] for frame in stack):
                continue
            lines.append((lineno, line))
    return lines


def strip_comment(line):
    out = []
    in_str = False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == ";" and not in_str:
            break
        out.append(ch)
    return "".join(out)


# --------------------------------------------------------------- encounters

def parse_wild_tables(root, defines):
    """data/wild/maps/*.asm -> label -> {grass, water} (rate + slots)."""
    tables = {}
    wild_dir = os.path.join(root, "data/wild/maps")
    for fname in sorted(os.listdir(wild_dir)):
        if not fname.endswith(".asm"):
            continue
        grass = water = current = None
        for _, line in read_asm_lines(os.path.join(wild_dir, fname), defines):
            s = line.strip()
            m = re.match(r"(\w+):{1,2}\s*$", s)
            if m:
                grass = {"rate": 0, "slots": []}
                water = {"rate": 0, "slots": []}
                tables[m.group(1)] = {"grass": grass, "water": water,
                                      "source": f"data/wild/maps/{fname}"}
                current = None
                continue
            m = re.match(r"def_grass_wildmons\s+(\d+)", s)
            if m:
                grass["rate"] = int(m.group(1))
                current = grass
                continue
            m = re.match(r"def_water_wildmons\s+(\d+)", s)
            if m:
                water["rate"] = int(m.group(1))
                current = water
                continue
            if s.startswith(("end_grass_wildmons", "end_water_wildmons")):
                current = None
                continue
            m = re.match(r"db\s+(\d+)\s*,\s*(\w+)\s*$", s)
            if m and current is not None:
                current["slots"].append({"level": int(m.group(1)),
                                         "species": m.group(2)})
    return tables


def parse_wild_pointers(root, defines):
    pointers = []
    path = os.path.join(root, "data/wild/grass_water.asm")
    for _, line in read_asm_lines(path, defines):
        m = re.match(r"dw\s+(\w+)$", line.strip())
        if m:
            pointers.append(m.group(1))
    return pointers


def build_encounters(root, defines, map_order):
    tables = parse_wild_tables(root, defines)
    pointers = parse_wild_pointers(root, defines)
    out = {}
    for i, label in enumerate(pointers):
        if i >= len(map_order):
            break
        if label == "NothingWildMons":
            continue
        table = tables.get(label)
        if table is None:
            continue
        entry = {"source": table["source"]}
        for kind in ("grass", "water"):
            if table[kind]["rate"] > 0 or table[kind]["slots"]:
                entry[kind] = table[kind]
        out[map_order[i]] = entry
    return out


# ---------------------------------------------------------------- super rod

def parse_super_rod(root, defines):
    """Red/Blue: dbw MAP, .GroupN then db level, SPECIES rows."""
    path = os.path.join(root, "data/wild/super_rod.asm")
    groups, per_map, current = {}, [], None
    for _, line in read_asm_lines(path, defines):
        s = line.strip()
        m = re.match(r"dbw\s+(\w+),\s*\.(\w+)", s)
        if m:
            per_map.append((m.group(1), m.group(2)))
            continue
        m = re.match(r"\.(\w+):?\s*$", s)
        if m:
            current = m.group(1)
            groups.setdefault(current, [])
            continue
        m = re.match(r"db\s+(\d+),\s*(\w+)$", s)
        if m and current:
            groups[current].append({"level": int(m.group(1)),
                                    "species": m.group(2)})
    return {map_id: groups.get(group, []) for map_id, group in per_map}


def parse_super_rod_yellow(root, defines):
    """Yellow: db MAP, SPECIES, level, SPECIES, level, ... (four pairs)."""
    path = os.path.join(root, "data/wild/super_rod.asm")
    out = {}
    for _, line in read_asm_lines(path, defines):
        s = line.strip()
        m = re.match(r"db\s+([A-Z0-9_]+)\s*,\s*(.+)$", s)
        if not m:
            continue
        rest = [a.strip() for a in m.group(2).split(",")]
        if len(rest) < 2 or len(rest) % 2 != 0:
            continue
        slots = []
        ok = True
        for i in range(0, len(rest), 2):
            species, level = rest[i], rest[i + 1]
            if not re.match(r"^[A-Z0-9_]+$", species) or not level.isdigit():
                ok = False
                break
            slots.append({"level": int(level), "species": species})
        if ok and slots:
            out[m.group(1)] = slots
    return out


def parse_good_rod(root, defines):
    path = os.path.join(root, "data/wild/good_rod.asm")
    slots = []
    if not os.path.exists(path):
        return slots
    for _, line in read_asm_lines(path, defines):
        m = re.match(r"db\s+(\d+),\s*(\w+)$", line.strip())
        if m:
            slots.append({"level": int(m.group(1)), "species": m.group(2)})
    return slots


# ---------------------------------------------------------------- evolutions

def parse_evolutions(root, defines):
    """data/pokemon/evos_moves.asm -> species -> [ {method, into} ]."""
    path = os.path.join(root, "data/pokemon/evos_moves.asm")
    evos = {}
    current = None
    for _, line in read_asm_lines(path, defines):
        s = line.strip()
        m = re.match(r"(\w+)EvosMoves:\s*$", s)
        if m:
            current = m.group(1)
            evos[current] = []
            continue
        if current is None:
            continue
        m = re.match(r"db\s+EVOLVE_LEVEL\s*,\s*(\d+)\s*,\s*(\w+)", s)
        if m:
            evos[current].append({"method": "LEVEL", "level": int(m.group(1)),
                                  "into": m.group(2)})
            continue
        m = re.match(r"db\s+EVOLVE_ITEM\s*,\s*(\w+)\s*,\s*\d+\s*,\s*(\w+)", s)
        if m:
            evos[current].append({"method": "ITEM", "item": m.group(1),
                                  "into": m.group(2)})
            continue
        m = re.match(r"db\s+EVOLVE_TRADE\s*,\s*\d+\s*,\s*(\w+)", s)
        if m:
            evos[current].append({"method": "TRADE", "into": m.group(1)})
    return evos


def evos_moves_label_to_species(species_order, root, defines):
    """Map the EvosMoves label prefix onto the species constant.

    EvosMovesPointerTable is in internal index order, which is exactly what
    constants.speciesOrder is, so the two zip.
    """
    path = os.path.join(root, "data/pokemon/evos_moves.asm")
    labels = []
    for _, line in read_asm_lines(path, defines):
        m = re.match(r"dw\s+(\w+)EvosMoves\s*$", line.strip())
        if m:
            labels.append(m.group(1))
    return dict(zip(labels, species_order))


# -------------------------------------------------------- acquisition source

def parse_trades(root, defines):
    path = os.path.join(root, "data/events/trades.asm")
    trades = []
    if not os.path.exists(path):
        return trades
    for _, line in read_asm_lines(path, defines):
        m = re.match(r'npctrade\s+(\w+),\s*(\w+),\s*(\w+),\s*"([^"]*)"',
                     line.strip())
        if m:
            trades.append({"give": m.group(1), "get": m.group(2)})
    return trades


def scan_scripts(root, defines, species_set):
    """Every mention of a species constant under scripts/ and data/, so an
    acquisition method is read out of the tree instead of remembered."""
    hits = {s: [] for s in species_set}
    roots = [os.path.join(root, "scripts"), os.path.join(root, "data")]
    pattern = re.compile(r"\b([A-Z][A-Z0-9_]+)\b")
    for base in roots:
        for dirpath, _, files in os.walk(base):
            if os.path.join("data", "wild") in dirpath:
                continue
            for fname in files:
                if not fname.endswith(".asm"):
                    continue
                full = os.path.join(dirpath, fname)
                rel = os.path.relpath(full, root)
                try:
                    lines = read_asm_lines(full, defines)
                except (UnicodeDecodeError, OSError):
                    continue
                for lineno, line in lines:
                    for token in pattern.findall(line):
                        if token in hits:
                            hits[token].append((rel, lineno, line.strip()))
    return hits


# ------------------------------------------------------------------- gap set

REPEATABLE_KINDS = ("grass", "water", "super_rod", "good_rod", "old_rod")


def repeatable_sources(encounters, super_rod, good_rod):
    """species -> list of (kind, map) for every renewable table it sits in."""
    out = {}

    def add(species, kind, where):
        out.setdefault(species, []).append((kind, where))

    for map_id, entry in encounters.items():
        for kind in ("grass", "water"):
            group = entry.get(kind)
            if not group:
                continue
            for slot in group["slots"]:
                add(slot["species"], kind, map_id)
    for map_id, slots in super_rod.items():
        for slot in slots:
            add(slot["species"], "super_rod", map_id)
    for slot in good_rod:
        add(slot["species"], "good_rod", "ANY")
    add("MAGIKARP", "old_rod", "ANY")  # FieldDefaults.FISHING.OLD_ROD
    return out


def reachable_by_evolution(repeatable, evolutions, label_map):
    """Species obtainable by evolving something that has a repeatable source.

    Trade evolutions do NOT count as reachable in vanilla single-save play,
    which is exactly why they are in the gap set.
    """
    have = set(repeatable)
    reached = {}
    changed = True
    while changed:
        changed = False
        for label, rows in evolutions.items():
            parent = label_map.get(label)
            if parent is None or parent not in have:
                continue
            for row in rows:
                if row["method"] == "TRADE":
                    continue
                if row["into"] not in have:
                    have.add(row["into"])
                    reached[row["into"]] = (parent, row["method"])
                    changed = True
    return have, reached


def blocked_evolutions(repeatable, evolutions, label_map):
    """Species whose only route from a repeatable parent is a trade."""
    have = set(repeatable)
    out = {}
    for label, rows in evolutions.items():
        parent = label_map.get(label)
        if parent is None:
            continue
        for row in rows:
            if row["method"] == "TRADE" and parent in have:
                out[row["into"]] = parent
    return out


# ---------------------------------------------------------------------- main

def version_data(recomp, root, defines, yellow=False):
    constants_mod, _, _ = load_extractors(recomp)
    with tempfile.TemporaryDirectory() as tmp:
        consts = constants_mod.extract(root, tmp)
    map_order = consts["mapOrder"]
    species_order = [s for s in consts["speciesOrder"] if s != "UNUSED"]
    encounters = build_encounters(root, defines, map_order)
    super_rod = (parse_super_rod_yellow(root, defines) if yellow
                 else parse_super_rod(root, defines))
    good_rod = parse_good_rod(root, defines)
    evolutions = parse_evolutions(root, defines)
    label_map = evos_moves_label_to_species(consts["speciesOrder"], root, defines)
    return {
        "root": root,
        "defines": defines,
        "mapOrder": map_order,
        "speciesOrder": species_order,
        "encounters": encounters,
        "superRod": super_rod,
        "goodRod": good_rod,
        "evolutions": evolutions,
        "labelMap": label_map,
        "trades": parse_trades(root, defines),
    }


def parents_of(evolutions, label_map):
    """child -> list of (parent, method)."""
    out = {}
    for label, rows in evolutions.items():
        parent = label_map.get(label)
        if parent is None:
            continue
        for row in rows:
            out.setdefault(row["into"], []).append((parent, row["method"]))
    return out


def classify(data, all_species):
    repeatable = repeatable_sources(data["encounters"], data["superRod"],
                                    data["goodRod"])
    have, reached = reachable_by_evolution(repeatable, data["evolutions"],
                                           data["labelMap"])
    blocked = blocked_evolutions(repeatable, data["evolutions"],
                                 data["labelMap"])
    parents = parents_of(data["evolutions"], data["labelMap"])
    missing = [s for s in all_species if s not in have]
    missing_set = set(missing)

    # Set C: missing only because a missing ancestor is missing.  A trade
    # evolution is never Set C -- fixing the parent does not fix it, which is
    # the whole reason it needs an item (SPEC 4 step 2).
    set_c, set_a = {}, []
    for species in missing:
        via = None
        for parent, method in parents.get(species, []):
            if method != "TRADE" and parent in missing_set:
                via = (parent, method)
                break
        if via:
            set_c[species] = via
        else:
            set_a.append(species)
    return {
        "repeatable": repeatable,
        "reachableByEvolution": reached,
        "blockedTradeEvolutions": blocked,
        "missing": missing,
        "setA": set_a,
        "setC": set_c,
        "parents": parents,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--recomp", required=True)
    ap.add_argument("--pokered", required=True)
    ap.add_argument("--pokeyellow", required=True)
    ap.add_argument("--json")
    ap.add_argument("--lua",
                    help="write the derived vanilla tables as a Lua fixture")
    args = ap.parse_args()

    versions = {
        "red": (args.pokered, {"_RED"}, False),
        "blue": (args.pokered, {"_BLUE"}, False),
        "yellow": (args.pokeyellow, {"_YELLOW"}, True),
    }

    out = {}
    for name, (root, defines, yellow) in versions.items():
        data = version_data(args.recomp, root, defines, yellow)
        out[name] = data

    # The 151 in dex order, from the Red tree (the dex numbering is shared).
    dex = dex_order(args.pokered, {"_RED"})
    all_species = [s for s in dex if s]

    report = {"dex": all_species, "versions": {}}
    for name, data in out.items():
        result = classify(data, all_species)
        report["versions"][name] = {
            "acquisition": acquisition_evidence(
                out[name], set(result["setA"])),
            "missing": result["missing"],
            "setA": result["setA"],
            "setC": {k: list(v) for k, v in result["setC"].items()},
            "blockedTradeEvolutions": result["blockedTradeEvolutions"],
            "reachableByEvolution": {
                k: list(v) for k, v in result["reachableByEvolution"].items()},
            "repeatableCount": len(result["repeatable"]),
            "repeatable": {k: v for k, v in result["repeatable"].items()},
            "trades": data["trades"],
        }

    # Set B: obtainable renewably on one version (directly or by evolving
    # something that is), absent from another.  Computed over the reachable
    # set rather than the raw slot tables, so Hypno -- a wild slot on Red and
    # a Drowzee evolution on Yellow -- is correctly NOT a gap.
    per = {n: set(all_species) - set(report["versions"][n]["missing"])
           for n in versions}
    exclusive = {}
    for species in all_species:
        present = sorted(n for n in versions if species in per[n])
        if present and len(present) < len(versions):
            exclusive[species] = present
    report["versionExclusive"] = exclusive

    if args.lua:
        write_lua_fixture(args.lua, out, report)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1, sort_keys=True)
    print_report(report, all_species)


# Where a species that has no renewable table is handed out instead.  Each
# rule is a path prefix plus the shape of the mention, so the classification
# is read out of the pret tree rather than asserted (SPEC 4 step 2).
ACQUISITION_RULES = (
    ("data/events/trades.asm", "npc_trade"),
    ("scripts/", "script"),
    ("data/maps/objects/", "map_object"),
    ("data/events/", "event_data"),
    ("data/items/", "item_data"),
)


def acquisition_evidence(data, species):
    """species -> [{kind, file, line, text}] for every non-wild mention."""
    hits = scan_scripts_for(data["root"], data["defines"], species)
    out = {}
    for name, rows in hits.items():
        if not rows:
            continue
        tagged = []
        for rel, lineno, text in rows:
            kind = "other"
            for prefix, label in ACQUISITION_RULES:
                if rel.replace("\\", "/").startswith(prefix):
                    kind = label
                    break
            tagged.append({"kind": kind, "file": rel, "line": lineno,
                           "text": text})
        out[name] = tagged
    for name in species:
        for row in data["trades"]:
            if row["get"] == name:
                out.setdefault(name, []).insert(
                    0, {"kind": "npc_trade", "file": "data/events/trades.asm",
                        "line": 0,
                        "text": f"wants {row['give']}, gives {row['get']}"})
    return out


def scan_scripts_for(root, defines, species):
    import re as _re
    hits = {s: [] for s in species}
    pattern = _re.compile(r"\b([A-Z][A-Z0-9_]+)\b")
    for base in ("scripts", "data"):
        base_dir = os.path.join(root, base)
        if not os.path.isdir(base_dir):
            continue
        for dirpath, _, files in os.walk(base_dir):
            rel_dir = os.path.relpath(dirpath, root).replace("\\", "/")
            if rel_dir.startswith("data/wild") or rel_dir.startswith("data/pokemon"):
                continue
            for fname in sorted(files):
                if not fname.endswith(".asm"):
                    continue
                full = os.path.join(dirpath, fname)
                rel = os.path.relpath(full, root).replace("\\", "/")
                try:
                    lines = read_asm_lines(full, defines)
                except (UnicodeDecodeError, OSError):
                    continue
                for lineno, line in lines:
                    for token in pattern.findall(line):
                        if token in hits:
                            hits[token].append((rel, lineno, line.strip()))
    return hits


def dex_order(root, defines):
    """constants/pokedex_constants.asm gives DEX_<NAME> in dex order."""
    path = os.path.join(root, "constants/pokedex_constants.asm")
    names = []
    for _, line in read_asm_lines(path, defines):
        m = re.match(r"const\s+DEX_(\w+)", line.strip())
        if m:
            names.append(m.group(1))
    return names


def lua_value(value, indent=0):
    pad = "  " * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = []
        for key in sorted(value):
            k = (key if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", str(key))
                 else '["%s"]' % key)
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", str(key)):
                rows.append("%s  %s = %s," % (pad, k, lua_value(value[key], indent + 1)))
            else:
                rows.append("%s  %s = %s," % (pad, k, lua_value(value[key], indent + 1)))
        return "{\n" + "\n".join(rows) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "{}"
        rows = ["%s  %s," % (pad, lua_value(v, indent + 1)) for v in value]
        return "{\n" + "\n".join(rows) + "\n" + pad + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return '"%s"' % str(value).replace('"', '\\"')


def write_lua_fixture(path, out, report):
    """The derived vanilla tables, for tests and for placement validation.

    Source-derived (pret disassembly), never ROM-derived, and kept out of the
    packaged mod by .modkitignore -- the shipped mod reads the player's own
    generated tables at runtime and never carries a copy.
    """
    fixture = {"versions": {}, "dex": report["dex"]}
    for name, data in out.items():
        fixture["versions"][name] = {
            "encounters": data["encounters"],
            "superRod": data["superRod"],
            "goodRod": data["goodRod"],
            "setA": report["versions"][name]["setA"],
            "setC": report["versions"][name]["setC"],
            "missing": report["versions"][name]["missing"],
        }
    fixture["versionExclusive"] = report["versionExclusive"]
    body = ("-- GENERATED by tools/gapset.py from the pret disassembly.\n"
            "-- Do not hand-edit; re-run the script instead.\n"
            "return " + lua_value(fixture) + "\n")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)
    print("wrote " + path)


def print_report(report, all_species):
    for name in ("red", "blue", "yellow"):
        v = report["versions"][name]
        print(f"\n=== {name.upper()} ===")
        print(f"repeatable species: {v['repeatableCount']}/151")
        print(f"Set A ({len(v['setA'])}) -- no repeatable source, "
              f"not fixed by an ancestor:")
        print("  " + ", ".join(v["setA"]))
        print(f"Set C ({len(v['setC'])}) -- follows from a Set A/B parent:")
        for species, (parent, method) in sorted(v["setC"].items()):
            print(f"  {species:<12} <- {parent} ({method})")
        print("trade-evolution blocked (repeatable parent, no route): "
              + ", ".join(sorted(v["blockedTradeEvolutions"])))
    print("\n=== Set B: version-exclusive ===")
    for species, present in sorted(report["versionExclusive"].items()):
        absent = [n for n in ("red", "blue", "yellow") if n not in present]
        print(f"  {species:<12} on {'/'.join(present):<18} missing from "
              f"{'/'.join(absent)}")


if __name__ == "__main__":
    main()
