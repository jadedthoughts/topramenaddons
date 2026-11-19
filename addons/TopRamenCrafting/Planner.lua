-- Top Ramen Crafting: planner math (no UI). Works on plain tables so it can be tested outside the game.
--
-- item(id) -> { name, quality, sell, vbuy, ah, age, bags, total, bind } or nil
-- recipe   -> { name, diff, out, min, max, reagents = { {id, n}, ... } }
-- settings -> { mode = "vendor"|"best"|"ah", points, maxAge, ownedFree, makeReagents }

local _, ns = ...
ns = ns or {}

local P = {}
P.__index = P
ns.Planner = P

P.CHANCE = { optimal = 1, medium = 0.75, easy = 0.25, trivial = 0 }
P.AH_CUT = 0.05
-- Skill-up plans: no charge for your time; "Best chance for skill-ups" is what keeps plans on guaranteed points.
P.CRAFT_COST = 0
-- Making a reagent yourself costs an extra craft, so with "Make reagents myself" each of those crafts
-- counts as this much of your time (copper): you only make it when the saving is worth the extra crafting.
P.PREP_COST = 100
-- Only make a reagent yourself when that's at least this much cheaper than buying it.
P.MAKE_SAVING = 0.10
local MAX_DEPTH = 3
-- Where a recipe turns yellow, when the game hasn't been seen to change it yet: this many below gray.
P.YELLOW_GAP = 25

-- Skill where a recipe stops being orange (its first yellow skill), and whether that's known or estimated.
-- Needs the recipe's gray level (from the game); returns nil without it.
function P.yellowStart(r)
  local gray = r.gray
  if not gray then return nil end
  if r.yellowMin and r.orangeMax and r.yellowMin == r.orangeMax + 1 then return r.yellowMin, true end
  local y = gray - P.YELLOW_GAP
  if r.orangeMax then y = math.max(y, r.orangeMax + 1) end
  if r.yellowMin then y = math.min(y, r.yellowMin) end
  return math.min(y, gray), false
end

-- Chance one craft gives a point at a given skill. Orange: always. Yellow to gray: falls in a straight line
-- from 100% to 0% (the classic formula). Without a gray level, uses the recipe's current color.
function P.chanceAt(r, skill)
  local y = P.yellowStart(r)
  if not y or not skill then return P.CHANCE[r.diff] or 0 end
  if skill >= r.gray then return 0 end
  if skill < y then return 1 end
  return math.max(0, math.min(1, (r.gray - skill) / (r.gray - y)))
end

local function made(r) return ((r.min or 1) + (r.max or r.min or 1)) / 2 end

-- recipes: the profession being planned. allRecipes: every recipe the character knows (for making reagents).
function P.new(item, recipes, allRecipes, settings)
  local self = setmetatable({ item = item, recipes = recipes, s = settings, makers = {}, memo = {}, items = {} }, P)
  for _, r in ipairs(allRecipes or recipes) do
    if (r.out or 0) > 0 and #r.reagents > 0 then
      self.makers[r.out] = self.makers[r.out] or {}
      table.insert(self.makers[r.out], r)
    end
  end
  return self
end

function P:get(id)
  local v = self.items[id]
  if v == nil then v = self.item(id) or false; self.items[id] = v end
  return v or nil
end

function P:ahPrice(it)
  if not it or not it.ah then return nil end
  if it.age == nil or it.age > self.s.maxAge then return nil end
  return it.ah
end

-- cheapest way to buy one: price, "vendor" | "ah" | "none"
function P:buyPrice(id)
  local it = self:get(id)
  local a, v = self:ahPrice(it), it and it.vbuy
  if v and (not a or v <= a) then return v, "vendor" end
  if a then return a, "ah" end
  return nil, "none"
end

-- What buying `n` more units costs after `already` units have been planned, walking up the auction
-- house price levels (a vendor is used whenever it's cheaper). Without price levels, n x the cheapest price.
-- returns total, short (true when more than the listed amount is needed), tiers { {price, units} ... }
P.GOOD_PRICE = 1.25 -- "good price" = within 25% of the cheapest listing
function P:buyCost(id, already, n)
  if n <= 0 then return 0, false, {} end
  local it = self:get(id)
  local v = it and it.vbuy
  local a = self:ahPrice(it)
  if not a then
    if v then return v * n, false, { { v, n } } end
    return nil
  end
  local lv = it.levels
  if not lv or #lv < 2 then
    local unit = (v and v < a) and v or a
    return unit * n, false, { { unit, n } }
  end
  local cost, skip, need, tiers = 0, already or 0, n, {}
  for i = 1, #lv - 1, 2 do
    local price, q = lv[i], lv[i + 1]
    if v and v <= price then -- the vendor is cheaper from here on
      cost = cost + v * need; tiers[#tiers + 1] = { v, need, vendor = true }
      return cost, false, tiers
    end
    if skip >= q then skip = skip - q
    else
      local take = math.min(q - skip, need)
      skip = 0
      cost, need = cost + take * price, need - take
      tiers[#tiers + 1] = { price, take }
      if need <= 0 then return cost, false, tiers end
    end
  end
  -- more than was listed: price the rest at the last level seen
  local last = lv[#lv - 1]
  cost = cost + last * need
  tiers[#tiers + 1] = { last, need, unlisted = true }
  return cost, true, tiers
end

-- cheapest way to get one: buy it, or craft it from its own reagents. price, where, recipe
function P:unitCost(id, depth)
  local m = self.memo[id]
  if m then return m[1], m[2], m[3] end
  depth = depth or 0
  self.memo[id] = { nil, "none" } -- guards against recipe loops
  local price, where = self:buyPrice(id)
  local via
  if self.s.makeReagents and depth < MAX_DEPTH and self.makers[id] then
    for _, r in ipairs(self.makers[id]) do
      local cost, ok = 0, true
      for _, rg in ipairs(r.reagents) do
        local p = self:unitCost(rg.id, depth + 1)
        if not p then ok = false; break end
        cost = cost + p * rg.n
      end
      if ok then
        cost = (cost + P.PREP_COST) / made(r)
        if not price or cost < price * (1 - P.MAKE_SAVING) then price, where, via = cost, "craft", r end
      end
    end
  end
  self.memo[id] = { price, where, via }
  return price, where, via
end

-- what one craft is worth when sold: value, "vendor" | "ah" | "none"
function P:payout(r)
  local it = self:get(r.out)
  if not it then return 0, "none" end
  local n = made(r)
  local vendor = (it.sell or 0) * n
  local a = self:ahPrice(it)
  local ah = (a and it.bind ~= 1) and a * n * (1 - P.AH_CUT) or nil
  local mode = self.s.mode
  if mode == "vendor" then return vendor, vendor > 0 and "vendor" or "none" end
  if mode == "ah" then if ah then return ah, "ah" end return 0, "none" end
  if ah and ah > vendor then return ah, "ah" end
  return vendor, vendor > 0 and "vendor" or "none"
end

-- full cost of one craft if every reagent is bought (or made): cost, missingIDs
function P:recipeCost(r)
  local cost, missing = 0, {}
  for _, rg in ipairs(r.reagents) do
    local p = self:unitCost(rg.id)
    if p then cost = cost + p * rg.n else missing[#missing + 1] = rg.id end
  end
  return cost, missing
end

local function ownedTable(self)
  local owned = {}
  return setmetatable(owned, { __index = function(t, id)
    local it = self:get(id)
    local v = it and it.total or 0
    rawset(t, id, v)
    return v
  end })
end

-- Skill-up plan: cheapest expected cost per point, one craft at a time.
-- returns { crafts = { {recipe, n} ... }, expected = points }
-- rank: your current skill. Each craft's chance is worked out at the skill you'll have by then.
function P:planSkillUps(points, rank)
  local s = self.s
  local owned = ownedTable(self)
  local counts, order, expected, guard = {}, {}, 0, 0
  local pointsBy = {}
  local bought = {} -- units of each material already planned to buy
  while expected < points - 1e-9 and guard < 3000 do
    guard = guard + 1
    local best, bestScore, bestChance, bestNet
    local skillNow = rank and math.floor(rank + expected + 1e-9) or nil
    -- every recipe we can price, with its chance at the skill you'll have by now
    local cands, topChance = {}, 0
    for _, r in ipairs(self.recipes) do
      local chance = P.chanceAt(r, skillNow)
      if chance > 0 then
        local cost, ok = 0, true
        for _, rg in ipairs(r.reagents) do
          local need = rg.n
          if s.ownedFree then need = need - math.min(need, owned[rg.id]) end
          if need > 0 then
            local p, where = self:unitCost(rg.id)
            if not p then ok = false; break end
            if where == "ah" then
              p = self:buyCost(rg.id, bought[rg.id] or 0, need) -- the next listings up, not just the cheapest
              if not p then ok = false; break end
              cost = cost + p
            else
              cost = cost + p * need
            end
          end
        end
        if ok then
          local net = cost - self:payout(r)
          cands[#cands + 1] = { r = r, chance = chance, net = net,
            -- money lost per craft (a profit counts as zero) plus the time a craft takes, per expected point
            score = (math.max(net, 0) + P.CRAFT_COST) / chance }
          if chance > topChance then topChance = chance end
        end
      end
    end
    -- "Best chance for skill-ups": only the recipes with the highest chance compete, then the cheapest wins
    -- cheapest per point wins; on a tie (e.g. both pay for themselves) the better chance, then the bigger profit
    for _, c in ipairs(cands) do
      if not s.bestChance or c.chance >= topChance - 1e-9 then
        local better = not bestScore or c.score < bestScore - 1e-9
        if not better and math.abs(c.score - bestScore) < 1e-9 then
          better = c.chance > bestChance + 1e-9 or (math.abs(c.chance - bestChance) < 1e-9 and c.net < bestNet)
        end
        if better then best, bestScore, bestChance, bestNet = c.r, c.score, c.chance, c.net end
      end
    end
    if not best then break end
    if not counts[best] then counts[best] = 0; order[#order + 1] = best end
    counts[best] = counts[best] + 1
    pointsBy[best] = (pointsBy[best] or 0) + bestChance
    expected = expected + bestChance
    for _, rg in ipairs(best.reagents) do
      local need = rg.n
      if s.ownedFree then
        local use = math.min(need, owned[rg.id])
        owned[rg.id] = owned[rg.id] - use
        need = need - use
      end
      if need > 0 then bought[rg.id] = (bought[rg.id] or 0) + need end
    end
  end
  local crafts = {}
  for _, r in ipairs(order) do crafts[#crafts + 1] = { recipe = r, n = counts[r], points = pointsBy[r] } end
  return { crafts = crafts, expected = expected }
end

-- Crafts that make money if every material is bought: { {recipe, cost, value, where, net} ... }, best first
-- cost of making k of a recipe, buying every material up the AH price levels (the more you buy, the
-- pricier listings you reach). Reagents you'd craft yourself are counted at their crafting cost.
function P:batchCost(r, k)
  if k <= 0 then return 0 end
  local total = 0
  for _, rg in ipairs(r.reagents) do
    local unit, where = self:unitCost(rg.id)
    if not unit then return nil end
    local c = where ~= "craft" and self:buyCost(rg.id, 0, rg.n * k) or nil
    total = total + (c or unit * rg.n * k)
  end
  return total
end

-- how many you can make before one more stops paying (each extra craft costs at least as much as the last).
-- Searches up to `cap`; returns cap when every one of them still pays.
function P:profitableCount(r, value, cap)
  local function pays(k) -- does the k-th craft still pay for itself?
    local a, b = self:batchCost(r, k), self:batchCost(r, k - 1)
    return a and b and (a - b) <= value
  end
  if not pays(1) then return 0 end
  if pays(cap) then return cap end
  local lo, hi = 1, cap -- pays(lo) true, pays(hi) false
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if pays(mid) then lo = mid else hi = mid end
  end
  return lo
end

-- how many you can make before the materials get any pricier than for the first craft (profit each stays at its best).
function P:bestPriceCount(r, value, cap)
  local first = self:batchCost(r, 1)
  if not first or first > value then return 0 end
  local function same(k) -- does the k-th craft still cost what the first did?
    local a, b = self:batchCost(r, k), self:batchCost(r, k - 1)
    return a and b and (a - b) <= first + 0.01
  end
  if same(cap) then return cap end
  local lo, hi = 1, cap
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if same(mid) then lo = mid else hi = mid end
  end
  return lo
end

-- recipes that make money. qty: how many of each you plan to make (by recipe name); prices count that many.
-- each: { recipe, cost (per craft at that quantity), value, where, net (per craft), qty, upTo (how many still pay) }
function P:moneyMakers(qty)
  local out = {}
  for _, r in ipairs(self.recipes) do
    local cost1, missing = self:recipeCost(r)
    local value, where = self:payout(r)
    if #missing == 0 and value > 0 and value - cost1 > 0.5 then
      local n = math.max(1, (qty and qty[r.name]) or 1)
      local batch = self:batchCost(r, n) or cost1 * n
      local cost = batch / n
      local upTo = self:profitableCount(r, value, 2000)
      local atBest = self:bestPriceCount(r, value, 2000)
      out[#out + 1] = { recipe = r, cost = cost, value = value, where = where, net = value - cost, qty = n, upTo = upTo, atBest = atBest,
                        total = value * n - batch }
    end
  end
  table.sort(out, function(a, b) return a.net > b.net end)
  return out
end

-- Turn a list of crafts into what to make first and what to buy.
-- crafts: { {recipe, n} ... }
-- returns {
--   buy = { {id, need, have, buy, price, where, total} ... },    -- materials, incl. ones you already have
--   prep = { {recipe, n} ... },                                  -- reagents to craft yourself first
--   cash = copper to spend, ownedValue = buy-price value of your own materials used,
--   ownedResale = what those materials would sell for instead, unknown = count of unpriced items to buy }
function P:shopping(crafts)
  local owned = ownedTable(self)
  local need, prepCount, prepOrder = {}, {}, {}
  local usedOwned = {}
  local queue = {}
  for _, c in ipairs(crafts) do
    for _, rg in ipairs(c.recipe.reagents) do queue[#queue + 1] = { rg.id, rg.n * c.n, 0 } end
  end
  local i = 1
  while i <= #queue do
    local id, qty, depth = queue[i][1], queue[i][2], queue[i][3]
    i = i + 1
    need[id] = (need[id] or 0) + qty
    local use = math.min(qty, owned[id])
    owned[id] = owned[id] - use
    usedOwned[id] = (usedOwned[id] or 0) + use
    local rest = qty - use
    if rest > 0 then
      local _, where, via = self:unitCost(id)
      if where == "craft" and via and depth < MAX_DEPTH then
        local n = math.ceil(rest / made(via))
        if not prepCount[via] then prepCount[via] = 0; prepOrder[#prepOrder + 1] = via end
        prepCount[via] = prepCount[via] + n
        for _, rg in ipairs(via.reagents) do queue[#queue + 1] = { rg.id, rg.n * n, depth + 1 } end
        need[id] = need[id] - rest -- made, not bought
      end
    end
  end

  -- buy = everything needed beyond what you own (items you'll craft yourself were taken out above)
  local rows, cash, unknown = {}, 0, 0
  local ownedLeft = ownedTable(self)
  for id, n in pairs(need) do
    if n > 0 then
      local have = ownedLeft[id]
      local buy = math.max(0, n - have)
      local price, where = self:buyPrice(id)
      local total, short, tiers = nil, false, nil
      if price then
        if where == "ah" then total, short, tiers = self:buyCost(id, 0, buy)
        else total = price * buy end
      end
      -- how many are at a good price (within GOOD_PRICE of the cheapest), and what the rest average
      local good, rest, restCost = buy, 0, 0
      if tiers and #tiers > 0 then
        local cheapest = tiers[1][1]
        good = 0
        for _, t in ipairs(tiers) do
          if t[1] <= cheapest * P.GOOD_PRICE then good = good + t[2]
          else rest, restCost = rest + t[2], restCost + t[1] * t[2] end
        end
      end
      if buy > 0 then
        if total then cash = cash + total else unknown = unknown + 1 end
      end
      rows[#rows + 1] = { id = id, need = n, have = have, buy = buy, price = price, where = where, total = total,
        short = short, tiers = tiers, good = good, rest = rest, restAvg = rest > 0 and restCost / rest or nil }
    end
  end
  table.sort(rows, function(a, b)
    if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
    if a.where ~= b.where then return a.where < b.where end
    return (a.total or 0) > (b.total or 0)
  end)

  local ownedValue, ownedResale = 0, 0
  for id, n in pairs(usedOwned) do
    if n > 0 then
      local price = self:buyPrice(id)
      ownedValue = ownedValue + (price or 0) * n
      local it = self:get(id)
      local resale = it and (it.sell or 0) or 0
      local a = self:ahPrice(it)
      if a and it.bind ~= 1 then resale = math.max(resale, a * (1 - P.AH_CUT)) end
      ownedResale = ownedResale + resale * n
    end
  end

  local prep = {}
  for _, r in ipairs(prepOrder) do prep[#prep + 1] = { recipe = r, n = prepCount[r] } end
  return { buy = rows, prep = prep, cash = cash, ownedValue = ownedValue, ownedResale = ownedResale, unknown = unknown }
end

-- Payout of a list of crafts when sold
function P:totalPayout(crafts)
  local v = 0
  for _, c in ipairs(crafts) do v = v + self:payout(c.recipe) * c.n end
  return v
end

return P
