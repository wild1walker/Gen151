# Gen151 Debug

A test bench for the parts of [Gen151](https://github.com/wild1walker/Gen151)
that only exist once a game is running.

```sh
cp -r Gen151/gen151_debug <gen1recomp>/mods/gen151_debug
```

Then in game: **OPTIONS → GEN151 BENCH**. No developer build, no console.

**This is a development tool, not part of normal play.** It is a separate mod
so that not installing it — or deleting it — is all it takes, and so Gen151
itself carries no debug rows in its own options. It is published alongside
Gen151 only because there is otherwise no way to get it.

## Why it exists

Everything Gen151 does to the encounter tables is covered by headless tests —
no vanilla slot moves, the RNG stream is identical at zero rarity, every gap
closes. What those cannot reach is anything that has to be *seen* or *heard*:

- does `ZzZzap` render in the font?
- does the cable snap sound like an electrical fault or like a mistake?
- does the FIELD NOTES list fit its box, and do its hints match what you met?
- does the dex AREA screen really blink a nest on the maps Gen151 added to?
- is a very-rare tier a satisfying hunt, or just a long one?

Reaching those in normal play means buying a cable, finding a Kadabra, surfing
to Cinnabar, and walking through grass a few thousand times. This collapses
that into a menu.

## The rows

| Row | What it is for |
|---|---|
| `CHECKLIST` | The list below, in the game, in the order it is cheapest to work through. |
| `KIT` | 5 LINK CABLEs, all three rods, the FLUTE and the SILPH SCOPE into the bag; a Kadabra, Machoke, Graveler and Haunter into the party — one for each cable. |
| `SPAWNS: ON/OFF` | While on, every encounter on a map Gen151 touched is one of its species, round-robin so a walk reaches all of them. |
| `SPAWN HERE` | Every placement on the map you are standing on, at its own level. Choose one and fight it now. |
| `GO TO` | Warp to any map Gen151 places on. |
| `CABLE SFX` | Play the cable snap, on its own. |
| `CABLE HUM` | Play `Trade_Machine`, the sound the cable opens on. |
| `BREAK BOX` | Push the exact `. . . / ZzZzap! / The LINK CABLE broke!` box without spending a cable. |
| `MEW: HIDDEN/FOUND` | Flip the four journal flags and `GEN151_MEW_FOUND`, and ask Gen151 to reconcile the encounter table — which is what AREA reads. |
| `DEX FILL` | Mark every species SEEN (not OWNED), so the dex list, AREA and the HINT row are all usable. |

## What it does not do

**`SPAWNS` forces what you meet, never whether you meet it.** The bench wraps
`encounter.roll` above Gen151's own layer and calls `next()` before it decides
anything, so a step that would not have produced an encounter still produces
none. Forcing the rate as well would make the walk a lie, and the walk is the
thing being judged.

It asks for **no permissions** and changes nothing about Gen151: it reads the
resolved placement rows out of `mod.find("gen151").exports` and drives the same
public seams any mod has.

## Suggested order

1. `CABLE SFX`, then `BREAK BOX` — the two fastest questions.
2. `KIT`, then use a LINK CABLE on the Kadabra. Press B during the flash; it
   should do nothing, because the evolution runs as a trade evolution.
3. `SPAWNS: ON`, then walk somewhere placed. `GO TO` if you are not.
4. Open FIELD NOTES and check the hints against what you actually met.
5. `DEX FILL`, then POKéDEX → a placed species → AREA.
6. `MEW` off, check AREA shows no nest for it. `MEW` on, check it does.
7. Celadon Mart 4F: is LINK CABLE on the shelf at 2100?
