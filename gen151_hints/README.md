# Gen151 Hints

Adds a **HINT** row to the Pokedex side menu, right after AREA. Pressing it
tells you where Gen151 put the species you are looking at — the map, the
method, the level band, the rarity and the gate.

```sh
cp -r Gen151/gen151_hints <gen1recomp>/mods/gen151_hints
python3 tools/modkit.py validate mods/gen151_hints
```

Needs [Gen151](https://github.com/wild1walker/Gen151) to do anything: it reads
that mod's resolved placement rows through `mod.find("gen151").exports`, so the
row can never disagree with the spawn it describes, and it shows nothing at all
for the species vanilla already provides. Without Gen151 installed it logs one
line saying so and registers nothing.

Gen151 is declared as an *optional* dependency rather than a hard one for a
packaging reason: `modkit pack` validates a mod by mounting it alone in the
headless loader, so a hard dependency is unreachable there and no release
archive could ever be built. Optional still guarantees the load order.

This is a separate mod for one reason: it is the only Gen151 feature that has
to reach an engine internal, and requesting `engine_internals` shows the player
a "PATCHES ENGINE CODE" badge in the mod manager. The encounter mod earns no
such badge and should not carry one.

## Turning it off

Two switches, either will do:

- this mod's own `HINT ROW` option
- Gen151's `HINTS` option, set to anything other than `AREA + DEX ROW`

## Compatibility

Tested against a vanilla dex and against
[Gen1Dex](https://github.com/wild1walker/Gen1Dex).

It works next to Gen1Dex because Gen1Dex builds its list by calling the
*vanilla* `PokedexMenu` constructor and re-dressing the result — the
DATA / CRY / AREA / QUIT side menu it hands back is untouched vanilla. This mod
wraps that same constructor rather than registering over the `PokedexMenu`
screen id, which Gen1Dex owns; two records on one id collide, and whichever
loses takes its whole screen with it.

A dex mod that replaces the side menu instead of delegating it will simply not
show the row. Nothing breaks; the row is not there.
