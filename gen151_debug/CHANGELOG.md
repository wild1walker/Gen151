# Changelog

## [1.0.0] - 2026-08-25

First release.

### Added

- An OPTIONS row opening a bench of test actions for Gen151: force its spawns,
  hand over the kit, play the LINK CABLE sounds on demand, push the break box
  without spending a cable, flip the Mew gate, warp to every map it places on,
  and mark the dex SEEN.
- Forcing sits above Gen151 in the `encounter.roll` chain and calls next()
  first, so it changes what you meet and never whether you meet it.
