-- Rarity tiers (SPEC 5).
--
-- One table, used everywhere, so retuning is a single edit and the mod option
-- can scale the whole ladder without touching a placement.  Weights are parts
-- per Roll.RARITY_SCALE (10000) of the encounters on that map -- the share of
-- rolls that produce an encounter at all, not of steps taken.  Encounter RATE
-- is untouched, so these numbers never change how often the player is jumped,
-- only what jumps them.

local Rarity = {}

Rarity.TIERS = {
  -- version exclusives, in their natural habitat.  A few percent: the species
  -- reads as a resident of the route, not as a prize.
  UNCOMMON = 400,   -- 4%
  -- one-time gift mons and NPC-trade mons.  About one in a hundred: findable
  -- in an afternoon, never on the way past.
  RARE = 100,       -- 1%
  -- starters and fossils.  Well under one percent, which is roughly the price
  -- the vanilla game charged for choosing the other one.
  VERY_RARE = 40,   -- 0.4%
  -- anything the vanilla game treated as unique.
  TROPHY = 10,      -- 0.1%
}

Rarity.ORDER = { "UNCOMMON", "RARE", "VERY_RARE", "TROPHY" }

Rarity.LABELS = {
  UNCOMMON = "uncommon",
  RARE = "rare",
  VERY_RARE = "very rare",
  TROPHY = "almost never",
}

-- The mod option is a percentage multiplier: 100 leaves the table alone, 300
-- triples every tier, 25 quarters it.  Clamped so a scaled tier can never
-- reach or pass 100% of a map's encounters -- a placement that displaced every
-- vanilla species would break prime directive 1 by the back door.
function Rarity.weight(tier, multiplierPercent)
  local base = Rarity.TIERS[tier]
  if not base then return nil end
  local scaled = math.floor(base * (multiplierPercent or 100) / 100 + 0.5)
  if scaled < 0 then return 0 end
  if scaled > 5000 then return 5000 end
  return scaled
end

return Rarity
