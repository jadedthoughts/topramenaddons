-- Top Ramen Gear: scoring engine (a Lua port of the website's scoring)
-- Reads exact stats from the game, then scores items for Bear tanking and Cat DPS.
local _, ns = ...

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats

---------------------------------------------------------------------------
-- settings (saved between sessions)
---------------------------------------------------------------------------
ns.DEFAULT_W = {
  bear = { wdps = 9.8, str = 1.4, agi = 2.2, sta = 2.0, ap = 0.7, fap = 0.7, hit = 2.0, exp = 3.6, crit = 0.7, haste = 0.9,
           armor = 0.12, def = 1.6, dodge = 0.85, parry = 0, wskill = 2, int = 0.1, spi = 0.1, hp = 0.2, holyres = 0,
           fireres = 0.2, natureres = 0.2, frostres = 0.2, shadowres = 0.2, arcaneres = 0.2, sp = 0, heal = 0, mp5 = 0 },
  cat  = { wdps = 14, str = 2.4, agi = 2.5, sta = 0.05, ap = 1, fap = 1, hit = 2.8, exp = 2.2, crit = 1.9, haste = 1.2,
           armor = 0, def = 0, dodge = 0, parry = 0, wskill = 3, int = 0.15, spi = 0.1, hp = 0, holyres = 0,
           fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0, sp = 0, heal = 0, mp5 = 0 },
  -- Balance: per point, spell power = 1. Order from the Wowhead Forever Balance guide:
  -- hit (to the cap) > spell damage > spell penetration > crit > haste > Intellect > Spirit > Stamina.
  -- Wrath is Nature and Starfire Arcane, so school damage counts for about half each.
  balance = { sp = 1.0, spnature = 0.5, sparcane = 0.5, shit = 1.1, spen = 0.85, scrit = 0.8, shaste = 0.7,
              int = 0.2, spi = 0.15, mp5 = 0.4, sta = 0.05, heal = 0, wdps = 0, str = 0, agi = 0, ap = 0, fap = 0,
              hit = 0, crit = 0, haste = 0, exp = 0, armor = 0, def = 0, dodge = 0, parry = 0, wskill = 0, hp = 0,
              holyres = 0, fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0 },
  -- Restoration: per point, healing = 1. Order from the Wowhead Forever Restoration guide:
  -- healing > crit > haste > Spirit > Intellect > mana per 5 > Stamina. Heals crit for 150% and HoTs can crit.
  -- "+damage and healing" on an item counts as healing (see ns.Score), so sp itself is 0 here.
  resto = { heal = 1.0, scrit = 0.75, shaste = 0.65, spi = 0.55, int = 0.3, mp5 = 0.4, sta = 0.1,
            sp = 0, spnature = 0, sparcane = 0, shit = 0, spen = 0, wdps = 0, str = 0, agi = 0, ap = 0, fap = 0,
            hit = 0, crit = 0, haste = 0, exp = 0, armor = 0, def = 0, dodge = 0, parry = 0, wskill = 0, hp = 0,
            holyres = 0, fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0 },
}
local DEFAULTS = {
  tooltip = true,      -- show upgrade lines on item tooltips
  showBear = true, showCat = true,
  showBear3 = true,    -- also show the Bear score with Swipe on 3 targets
  showBalance = false, -- Balance line on tooltips (turn on in Settings)
  showResto = false,   -- Restoration line on tooltips (turn on in Settings)
  capSpellHit = 17,    -- spell hit cap vs bosses (Wowhead Forever guide: 16% miss, 17% never misses)
  bearFocus = 0,       -- -100 survival .. +100 threat
  capHit = 8, talHit = 0, capExp = 6.5, capDef = 140,
  useTalents = true,   -- apply your talents to the scores
  dgWithinDefault = false, dgWithinLevels = 5, dgShowAllDefault = false, dgMineDefault = true, -- Dungeons tab filters at login
}

-- the specs Top Ramen scores, by class (only Druids for now; Feral covers Bear and Cat)
-- color: the spec's dot on tooltips and the window
ns.SPECS = {
  DRUID = { { key = "bear", name = "Bear", long = "Bear Tank", group = "Feral", show = "showBear", color = { 1, 0.49, 0.04 } },
            { key = "cat", name = "Cat", long = "Cat DPS", group = "Feral", show = "showCat", color = { 1, 0.82, 0 } },
            { key = "balance", name = "Balance", long = "Balance", group = "Caster", show = "showBalance", color = { 0.29, 0.66, 1 } },
            { key = "resto", name = "Restoration", long = "Restoration", group = "Healer", show = "showResto", color = { 0.29, 0.87, 0.5 } } },
}
function ns.ClassSpecs()
  local _, class = UnitClass("player")
  return ns.SPECS[class or ""] or ns.SPECS.DRUID
end
function ns.ModeName(mode)
  for _, list in pairs(ns.SPECS) do for _, s in ipairs(list) do if s.key == mode then return s.name end end end
  return mode
end

function ns.InitDB()
  TopRamenGearDB = TopRamenGearDB or {}
  local db = TopRamenGearDB
  for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
  db.weights = db.weights or {}
  for mode, w in pairs(ns.DEFAULT_W) do
    db.weights[mode] = db.weights[mode] or {}
    for k, v in pairs(w) do if db.weights[mode][k] == nil then db.weights[mode][k] = v end end
  end
  -- Bear offence re-ordered to match the Wowhead Forever tank guide (hit > expertise > haste > crit; Strength = its 2 AP):
  -- update saved weights that still have the old defaults
  -- expertise is a % in Forever; the cap is 6.5% against boss dodges (Wowhead and ConquestCapped guides)
  if (db.weightsVersion or 1) < 3 and (db.capExp or 0) == 0 then db.capExp = 6.5 end
  if (db.weightsVersion or 1) < 2 then
    local old = { str = 1.6, hit = 1.5, exp = 1.2, haste = 0.6 }
    for k, v in pairs(old) do
      if db.weights.bear[k] == v then db.weights.bear[k] = ns.DEFAULT_W.bear[k] end
    end
  end
  -- Forever expertise lowers the chance to be dodged AND parried, and a Bear tanks from the front where bosses
  -- parry, so for Bear it's worth more than hit (about 1.8x; a WoWSims Forever Bear set has it at 2.6x hit).
  -- Cat attacks from behind (no parries), so Cat expertise stays below hit.
  if (db.weightsVersion or 1) < 4 and db.weights.bear.exp == 1.6 then db.weights.bear.exp = ns.DEFAULT_W.bear.exp end
  -- dodge halved (1% dodge ~ 5 Stamina at middle focus): it's random avoidance, not reliable survival like
  -- Stamina and armor. Kept above zero for dungeons/leveling, where it saves the healer's mana.
  if (db.weightsVersion or 1) < 5 and db.weights.bear.dodge == 1.7 then db.weights.bear.dodge = ns.DEFAULT_W.bear.dodge end
  if (db.weightsVersion or 1) < 5 then db.weightsVersion = 5 end
  ns.db = db
  return db
end

---------------------------------------------------------------------------
-- reading an item's stats
---------------------------------------------------------------------------
local GIS = {
  ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_INTELLECT_SHORT = "int",
  ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor", ITEM_MOD_EXTRA_ARMOR_SHORT = "armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "wdps",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "fap", ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit", ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "haste",
  ITEM_MOD_EXPERTISE_RATING_SHORT = "exp", ITEM_MOD_DODGE_RATING_SHORT = "dodge", ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
  ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_HEALTH_SHORT = "hp",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
  ITEM_MOD_HIT_SPELL_RATING_SHORT = "shit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "scrit", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "shaste",
  ITEM_MOD_SPELL_PENETRATION_SHORT = "spen",
  RESISTANCE2_NAME = "fireres", RESISTANCE3_NAME = "natureres", RESISTANCE4_NAME = "frostres", RESISTANCE5_NAME = "shadowres", RESISTANCE6_NAME = "arcaneres",
}
-- tooltip patterns (matched on lower-case text), used only for stats the game's stat list didn't report
local TT = {
  -- Forever expertise is a flat %: "Reduces the chance for your attacks to be dodged or parried by 1.1%"
  { "dodged or parried by ([%d%.]+)%%", "exp", 10 },
  -- spell versions first (so "chance to hit with spells" isn't read as melee hit)
  { "chance to hit with spells by (%d+)%%", "shit", 10 }, { "spell hit rating by (%d+)", "shit" },
  { "critical strike with spells by (%d+)%%", "scrit", 14 }, { "spell critical strike rating by (%d+)", "scrit" },
  { "spell haste rating by (%d+)", "shaste" },
  { "damage done by nature spells and effects by up to (%d+)", "spnature" },
  { "damage done by arcane spells and effects by up to (%d+)", "sparcane" },
  { "spell penetration by (%d+)", "spen" }, { "magical resistances of your spell targets by (%d+)", "spen" },
  { "healing done by spells and effects by up to (%d+)", "heal" },
  { "^%+?(%d+) armor$", "armor" }, { "^%+(%d+) agility$", "agi" }, { "^%+(%d+) strength$", "str" }, { "^%+(%d+) stamina$", "sta" },
  { "^%+(%d+) intellect$", "int" }, { "^%+(%d+) spirit$", "spi" }, { "%(([%d%.]+) damage per second%)", "wdps" },
  { "attack power by (%d+) in cat, bear", "fap" }, { "%+(%d+) attack power in cat, bear", "fap" },
  { "^equip: %+(%d+) attack power%.?$", "ap" }, { "^equip: increases attack power by (%d+)%.?$", "ap" },
  { "increased defense %+(%d+)", "def" }, { "increases defense rating by (%d+)", "def" }, { "increases defense skill by (%d+)", "def" },
  { "increases defense by (%d+)", "def" }, { "^equip: %+(%d+) defense%.?$", "def" },
  { "hit rating by (%d+)", "hit" }, { "critical strike rating by (%d+)", "crit" }, { "dodge rating by (%d+)", "dodge" },
  { "parry rating by (%d+)", "parry" }, { "haste rating by (%d+)", "haste" }, { "expertise rating by (%d+)", "exp" },
  { "chance to hit by (%d+)%%", "hit", 10 }, { "critical strike by (%d+)%%", "crit", 14 }, { "chance to dodge an attack by (%d+)%%", "dodge", 12 },
  { "damage and healing done by magical spells and effects by up to (%d+)", "sp" },
  { "damage done by magical spells and effects by up to (%d+)", "sp" }, { "spell power by (%d+)", "sp" },
  { "^equip: restores (%d+) mana per 5 sec", "mp5" }, { "(%d+) mana every 5 sec", "mp5" },
  { "^%+(%d+) (%a+) resistance$", "res" },
}

local LOC2S = {
  INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back", INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest",
  INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands", INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
  INVTYPE_TRINKET = "trinket", INVTYPE_2HWEAPON = "weapon2h", INVTYPE_WEAPON = "weapon1h", INVTYPE_WEAPONMAINHAND = "weapon1h",
  INVTYPE_HOLDABLE = "offhand", INVTYPE_RELIC = "relic",
}
ns.LOC2S = LOC2S
-- staves, maces (1H/2H), polearms, fist weapons, daggers
local DRUID_WEAPONS = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true }

-- Can a Druid use this kind of item? Returns the slot group, or nil.
function ns.DruidSlot(equipLoc, classID, subclassID)
  local s = LOC2S[equipLoc or ""]
  if not s then return nil end
  if classID == 4 and (subclassID == 3 or subclassID == 4 or subclassID == 6) then return nil end -- mail, plate, shield
  if classID == 2 and not DRUID_WEAPONS[subclassID] then return nil end
  return s
end

local cache, recheck = {}, {}
function ns.ClearCache() wipe(cache) end
function ns.ItemStatsKnownBad(link) return cache[link] == false end

-- Exact stats of an item link, or nil (not loaded yet / not Druid gear).
function ns.ItemStats(link)
  if not link then return nil end
  local c = cache[link]
  if c ~= nil then return c or nil end
  local name, _, quality, _, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID = GetInfo(link)
  if not name then return nil end -- not loaded yet: don't cache
  local slot = ns.DruidSlot(equipLoc, classID, subclassID)
  if not slot then cache[link] = false; return nil end

  local st = {}
  local ok, gs = pcall(GetStats, link)
  if ok and type(gs) == "table" then
    for k, v in pairs(gs) do
      local key = GIS[k]
      if key and tonumber(v) then st[key] = (st[key] or 0) + tonumber(v) end
    end
  end
  local fx, pending = {}, false
  local lines = ns.tooltipLines("link", link) or {}
  if #lines < 2 then pending = true end
  for _, line in ipairs(lines) do
    local l = line:lower()
    -- the game fills in "Chance on hit: / Equip: / Use:" text a moment after the rest of the tooltip
    if l:find("retrieving") or l:match("^chance on hit:%s*$") or l:match("^equip:%s*$") or l:match("^use:%s*$") then pending = true end
    if not l:match("^%(%d%) set:") then
      local used = false
      local h, d = l:match("healing done by up to (%d+) and damage done by up to (%d+)")
      if h then
        used = true
        if st.heal == nil then st.heal = tonumber(h) end
        st.sp = (st.sp or 0) + tonumber(d)
      end
      for _, p in ipairs(used and {} or TT) do
        local a, b = l:match(p[1])
        if a then
          used = true
          local key = p[2] == "res" and (b .. "res") or p[2]
          if st[key] == nil then st[key] = tonumber(a) * (p[3] or 1) end
          break
        end
      end
      if not used then
        local kind, body = l:match("^(equip): (.*)$")
        if not kind then kind, body = l:match("^(use): (.*)$") end
        if not kind then kind, body = l:match("^(chance on hit): (.*)$") end
        if kind == "use" then
          fx[#fx + 1] = { "use", body }
        elseif kind == "chance on hit" then
          fx[#fx + 1] = { "hit", body }
        elseif kind == "equip" and (body:find("chance on") or body:find("on hit") or body:find("on melee hit")) and not body:find("^improves") then
          fx[#fx + 1] = { body:find("when struck") and "struck" or "hit", body }
        elseif kind == "equip" and body:find("when struck") then
          fx[#fx + 1] = { "struck", body }
        end
      end
    end
  end
  if st.wdps then st.wdps = math.floor(st.wdps * 100 + 0.5) / 100 end
  local id = tonumber(link:match("item:(%d+)"))
  local it = { id = id, link = link, name = name, q = quality, rl = reqLevel or 0, s = slot, st = st, fx = (#fx > 0) and fx or nil }
  -- weapons and anything with an effect line get read again shortly, in case part of the text was still loading;
  -- after that the result is kept
  if pending then return it end
  if not recheck[link] and (slot == "weapon2h" or slot == "weapon1h" or #fx > 0 or slot == "trinket") then
    recheck[link] = true
    cache[link] = it
    if C_Timer then C_Timer.After(2, function() cache[link] = nil; if ns.RefreshWindow then ns.RefreshWindow() end end) end
    return it
  end
  cache[link] = it
  return it
end

---------------------------------------------------------------------------
-- proc and use effects (estimates, same rules as the website)
---------------------------------------------------------------------------
local FORM_SPEED = { cat = 1.0, bear = 2.5 }
local function hitsPerMin(mode, scen) if mode == "cat" then return 90 end return scen == 3 and 84 or 34 end
local function hitsTakenPerMin(mode, scen) if mode == "bear" then return scen == 3 and 60 or 25 end return 0 end
ns.CTX = { wdps = 0, ap = 0 } -- equipped weapon DPS and attack power, for extra-attack procs

local function cdFromText(d)
  local n, unit = (d or ""):match("%((%d+%.?%d*) (%a+) cooldown%)")
  if not n then return 0 end
  unit = unit:lower()
  local mul = unit:find("^min") and 60 or unit:find("^hour") and 3600 or 1
  return tonumber(n) * mul
end

local STATWORD = { strength = "str", agility = "agi", stamina = "sta" }
local function parseEffect(d)
  d = (d or ""):lower()
  local dur = tonumber(d:match("for (%d+) sec") or d:match("lasts (%d+) sec") or 0)
  local m = d:match("absorbs? (%d+)") or d:match("absorbing (%d+)")
  if m then return { kind = "absorb", val = tonumber(m), dur = dur } end
  m = d:match("attack speed by (%d+)%%")
  if m then return { kind = "stat", st = { haste = tonumber(m) * 10 }, dur = dur } end
  m = d:match("attack power by (%d+)")
  if m and not (d:find("against") or d:find("beasts") or d:find("undead") or d:find("demons")) then
    return { kind = "stat", st = { ap = tonumber(m) }, dur = dur }
  end
  m = d:match("armor by (%d+)")
  if m then return { kind = "stat", st = { armor = tonumber(m) }, dur = dur } end
  local word, n = d:match("(strength) by (%d+)")
  if not word then word, n = d:match("(agility) by (%d+)") end
  if not word then word, n = d:match("(stamina) by (%d+)") end
  if word then return { kind = "stat", st = { [STATWORD[word]] = tonumber(n) }, dur = dur } end
  local chance = tonumber(d:match("proc chance: (%d+%.?%d*)%%") or d:match("(%d+%.?%d*)%% chance") or 0)
  if d:find("extra attack") then
    return { kind = "extra", val = tonumber(d:match("(%d+) extra attack") or 1), chance = chance }
  end
  local a, b = d:match("(%d+) to (%d+) %a* ?damage")
  local dmg
  if a then dmg = (tonumber(a) + tonumber(b)) / 2 else dmg = tonumber(d:match("(%d+) %a* ?damage")) end
  -- damage over time: "24 Nature damage every 1 sec for 7 sec" is 7 ticks, 168 in all
  local tick, every, total = d:match("(%d+) %a* ?damage every (%d+%.?%d*) sec%a* for (%d+) sec")
  if tick then dmg = tonumber(tick) * math.max(1, math.floor(tonumber(total) / math.max(0.1, tonumber(every)) + 0.5)) end
  if dmg then
    local extra = d:match("additional (%d+) %a* ?damage over")
    if extra then dmg = dmg + tonumber(extra) end
    return { kind = "dmg", val = dmg, chance = chance }
  end
  return nil
end
ns.parseEffect = parseEffect

function ns.EffectStats(it, mode, scen)
  if not it or not it.fx then return nil end
  if mode == "balance" or mode == "resto" then return nil end -- melee procs and use effects don't help a caster (yet)
  local out, S, any = {}, FORM_SPEED[mode], false
  local function add(st, f) for k, v in pairs(st) do out[k] = (out[k] or 0) + v * f; any = true end end
  for _, f in ipairs(it.fx) do
    local trig, desc = f[1], f[2]
    local e = parseEffect(desc)
    if e then
      if trig == "use" then
        local cd = cdFromText(desc); if cd == 0 then cd = 180 end
        if e.kind == "stat" then add(e.st, math.min(1, (e.dur or 0) / cd))
        elseif e.kind == "dmg" then add({ ap = e.val / cd * 14 }, 1)
        elseif e.kind == "absorb" then add({ sta = e.val / 10 * math.min(1, 60 / cd) }, 1) end
      else
        local perHit = (e.chance and e.chance > 0) and e.chance / 100 or S / 60
        -- a damage shield (like Thorns) fires on every melee hit you take, it isn't a random proc
        if trig == "struck" and not (e.chance and e.chance > 0) and not desc:lower():find("chance") then perHit = 1 end
        local n = trig == "struck" and hitsTakenPerMin(mode, scen) or hitsPerMin(mode, scen)
        local perMin = perHit * n
        if e.kind == "dmg" then add({ ap = perMin * e.val / 60 * 14 }, 1)
        elseif e.kind == "stat" then add(e.st, math.min(1, perMin * ((e.dur and e.dur > 0) and e.dur or 10) / 60))
        elseif e.kind == "extra" then add({ wdps = perMin * e.val * S / 60 * (ns.CTX.wdps + ns.CTX.ap / 14) }, 1)
        elseif e.kind == "absorb" then add({ sta = perMin * e.val / 10 }, 1) end
      end
    end
  end
  return any and out or nil
end

---------------------------------------------------------------------------
-- scoring
---------------------------------------------------------------------------
local CRIT_RATING_PER_PCT, DODGE_RATING_PER_PCT = 14, 12
local FormArmorMultiplier
local SURVIVAL = { sta = 1, armor = 1, def = 1, dodge = 1, parry = 1, hp = 1, fireres = 1, natureres = 1, frostres = 1, shadowres = 1, arcaneres = 1, holyres = 1 }
local THREAT = { wdps = 1, str = 1, ap = 1, fap = 1, hit = 1, exp = 1, crit = 1, haste = 1, wskill = 1 }

-- weights for a mode, with the Bear Survival <-> Threat focus applied
-- and with your talents applied: "+20% Stamina in Bear Form" makes Stamina on gear worth 20% more for Bear
function ns.Weights(mode)
  local w = ns.db.weights[mode]
  local f = mode == "bear" and (ns.db.bearFocus or 0) / 100 or 0
  local tal = (ns.db.useTalents ~= false and ns.TalentMods and ns.TalentMods[mode]) or {}
  local liveArmor = mode == "bear" and ns.LiveArmorWeight(w) or nil
  local out = {}
  for k, v in pairs(w) do
    local x = v
    if k == "armor" and liveArmor then x = liveArmor end
    if f ~= 0 then x = x * (SURVIVAL[k] and (1 - 0.6 * f) or THREAT[k] and (1 + 0.6 * f) or 1) end
    if tal[k] then x = x * (1 + tal[k]) end
    out[k] = x
  end
  -- Agility is worth what it does at your level (Forever's character sheet, level 32 Bear:
  -- 112 Agility = 9.8% crit and 9.8% dodge, 224 armor, and 1 attack power each in Cat Form)
  if mode == "balance" or mode == "resto" then
    -- Intellect gives spell crit (60 per 1% at level 60; about 31 per 1% at level 32 on your sheet)
    out.int = (out.int or 0) + ns.IntPctPerPoint() * CRIT_RATING_PER_PCT * (out.scrit or 0)
    return out
  end
  local pct = ns.AgiPctPerPoint()
  out.agi = (mode == "cat" and (out.ap or 0) or 0)
    + 2 * (out.armor or 0) / FormArmorMultiplier(mode)
    + pct * CRIT_RATING_PER_PCT * (out.crit or 0)
    + pct * DODGE_RATING_PER_PCT * (out.dodge or 0)
  return out
end

-- Bear Form raises armor from items (+180%, or +360% in Dire Bear Form from level 40), and the armor
-- weight is per point of item armor. Armor from Agility isn't raised by the form, so it's worth less.
FormArmorMultiplier = function(mode)
  if mode ~= "bear" then return 1 end
  local f = ns.BearForm()
  return 1 + f.armorPct / 100
end

-- Which bear form you know, and what it does, read from the spell's own text
-- ("Armor contribution from items by 180%", "Health by 560"). Falls back to classic's numbers.
local BEAR_SPELLS = { 9634, 5487 } -- Dire Bear Form, Bear Form
local formCache
function ns.BearForm()
  if formCache then return formCache end
  local lvl = (ns.Level and ns.Level()) or 60
  local f = { name = lvl >= 40 and "Dire Bear Form" or "Bear Form", armorPct = lvl >= 40 and 360 or 180, health = lvl >= 40 and 1240 or 560, source = "level" }
  for _, id in ipairs(BEAR_SPELLS) do
    local known = false
    if IsPlayerSpell then local ok, v = pcall(IsPlayerSpell, id); known = ok and v end
    if not known and IsSpellKnown then local ok, v = pcall(IsSpellKnown, id); known = ok and v end
    if known then
      local d = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id)) or (GetSpellDescription and GetSpellDescription(id)) or ""
      local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) or f.name
      local a = tonumber(d:lower():match("armor contribution from items by (%d+)%%"))
      local h = tonumber(d:lower():match("health by (%d+)"))
      f = { name = name, armorPct = a or (id == 9634 and 360 or 180), health = h or (id == 9634 and 1240 or 560), source = a and "spell" or "known" }
      break
    end
  end
  formCache = f
  return f
end
function ns.ForgetBearForm() formCache = nil end

-- How much one point of armor on an item is worth, compared with Stamina, for YOUR character right now:
-- the game's armor formula (reduction = armor / (armor + 400 + 85 x level); your sheet: 2,278 armor at
-- level 32 = 42.2%), your armor and health in bear form, and the form's bonus to item armor.
-- Armor only stops physical damage; about 85% of dungeon damage is physical.
local PHYSICAL = 0.85
function ns.LiveArmorWeight(w)
  local L = ns.Live
  if not L or not L.armor or not L.health or not L.level then return nil end
  local lvl = L.level
  local K = lvl < 60 and (400 + 85 * lvl) or (467.5 * lvl - 22167.5)
  local f = ns.BearForm()
  local mult = 1 + f.armorPct / 100
  local A, H = L.armor, L.health
  if not L.inBear then
    -- you're not in bear form right now: add what the form would add
    A = A + (L.itemArmor or 0) * (mult - 1)
    H = H + (f.health or 0)
  end
  local D = (1 - PHYSICAL) + PHYSICAL * K / (A + K)        -- share of damage you still take
  local perItemArmor = mult * H * PHYSICAL * K / ((A + K) ^ 2 * D)  -- effective health per point of item armor
  local perSta = 10 / D                                     -- effective health per point of Stamina (10 health)
  return (w.sta or 2) * perItemArmor / perSta
end

-- % spell crit per point of Intellect, by level (your sheet: 92 Intellect = 3.0% at level 32; the guide: 60 per 1% at 60)
function ns.IntPctPerPoint()
  local lvl = (ns.Level and ns.Level()) or 60
  lvl = math.max(1, math.min(60, lvl))
  local intPer1 = 30.7 + (60 - 30.7) * (lvl - 32) / (60 - 32)
  return 1 / math.max(8, intPer1)
end

-- % crit (and dodge) per point of Agility. Read from the game when it can tell us; otherwise
-- estimated from your level: 11.4 Agility per 1% at level 32 (measured), 20 per 1% at level 60.
function ns.AgiPctPerPoint()
  if ns.agiPct then return ns.agiPct end
  local lvl = (ns.Level and ns.Level()) or 60
  lvl = math.max(1, math.min(60, lvl))
  local agiPer1 = 11.43 + (20 - 11.43) * (lvl - 32) / (60 - 32)
  return 1 / math.max(4, agiPer1)
end

local HIT_PER_PCT = 10
local function caps(mode)
  local db = ns.db
  return {
    -- hit you still need from gear: the cap, less hit from talents (read from the game) and any extra you entered
    hit = math.max(0, (db.capHit or 0) - (db.talHit or 0) - ((db.useTalents ~= false and ns.TalentMods and ns.TalentMods.hit) or 0)) * HIT_PER_PCT,
    exp = (db.capExp or 0) * 10, -- % -> points (10 per 1%, like hit)
    shit = mode == "balance" and math.max(0, (db.capSpellHit or 17) - ((db.useTalents ~= false and ns.TalentMods and ns.TalentMods.spellHit) or 0)) * HIT_PER_PCT or 0,
    def = mode == "bear" and (db.capDef or 0) or 0,
  }
end
local function capped(cap, base, add)
  if not cap or cap == 0 then return add end
  return math.max(0, math.min(cap, base + add) - math.min(cap, base))
end

-- items: list of items worn together (e.g. a weapon and an off-hand); base: stat totals of the rest of the gear
-- scen: 1 = single target, 3 = Swipe on 3 targets (Bear)
function ns.Score(items, mode, base, scen)
  local w, sum, s = ns.Weights(mode), {}, 0
  for _, it in ipairs(items) do
    if it then
      for k, v in pairs(it.st) do sum[k] = (sum[k] or 0) + v end
      -- healing: an item's "+healing" line, or else its "+damage and healing" (spell power) heals too
      if mode == "resto" and not it.st.heal and it.st.sp then sum.heal = (sum.heal or 0) + it.st.sp end
      local ex = ns.EffectStats(it, mode, scen or 1)
      if ex then for k, v in pairs(ex) do sum[k] = (sum[k] or 0) + v end end
    end
  end
  if mode == "balance" or mode == "resto" then
    for _, pair in ipairs({ { "hit", "shit" }, { "crit", "scrit" }, { "haste", "shaste" } }) do
      if sum[pair[1]] then sum[pair[2]] = (sum[pair[2]] or 0) + sum[pair[1]]; sum[pair[1]] = nil end
    end
    if base then
      base = setmetatable({ shit = (base.shit or 0) + (base.hit or 0) }, { __index = base })
    end
  end
  local cp = caps(mode)
  for k, v in pairs(sum) do
    if cp[k] and base then s = s + (w[k] or 0) * capped(cp[k], base[k] or 0, v)
    else s = s + (w[k] or 0) * v end
  end
  return s
end

function ns.Totals(items, out)
  out = out or {}
  for _, it in pairs(items) do
    if it then for k, v in pairs(it.st) do out[k] = (out[k] or 0) + v end end
  end
  return out
end
