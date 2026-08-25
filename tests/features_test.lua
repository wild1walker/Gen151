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

-- ----------------------------------------------------- AREA on an unknown
--
-- The whole hint surface, after the FIELD NOTES item and the companion mod
-- that came before it were both thrown away: the POKeDEX opens AREA on a
-- Pokemon you have never met, and the map it opens has a line under it.

do
  local run, data = load()
  local game = stubGame(data)
  run.loader.game = game

  eq(game.save.inventory.FIELD_NOTES, nil,
    "area: no key item is added to the bag any more")
  check(data.screens == nil or data.screens.Gen151FieldNotes == nil,
    "area: and no screen of its own is registered")

  -- ---- a PLACED species is captioned from the same resolved rows as its
  -- spawn, so a hint cannot drift from the thing it describes
  local Hints = run.loader.exports.gen151.hints
  check(Hints ~= nil, "area: the hint vocabulary is published")
  local placed
  for _, row in ipairs(run.loader.exports.gen151.rows or {}) do
    if not row.gated then placed = row break end
  end
  check(placed ~= nil, "area: there is a placed species to caption")

  -- 18 columns, because the hint sits in the game's own dialogue box now and
  -- that is the interior width TextBox.paginate wraps to
  local caption = Hints.caption({ placed }, 18)
  check(type(caption) == "table" and caption[1] ~= nil,
    "area: which produces a caption")
  for _, line in ipairs(caption or {}) do
    check(#line <= 18,
      ("area: every caption line fits the box, but %q is %d wide")
        :format(line, #line))
  end

  -- ---- and so is a VANILLA one, which is the whole of the second ask: the
  -- hint is for all 151, not just the ones this mod moved.  Nothing about
  -- this depends on having caught it -- the caption is read out of the
  -- encounter tables, which do not know or care what the player owns.
  local TownMap = require("src.ui.TownMap")
  local captured = {}
  local realDraw = love.graphics.rectangle
  local function captionOf(species)
    local seen = {}
    local screen = TownMap.new(game, { nestSpecies = species })
    if type(screen) ~= "table" then return nil end
    -- the strip is drawn by an instance-level draw the wrap installed; a
    -- screen with no caption never installs one
    return screen, screen.draw ~= TownMap.draw
  end

  local vanillaSpecies
  for mapId, record in pairs(data.encounters or {}) do
    for _, slot in ipairs((record.grass or {}).slots or {}) do
      local ours = false
      for _, row in ipairs(run.loader.exports.gen151.rows or {}) do
        if row.species == slot.species then ours = true end
      end
      if not ours then vanillaSpecies = vanillaSpecies or slot.species end
    end
  end
  check(vanillaSpecies ~= nil,
    "area: the fixture has a vanilla species this mod never touched")

  local _, hasCaption = captionOf(vanillaSpecies)
  check(hasCaption,
    "area: which is captioned anyway, caught or not -- " ..
      tostring(vanillaSpecies))

  for _, owned in ipairs({ true, false }) do
    game.save.pokedex.owned[vanillaSpecies] = owned or nil
    game.save.pokedex.seen[vanillaSpecies] = owned or nil
    local _, still = captionOf(vanillaSpecies)
    check(still, "area: and stays captioned with owned=" .. tostring(owned))
  end
  game.save.pokedex.owned[vanillaSpecies] = nil
  game.save.pokedex.seen[vanillaSpecies] = nil

  -- ---- a press takes the strip away, because it covers two tile rows of
  -- Kanto and one of them has nests in it
  local screen = TownMap.new(game, { nestSpecies = vanillaSpecies })
  local popped = false
  game.stack = newStack()
  game.stack.pop = function(self) popped = true return table.remove(self.pushed) end
  local pressed = "a"
  game.input = { wasPressed = function(_, btn) return btn == pressed end,
                 isDown = function() return false end }
  screen.game = game

  -- Four rows at the bottom, not the dialogue box's six: 0,14 x 20,4 in
  -- tiles, which Font.drawBox fills as 0,112 x 160,32 in pixels.  The height
  -- is the assertion -- a six-row box passes every other check here and still
  -- eats two more tile rows of Kanto than it needs to.
  local painted = 0
  local realRect = love.graphics.rectangle
  love.graphics.rectangle = function(mode, x, y, w, h)
    if x == 0 and y == 112 and w == 160 and h == 32 then
      painted = painted + 1
    end
    return realRect(mode, x, y, w, h)
  end
  screen:draw()
  eq(painted, 1, "area: the box is on screen to begin with, four rows tall")

  screen:update(0)
  check(not popped,
    "area: the first A takes the hint down rather than closing the map")
  painted = 0
  screen:draw()
  eq(painted, 0, "area: and the box really is gone")

  -- ---- START brings it back, because dismissing a hint you were still
  -- reading should not mean leaving the screen and coming in again
  pressed = "start"
  screen:update(0)
  check(not popped, "area: START does not close the map")
  painted = 0
  screen:draw()
  eq(painted, 1, "area: it brings the hint back")

  -- and A still dismisses the reopened one rather than closing the screen
  pressed = "a"
  screen:update(0)
  check(not popped, "area: A dismisses the reopened hint")
  painted = 0
  screen:draw()
  eq(painted, 0, "area: which goes away again")

  screen:update(0)
  check(popped, "area: and only THEN does A close it, the way A always did")
  love.graphics.rectangle = realRect

  -- ---- nothing the text draws may reach the column the prompt sits in
  --
  -- The bug: the second line was budgeted the full 18 columns of box
  -- interior, and the arrow is drawn in the eighteenth.  "VERY RARE  2 SPOTS"
  -- is exactly 18, so the arrow landed on the final S.  The six-row dialogue
  -- box hid this -- it has a blank row under its text for the arrow to sit
  -- in, and the four-row box does not.
  --
  -- Measured through a real draw rather than by counting the string, because
  -- what collides is pixels: Font.draw takes a whole line and its width is
  -- the sum of the glyph advances.
  do
    local Font = require("src.render.Font")
    local ARROW_X = (0 + 20 - 2) * 8      -- the box's own arithmetic
    local worst, widest = 0, nil
    local realDraw, realCode = Font.draw, Font.drawCode
    local arrowAt
    Font.draw = function(text, x, y)
      if y >= 96 then
        local spans = Font.split(tostring(text))
        local width = 0
        for _, span in ipairs(spans) do
          width = width + Font.advanceOf(span.code)
        end
        if x + width > worst then
          worst, widest = x + width, tostring(text)
        end
      end
      return realDraw(text, x, y)
    end
    Font.drawCode = function(code, x, y)
      if y >= 96 then arrowAt = x end
      return realCode(code, x, y)
    end

    -- every species the mod placed, so the widest caption in the whole table
    -- is the one this is judged on rather than a species picked by hand
    local seen = {}
    for _, row in ipairs(run.loader.exports.gen151.rows or {}) do
      if not seen[row.species] then
        seen[row.species] = true
        local one = TownMap.new(game, { nestSpecies = row.species })
        if type(one) == "table" and one.draw then
          one.game = game
          one.blink = 0            -- arrow showing
          one:draw()
        end
      end
    end
    Font.draw, Font.drawCode = realDraw, realCode

    check(next(seen) ~= nil, "arrow: there were captions to draw")
    eq(arrowAt, ARROW_X, "arrow: the prompt is in the box's last-but-one cell")
    check(worst <= ARROW_X,
      ("arrow: the widest caption line ends at %d, which reaches the prompt "
        .. "cell at %d -- %q"):format(worst, ARROW_X, tostring(widest)))
  end

  -- ---- and the header is made to fit, because vanilla writes into an
  -- 19-column strip without measuring: "CHARIZARD AREA UNKNOWN" is 22 and ran
  -- off the right edge of the screen mid-word
  local Font = require("src.render.Font")
  local drawn = {}
  local realDrawText = Font.draw
  Font.draw = function(text, x, y)
    if y == 0 then drawn[#drawn + 1] = tostring(text) end
    return realDrawText(text, x, y)
  end
  local longName = "CHARIZARD"
  check(game.data.pokemon[longName] ~= nil,
    "area: the fixture has " .. longName .. ", which is the name that "
      .. "overflowed")
  local long = TownMap.new(game, { nestSpecies = longName })
  long.game = game
  long:draw()
  Font.draw = realDrawText
  local header = drawn[#drawn]
  check(header ~= nil, "area: a header was drawn")
  if header then
    local spans = Font.split(header)
    check(Font.spansFitting(spans, 19 * 8) >= #spans,
      ("area: and it fits the strip, unlike %q"):format(header))
    check(header:find(longName, 1, true) ~= nil,
      "area: while still naming the Pokemon, got " .. header)
  end

  -- ---- MEW's caption stays sealed until its gate opens, because a caption
  -- would spoil the basement more precisely than a nest ever could
  local mewRow
  for _, row in ipairs(run.loader.exports.gen151.rows or {}) do
    if row.species == "MEW" then mewRow = row end
  end
  check(mewRow ~= nil and mewRow.gated == "mew",
    "area: MEW's row is the gated one")
  local _, mewCaptioned = captionOf("MEW")
  check(not mewCaptioned,
    "area: and MEW has no caption while its gate is shut")

  eq(Hints.caption({}, 18), nil,
    "area: a species with no rows produces no placement caption")

  local PokedexMenu = require("src.ui.PokedexMenu")
  check(PokedexMenu.new ~= nil and TownMap.new ~= nil,
    "area: both engine screens are still callable after the wrap")

  -- ---- an undiscovered entry opens a side menu, which vanilla refuses to do
  local list = PokedexMenu.new(game, {})
  check(type(list) == "table" and type(list.items) == "table",
    "area: the dex list still builds")
  local unknown
  for _, item in ipairs(list.items or {}) do
    if not item.value then unknown = item break end
  end
  check(unknown ~= nil, "area: with an undiscovered entry in it")
  game.stack = newStack()
  list.onChoose(unknown, list)
  local menu = game.stack:top()
  check(menu ~= nil, "area: choosing it opens something, where vanilla "
    .. "returns early and opens nothing")
  local labels = {}
  for _, entry in ipairs((menu or {}).items or {}) do
    labels[#labels + 1] = entry.label
  end
  eq(labels[1], "AREA", "area: whose first row is AREA")
  eq(labels[2], "QUIT",
    "area: and whose second is QUIT -- DATA on a Pokemon you have never met "
      .. "would hand over the dex paragraph, which nobody asked for")

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
