-- FIELD NOTES: a key item that says where to look (SPEC 6b).
--
-- Why a bag item and not a row in the Pokedex:
--
--   * it touches no engine UI file, so it CANNOT conflict with the dex mod
--   * one data source drives the spawns and the hints, so they can never
--     drift apart -- every line printed here is composed from the same
--     resolved placement rows the roll layer is using
--   * it can express method, floor, level band and rarity, which is exactly
--     what the dex AREA screen cannot: AREA says "Seafoam Islands", not
--     "B4F, with a SUPER ROD"
--   * the Super Rod placements are invisible to AREA entirely, so without
--     this they would have no hint coverage at all
--
-- The notebook lists what the player has NOT caught yet, which keeps it short
-- and makes it read as a to-do list rather than a spoiler dump.  SPOILERS.md
-- is where the whole table lives, for people who want it.

local M = {}

local ITEM = "FIELD_NOTES"
local NAME = "FIELD NOTES"
local SCREEN = "Gen151FieldNotes"

-- Bag.add's rule for a key item, without requiring the module: key items are
-- unique, so this is an insert-if-absent.
local function give(save, id)
  local inventory = save and save.inventory
  if not inventory or inventory[id] then return false end
  save.bagOrder = save.bagOrder or {}
  save.bagOrder[#save.bagOrder + 1] = id
  inventory[id] = 1
  return true
end

local function owned(save, species)
  local dex = save and save.pokedex
  return dex and dex.owned and dex.owned[species] == true
end

function M.install(mod, ctx)
  local Hints = ctx.hints

  mod.content.items:register(ITEM, {
    id = ITEM,
    name = NAME,
    price = 0,
    -- the KEY_ITEM pocket: not sellable, not tossable, not used on a mon
    pocket = "KEY_ITEM",
    tossable = false,
    needsTarget = false,
  })

  -- Every row Gen151 actually applied on this install, grouped by species,
  -- with the Super Rod rows folded in so they are covered too.
  local bySpecies = {}
  local order = {}
  local function record(row, method)
    local list = bySpecies[row.species]
    if not list then
      list = {}
      bySpecies[row.species] = list
      order[#order + 1] = row.species
    end
    list[#list + 1] = {
      map = row.map, method = method or row.method, rod = row.rod,
      levels = row.levels, tier = row.tier, gate = row.gate,
    }
  end
  for _, row in ipairs(ctx.rows) do record(row) end
  for _, row in ipairs(ctx.fishing) do record(row, "super_rod") end

  -- dex order, so the notebook reads like the notebook of someone filling in
  -- a dex rather than like a hash table
  local function dexNumber(game, species)
    local def = game.data.pokemon[species]
    return (def and def.dex) or 9999
  end

  mod.content.screens:register(SCREEN, {
    new = function(game)
      local rows = {}
      for _, species in ipairs(order) do
        if not owned(game.save, species) then
          rows[#rows + 1] = species
        end
      end
      table.sort(rows, function(a, b)
        return dexNumber(game, a) < dexNumber(game, b)
      end)

      local items = {}
      for _, species in ipairs(rows) do
        local def = game.data.pokemon[species]
        items[#items + 1] = {
          label = (def and def.name) or species,
          value = species,
        }
      end

      -- An empty notebook is a sentence, not a blank box: it is the state a
      -- finished playthrough leaves behind, and it should read like one.
      if #items == 0 then
        items[1] = { label = "ALL FOUND!" }
      end

      return mod.ui.ListMenu.new(game, NAME, items, {
        onChoose = function(item)
          if not item.value then return end
          local def = game.data.pokemon[item.value]
          local name = (def and def.name) or item.value
          game.stack:push(mod.ui.TextBox.new(game,
            Hints.forSpecies(bySpecies[item.value] or {}, name)))
        end,
      })
    end,
  })

  mod.hooks:wrap("item.use", function(nextLink, game, battle, id, target,
                                      list, moveIndex, picker)
    if id ~= ITEM then
      return nextLink(game, battle, id, target, list, moveIndex, picker)
    end
    if battle then
      -- notes are for the field; in a battle the engine's own refusal is the
      -- right answer and it already knows how to word it
      return nextLink(game, battle, id, target, list, moveIndex, picker)
    end
    mod.ui.push(game, SCREEN)
  end)

  -- The notebook is something a trainer carries, so it is in the bag from the
  -- start -- and it is handed to an existing save on load too, so installing
  -- Gen151 mid-playthrough does not leave the hint system unreachable.
  local function grant()
    local game = mod.game
    if game and game.save and give(game.save, ITEM) then
      mod.log:info("FIELD NOTES added to the bag")
    end
  end
  mod.events:on("save.created", grant)
  mod.events:on("save.loaded", grant)
  mod.events:on("game.ready", grant)
end

return M
