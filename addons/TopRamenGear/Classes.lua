-- Top Ramen Gear: the other classes (Druid and Hunter are in Score.lua).
-- Specs, roles and stat weights for Warrior, Paladin, Rogue, Priest, Shaman, Mage and Warlock.
--
-- Weights are per point of each stat on gear. Scales: physical specs 1 attack power = 1 (tanks 0.7, like
-- Bear), 14 attack power = 1 weapon DPS; casters and healers 1 spell power (or healing) = 1. Hit, crit,
-- haste, dodge etc. are stored as rating points (10 hit = 1%, 14 crit = 1%, 12 dodge = 1%, 5 block = 1%).
-- Strength weight = attack power per Strength for the class (Stats.lua) x the attack power weight.
-- Agility, and Intellect for casters, are worked out live in ns.Weights from your level and class.
--
-- Stat orders come from the WoW Forever guides (Icy Veins, wow.gg, Warcraft Tavern, Mobalytics), Nov 2026:
--   Arms Warrior: weapon > hit > expertise > crit > Strength (Forever normalizes auto-attack rage)
--   Fury Warrior: weapon DPS > hit > expertise > crit > Strength
--   Protection Warrior: hit > expertise > Agility > Strength; defense: Stamina > armor > Agility > avoidance > defense
--   Holy Paladin: healing > Intellect > Spirit > mp5 > crit
--   Protection Paladin: Stamina > defense > spell power > Intellect > Strength
--   Retribution Paladin: weapon damage > hit (8%) > expertise (6.5%) > spell power > Strength
--   Assassination / Combat Rogue: hit > Agility > weapon damage > crit > haste; Subtlety: weapon > expertise > hit > Agility
--   Discipline / Holy Priest: healing > Intellect > Spirit > crit; Shadow: hit > shadow power > crit > Intellect > Spirit
--     (Shadowform doubles crit damage, and periodic damage can crit in Forever)
--   Elemental Shaman: hit > spell power > crit > Intellect > mp5 > Spirit
--   Enhancement Shaman: weapon DPS (two-handed) > hit > expertise > crit > Strength
--   Restoration Shaman: healing > crit > Intellect > mp5 > Spirit
--   Arcane / Fire / Frost Mage: hit (17%) > spell power > crit > Intellect > mp5 > Spirit (haste is rare but strong)
--   Affliction / Demonology / Destruction Warlock: hit > spell power > crit > haste (Spirit feeds Life Tap)
local _, ns = ...

local function spec(key, name, group, role, color, extra)
  local s = { key = key, name = name, long = name, group = group, role = role, show = "show_" .. key, color = color }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local RED, GOLD, BLUE, GREEN, PURPLE, ORANGE, WHITE = { 0.97, 0.44, 0.44 }, { 1, 0.82, 0 }, { 0.29, 0.66, 1 },
  { 0.29, 0.87, 0.5 }, { 0.71, 0.49, 1 }, { 1, 0.49, 0.04 }, { 0.92, 0.92, 0.92 }

ns.SPECS.WARRIOR = {
  spec("arms", "Arms", "Melee", "melee", RED, { hpm = 26 }),
  spec("fury", "Fury", "Melee", "melee", ORANGE, { hpm = 60 }),
  spec("wprot", "Protection", "Tank", "tank", BLUE, { tank = true }),
}
ns.SPECS.PALADIN = {
  spec("pholy", "Holy", "Healer", "healer", GOLD),
  spec("pprot", "Protection", "Tank", "tank", BLUE, { tank = true }),
  spec("ret", "Retribution", "Melee", "melee", RED, { hpm = 26 }),
}
ns.SPECS.ROGUE = {
  spec("assn", "Assassination", "Melee", "melee", GREEN, { hpm = 60 }),
  spec("combat", "Combat", "Melee", "melee", RED, { hpm = 60 }),
  spec("sub", "Subtlety", "Melee", "melee", PURPLE, { hpm = 55 }),
}
ns.SPECS.PRIEST = {
  spec("disc", "Discipline", "Healer", "healer", WHITE),
  spec("prholy", "Holy", "Healer", "healer", GOLD),
  spec("shadow", "Shadow", "Caster", "caster", PURPLE),
}
ns.SPECS.SHAMAN = {
  spec("ele", "Elemental", "Caster", "caster", BLUE),
  spec("enh", "Enhancement", "Melee", "melee", ORANGE, { hpm = 30 }),
  spec("sresto", "Restoration", "Healer", "healer", GREEN),
}
ns.SPECS.MAGE = {
  spec("arcane", "Arcane", "Caster", "caster", PURPLE),
  spec("fire", "Fire", "Caster", "caster", ORANGE),
  spec("frost", "Frost", "Caster", "caster", BLUE),
}
ns.SPECS.WARLOCK = {
  spec("affl", "Affliction", "Caster", "caster", GREEN),
  spec("demo", "Demonology", "Caster", "caster", PURPLE),
  spec("destro", "Destruction", "Caster", "caster", ORANGE),
}

-- tooltip lines: every spec of these classes is on to start with (turn them off in Settings)
ns.EXTRA_DEFAULTS = ns.EXTRA_DEFAULTS or {}
for _, class in ipairs({ "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK" }) do
  for _, s in ipairs(ns.SPECS[class]) do ns.EXTRA_DEFAULTS[s.show] = true end
end

local W = ns.DEFAULT_W
-- physical DPS: wdps = main-hand (or two-hander) DPS, ohwdps = off-hand weapon DPS, rwdps = ranged weapon
W.arms   = { wdps = 15, str = 2, ap = 1, hit = 1.0, exp = 1.0, crit = 0.9, haste = 0.4, sta = 0.15, armor = 0.01,
             rwdps = 0.3, int = 0, spi = 0.02, hp = 0.015 }
W.fury   = { wdps = 13, ohwdps = 7, str = 2, ap = 1, hit = 1.0, exp = 0.95, crit = 0.9, haste = 0.5, sta = 0.15,
             armor = 0.01, rwdps = 0.3, spi = 0.02, hp = 0.015 }
W.ret    = { wdps = 15, str = 2, ap = 1, hit = 1.0, exp = 0.95, sp = 0.5, spholy = 0.5, crit = 0.85, haste = 0.4,
             int = 0.25, mp5 = 0.3, spi = 0.1, sta = 0.15, armor = 0.01, hp = 0.015 }
W.assn   = { wdps = 10, ohwdps = 5, str = 1, ap = 1, hit = 1.0, exp = 0.9, crit = 0.9, haste = 0.6, sta = 0.12,
             armor = 0.01, rwdps = 0.3, hp = 0.012 }
W.combat = { wdps = 14, ohwdps = 7, str = 1, ap = 1, hit = 1.0, exp = 0.9, crit = 0.8, haste = 0.7, sta = 0.12,
             armor = 0.01, rwdps = 0.3, hp = 0.012 }
W.sub    = { wdps = 14, ohwdps = 5, str = 1, ap = 1, hit = 0.95, exp = 1.0, crit = 0.85, haste = 0.5, sta = 0.12,
             armor = 0.01, rwdps = 0.3, hp = 0.012 }
W.enh    = { wdps = 15, str = 2, ap = 1, hit = 1.0, exp = 0.95, crit = 0.85, haste = 0.5, int = 0.3, sp = 0.3,
             spnature = 0.15, spfire = 0.1, mp5 = 0.2, sta = 0.15, armor = 0.01, spi = 0.05, hp = 0.015 }
-- tanks (the Tank focus slider applies): like Bear, 1 attack power = 0.7
W.wprot  = { sta = 2.0, armor = 0.1, def = 1.6, dodge = 0.85, parry = 0.8, block = 0.5, blockval = 0.35, hp = 0.2,
             hit = 2.0, exp = 3.0, str = 1.4, ap = 0.7, crit = 0.6, haste = 0.6, wdps = 5, rwdps = 0.2,
             fireres = 0.2, natureres = 0.2, frostres = 0.2, shadowres = 0.2, arcaneres = 0.2 }
W.pprot  = { sta = 2.0, armor = 0.1, def = 1.8, dodge = 0.85, parry = 0.8, block = 0.5, blockval = 0.4, hp = 0.2,
             sp = 0.8, spholy = 0.8, int = 0.4, mp5 = 0.6, spi = 0.1, hit = 1.6, exp = 1.8, str = 1.0, ap = 0.5,
             crit = 0.5, haste = 0.4, wdps = 4,
             fireres = 0.2, natureres = 0.2, frostres = 0.2, shadowres = 0.2, arcaneres = 0.2 }
-- casters: sp = all spell damage; school damage (spfire...) counts by how much of the spec's damage is that school
W.arcane = { sp = 1, sparcane = 0.7, spfire = 0.3, shit = 1.1, scrit = 0.8, shaste = 0.7, spen = 0.1, int = 0.4,
             mp5 = 0.5, spi = 0.25, sta = 0.05, rwdps = 0.5 }
W.fire   = { sp = 1, spfire = 1, shit = 1.1, scrit = 0.9, shaste = 0.75, spen = 0.1, int = 0.25, mp5 = 0.4,
             spi = 0.15, sta = 0.05, rwdps = 0.5 }
W.frost  = { sp = 1, spfrost = 1, shit = 1.1, scrit = 0.75, shaste = 0.7, spen = 0.1, int = 0.25, mp5 = 0.45,
             spi = 0.15, sta = 0.05, rwdps = 0.5 }
W.affl   = { sp = 1, spshadow = 1, shit = 1.1, scrit = 0.7, shaste = 0.75, spen = 0.1, int = 0.2, spi = 0.25,
             mp5 = 0.3, sta = 0.1, rwdps = 0.5 }
W.demo   = { sp = 1, spshadow = 0.8, spfire = 0.2, shit = 1.1, scrit = 0.75, shaste = 0.65, spen = 0.1, int = 0.2,
             spi = 0.2, mp5 = 0.3, sta = 0.15, rwdps = 0.5 }
W.destro = { sp = 1, spfire = 0.5, spshadow = 0.5, shit = 1.1, scrit = 0.85, shaste = 0.7, spen = 0.1, int = 0.2,
             spi = 0.25, mp5 = 0.3, sta = 0.1, rwdps = 0.5 }
W.shadow = { sp = 1, spshadow = 1, shit = 1.1, scrit = 0.9, shaste = 0.7, spen = 0.1, int = 0.25, spi = 0.25,
             mp5 = 0.35, sta = 0.1, rwdps = 0.5 }
W.ele    = { sp = 1, spnature = 0.7, spfire = 0.3, shit = 1.1, scrit = 0.8, shaste = 0.7, spen = 0.1, int = 0.25,
             mp5 = 0.45, spi = 0.15, sta = 0.05 }
-- healers: heal = +healing; an item's "+damage and healing" counts as healing (see ns.Score)
W.pholy  = { heal = 1, int = 0.5, spi = 0.3, mp5 = 0.6, scrit = 0.55, shaste = 0.45, sta = 0.1 }
W.disc   = { heal = 1, scrit = 0.6, int = 0.45, spi = 0.4, mp5 = 0.55, shaste = 0.6, sta = 0.1, rwdps = 0.3 }
W.prholy = { heal = 1, scrit = 0.6, spi = 0.5, int = 0.4, mp5 = 0.55, shaste = 0.65, sta = 0.1, rwdps = 0.3 }
W.sresto = { heal = 1, scrit = 0.65, int = 0.4, mp5 = 0.6, spi = 0.3, shaste = 0.6, sta = 0.1 }
