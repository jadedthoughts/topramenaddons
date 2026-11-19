-- Top Ramen Gear: talents
-- Reads your talents and their descriptions at your current rank, and works out what they do to
-- item stats: "+20% Stamina in Bear Form" makes each point of Stamina on gear worth 20% more for Bear,
-- "+3% chance to hit" lowers how much hit rating you still need. Nothing is hard-coded, so Forever's
-- own talent changes are picked up from the game's text.
local _, ns = ...

local GOLD, GREY, GREEN = "|cffe0b04a", "|cff9d9d9d", "|cff40d040"

-- what talents add: mods.bear.sta = 0.2 means +20% Stamina from gear for Bear
ns.TalentMods = { bear = {}, cat = {}, balance = {}, resto = {}, hit = 0, spellHit = 0, found = {}, all = {} }

local STATWORDS = {
  { "stamina", "sta" }, { "strength", "str" }, { "agility", "agi" }, { "intellect", "int" }, { "spirit", "spi" },
  { "armor contribution from", "armor" }, { "armor from items", "armor" }, { "armor value from items", "armor" },
  { "total health", "sta" }, -- Survivalist: +10% health is +10% from Stamina too
}

local scanTip
local function tipLines(tab, index)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "TopRamenGearTalentScan", UIParent, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  local ok = pcall(scanTip.SetTalent, scanTip, tab, index)
  if not ok then return {} end
  local out = {}
  for i = 1, scanTip:NumLines() do
    local fs = _G["TopRamenGearTalentScanTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and t ~= "" then out[#out + 1] = t end
  end
  scanTip:Hide()
  return out
end

-- the text of a talent's current rank (stops before "Next rank:")
local function currentText(lines)
  local parts = {}
  for i = 2, #lines do
    local l = lines[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local low = l:lower()
    if low:find("^next rank") then break end
    if not low:find("^rank %d") and not low:find("^requires") and not low:find("^click to learn") then
      parts[#parts + 1] = l
    end
  end
  return table.concat(parts, " ")
end

-- turn a description into effects: { {forms = {bear=true}, stat = "sta", pct = 20}, ..., hit = 3 }
function ns.ParseTalentText(text)
  local effects, hit, spellHit = {}, 0, 0
  local low = " " .. (text or ""):lower() .. " "
  -- an ability that turns you into a form (Moonkin Form): its bonuses are flat or form-only
  if low:find("^ shapeshift into") then return effects, hit, spellHit end
  -- your own hit chance (not lowering the enemy's): spell hit if the sentence is about spells
  for sentence in low:gmatch("[^%.]+") do
    local h = sentence:match("your chance to hit[^%%]-by (%d+)%%") or sentence:match("your hit chance[^%%]-by (%d+)%%")
    -- "reduces/decreases" before the hit wording means it's about the enemy's hit; only some abilities = not gear hit
    local hitAt = sentence:find("hit") or 1
    local before = sentence:sub(1, hitAt)
    if h and (before:find("decreas") or before:find("reduc") or sentence:find("trap") or sentence:find("feign death")
      or sentence:find("off%-hand")) then h = nil end
    -- Forever's hit is one stat for attacks and spells, so a plain "chance to hit" talent counts for both
    if h and not sentence:find("spell") then spellHit = spellHit + tonumber(h) end
    if h then
      if sentence:find("spell") then spellHit = spellHit + tonumber(h) else hit = hit + tonumber(h) end
    end
  end
  -- Defense from talents (Anticipation: "Increases your Defense Skill by 20") lowers what a tank needs from gear
  local dskill = low:match("increases your defense skill by (%d+)") or low:match("increases your defense by (%d+)")
  if dskill then effects[#effects + 1] = { forms = { tank = true }, stat = "defskill", pct = tonumber(dskill) } end
  -- Intellect / Spirit turned into power (Careful Aim, Mental Dexterity, Mental Quickness, Champion of the Light,
  -- Natural Instinct, Spiritual Guidance): makes that stat worth what it turns into
  local conv = false
  local i2a = low:match("attack power by (%d+)%% of your intellect") or low:match("attack power by an amount equal to (%d+)%% of your intellect")
  if i2a then effects[#effects + 1] = { forms = {}, stat = "int2ap", pct = tonumber(i2a) }; conv = true end
  for sentence in low:gmatch("[^%.]+") do
    for clause in (sentence .. " and "):gmatch("(.-) and ") do
      local p, stat = clause:match("by up to (%d+)%% of your t?o?t?a?l? ?(%a+)")
      if not p then p, stat = clause:match("by (%d+)%% of your t?o?t?a?l? ?(%a+)") end
      if p and (stat == "intellect" or stat == "spirit") and not clause:find("attack power") and not clause:find("armor") then
        local from = stat == "intellect" and "int" or "spi"
        local heal = clause:find("heal") or sentence:find("damage and healing") and true
        local dmg = clause:find("damage") or sentence:find("damage and healing") and true
        if heal then effects[#effects + 1] = { forms = {}, stat = from .. "2heal", pct = tonumber(p) }; conv = true end
        if dmg then effects[#effects + 1] = { forms = {}, stat = from .. "2sp", pct = tonumber(p) }; conv = true end
      end
    end
  end
  -- extra critical strike damage on abilities makes crit worth more (about half your damage is from abilities)
  local cd
  for sentence in low:gmatch("[^%.]+") do
    local part, v = sentence:match("(critical strike damage bonus[^%%]-by (%d+)%%)")
    if not v then part, v = sentence:match("(critical strike healing bonus[^%%]-by (%d+)%%)") end
    if not v then part, v = sentence:match("(critical strike damage[^%%]-by (%d+)%%)") end
    -- Hunters: ranged crit damage (Mortal Shots) helps the ranged specs, melee (Predator's Edge) Survival
    local hunterDone = false
    if v and sentence:find("ranged") and not sentence:find("melee") then
      effects[#effects + 1] = { forms = { bm = true, mm = true }, stat = "crit", pct = tonumber(v) / 2, critDmg = tonumber(v) }
      hunterDone = true
    elseif v and sentence:find("melee") and sentence:find("abilit") and not sentence:find("spell") and part and not part:find("melee") then
      effects[#effects + 1] = { forms = { sv = true }, stat = "crit", pct = tonumber(v) / 2, critDmg = tonumber(v) }
      hunterDone = true
    end
    if hunterDone then v = nil end
    -- Druids: melee ability crit damage (Natural Instinct) helps every spec
    if v and part:find("melee") and not part:find("spell") then cd = v
    -- spell crit damage (Vengeance, Shadowform, Elemental Fury, Ruin...): +100% to a 50% bonus doubles what
    -- spell crit is worth, for the class's caster specs
    elseif v and (part:find("spell") or sentence:find("spells")) and not part:find("melee") and not sentence:find("heal") then
      effects[#effects + 1] = { forms = { caster = true }, stat = "scrit", pct = tonumber(v), critDmgSpell = tonumber(v) }
    -- crit healing (Holy Power): healers
    elseif v and sentence:find("heal") then
      effects[#effects + 1] = { forms = { healer = true }, stat = "scrit", pct = tonumber(v) / 2, critDmgSpell = tonumber(v) }
    -- other abilities (Impale, Lethality): physical specs; about half the damage is from abilities
    elseif v and not sentence:find("ranged") and not sentence:find("spell") then
      effects[#effects + 1] = { forms = { melee = true, tank = true }, stat = "crit", pct = tonumber(v) / 2, critDmg = tonumber(v) }
    end
  end
  if cd then effects[#effects + 1] = { forms = {}, stat = "crit", pct = tonumber(cd) / 2, critDmg = tonumber(cd) } end
  -- split into clauses; a clause that only names a form ("while in bear") carries over to the next one
  local pending = {}
  for sentence in low:gmatch("[^%.]+") do
    for clause in (sentence .. " and "):gmatch("(.-) and ") do
      local forms = {}
      for k in pairs(pending) do forms[k] = true end
      if clause:find("bear") then forms.bear = true end
      if clause:find("cat") then forms.cat = true end
      local otherFormOnly = clause:find("moonkin") and not forms.bear and not forms.cat
      -- a short buff after something happens (Spirit Tap, Dark Inspiration) or a conversion read above isn't a
      -- permanent bonus on gear
      local temporary = sentence:find("for %d+ sec") or sentence:find("after killing") or sentence:find("each time")
        or (conv and (clause:find("of your") or false))
      local matched = (otherFormOnly or temporary) and true or false
      -- "all attributes" / "all stats": every primary stat
      local s0 = clause:find("all attributes", 1, true) or clause:find("all stats", 1, true)
      if s0 then
        local pct, after = clause:match("by (%d+)%%(.?.?.?.?)", s0)
        if pct and not (after or ""):find("^ of") then
          for _, k in ipairs({ "sta", "str", "agi", "int", "spi" }) do
            effects[#effects + 1] = { forms = forms, stat = k, pct = tonumber(pct) }
          end
          matched = true
        end
      end
      for _, sw in ipairs(matched and {} or STATWORDS) do
        local s = clause:find(sw[1], 1, true)
        if s then
          local pct, after = clause:match("by (%d+)%%(.?.?.?.?)", s)
          if not pct then pct, after = clause:match("(%d+)%%(.?.?.?.?)", s) end
          if pct and not (after or ""):find("^ of") then
            effects[#effects + 1] = { forms = forms, stat = sw[2], pct = tonumber(pct) }
            matched = true
            break
          end
        end
      end
      if matched then pending = {} else
        if clause:find("bear") then pending.bear = true end
        if clause:find("cat") then pending.cat = true end
      end
    end
    pending = {}
  end
  return effects, hit, spellHit
end

local function apply(mods, e)
  -- the effect's specs, kept to this character's class; none named = every spec of the class
  -- (e.g. "+10% Intellect"; a Hunter talent mentioning "cat" in some other word isn't a Cat Form bonus)
  local targets, mine = {}, {}
  for _, sp in ipairs(ns.ClassSpecs()) do mine[sp.key] = true end
  for k in pairs(e.forms) do if mine[k] then targets[#targets + 1] = k end end
  -- roles: "caster" / "healer" / "melee" / "tank" mean this class's specs with that role
  local named = next(e.forms) ~= nil
  for _, sp in ipairs(ns.ClassSpecs()) do
    local role = ns.Role(sp.key)
    if e.forms[role] and not mine[role] then
      local dup = false
      for _, t in ipairs(targets) do if t == sp.key then dup = true end end
      if not dup then targets[#targets + 1] = sp.key end
    end
  end
  -- named only roles/forms this class doesn't have (e.g. a Cat Form bonus for a Hunter): nothing to apply
  if named and #targets == 0 then
    local onlyRoles = true
    for k in pairs(e.forms) do if not (k == "caster" or k == "healer" or k == "melee" or k == "tank" or k == "ranged") then onlyRoles = false end end
    if onlyRoles then return end
  end
  if #targets == 0 then for _, sp in ipairs(ns.ClassSpecs()) do targets[#targets + 1] = sp.key end end
  for _, m in ipairs(targets) do
    mods[m] = mods[m] or {}
    mods[m][e.stat] = (mods[m][e.stat] or 0) + e.pct / 100
  end
end

-- Forever keeps talents in the traits system (like SimulationCraft reads them): the active spec
-- group's config, every node you've bought, its rank, and the description at that rank.
local function traitDescription(entryID, rank, spellID)
  -- the game's own tooltip for this talent at this rank
  if scanTip == nil then scanTip = CreateFrame("GameTooltip", "TopRamenGearTalentScan", UIParent, "GameTooltipTemplate") end
  if scanTip.SetTraitEntry then
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if pcall(scanTip.SetTraitEntry, scanTip, entryID, rank) and scanTip:NumLines() > 1 then
      local lines = {}
      for i = 1, scanTip:NumLines() do
        local fs = _G["TopRamenGearTalentScanTextLeft" .. i]
        local t = fs and fs:GetText()
        if t and t ~= "" then lines[#lines + 1] = t end
      end
      scanTip:Hide()
      local text = currentText(lines)
      if text ~= "" then return text, "tooltip" end
    end
  end
  -- otherwise the spell's description
  if spellID then
    local d = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)) or (GetSpellDescription and GetSpellDescription(spellID))
    if d and d ~= "" then return d, "spell" end
  end
  return "", "none"
end

local function readTraitTalents()
  if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil end
  local SI = C_SpecializationInfo
  local configID
  if SI and SI.GetCombatConfigIDForSpecGroup then
    local group = (SI.GetActiveSpecGroup and SI.GetActiveSpecGroup()) or (GetActiveSpecGroup and GetActiveSpecGroup()) or 1
    configID = SI.GetCombatConfigIDForSpecGroup(group)
  end
  if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then configID = C_ClassTalents.GetActiveConfigID() end
  if not configID then return nil end
  local info = C_Traits.GetConfigInfo(configID)
  if not info or not info.treeIDs then return nil end
  local out = {}
  for _, treeID in ipairs(info.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      if node and (node.ranksPurchased or 0) > 0 and node.activeEntry then
        local rank = node.currentRank or node.ranksPurchased
        local entryID = node.activeEntry.entryID
        local entry = C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo and C_Traits.GetDefinitionInfo(entry.definitionID)
        local spellID = def and (def.overriddenSpellID or def.spellID)
        local name = def and def.overrideName
        if (not name or name == "") and spellID then
          name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
        end
        local text, src = traitDescription(entryID, rank, spellID)
        out[#out + 1] = { name = name or ("talent " .. entryID), rank = rank, max = node.maxRanks or rank, text = text, src = src }
      end
    end
  end
  return out
end

-- the classic talent tabs (other clients)
local function readTabTalents()
  local nTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
  if nTabs == 0 then return nil end
  local out = {}
  for tab = 1, nTabs do
    for i = 1, (GetNumTalents(tab) or 0) do
      local name, _, _, _, rank, max = GetTalentInfo(tab, i)
      if name and (rank or 0) > 0 then
        out[#out + 1] = { name = name, rank = rank, max = max or rank, text = currentText(tipLines(tab, i)), src = "tab" }
      end
    end
  end
  return out
end

function ns.ScanTalents()
  local mods = { bear = {}, cat = {}, balance = {}, resto = {}, hit = 0, spellHit = 0, found = {}, all = {} }
  local ok, list = pcall(readTraitTalents)
  if not ok or not list then ok, list = pcall(readTabTalents) end
  if not ok then list = nil end
  for _, t in ipairs(list or {}) do
    mods.all[#mods.all + 1] = t
    local effects, hit, spellHit = ns.ParseTalentText(t.text)
    if #effects > 0 or hit > 0 or spellHit > 0 then
      for _, e in ipairs(effects) do apply(mods, e) end
      mods.hit = mods.hit + hit
      mods.spellHit = mods.spellHit + spellHit
      mods.found[#mods.found + 1] = { name = t.name, rank = t.rank, max = t.max, effects = effects, hit = hit, spellHit = spellHit }
    end
  end
  mods.scanned = list ~= nil
  ns.TalentMods = mods
  if ns.RefreshWindow then ns.RefreshWindow() end
  return mods
end

local function describe(e)
  local forms = {}
  if e.forms.bear then forms[#forms + 1] = "Bear" end
  if e.forms.cat then forms[#forms + 1] = "Cat" end
  if e.forms.balance and not e.critDmgSpell then forms[#forms + 1] = "Balance" end
  local names = { sta = "Stamina", str = "Strength", agi = "Agility", int = "Intellect", spi = "Spirit", armor = "Armor from items" }
  if e.critDmgSpell then return "+" .. e.critDmgSpell .. "% spell crit damage (spell crit worth +" .. e.pct .. "% for Balance)" end
  if e.critDmg then return "+" .. e.critDmg .. "% crit damage (crit rating worth +" .. e.pct .. "%)" end
  return "+" .. e.pct .. "% " .. (names[e.stat] or e.stat) .. (#forms > 0 and (" (" .. table.concat(forms, ", ") .. ")") or "")
end

-- a short summary for the Settings tab and /trg talents
function ns.TalentSummary()
  local m = ns.TalentMods
  if not m.scanned then return GREY .. "Talents haven't been read yet.|r" end
  if #m.found == 0 then return GREY .. "None of your talents change item stats.|r" end
  local parts = {}
  for _, t in ipairs(m.found) do
    local fx = {}
    for _, e in ipairs(t.effects) do fx[#fx + 1] = describe(e) end
    if t.hit > 0 then fx[#fx + 1] = "+" .. t.hit .. "% hit" end
    if (t.spellHit or 0) > 0 then fx[#fx + 1] = "+" .. t.spellHit .. "% spell hit" end
    parts[#parts + 1] = GREEN .. t.name .. "|r " .. GREY .. "(" .. t.rank .. "/" .. (t.max or t.rank) .. "): " .. table.concat(fx, ", ") .. "|r"
  end
  return table.concat(parts, "\n")
end

function ns.PrintTalents(all)
  local m = ns.ScanTalents()
  if all then
    print(GOLD .. "Top Ramen:|r every talent you've learned (" .. #m.all .. "):")
    for _, t in ipairs(m.all) do
      print("  " .. GREEN .. t.name .. "|r " .. t.rank .. "/" .. (t.max or t.rank) .. GREY .. " [" .. t.src .. "] " .. (t.text or ""):sub(1, 90) .. "|r")
    end
    return
  end
  print(GOLD .. "Top Ramen:|r talents that change item stats:")
  if not m.scanned then print("  " .. GREY .. "couldn't read talents on this client|r") return end
  if #m.found == 0 then print("  " .. GREY .. "none of your " .. #m.all .. " learned talents change item stats (/trg talents all lists them)|r") return end
  for line in ns.TalentSummary():gmatch("[^\n]+") do print("  " .. line) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local pending = false
ev:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  C_Timer.After(1, function()
    pending = false
    ns.AfterCombat("talents", function() pcall(ns.ScanTalents) end) -- wait for combat to end
  end)
end)
