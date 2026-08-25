-- Where a Pokemon is, on the screen the game already has for it.
--
-- The first two releases put this in a FIELD NOTES key item with a screen of
-- its own, and a HINT row spliced into the dex side menu by a companion mod.
-- Both were wrong in the same way: a player looking for a Pokemon opens the
-- POKeDEX and presses AREA.  That is the surface.  A second item and a second
-- menu are two more things to find before the answer turns up, and the answer
-- was already one press away on a screen the cartridge shipped with.
--
-- So this does three things and nothing else:
--
--   * AREA opens on an UNDISCOVERED entry.  Vanilla refuses -- PokedexMenu's
--     onChoose returns early unless the entry is seen or owned -- which is
--     exactly backwards for a mod whose whole job is helping you find the
--     ones you have never met.
--   * The AREA map gets a line under it saying how to get there, for ALL 151
--     rather than only the ones this mod placed.  The blinking nests say
--     WHERE; they cannot say "in the grass, around level ten, and rare", and
--     that is the half a player actually needs.  A vanilla Pokemon's line is
--     read straight out of the live encounter tables, so it is right by
--     construction and costs no placement data at all.
--   * A press takes the line away, because the strip covers two tile rows of
--     Kanto and one of those rows has nests in it.  The first A dismisses the
--     hint; the second closes the screen, which is what A always did.
--
-- Both screens need reaching for directly, so this is what buys the mod its
-- engine_internals permission.  Neither is replaced: PokedexMenu.new and
-- TownMap.new are wrapped and their originals called, so a dex replacement
-- that calls through keeps working, and one that does not simply does not get
-- the extra AREA -- it never gets a broken one.

local M = {}

-- The hint goes in the game's OWN dialogue box, at the geometry every other
-- box in the game uses -- src/render/TextBox.lua's BOX_TX/TY/TW/TH, its
-- textX, its line1Y and line2Y, its blinking prompt arrow, and Font.drawBox
-- for the frame tiles themselves.  The first version painted a bare white
-- strip with two lines in it, which read as a debug overlay rather than as
-- the game talking to the player, and looked it.
--
-- Nothing here is a copy of those numbers by eye: they are the same
-- arithmetic on the same constants, so a box drawn here lands on the same
-- pixels as a box drawn by the engine.
local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 0, 12, 20, 6
local TEXT_X = (BOX_TX + 1) * 8
local LINE1_Y = (BOX_TY + 2) * 8
local LINE2_Y = (BOX_TY + 4) * 8
local ARROW_X = (BOX_TX + BOX_TW - 2) * 8
local ARROW_Y = (BOX_TY + BOX_TH - 1) * 8 - 4

-- The interior of that box is 18 columns, the same budget TextBox.paginate
-- wraps to.
local CAPTION_COLS = 18

-- The header strip the engine paints across the top of the AREA screen is
-- 160px wide with its text inset 8px, so 19 columns of room -- and vanilla
-- writes into it without measuring.  "CHARIZARD AREA UNKNOWN" is 22, so it
-- ran off the right edge of the screen mid-word.
local HEADER_COLS = 19
local HEADER_Y = 0

-- Gen 1's ten cumulative slot thresholds out of 256 (wild_encounters.asm).
-- The dataset carries its own under constants.encounterBuckets; this is the
-- fallback for a stub that does not.
local BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

-- Wrapping a module function stacks, and this mod's entry chunk runs again on
-- every hot reload and every profile switch -- so the second load would paint
-- a second strip over the first and open a second side menu behind it.  The
-- pristine constructor is parked on the module under a key of this mod's own
-- so a re-install always wraps the original rather than the last wrap.
local PRISTINE = "__gen151_pristine_new"

local function wrapNew(module, make)
  local original = rawget(module, PRISTINE) or module.new
  rawset(module, PRISTINE, original)
  module.new = make(original)
  return original
end

-- A vanilla species' share of one map's encounters -> the same vocabulary the
-- placement tiers use, so a wild Rattata and a placed Bulbasaur describe
-- themselves in one language.
local function tierFor(share)
  if share >= 51 then return "COMMON" end       -- a whole top bucket, 20%
  if share >= 25 then return "UNCOMMON" end     -- ~10%
  if share >= 10 then return "RARE" end
  return "VERY RARE"
end

function M.install(mod, ctx)
  local Hints = ctx.hints
  local Font = mod.ui.Font
  local Theme = mod.ui.Theme

  -- species -> the placement rows that are live right now.  Recomputed per
  -- open rather than cached, because MEW's row is behind a flag and the
  -- answer changes when the flag does.  A gated row that is still locked
  -- must not be captioned: the whole point of the gate is that the dex
  -- cannot spoil it, and a caption would spoil it more precisely than a nest
  -- ever could.
  local function placedRows(species)
    local out = {}
    for _, row in ipairs(ctx.rows or {}) do
      if row.species == species
         and (not row.gated or (ctx.unlocked and ctx.unlocked())) then
        out[#out + 1] = row
      end
    end
    for _, row in ipairs(ctx.fishing or {}) do
      if row.species == species then out[#out + 1] = row end
    end
    return out
  end

  -- Anything already in the live encounter tables, which is every vanilla
  -- Pokemon and every one this mod added a slot for.  The map reported is
  -- the one where the species has the biggest share of the encounters, and
  -- the level band is that map's -- a band pooled across every map would
  -- read "Lv6-40" for Zubat and tell nobody anything.
  local function fromEncounters(game, species)
    local data = game.data
    local buckets = (data.constants or {}).encounterBuckets or BUCKETS
    local best, kind, lo, hi = 0, nil, nil, nil
    for _, record in pairs(data.encounters or {}) do
      for group, entry in pairs(record) do
        if group == "grass" or group == "water" then
          local share, low, high, previous = 0, nil, nil, 0
          for index, slot in ipairs(entry.slots or {}) do
            local edge = buckets[index]
            local width = edge and (edge - previous) or 0
            if edge then previous = edge end
            if slot.species == species then
              share = share + width
              low = math.min(low or slot.level, slot.level)
              high = math.max(high or slot.level, slot.level)
            end
          end
          if low and share >= best then
            best, kind, lo, hi = share, group, low, high
          end
        end
      end
    end
    if not kind then return nil end
    local how = Hints.SHORT_METHODS[kind] or kind:upper()
    local band = lo == hi and ("Lv%d"):format(lo) or ("Lv%d-%d"):format(lo, hi)
    -- share 0 means every slot it sits in is past the tenth bucket, i.e. it
    -- is one of this mod's appended slots and its real odds are the rarity
    -- roll rather than a bucket.  placedRows answered those already; this is
    -- the leftover case (a gated row, or another mod's append), and guessing
    -- COMMON for it would be a lie.
    if best <= 0 then return { how .. "  " .. band } end
    return { how .. "  " .. band, tierFor(best) }
  end

  -- Not a wild Pokemon on this cartridge at all.  The dex still owes the
  -- player an answer, and the evolution table has one: nothing here is a
  -- guess, it is the same table the game evolves from.
  local function fromEvolution(game, species)
    for id, def in pairs(game.data.pokemon or {}) do
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.species == species then
          local from = (game.data.pokemon[id] or {}).name or id
          if evo.method == "TRADE" then
            return { "LINK CABLE", "ON " .. from }
          end
          if evo.method == "ITEM" and evo.item then
            local item = (game.data.items or {})[evo.item] or {}
            return { item.name or evo.item, "ON " .. from }
          end
          if evo.level then
            return { "EVOLVE " .. from, ("AT LV%d"):format(evo.level) }
          end
          return { "EVOLVE " .. from }
        end
      end
    end
    return nil
  end

  -- One clamp for every source, at the box's own budget, measured in drawn
  -- pixels.  Each builder could mind its own width, and then a new builder
  -- would forget to -- the box knows how wide it is, so the box decides.
  local function clamp(lines)
    if not lines then return nil end
    for index, line in ipairs(lines) do
      local spans = Font.split(line)
      local room = Font.spansFitting(spans, CAPTION_COLS * 8)
      if room < #spans then
        lines[index] = line:sub(1, spans[math.max(room, 1)].to)
      end
    end
    return lines
  end

  local function captionFor(game, species)
    local ours = placedRows(species)
    if #ours > 0 then return clamp(Hints.caption(ours, CAPTION_COLS)) end
    local wild = fromEncounters(game, species)
    if wild then return clamp(wild) end
    return clamp(fromEvolution(game, species))
  end

  -- ------------------------------------------------------ the caption strip

  -- Whether a string fits a column budget, measured the way the text box
  -- measures it: in the pixels the glyphs actually draw, not in bytes.  A
  -- variable-advance font (a TTF skin) makes those two different numbers, and
  -- the header that overflowed was counted in bytes.
  local function fits(text, cols)
    local spans = Font.split(text)
    return Font.spansFitting(spans, cols * 8) >= #spans
  end

  local function drawBox(lines, arrow)
    Font.drawBox(BOX_TX, BOX_TY, BOX_TW, BOX_TH)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(lines[1] or "", TEXT_X, LINE1_Y)
    if lines[2] then Font.draw(lines[2], TEXT_X, LINE2_Y) end
    -- the same blinking prompt the engine prints at the end of a page, in
    -- the same corner of the same box: "there is a press waiting here" said
    -- the way the rest of the game says it
    if arrow then Font.drawCode(Theme.moreArrow or 0xEE, ARROW_X, ARROW_Y) end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- The header, repainted ONLY when the engine's own would not have fitted.
  -- A name short enough to leave vanilla's line alone leaves it alone.
  local function headerFor(screen, species)
    local def = screen.game.data.pokemon[species]
    local name = (def and def.name) or species
    local full = #screen.nests > 0 and (name .. "'s NEST")
      or (name .. " AREA UNKNOWN")
    if fits(full, HEADER_COLS) then return nil end
    -- shortest thing that still says both halves, then the name alone
    for _, try in ipairs({ name .. " UNKNOWN", name }) do
      if fits(try, HEADER_COLS) then return try end
    end
    return name
  end

  local function drawHeader(text)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, HEADER_Y, 160, 8)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(text, 8, HEADER_Y)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local TownMap = require("src.ui.TownMap")
  wrapNew(TownMap, function(baseTownMap)
  return function(game, opts)
    local screen = baseTownMap(game, opts)
    local species = opts and opts.nestSpecies
    if not (species and type(screen) == "table") then return screen end
    local lines = captionFor(game, species)
    if not lines or not lines[1] then return screen end

    -- Instance fields shadow the metatable methods, so the engine's own draw
    -- and update run untouched underneath.
    local showing = true
    local baseDraw = screen.draw or TownMap.draw
    local baseUpdate = screen.update or TownMap.update

    local header = headerFor(screen, species)

    screen.draw = function(self)
      baseDraw(self)
      if header then drawHeader(header) end
      if showing then
        -- blinking in time with the map's own nests rather than to a clock
        -- of its own: one screen, one pulse
        drawBox(lines, (self.blink or 0) < 25)
      end
    end

    screen.update = function(self, dt)
      -- A on the AREA screen closes it (TownMap:update).  While the hint is
      -- up, A means "I have read it" instead -- so the strip comes off the
      -- two tile rows of Kanto it was covering, nests included, and the NEXT
      -- A closes the screen the way it always did.  B is untouched: it still
      -- leaves immediately, for anyone who does not want the hint at all.
      if showing and self.game.input:wasPressed("a") then
        showing = false
        return
      end
      return baseUpdate(self, dt)
    end
    return screen
  end
  end)

  -- ------------------------------------------- AREA on an undiscovered entry

  local PokedexMenu = require("src.ui.PokedexMenu")
  local Menu = mod.ui.Menu
  local warned = false

  wrapNew(PokedexMenu, function(basePokedex)
  return function(game, opts)
    local list = basePokedex(game, opts)
    if type(list) ~= "table" or type(list.items) ~= "table" then return list end

    -- Vanilla builds one item per dex number that has a species, in number
    -- order, and gives an undiscovered one no `value` to identify it by.  So
    -- stamp the species on while the order is still known to be vanilla's.
    --
    -- Stamping rather than remembering the order is what makes this survive a
    -- dex mod: Gen1Dex calls this constructor and then REPLACES list.items
    -- wholesale with rows of its own, which would strand any index-based
    -- lookup -- and did.  Its rows carry `species` on every entry, seen or
    -- not, so between the two there is always a name to read.
    local byDex = {}
    for id, def in pairs(game.data.pokemon or {}) do
      if def.dex then byDex[def.dex] = id end
    end
    local at = 0
    for n = 1, (game.data.constants or {}).dexSize or 151 do
      if byDex[n] then
        at = at + 1
        local item = list.items[at]
        if type(item) == "table" and item.species == nil then
          item.species = byDex[n]
        end
      end
    end

    local baseChoose = list.onChoose
    local choose
    choose = function(item, dexList)
      if item.value then
        if baseChoose then return baseChoose(item, dexList) end
        return
      end
      local species = item.species
      if type(species) ~= "string" then
        -- A dex mod replaced the rows with something that names no species.
        -- Nothing sensible is left to open, so say so once rather than
        -- returning silently -- a menu that does nothing when pressed is the
        -- hardest kind of bug to report.
        if not warned then
          warned = true
          mod.log:warn("the dex list's rows carry no species, so AREA cannot "
            .. "be opened on an undiscovered entry; another dex mod has "
            .. "replaced them with rows this cannot read")
        end
        return
      end
      -- AREA and QUIT only.  DATA on a Pokemon you have never met would hand
      -- over the height, the weight and the dex paragraph, which is a good
      -- deal more than "where do I look" -- and nobody asked for it.
      local entries = {
        { label = "AREA", onSelect = function()
            mod.ui.push(game, "TownMap", { nestSpecies = species })
          end },
        { label = "QUIT", onSelect = function()
            dexList:close()
            if opts and opts.onCancel then opts.onCancel() end
          end },
      }
      game.stack:push(Menu.new(game, entries,
        { tx = 12, ty = 8, tw = 8, th = #entries * 2 + 2 }))
    end

    -- Marked so the bench can say, in one press, which link of this chain is
    -- missing on an install that is not behaving.  A dex mod is free to
    -- replace the rows (Gen1Dex does) or the handler (none seen yet); the
    -- difference decides the fix, and guessing between them from a bug
    -- report is what cost the last release.
    list.onChoose = choose
    list.__gen151Wrapped = true
    list.__gen151Choose = choose
    return list
  end
  end)

  mod.log:info("AREA now opens on undiscovered entries, with a hint under "
    .. "the map for every species the data can answer for")

  -- What the bench prints.  Every link that has to hold for a press on an
  -- undiscovered entry to open AREA, reported from the list the game would
  -- actually build -- through the screens registry, so a dex mod's own
  -- factory is what answers.
  return function(game)
    local Screens = require("src.ui.Screens")
    local factory = Screens.get(game, "PokedexMenu")
    local ok, list = pcall(factory.new, game, {})
    if not ok or type(list) ~= "table" then
      return "The dex list did\nnot build.\f" .. tostring(list)
    end
    local owner = factory.__modOwned and "A MOD" or "VANILLA"
    if not list.__gen151Wrapped then
      return "DEX: " .. owner .. "\fIt does not call\nthe builtin,\fso AREA cannot\nbe added."
    end
    if list.onChoose ~= list.__gen151Choose then
      return "DEX: " .. owner .. "\fIt replaced the A\nhandler,\fso AREA cannot\nbe added."
    end
    local unknown, named = nil, 0
    for _, item in ipairs(list.items or {}) do
      if not item.value then
        unknown = unknown or item
        if type(item.species) == "string" then named = named + 1 end
      end
    end
    if not unknown then
      return "DEX: " .. owner .. "\fEvery entry is\nalready seen,\fso there is nothing\nto test."
    end
    if type(unknown.species) ~= "string" then
      return "DEX: " .. owner .. "\fIts rows do not\nname a species,\fso AREA cannot\nbe added."
    end
    return "DEX: " .. owner .. "\fWrap on, rows\nnamed.\f" .. tostring(named)
      .. " unseen rows\nwill open AREA."
  end
end

return M
