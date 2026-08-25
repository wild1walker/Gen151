-- The features that only exist at runtime: the LINK CABLE's use flow, the
-- Mew gate's journals, the four legendaries, and the words this mod hands to
-- Gen1Dex's AREA screen.
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

-- Both engine screens, held from before anything loads.  This mod wrapped
-- them for two releases and does not any more -- the AREA surface belongs to
-- Gen1Dex -- and these two are what says so.
local PRISTINE_DEX_NEW = require("src.ui.PokedexMenu").new
local PRISTINE_TOWNMAP_NEW = require("src.ui.TownMap").new

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

  -- ---- it ASKS first, which is the only place a cancel can mean anything
  --
  -- Everything past this point is a trade evolution, and a trade evolution
  -- is non-cancelable by design (via = "TRADE").  So B has to have a meaning
  -- here or it has none at all, which is exactly how it played.
  local ask = game.stack:top()
  local askText = boxText(ask)
  check(askText ~= nil and askText:find("KADABRA", 1, true) ~= nil,
    "cable: it asks before it does anything, got " .. tostring(askText))
  check(askText ~= nil and askText:lower():find("modified", 1, true) ~= nil,
    "cable: and says what the thing is, which the mart list cannot")
  check(type(ask.choice) == "function",
    "cable: as a YES/NO, so B is NO")

  -- ---- NO backs all the way out, spending nothing
  ask.choice(false)
  eq(kadabra.species, "KADABRA", "cable: NO evolves nothing")
  eq(game.save.inventory.LINK_CABLE, 2, "cable: and consumes nothing")
  check(pickerClosed, "cable: and takes the party picker back down")
  eq(#game.stack.pushed, 1,
    "cable: leaving nothing of its own on the stack")

  -- ---- YES is what starts the machine
  pickerClosed = false
  game.stack = newStack()
  hooks:call("item.use", vanillaUse, game, nil, "LINK_CABLE", kadabra, bag,
             nil, picker)
  game.stack:top().choice(true)
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

  -- ---- the break is three boxes, because it is three beats with two
  -- different sounds on them.  One box could only ever carry one sound
  -- (TextBox fires auto.sound when the LAST page of a box types out), which
  -- is why the arc had nothing to play on.
  local beat = game.stack:top()
  check(game.stack:top() ~= intro,
    "cable: the is-evolving box is taken down first")
  eq(boxText(beat), ". . .", "cable: the break opens on the beat")
  check(not pickerClosed,
    "cable: the party picker is still up while the break plays, the way "
      .. "vanilla holds it through showMessages")

  game.stack:pop()
  beat.onDone()
  local zapBox = game.stack:top()
  eq(boxText(zapBox), "ZzZzap!", "cable: then the arc")
  check(zapBox.preSound ~= nil,
    "cable: with the zap armed to fire as the box comes up, not after the "
      .. "player has finished reading it")

  game.stack:pop()
  zapBox.onDone()
  local breakBox = game.stack:top()
  local breakText = boxText(breakBox)
  check(breakText ~= nil and breakText:lower():find("broke", 1, true) ~= nil,
    "cable: then the cable breaks, got " .. tostring(breakText))
  check(breakBox.auto ~= nil and breakBox.auto.sound ~= nil,
    "cable: with the snap on it, which is the sound that was already right")
  check(type(breakBox.onDone) == "function",
    "cable: and dismissing THAT is what takes the picker down")
  breakBox.onDone()
  check(pickerClosed, "cable: which it does")

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

-- ------------------------------------------------ what the AREA map says
--
-- The SCREEN is Gen1Dex's: AREA on an entry you have never met, the box
-- under the map, the presses that take it down and put it back.  What is
-- left in this mod is the sentence -- the words for the species it placed,
-- and the one species whose answer it deliberately withholds.
--
-- So the first half of this is a subtraction: on its own, this mod puts
-- nothing on the screen and wraps nothing to get there.

do
  local run, data = load()
  local game = stubGame(data)
  run.loader.game = game

  eq(game.save.inventory.FIELD_NOTES, nil,
    "area: no key item is added to the bag")
  check(data.screens == nil or data.screens.Gen151FieldNotes == nil,
    "area: and no screen of its own is registered")
  check(require("src.ui.PokedexMenu").new == PRISTINE_DEX_NEW,
    "area: nor is the POKeDEX constructor wrapped")
  check(require("src.ui.TownMap").new == PRISTINE_TOWNMAP_NEW,
    "area: nor the town map's -- both of those are Gen1Dex's to wrap")

  -- ---- the words themselves, off the same resolved rows as the spawn, so a
  -- hint cannot drift from the thing it describes
  local Hints = run.loader.exports.gen151.hints
  check(Hints ~= nil, "area: the hint vocabulary is published")
  local placed
  for _, row in ipairs(run.loader.exports.gen151.rows or {}) do
    if not row.gated then placed = row break end
  end
  check(placed ~= nil, "area: there is a placed species to caption")

  -- 18 columns, because the caption sits in a box built from the game's own
  -- frame tiles and that is the interior width TextBox.paginate wraps to
  local caption = Hints.caption({ placed }, 18)
  check(type(caption) == "table" and caption[1] ~= nil,
    "area: which produces a caption")
  for _, line in ipairs(caption or {}) do
    check(#line <= 18,
      ("area: every caption line fits the box, but %q is %d wide")
        :format(line, #line))
  end

  eq(Hints.caption({}, 18), nil,
    "area: a species with no rows produces no placement caption")

  -- ---- and with no Gen1Dex installed, AREA is the cartridge's own screen
  -- with this mod's nests on it, which is the whole of what Gen151 alone is
  -- meant to do to that screen.  The nests are free: they come off the
  -- appended slots in data.encounters, which TownMap scans for itself, and no
  -- part of this mod goes anywhere near the screen to put them there.
  local TownMap = require("src.ui.TownMap")
  -- the fixture's town map knows two of its own maps and none of Kanto's, and
  -- a nest is only drawn for a map the town map can place; the real dataset
  -- has an entry for every one, so the placed row's map gets one here
  local townMap = data.field.townMap
  townMap.locations = townMap.locations or {}
  townMap.locations[placed.map] = townMap.locations[placed.map]
    or { x = 5, y = 5, name = "PLACED" }
  local screen = TownMap.new(game, { nestSpecies = placed.species })
  check(type(screen) == "table", "area: the AREA screen still builds")
  eq(rawget(screen, "draw"), nil,
    "area: with no caption strip installed over it -- the box is Gen1Dex's, "
      .. "and Gen1Dex is not here")
  eq(rawget(screen, "update"), nil,
    "area: and no input of its own, so A closes it the way A always did")
  check(type(screen.nests) == "table" and #screen.nests > 0,
    "area: and " .. placed.species .. "'s nest blinks on it anyway, because "
      .. "the spawn is in the encounter table the engine already reads")

  -- MEW is the one that must NOT be marked, gate shut: no caption to withhold
  -- and no nest either, because the row is not in the table yet
  local mew = TownMap.new(game, { nestSpecies = "MEW" })
  eq(#(mew.nests or {}), 0,
    "area: and MEW's map is blank while its gate is shut")

  run.release()
end

-- ---- and next to the mod that draws the screen
--
-- Set GEN1DEX to a Gen1Dex checkout to run it; skipped, loudly, when absent.

local GEN1DEX = os.getenv("GEN1DEX")
if GEN1DEX then
  local data = datasetFor("red")
  local paths = { GEN151, GEN1DEX }
  local run = T.sdk.loadMods(paths, { data = data, fs = aliasFs(paths) })
  eq(#run.errors, 0, "hints: both mods load clean ("
    .. table.concat(run.errors, "; ") .. ")")

  local game = stubGame(data)
  -- before anything asks this mod a question: mod.world memoizes the Game it
  -- first resolved against, and an uninjected loader hands back the boot
  -- singleton, whose save has no flags on it
  run.loader.game = game

  local exports = run.loader.exports.gen151
  local area = run.loader.exports.Gen1Dex and run.loader.exports.Gen1Dex.area
  check(area ~= nil and type(area.caption) == "function",
    "hints: Gen1Dex publishes the AREA surface this mod writes on")

  local Font = require("src.render.Font")
  local Hints = exports.hints
  local cols = (area and area.cols) or 17

  -- ---- every species this mod placed, captioned in this mod's own words
  -- and inside the box Gen1Dex draws them in.  Measured in the pixels the
  -- glyphs actually draw rather than in bytes, because a variable-advance
  -- font skin makes those two different numbers -- and the second line is a
  -- column shorter than the first, because the blinking prompt sits there.
  -- The rows for one species, the way the mod's own provider gathers them:
  -- every live placement plus every Super Rod row, because a species with
  -- two homes is captioned once for both.
  local function rowsFor(species)
    local out = {}
    for _, row in ipairs(exports.rows or {}) do
      if row.species == species and not row.gated then out[#out + 1] = row end
    end
    for _, row in ipairs(exports.fishing or {}) do
      if row.species == species then out[#out + 1] = row end
    end
    return out
  end

  local species, order = {}, {}
  for _, row in ipairs(exports.rows or {}) do
    if not row.gated and not species[row.species] then
      species[row.species] = true
      order[#order + 1] = row.species
    end
  end
  for _, row in ipairs(exports.fishing or {}) do
    if not species[row.species] then
      species[row.species] = true
      order[#order + 1] = row.species
    end
  end

  local checked, widest = 0, nil
  for _, id in ipairs(order) do
    local lines = area.caption(game, id)
    check(type(lines) == "table" and lines[1] ~= nil,
      "hints: " .. id .. " is captioned on the AREA screen")
    local mine = Hints.caption(rowsFor(id), cols)
    if lines and mine then
      eq(lines[1], mine[1],
        "hints: in this mod's words rather than the generic reading, for " .. id)
      -- the second line is compared as a PREFIX: it is the tight one (the
      -- blinking prompt sits in its last column) and the box does its own
      -- cutting there, so "NEEDS THE SAFARI ZONE" arrives on screen cut.
      -- What this is checking is that the words are ours, not that they
      -- survived the box whole
      check(mine[2] == nil
              or (lines[2] ~= nil and mine[2]:sub(1, #lines[2]) == lines[2]),
        ("hints: on both lines, for %s (got %s, want %s)")
          :format(id, tostring(lines[2]), tostring(mine[2])))
    end
    for index, line in ipairs(lines or {}) do
      local budget = index == 1 and 18 or cols
      local spans = Font.split(line)
      if Font.spansFitting(spans, budget * 8) < #spans then widest = line end
      checked = checked + 1
    end
  end
  check(checked > 0, "hints: there were captions to measure")
  eq(widest, nil,
    ("hints: and every line of every one fits its own budget, unlike %q")
      :format(tostring(widest)))

  -- ---- and the whole chain, on the screen the player really opens
  local TownMap = require("src.ui.TownMap")
  local sample
  for _, row in ipairs(exports.rows or {}) do
    if not row.gated then sample = row.species break end
  end
  local screen = TownMap.new(game, { nestSpecies = sample })
  check(type(screen) == "table" and rawget(screen, "draw") ~= nil,
    "hints: opening AREA on a placed species really installs the strip")

  -- ---- MEW's answer is WITHHELD, not merely missing
  --
  -- Gen1Dex reads the encounter tables on its own, and the moment the gate
  -- patches MEW in they would answer for it.  `false` is how this mod says
  -- "mine, and not yet": a caption would spoil the basement more precisely
  -- than a nest ever could.
  local mewRow
  for _, row in ipairs(exports.rows or {}) do
    if row.species == "MEW" then mewRow = row end
  end
  check(mewRow ~= nil and mewRow.gated == "mew",
    "hints: MEW's row is the gated one")
  eq(area.caption(game, "MEW"), nil,
    "hints: and it is uncaptioned while its gate is shut")
  local sealed = TownMap.new(game, { nestSpecies = "MEW" })
  eq(rawget(sealed, "draw"), nil,
    "hints: so its AREA screen is the cartridge's own, strip and all")

  game.save.flags.GEN151_MEW_FOUND = true
  run.loader.events:emit("save.loaded", { save = game.save })
  local opened = area.caption(game, "MEW")
  check(type(opened) == "table" and opened[1] ~= nil,
    "hints: and the caption turns up the moment the gate opens")
  game.save.flags.GEN151_MEW_FOUND = nil
  run.loader.events:emit("save.loaded", { save = game.save })
  eq(area.caption(game, "MEW"), nil,
    "hints: and goes away again on a save that never opened it")

  run.release()
else
  io.write("note: GEN1DEX is unset, so the caption cases were not run\n")
end


-- --------------------------------------------------- the four legendaries
--
-- Vanilla sets EVENT_BEAT_<SPECIES> on ANY non-blackout end -- win, catch or
-- flee alike (src/script/Commands.lua static_battle, quoting
-- home/trainers.asm) -- and hides the object.  So knocking one out by
-- accident, or panicking and running, deletes that species from the file.
-- This puts it back unless it was actually caught.

do
  local run, data = load()
  local game = stubGame(data)
  run.loader.game = game

  local MAP = "SEAFOAM_ISLANDS_B4F"
  local OBJ = "SEAFOAMISLANDSB4F_ARTICUNO"

  local function beaten()
    game.save.flags.EVENT_BEAT_ARTICUNO = true
    game.save.objectToggles = { [MAP] = { [OBJ] = false } }
  end

  -- ---- fled or knocked out: it comes back
  beaten()
  run.loader.events:emit("map.entered", { mapId = MAP })
  eq(game.save.flags.EVENT_BEAT_ARTICUNO, nil,
    "legendary: the beat flag is cleared, so the script will battle again")
  eq(game.save.objectToggles[MAP][OBJ], true,
    "legendary: and its object is back on the map")

  -- ---- caught: vanilla behaviour exactly, because there is nothing to fix
  beaten()
  game.save.pokedex.owned.ARTICUNO = true
  run.loader.events:emit("map.entered", { mapId = MAP })
  eq(game.save.flags.EVENT_BEAT_ARTICUNO, true,
    "legendary: a CAUGHT one stays caught")
  eq(game.save.objectToggles[MAP][OBJ], false,
    "legendary: and its object stays gone")
  game.save.pokedex.owned.ARTICUNO = nil

  -- ---- idempotent: the sweep runs on every map entry forever
  beaten()
  for _ = 1, 3 do
    run.loader.events:emit("map.entered", { mapId = MAP })
  end
  eq(game.save.objectToggles[MAP][OBJ], true,
    "legendary: repeated entries leave it showing, not flickering")

  -- ---- another map's entry does not touch it
  beaten()
  run.loader.events:emit("map.entered", { mapId = "ROUTE_1" })
  eq(game.save.flags.EVENT_BEAT_ARTICUNO, true,
    "legendary: entering somewhere else changes nothing")

  -- ---- and it never touches an object that is not this species'
  game.save.objectToggles[MAP].SEAFOAMISLANDSB4F_BOULDER = false
  run.loader.events:emit("map.entered", { mapId = MAP })
  eq(game.save.objectToggles[MAP].SEAFOAMISLANDSB4F_BOULDER, false,
    "legendary: a hidden boulder on the same map is left alone")

  run.release()
end

-- ---- and with the option set to ONE SHOT, nothing is installed at all

do
  local data = datasetFor("red")
  local paths = { GEN151 }
  local run = T.sdk.loadMods(paths, { data = data, fs = aliasFs(paths, {
    ["options.lua"] = 'return { modOptions = { gen151 = '
      .. '{ legendaries = "once" } } }',
  }) })
  local game = stubGame(data)
  run.loader.game = game
  game.save.flags.EVENT_BEAT_ARTICUNO = true
  game.save.objectToggles = {
    SEAFOAM_ISLANDS_B4F = { SEAFOAMISLANDSB4F_ARTICUNO = false },
  }
  run.loader.events:emit("map.entered", { mapId = "SEAFOAM_ISLANDS_B4F" })
  eq(game.save.flags.EVENT_BEAT_ARTICUNO, true,
    "legendary: ONE SHOT leaves the cartridge's behaviour exactly alone")
  run.release()
end

-- --------------------------------------------------------- the debug bench
--
-- The bench exists to reach what a headless suite cannot, so most of it can
-- only be judged by a human.  What CAN be checked here is that it does not
-- lie: that forcing a spawn still respects the encounter rate, that the
-- species it forces are ones Gen151 actually placed, and that the Mew toggle
-- moves the encounter table rather than just the flag.

do
  local data = datasetFor("red")
  local paths = { GEN151 }
  local run = T.sdk.loadMods(paths, { data = data, fs = aliasFs(paths, {
    ["options.lua"] =
      'return { modOptions = { gen151 = { bench = true } } }',
  }) })
  local game = stubGame(data)
  run.loader.game = game

  eq(#run.errors, 0, "bench: it loads clean ("
    .. table.concat(run.errors, "; ") .. ")")

  -- ---- and it is OFF unless the option says otherwise, because a player
  -- who never asked for a bench must never be handed one
  do
    local quietData = datasetFor("red")
    local quiet = T.sdk.loadMods({ GEN151 }, { data = quietData,
      fs = aliasFs({ GEN151 }, {}) })
    quiet.loader.game = stubGame(quietData)
    local items = quiet.loader.hooks:call("ui.start_menu.items",
      function(_, given) return given end, quiet.loader.game,
      { { label = "POKeDEX" } })
    eq(#items, 1, "bench: default off adds no START row")
    check(quietData.screens == nil
            or quietData.screens.Gen151DebugBench == nil,
      "bench: and registers no screen")
    quiet.release()
  end

  -- ---- it puts itself on the OPTIONS menu and leaves the rest alone
  --
  -- Next to MODS, not at the end: OptionRows.VISIBLE is 4 and the desktop
  -- list is about thirty rows long, so an APPENDED row is seven screenfuls
  -- down and reads as missing.  This asserts the position, because the
  -- position is the bug that was reported.
  local rows = run.loader.hooks:call("ui.options.rows",
    function(_, given) return given end, game,
    { { id = "SOMEONE_ELSE" }, { id = "mods" }, { id = "controls" } })
  local at
  for i, row in ipairs(rows) do
    if row.id == "gen151_bench" then at = i end
  end
  check(at ~= nil, "bench: it adds an OPTIONS row")
  eq(at, 3, "bench: directly under MODS, inside the first screenful")
  eq(#rows, 4, "bench: without dropping anyone else's")
  check(rows[1] and rows[1].id == "SOMEONE_ELSE",
    "bench: and without reordering them")
  check(rows[4] and rows[4].id == "controls",
    "bench: the rows after MODS survive too")

  -- no MODS row to anchor to: append rather than lose the entry
  local noAnchor = run.loader.hooks:call("ui.options.rows",
    function(_, given) return given end, game, { { id = "SOMEONE_ELSE" } })
  eq(#noAnchor, 2, "bench: with no MODS row it still lands")
  eq(noAnchor[2] and noAnchor[2].id, "gen151_bench",
    "bench: appended, which keeps it reachable either way")

  -- ---- and on the START menu, which is the door that cannot scroll away
  local items = run.loader.hooks:call("ui.start_menu.items",
    function(_, given) return given end, game,
    { { label = "POKeDEX" }, { label = "QUIT" } })
  eq(#items, 3, "bench: it adds a START menu item")
  eq(items[1] and items[1].label, "BENCH", "bench: at the top, above the fold")
  check(type(items[1].onSelect) == "function", "bench: which opens something")
  eq(items[3] and items[3].label, "QUIT", "bench: leaving the rest in order")

  -- ---- the bench screen builds
  local factory = data.screens and data.screens.Gen151DebugBench
  check(factory ~= nil, "bench: the screen is registered")
  local built, list = pcall(factory.new, game)
  check(built, "bench: it constructs: " .. tostring(list))

  local function rowNamed(prefix)
    for _, item in ipairs((list or {}).items or {}) do
      if tostring(item.label):sub(1, #prefix) == prefix then return item end
    end
  end

  -- ---- forcing respects the encounter RATE
  --
  -- The bench sits above Gen151 in the chain and calls next() before it
  -- decides anything, so a step that would not have met anything still meets
  -- nothing.  Forcing WHAT you meet is the whole point; forcing WHETHER
  -- would make the walk a lie.
  local toggle = rowNamed("SPAWNS")
  check(toggle ~= nil, "bench: it has a SPAWNS toggle")
  eq(toggle and toggle.label, "SPAWNS: OFF", "bench: which starts off")
  list.onChoose(toggle, list)
  eq(toggle.label, "SPAWNS: ON", "bench: and turns on")

  local hooks = run.loader.hooks
  local ctx = { mapId = "ROUTE_4", terrain = "grass",
                rng = function(_, hi) return hi end }
  eq(hooks:call("encounter.roll", function() return nil end,
                data.encounters.ROUTE_4, ctx), nil,
    "bench: a step with no encounter still has none, forced or not")

  local placed = {}
  for _, row in ipairs(run.loader.exports.gen151.rows or {}) do
    if row.map == "ROUTE_4" then placed[row.species] = row end
  end
  check(next(placed) ~= nil, "bench: ROUTE_4 has placements to force")
  local seen = {}
  for _ = 1, 8 do
    local enc = hooks:call("encounter.roll",
      function() return { species = "RATTATA", level = 3 } end,
      data.encounters.ROUTE_4, ctx)
    check(placed[enc.species] ~= nil,
      "bench: every forced encounter is one Gen151 placed, got "
        .. tostring(enc.species))
    seen[enc.species] = true
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  local total = 0
  for _ in pairs(placed) do total = total + 1 end
  eq(distinct, total,
    "bench: and round-robin reaches every one of the map's placements")

  -- turning it back off hands the encounter straight back
  list.onChoose(toggle, list)
  eq(toggle.label, "SPAWNS: OFF", "bench: the toggle goes back")
  local back = hooks:call("encounter.roll",
    function() return { species = "RATTATA", level = 3 } end,
    data.encounters.ROUTE_4, { mapId = "ROUTE_1", terrain = "grass" })
  eq(back.species, "RATTATA", "bench: and stops forcing")

  -- ---- the Mew toggle moves the TABLE, not just the flag
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
  local mew = rowNamed("MEW")
  check(mew ~= nil, "bench: it has a MEW toggle")
  eq(mew and mew.label, "MEW: HIDDEN", "bench: which starts hidden")
  check(not mewInTable(), "bench: with MEW out of the table")
  list.onChoose(mew, list)
  eq(mew.label, "MEW: FOUND", "bench: it flips")
  eq(game.save.flags.GEN151_MEW_FOUND, true, "bench: setting the flag")
  check(mewInTable(),
    "bench: and asking Gen151 to put MEW in the table, which is what AREA "
      .. "reads")
  list.onChoose(mew, list)
  check(not mewInTable(), "bench: flipping back takes it out again")

  -- ---- dex fill
  local fill = rowNamed("DEX FILL")
  check(fill ~= nil, "bench: it has a DEX FILL row")
  list.onChoose(fill, list)
  eq(game.save.pokedex.seen.BULBASAUR, true,
    "bench: which marks species SEEN, the flag AREA and the HINT row read")
  eq(game.save.pokedex.owned.BULBASAUR, nil,
    "bench: without marking them OWNED, which would empty the notebook")

  run.release()
end

T.finish("gen151 features")
