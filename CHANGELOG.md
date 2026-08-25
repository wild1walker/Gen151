# Changelog

All notable changes to Gen151 are recorded here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) order.

## [1.0.2] - 2026-08-25

### Changed

- **MEW EVENT now defaults on.** It shipped off because it is an invention
  rather than a restoration, and that reasoning has not changed -- but a mod
  called Gen151 that leaves 151 out of the box is answering a question nobody
  asked it. Nothing about the feature itself moves: the gate is still all four
  Pokemon Mansion journals, MEW is still absent from the encounter table until
  the flag flips so AREA cannot spoil the location, and the toggle is still
  there for anyone who wants the cartridge's own answer.

## [1.0.1] - 2026-08-25

A companion fix. Gen151 itself is unchanged; the version moves because one
release covers every mod in this repo.

### Fixed

- `gen151_debug`: the bench was unreachable in practice. Its only way in was a
  row appended to the end of the OPTIONS list, which shows four rows at a time
  over a list around thirty long -- so the row sat seven screenfuls down and
  looked like it had never been added. It now sits directly under the MODS
  row, and the START menu carries a **BENCH** item at the top as a second door.
- `gen151_debug`: the CABLE SFX row blamed CABLE SOUND when no sound was
  registered. The snap is built by the LINK CABLE code, so the switch that
  decides whether it exists is TRADE EVOS.

## [1.0.0] - 2026-08-25

First release.

### Added

- Renewable wild spawns for every species with no renewable source on Red,
  Blue or Yellow: the version exclusives, the starters, the one-time gift
  Pokemon, the NPC-trade Pokemon, the fossils and Snorlax. A row is applied
  only where its species is actually missing, so no version has to be
  detected and a species another encounter mod already provided is left alone.
- A two-stage encounter roll: the engine's own `Encounter.roll` against the
  map's original slots, then one independent substitution check at the
  placement's rarity. The encounter rate is never touched, and with every
  rarity at zero the RNG stream is identical to a clean install draw for draw.
- LINK CABLE, sold on Celadon Department Store 4F beside the evolution stones
  for 2100. Runs one trade evolution as a trade evolution -- non-cancelable,
  so it always completes -- then breaks on screen, after the evolution
  resolves and only on success.
- FIELD NOTES, a key item listing every species Gen151 placed that has not
  been caught yet, with the map, the method, the level band, the rarity and
  the gate. Composed from the same placement rows the roll layer uses.
- An optional Mew unlock, default off: reading all four Pokemon Mansion
  journals flips `GEN151_MEW_FOUND` and Mew becomes a very rare renewable
  encounter in the Mansion basement. Until then Mew is absent from
  `data.encounters` entirely, so the dex AREA screen cannot spoil it.
- Ten mod option rows, one per independent decision.
- `tools/gapset.py`, which derives the gap set from the pret disassembly using
  the same parse the engine's own extractor performs, and the rest of the
  derivation pipeline that generates `placements.lua`'s version-exclusive
  rows, `hints.lua` and `SPOILERS.md` from it.

### Not changed, on purpose

- Articuno, Zapdos, Moltres and Mewtwo keep their vanilla statics. They are
  the sole exception to the renewability rule and there is no option to add
  one, so there is no dead row in the options menu either.
- No vanilla encounter slot, level or rate on any map on any version. Asserted
  in `tests/mod_load_test.lua` against the real Kanto tables.
