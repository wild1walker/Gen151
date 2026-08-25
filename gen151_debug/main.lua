-- Gen151 Debug -- a test bench for the parts of Gen151 that only exist once a
-- game is running.
--
-- Everything Gen151 does to the encounter tables is covered by headless tests.
-- What those cannot reach is anything that has to be seen or heard: whether
-- "ZzZzap" renders, whether the cable snap sounds like an electrical fault or
-- like a mistake, whether the FIELD NOTES list fits its box, whether AREA
-- really blinks a nest on the maps Gen151 added to -- and whether a very-rare
-- tier is a satisfying hunt or just a long one.
--
-- Reaching those in normal play means buying a cable, finding a Kadabra,
-- surfing to Cinnabar and walking through grass a few thousand times.  This
-- collapses that into a menu.
--
-- **Delete it before release.**  It is a separate mod so that deleting it is
-- all it takes, and so the shipped mod carries no debug rows in its options.
--
-- It asks for no permissions and changes nothing about Gen151: it reads the
-- resolved placement rows out of `mod.find("gen151").exports` and drives the
-- same public seams any mod has -- mod.world, mod.ui, and one high-priority
-- wrap on `encounter.roll` that sits ABOVE Gen151's own.

local FORCE_PRIORITY = 100

-- What the kit hands over, and why each one is in it.
local KIT_ITEMS = {
  { id = "LINK_CABLE", count = 5, why = "four trade evolutions and a spare" },
  { id = "SUPER_ROD", count = 1, why = "the two Super Rod placements" },
  { id = "GOOD_ROD", count = 1, why = "the rod Gen151 does NOT touch" },
  { id = "OLD_ROD", count = 1, why = "ditto" },
  { id = "POKE_FLUTE", count = 1, why = "the Route 12/16 sleepers" },
  { id = "SILPH_SCOPE", count = 1, why = "Pokemon Tower" },
}

-- One of each trade evolution's pre-form, so all four cables have somewhere
-- to go, and so the party is never empty when a forced battle starts.
local KIT_PARTY = {
  { "KADABRA", 25 }, { "MACHOKE", 30 }, { "GRAVELER", 30 }, { "HAUNTER", 30 },
}

local MEW_FLAGS = {
  "GEN151_MEW_DIARY_1", "GEN151_MEW_DIARY_2",
  "GEN151_MEW_DIARY_3", "GEN151_MEW_DIARY_4",
}
local MEW_FOUND = "GEN151_MEW_FOUND"

-- The list of things that need a human, in the order they are cheapest to
-- check.  Printed by the CHECKLIST row so the bench says what it is for.
local CHECKLIST = {
  "1 CABLE SFX\nDoes the snap read\nas electrical?",
  "2 BREAK BOX\nDoes ZzZzap render,\nand does it land\nafter the evolution?",
  "3 KIT, then use a\nLINK CABLE on the\nKADABRA. Watch for\na B press doing\nnothing.",
  "4 SPAWNS ON, then\nwalk. Every battle\nis a GEN151 one.",
  "5 NOTES: open FIELD\nNOTES. Does the list\nfit? Do the hints\nmatch what you met?",
  "6 DEX FILL, then\nPOKeDEX, AREA on a\nplaced species. Nest\non the right map?",
  "7 MEW: flip it OFF,\ncheck AREA shows no\nnest. Flip ON, check\nit does.",
  "8 CELADON MART 4F.\nIs LINK CABLE on the\nshelf at 2100?",
}

return function(mod)
  mod.options:define{
    { key = "enabled", type = "toggle", label = "DEBUG BENCH", default = true },
  }
  if mod.options:get("enabled") ~= true then return end

  local gen151 = mod.find("gen151")
  if not gen151 or not gen151.exports or gen151.exports.enabled ~= true then
    mod.log:warn("Gen151 is not loaded, so there is nothing to bench -- "
      .. "install it alongside this mod, or disable this one")
    return
  end
  local E = gen151.exports

  -- ------------------------------------------------------ the placement index

  local byMap, mapOrder, seenMap = {}, {}, {}
  local function index(row, kind)
    local key = row.map .. "|" .. kind
    local list = byMap[key]
    if not list then
      list = {}
      byMap[key] = list
    end
    list[#list + 1] = row
    if not seenMap[row.map] then
      seenMap[row.map] = true
      mapOrder[#mapOrder + 1] = row.map
    end
  end
  for _, row in ipairs(E.rows or {}) do
    index(row, row.method == "water" and "water" or "grass")
  end
  for _, row in ipairs(E.fishing or {}) do index(row, "rod") end
  table.sort(mapOrder)

  -- ------------------------------------------------------------- small tools

  local function say(game, text, onDone)
    game.stack:push(mod.ui.TextBox.new(game, text, onDone))
  end

  -- The console's own warp pops the whole stack before it moves the player.
  -- Same idea, without reaching for the overworld module: pop down to the
  -- object mod.world already resolves, so a battle or a warp starts from a
  -- clean stack instead of from under three menus.
  local function toOverworld(game)
    local ow = mod.world and mod.world:overworld()
    if not ow then return nil, "no overworld" end
    local guard = 0
    while game.stack:top() and game.stack:top() ~= ow and guard < 64 do
      game.stack:pop()
      guard = guard + 1
    end
    if game.stack:top() ~= ow then return nil, "could not reach the overworld" end
    return ow
  end

  -- Bag.add's rule, without requiring the module.
  local function giveItem(save, id, count)
    save.inventory = save.inventory or {}
    save.bagOrder = save.bagOrder or {}
    if not save.inventory[id] then
      save.bagOrder[#save.bagOrder + 1] = id
    end
    save.inventory[id] = math.min(99, (save.inventory[id] or 0) + count)
  end

  local function sound(game, name)
    local opts = mod.ui.TextBox.soundOpts(game, name)
    return opts and opts.auto and opts.auto.sound
  end

  -- --------------------------------------------------------------- the forcer
  --
  -- Wrapped ABOVE Gen151 (higher priority runs first), and it calls next()
  -- before it decides anything -- so the encounter RATE is still the vanilla
  -- roll's answer.  This forces WHAT you meet, never WHETHER you meet it,
  -- which is the only way the walk still feels like the real thing.
  local force = { on = false, seen = 0 }

  mod.hooks:wrap("encounter.roll", function(nextLink, encDef, ctx)
    local enc = nextLink(encDef, ctx)
    if not enc or not force.on then return enc end
    local kind = (ctx and ctx.terrain) == "water" and "water" or "grass"
    local rows = byMap[(ctx and ctx.mapId or "") .. "|" .. kind]
    if not rows or #rows == 0 then return enc end
    -- round robin rather than random: every placement on the map turns up,
    -- in order, so a walk covers the whole map's additions instead of
    -- rolling the same one six times
    force.seen = force.seen + 1
    local row = rows[(force.seen - 1) % #rows + 1]
    return { species = row.species, level = (row.levels or {})[1] or enc.level }
  end, FORCE_PRIORITY)

  mod.hooks:wrap("encounter.fishing", function(nextLink, rod, mapId, pool)
    local enc = nextLink(rod, mapId, pool)
    if not enc or not force.on then return enc end
    local rows = byMap[(mapId or "") .. "|rod"]
    if not rows or #rows == 0 then return enc end
    force.seen = force.seen + 1
    local row = rows[(force.seen - 1) % #rows + 1]
    return { species = row.species, level = (row.levels or {})[1] or enc.level }
  end, FORCE_PRIORITY)

  -- ------------------------------------------------------------- the actions

  local function actKit(game, list)
    local save = game.save
    for _, entry in ipairs(KIT_ITEMS) do
      if game.data.items[entry.id] then
        giveItem(save, entry.id, entry.count)
      end
    end
    list:close()
    local ow, err = toOverworld(game)
    if not ow then
      say(game, "Bag filled, but the\nparty needs the\noverworld.\f" .. tostring(err))
      return
    end
    local rows = {}
    for _, mon in ipairs(KIT_PARTY) do
      if game.data.pokemon[mon[1]] then
        rows[#rows + 1] = { "give_pokemon", mon[1], mon[2], true }
      end
    end
    local ok, why = mod.world:queueScript(rows)
    if not ok then
      say(game, "Bag filled.\nParty: " .. tostring(why))
    end
  end

  local function actCableSfx(game)
    local play = sound(game, "SFX_GEN151_CABLE_SNAP")
    if not play then
      say(game, "No SFX_GEN151_CABLE\n_SNAP registered.\fIs the CABLE SOUND\noption on?")
      return
    end
    play()
  end

  -- The exact box the cable prints, without spending one: this is the row
  -- that answers "does ZzZzap render" in about four seconds.
  local function actBreakBox(game)
    local opts = mod.ui.TextBox.soundOpts(game, "SFX_GEN151_CABLE_SNAP")
    game.stack:push(mod.ui.TextBox.new(game,
      ". . .\fZzZzap!\fThe LINK CABLE\nbroke!", nil, opts))
  end

  local function actHum(game)
    local play = sound(game, "Trade_Machine")
    if play then play() end
  end

  local function actSpawnHere(game, list)
    local here = mod.world and mod.world:current()
    local mapId = here and here.mapId
    local rows = {}
    for _, kind in ipairs({ "grass", "water", "rod" }) do
      for _, row in ipairs(byMap[(mapId or "") .. "|" .. kind] or {}) do
        rows[#rows + 1] = row
      end
    end
    if #rows == 0 then
      say(game, "GEN151 adds nothing\nto " .. tostring(mapId) .. ".\fTry GO TO...")
      return
    end
    local items = {}
    for _, row in ipairs(rows) do
      local def = game.data.pokemon[row.species]
      items[#items + 1] = {
        label = (def and def.name) or row.species,
        right = "L" .. tostring((row.levels or {})[1] or "?"),
        row = row,
      }
    end
    game.stack:push(mod.ui.ListMenu.new(game, "SPAWN HERE", items, {
      onChoose = function(item, inner)
        inner:close()
        list:close()
        if not toOverworld(game) then return end
        local ok, why = mod.world:startWildBattle(
          item.row.species, (item.row.levels or {})[1] or 5)
        if not ok then say(game, tostring(why)) end
      end,
    }))
  end

  local function actGoTo(game, list)
    local items = {}
    for _, mapId in ipairs(mapOrder) do
      items[#items + 1] = { label = mapId:gsub("_", " "), map = mapId }
    end
    game.stack:push(mod.ui.ListMenu.new(game, "GO TO", items, {
      onChoose = function(item, inner)
        inner:close()
        list:close()
        if not toOverworld(game) then return end
        local ok, why = mod.world:warpTo(item.map, 5, 5, "down")
        if not ok then say(game, tostring(why)) end
      end,
    }))
  end

  local function mewOn()
    return mod.world and mod.world:getFlag(MEW_FOUND) == true
  end

  local function actMew(game, list, item)
    local turnOn = not mewOn()
    for _, flag in ipairs(MEW_FLAGS) do
      mod.world:setFlag(flag, turnOn or nil)
    end
    mod.world:setFlag(MEW_FOUND, turnOn or nil)
    -- ask Gen151 to reconcile the encounter table with the flag, which is
    -- what the dex AREA screen reads
    if type(E.syncGated) == "function" then E.syncGated() end
    item.label = turnOn and "MEW: FOUND" or "MEW: HIDDEN"
  end

  local function actDexFill(game)
    local dex = game.save.pokedex
    if not dex then
      say(game, "This save has no\nPOKeDEX yet.")
      return
    end
    local n = 0
    for id, def in pairs(game.data.pokemon) do
      if def.dex and not dex.seen[id] then
        dex.seen[id] = true
        n = n + 1
      end
    end
    say(game, ("Marked %d species\nas SEEN."):format(n)
      .. "\fAREA and the HINT\nrow work on SEEN,\nnot OWNED.")
  end

  local function actChecklist(game)
    say(game, table.concat(CHECKLIST, "\f"))
  end

  -- ---------------------------------------------------------------- the bench

  local SCREEN = "Gen151DebugBench"

  mod.content.screens:register(SCREEN, {
    new = function(game)
      local items = {
        { label = "CHECKLIST", act = function(_, _) actChecklist(game) end },
        { label = "KIT", act = actKit },
        { label = force.on and "SPAWNS: ON" or "SPAWNS: OFF",
          act = function(_, list, item)
            force.on = not force.on
            item.label = force.on and "SPAWNS: ON" or "SPAWNS: OFF"
          end },
        { label = "SPAWN HERE", act = actSpawnHere },
        { label = "GO TO", act = actGoTo },
        { label = "CABLE SFX", act = function(_, _) actCableSfx(game) end },
        { label = "CABLE HUM", act = function(_, _) actHum(game) end },
        { label = "BREAK BOX", act = function(_, list)
            list:close()
            actBreakBox(game)
          end },
        { label = mewOn() and "MEW: FOUND" or "MEW: HIDDEN", act = actMew },
        { label = "DEX FILL", act = function(_, _) actDexFill(game) end },
      }
      return mod.ui.ListMenu.new(game, "GEN151 BENCH", items, {
        footer = ("%d rows on %d maps"):format(
          #(E.rows or {}) + #(E.fishing or {}), #mapOrder),
        onChoose = function(item, list)
          if item.act then item.act(game, list, item) end
        end,
      })
    end,
  })

  -- Reachable from OPTIONS, the way the engine's own example tool mod is:
  -- no developer build, no console, and next(), so every other mod's rows
  -- survive this one.
  mod.hooks:wrap("ui.options.rows", function(nextLink, game, rows)
    local out = nextLink(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = {
      id = "gen151_debug",
      label = "GEN151 BENCH",
      value = function() return force.on and "FORCED" or "OPEN" end,
      activate = function(g) mod.ui.push(g, SCREEN) end,
    }
    return out
  end)

  mod.log:info("bench installed: %d rows on %d maps, OPTIONS -> GEN151 BENCH",
    #(E.rows or {}) + #(E.fishing or {}), #mapOrder)
end
