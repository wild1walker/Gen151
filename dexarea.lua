-- Where a Pokemon is, on the screen the game already has for it.
--
-- The first two releases put this in a FIELD NOTES key item with a screen of
-- its own, and a HINT row spliced into the dex side menu by a companion mod.
-- Both were wrong in the same way: a player looking for a Pokemon opens the
-- POKeDEX and presses AREA.  That is the surface.  A second item and a second
-- menu are two more things to find before the answer turns up, and the answer
-- was already one press away on a screen the cartridge shipped with.
--
-- So this does two things and nothing else:
--
--   * AREA opens on an UNDISCOVERED entry.  Vanilla refuses -- PokedexMenu's
--     onChoose returns early unless the entry is seen or owned -- which is
--     exactly backwards for a mod whose whole job is helping you find the
--     ones you have never met.
--   * The AREA map gets a line under it saying how to get there.  The
--     blinking nests say WHERE; they cannot say "in the grass, around level
--     ten, and rare", and that is the half a player actually needs.
--
-- Both need the engine's own screens, so this is what buys the mod its
-- engine_internals permission.  Neither replaces a screen: PokedexMenu.new
-- and TownMap.new are wrapped and their originals called, so a dex
-- replacement mod that calls through keeps working, and one that does not
-- simply does not get the extra AREA -- it never gets a broken one.

local M = {}

-- The bar under the map is 20 columns wide.  19 leaves the same one-column
-- margin the nest header above it uses.
local CAPTION_COLS = 19
local CAPTION_Y = 128

function M.install(mod, ctx)
  local Hints = ctx.hints
  local Font = mod.ui.Font

  -- species -> the rows that are live right now.  Recomputed per open rather
  -- than cached, because MEW's row is behind a flag and the answer changes
  -- when the flag does.  A gated row that is still locked must not be
  -- captioned: the whole point of the gate is that the dex cannot spoil it,
  -- and a caption would spoil it more precisely than a nest ever could.
  local function rowsFor(species)
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

  -- ------------------------------------------------------ the caption strip

  local function drawCaption(lines)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, CAPTION_Y, 160, 16)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(lines[1] or "", 8, CAPTION_Y)
    if lines[2] then Font.draw(lines[2], 8, CAPTION_Y + 8) end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local TownMap = require("src.ui.TownMap")
  local baseTownMap = TownMap.new
  TownMap.new = function(game, opts)
    local screen = baseTownMap(game, opts)
    local species = opts and opts.nestSpecies
    if not (species and type(screen) == "table") then return screen end
    local lines = Hints.caption(rowsFor(species), CAPTION_COLS)
    if not lines then return screen end
    -- An instance field shadows the metatable method, so the engine's own
    -- draw runs untouched and the strip goes on top of whatever it painted.
    local baseDraw = screen.draw or TownMap.draw
    screen.draw = function(self)
      baseDraw(self)
      drawCaption(lines)
    end
    return screen
  end

  -- ------------------------------------------- AREA on an undiscovered entry

  local PokedexMenu = require("src.ui.PokedexMenu")
  local Menu = mod.ui.Menu
  local basePokedex = PokedexMenu.new
  PokedexMenu.new = function(game, opts)
    local list = basePokedex(game, opts)
    if type(list) ~= "table" or type(list.items) ~= "table" then return list end

    -- PokedexMenu builds one item per dex number that has a species, in
    -- number order, and gives an undiscovered one no `value` to identify it
    -- by.  Rebuilding that order here is what turns a row position back into
    -- a species -- the same walk, over the same table, in the same order.
    local byDex = {}
    for id, def in pairs(game.data.pokemon or {}) do
      if def.dex then byDex[def.dex] = id end
    end
    local order = {}
    for n = 1, (game.data.constants or {}).dexSize or 151 do
      if byDex[n] then order[#order + 1] = byDex[n] end
    end

    local baseChoose = list.onChoose
    list.onChoose = function(item, dexList)
      if item.value then
        if baseChoose then return baseChoose(item, dexList) end
        return
      end
      local species
      for index, other in ipairs(dexList.items or {}) do
        if other == item then
          species = order[index]
          break
        end
      end
      if not species then return end
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
    return list
  end

  mod.log:info("AREA now opens on undiscovered entries, with a hint under "
    .. "the map")
end

return M
