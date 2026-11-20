-- Top Ramen Gear: upgrade lines on item tooltips
-- Hover any Druid-usable item: shows how much it gains or loses versus what you're wearing,
-- for Bear (1 target and Swipe on 3 targets) and Cat.
local _, ns = ...

local GOLD = "|cffe0b04a"
local GREEN, RED, GREY = "|cff40d040", "|cffff5050", "|cff9d9d9d"

-- slot group -> equipment slot ids it can replace
local INV = {
  head = { 1 }, neck = { 2 }, shoulder = { 3 }, chest = { 5 }, waist = { 6 }, legs = { 7 }, feet = { 8 }, wrist = { 9 },
  hands = { 10 }, finger = { 11, 12 }, trinket = { 13, 14 }, back = { 15 }, relic = { 18 }, ranged = { 18 }, shield = { 17 },
}

---------------------------------------------------------------------------
-- what you're wearing
---------------------------------------------------------------------------
local equipped, equippedLinks, equippedDirty = {}, {}, true

local function readEquipped()
  wipe(equipped); wipe(equippedLinks)
  local complete = true
  for slot = 1, 18 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      equippedLinks[link] = true
      local it = ns.ItemStats(link)
      if it then equipped[slot] = it
      elseif GetInventoryItemID("player", slot) then complete = false end
    end
  end
  -- weapon DPS and attack power, for extra-attack procs
  local mh = equipped[16]
  ns.CTX.wdps = mh and mh.st.wdps or 0
  -- attack power, armor, health: read out of combat only (they can be hidden while fighting); keep the last known numbers
  if not ns.InCombat() then
    local _, effArmor = ns.safe(UnitArmor, "player")
    local hp = ns.safe(UnitHealthMax, "player")
    local lvl = ns.Level()
    local itemArmor = 0
    for slot, it in pairs(equipped) do if it.st.armor then itemArmor = itemArmor + it.st.armor end end
    local formID = GetShapeshiftFormID and ns.safe(GetShapeshiftFormID)
    if effArmor and hp and lvl then
      ns.Live = { armor = effArmor, health = hp, level = lvl, itemArmor = itemArmor, inBear = (formID == 5 or formID == 8) }
    end
    -- crit chance per point of Agility, if the game will tell us (sanity-checked: 0.02% to 0.25% per point)
    if GetCritChanceFromAgility then
      local v = ns.safe(GetCritChanceFromAgility, "player")
      local agi = ns.safe(UnitStat, "player", 2)
      if v and v > 0 and v < 0.25 and v > 0.02 then ns.agiPct = v
      elseif v and agi and agi > 0 and v / agi > 0.02 and v / agi < 0.25 then ns.agiPct = v / agi end
    end
    local base, pos, neg = ns.safe(UnitAttackPower, "player")
    if base then ns.CTX.ap = base + (pos or 0) + (neg or 0) end
  end
  equippedDirty = not complete -- try again later if an item wasn't loaded yet
end

local function gear()
  if equippedDirty then readEquipped() end
  return equipped
end
ns.Gear = gear
function ns.MarkGearDirty() equippedDirty = true end

-- stat totals of everything worn except the given slots (for hit/expertise/defense caps)
local baseWithout
function ns.BaseWithout(skip) return baseWithout(skip) end
baseWithout = function(skip)
  local t = {}
  for slot, it in pairs(gear()) do
    if not skip[slot] then for k, v in pairs(it.st) do t[k] = (t[k] or 0) + v end end
  end
  return t
end

---------------------------------------------------------------------------
-- comparing a hovered item with what it would replace
---------------------------------------------------------------------------
-- Returns {old = {items}, new = {items}, base = totals, note = text} for the best way to wear the item.
local function plan(it, mode)
  local g = gear()
  local s = it.s
  if s == "weapon2h" then
    return { old = { g[16], g[17] }, new = { it }, base = baseWithout({ [16] = true, [17] = true }) }
  elseif s == "weapon1h" then
    local mh = g[16]
    if mh and mh.s == "weapon2h" then
      return { old = { mh }, new = { it }, base = baseWithout({ [16] = true, [17] = true }), note = "replacing your two-hander" }
    end
    return { old = { mh }, new = { it }, base = baseWithout({ [16] = true }) }
  elseif s == "offhand" or s == "offweapon" or s == "shield" then
    local mh = g[16]
    if mh and mh.s == "weapon2h" then return nil, "needs a one-hand weapon" end
    -- a weapon in the off hand hits for half: its DPS counts as off-hand DPS
    return { old = { ns.AsOffhand(g[17]) }, new = { ns.AsOffhand(it) }, base = baseWithout({ [17] = true }) }
  end
  local slots = INV[s]
  if not slots then return nil end
  if #slots == 1 then
    return { old = { g[slots[1]] }, new = { it }, base = baseWithout({ [slots[1]] = true }) }
  end
  -- rings and trinkets: replace whichever of the two is worse for this mode
  local best
  for _, slot in ipairs(slots) do
    local cur = g[slot]
    local base = baseWithout({ [slot] = true })
    local curScore = cur and ns.Score({ cur }, mode, base, 1) or 0
    if not best or curScore < best.curScore then
      best = { old = { cur }, new = { it }, base = base, curScore = curScore, slot = slot }
    end
  end
  return best
end

local function gain(it, mode, scen)
  local p, why = plan(it, mode)
  if not p then return nil, why end
  local new = ns.Score(p.new, mode, p.base, scen)
  local old = ns.Score(p.old, mode, p.base, scen)
  return new - old, p.note
end
ns.Gain = gain
-- the score of what the item would replace (0 for an empty slot), for the party roll window's percentages
function ns.RollOldScore(it, mode)
  local p = plan(it, mode)
  if not p then return 0 end
  return ns.Score(p.old, mode, p.base, 1)
end

local function fmt(d)
  if not d then return GREY .. "–|r" end
  if math.abs(d) < 0.05 then return GREY .. "±0|r" end
  local s = string.format("%+.1f", d)
  return (d > 0 and GREEN or RED) .. s .. "|r"
end

-- a small coloured dot for a spec (r, g, b from 0 to 1)
function ns.Dot(c, size)
  size = size or 8
  return string.format("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t", size, size, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- the lines to add for an item link (nil when nothing to show)
-- each line is a string, or { left, right } for a two-column line
function ns.TooltipLines(link)
  local db = ns.db
  if not db or not db.tooltip or not ns.isDruid then return nil end
  local it = ns.ItemStats(link)
  if not it then return nil end
  gear()
  local head = GOLD .. "Top Ramen|r"
  if equippedLinks[link] then return { { head, GREY .. "equipped|r" } } end
  local out, note = { head }, nil
  for _, sp in ipairs(ns.ClassSpecs()) do
    if db[sp.show] then
      local d, n = gain(it, sp.key, 1)
      if d == nil and n then return { { head, GREY .. n .. "|r" } } end
      note = note or n
      local right = fmt(d)
      if sp.key == "bear" and db.showBear3 then right = right .. GREY .. "  ·  3 targets|r " .. fmt((gain(it, "bear", 3))) end
      out[#out + 1] = { ns.Dot(sp.color) .. " |cffece6d8" .. sp.name .. "|r", right }
    end
  end
  if #out == 1 then return nil end
  local lvl = ns.Level()
  if lvl and (it.rl or 0) > lvl then out[#out + 1] = GREY .. "(you can wear it at level " .. it.rl .. ")|r" end
  if note then out[#out + 1] = GREY .. "(" .. note .. ")|r" end
  return out
end

---------------------------------------------------------------------------
-- hooking the tooltips
---------------------------------------------------------------------------
local function addTo(tooltip, link)
  if not link or tooltip.__trgLink == link then return end
  local ok, lines = pcall(ns.TooltipLines, link)
  if not ok or not lines then return end
  tooltip.__trgLink = link
  tooltip:AddLine(" ")
  for _, l in ipairs(lines) do
    if type(l) == "table" then tooltip:AddDoubleLine(l[1], l[2]) else tooltip:AddLine(l) end
  end
  tooltip:Show()
end

local function onSetItem(tooltip)
  if not tooltip.GetItem then return end
  local _, link = tooltip:GetItem()
  addTo(tooltip, link)
end
local function onCleared(tooltip) tooltip.__trgLink = nil end

local function hook()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then onSetItem(tooltip) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", onSetItem) end
    end
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then tt:HookScript("OnTooltipCleared", onCleared) end
  end
end

---------------------------------------------------------------------------
-- slash options: /trg help
---------------------------------------------------------------------------
local function say(msg) print(GOLD .. "Top Ramen:|r " .. msg) end
local function onOff(v) return v and "on" or "off" end

function ns.Command(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local db = ns.db
  if cmd == "help" or cmd == "?" then
    say("/trg - open the gear window")
    say("/trg dungeons - what's worth hunting in each dungeon")
    say("/trg talents - show which of your talents change item stats (/trg talents all lists every one)")
    say("/trg preview hunter - see Top Ramen as a Hunter would on this character (/trg preview off to stop; then /reload)")
    say("/trg equip - put on the best items from your bags for the spec picked in the window (same as the Equip best button)")
    say("/trg stats - show the level, form, armor and health the scores are based on")
    say("/trg usetalents - include your talents in scores on/off (now " .. onOff(db.useTalents ~= false) .. ")")
    say("/trg settings - open the settings (every option has a button there)")
    say("/trg export - export your gear for the website")
    say("/trg loot - export dungeon loot for the website")
    say("/trg tip - turn the tooltip lines on or off (now " .. onOff(db.tooltip) .. ")")
    say("/trg bear, /trg cat, /trg balance, /trg resto - show or hide that line (now Bear " .. onOff(db.showBear) .. ", Cat " .. onOff(db.showCat) .. ", Balance " .. onOff(db.showBalance) .. ", Restoration " .. onOff(db.showResto) .. ")")
    say("/trg 3t - show or hide the Bear 3-target score (now " .. onOff(db.showBear3) .. ")")
    say("/trg focus <-100 to 100> - Bear focus, survival (-) to threat (+) (now " .. (db.bearFocus or 0) .. ")")
    say("/trg rolltest - try the party loot window with an item from your bags")
    say("/trg hitcap <percent> - your own hit cap (now " .. ns.CapValue("capHit") .. "%; sets caps to Custom)")
    return true
  elseif cmd == "usetalents" then
    db.useTalents = not (db.useTalents ~= false)
    say("talents in scores " .. onOff(db.useTalents))
    if ns.RefreshWindow then ns.RefreshWindow() end
    return true
  elseif cmd == "stats" then
    ns.MarkGearDirty(); ns.Gear()
    local L, f = ns.Live, ns.BearForm()
    say("what the scores are based on right now:")
    say("  level " .. tostring(ns.Level() or "?") .. ", " .. f.name .. " (+" .. f.armorPct .. "% armor from items, +" .. f.health .. " health" .. (f.source == "spell" and ", read from the spell" or "") .. ")")
    if L then say("  armor " .. L.armor .. ", health " .. L.health .. (L.inBear and " (in bear form)" or " (not in bear form; form bonus added)") .. ", armor on gear " .. L.itemArmor)
    else say("  armor and health not read yet (they're read out of combat)") end
    local wb, wc = ns.Weights("bear"), ns.Weights("cat")
    say(string.format("  one point of item armor is worth %.3f for Bear (Stamina %.2f)", wb.armor or 0, wb.sta or 0))
    say(string.format("  one point of Agility is worth %.2f for Bear, %.2f for Cat (1%% crit per %.1f Agility)", wb.agi or 0, wc.agi or 0, 1 / ns.AgiPctPerPoint()))
    return true
  elseif cmd == "talents" or cmd == "talent" then
    ns.PrintTalents(arg == "all")
    return true
  elseif cmd == "dungeons" or cmd == "dungeon" or cmd == "dj" then
    if ns.OpenTab then ns.OpenTab("dungeons") end
    return true
  elseif cmd == "settings" or cmd == "options" or cmd == "config" then
    if ns.OpenSettings then ns.OpenSettings() end
    return true
  elseif cmd == "tip" or cmd == "tooltip" then
    db.tooltip = not db.tooltip; say("tooltip lines " .. onOff(db.tooltip)); return true
  elseif cmd == "bear" then
    db.showBear = not db.showBear; say("Bear line " .. onOff(db.showBear)); return true
  elseif cmd == "cat" then
    db.showCat = not db.showCat; say("Cat line " .. onOff(db.showCat)); return true
  elseif cmd == "balance" then
    db.showBalance = not db.showBalance; say("Balance line " .. onOff(db.showBalance)); return true
  elseif cmd == "preview" then
    local c = (arg or ""):upper()
    if c == "" or c == "OFF" then db.previewClass = nil
    elseif ns.SPECS[c] then db.previewClass = c
    else say("/trg preview hunter, /trg preview druid, or /trg preview off"); return true end
    if ns.ClearCache then ns.ClearCache() end
    if ns.ClearScores then ns.ClearScores() end
    say("preview: " .. (db.previewClass or "off") .. ". Type /reload to see it in the window.")
    return true
  elseif cmd == "equip" then
    ns.EquipBest(ns.CurrentMode()); return true
  elseif cmd == "resto" or cmd == "restoration" then
    db.showResto = not db.showResto; say("Restoration line " .. onOff(db.showResto)); return true
  elseif cmd == "3t" then
    db.showBear3 = not db.showBear3; say("Bear 3-target score " .. onOff(db.showBear3)); return true
  elseif cmd == "focus" then
    local n = tonumber(arg)
    if not n then say("Bear focus is " .. (db.bearFocus or 0) .. ". Use /trg focus -100 (all survival) to 100 (all threat).") return true end
    db.bearFocus = math.max(-100, math.min(100, math.floor(n / 10 + 0.5) * 10))
    say("Bear focus set to " .. db.bearFocus .. (db.bearFocus < 0 and " (survival)" or db.bearFocus > 0 and " (threat)" or " (balanced)"))
    return true
  elseif cmd == "rolltest" then
    if ns.RollTest then ns.RollTest(msg) end
    return true
  elseif cmd == "hitcap" then
    local n = tonumber(arg)
    if n then db.capHit = math.max(0, n); db.capTarget = "custom"; if ns.ClearScores then ns.ClearScores() end end
    say("hit cap " .. ns.CapValue("capHit") .. "%" .. (n and " (caps set to Custom)" or ""))
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- start-up and keeping up to date
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
ev:RegisterEvent("UNIT_ATTACK_POWER")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    ns.InitDB()
    local _, class = UnitClass("player")
    ns.isDruid = ns.ClassSupported() -- tooltip lines only for classes Top Ramen scores (Druid, Hunter)
    hook()
    ns.RegisterDialogueUI()
    equippedDirty = true
  elseif event == "PLAYER_LEVEL_UP" or event == "SPELLS_CHANGED" then
    if ns.ForgetBearForm then ns.ForgetBearForm() end -- e.g. you just learned Dire Bear Form
    -- what you can wear changes with level (Hunters: mail at 40)
    if event == "PLAYER_LEVEL_UP" and ns.ClearCache then ns.ClearCache() end
    equippedDirty = true
  elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_ATTACK_POWER" or event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_SHAPESHIFT_FORM" then
    equippedDirty = true
    if ns.RefreshWindow then ns.RefreshWindow() end
  end
end)

---------------------------------------------------------------------------
-- DialogueUI: it draws its own quest-reward tooltips, so register with its
-- item-evaluator API (the same one it uses for Pawn). This adds the Top Ramen
-- lines to its tooltips and drives its green "upgrade" arrow.
---------------------------------------------------------------------------
local function duiIsUpgrade(link)
  if not ns.db or not ns.isDruid then return nil, false end
  local ok, it = pcall(ns.ItemStats, link)
  if not ok then return false, true end
  if not it then
    if ns.ItemStatsKnownBad(link) then return false, true end -- not Druid gear
    return nil, false                                         -- not loaded yet: DialogueUI asks again
  end
  local up = false
  for _, sp in ipairs(ns.ClassSpecs()) do
    if ns.db[sp.show] then
      local okG, g = pcall(ns.Gain, it, sp.key, 1)
      if okG and g and g > 0.05 then up = true end
    end
  end
  return up, true
end

local function duiWriter(capture, link)
  local ok, lines = pcall(ns.TooltipLines, link)
  if not ok or not lines then return false end
  for _, l in ipairs(lines) do
    if type(l) == "table" then
      if capture.AddDoubleLine then capture:AddDoubleLine(l[1], l[2]) else capture:AddLine(l[1] .. "   " .. l[2], 1, 1, 1, true) end
    else capture:AddLine(l, 1, 1, 1, true) end
  end
  return true
end

function ns.RegisterDialogueUI()
  if ns.duiRegistered then return end
  if not (DialogueUIAPI and DialogueUIAPI.AddItemEvaluator) then return end
  ns.duiRegistered = true
  pcall(DialogueUIAPI.AddItemEvaluator, "Top Ramen", duiIsUpgrade, duiWriter)
end
ns.RegisterDialogueUI() -- as early as possible, so DialogueUI picks us up when it reads its settings
