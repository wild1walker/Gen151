-- Gen151 -- every one of the 151 obtainable renewably, in one save, on one
-- version, without trading, while every vanilla encounter keeps its exact
-- vanilla behaviour.
--
-- The wiring lives here; the deciding lives elsewhere:
--
--   placements.lua  the single source of truth: species -> map, method,
--                   level, rarity, gate, justification
--   build.lua       placements + the pristine data -> roll rows and slot
--                   appends, and the "is this species already renewable
--                   here?" question that makes version detection unnecessary
--   roll.lua        the two-stage roll: vanilla exactly, then substitution
--   rarity.lua      the tier table the whole mod shares
--   hints.lua       generated hint vocabulary
--   linkcable.lua   the consumable trade-evolution item
--   fieldnotes.lua  the FIELD NOTES key item and its screen
--   mewgate.lua     the Mansion journals, and the spawn they unlock
--
-- No permissions.  Everything here goes through mod.content, mod.hooks,
-- mod.events, mod.options, mod.ui, mod.world and mod.game.

local MOD_ID = "gen151"

-- A file this mod ships, compiled in this mod's own sandbox.  mod:read plus
-- load is the documented way to reach one: a mod's directory is not on
-- package.path, and require() would only find it by accident of where the
-- mod happens to be installed.
local function submodule(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing from %s -- reinstall the mod; the whole "
      .. "spawn layer is skipped", name, mod.path)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s did not compile: %s -- reinstall the mod", name,
      tostring(err))
    return nil
  end
  local ok, value = pcall(chunk)
  if not ok then
    mod.log:error("%s failed to load: %s -- reinstall the mod", name,
      tostring(value))
    return nil
  end
  return value
end

-- The line the game itself prints, with our wording as backup: on a
-- localized or total-conversion import the extracted label is the one the
-- player recognizes.  A slot count that does not match what we can fill
-- means the extracted line cannot carry this sentence, so the literal
-- stands in rather than printing one with a hole in it (the rule
-- src/core/RomText.lua follows).
local function romText(data, label, fallback, ...)
  local text = data and data.text and data.text[label]
  local args = { ... }
  if type(text) ~= "string" then
    if #args == 0 then return fallback end
    return (fallback:format(...))
  end
  if #args == 0 then return text end
  local slots = 0
  for _ in text:gmatch("%b{}") do slots = slots + 1 end
  if slots ~= #args then return (fallback:format(...)) end
  local i = 0
  return (text:gsub("%b{}", function()
    i = i + 1
    return tostring(args[i])
  end))
end

return function(mod)
  local options = mod.options:define{
    { key = "enabled", type = "toggle", label = "GEN151", default = true },

    -- SPEC 7: every independent decision gets its own row.  The single
    -- biggest complaint about the existing all-151 mod is that it is
    -- all-or-nothing; someone who wants the version exclusives but not a
    -- wild Mew should not have to fork it.
    { key = "exclusives", type = "toggle", label = "EXCLUSIVES",
      default = true, visible_if = { key = "enabled", equals = true } },
    { key = "gifts", type = "toggle", label = "GIFT MONS", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "fossils", type = "toggle", label = "FOSSILS", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "snorlax", type = "toggle", label = "SNORLAX", default = true,
      visible_if = { key = "enabled", equals = true } },

    { key = "trade_evolutions", type = "choice", label = "TRADE EVOS",
      default = "link_cable",
      choices = { { "LINK CABLE", "link_cable" }, { "OFF", "off" } },
      visible_if = { key = "enabled", equals = true } },
    { key = "cable_sfx", type = "toggle", label = "CABLE SOUND",
      default = true,
      visible_if = { key = "trade_evolutions", equals = "link_cable" } },

    -- An invention rather than a restoration, and it shipped off for that
    -- reason.  On, now, by the author's call: a mod called Gen151 that leaves
    -- 151 out of the box is answering a question nobody asked it.  The
    -- caution the default was expressing is still all there in the design --
    -- the gate is four journals in an optional late-game dungeon, MEW is
    -- absent from the encounter table until the flag flips so AREA cannot
    -- spoil it, and the toggle is right here for anyone who wants the
    -- cartridge's own answer instead.
    { key = "mew", type = "toggle", label = "MEW EVENT", default = true,
      visible_if = { key = "enabled", equals = true } },

    -- A percentage over the whole tier table, so the ladder keeps its shape.
    { key = "rarity", type = "number", label = "RARITY %", default = 100,
      min = 0, max = 500, step = 25,
      visible_if = { key = "enabled", equals = true } },

    -- The test bench.  Off is the shipping state and off is what a player
    -- gets; on, the START menu grows a BENCH row that forces this mod's
    -- spawns, hands over the kit and plays the cable sounds on demand.  It
    -- lives here rather than in a companion mod because a bench you have to
    -- download and import separately is a bench that is not there when you
    -- want it.
    { key = "bench", type = "toggle", label = "TEST BENCH", default = false,
      visible_if = { key = "enabled", equals = true } },

    { key = "hints", type = "choice", label = "HINTS", default = "dex",
      choices = { { "AREA + DEX ROW", "dex" },
                  { "AREA + NOTES", "notes" },
                  { "AREA ONLY", "area" } },
      visible_if = { key = "enabled", equals = true } },
  }

  local function opt(key) return mod.options:get(key) end

  -- Published for the companion mod (the dex HINT row) and for anyone else
  -- who wants the placement table.  Filled in below; declared here so an
  -- early return still leaves a well-formed handle behind.
  mod.exports.version = mod.version
  mod.exports.rows = {}
  mod.exports.fishing = {}
  mod.exports.hints = nil
  mod.exports.hintSurface = opt("hints")
  mod.exports.enabled = false

  if opt("enabled") ~= true then
    mod.log:info("switched off in its own options; nothing registered")
    return
  end

  local Rarity = submodule(mod, "rarity.lua")
  local Roll = submodule(mod, "roll.lua")
  local Build = submodule(mod, "build.lua")
  local Placements = submodule(mod, "placements.lua")
  local Hints = submodule(mod, "hints.lua")
  if not (Rarity and Roll and Build and Placements and Hints) then return end

  -- Read vanilla through the registries.  :each() enumerates the base
  -- table's ids as well as the registered ones, and the entry chunk runs
  -- BEFORE the merge, so what comes back here is the pristine dataset -- no
  -- other mod's patches have landed yet.  That is exactly what both jobs
  -- below need: the vanilla slot count for stage one, and an honest answer to
  -- "does this species already have a renewable source on this cartridge".
  local source = {
    eachEncounter = function() return mod.content.encounters:each() end,
    encounter = function(id) return mod.content.encounters:get(id) end,
    eachPokemon = function() return mod.content.pokemon:each() end,
    field = function(key) return mod.content.field:get(key) end,
  }
  if mod.content.pokemon:get("MEW") == nil then
    mod.log:warn("the species table has no MEW, so this is not a Kanto "
      .. "dataset -- the spawn layer is skipped and nothing is patched")
    return
  end

  local resolved = Build.resolve(Placements, source, {
    rarity = Rarity,
    multiplier = opt("rarity"),
    features = {
      exclusives = opt("exclusives") == true,
      gifts = opt("gifts") == true,
      fossils = opt("fossils") == true,
      snorlax = opt("snorlax") == true,
      mew = opt("mew") == true,
    },
  })
  for _, warning in ipairs(resolved.warnings) do
    mod.log:warn("placement skipped -- %s", warning)
  end

  -- ------------------------------------------------------------ the roll

  local mew = submodule(mod, "mewgate.lua")
  local mewGate = mew and mew.new(mod, { romText = romText })

  local layer = Roll.new()
  for _, row in ipairs(resolved.rows) do
    layer:setVanillaCount(row.map, row.method, row.vanillaCount)
  end
  for _, row in ipairs(resolved.rows) do
    layer:add(row.map, row.method, {
      species = row.species, levels = row.levels, weight = row.weight,
      active = row.gated == "mew" and mewGate and mewGate.unlocked or nil,
    })
  end
  for _, row in ipairs(resolved.fishing) do
    layer:addFishing(row.map, row.rod, {
      species = row.species, levels = row.levels, weight = row.weight,
    })
  end

  -- The data layer: appends only, never a bare slots list, never a `buckets`
  -- key.  These are what makes the dex AREA screen light up the right maps
  -- for free (SPEC 6a), which is why slot placement is preferred over the
  -- Super Rod wherever the choice exists.
  for mapId, byKind in pairs(resolved.appends) do
    local payload = {}
    for kind, slots in pairs(byKind) do
      payload[kind] = { slots = { __append = slots } }
    end
    mod.content.encounters:patch(mapId, payload)
  end

  local random = love and love.math and love.math.random
  mod.hooks:wrap("encounter.roll", function(nextLink, encDef, ctx)
    return layer:roll(nextLink, encDef, ctx, (ctx and ctx.rng) or random)
  end)
  mod.hooks:wrap("encounter.fishing", function(nextLink, rod, mapId, pool)
    return layer:fish(nextLink, rod, mapId, pool, random)
  end)

  local placed = {}
  for _, row in ipairs(resolved.rows) do placed[row.species] = true end
  for _, row in ipairs(resolved.fishing) do placed[row.species] = true end
  local count = 0
  for _ in pairs(placed) do count = count + 1 end
  mod.log:info("%d species placed across %d rows (%d skipped)", count,
    #resolved.rows + #resolved.fishing, #resolved.skipped)

  -- --------------------------------------------------------- the features

  if mewGate then mewGate.install(resolved.rows) end

  -- Anything Gen151 adds to the bag gets a line in the FIELD NOTES, because
  -- Gen 1 has no item descriptions and that is the only surface there is.
  local kit = {}

  if opt("trade_evolutions") == "link_cable" then
    local cable = submodule(mod, "linkcable.lua")
    if cable then
      cable.install(mod, {
        romText = romText,
        sfx = function() return opt("cable_sfx") == true end,
      })
      kit[#kit + 1] = cable.note()
    end
  end

  if opt("hints") ~= "area" then
    local notes = submodule(mod, "fieldnotes.lua")
    if notes then
      notes.install(mod, {
        hints = Hints,
        rows = resolved.rows,
        fishing = resolved.fishing,
        romText = romText,
        kit = kit,
      })
    end
  end

  -- Last, so the bench's high-priority wrap on encounter.roll goes on above a
  -- chain that is already complete, and so a fault in it cannot cost a player
  -- the spawn layer.
  if opt("bench") == true then
    local bench = submodule(mod, "bench.lua")
    if bench then
      bench.install(mod, {
        rows = resolved.rows,
        fishing = resolved.fishing,
        syncGated = mewGate and mewGate.sync or function() end,
      })
    end
  end

  mod.exports.rows = resolved.rows
  mod.exports.fishing = resolved.fishing
  -- Reconcile the runtime-conditional rows -- today that is MEW -- with the
  -- flags they are gated on.  Gen151 calls this itself on every save load, so
  -- nothing needs it in normal play; it is published because a mod that flips
  -- GEN151_MEW_FOUND from outside has no other way to ask for the encounter
  -- table to catch up, and a stale table is what the dex AREA screen reads.
  mod.exports.syncGated = mewGate and mewGate.sync or function() end
  mod.exports.hints = Hints
  mod.exports.hintSurface = opt("hints")
  mod.exports.enabled = true
  mod.exports.id = MOD_ID
end
