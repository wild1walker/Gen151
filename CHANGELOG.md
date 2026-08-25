# Changelog

All notable changes to Gen151 are recorded here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) order.

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
