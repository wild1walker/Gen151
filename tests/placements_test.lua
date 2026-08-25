-- placements.lua's own invariants (SPEC 4 step 3, SPEC 5, SPEC 9).
--
-- Pure Lua, no engine and no love.*:
--
--   lua tests/placements_test.lua
--
-- The Set B rows are not checked here for drift, because the honest check for
-- generated content is to regenerate it and diff:
--
--   python3 tools/build_placements.py --recomp ... --pokered ... --pokeyellow ...
--   git diff --exit-code placements.lua
--
-- which is what tools/regen.sh does and what CI should run.

local Placements = dofile("placements.lua")
local Rarity = dofile("rarity.lua")
local Build = dofile("build.lua")
local Hints = dofile("hints.lua")
local vanilla = dofile("tests/fixtures/vanilla.lua")

local failures, checks = 0, 0

local function check(cond, fmt, ...)
  checks = checks + 1
  if cond then return true end
  failures = failures + 1
  io.write("FAIL: " .. string.format(fmt, ...) .. "\n")
  return false
end

local function allRows()
  local out = {}
  for _, row in ipairs(Placements.common) do out[#out + 1] = row end
  for _, row in ipairs(Placements.gapFill) do out[#out + 1] = row end
  for _, row in ipairs(Placements.fishing) do out[#out + 1] = row end
  return out
end

-- ------------------------------------------------------------ well-formed

local LAZY = {
  ["it needed to go somewhere"] = true,
  ["somewhere"] = true,
  [""] = true,
}

for _, row in ipairs(allRows()) do
  local where = tostring(row.species) .. " on " .. tostring(row.map)
  check(type(row.species) == "string" and row.species ~= "",
    "%s: a row needs a species", where)
  check(type(row.map) == "string" and row.map ~= "",
    "%s: a row needs a map", where)
  check(row.method == "grass" or row.method == "water" or row.rod ~= nil,
    "%s: method must be grass or water, or the row must name a rod", where)
  check(Rarity.TIERS[row.tier] ~= nil,
    "%s: %s is not a rarity tier", where, tostring(row.tier))
  check(Placements.FEATURES[row.feature] ~= nil,
    "%s: %s is not a known feature", where, tostring(row.feature))
  -- SPEC 4: "If the justification is 'it needed to go somewhere,' the
  -- placement is wrong."
  check(type(row.why) == "string" and not LAZY[row.why:lower()],
    "%s: the justification is missing or empty", where)
  check(row.levels ~= nil or row.band ~= nil,
    "%s: a row needs explicit levels or a band", where)
  check(Placements.MAP_RUNG[row.map] ~= nil,
    "%s: %s has no rung on the ladder", where, row.map)
  check(Hints.MAPS[row.map] ~= nil,
    "%s: %s has no display name in hints.lua -- regenerate it", where, row.map)
end

-- ------------------------------------------- difficulty is at least earned

for _, row in ipairs(allRows()) do
  local minimum = Placements.MIN_RUNG[row.species]
  if minimum then
    local rung = Placements.MAP_RUNG[row.map] or 0
    check(rung >= minimum,
      "%s on %s sits at rung %d, but vanilla charged rung %d for it",
      row.species, row.map, rung, minimum)
  end
end

-- ------------------------------------------------- the gap actually closes

local UNTOUCHED = { ARTICUNO = true, ZAPDOS = true, MOLTRES = true,
                    MEWTWO = true }
local CABLE = { ALAKAZAM = true, MACHAMP = true, GOLEM = true, GENGAR = true }

local function sourceFor(version)
  local set = vanilla.versions[version]
  return {
    eachEncounter = function() return pairs(set.encounters) end,
    encounter = function(id) return set.encounters[id] end,
    eachPokemon = function() return pairs(set.pokemon) end,
    field = function(key)
      if key == "fishing" then
        return { OLD_ROD = { always = { species = "MAGIKARP", level = 5 } },
                 GOOD_ROD = { pool = set.goodRod },
                 SUPER_ROD = { perMap = "superRod" } }
      end
      if key == "superRod" then return set.superRod end
      return nil
    end,
  }
end

local ALL_ON = { exclusives = true, gifts = true, fossils = true,
                 snorlax = true, mew = true }

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local set = vanilla.versions[version]
  local resolved = Build.resolve(Placements, sourceFor(version), {
    rarity = Rarity, multiplier = 100, features = ALL_ON,
  })

  check(#resolved.warnings == 0,
    "%s: placements resolved with warnings: %s", version,
    table.concat(resolved.warnings, "; "))

  local covered = {}
  local missing = {}
  for _, name in ipairs(set.missing) do missing[name] = true end
  for _, name in ipairs(vanilla.dex) do
    if not missing[name] then covered[name] = true end
  end
  for _, row in ipairs(resolved.rows) do covered[row.species] = true end
  for _, row in ipairs(resolved.fishing) do covered[row.species] = true end

  local changed = true
  while changed do
    changed = false
    for id, def in pairs(set.pokemon) do
      if covered[id] then
        for _, evo in ipairs(def.evolutions or {}) do
          if evo.species and not covered[evo.species]
             and (evo.method ~= "TRADE" or CABLE[evo.species]) then
            covered[evo.species] = true
            changed = true
          end
        end
      end
    end
  end

  local gaps = {}
  for _, name in ipairs(vanilla.dex) do
    if not covered[name] and not UNTOUCHED[name] then
      gaps[#gaps + 1] = name
    end
  end
  check(#gaps == 0, "%s: still unobtainable: %s", version,
    table.concat(gaps, ", "))

  -- ---- no orphans: every applied row has hint coverage
  --
  -- A slot row is covered by the dex AREA screen, which scans the live
  -- encounter tables.  A Super Rod row is NOT in those tables, so it must be
  -- reachable through the FIELD NOTES table -- which is built from the same
  -- resolved rows, so this checks that the row survives resolution with the
  -- fields the hint formatter needs.
  for _, row in ipairs(resolved.fishing) do
    local text = Hints.describe(row)
    check(type(text) == "string" and text:find(row.map:sub(1, 5), 1, true)
            ~= nil,
      "%s: %s's Super Rod row produced no usable hint (%q)",
      version, row.species, tostring(text))
  end

  -- ---- every level lands inside the destination map's own band
  for _, row in ipairs(resolved.rows) do
    local record = set.encounters[row.map]
    local group = record and record[row.method == "water" and "water" or "grass"]
    local lo, hi = math.huge, -math.huge
    for _, slot in ipairs((group or {}).slots or {}) do
      lo = math.min(lo, slot.level)
      hi = math.max(hi, slot.level)
    end
    for _, level in ipairs(row.levels or {}) do
      check(level >= lo and level <= hi,
        "%s: %s on %s is level %d, outside the map's own %d-%d band",
        version, row.species, row.map, level, lo, hi)
    end
  end

  -- ---- rarity is a share, and the shares on one map cannot exceed it
  local perMap = {}
  for _, row in ipairs(resolved.rows) do
    local key = row.map .. "|" .. row.method
    perMap[key] = (perMap[key] or 0) + row.weight
  end
  for key, total in pairs(perMap) do
    check(total < 5000,
      "%s: %s gives away %.1f%% of its encounters, which is too much of "
        .. "somebody else's share", version, key, total / 100)
  end
end

io.write(("\nplacements_test: %d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
