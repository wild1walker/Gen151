# Gen151

Every one of the 151 becomes obtainable **renewably** in a single save, on any
one version, without trading — while every encounter that exists in the vanilla
game keeps its exact vanilla behaviour.

For [Pokemon Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), mod API 2,
Red / Blue / Yellow.

```sh
# drop it in and play
cp -r Gen151 <gen1recomp>/mods/gen151

# or check it first
python3 tools/modkit.py validate mods/gen151 --base imported
python3 tools/modkit.py lint mods/gen151
```

---

## The two words

**Renewable.** Not "obtainable". A one-time static, a gift NPC or a scripted
event does not count, even when it fills the dex slot. If you KO it, flee, run
out of Balls, or want a second one to evolve, the game has to be able to
produce another. Every species Gen151 touches ends up in a table that can be
rolled again tomorrow.

**Additive.** Gen151 never rewrites a vanilla encounter slot, never changes a
vanilla encounter rate, and never removes a species from a table it already
occupies. The only new thing that can happen is a new thing.

What that costs, stated plainly: vanilla species' **share** of a placed map's
encounters shifts by the substitution rate. Probability is conserved and
something has to give. It is bounded by the rarity tier, it is listed per row in
[SPOILERS.md](SPOILERS.md), and it is a single number you can turn down — or off
— in the options.

---

## What it actually does

Nothing here was hand-listed. `tools/gapset.py` reads the
[pret](https://github.com/pret/pokered) disassembly with the same parse the
engine's own extractor performs and computes, for Red, Blue and Yellow
separately, which of the 151 have no renewable source. That gap set is what the
placements answer.

| | Red | Blue | Yellow |
|---|---|---|---|
| renewable in vanilla | 86 / 151 | 86 / 151 | 85 / 151 |
| placed by Gen151 | 23 | 23 | 23 |
| follows by evolution | 16 | 16 | 18 |
| LINK CABLE | 4 | 4 | 4 |
| left alone on purpose | 4 | 4 | 4 |

The four left alone are Articuno, Zapdos, Moltres and Mewtwo — see
[Legendaries](#legendaries) below.

**Version exclusives** get the answer the sibling cartridge already gave. Blue
puts Sandshrew on Routes 4, 8, 9, 10, 11 and 23; Gen151 gives Red the same maps
at the substitution rate, carrying Blue's own levels. Yellow puts Farfetch'd on
Routes 12 and 13 and Lickitung in Cerulean Cave; Red and Blue get those. It is
the most defensible source there is, and it makes the addition feel like it was
always there, because on the other cartridge it was.

**Everything else** is a design decision with a written justification, one per
row, in `placements.lua`. Where a later official Kanto game answered "where does
this live" — Let's Go's wild Bulbasaur in Viridian Forest, its Charmander on
Route 3, its Squirtle on Route 25 — that answer is used verbatim. Where no
official game ever placed the species in Kanto at all, the location is invented
and the reasoning is written down next to it.

**Levels** come from the destination map, never from the species' vanilla gift
level. A Charmander that spawns on Victory Road at level 5 is a dex checkbox; at
the area's band it is a Pokemon you might actually use. Because the three
cartridges disagree about their own bands by as much as twenty levels, the band
is read at load time rather than written down.

---

## Trade evolutions: the LINK CABLE

Alakazam, Machamp, Golem and Gengar are not spawns. Their pre-evolutions are
already in the vanilla grass on every version; what was missing was the trade.

**Celadon Department Store 4F** sells a LINK CABLE for **2100**, on the same
shelf and at the same price as the four evolution stones. It buys exactly one
evolution, the same as a stone does.

Using it runs the evolution as a *trade* evolution, which means B is read and
thrown away exactly as `evolution.asm` does — it always completes, so it always
breaks:

```
. . .
What? KADABRA is
evolving!
        [ the evolution movie ]
KADABRA evolved
into ALAKAZAM!
. . .
ZzZzap!
The LINK CABLE
broke!
```

The break comes **after** the evolution resolves, and only on success. The cable
works, then it fails; reversed, it would read as the evolution failing, and a
consumed item with nothing to show for it is the one outcome that would make
this feel like a tax rather than like flavour.

Why an item and not a level threshold: a level-up rule evolves every Kadabra you
own whether you wanted it or not, and B-cancelling out of it every level is a
bad opt-out.

---

## Finding things

**The dex AREA screen already works.** `TownMap` scans the live encounter tables
and blinks a nest icon on every matching map, so every species Gen151 adds to a
slot table shows up there automatically — no UI code, no contact with the dex at
all. That is why slot placement is preferred over the Super Rod everywhere the
choice exists.

**FIELD NOTES** is in your bag from the start. It lists what you have not caught
yet and, for each, the map, the method, the level band, the rarity and the gate:

```
SEAFOAM IS. B4F, Lv31-33
in the grass
        [ next page ]
Very rare there.
Needs STRENGTH
```

Every line is composed from the same placement rows the roll layer is using, so
a hint cannot drift from the spawn it describes. It also covers the two Super
Rod placements, which AREA cannot see.

The notebook is also where anything Gen151 adds to the bag gets explained, at
the top of the list above the species. **Gen 1 has no item descriptions
anywhere** — the mart shows a name and a price, the bag a name and a count;
descriptions arrive in Gen 2 — so this is the only surface a line like this can
live on without the game growing one first:

```
An old LINK CABLE,
modified.
        [ next page ]
Good for one
trade evolution.
        [ next page ]
It does not
survive the job.
```

**A HINT row in the Pokedex** ships as a separate companion mod,
`gen151_hints`, because it is the one feature that needs the
`engine_internals` permission and the base mod should not have to request it.
Install it alongside if you want the row; Gen151 works without it.

---

## Options

Every independent decision is its own row. The single biggest complaint about
the existing all-151 mod is that it is all-or-nothing; someone who wants the
version exclusives but not a wild Mew should not have to fork it.

| Option | Default | What it does |
|---|---|---|
| GEN151 | on | master switch; off registers nothing at all |
| EXCLUSIVES | on | the version-exclusive spawns |
| GIFT MONS | on | starters, Eevee, Lapras, Porygon, the Dojo pair, the NPC-trade mons |
| FOSSILS | on | Omanyte, Kabuto, Aerodactyl |
| SNORLAX | on | the renewable Snorlax |
| TRADE EVOS | LINK CABLE | LINK CABLE, or off entirely |
| CABLE SOUND | on | the snap; charming once, possibly grating on the fourth use |
| MEW EVENT | on | the Mansion journals and what they unlock |
| TEST BENCH | off | the built-in bench, below — not part of normal play |
| RARITY % | 100 | scales every tier at once; 0 disables every substitution |
| HINTS | AREA + DEX ROW | AREA only, + FIELD NOTES, or + the dex row |

There is no legendary option, because there is nothing to toggle — see below.

---

## Decisions worth knowing about

### Legendaries

Articuno, Zapdos, Moltres and Mewtwo keep their vanilla statics, untouched. No
respawn, no wild slot, no option to add one. They are the sole exception to the
renewability rule, and this is deliberate rather than an oversight — please do
not file it as a bug. The practical consequence is that soft-resetting before
the catch stays the way to handle a bad outcome, exactly as in vanilla.

### Snorlax

Not a legendary, and it does not inherit the exception. Both statics stay, and a
third, very rare Snorlax turns up on Routes 13 and 17 — next door to each
sleeper — so a player who KOs or flees both is not locked out.

### Mew

On by default. Mew is not a static and not an ordinary wild slot: reading all
four Pokemon Mansion journals flips an event flag, and only then does Mew become
a very rare renewable encounter in the basement the journals describe.

This is the one part of Gen151 that is an invention rather than a restoration,
which is why it has a switch of its own — turn it off and Mew stays exactly as
unobtainable as the cartridge left it.

Before the flag is set, Mew is **not in the encounter table at all** — otherwise
the AREA screen would spoil the location the moment anyone opened the dex. The
unlock is an event flag, not a save-schema addition, so it survives
uninstall/reinstall and the debug console can read it:

```
flag GEN151_MEW_FOUND
flag GEN151_MEW_FOUND on
```

### Water

Red and Blue give a live surf rate to Routes 19, 20 and 21 and to nothing else;
every other water table on those cartridges is rate 0. Raising a rate is the one
thing this mod will not do, so almost everything lands in grass — which is also
what the caves, towers and the Mansion roll — or on the Super Rod.

---

## How the roll works, and why it is built this way

The tempting approach is to append an eleventh slot and ship an eleven-entry
`buckets` list. Do not.

`buckets` is a list, and under `record` merge semantics a list in a patch
replaces the target list wholesale. If any other installed mod also appends a
slot and ships its own bucket list, one of you wins and the other's vanishes —
and a slots/buckets length mismatch **does not error**. The roll falls off the
end of the loop, `slots[i]` comes back nil, and the encounter silently becomes
"no encounter". Invisible dead rolls that nobody can debug.

So Gen151 splits the concerns:

- **Data layer** — append slots with the documented `{ __append = { row } }`
  wrapper, so two mods appending to the same map both land. Never a bare `slots`
  list. Never a `buckets` key, at all.
- **Roll layer** — wrap `encounter.roll` and own the roll. Stage one runs the
  engine's *own* `Encounter.roll` against the map's original slots using the
  engine's own bucket list, so the encounter rate and the vanilla distribution
  are untouched and the appended slots are unreachable by construction. Stage
  two, only on an encounter stage one already produced, rolls one independent
  check at the placement's rarity and substitutes.

Two properties fall out, and both are tested:

- With every rarity at 0, the RNG stream is identical to a clean install **draw
  for draw** — the layer consumes no random numbers at all on a map with nothing
  to substitute.
- Another mod's `buckets` cannot reach this roll, because it is never read.

The trade-off that buys: on a map Gen151 touches, another encounter mod's
eleventh-and-beyond slots stay unreachable. They already were, unless that mod
shipped its own bucket list — which is the failure mode above.

---

## Testing it by hand

The headless suites cover everything that can be checked without a screen. For
the rest — whether `ZzZzap` renders, whether the cable snap sounds right,
whether AREA blinks the nest, whether a very-rare tier is a hunt or a chore —
there is a test bench built in. Nothing to install:

1. **MODS → Gen151 → TEST BENCH: ON**
2. **START → BENCH** (or OPTIONS → GEN151 BENCH, directly under the MODS row)

It forces the spawns, hands over the kit, plays the sounds on demand and flips
the Mew gate, so a pass that would take an evening takes a few minutes.

The option defaults **off**, and off means nothing registers — no START row, no
screen, no wrap on the encounter chain. It shipped as a separate mod for the
first two releases; that was the wrong shape, because a bench you have to
download and import separately is a bench that is not there when you want it.

## Testing

```sh
# the roll layer, against the engine's own src/world/Encounter.lua
GEN1RECOMP=/path/to/gen1recomp lua tests/roll_test.lua

# placements.lua's invariants: justifications, gates, bands, no orphans
lua tests/placements_test.lua

# end to end, through the engine's real headless loader, on all three
# versions, plus the companion mod's dex row and, if you point it at a
# Gen1Dex checkout, that row inside Gen1Dex's own re-dressed list
cd /path/to/gen1recomp
GEN151=/path/to/Gen151 GEN1DEX=/path/to/Gen1Dex \
  luajit "$GEN151/tests/mod_load_test.lua"

# regenerate everything derived, then diff
./tools/regen.sh /path/to/gen1recomp /path/to/pokered /path/to/pokeyellow
git diff --exit-code placements.lua hints.lua SPOILERS.md tests/fixtures thumbnail.png

# the runtime features: the LINK CABLE's use flow, the Mansion journals and
# the FIELD NOTES screen, all driven through the buses the mod registered on
cd /path/to/gen1recomp
GEN151=/path/to/Gen151 luajit "$GEN151/tests/features_test.lua"

# or all of it at once, which is what CI should run
./tools/check.sh /path/to/gen1recomp /path/to/pokered /path/to/pokeyellow \
  /path/to/Gen1Dex

# build the release archives
./tools/package.sh /path/to/gen1recomp
```

The end-to-end suite asserts every prime directive against the real Kanto
tables: no vanilla species, level or rate changed on any map on any version;
everything added lands in a table that can be rolled again; every gap closes;
and Mew is absent from `data.encounters` until its gate flips. The features
suite drives the LINK CABLE onto a Kadabra and onto a Pidgey, reads all four
journals one at a time, and opens the notebook — through the loader's own hook
and event tables, so what runs is the wiring as installed.

---

## Layout

```
manifest.json
main.lua           wiring
placements.lua     the single source of truth -- every spawn and every hint
build.lua          placements + the pristine tables -> roll rows and appends
roll.lua           the two-stage roll
rarity.lua         the tier table
hints.lua          GENERATED hint vocabulary
linkcable.lua      the trade-evolution item
fieldnotes.lua     the FIELD NOTES key item and its screen
mewgate.lua        the journals, and the spawn they unlock
tools/             the derivation pipeline (not shipped)
tests/             (not shipped)
```

`placements.lua` driving the encounter patches, the hints and SPOILERS.md is the
central structural decision. Everything else is downstream of it.

---

## Credits

By **Wild**.

Derived from the [pret](https://github.com/pret) disassemblies of Pokemon Red,
Blue and Yellow, and built on the encounter, merge and hook seams of
[Pokemon Gen1Recomp](https://github.com/bryanthaboi/gen1recomp).

Tested against a vanilla install and against
[Gen1Dex](https://github.com/wild1walker/Gen1Dex).
