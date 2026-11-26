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
           armor = 0.12, def = 1.6, dodge = 0.3, parry = 0, wskill = 2, arp = 0.27, int = 0.1, spi = 0.1, hp = 0.2, holyres = 0,
           fireres = 0.2, natureres = 0.2, frostres = 0.2, shadowres = 0.2, arcaneres = 0.2, sp = 0, heal = 0, mp5 = 0 },
  cat  = { wdps = 14, str = 2.4, agi = 2.5, sta = 0.05, ap = 1, fap = 1, hit = 2.8, exp = 2.2, crit = 1.9, haste = 1.2,
           armor = 0, def = 0, dodge = 0, parry = 0, wskill = 3, arp = 0.38, int = 0.15, spi = 0.1, hp = 0, holyres = 0,
           fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0, sp = 0, heal = 0, mp5 = 0 },
  -- Balance: per point, spell power = 1. Order from the Wowhead Forever Balance guide:
  -- hit (to the cap) > spell damage > spell penetration > crit > haste > Intellect > Spirit > Stamina.
  -- Wrath is Nature and Starfire Arcane, so school damage counts for about half each.
  balance = { sp = 1.0, spnature = 0.5, sparcane = 0.5, shit = 1.1, spen = 0.1, scrit = 0.8, shaste = 0.7,
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
  -- Hunters: per point, 1 ranged attack power = 1 (14 attack power = 1 weapon DPS). "+attack power" on gear
  -- raises ranged attack power too; Strength only raises melee attack power. Agility (worked out live in
  -- ns.Weights) = 2 ranged attack power + crit. Guides (Icy Veins / wow.gg, Forever): weapon damage first,
  -- then hit to the cap, Agility, crit; the pet inherits all of your crit. rwdps = bow/gun/crossbow DPS,
  -- wdps = melee weapon DPS, ohwdps = an off-hand weapon's DPS (off-hand hits do half damage).
  bm = { rwdps = 18, rap = 1, ap = 1, hit = 0.9, crit = 0.85, haste = 0.6, sta = 0.3, int = 0.1, spi = 0.1, mp5 = 0.4,
         wdps = 0.3, ohwdps = 0.1, str = 0, armor = 0.01, dodge = 0, parry = 0, def = 0, exp = 0, hp = 0.03,
         fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0, holyres = 0, sp = 0, heal = 0 },
  mm = { rwdps = 19, rap = 1, ap = 1, hit = 0.95, crit = 0.85, haste = 0.55, sta = 0.25, int = 0.12, spi = 0.1, mp5 = 0.4,
         wdps = 0.3, ohwdps = 0.1, str = 0, armor = 0.01, dodge = 0, parry = 0, def = 0, exp = 0, hp = 0.025,
         fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0, holyres = 0, sp = 0, heal = 0 },
  -- Survival is a melee spec in Forever ("weapon damage is your most important stat"): it dual wields
  sv = { wdps = 14, ohwdps = 6, str = 1, ap = 1, rap = 0.15, rwdps = 2, hit = 0.9, exp = 0.9, crit = 0.85, haste = 0.5,
         sta = 0.35, int = 0.05, spi = 0.08, mp5 = 0.2, armor = 0.02, dodge = 0.15, parry = 0.1, def = 0, hp = 0.035,
         fireres = 0, natureres = 0, frostres = 0, shadowres = 0, arcaneres = 0, holyres = 0, sp = 0, heal = 0 },
}
local DEFAULTS = {
  tooltip = true,      -- show upgrade lines on item tooltips
  showBear = true, showCat = true,
  showBear3 = true,    -- also show the Bear score with Swipe on 3 targets
  showBalance = false, -- Balance line on tooltips (turn on in Settings)
  showResto = false,   -- Restoration line on tooltips (turn on in Settings)
  showBM = true, showMM = true, showSV = true, -- Hunter lines on tooltips
  capSpellHit = 17,    -- spell hit cap vs bosses (Wowhead Forever guide: 16% miss, 17% never misses)
  bearFocus = 0,       -- -100 survival .. +100 threat
  capHit = 8, talHit = 0, capExp = 6.5, capDef = 140,
  capTarget = "auto", -- hit and expertise caps for: auto (my level until 60, then raid), level, dungeon, raid, custom
  useTalents = true,   -- apply your talents to the scores
  dgWithinDefault = false, dgWithinLevels = 5, dgShowAllDefault = false, dgMineDefault = true, -- Dungeons tab filters at login
  rollCompare = true,  -- party loot roll window
  subDaggers = true,   -- Subtlety: a main hand that isn't a dagger counts its weapon DPS at 70%
}

-- the specs Top Ramen scores, by class (only Druids for now; Feral covers Bear and Cat)
-- color: the spec's dot on tooltips and the window
ns.SPECS = {
  DRUID = { { key = "bear", name = "Bear", long = "Bear Tank", group = "Feral", show = "showBear", color = { 1, 0.49, 0.04 }, tank = true },
            { key = "cat", name = "Cat", long = "Cat DPS", group = "Feral", show = "showCat", color = { 1, 0.82, 0 } },
            { key = "balance", name = "Balance", long = "Balance", group = "Caster", show = "showBalance", color = { 0.29, 0.66, 1 } },
            { key = "resto", name = "Restoration", long = "Restoration", group = "Healer", show = "showResto", color = { 0.29, 0.87, 0.5 } } },
  HUNTER = { { key = "bm", name = "Beast Mastery", long = "Beast Mastery", group = "Ranged", show = "showBM", color = { 0.67, 0.83, 0.45 } },
             { key = "mm", name = "Marksmanship", long = "Marksmanship", group = "Ranged", show = "showMM", color = { 0.29, 0.66, 1 } },
             { key = "sv", name = "Survival", long = "Survival", group = "Melee", show = "showSV", color = { 1, 0.49, 0.04 } } },
}
-- the class Top Ramen scores for: yours, or the class you're previewing (Settings: "Preview as")
function ns.RealClass() local _, c = UnitClass("player"); return c end
function ns.PlayerClass()
  local p = ns.db and ns.db.previewClass
  if p and ns.SPECS[p] then return p end
  return ns.RealClass()
end
function ns.Previewing()
  local p = ns.db and ns.db.previewClass
  return p ~= nil and ns.SPECS[p] ~= nil and p ~= ns.RealClass()
end
function ns.ClassSpecs()
  return ns.SPECS[ns.PlayerClass() or ""] or ns.SPECS.DRUID
end
-- does this class have a tank spec (Bear; later Protection Warrior / Paladin)? The Tank focus slider is for those.
function ns.HasTankSpec()
  for _, sp in ipairs(ns.ClassSpecs()) do if sp.tank then return true end end
  return false
end
-- does Top Ramen score this class yet?
function ns.ClassSupported()
  return ns.SPECS[ns.PlayerClass() or ""] ~= nil
end
-- the spec to show: the saved one if it belongs to this class, otherwise the class's first
function ns.CurrentMode()
  local m = ns.db and ns.db.windowMode
  for _, sp in ipairs(ns.ClassSpecs()) do if sp.key == m then return m end end
  return ns.ClassSpecs()[1].key
end
local HUNTER_MODES = { bm = true, mm = true, sv = true }
ns.HUNTER_MODES = HUNTER_MODES
-- spec roles: tank, melee, ranged, caster, healer (set on each spec in ns.SPECS; Druid's set here)
local DRUID_ROLES = { bear = "tank", cat = "melee", balance = "caster", resto = "healer", bm = "ranged", mm = "ranged", sv = "melee" }
function ns.SpecInfo(mode)
  for _, list in pairs(ns.SPECS) do for _, s in ipairs(list) do if s.key == mode then return s end end end
end
function ns.Role(mode)
  local s = ns.SpecInfo(mode)
  return (s and s.role) or DRUID_ROLES[mode] or "melee"
end
function ns.IsTank(mode) return ns.Role(mode) == "tank" end
function ns.IsHealer(mode) return ns.Role(mode) == "healer" end
function ns.IsCaster(mode) local r = ns.Role(mode); return r == "caster" or r == "healer" end
function ns.ModeName(mode)
  for _, list in pairs(ns.SPECS) do for _, s in ipairs(list) do if s.key == mode then return s.name end end end
  return mode
end

function ns.InitDB()
  TopRamenGearDB = TopRamenGearDB or {}
  local db = TopRamenGearDB
  for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
  for k, v in pairs(ns.EXTRA_DEFAULTS or {}) do if db[k] == nil then db[k] = v end end
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
  -- 1.18: caps follow who you fight. If you had typed your own caps, keep them ("custom").
  if (db.weightsVersion or 1) < 6 then
    if db.capHit ~= 8 or db.capSpellHit ~= 17 or db.capExp ~= 6.5 then db.capTarget = "custom" end
    db.weightsVersion = 6
  end
  -- 1.18: Spell Piercing only matters against resistances (most mobs have none): 0.1, a tie-breaker
  if (db.weightsVersion or 1) < 7 then
    local old = { balance = 0.85, arcane = 0.6, fire = 0.6, frost = 0.6, affl = 0.6, demo = 0.5, destro = 0.7, shadow = 0.6, ele = 0.6 }
    for mode, v in pairs(old) do
      local w = db.weights[mode]
      if w and w.spen == v and ns.DEFAULT_W[mode] then w.spen = ns.DEFAULT_W[mode].spen end
    end
    db.weightsVersion = 7
  end
  -- 1.21: Bear dodge lowered again, to match the Pawn and WoWSims Forever Bear sets (1% dodge ~ 1.3-2.4
  -- Stamina there; it was ~5). Only changed if you hadn't set your own.
  if (db.weightsVersion or 1) < 8 then
    if db.weights.bear.dodge == 0.85 then db.weights.bear.dodge = ns.DEFAULT_W.bear.dodge end
    db.weightsVersion = 8
  end
  ns.db = db
  return db
end

---------------------------------------------------------------------------
-- reading an item's stats
---------------------------------------------------------------------------
local GIS = {
  ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_INTELLECT_SHORT = "int",
  ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor", ITEM_MOD_EXTRA_ARMOR_SHORT = "armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "wdps",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
  ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "blockval", ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "fap", ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit", ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "haste",
  ITEM_MOD_EXPERTISE_RATING_SHORT = "exp", ITEM_MOD_DODGE_RATING_SHORT = "dodge", ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
  ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_HEALTH_SHORT = "hp",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
  ITEM_MOD_HIT_SPELL_RATING_SHORT = "shit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "scrit", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "shaste",
  ITEM_MOD_SPELL_PENETRATION_SHORT = "spen", ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arp",
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
  { "damage done by fire spells and effects by up to (%d+)", "spfire" },
  { "damage done by frost spells and effects by up to (%d+)", "spfrost" },
  { "damage done by shadow spells and effects by up to (%d+)", "spshadow" },
  { "damage done by holy spells and effects by up to (%d+)", "spholy" },
  { "chance to block attacks with a shield by (%d+)%%", "block", 5 }, { "block rating by (%d+)", "block" },
  { "block value of your shield by (%d+)", "blockval" }, { "^(%d+) block$", "blockval" },
  { "spell penetration by (%d+)", "spen" }, { "magical resistances of your spell targets by (%d+)", "spen" },
  { "healing done by spells and effects by up to (%d+)", "heal" },
  { "^%+?(%d+) armor$", "armor" }, { "^%+(%d+) agility$", "agi" }, { "^%+(%d+) strength$", "str" }, { "^%+(%d+) stamina$", "sta" },
  { "^%+(%d+) intellect$", "int" }, { "^%+(%d+) spirit$", "spi" }, { "%(([%d%.]+) damage per second%)", "wdps" },
  { "attack power by (%d+) in cat, bear", "fap" }, { "%+(%d+) attack power in cat, bear", "fap" },
  { "ranged attack power by (%d+)", "rap" }, { "^%+(%d+) ranged attack power", "rap" },
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
  -- 1.21: Feral skill (weapon skill in Cat and Bear Form) and armor penetration
  { "increased feral combat %+(%d+)", "wskill" }, { "feral combat skill by (%d+)", "wskill" },
  { "feral skill by (%d+)", "wskill" }, { "^equip: %+(%d+) feral", "wskill" },
  { "armor penetration by (%d+)", "arp" }, { "^equip: your attacks ignore (%d+) of", "arp" },
}

local LOC2S = {
  INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back", INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest",
  INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands", INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
  INVTYPE_TRINKET = "trinket", INVTYPE_2HWEAPON = "weapon2h", INVTYPE_WEAPON = "weapon1h", INVTYPE_WEAPONMAINHAND = "weapon1h",
  INVTYPE_HOLDABLE = "offhand", INVTYPE_RELIC = "relic", INVTYPE_WEAPONOFFHAND = "offweapon",
  INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged", INVTYPE_SHIELD = "shield",
}
ns.LOC2S = LOC2S
-- What each class can wear. Weapon subclasses: 0 axe, 1 2h axe, 2 bow, 3 gun, 4 mace, 5 2h mace, 6 polearm,
-- 7 sword, 8 2h sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
-- Armor: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield; relics: 7 libram (Paladin), 8 idol (Druid), 9 totem (Shaman).
-- armor = best armor type, and the level you can wear it from (the type below until then).
local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
ns.CLASS_RULES = {
  DRUID   = { armor = 2, weapons = set({ 4, 5, 6, 10, 13, 15 }), relic = 8, offhand = true },
  HUNTER  = { armor = 3, armorAt = 40, weapons = set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }), ranged = true, dual = true, offhand = true },
  WARRIOR = { armor = 4, armorAt = 40, weapons = set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }), ranged = true, dual = true, shield = true },
  PALADIN = { armor = 4, armorAt = 40, weapons = set({ 0, 1, 4, 5, 6, 7, 8 }), relic = 7, shield = true, offhand = true },
  ROGUE   = { armor = 2, weapons = set({ 2, 3, 4, 7, 13, 15, 16, 18 }), ranged = true, dual = true },
  PRIEST  = { armor = 1, weapons = set({ 4, 10, 15, 19 }), ranged = true, offhand = true },
  SHAMAN  = { armor = 3, armorAt = 40, weapons = set({ 0, 1, 4, 5, 10, 13, 15 }), relic = 9, shield = true, offhand = true },
  MAGE    = { armor = 1, weapons = set({ 7, 10, 15, 19 }), ranged = true, offhand = true },
  WARLOCK = { armor = 1, weapons = set({ 7, 10, 15, 19 }), ranged = true, offhand = true },
}
local function myClass() return ns.PlayerClass() or "DRUID" end

-- Can this character use this kind of item? Returns the slot group, or nil.
function ns.ClassSlot(equipLoc, classID, subclassID)
  local s = LOC2S[equipLoc or ""]
  if not s then return nil end
  local class = myClass()
  local R = ns.CLASS_RULES[class] or ns.CLASS_RULES.DRUID
  if s == "ranged" and not R.ranged then return nil end
  if s == "offweapon" and not R.dual then return nil end
  if s == "shield" and not R.shield then return nil end
  if s == "offhand" and not R.offhand then return nil end
  if s == "relic" and not R.relic then return nil end
  if classID == 4 then
    if subclassID == 6 then return R.shield and s or nil end
    if s == "relic" then return (subclassID == R.relic or subclassID == 0) and s or nil end
    if subclassID and subclassID >= 1 and subclassID <= 4 then
      local best = R.armor
      if R.armorAt and (ns.Level() or 1) < R.armorAt then best = best - 1 end
      if subclassID > best then return nil end
    end
  end
  if classID == 2 and not R.weapons[subclassID] then return nil end
  return s
end
ns.DruidSlot = ns.ClassSlot

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
  local slot = ns.ClassSlot(equipLoc, classID, subclassID)
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
  -- 1.21.2: the weapon's own speed ("Speed 2.90"), for proc chances; from "94 - 141 Damage" / DPS if missing
  local spd, dlo, dhi
  for _, line in ipairs(lines) do
    local l = line:lower()
    spd = spd or tonumber(l:match("^speed (%d+%.?%d*)$"))
    if not dlo then dlo, dhi = l:match("^(%d+) %- (%d+) damage") end
  end
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
  -- a bow, gun, crossbow or thrown weapon: its damage per second is ranged weapon DPS
  if slot == "ranged" and st.wdps then st.rwdps = st.wdps; st.wdps = nil end
  if not spd and dlo and (st.wdps or st.rwdps or 0) > 0 then
    spd = math.floor((tonumber(dlo) + tonumber(dhi)) / 2 / (st.wdps or st.rwdps) * 100 + 0.5) / 100
  end
  local id = tonumber(link:match("item:(%d+)"))
  local it = { id = id, link = link, name = name, spd = spd, q = quality, rl = reqLevel or 0, s = slot, st = st, fx = (#fx > 0) and fx or nil,
               loc = equipLoc, cls = classID, sub = subclassID }
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
local FORM_SPEED = setmetatable({ cat = 1.0, bear = 2.5, bm = 2.8, mm = 2.8, sv = 2.6 }, { __index = function() return 2.6 end })
local function hitsPerMin(mode, scen)
  if mode == "cat" then return 90 end
  local sp = ns.SpecInfo(mode)
  if sp and sp.hpm then return sp.hpm end            -- e.g. dual wielders swing more often
  local role = ns.Role(mode)
  if role == "ranged" then return 4 end              -- ranged specs rarely swing a melee weapon
  if role == "melee" then return 40 end
  return scen == 3 and 84 or 34                      -- tanks (Bear: Swipe on 3 targets)
end
local function hitsTakenPerMin(mode, scen) if ns.IsTank(mode) then return scen == 3 and 60 or 25 end return 0 end
ns.CTX = { wdps = 0, ap = 0, wspd = 0 } -- equipped weapon DPS, attack power and main-hand speed, for procs
-- only hits that land can proc (misses, dodges and parries don't): about 92% of swings
local LANDED = 0.92
-- 1.22.0: Cat and Bear Form, from WoWSims Forever's Forever logs (EV-0003, EV-0119, EV-0122): a weapon's proc is
-- priced on the paw's speed (Cat 1.0, Bear 2.5), not the weapon's, and only white swings roll it (0 procs in 16,655
-- Cat Form specials). So in a form a weapon proc rolls on the paw's white swings only (Swipe targets add none).
-- The Bear part is carried over from Cat: Bear Form has almost no data yet.
local PAW_WHITE = { cat = 60, bear = 24 } -- white swings a minute at the paw's speed
local ATTACKER_SPEED = 2.0                -- a typical enemy's swing, for "when struck" rates in procs per minute

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
  if ns.IsCaster(mode) then return nil end -- melee procs and use effects don't help a caster or healer (yet)
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
        -- a proc's chance per landed hit = PPM x speed / 60. The PPM: a measured rate from ProcRates.lua (WoWSims
        -- Forever) first, else 1. The speed: the weapon's printed speed (the item's own if it's a weapon, else your
        -- main hand's), but the paw's in Cat or Bear Form (1.22.0). A flat chance (from the table or a stated "2%
        -- chance") is used as it is.
        local rate = ns.PROC_RATES and it.id and ns.PROC_RATES[it.id]
        local isWeapon = it.spd and it.spd > 0
        local paw = PAW_WHITE[mode] ~= nil
        local wspd = (paw and S) or (isWeapon and it.spd) or (ns.CTX.wspd and ns.CTX.wspd > 0 and ns.CTX.wspd) or S
        if trig == "struck" then wspd = ATTACKER_SPEED end
        local perHit
        if rate and rate.chance then perHit = rate.chance
        elseif rate and rate.ppm then perHit = rate.ppm * wspd / 60
        elseif e.chance and e.chance > 0 then perHit = e.chance / 100
        else perHit = wspd / 60 end
        -- a damage shield (like Thorns) fires on every melee hit you take, it isn't a random proc
        if trig == "struck" and not rate and not (e.chance and e.chance > 0) and not desc:lower():find("chance") then perHit = 1 end
        local n = trig == "struck" and hitsTakenPerMin(mode, scen) or hitsPerMin(mode, scen)
        -- in a form a weapon's proc rolls on white swings only
        if trig ~= "struck" and paw and isWeapon then n = PAW_WHITE[mode] end
        local perMin = perHit * n * (trig == "struck" and 1 or LANDED)
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
local THREAT = { wdps = 1, str = 1, ap = 1, fap = 1, hit = 1, exp = 1, crit = 1, haste = 1, wskill = 1, arp = 1 }

-- 1.21: raid weights for Feral at level 60 when the caps are for raid bosses (level 63). From WoWSims Forever
-- pre-raid weights: Cat values crit above hit and haste lower; Feral skill is worth far more against
-- +3 bosses (it cuts glancing blows and misses). Multiplies your weights, so your own changes still count.
local RAID_W = {
  cat  = { crit = 2.17 / 1.9, hit = 2.3 / 2.8, haste = 0.72 / 1.2, wskill = 16 / 3 },
  bear = { wskill = 6 / 2 },
}
function ns.RaidWeights(mode)
  return RAID_W[mode] and ((ns.Level and ns.Level()) or 60) >= 60 and ns.CapTarget() == "raid" and RAID_W[mode] or nil
end

-- weights for a mode, with the Bear Survival <-> Threat focus applied
-- and with your talents applied: "+20% Stamina in Bear Form" makes Stamina on gear worth 20% more for Bear
function ns.Weights(mode)
  local w = ns.db.weights[mode]
  local f = ns.IsTank(mode) and (ns.db.bearFocus or 0) / 100 or 0
  local tal = (ns.db.useTalents ~= false and not ns.Previewing() and ns.TalentMods and ns.TalentMods[mode]) or {}
  local liveArmor = mode == "bear" and ns.LiveArmorWeight(w) or nil
  local raid = ns.RaidWeights(mode) or {}
  local out = {}
  for k, v in pairs(w) do
    local x = v * (raid[k] or 1)
    if k == "armor" and liveArmor then x = liveArmor end
    if f ~= 0 then x = x * (SURVIVAL[k] and (1 - 0.6 * f) or THREAT[k] and (1 + 0.6 * f) or 1) end
    if tal[k] then x = x * (1 + tal[k]) end
    out[k] = x
  end
  -- Agility is worth what it does at your level (Forever's character sheet, level 32 Bear:
  -- 112 Agility = 9.8% crit and 9.8% dodge, 224 armor, and 1 attack power each in Cat Form)
  if ns.IsCaster(mode) then
    -- Intellect gives spell crit (60 per 1% at level 60; about 31 per 1% at level 32 on your sheet)
    out.int = (out.int or 0) + ns.IntPctPerPoint() * CRIT_RATING_PER_PCT * (out.scrit or 0)
    ns.ConvertTalents(out, tal)
    return out
  end
  local pct = ns.AgiPctPerPoint()
  local class = ns.PlayerClass()
  if class ~= "DRUID" then
    -- Agility: melee attack power (Hunters, Rogues), ranged attack power, 2 armor, crit (and dodge).
    -- What 1 melee attack power is worth = the Strength weight / attack power per Strength.
    local T = ns.StatTable(class)
    local meleeAP = (out.str or 0) / math.max(1, T.str or 1)
    out.agi = (T.agiAP or 0) * meleeAP + (T.agiRAP or 0) * (out.rap or 0) + 2 * (out.armor or 0)
      + pct * CRIT_RATING_PER_PCT * (out.crit or 0) + pct * DODGE_RATING_PER_PCT * (out.dodge or 0)
    ns.ConvertTalents(out, tal)
    return out
  end
  out.agi = (mode == "cat" and (out.ap or 0) or 0)
    + 2 * (out.armor or 0) / FormArmorMultiplier(mode)
    + pct * CRIT_RATING_PER_PCT * (out.crit or 0)
    + pct * DODGE_RATING_PER_PCT * (out.dodge or 0)
  return out
end

-- talents that turn Intellect or Spirit into power: that stat is also worth what it turns into
-- (Careful Aim / Mental Dexterity: attack power; Mental Quickness, Champion of the Light: spell damage;
-- Natural Instinct, Spiritual Guidance: healing)
function ns.ConvertTalents(out, tal)
  if not tal then return end
  local ap = math.max(out.ap or 0, out.rap or 0)
  if tal.int2ap then out.int = (out.int or 0) + tal.int2ap * ap end
  if tal.int2sp then out.int = (out.int or 0) + tal.int2sp * (out.sp or 0) end
  if tal.int2heal then out.int = (out.int or 0) + tal.int2heal * (out.heal or 0) end
  if tal.spi2sp then out.spi = (out.spi or 0) + tal.spi2sp * (out.sp or 0) end
  if tal.spi2heal then out.spi = (out.spi or 0) + tal.spi2heal * (out.heal or 0) end
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

-- % spell crit per point of Intellect at your level, for your class (Stats.lua: foreverdb.net's tables
-- from the Forever client; your own Druid sheet matched them: 92 Intellect = 3.0% at level 32)
function ns.IntPctPerPoint()
  local per1 = ns.IntPer1(ns.PlayerClass(), (ns.Level and ns.Level()) or 60)
  if not per1 then return 0 end -- a class without mana gets no spell crit from Intellect
  return 1 / math.max(4, per1)
end

-- % crit per point of Agility. Read from the game when it can tell us (your own class); otherwise from
-- Stats.lua's table for your class and level (your sheets matched it: Druid level 32, Hunter level 42)
function ns.AgiPctPerPoint()
  -- (previewing another class: your own character's live figure is for the wrong class)
  if ns.agiPct and not ns.Previewing() then return ns.agiPct end
  local per1 = ns.AgiPer1(ns.PlayerClass(), (ns.Level and ns.Level()) or 60)
  return 1 / math.max(2, per1 or 20)
end

local HIT_PER_PCT = 10

-- WoW Forever hit and dodge chances by how many levels the target is above you (0, +1, +2, +3 = raid boss).
-- Spells, dodge and the own-level / raid boss attack numbers: stated by the game (character sheet, live data
-- build 1.60.1). Attacks against +1 / +2: Forever's game files list 5.2% and 5.4%.
ns.CAP_TABLE = {
  spell = { 4, 5, 6, 17 },     -- spell hit cap
  melee = { 5, 5.2, 5.4, 8 },  -- melee and ranged hit cap
  dodge = { 5, 5.5, 6, 6.5 },  -- target's dodge chance = expertise cap
  dual  = { 24, 24.5, 25, 27 }, -- auto attacks while dual wielding (Rogue character sheet: 24% own level, 27% raid)
}
ns.CAP_TARGETS = {
  { key = "auto",    text = "Automatic",      tip = "Your level until 60, then raid bosses." },
  { key = "level",   text = "My level",       tip = "Questing: mobs your own level." },
  { key = "dungeon", text = "Dungeon bosses", tip = "Bosses and trash 2 levels above you." },
  { key = "raid",    text = "Raid bosses",    tip = "Bosses 3 levels above you (level 63 at 60). At 60, Feral also uses raid weights." },
  { key = "custom",  text = "Custom",         tip = "Type your own numbers below." },
}
local CAP_DIFF = { level = 0, dungeon = 2, raid = 3 }
function ns.CapTarget()
  local t = ns.db.capTarget or "auto"
  if t == "auto" then return ((ns.Level and ns.Level()) or 60) >= 60 and "raid" or "level" end
  return t
end
-- the cap in use for capHit / capSpellHit / capExp: from the table, or what you typed when Custom
function ns.CapValue(key)
  local db = ns.db
  local i = CAP_DIFF[ns.CapTarget()]
  if i then
    i = i + 1
    if key == "capHit" then return ns.CAP_TABLE.melee[i] end
    if key == "capSpellHit" then return ns.CAP_TABLE.spell[i] end
    if key == "capExp" then return ns.CAP_TABLE.dodge[i] end
    if key == "capDW" then return ns.CAP_TABLE.dual[i] end
  end
  if key == "capDW" then return (db.capHit or 0) > 0 and (db.capHit + 19) or 0 end -- Custom: dual wield adds 19%
  return db[key] or 0
end

-- dual wielding: holding a weapon in the off hand (when previewing: the specs that usually do)
local DW_SPECS = { fury = true, assn = true, combat = true, sub = true, sv = true }
function ns.DualWielding(mode)
  local R = ns.CLASS_RULES[ns.PlayerClass()]
  if not (R and R.dual) or ns.Role(mode) ~= "melee" then return false end
  if ns.Previewing() then return DW_SPECS[mode] or false end
  local link = GetInventoryItemLink and GetInventoryItemLink("player", 17)
  if not link or not GetInstant then return false end
  local _, _, _, _, _, classID = GetInstant(link)
  return classID == 2
end
-- past the special-attack hit cap, hit still stops auto-attack misses for dual wielders (up to 24-27%);
-- auto attacks are roughly half of their damage, so that hit counts at half value
local DW_WHITE = 0.5
local SUB_NON_DAGGER = 0.7

-- a cap of 0 in the settings means "no cap" (nil); otherwise what gear still needs, which can be 0
-- (your talents already reach it: then more hit from gear is worth nothing)
local function need(capPct, fromTalents, per)
  if not capPct or capPct <= 0 then return nil end
  return math.max(0, capPct - (fromTalents or 0)) * per
end
local function caps(mode)
  local db = ns.db
  local tal = db.useTalents ~= false and ns.TalentMods or {}
  -- hit you still need from gear: the cap, less hit from talents (read from the game) and any extra you entered
  local talHit = (db.talHit or 0) + (tal.hit or 0)
  return {
    hit = need(ns.CapValue("capHit"), talHit, HIT_PER_PCT),
    dw = ns.DualWielding(mode) and need(ns.CapValue("capDW"), talHit, HIT_PER_PCT) or nil,
    exp = need(ns.CapValue("capExp"), 0, 10), -- % -> points (10 per 1%, like hit)
    shit = ns.IsCaster(mode) and need(ns.CapValue("capSpellHit"), tal.spellHit, HIT_PER_PCT) or nil,
    -- (Defense from talents, e.g. Anticipation +20, is already yours: gear needs that much less)
    def = ns.IsTank(mode) and need(db.capDef, 100 * ((not ns.Previewing() and tal[mode] and tal[mode].defskill) or 0), 1) or nil,
  }
end
local function capped(cap, base, add)
  if not cap then return add end
  return math.max(0, math.min(cap, base + add) - math.min(cap, base))
end

-- items: list of items worn together (e.g. a weapon and an off-hand); base: stat totals of the rest of the gear
-- scen: 1 = single target, 3 = Swipe on 3 targets (Bear)
function ns.Score(items, mode, base, scen)
  local w, sum, s = ns.Weights(mode), {}, 0
  -- Subtlety: Backstab and Ambush need a dagger in the main hand, and Hemorrhage / Ghostly Strike hit about 45%
  -- harder with one, so another main-hand weapon's DPS counts at 70% (Settings can turn this off)
  local daggerRule = mode == "sub" and ns.db.subDaggers ~= false
  for _, it in ipairs(items) do
    if it then
      for k, v in pairs(it.st) do
        if k == "wdps" and daggerRule and it.cls == 2 and it.sub ~= 15 then v = v * SUB_NON_DAGGER end
        sum[k] = (sum[k] or 0) + v
      end
      -- healing: an item's "+healing" line, or else its "+damage and healing" (spell power) heals too
      if ns.IsHealer(mode) and not it.st.heal and it.st.sp then sum.heal = (sum.heal or 0) + it.st.sp end
      local ex = ns.EffectStats(it, mode, scen or 1)
      if ex then for k, v in pairs(ex) do sum[k] = (sum[k] or 0) + v end end
    end
  end
  if ns.IsCaster(mode) then
    for _, pair in ipairs({ { "hit", "shit" }, { "crit", "scrit" }, { "haste", "shaste" } }) do
      if sum[pair[1]] then sum[pair[2]] = (sum[pair[2]] or 0) + sum[pair[1]]; sum[pair[1]] = nil end
    end
    if base then
      base = setmetatable({ shit = (base.shit or 0) + (base.hit or 0) }, { __index = base })
    end
  end
  local cp = caps(mode)
  for k, v in pairs(sum) do
    if k == "hit" and cp.dw and cp.hit and base then
      local b = base.hit or 0
      local full = capped(cp.hit, b, v)
      s = s + (w.hit or 0) * (full + DW_WHITE * math.max(0, capped(cp.dw, b, v) - full))
    elseif cp[k] and base then s = s + (w[k] or 0) * capped(cp[k], base[k] or 0, v)
    else s = s + (w[k] or 0) * v end
  end
  return s
end

-- the same item worn in the off hand: its weapon DPS counts as off-hand DPS (half-damage hits)
local offCache = setmetatable({}, { __mode = "k" })
function ns.AsOffhand(it)
  if not it or not it.st or not it.st.wdps then return it end
  local c = offCache[it]
  if c then return c end
  local st = {}
  for k, v in pairs(it.st) do st[k] = v end
  st.ohwdps, st.wdps = st.wdps, nil
  c = setmetatable({ st = st, offhandOf = it }, { __index = it })
  offCache[it] = c
  return c
end

function ns.Totals(items, out)
  out = out or {}
  for _, it in pairs(items) do
    if it then for k, v in pairs(it.st) do out[k] = (out[k] or 0) + v end end
  end
  return out
end
