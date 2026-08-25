# Changelog

## [1.0.1] - 2026-08-25

### Fixed

- The bench was unreachable in practice. Its only entry point was a row
  appended to the end of the OPTIONS list, which shows four rows at a time
  over a list around thirty long on a desktop build -- so the row was seven
  screenfuls down, under the more-arrow, and looked like it had never been
  added. It now sits directly under the MODS row instead, and the START menu
  carries a **BENCH** item at the top as a second door that no amount of
  scrolling, and no menu-replacing mod, can take away.
- CABLE SFX blamed the wrong switch when no sound was registered. The snap is
  built by the LINK CABLE code, which only runs when TRADE EVOS is set to LINK
  CABLE; CABLE SOUND decides whether it plays, not whether it exists.

## [1.0.0] - 2026-08-25

First release.

### Added

- An OPTIONS row opening a bench of test actions for Gen151: force its spawns,
  hand over the kit, play the LINK CABLE sounds on demand, push the break box
  without spending a cable, flip the Mew gate, warp to every map it places on,
  and mark the dex SEEN.
- Forcing sits above Gen151 in the `encounter.roll` chain and calls next()
  first, so it changes what you meet and never whether you meet it.
