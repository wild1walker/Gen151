-- The three features that only exist at runtime: the LINK CABLE's use flow,
-- the Mew gate's journals, and the FIELD NOTES screen.
--
--   cd /path/to/gen1recomp
--   GEN151=/path/to/Gen151 luajit "$GEN151/tests/features_test.lua"
--
-- Everything here is driven through the buses the mod actually registered on
-- -- the loader's own hook and event tables -- rather than by calling into the
-- mod's files, so what is exercised is the wiring as installed.  The game is a
-- stub: enough of it for TextBox, the bag and the flag table, injected onto
-- the loader so mod.game and mod.world resolve to it the way they resolve to
-- the real one in a boot.

local GEN151 = os.getenv("GEN151") or "../Gen151"

if not package.path:find("./?/init.lua", 1, true) then
  package.path = "./?.lua;./?/init.lua;" .. package.path
end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local vanilla = assert(loadfile(GEN151 .. "/tests/fixtures/vanilla.lua"))()
local ROOT = GEN151:sub(1, 1) == "/" and "" or "."

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = deepCopy(v) end
  return copy
end

local function datasetFor(version)
  local data = T.fixtures.fresh()
  local source = vanilla.versions[version]
  data.encounters = deepCopy(source.encounters)
  for _, def in pairs(data.pokemon) do def.dex = nil end
  for id, def in pairs(source.pokemon) do data.pokemon[id] = deepCopy(def) end
  data.field.superRod = deepCopy(source.superRod)
  data.constants = data.constants or {}
  data.constants.dexSize = 151
  return data
end

local function aliasFs(paths, overrides)
  local inner = T.fs.new(ROOT)
  overrides = overrides or {}
  if overrides["options.lua"] == nil then
    overrides["options.lua"] = "return {}"
  end
  local alias = {}
  for _, path in ipairs(paths) do
    alias[(path:gsub("/+$", ""):match("[^/]+$"))] = path
  end
  local function map(path)
    if path == nil then return path end
    for name, real in pairs(alias) do
      local prefix = "mods/" .. name
      if path == prefix then return real end
      if path:sub(1, #prefix + 1) == prefix .. "/" then
        return real .. path:sub(#prefix + 1)
      end
    end
    return path
  end
  local loadstr = loadstring or load
  return {
    root = inner.root,
    read = function(path)
      if overrides[path] then return overrides[path] end
      return inner.read(map(path))
    end,
    load = function(path)
      if overrides[path] then return loadstr(overrides[path], path) end
      return inner.load(map(path))
    end,
    getInfo = function(path)
      if overrides[path] then return { type = "file" } end
      if path == "mods" then return { type = "directory" } end
      return inner.getInfo(map(path))
    end,
    getDirectoryItems = function(path)
      if path == "mods" then
        local names = {}
        for name in pairs(alias) do names[#names + 1] = name end
        table.sort(names)
        return names
      end
      return inner.getDirectoryItems(map(path))
    end,
  }
end

local function newStack()
  local stack = { pushed = {} }
  function stack:push(state) self.pushed[#self.pushed + 1] = state end
  function stack:top() return self.pushed[#self.pushed] end
  function stack:pop() return table.remove(self.pushed) end
  return stack
end

local function stubGame(data)
  return {
    data = data,
    stack = newStack(),
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
    save = {
      flags = {},
      inventory = {},
      bagOrder = {},
      party = {},
      pokedex = { seen = {}, owned = {} },
      player = { name = "RED" },
      options = {},
    },
  }
end

-- text of whatever box is on top, pages flattened
local function boxText(state)
  if type(state) ~= "table" or type(state.pages) ~= "table" then return nil end
  local out = {}
  for _, page in ipairs(state.pages) do
    for _, line in ipairs(page) do out[#out + 1] = tostring(line) end
  end
  return table.concat(out, " ")
end

local function load(overrides)
  local data = datasetFor("red")
  local paths = { GEN151 }
  local run = T.sdk.loadMods(paths, { data = data,
                                      fs = aliasFs(paths, overrides) })
  run.mod = select(2, next(run.mods))
  return run, data
end

-- ------------------------------------------------------- the LINK CABLE

do
  local run, data = load()
  local game = stubGame(data)
  run.loader.game = game

  local hooks = run.loader.hooks
  local vanillaUse = function() return "vanilla" end

  -- ---- on a Pokemon with no trade evolution, nothing happens but a refusal
  local pidgey = { species = "PIDGEY", level = 12, nickname = nil }
  game.save.inventory.LINK_CABLE = 2
  game.save.bagOrder = { "LINK_CABLE" }
  hooks:call("item.use", vanillaUse, game, nil, "LINK_CABLE", pidgey, nil,
             nil, nil)
  local refusal = boxText(game.stack:top())
  check(refusal ~= nil and refusal:lower():find("effect", 1, true) ~= nil,
    "cable: a mon with no trade evolution gets the no-effect line, got "
      .. tostring(refusal))
  eq(pidgey.species, "PIDGEY", "cable: and it does not evolve")
  eq(game.save.inventory.LINK_CABLE, 2,
    "cable: and the cable is NOT consumed")

  -- ---- an unrelated item falls straight through to vanilla
  eq(hooks:call("item.use", vanillaUse, game, nil, "POTION", pidgey), "vanilla",
    "cable: every other item is untouched")

  -- ---- in battle it defers to the engine's own refusal
  eq(hooks:call("item.use", vanillaUse, game, {}, "LINK_CABLE", pidgey),
    "vanilla", "cable: in battle it defers rather than wording its own no")

  -- ---- on a Kadabra it opens with the machine hum
  --
  -- The bag list and the party picker are passed in the way BagMenu passes
  -- them, because the mod is responsible for both on the far side: the open
  -- list has to end up showing the right count, and the picker has to come
  -- down.
  game.stack = newStack()
  local kadabra = { species = "KADABRA", level = 20 }
  local bag = { items = { { value = "LINK_CABLE", right = "x2" },
                          { value = "POTION", right = "x3" } }, index = 1 }
  local pickerClosed = false
  local picker = { close = function() pickerClosed = true end }
  hooks:call("item.use", vanillaUse, game, nil, "LINK_CABLE", kadabra, bag,
             nil, picker)
  local first = game.stack:top()
  eq(boxText(first), ". . .", "cable: it opens on the engine's beat idiom")
  check(first.auto ~= nil and first.auto.sound ~= nil,
    "cable: with a sound armed on it")
  eq(kadabra.species, "KADABRA",
    "cable: and nothing has evolved yet")
  eq(game.save.inventory.LINK_CABLE, 2,
    "cable: and nothing has been consumed yet")

  -- ---- dismissing it raises the "is evolving!" box, which STAYS up
  game.stack:pop()
  first.onDone()
  local intro = game.stack:top()
  local introText = boxText(intro)
  check(introText ~= nil and introText:find("KADABRA", 1, true) ~= nil,
    "cable: the second box names the Pokemon, got " .. tostring(introText))
  check(intro.stay ~= nil and type(intro.stay.onShown) == "function",
    "cable: and it stays up under the evolution screen")
  eq(game.save.inventory.LINK_CABLE, 2,
    "cable: still not consumed on the far side of the intro")

  -- ---- the evolution screen is asked for on the right terms
  --
  -- EvolutionState itself is not constructed here: it loads sprites and runs
  -- Stats.calc, neither of which this fixture can answer, and neither of
  -- which is what the mod is responsible for.  What the mod IS responsible
  -- for is the two arguments the whole design turns on -- the species and
  -- `via` -- and what it does when the screen hands control back.
  local captured
  local Screens = require("src.ui.Screens")
  local realPush = Screens.push
  Screens.push = function(g, id, ...)
    if id == "EvolutionState" then
      captured = { ... }
      return
    end
    return realPush(g, id, ...)
  end
  intro.stay.onShown()
  Screens.push = realPush

  check(captured ~= nil, "cable: it pushes the evolution screen")
  if captured then
    eq(captured[1], kadabra, "cable: on the Pokemon that was chosen")
    eq(captured[2], "ALAKAZAM", "cable: into the right species")
    eq(captured[4], "TRADE",
      "cable: as a TRADE evolution, which is what makes it non-cancelable "
        .. "and therefore always complete")
    eq(game.save.inventory.LINK_CABLE, 2,
      "cable: and STILL not consumed while the evolution is running")
  end

  -- ---- and only when the evolution comes back does the cable die
  captured[3]()
  eq(game.save.inventory.LINK_CABLE, 1,
    "cable: the evolution finishing is what consumes it")
  eq(bag.items[1].right, "x1",
    "cable: the open bag list is corrected to the new count")

  local breakBox = game.stack:top()
  check(not pickerClosed,
    "cable: the party picker is still up while the break message is on "
      .. "screen, the way vanilla holds it through showMessages")
  check(type(breakBox.onDone) == "function",
    "cable: and dismissing the break message is what takes it down")
  breakBox.onDone()
  check(pickerClosed, "cable: which it does")
  local breakText = boxText(game.stack:top())
  check(breakText ~= nil and breakText:find("ZzZzap", 1, true) ~= nil,
    "cable: the break message zaps, got " .. tostring(breakText))
  check(breakText ~= nil and breakText:lower():find("broke", 1, true) ~= nil,
    "cable: and says the cable broke")
  check(breakText ~= nil
          and breakText:find("ZzZzap", 1, true) > breakText:find(".", 1, true),
    "cable: after the beat, not before it")
  check(game.stack:top() ~= intro,
    "cable: and the is-evolving box is taken down first")

  -- ---- the last one leaves the bag entirely
  game.save.bagOrder = { "LINK_CABLE", "POTION" }
  captured[3]()
  eq(game.save.inventory.LINK_CABLE, nil,
    "cable: spending the last one clears the slot")
  eq(#game.save.bagOrder, 1,
    "cable: and drops it out of the bag order")
  eq(game.save.bagOrder[1], "POTION",
    "cable: without disturbing what was next to it")
  eq(#bag.items, 1,
    "cable: and the row leaves the open bag list too")
  eq(bag.items[1].value, "POTION",
    "cable: leaving what was next to it selected")

  run.release()
end

-- --------------------------------------------------------- the Mew gate

do
  local run, data = load({
    ["options.lua"] = 'return { modOptions = { gen151 = { mew = true } } }',
  })
  local game = stubGame(data)
  run.loader.game = game

  local exports = run.loader.exports.gen151
  local mewRow
  for _, row in ipairs(exports.rows or {}) do
    if row.species == "MEW" then mewRow = row end
  end
  check(mewRow ~= nil, "mew: with the option on, the row is resolved")

  local hooks, events = run.loader.hooks, run.loader.events
  events:emit("game.ready", { game = game })

  local function mewInTable()
    for _, record in pairs(data.encounters) do
      for _, kind in ipairs({ "grass", "water" }) do
        for _, slot in ipairs((record[kind] or {}).slots or {}) do
          if slot.species == "MEW" then return true end
        end
      end
    end
    return false
  end

  check(not mewInTable(),
    "mew: it is absent from the table before the gate, so AREA cannot "
      .. "spoil it")

  local JOURNALS = {
    "TEXT_POKEMONMANSION2F_DIARY1",
    "TEXT_POKEMONMANSION2F_DIARY2",
    "TEXT_POKEMONMANSION3F_DIARY",
    "TEXT_POKEMONMANSIONB1F_DIARY",
  }
  local talked = 0
  local function talkVanilla(_, npc)
    talked = talked + 1
    -- what the map's own text tables would put up
    game.stack:push({ pages = { { "Diary" } }, maxCols = 18 })
    return "talked"
  end

  for i = 1, 3 do
    hooks:call("world.talk", talkVanilla, {},
               { def = { text = JOURNALS[i] } })
    check(not mewInTable(),
      "mew: still absent after " .. i .. " of 4 journals")
  end
  eq(talked, 3, "mew: each journal still prints its own text")

  hooks:call("world.talk", talkVanilla, {},
             { def = { text = JOURNALS[4] } })
  eq(talked, 4, "mew: the last journal prints its own text too")
  eq(game.save.flags.GEN151_MEW_FOUND, true,
    "mew: the fourth journal flips the flag")
  check(mewInTable(), "mew: and MEW joins the table")

  -- the beat lands on the far side of the journal, not in front of it
  local box = game.stack:top()
  local text = boxText(box)
  check(text ~= nil and text:find("Diary", 1, true) ~= nil,
    "mew: the journal's own text is still the first thing on the box")
  check(text ~= nil and text:lower():find("loose", 1, true) ~= nil,
    "mew: with the discovery appended after it, got " .. tostring(text))

  -- reading one again does nothing further
  local before = #game.stack.pushed
  hooks:call("world.talk", talkVanilla, {},
             { def = { text = JOURNALS[1] } })
  eq(#game.stack.pushed, before + 1,
    "mew: re-reading a journal just prints the journal")

  -- a save without the flag drops the slot again
  game.save.flags.GEN151_MEW_FOUND = nil
  events:emit("save.loaded", { save = game.save })
  check(not mewInTable(),
    "mew: loading a save without the flag takes MEW back out")

  run.release()
end

-- ------------------------------------------------------- the FIELD NOTES

do
  local run, data = load()
  local game = stubGame(data)
  run.loader.game = game

  run.loader.events:emit("save.created", { save = game.save })
  eq(game.save.inventory.FIELD_NOTES, 1,
    "notes: the notebook is in the bag")
  run.loader.events:emit("save.loaded", { save = game.save })
  eq(game.save.inventory.FIELD_NOTES, 1,
    "notes: and granting it twice does not stack it")

  local order = 0
  for _, id in ipairs(game.save.bagOrder) do
    if id == "FIELD_NOTES" then order = order + 1 end
  end
  eq(order, 1, "notes: it appears once in the bag order")

  local pushed = false
  local Screens = require("src.ui.Screens")
  local realPush = Screens.push
  Screens.push = function(g, id, ...)
    if id == "Gen151FieldNotes" then
      pushed = true
      return
    end
    return realPush(g, id, ...)
  end
  run.loader.hooks:call("item.use", function() return "vanilla" end,
                        game, nil, "FIELD_NOTES", nil, nil, nil, nil)
  Screens.push = realPush
  check(pushed, "notes: using it opens the notebook screen")

  -- and the screen itself builds, listing what has not been caught
  local factory = data.screens and data.screens.Gen151FieldNotes
  check(factory ~= nil, "notes: the screen is registered")
  if factory then
    local built, list = pcall(factory.new, game)
    check(built, "notes: the screen constructs: " .. tostring(list))
    if built then
      check(#list.items > 0, "notes: it lists the species still missing")
      local first
      for _, item in ipairs(list.items) do
        if item.value then first = item break end
      end
      check(first ~= nil, "notes: with at least one selectable row")
      if first then
        list.onChoose(first, list)
        local hint = boxText(game.stack:top())
        check(hint ~= nil and hint ~= "",
          "notes: and choosing one says where to look")
      end
    end
  end

  -- ---- the kit row: Gen 1 has no item descriptions, so this is the only
  -- place the LINK CABLE gets explained
  local _, listed = pcall(factory.new, game)
  local kitRow
  for _, item in ipairs((listed or {}).items or {}) do
    if item.label == "LINK CABLE" then kitRow = item end
  end
  check(kitRow ~= nil, "notes: the LINK CABLE has an entry")
  eq(listed.items[1].label, "LINK CABLE",
    "notes: at the top, above the species")
  if kitRow then
    check(kitRow.value == nil,
      "notes: and it is not mistaken for a species")
    game.stack = newStack()
    listed.onChoose(kitRow, listed)
    local note = boxText(game.stack:top())
    check(note ~= nil and note:lower():find("old link cable", 1, true) ~= nil,
      "notes: which says what it is, got " .. tostring(note))
    check(note ~= nil and note:lower():find("modified", 1, true) ~= nil,
      "notes: and that it was modified")
    for _, page in ipairs(game.stack:top().pages) do
      for _, line in ipairs(page) do
        check(#line <= 18,
          "notes: every line fits the text box, but %q is %d wide",
          line, #line)
      end
    end
  end

  -- everything caught: a sentence, not a blank box, and the kit survives it
  for id in pairs(data.pokemon) do game.save.pokedex.owned[id] = true end
  local _, full = pcall(factory.new, game)
  if type(full) == "table" and full.items then
    eq(#full.items, 2, "notes: a finished notebook keeps the kit row")
    eq(full.items[1].label, "LINK CABLE",
      "notes: the kit row first")
    eq(full.items[2].label, "ALL FOUND!",
      "notes: then the sentence")
  end

  run.release()
end

T.finish("gen151 features")
