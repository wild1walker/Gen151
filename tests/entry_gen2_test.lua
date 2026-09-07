-- Which half of this mod the entry installs, on which cartridge.
--
-- Reported from a real Gold boot, as a crash on the MOD MANAGER page:
--
--   FAILED: mods/gen151/build.lua:36:
--   attempt to index local 'record' (a number value)
--
-- build.lua is ALL 151's -- a placement table researched against KANTO maps,
-- Red and Blue's version exclusives and a 151-entry dex.  On Gold it read
-- Johto's encounter registry with Kanto's shape and took the game down.
--
-- The manifest says `games: [gen1, gen2]`, which is TRUE of the repository:
-- the Gen 2 half is in gen2/.  But `entry` is one file, so a standalone
-- install ran the Gen 1 half on both cartridges.  Inside the Gen1Wild bundle
-- it never showed, because features.lua carries `gen1_only = true` on ALL 151
-- and lists ALL 251 and the GS BALL as their own rows -- the bundle was
-- making a choice the entry did not.
--
-- So this asserts the choice, by watching which files the entry ASKS FOR.
-- That is the observation that matters: a Kanto table not read is a Kanto
-- table that cannot crash.
--
-- Run:  luajit tests/entry_gen2_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

-- ---- the cartridge, which is the only thing that differs between the runs

local generation, engineName = 1, "gen1"
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  engine = function() return engineName end,
}

-- ---- a mod handle that records what was read

local KANTO = {
  ["rarity.lua"] = true, ["roll.lua"] = true, ["build.lua"] = true,
  ["placements.lua"] = true, ["hints.lua"] = true,
}

local function fakeMod()
  local self = {
    id = "gen151", path = "mods/gen151", version = "1.6.1",
    exports = {}, reads = {}, logged = {}, hooked = {}, evented = {},
  }
  self.options = {
    define = function(_, rows) return rows end,
    get = function(_, key) return key == "enabled" and true or false end,
  }
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function(_, fmt) self.logged[#self.logged + 1] = tostring(fmt) end
  end
  self.hooks = { wrap = function(_, name) self.hooked[name] = true end }
  self.events = { on = function(_, name) self.evented[name] = true end }
  self.content = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return function() end end })
  end })
  -- Every read is recorded and answered with nil.  nil is a file the loader
  -- could not find, which every loader here already handles by logging and
  -- standing down -- so the run reaches the end either way and the RECORD is
  -- what the test reads.
  function self:read(name) self.reads[name] = true; return nil end
  return self
end

local installer = assert(loadfile("main.lua"))()
eq(type(installer), "function", "main.lua returns an installer")

local function install(gen, engineId)
  generation, engineName = gen, engineId
  local mod = fakeMod()
  local ran, err = pcall(installer, mod)
  return mod, ran, err
end

-- ------------------------------------------------------------------ Gold

do
  io.write("on Gold the entry installs the Gen 2 half and no Kanto table\n")
  local mod, ran, err = install(2, "gs")
  ok(ran, "the entry runs to the end: " .. (ran and "no error" or tostring(err)))

  ok(mod.reads["gen2/main.lua"], "it asks for ALL 251")
  ok(mod.reads["gen2/celebi.lua"], "and for the GS BALL")

  for name in pairs(KANTO) do
    ok(not mod.reads[name],
       ("it never reads %s -- ALL 151's tables are Kanto's"):format(name))
  end
  eq(mod.exports.enabled, true, "and the mod reports itself installed")
end

-- ------------------------------------------------------------------- Red

do
  io.write("on Red it installs ALL 151, as it always did\n")
  local mod, ran, err = install(1, "gen1")
  ok(ran, "the entry runs to the end: " .. (ran and "no error" or tostring(err)))

  ok(mod.reads["rarity.lua"], "it reads the rarity tiers")
  ok(mod.reads["build.lua"], "and the builder the crash came from")
  ok(mod.reads["placements.lua"], "and the placement table")

  ok(not mod.reads["gen2/main.lua"], "and never reaches for ALL 251")
  ok(not mod.reads["gen2/celebi.lua"], "nor the GS BALL")
end

-- --------------------------------------------- and OFF is off on both

do
  io.write("switched off, neither half is loaded\n")
  for _, arm in ipairs({ { 1, "gen1" }, { 2, "crystal" } }) do
    generation, engineName = arm[1], arm[2]
    local mod = fakeMod()
    -- `key == "enabled" and false or nil` would answer NIL here, not false --
    -- `a and false or b` is always b -- and opt() repairs a non-boolean back
    -- to the row's default, which is ON.  The switch has to be said plainly.
    mod.options.get = function(_, key)
      if key == "enabled" then return false end
      return nil
    end
    ok(pcall(installer, mod), "it runs with the switch off")
    local any = false
    for _ in pairs(mod.reads) do any = true end
    eq(any, false,
       ("nothing is read on generation %d when the mod is off"):format(arm[1]))
  end
end

io.write(("\nentry_gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
