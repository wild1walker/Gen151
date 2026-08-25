# Changelog

All notable changes to Gen151 are recorded here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) order.

## [1.1.4] - 2026-08-25

### Changed

- The AREA hint box is **four rows rather than six**. The dialogue box
  double-spaces its two lines because it is typing a story at you and has
  nothing behind it; this is a two-line label over a map, and the sixteen
  pixels that buys back are two whole tile rows of Kanto.

### Added

- **START reopens the hint** once it has been dismissed. Dismissing one you
  were still reading should not mean leaving the AREA screen and coming back
  in. START does nothing at all on that screen in vanilla, so nothing is taken
  away to pay for it, and both presses play the same Press_AB the screen plays
  for every other button.

## [1.1.3] - 2026-08-25

### Changed

- **The AREA hint is the game's own dialogue box now.** It was a bare white
  strip with two lines painted into it, which read as a debug overlay rather
  than as the game talking to you. It uses `Font.drawBox` and the same
  arithmetic on the same constants `src/render/TextBox.lua` uses for every
  other box -- the frame tiles, the box geometry, the text baselines, the
  blinking prompt in the corner -- so it lands on the same pixels rather than
  on pixels that look about right.

### Fixed

- The AREA header ran off the right edge of the screen. Vanilla writes into a
  19-column strip without measuring it, and `CHARIZARD AREA UNKNOWN` is 22, so
  it was cut mid-word. It is now measured in the pixels the glyphs draw -- not
  in bytes, which a variable-advance font skin would get wrong -- and shortened
  to `CHARIZARD UNKNOWN` only when the full line would not have fitted. A name
  short enough to leave vanilla's line alone leaves it alone.
- Every caption line is clamped to the box's own width in one place, so a
  source that forgets its budget cannot overflow.

## [1.1.2] - 2026-08-25

### Fixed

- **An upgraded install had the whole dex surface switched off, while its own
  option row read ON.** HINTS was a three-way choice through 1.0.x and became
  a toggle in 1.1.0. The loader hands a stored option straight back -- it
  checks nothing against the schema the mod defines today -- so an options
  file written by 1.0.x answered `hints == true` with the string `"dex"`.
  Not true. `dexarea.lua` never installed: no AREA on an undiscovered entry,
  no line under the map, and the bench reporting AREA HINTS as off. Three
  separate-looking faults, one stale string.

  Every option row is now checked against its own schema before it is read, so
  this is fixed for the whole class rather than for the row that caught fire:
  a stale value on a toggle, a number out of range, or a choice that is no
  longer offered all fall back to the row's default, with a line in the log
  saying so. `"area"` -- which really did mean "leave the dex alone" -- is
  carried across to OFF rather than reset, so nobody who switched hints off on
  purpose gets them back.

## [1.1.1] - 2026-08-25

### Changed

- **The AREA hint now covers all 151**, not just the species this mod placed.
  A vanilla Pokemon's line is read straight out of the live encounter tables
  -- the map where it has the biggest share, that map's own level band, and a
  rarity worked out from Gen 1's ten slot buckets -- and one that is in no
  table at all falls back to the evolution table (`EVOLVE ODDISH / AT LV21`,
  `LINK CABLE / ON KADABRA`). None of it depends on having caught the thing.
- **A press takes the hint away.** The strip covers the bottom two tile rows
  of Kanto and one of them has nests in it. The first A dismisses the hint,
  the second closes the screen the way A always did; B still leaves at once.
  The engine's own more-below arrow marks the waiting press.

### Fixed

- AREA would not open on an undiscovered entry next to a dex mod that replaces
  the list's rows. The species was being recovered from a row's POSITION, by
  rebuilding the vanilla dex order and indexing it -- which holds only while
  the list is the vanilla list. It now reads the species off the row itself,
  which every dex list carries, so sorting, filtering or replacing the rows
  cannot strand it.
- The screen wraps stacked on every reload. A second load of the mod -- a hot
  reload, a profile switch -- painted a second hint strip over the first.

### Added

- A **DEX WRAP** row on the bench, which names every link that has to hold for
  a press on an undiscovered entry to open AREA: who owns the dex, whether it
  calls the builtin, whether it kept the A handler, and whether its rows name
  their species. Written because the report that sent me here could not be
  reproduced from the outside, and the possible causes need opposite fixes.

## [1.1.0] - 2026-08-25

Six things a human found by playing it, which is the only way any of them
were ever going to turn up.

### Changed

- **The hints moved onto the dex AREA screen, and FIELD NOTES is gone.** The
  POKeDEX now opens its side menu on an entry you have never seen -- vanilla
  refuses, which is backwards for a mod about finding what you have not met --
  with AREA on it, and the AREA map carries a line underneath saying how to
  get there: method, level band, and either the rarity or the HM you need to
  be standing there at all. The FIELD NOTES key item and its screen are
  deleted, and so is the `gen151_hints` companion that added a HINT row to the
  same menu. Both were a second place to look for an answer that belonged on
  the first one.
- Mew keeps its seal: while its gate is shut there is no nest AND no caption.
- **Every text box the mod prints was rewritten to fit.** A page that renders
  three lines does not stop -- the engine only waits between lines when the
  break is `\v` -- so the top line scrolled away while the player was still
  reading it. Fifteen pages across five files did that. `tests/text_test.lua`
  now paginates every string in the mod with the real `TextBox.paginate` and
  fails the build on any page that would scroll unread.
- The LINK CABLE **asks before it commits**, which is where B gets a meaning:
  everything after the question is a trade evolution, and a trade evolution
  has never been cancelable on any cartridge. The question also carries the
  one line of description Gen 1 has nowhere else to put, now that the FIELD
  NOTES screen it used to live on is gone.

### Added

- A second sound on the cable break. The snap stays exactly where it was, on
  the page that says the cable broke; **ZzZzap** now gets an arc of its own --
  the noise channel's 7-bit polynomial, three bursts and a decay, over a
  square sweeping up where the snap sweeps down. It fires as the box comes up
  rather than after the word has finished typing.

### Fixed

- The bench's MEW row said nothing and looked like it did nothing. It now
  confirms what it did, and when MEW EVENT is switched off -- the one case
  where flipping the flag really does move nothing -- it says so instead of
  failing silently.

## [1.0.3] - 2026-08-25

### Added

- **TEST BENCH**, an option in Gen151's own settings, default off. On, the
  START menu grows a **BENCH** row (and OPTIONS grows one under MODS) that
  forces this mod's spawns, hands over the kit, plays the LINK CABLE sounds on
  demand, pushes the break box, flips the Mew gate, warps to every map it
  places on, and marks the dex SEEN. Off, nothing registers: no row, no
  screen, no wrap on the encounter chain.

### Removed

- The `gen151_debug` companion mod, whose entire contents this is. A bench in
  a second archive is a bench nobody has installed at the moment they want it,
  which is exactly how it went. One implementation, in the mod you already
  have. The v1.0.2 archive still exists for anyone who wants the old shape.

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
