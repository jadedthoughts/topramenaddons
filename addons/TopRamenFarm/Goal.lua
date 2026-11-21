-- Top Ramen Farm: the numbers behind the Goal tab. What you're saving for (mount, dual spec,
-- epic mount, or an amount of your own), what you have toward it, and how long the farming
-- should take at the gold per hour you actually make.

local _, ns = ...

local G = 10000 -- copper in a gold

-- rep = Honored with your home city takes 10% off
ns.GOALS = {
  { key = "mount", label = "Mount", cost = 100 * G, rep = true,
    help = "Riding and your first mount." },
  { key = "dual", label = "Dual spec", cost = 50 * G,
    help = "Dual specialization." },
  { key = "epic", label = "Epic mount", cost = 1200 * G, rep = true,
    help = "Epic riding (1,000g) and an epic mount (200g)." },
}
ns.REP_DISCOUNT = 0.9

-- this character's goal settings
--   mount, dual, epic, useCustom = ticked; custom = gold; honored = nil (automatic) / true / false
--   count = "gold" (gold on hand) | "vendor" (+ bags, vendored) | "smart" (+ bags, sold smart)
function ns.goal()
  local c = ns.char()
  c.goal = c.goal or {}
  local g = c.goal
  if g.count ~= "gold" and g.count ~= "vendor" and g.count ~= "smart" then g.count = "smart" end
  return g
end

---------------------------------------------------------------------------
-- reputation: the mount vendor and riding trainer are in your race's home city
---------------------------------------------------------------------------
local HOME = { Human = 72, Dwarf = 47, NightElf = 69, Gnome = 54,
  Orc = 76, Tauren = 81, Scourge = 68, Undead = 68, Troll = 530 }

-- Honored or better with your home city? returns true/false and the city's name (nil if unknown)
function ns.detectHonored()
  local _, race = UnitRace("player")
  local id = race and HOME[race]
  if not id then return nil end
  if GetFactionInfoByID then
    local ok, name, _, standing = pcall(GetFactionInfoByID, id)
    if ok and name then return (standing or 0) >= 6, name end -- 6 = Honored
  end
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and type(d) == "table" and d.name then return (d.reaction or 0) >= 6, d.name end
  end
  return nil
end

-- the discount in use: your own setting, or what the game says. Second value: true when automatic.
function ns.isHonored()
  local g = ns.goal()
  if g.honored ~= nil then return g.honored, false end
  return ns.detectHonored() and true or false, true
end

---------------------------------------------------------------------------
-- things you already have don't count toward the total
---------------------------------------------------------------------------
local function ridingSkill()
  if not GetNumSkillLines or not GetSkillLineInfo then return 0 end
  for i = 1, GetNumSkillLines() do
    local name, header, _, rank = GetSkillLineInfo(i)
    if not header and name == "Riding" then return rank or 0 end
  end
  return 0
end

local function hasDualSpec()
  if not GetNumTalentGroups then return false end
  local ok, n = pcall(GetNumTalentGroups)
  return ok and (n or 0) >= 2
end

function ns.goalDone(key)
  if key == "mount" then return ridingSkill() >= 75 end
  if key == "epic" then return ridingSkill() >= 150 end
  if key == "dual" then return hasDualSpec() end
  return false
end

function ns.goalCost(def)
  if def.rep and ns.isHonored() then return math.floor(def.cost * ns.REP_DISCOUNT) end
  return def.cost
end

-- copper for everything ticked that you don't have yet, and their names
function ns.goalTotal()
  local g, total, parts = ns.goal(), 0, {}
  for _, def in ipairs(ns.GOALS) do
    if g[def.key] and not ns.goalDone(def.key) then
      total = total + ns.goalCost(def)
      parts[#parts + 1] = def.label
    end
  end
  if g.useCustom and (g.custom or 0) > 0 then
    total = total + g.custom * G
    parts[#parts + 1] = "Other"
  end
  return total, parts
end

---------------------------------------------------------------------------
-- what you have toward it
---------------------------------------------------------------------------
local bagCache, bagDirty = nil, true
function ns.goalBagsDirty() bagDirty = true end
local function bagTotals()
  if bagDirty or not bagCache then
    bagCache = ns.totals(ns.scanBags())
    bagDirty = false
  end
  return bagCache
end

-- gold on hand, plus your bags if you count them. Returns total, gold, bags (copper).
function ns.goalHave()
  local g = ns.goal()
  local gold = GetMoney and GetMoney() or 0
  if g.count == "gold" then return gold, gold, 0 end
  local t = bagTotals()
  local bags = g.count == "vendor" and t.vendor or t.smart
  return gold + bags, gold, bags
end

-- which loot value plans the farm time: sold smart, or vendored (also used for "gold on hand")
function ns.goalKind() return ns.goal().count == "smart" and "smart" or "vendor" end

-- gold per hour to plan with: this run once it's 10 minutes old, otherwise your average
-- over saved runs. Returns copper per hour (nil if there's nothing to go on) and where it's from.
function ns.goalRate()
  local kind = ns.goalKind()
  local s = ns.session()
  if s and s.running then
    local sec = ns.elapsed(s)
    if sec >= 600 then return ns.perHour(ns.totals(s)[kind], sec), "this run" end
  end
  local sum, sec = 0, 0
  for _, h in ipairs(ns.char().history) do
    local snap = h.snap or ns.totals(h)
    sum, sec = sum + (snap[kind] or 0), sec + (h.elapsed or 0)
  end
  local r = ns.perHour(sum, sec)
  if r then return r, "your average" end
  return nil
end

-- "2h 05m" of farming to make copper at perHour (nil when there's no rate)
function ns.etaText(copper, perHour)
  if not copper or copper <= 0 then return "none" end
  if not perHour or perHour <= 0 then return nil end
  local min = math.ceil(copper / perHour * 60)
  if min >= 60000 then return "1000h+" end
  local h, m = math.floor(min / 60), min % 60
  if h == 0 then return m .. "m" end
  return string.format("%dh %02dm", h, m)
end

---------------------------------------------------------------------------
-- your saved runs, zone by zone: { name, runs, sec, money, vendor, smart }
-- Runs from 0.3.0 on split their time and loot by zone. Older runs that crossed zones
-- can't be split, so they're grouped under all their zones together ("Badlands, Wetlands").
---------------------------------------------------------------------------
function ns.goalZones()
  local by, list = {}, {}
  local function add(name, sec, snap)
    local z = by[name]
    if not z then
      z = { name = name, runs = 0, sec = 0, money = 0, vendor = 0, smart = 0 }
      by[name] = z
      list[#list + 1] = z
    end
    z.runs = z.runs + 1
    z.sec = z.sec + (sec or 0)
    z.money = z.money + (snap.money or 0)
    z.vendor = z.vendor + (snap.vendor or 0)
    z.smart = z.smart + (snap.smart or 0)
  end
  for _, s in ipairs(ns.char().history) do
    if (s.zoneTime and next(s.zoneTime)) or (s.zoneSnap and next(s.zoneSnap)) then
      local names = {}
      for name in pairs(s.zoneTime or {}) do names[name] = true end
      for name in pairs(s.zoneSnap or {}) do names[name] = true end
      for name in pairs(names) do
        add(name, (s.zoneTime or {})[name] or 0, (s.zoneSnap or {})[name] or {})
      end
    else
      local name = ns.zonesText(s, 3)
      add(name ~= "" and name or "Unknown zone", s.elapsed, s.snap or ns.totals(s))
    end
  end
  return list
end
