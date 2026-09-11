-- Render the Johto half of SPOILERS.md from gen2/placements.lua.
--
-- Sourced by tools/dump_placements.lua, so SPOILERS.md stays ONE generated
-- file with one command behind it.  Separate file for the same reason
-- gapset2.py, build_placements2.py and placements2_test.lua are separate: the
-- Gen 2 table is a different shape with different caveats, and reading either
-- half should not mean reading past the other.
--
-- ------- why this half prints a BAND where Gen 1 prints levels
--
-- Gen 1's dump resolves real level ranges because it can: the vanilla tables
-- are checked in at tests/fixtures/vanilla.lua, so `Build.resolve` runs here
-- exactly as it runs in the game.  There is no such fixture for Gen 2 -- the
-- Johto arm substitutes into the tables merged on the live install, and a row
-- takes a third of the DESTINATION map's own levels (gen2/build.lua:187
-- `Build.band`), which differ between Gold, Silver and Crystal by as much as
-- twenty levels.
--
-- So the honest column is the band the row asks for.  Printing a single Lv
-- range would be picking one cartridge and not saying which, which is the one
-- thing a spoiler table must not do.
--
-- ------- and why it prints every row rather than the rows that fire
--
-- A Gen 2 placement applies only where the species has no renewable source on
-- the tables actually merged (gen2/build.lua:226 `already renewable`), and
-- that is a fact about the install, not about the table.  Set B's `why`
-- already names which cartridge is missing which species, which is the same
-- information a per-version split would carry, without pretending this file
-- knows what is merged.

local P = dofile("gen2/placements.lua")
local Hints = dofile("hints.lua")
local Rarity = dofile("rarity.lua")

-- Set B is spliced in by tools/build_placements2.py and is exactly the
-- `exclusives` feature -- checked here rather than assumed, because a table
-- that stopped agreeing with that would silently print one section empty.
local SET_B_FEATURE = "exclusives"

local function methodOf(row)
  return row.method == "water" and "surf" or "grass"
end

local function rowsWhere(keep)
  local out = {}
  for _, row in ipairs(P.common) do
    if keep(row) then out[#out + 1] = row end
  end
  table.sort(out, function(a, b)
    if a.species ~= b.species then return a.species < b.species end
    return a.map < b.map
  end)
  return out
end

local function speciesCount(rows)
  local seen, n = {}, 0
  for _, row in ipairs(rows) do
    if not seen[row.species] then seen[row.species] = true; n = n + 1 end
  end
  return n
end

local function table_(rows)
  io.write("| Species | Where | How | Band | Rarity | Behind | Why |\n")
  io.write("|---|---|---|---|---|---|---|\n")
  for _, row in ipairs(rows) do
    io.write(("| %s | %s | %s | %s | %s | %s | %s |\n"):format(
      row.species,
      Hints.mapName(row.map),
      methodOf(row),
      row.band,
      Rarity.LABELS[row.tier] or row.tier,
      P.gateFor(row.map, row.method) or "nothing",
      (row.why or ""):gsub("|", "/")))
  end
  io.write("\n")
end

local setA = rowsWhere(function(row) return row.feature ~= SET_B_FEATURE end)
local setB = rowsWhere(function(row) return row.feature == SET_B_FEATURE end)
assert(#setA + #setB == #P.common, "a row went missing between the two sets")
assert(#setA > 0 and #setB > 0, "one of the two sets came out empty")

io.write([[

# ALL 251 -- Johto SPOILERS

The same table for the Gold, Silver and Crystal half of the mod, and the same
promise: nothing below is a surprise it means to keep.

**GENERATED** by `tools/dump_placements2.lua` from `gen2/placements.lua`, so a
row here cannot disagree with the spawn it describes.

Two things read differently from the Kanto half above.

**A Johto placement SUBSTITUTES; it does not append.** Gold picks a grass slot
off a fixed seven-entry probability ladder, so an eighth slot can never be
drawn -- there is nothing to append to. A placed species takes a slot that was
already there, which is why the tables below have no row count against
vanilla: nothing is added and nothing is taken away.

**The Levels column is a BAND, not a range.** A row takes a third of its
destination map's OWN levels -- the low, middle or high third -- rather than a
level of its own, so one row stays right on all three cartridges even where
their bands differ by twenty levels. What that third actually comes out as
depends on which cartridge you are playing, so the honest thing to print is
the third.

And the same rule as Kanto decides whether a row fires at all: a species is
placed only where the cartridge has no renewable source for it already. Set
B's reasons say which cartridge that is, species by species.

]])

io.write(("## Set A -- the decisions -- %d species, %d rows\n\n"):format(
  speciesCount(setA), #setA))
io.write([[
The half that needed taste. Where a later official game put a species in the
wild, that is the authority; where none ever did, the row justifies itself on
habitat and gate instead and says so.

]])
table_(setA)

io.write(("## Set B -- the version exclusives -- %d species, %d rows\n\n"):format(
  speciesCount(setB), #setB))
io.write([[
Derived rather than decided, by `tools/build_placements2.py`: a version
exclusive is missing on one cartridge and present on another, so its placement
is the map the OTHER cartridge puts it on -- same game, same species, same map.
Where a donor keeps it in more than one place, the lowest band wins, because
the earliest place a cartridge keeps a species is the one its own designers
thought of as that species' home.

Only the ROOT of each line is placed: placing EKANS gives ARBOK, because the
renewability closure runs over evolution.

]])
table_(setB)

io.write([[
## Not placed in Johto, on purpose

**The ten trade evolutions** -- ALAKAZAM, MACHAMP, GOLEM, GENGAR, POLITOED,
SLOWKING, STEELIX, SCIZOR, KINGDRA, PORYGON2 -- get the cable rather than a
habitat, and on Gold the cable is a RULE rather than an item. Gen 2 ships the
EVERSTONE, which the cartridge's own evolution code already checks before it
checks anything else, so there is a first-class opt-out and no need to invent,
price and shelve a consumable. Everything else about a trade evolution is
untouched: SCIZOR still costs a METAL COAT, an EVERSTONE still says no, and
the Time Capsule still refuses a held-item trade.

**The statics** -- LUGIA, HO-OH, SNORLAX and SUDOWOODO -- keep their objects
and become RETRYABLE instead. Knock one out or run, and it is back on the map
the next time you walk in, because what is put back is the object's own
visibility flag and not the EVENT_FOUGHT flag: Gen 2's fought flags are
load-bearing for unrelated progression, and clearing EVENT_FOUGHT_SUICUNE to
give a player their SUICUNE back could take HO-OH away from them. Nothing here
writes an event flag at all.

**SUICUNE on Crystal** is the one static that cannot be un-hidden, so a lost
one is seeded into the ROAMER slot instead and roams Johto -- which is what
the other two beasts do on that cartridge anyway.

**CELEBI on Crystal** is not a placement either. The whole GS BALL event is on
the cartridge and unreachable, because the one byte that starts it was only
ever written by the Mobile Adapter GB. The mod writes the byte and stops: the
receptionist, KURT, the shrine in ILEX FOREST and the level 30 CELEBI are all
the cartridge's own, in its own words. On Gold and Silver none of it exists,
which is why CELEBI has a placement row there and not on Crystal.

**Six babies that look missing and are not** -- PICHU, CLEFFA, IGGLYBUFF,
SMOOCHUM, ELEKID and MAGBY. Every one breeds from an adult already in the
grass and the engine implements the Day-Care, so the gap set closes over
breeding and drops them. Placing them would have been inventing work for the
player.
]])
