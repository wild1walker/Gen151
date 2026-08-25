"""Assemble placements.lua: hand-authored Set A + derived Set B.

Set A is a design decision per species and lives here in full, with the
justification each row is required to carry (SPEC 4 step 3).  Set B is
derived by tools/gen_placements.py from the sibling cartridges' own tables and
is spliced in, so the version-exclusive rows can never drift from the
disassembly.

    python3 tools/build_placements.py --recomp ... --pokered ... --pokeyellow ...
"""

import argparse
import os
import subprocess
import sys

HEADER = '''-- placements.lua -- the single source of truth (SPEC 8).
--
-- Every spawn Gen151 adds and every hint it prints comes from this table.
-- hints.lua is generated from it, main.lua drives the roll layer from it, and
-- SPOILERS.md is printed from it, so a placement can never disagree with what
-- the mod tells the player about it.
--
-- Row shape:
--
--   species  the id to substitute in
--   map      the map constant it substitutes on
--   method   "grass" (also the caves/towers/Mansion "indoor" roll, which
--            reads the grass table), "water" (surfing), or "super_rod"
--   tier     a key of rarity.lua's TIERS
--   levels   explicit levels, when the placement is copied from a table that
--            already chose them
--   band     "low" / "mid" / "high" -- otherwise, take the destination map's
--            OWN distinct levels and use that third of them.  SPEC 5: "Match
--            the destination map's existing level band, not the species'
--            vanilla gift level."  Deriving it at load time rather than
--            writing it down is what keeps one row correct on all three
--            versions, whose bands differ by up to twenty levels.
--   gate     the progression gate the map sits behind, for the hint text
--   why      one sentence on why this location.  SPEC 4: "If the
--            justification is 'it needed to go somewhere,' the placement is
--            wrong."
--
-- The version tables are additive to `common`, never a replacement for it.
--
-- Set A rows (the design decisions) are authored here.
-- Set B rows (the version exclusives) are DERIVED and spliced in by
-- tools/build_placements.py; tests/placements_test.lua re-derives them and
-- fails if the checked-in rows have drifted.  Edit the tool, not the block.

local P = {}

-- The ladder from SPEC 5, in order.  A placement's gate must sit at or above
-- the rung the vanilla game charged for that species.
-- The ladder from SPEC 5, in the order the game opens it up.  A placement's
-- gate must sit at or above the rung the vanilla game charged for that
-- species; tests/placements_test.lua checks every row against it.
--
-- Spelled the way the game spells them, in caps, because these strings reach
-- the player through the FIELD NOTES text box.
P.GATES = {
  "FLASH", "the SILPH SCOPE", "the FLUTE", "the BICYCLE",
  "the SAFARI ZONE", "SURF", "STRENGTH", "8 BADGES", "the LEAGUE",
}

-- Which rung each map Gen151 touches sits on.  A map with no entry is open
-- Kanto -- reachable on foot with nothing in the bag -- and its hints simply
-- do not print a requirement line, because there is nothing to require.
P.MAP_GATES = {
  ROCK_TUNNEL_1F = "FLASH", ROCK_TUNNEL_B1F = "FLASH",
  POKEMON_TOWER_3F = "the SILPH SCOPE",
  POKEMON_TOWER_7F = "the SILPH SCOPE",
  ROUTE_12 = "the FLUTE", ROUTE_13 = "the FLUTE",
  ROUTE_14 = "the FLUTE", ROUTE_15 = "the FLUTE",
  ROUTE_16 = "the BICYCLE", ROUTE_17 = "the BICYCLE",
  ROUTE_18 = "the BICYCLE",
  SAFARI_ZONE_CENTER = "the SAFARI ZONE", SAFARI_ZONE_EAST = "the SAFARI ZONE",
  SAFARI_ZONE_NORTH = "the SAFARI ZONE", SAFARI_ZONE_WEST = "the SAFARI ZONE",
  ROUTE_19 = "SURF", ROUTE_20 = "SURF", ROUTE_21 = "SURF",
  POWER_PLANT = "SURF",
  POKEMON_MANSION_1F = "SURF", POKEMON_MANSION_2F = "SURF",
  POKEMON_MANSION_3F = "SURF", POKEMON_MANSION_B1F = "SURF",
  SEAFOAM_ISLANDS_1F = "SURF", SEAFOAM_ISLANDS_B1F = "SURF",
  SEAFOAM_ISLANDS_B2F = "SURF", SEAFOAM_ISLANDS_B3F = "SURF",
  -- IsSurfingAllowed bars the B4F stairs until both plug boulders are down
  -- (FieldDefaults.seafoam), so the deepest floor really is STRENGTH-gated.
  SEAFOAM_ISLANDS_B4F = "STRENGTH",
  ROUTE_23 = "8 BADGES", VICTORY_ROAD_1F = "8 BADGES",
  VICTORY_ROAD_2F = "8 BADGES", VICTORY_ROAD_3F = "8 BADGES",
  CERULEAN_CAVE_1F = "the LEAGUE", CERULEAN_CAVE_2F = "the LEAGUE",
  CERULEAN_CAVE_B1F = "the LEAGUE",

}

-- Which mod option each row answers to, so a player who wants the version
-- exclusives but not a wild Charmander gets exactly that (SPEC 7).
P.FEATURES = {
  exclusives = "version exclusives",
  gifts = "one-time gift mons",
  fossils = "fossils",
  snorlax = "Snorlax",
  mew = "Mew",
}

-- ---------------------------------------------------------------- Set A
--
-- Missing on every version for the same reason on every version, so these
-- rows are shared.  Set C follows from them: fixing BULBASAUR fixes IVYSAUR
-- and VENUSAUR, so neither is placed (SPEC 4 step 1).

P.common = {

  -- ---- starters (VERY_RARE, feature "gifts")
  --
  -- Let's Go Pikachu/Eevee is the later official Kanto game that answered
  -- "where would these live", and its answer is used verbatim: Bulbasaur in
  -- Viridian Forest and Cerulean Cave, Charmander on Route 3 and in Rock
  -- Tunnel, Squirtle on Route 25 and in Seafoam Islands.  Two habitats each,
  -- one early and one late, so a player who reaches the endgame still short
  -- of one is not sent back to a level-4 route to find it.
  { species = "BULBASAUR", map = "VIRIDIAN_FOREST", method = "grass",
    band = "low", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild Bulbasaur in Viridian Forest; the forest is "
      .. "also where a starter-less player first walks through tall grass" },
  { species = "BULBASAUR", map = "CERULEAN_CAVE_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's other Bulbasaur habitat, and the late-game copy for a "
      .. "player who finished the game still needing one" },
  { species = "CHARMANDER", map = "ROUTE_3", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild Charmander on Route 3, on the climb to Mt. "
      .. "Moon where a fire type first earns its keep" },
  { species = "CHARMANDER", map = "ROCK_TUNNEL_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's other Charmander habitat; a cave that wants a light "
      .. "source is a fair place to meet one" },
  { species = "SQUIRTLE", map = "ROUTE_25", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild Squirtle on Routes 24 and 25, along Cerulean's "
      .. "waterfront" },
  { species = "SQUIRTLE", map = "SEAFOAM_ISLANDS_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's other Squirtle habitat, and the one sea cave in Kanto" },

  -- ---- the Fighting Dojo's prize pair (RARE, feature "gifts")
  --
  -- No official Kanto game ever put either in the wild, so this is an
  -- invented location, chosen the way SPEC 4 asks: the only Fighting-type
  -- habitat in Kanto's own tables is Victory Road's Machop line, and Victory
  -- Road sits behind all eight badges, which is at least as demanding as
  -- walking into the Dojo.
  { species = "HITMONLEE", map = "VICTORY_ROAD_1F", method = "grass",
    band = "mid", tier = "RARE", feature = "gifts",
    why = "Kanto's only Fighting-type habitat is Victory Road's Machop line; "
      .. "the Dojo's prize pair belongs with them" },
  { species = "HITMONCHAN", map = "VICTORY_ROAD_2F", method = "grass",
    band = "mid", tier = "RARE", feature = "gifts",
    why = "the other half of the Dojo's prize pair, one floor up from its "
      .. "twin so the choice the Dojo made stays a choice" },

  -- ---- the NPC trades (RARE, feature "gifts")
  { species = "MR_MIME", map = "ROUTE_11", method = "grass",
    band = "high", tier = "RARE", feature = "gifts",
    why = "Route 11's Drowzee band is the only Psychic habitat outside the "
      .. "endgame caves, and the Route 2 trade that hands MR.MIME over in "
      .. "vanilla is itself gated on finding an ABRA" },
  { species = "JYNX", map = "SEAFOAM_ISLANDS_B2F", method = "grass",
    band = "mid", tier = "RARE", feature = "gifts",
    why = "an Ice type belongs in the ice cave; Seafoam is also the only "
      .. "place in Kanto its Seel and Dewgong neighbours live" },

  -- ---- the gifts (RARE, feature "gifts")
  { species = "LAPRAS", map = "ROUTE_20", method = "water", band = "high",
    tier = "RARE", feature = "gifts",
    why = "the open sea between Fuchsia and Cinnabar, past the Seafoam "
      .. "Islands -- the one stretch of Kanto where surfing something that "
      .. "big reads as ordinary" },
  { species = "EEVEE", map = "ROUTE_7", method = "grass", band = "mid",
    tier = "RARE", feature = "gifts",
    why = "Route 7 is the Celadon approach, so the gate is the same one the "
      .. "Celadon Mansion gift sits behind" },
  { species = "PORYGON", map = "POWER_PLANT", method = "grass", band = "mid",
    tier = "RARE", feature = "gifts",
    why = "the only man-made-Pokemon habitat in Kanto: a building full of "
      .. "Magnemite and Voltorb, behind SURF rather than a coin counter" },

  -- ---- the fossils (VERY_RARE, feature "fossils")
  --
  -- Invented locations: no official Kanto game puts any of the three in a
  -- wild table.  The gate is the constraint that decided them -- vanilla
  -- charges a Cinnabar Lab revival for all three, so none of them may appear
  -- anywhere reachable before SURF, which rules out Mt. Moon, where the
  -- fossils are actually found.
  { species = "OMANYTE", map = "SEAFOAM_ISLANDS_B4F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "fossils",
    why = "the deepest floor of the sea cave, behind SURF and STRENGTH: a "
      .. "living ammonite belongs where the water never reached the surface" },
  { species = "KABUTO", map = "SEAFOAM_ISLANDS_B3F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "fossils",
    why = "one floor above its Helix counterpart, so the two fossils keep "
      .. "the separation the Mt. Moon choice gave them" },
  { species = "AERODACTYL", map = "VICTORY_ROAD_3F", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the top of the last rock cave before the League: the only place "
      .. "in Kanto whose band suits a revived AERODACTYL and whose gate is "
      .. "at least as demanding as the Old Amber's Cinnabar Lab" },

  -- ---- Snorlax (VERY_RARE, feature "snorlax")
  --
  -- SPEC 5: both statics stay; this is the renewable copy so a player who
  -- KOs or flees both is not locked out.  The two statics sleep on Routes 12
  -- and 16, so their immediate neighbours are where a third one wandered to.
  { species = "SNORLAX", map = "ROUTE_13", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "snorlax",
    why = "next door to the Route 12 sleeper: one that wandered south and "
      .. "found somewhere quieter" },
  { species = "SNORLAX", map = "ROUTE_17", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "snorlax",
    why = "next door to the Route 16 sleeper, down the length of Cycling "
      .. "Road" },

  -- ---- Mew (VERY_RARE, feature "mew", gated)
  --
  -- Not a static and not an ordinary wild slot: the row only exists once the
  -- Mansion journals have been read, and until then the species is not in
  -- data.encounters at all, so the AREA screen cannot spoil it.
  { species = "MEW", map = "POKEMON_MANSION_B1F", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "mew", gated = "mew",
    why = "the basement the journals describe: MEW was here before MEWTWO "
      .. "was, and reading all four diaries is what brings it back" },
}

-- ---------------------------------------------------------- Super Rod
--
-- The `encounter.fishing` hook, which touches no grass table and cannot
-- conflict with any encounter mod.  Substitution rather than an extra pool
-- entry: the engine's rejection loop picks `floor(r/2) % 4`, so a fifth entry
-- in a Super Rod group is unreachable no matter who adds it.
--
-- These rows are invisible to the AREA screen (SPEC 6a), so every one of them
-- is covered explicitly by the FIELD NOTES hints.
P.fishing = {
  { species = "OMANYTE", map = "SEAFOAM_ISLANDS_B4F", rod = "SUPER_ROD",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the same floor as its grass row, for a player carrying a rod "
      .. "instead of a repel" },
  { species = "KABUTO", map = "SEAFOAM_ISLANDS_B3F", rod = "SUPER_ROD",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the same floor as its grass row" },
}

-- ---------------------------------------------------------------- Set B
--
-- DERIVED.  Do not hand-edit: tools/build_placements.py regenerates this
-- block and tests/placements_test.lua fails if it has drifted.
--
-- The rule: a species missing from one version is present on another, and
-- that other version already answered every question a placement has to
-- answer -- which maps, which levels, which company.  Re-using its answer is
-- the most defensible source there is, and it makes the addition feel like it
-- was always there, because on the other cartridge it was.
--
-- Two rows carry a tier the rule cannot derive.  FARFETCHD and LICKITUNG are
-- wild on Yellow but cost an NPC trade on Red and Blue, so Yellow's tables
-- give the location and Red's price gives the tier.
--
-- One table, not three.  Every row here -- and every row in P.common above --
-- is applied only when its species has no renewable source in the tables
-- actually merged on this install, which is the same question the derivation
-- asked.  So a Red row cannot fire on Blue, no version has to be detected at
-- all, and a species some other encounter mod already provided is left alone
-- rather than provided twice.

P.gapFill = {
'''

FOOTER = '''}

return P
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--recomp", required=True)
    ap.add_argument("--pokered", required=True)
    ap.add_argument("--pokeyellow", required=True)
    ap.add_argument("--out", default="placements.lua")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    proc = subprocess.run(
        [sys.executable, os.path.join(here, "gen_placements.py"),
         "--recomp", args.recomp, "--pokered", args.pokered,
         "--pokeyellow", args.pokeyellow],
        capture_output=True, text=True, check=True)
    setb = [line for line in proc.stdout.splitlines()
            if not line.startswith("wrote ")]

    body = setb

    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(HEADER)
        handle.write("\n".join(body))
        handle.write("\n")
        handle.write(FOOTER)
    print("wrote " + args.out)


if __name__ == "__main__":
    main()
