-- Top Ramen Procs: the proc logger (/trp opens the window)
-- Counts how often the gear you wear really procs, from the combat log, so Top Ramen Gear's scores can
-- later use real rates instead of the "1 proc per minute" guess. A separate addon on purpose: it's a
-- supplemental data-collecting tool and stays out of Gear's way (they may be combined later).
-- For each item it keeps: time worn in combat, the hits that could trigger it (that weapon's hits for a
-- weapon, all your melee hits for other gear, hits taken for "when struck"), and the procs it caused.
-- Everything is saved account-wide in TopRamenProcsDB.
--
-- Which item caused a proc: the combat log names the spell, not the item. A proc spell is matched to an
-- item by (1) the spell's name appearing in the item's name or effect text, otherwise (2) elimination:
-- every time the spell fires, only items with an effect that you were wearing at that moment stay
-- possible; once one is left, that's the item. Spells you cast yourself, spells in your spellbook,
-- rogue poisons, Windfury and a few talent procs are never counted.
local _, ns = ...

local GOLD, GREY, GREEN, RED = "|cffe0b04a", "|cff9d9d9d", "|cff4ade80", "|cffff6060"
local MIN_PROCS = 10      -- below this, a rate is shown as "early"
local DEDUPE = 0.15       -- the same proc showing up as damage + aura (or hitting 3 targets) counts once

local function say(msg) print(GOLD .. "Top Ramen Procs:|r " .. msg) end
ns.say = say
local function now() return GetTime and GetTime() or 0 end

-- not gear, whatever else they look like
local IGNORE = {
  "^instant poison", "^deadly poison", "^wound poison", "^mind%-numbing poison", "^crippling poison",
  "^windfury attack", "^windfury totem", "^clearcasting", "^enrage", "^blood craze", "^flurry",
  "^holy strength", "^fiery weapon", "^lifestealing", "^icy chill", "^unholy curse", -- weapon enchants (enchants aren't scored)
  "^well fed", "^food", "^drink", "^first aid", "^recently bandaged", "^sword specialization",
  "^seal of", "^judgement", "^vengeance", "^redoubt", "^reckoning", "^improved", "^furor",
}
local SCHOOL = { holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }

---------------------------------------------------------------------------
-- saved data
---------------------------------------------------------------------------
local L -- TopRamenProcsDB
local function log()
  if L then return L end
  if not ns.ready then return nil end -- saved data isn't loaded before PLAYER_LOGIN
  TopRamenProcsDB = TopRamenProcsDB or {}
  L = TopRamenProcsDB
  -- Gear 1.21.0 had this logger built in for a short while: carry over what it counted
  local old = TopRamenGearDB and TopRamenGearDB.procLog
  if old and not L.items and old.items then
    L.items, L.spells, L.party, L.since, L.on = old.items, old.spells, old.party, old.since, old.on
  end
  if L.on == nil then L.on = true end
  -- itemID -> { n = name, fx = effect text, w = slot kind, s = secs, mh, oh, sp, rg, tk,
  --   spd/spdN = printed weapon speed while worn (its own for a weapon, else your main hand's), sum/count,
  --   sw/swN = your real swing speed (hasted, or the form's), sum/count, for reference }
  L.items = L.items or {}
  L.spells = L.spells or {}  -- spell name -> { n, id, sc, c, cand = {itemID = true}, ng, kinds = {}, dmg, dn, crit, tick, up }
  L.party = L.party or {}    -- itemID -> { [player] = { p, h, s, t, when } }
  L.since = L.since or time()
  -- 0.1.0 stored the real swing speed in spd: move it to sw (spd is now the weapon's printed speed)
  if (L.ver or 1) < 2 then
    for _, r in pairs(L.items) do r.sw, r.swN, r.spd, r.spdN = r.spd or 0, r.spdN or 0, 0, 0 end
    L.ver = 2
  end
  return L
end
local function on() local l = log(); return l and l.on end

---------------------------------------------------------------------------
-- what you're wearing
---------------------------------------------------------------------------
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local worn = {}      -- itemID -> { slot = n, fx = bool, melee = bool, struck = bool }
local wornFx = {}    -- itemIDs with an on-hit / when-struck effect
local hand = {}      -- 16 / 17 / 18 -> itemID
local mhSpeed        -- the main-hand weapon's printed speed
local wornDirty, retry = true, false

-- the effect lines of a worn item ("Chance on hit: ...", "Equip: 2% chance on melee hit ...", "... when struck ...")
local scan
local function tooltipLines(slot)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
    local ok, d = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
    if ok and d and d.lines then
      for _, l in ipairs(d.lines) do if l.leftText then out[#out + 1] = l.leftText end end
    end
  end
  if #out == 0 then
    if not scan then
      scan = CreateFrame("GameTooltip", "TopRamenProcsScanTip", nil, "GameTooltipTemplate")
    end
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    pcall(scan.SetInventoryItem, scan, "player", slot)
    for i = 1, scan:NumLines() do
      local fs = _G["TopRamenProcsScanTipTextLeft" .. i]
      local t = fs and fs:GetText()
      if t then out[#out + 1] = t end
    end
    scan:Hide()
  end
  return out
end
-- returns fx = { { "hit" | "struck", text }, ... } or nil, whether part of the text was still loading,
-- and a weapon's printed speed ("Speed 2.90"), which is what a proc's chance per hit is based on
local function itemEffects(slot)
  local lines = tooltipLines(slot)
  local fx, pending, wspd = {}, #lines < 2, nil
  for _, line in ipairs(lines) do
    local l = line:lower()
    wspd = wspd or tonumber(l:match("^speed (%d+%.?%d*)$") or l:match("%s+speed (%d+%.?%d*)$"))
    if l:find("retrieving") or l:match("^chance on hit:%s*$") or l:match("^equip:%s*$") then pending = true end
    if not l:match("^%(%d%) set:") then
      local kind, body = l:match("^(equip): (.*)$")
      if not kind then kind, body = l:match("^(chance on hit): (.*)$") end
      if kind == "chance on hit" then
        fx[#fx + 1] = { "hit", body }
      elseif kind == "equip" and (body:find("chance on") or body:find("on hit") or body:find("on melee hit")) and not body:find("^improves") then
        fx[#fx + 1] = { body:find("when struck") and "struck" or "hit", body }
      elseif kind == "equip" and body:find("when struck") then
        fx[#fx + 1] = { "struck", body }
      end
    end
  end
  return (#fx > 0) and fx or nil, pending, wspd
end

local function newRec() return { s = 0, mh = 0, oh = 0, sp = 0, rg = 0, tk = 0, spd = 0, spdN = 0, sw = 0, swN = 0 } end
local function itemRec(id)
  local l = log()
  local r = l.items[id]
  if not r then r = newRec(); l.items[id] = r end
  r.sw = r.sw or 0; r.swN = r.swN or 0
  return r
end

local function readWorn()
  wornDirty = false
  wipe(worn); wipe(wornFx); wipe(hand); mhSpeed = nil
  local missing = false
  for _, slot in ipairs(SLOTS) do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local fx, pending, wspd = itemEffects(slot)
      local w = { slot = slot, wspd = (slot >= 16) and wspd or nil }
      if slot == 16 then mhSpeed = wspd end
      local text = {}
      for _, f in ipairs(fx or {}) do
        if f[1] == "hit" then w.fx = true; if (f[2] or ""):find("melee") then w.melee = true end
        elseif f[1] == "struck" then w.fx = true; w.struck = true end
        text[#text + 1] = f[2]
      end
      if pending then missing = true end
      worn[id] = w
      if slot >= 16 then hand[slot] = id end
      if w.fx then wornFx[id] = true end
      if log() then
        local r = itemRec(id)
        local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)) or link:match("%[(.-)%]")
        if name then r.n = name end
        if #text > 0 then r.fx = table.concat(text, " / ") end
        r.w = slot == 16 and "mh" or slot == 17 and "oh" or slot == 18 and "rg" or (w.struck and not w.melee and "tk") or "any"
      end
    end
  end
  -- an item's text can still be loading: look again shortly
  if missing and not retry and C_Timer then
    retry = true
    C_Timer.After(3, function() retry = false; wornDirty = true end)
  end
end
local function wornNow() if wornDirty then readWorn() end return worn end

---------------------------------------------------------------------------
-- time in combat
---------------------------------------------------------------------------
local fightStart -- GetTime() when this stretch of combat (with this gear) began
local function inCombat() return fightStart ~= nil end
local function flushTime()
  if not fightStart or not log() then return end
  local t = now()
  local dt = t - fightStart
  fightStart = t
  if dt <= 0 or dt > 3600 then return end -- clock oddities
  for id in pairs(wornNow()) do local r = itemRec(id); r.s = r.s + dt end
end

---------------------------------------------------------------------------
-- spells that are yours, not gear
---------------------------------------------------------------------------
local cast = {}       -- names of spells you cast (abilities, potions, on-use items)
local known = {}      -- name -> true / false (cached spellbook check)
local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function isKnown(name, id)
  local k = known[name]
  if k ~= nil then return k end
  k = false
  local function knows(sid)
    if not sid or sid == 0 then return false end
    return (IsPlayerSpell and IsPlayerSpell(sid)) or (IsSpellKnown and IsSpellKnown(sid)) or false
  end
  if knows(id) then k = true
  else
    -- looking a spell up by name only finds spells in your spellbook
    local sid
    if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(name); sid = i and i.spellID
    elseif GetSpellInfo then sid = select(7, GetSpellInfo(name)) end
    if knows(sid) then k = true end
  end
  known[name] = k
  return k
end
local function ignored(name)
  local l = name:lower()
  for _, p in ipairs(IGNORE) do if l:find(p) then return true end end
  return false
end
local function notGear(name, id) return cast[name] or isKnown(name, id) or ignored(name) end

---------------------------------------------------------------------------
-- counting
---------------------------------------------------------------------------
local last = {}   -- spell name -> GetTime() of the last counted proc
local upStart = {} -- spell name -> GetTime() a proc buff went up on you

local function hit(kind)  -- a hit that could trigger a proc
  for id, w in pairs(wornNow()) do
    local r = itemRec(id)
    if kind == "mh" then
      if w.slot ~= 17 and w.slot ~= 18 then r.mh = r.mh + 1 end
    elseif kind == "oh" then
      if w.slot ~= 16 and w.slot ~= 18 then r.oh = r.oh + 1 end
    elseif kind == "sp" then
      if w.slot ~= 17 and w.slot ~= 18 then r.sp = r.sp + 1 end
    elseif kind == "rg" then
      if w.slot == 18 or w.slot < 16 then r.rg = r.rg + 1 end
    elseif kind == "tk" then
      r.tk = r.tk + 1
    end
  end
end

local function proc(name, id, school, kind, amount, crit)
  if not name or name == "" or notGear(name, id) then return end
  local l = log()
  local s = l.spells[name]
  if not s then s = { n = name, c = 0, kinds = {}, dmg = 0, dn = 0, crit = 0, tick = 0, up = 0 }; l.spells[name] = s end
  if id and id > 0 then s.id = id end
  if school and school > 0 then s.sc = school end
  if amount and amount > 0 then
    s.dmg = s.dmg + amount; s.dn = s.dn + 1
    if crit then s.crit = s.crit + 1 end
  end
  local t = now()
  if last[name] and t - last[name] < DEDUPE then return end -- same proc, another target or another part of it
  last[name] = t
  s.c = s.c + 1
  s.kinds[kind] = (s.kinds[kind] or 0) + 1
  if s.ng then return end
  -- elimination: only items with an effect you're wearing right now could have done it
  wornNow()
  if not s.cand then
    s.cand = {}
    for iid in pairs(wornFx) do s.cand[iid] = true end
  else
    for iid in pairs(s.cand) do if not wornFx[iid] then s.cand[iid] = nil end end
  end
  if next(s.cand) == nil then s.ng = true; s.cand = nil end
end

-- the item a spell belongs to: name match first, then the last one standing
local function owner(s)
  local l = log()
  local lname = s.n:lower()
  for id, r in pairs(l.items) do
    if r.fx and ((r.n and r.n:lower() == lname) or r.fx:lower():find(lname, 1, true)) then return id, "name" end
  end
  for id, r in pairs(l.items) do
    if r.n and r.fx and r.n:lower():find(lname, 1, true) then return id, "name" end
  end
  if s.ng or not s.cand then return nil end
  local only, n = nil, 0
  for id in pairs(s.cand) do only = id; n = n + 1 end
  if n == 1 then return only, "only" end
  -- more than one: the effect text names the same school (e.g. "Nature damage")
  if s.sc and s.sc > 1 then
    local pick, m = nil, 0
    for id in pairs(s.cand) do
      local r = l.items[id]
      local txt = r and r.fx and r.fx:lower() or ""
      for word, code in pairs(SCHOOL) do
        if code == s.sc and txt:find(word .. " damage") then pick = id; m = m + 1; break end
      end
    end
    if m == 1 then return pick, "school" end
  end
  return nil
end
ns.ProcOwner = owner

---------------------------------------------------------------------------
-- the combat log
---------------------------------------------------------------------------
local me
local MELEE_SCHOOL = 1
local function onCLEU()
  if not on() then return end
  local _, sub, _, src, _, _, _, dst, _, _, _, a12, a13, a14, a15, _, _, _, _, a19, a20, a21 = CombatLogGetCurrentEventInfo()
  me = me or (UnitGUID and UnitGUID("player"))
  if src ~= me and dst ~= me then return end
  if not inCombat() then
    -- a proc buff can fall off after combat: still count its uptime
    if sub == "SPELL_AURA_REMOVED" and dst == me and a13 and upStart[a13] then
      local s = log().spells[a13]
      if s then s.up = s.up + (now() - upStart[a13]) end
      upStart[a13] = nil
    end
    return
  end
  if src == me then
    if sub == "SWING_DAMAGE" then
      if dst ~= me then hit(a21 and "oh" or "mh") end
      if not a21 then
        -- the speed a proc's chance is based on: the weapon's printed speed (its own for a weapon, else your
        -- main hand's), not how fast you really swing (Cat and Bear Form swing fast but roll the weapon's chance)
        local real = UnitAttackSpeed and UnitAttackSpeed("player")
        for id, w in pairs(wornNow()) do
          local r = itemRec(id)
          local base = w.wspd or mhSpeed
          if base and base > 0 then r.spd = r.spd + base; r.spdN = r.spdN + 1 end
          if real and real > 0 then r.sw = r.sw + real; r.swN = r.swN + 1 end
        end
      end
    elseif sub == "RANGE_DAMAGE" then
      hit("rg")
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED" then
      local name, id, school = a13, a12, a14
      if isKnown(name, id) or cast[name] then
        if sub == "SPELL_DAMAGE" and school == MELEE_SCHOOL then hit("sp") end
      else
        proc(name, id, school, "dmg", sub == "SPELL_DAMAGE" and a15 or 0, sub == "SPELL_DAMAGE" and a21)
      end
    elseif sub == "SPELL_PERIODIC_DAMAGE" then
      local s = log().spells[a13]
      if s and a15 then s.tick = s.tick + a15 end
    elseif sub == "SPELL_EXTRA_ATTACKS" then
      proc(a13, a12, a14, "extra")
    elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
      proc(a13, a12, a14, a15 == "BUFF" and "buff" or "debuff")
      if dst == me and a15 == "BUFF" and log().spells[a13] and not upStart[a13] then upStart[a13] = now() end
    elseif sub == "SPELL_AURA_REMOVED" then
      if dst == me and upStart[a13] then
        local s = log().spells[a13]
        if s then s.up = s.up + (now() - upStart[a13]) end
        upStart[a13] = nil
      end
    elseif sub == "SPELL_HEAL" then
      proc(a13, a12, a14, "heal", a15)
    elseif sub == "SPELL_ENERGIZE" then
      proc(a13, a12, a14, "energize")
    end
  end
  if dst == me and src ~= me and sub == "SWING_DAMAGE" then hit("tk") end
end

local export

---------------------------------------------------------------------------
-- the report
---------------------------------------------------------------------------
local function hitsFor(r)
  if r.w == "mh" then return r.mh + r.sp, "hits with it"
  elseif r.w == "oh" then return r.oh, "off-hand hits"
  elseif r.w == "rg" then return r.rg, "ranged hits"
  elseif r.w == "tk" then return r.tk, "hits taken" end
  return r.mh + r.oh + r.sp, "melee hits"
end
ns.ProcHitsFor = hitsFor

local function fmtTime(s)
  if s >= 3600 then return string.format("%dh %02dm", s / 3600, (s % 3600) / 60) end
  if s >= 60 then return string.format("%dm", s / 60) end
  return string.format("%ds", s)
end
local function pct(x) return string.format(x < 0.1 and "%.2f%%" or "%.1f%%", x * 100) end

-- what Gear assumes now, from the tooltip: a stated % chance, or 1 proc per minute
-- the weapon speed a proc's chance is based on, while this item was worn (nil if never seen)
local function baseSpeed(r) return (r.spdN or 0) > 0 and r.spd / r.spdN or nil end
ns.BaseSpeed = baseSpeed
-- what Top Ramen Gear assumes (same rule as its scoring, Gear 1.21.2): a stated % chance, else 1 proc per
-- minute = the weapon's printed speed / 60 per hit (2.6 if no weapon speed was seen)
local function assumed(r)
  local d = (r.fx or ""):lower()
  local chance = tonumber(d:match("proc chance: (%d+%.?%d*)%%") or d:match("(%d+%.?%d*)%% chance"))
  if chance and chance > 0 then return chance / 100, "stated " .. chance .. "%" end
  local spd = baseSpeed(r)
  return (spd or 2.6) / 60, string.format("1 per minute at weapon speed %.2f", spd or 2.6)
end
ns.Assumed = assumed

-- one line per item: { id, r, procs, spells, hits, perMin, perHit, ppm }
function ns.ProcRows()
  local l = log()
  if not l then return {} end
  flushTime()
  local byItem = {}
  for _, s in pairs(l.spells) do
    local id = owner(s)
    if id then
      byItem[id] = byItem[id] or { procs = 0, spells = {} }
      byItem[id].procs = byItem[id].procs + s.c
      byItem[id].spells[#byItem[id].spells + 1] = s
    end
  end
  local rows = {}
  for id, r in pairs(l.items) do
    if r.fx and r.s > 0 then
      local b = byItem[id] or { procs = 0, spells = {} }
      local h = hitsFor(r)
      local row = { id = id, r = r, procs = b.procs, spells = b.spells, hits = h, perMin = b.procs / r.s * 60 }
      row.perHit = h > 0 and b.procs / h or nil
      -- PPM the way the game defines it: chance per hit = PPM x weapon speed / 60
      local spd = baseSpeed(r)
      if row.perHit and spd and r.w ~= "tk" then row.ppm = row.perHit * 60 / spd end
      rows[#rows + 1] = row
    end
  end
  table.sort(rows, function(a, b) if a.procs ~= b.procs then return a.procs > b.procs end return a.r.s > b.r.s end)
  return rows
end

local function partyLine(id)
  local p = log().party[id]
  if not p then return nil end
  local pr, h, n = 0, 0, 0
  for _, v in pairs(p) do pr = pr + (v.p or 0); h = h + (v.h or 0); n = n + 1 end
  if n == 0 or h == 0 then return nil end
  return string.format("party: %d procs in %d hits from %d %s (%s per hit)", pr, h, n, n == 1 and "player" or "players", pct(pr / h))
end

local function report(all)
  local l = log()
  local rows = ns.ProcRows()
  local total = 0
  for _, r in pairs(l.items) do if r.s > total then total = r.s end end
  say("proc log" .. (l.on and "" or (RED .. " (paused: /trp on)|r")) .. GREY .. " since " .. date("%d %b", l.since) .. "|r")
  if #rows == 0 then
    say("  nothing yet. Wear an item with a \"Chance on hit\" effect and fight; it counts in the background.")
  end
  for _, row in ipairs(rows) do
    local r = row.r
    local _, hitWord = hitsFor(r)
    local early = row.procs < MIN_PROCS and (GREY .. " (early, keep going)|r") or ""
    local line = string.format("  %s%s|r: %d procs in %s worn, %d %s", GOLD, r.n or ("item " .. row.id), row.procs, fmtTime(r.s), row.hits, hitWord)
    say(line .. early)
    if row.procs > 0 then
      local a, aw = assumed(r)
      local s = string.format("     %.2f per minute", row.perMin)
      if row.perHit then s = s .. ", " .. pct(row.perHit) .. " per hit" end
      if row.ppm then s = s .. string.format(" (about %.1f PPM)", row.ppm) end
      if row.perHit then
        local ratio = row.perHit / a
        local col = ratio > 1.25 and GREEN or ratio < 0.8 and RED or GREY
        s = s .. GREY .. "; Gear assumes " .. pct(a) .. " (" .. aw .. ")|r " .. col .. string.format("x%.1f", ratio) .. "|r"
      end
      say(s)
      local names = {}
      for _, sp in ipairs(row.spells) do names[#names + 1] = sp.n end
      say(GREY .. "     from: " .. table.concat(names, ", ") .. "|r")
    end
    local pl = partyLine(row.id)
    if pl then say(GREY .. "     " .. pl .. "|r") end
  end
  -- procs not tied to an item yet
  local loose = {}
  for _, s in pairs(l.spells) do
    if not owner(s) and (all or not s.ng) then loose[#loose + 1] = s end
  end
  table.sort(loose, function(a, b) return a.c > b.c end)
  if #loose > 0 then
    say(all and "  procs not from an item:" or "  not matched to an item yet (change one piece of gear and it sorts itself out):")
    for i, s in ipairs(loose) do
      if i > 8 and not all then say(GREY .. "     ... " .. (#loose - 8) .. " more (/trp report all)|r"); break end
      local c = {}
      for id in pairs(s.cand or {}) do c[#c + 1] = (l.items[id] and l.items[id].n) or tostring(id) end
      local from = s.ng and "not gear" or (#c > 0 and ("could be " .. table.concat(c, " or ") .. ", or a talent") or "?")
      say(GREY .. string.format("     %s: %d (%s)", s.n, s.c, from) .. "|r")
    end
  end
  say(GREY .. "  /trp opens the window · /trp help|r")
end

---------------------------------------------------------------------------
-- sharing with the group and exporting
---------------------------------------------------------------------------
local PREFIX = "TRProcs"
local function short(name) return name and name:match("^([^%-%s]+)") end -- "Name-Realm" / "Name Something" -> "Name"
local function myName() return short(UnitName and UnitName("player")) or "me" end
local function channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
     and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end
function ns.PartySend(msg)
  local ch = channel()
  local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not ch or not fn then return end
  local ok, res = pcall(fn, PREFIX, msg, ch)
  if not (ok and (res == nil or res == true or res == 0)) then
    for _, other in ipairs({ "INSTANCE_CHAT", "PARTY", "RAID" }) do
      if other ~= ch then
        ok, res = pcall(fn, PREFIX, msg, other)
        if ok and (res == nil or res == true or res == 0) then break end
      end
    end
  end
end
function ns.ShareProcs()
  if not channel() then say("you're not in a group"); return end
  local rows = ns.ProcRows()
  local n = 0
  for _, row in ipairs(rows) do
    if row.hits > 0 then
      n = n + 1
      local msg = string.format("P|%d|%d|%d|%d|%s", row.id, row.procs, row.hits, math.floor(row.r.s + 0.5), row.r.w or "any")
      if C_Timer then C_Timer.After(0.3 * n, function() ns.PartySend(msg) end) else ns.PartySend(msg) end
    end
  end
  say(n > 0 and ("sending " .. n .. " items to your group") or "nothing to share yet")
end

function ns.OnProcMessage(who, msg)
  local id, p, h, s = msg:match("^P|(%d+)|(%d+)|(%d+)|(%d+)")
  who = short(who)
  if not id or not who or not log() or who == myName() then return end
  id = tonumber(id)
  L.party[id] = L.party[id] or {}
  L.party[id][who] = { p = tonumber(p), h = tonumber(h), s = tonumber(s), when = time() }
  if not L.items[id] then
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
    L.items[id] = newRec(); L.items[id].n = name
  end
end

function ns.ExportText() return export() end
function export()
  local l = log()
  local _, class = UnitClass("player")
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local out = { "# Top Ramen Procs log v" .. ((meta and meta("TopRamenProcs", "Version")) or "?")
                .. " | " .. (class or "?") .. " level " .. (UnitLevel and UnitLevel("player") or "?") .. " | since " .. date("%Y-%m-%d", l.since),
                "# item|name|slot|secs|hits|procs|perHit|ppm|weaponSpeed|swingSpeed|spells (name:count:dmg:ticks:crits:uptime)|effect" }
  for _, row in ipairs(ns.ProcRows()) do
    local sp = {}
    for _, s in ipairs(row.spells) do
      sp[#sp + 1] = string.format("%s:%d:%d:%d:%d:%d", s.n, s.c, s.dmg, s.tick, s.crit, s.up)
    end
    local bs = baseSpeed(row.r)
    local sw = (row.r.swN or 0) > 0 and row.r.sw / row.r.swN or nil
    out[#out + 1] = string.format("%d|%s|%s|%d|%d|%d|%.4f|%s|%s|%s|%s|%s", row.id, row.r.n or "?", row.r.w or "?", row.r.s, row.hits, row.procs,
      row.perHit or 0, row.ppm and string.format("%.2f", row.ppm) or "", bs and string.format("%.2f", bs) or "",
      sw and string.format("%.2f", sw) or "", table.concat(sp, ","), ((row.r.fx or ""):gsub("|", "/")))
    for who, v in pairs(l.party[row.id] or {}) do
      out[#out + 1] = string.format("#  party %s: %d procs, %d hits, %d secs", who, v.p or 0, v.h or 0, v.s or 0)
    end
  end
  out[#out + 1] = "# not matched"
  for _, s in pairs(l.spells) do
    if not owner(s) then
      local c = {}
      for id in pairs(s.cand or {}) do c[#c + 1] = id end
      out[#out + 1] = string.format("#  %s|%d|%s", s.n, s.c, s.ng and "not gear" or table.concat(c, "/"))
    end
  end
  return table.concat(out, "\n")
end

function ns.Reset()
  local l = log()
  wipe(l.items); wipe(l.spells); wipe(l.party); wipe(last); wipe(upStart)
  l.since = time(); wornDirty = true
  if fightStart then fightStart = now() end
end
function ns.SetOn(v)
  local l = log()
  if not v then flushTime(); l.on = false; fightStart = nil
  else
    l.on = true
    if UnitAffectingCombat and UnitAffectingCombat("player") then fightStart = now() end
  end
end
function ns.IsOn() return on() end
function ns.Since() local l = log(); return l and l.since end
function ns.Loose(all)
  local l, out = log(), {}
  if not l then return out end
  for _, s in pairs(l.spells) do
    if not owner(s) and (all or not s.ng) then
      local c = {}
      for id in pairs(s.cand or {}) do c[#c + 1] = (l.items[id] and l.items[id].n) or tostring(id) end
      out[#out + 1] = { s = s, from = s.ng and "not gear" or (#c > 0 and ("could be " .. table.concat(c, " or ") .. ", or a talent") or "?") }
    end
  end
  table.sort(out, function(a, b) return a.s.c > b.s.c end)
  return out
end
function ns.PartyLine(id) return partyLine(id) end
ns.fmtTime, ns.pct = fmtTime, pct

function ns.ProcCommand(arg)
  local l = log()
  if not l then return end
  arg = (arg or ""):lower()
  if arg == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif arg == "help" or arg == "?" then
    say("/trp opens the window. /trp report prints it in chat (/trp report all also lists procs that aren't from gear).")
    say("/trp share sends your counts to your group, /trp export copies everything, /trp reset clears it, /trp off / on pauses or resumes.")
  elseif arg == "reset" then
    ns.Reset(); say("proc log cleared")
  elseif arg == "off" then
    ns.SetOn(false); say("proc logger paused (/trp on to start again)")
  elseif arg == "on" then
    ns.SetOn(true); say("proc logger on")
  elseif arg == "share" then
    ns.ShareProcs()
  elseif arg == "export" then
    if ns.ShowExport then ns.ShowExport(export()) end
  elseif arg == "report" or arg == "report all" or arg == "all" then
    report(arg ~= "report")
  else
    say("unknown command. /trp help lists them.")
  end
  if ns.Refresh then ns.Refresh() end
end

SLASH_TOPRAMENPROCS1 = "/trp"
SLASH_TOPRAMENPROCS2 = "/trprocs"
SLASH_TOPRAMENPROCS3 = "/topramenprocs"
SlashCmdList.TOPRAMENPROCS = function(msg) ns.ProcCommand((msg or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("UNIT_SPELLCAST_SENT")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    onCLEU()
  elseif event == "CHAT_MSG_ADDON" then
    -- prefix, message, channel, sender
    if a1 == PREFIX and type(a2) == "string" and a2:sub(1, 2) == "P|" then ns.OnProcMessage(a4, a2); if ns.Refresh then ns.Refresh() end end
  elseif event == "PLAYER_LOGIN" then
    ns.ready = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    log(); me = UnitGUID and UnitGUID("player")
    if on() and UnitAffectingCombat and UnitAffectingCombat("player") then fightStart = now() end
  elseif event == "PLAYER_REGEN_DISABLED" then
    if on() then fightStart = now() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    flushTime(); fightStart = nil
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    flushTime(); wornDirty = true
  elseif event == "SPELLS_CHANGED" then
    wipe(known)
  elseif event == "UNIT_SPELLCAST_SENT" and a1 == "player" then
    -- unit, target, castGUID, spellID: only spells you start yourself (abilities, potions, on-use items)
    local name = a4 and spellName(a4)
    if name then cast[name] = true end
  end
end)
