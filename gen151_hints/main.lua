-- Gen151's HINT row in the Pokedex side menu (SPEC 6c).
--
-- Why this is a separate mod: it is the one Gen151 feature that has to reach
-- an engine internal, and a mod that requests `engine_internals` shows the
-- player a "PATCHES ENGINE CODE" badge in the manager.  The encounter mod
-- earns no such badge and should not carry one, so the row lives here and
-- Gen151 ships permission-free.
--
-- Why the row is safe next to a dex mod, and why it defaults on:
--
-- Gen1Dex registers over the PokedexMenu and DexEntryMenu screen ids, but its
-- list.lua builds its list by calling the VANILLA constructor and re-dressing
-- the result -- its own comment is that it "has an opinion about how the list
-- looks and which entries are in it, and none at all about what pressing A on
-- one does".  The DATA / CRY / AREA / QUIT side menu, the cursor memory and
-- the QUIT path are untouched vanilla.  So a row spliced into that side menu
-- appears inside Gen1Dex's re-dressed list for free.
--
-- The one hard rule: do NOT register a screen over "PokedexMenu".  Gen1Dex
-- claims that id at priority 1100, R.screens is `record` semantics, and two
-- records on one id collide -- whichever loses takes its whole screen with
-- it.  This wraps the vanilla module's `new` instead, which is the exact
-- function Gen1Dex calls at construction time, so the two compose rather than
-- compete.  The wrap is installed at load time and Gen1Dex resolves at
-- construction time, so ordering is not load-bearing -- but the manifest
-- declares Gen1Dex as an optional dependency and sits below 1100 anyway, so
-- the intent is legible.
--
-- ui.list_menu cannot do this: src/ui/ListMenu.lua passes the hook only
-- `wrap`, `pageJump`, `keyRepeat`, `repeatDelay` and `repeatRate`.  It cannot
-- add rows, and designing around it would not work.

return function(mod)
  mod.options:define{
    { key = "enabled", type = "toggle", label = "HINT ROW", default = true },
  }
  if mod.options:get("enabled") ~= true then return end

  -- Gen151 is an OPTIONAL dependency, not a hard one, for a packaging
  -- reason worth writing down: modkit's `pack` validates a mod by mounting
  -- it alone through the headless loader, so a hard dependency is
  -- unreachable there and no release archive can ever be built.  Optional
  -- still guarantees the load order -- Gen151 runs first whenever it is
  -- present -- and this mod does nothing at all without it, which is what
  -- the branch below says out loud rather than failing.
  local gen151 = mod.find("gen151")
  if not gen151 or not gen151.exports then
    mod.log:warn("Gen151 is not installed or did not load, and this mod is "
      .. "only its Pokedex row -- install Gen151 alongside it, or disable "
      .. "this mod")
    return
  end
  local exports = gen151.exports
  if exports.enabled ~= true then
    mod.log:info("Gen151 is installed but switched off in its own options; "
      .. "the HINT row is not installed")
    return
  end
  if exports.hintSurface ~= "dex" then
    mod.log:info("Gen151's HINTS option is set to %q, not \"dex\"; the HINT "
      .. "row is not installed", tostring(exports.hintSurface))
    return
  end

  local ok, PokedexMenu = pcall(require, "src.ui.PokedexMenu")
  local okMenu, Menu = pcall(require, "src.ui.Menu")
  local okStrings, Strings = pcall(require, "src.core.Strings")
  if not (ok and okMenu and okStrings) or type(PokedexMenu) ~= "table"
      or type(PokedexMenu.new) ~= "function" or type(Menu.new) ~= "function" then
    mod.log:warn("the Pokedex side menu is not where this mod expects it; "
      .. "the HINT row is skipped and the dex is untouched")
    return
  end

  local Hints = exports.hints
  if not Hints then
    mod.log:warn("Gen151 published no hint vocabulary; the HINT row is "
      .. "skipped")
    return
  end

  -- species -> every row Gen151 actually applied for it, Super Rod included
  local bySpecies = {}
  local function record(row, method)
    local list = bySpecies[row.species]
    if not list then
      list = {}
      bySpecies[row.species] = list
    end
    list[#list + 1] = {
      map = row.map, method = method or row.method, rod = row.rod,
      levels = row.levels, tier = row.tier, gate = row.gate,
    }
  end
  for _, row in ipairs(exports.rows or {}) do record(row) end
  for _, row in ipairs(exports.fishing or {}) do record(row, "super_rod") end

  local AREA = Strings("AREA")
  local HINT = Strings("HINT")

  local function hintFor(game, species)
    local def = game.data.pokemon[species]
    local name = (def and def.name) or species
    local rows = bySpecies[species]
    if not rows or #rows == 0 then
      -- Everything the vanilla game already provides falls here, which is
      -- most of the dex.  A sentence, not a blank box.
      return name .. " turns up\nwhere it always\ndid."
    end
    return Hints.forSpecies(rows, name)
  end

  -- The side menu's `entries` list is a local inside PokedexMenu.new's
  -- onChoose closure, so there is no seam that hands it over.  The narrowest
  -- reach that gets it: for the duration of ONE onChoose call, intercept
  -- Menu.new, splice the row into the descriptor list ModUI's helpers are
  -- built for, and hand the list straight back to the real constructor.
  -- Nothing stays patched between calls.
  local realMenuNew = Menu.new

  local function withHintRow(game, species, body)
    Menu.new = function(g, items, opts)
      Menu.new = realMenuNew
      -- Anchored on the AREA label rather than an index: Yellow's side menu
      -- carries a PRNT row, which shifts every index after it.  A missing
      -- anchor appends, which keeps the row reachable either way.
      mod.ui.insertAfter(items, AREA, {
        label = HINT,
        onSelect = function()
          g.stack:push(mod.ui.TextBox.new(g, hintFor(g, species)))
        end,
      })
      -- PokedexMenu sizes the box from the row count it knew about
      local sized = {}
      for key, value in pairs(opts or {}) do sized[key] = value end
      if type(sized.th) == "number" then sized.th = sized.th + 2 end
      return realMenuNew(g, items, sized)
    end
    local ran, err = pcall(body)
    Menu.new = realMenuNew
    if not ran then error(err, 0) end
  end

  local vanillaNew = PokedexMenu.new
  PokedexMenu.new = function(game, opts)
    local list = vanillaNew(game, opts)
    local vanillaChoose = type(list) == "table" and list.onChoose
    if type(vanillaChoose) ~= "function" then return list end
    list.onChoose = function(item, dexList)
      if not item or not item.value then
        return vanillaChoose(item, dexList)
      end
      withHintRow(game, item.value, function()
        vanillaChoose(item, dexList)
      end)
    end
    return list
  end

  mod.log:info("HINT row installed next to AREA")
end
