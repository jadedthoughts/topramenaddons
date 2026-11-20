-- Top Ramen Feral Druid Gear Companion
-- /topramengear (or /topramen) opens a window with your equipped and bag gear, read from the game's own item data
-- and tooltips, ready to copy (Ctrl+C) and paste into Top Ramen: Feral Druid Gear Advisor.
-- Read-only: it never changes, moves or uses anything.

local _, ns = ...
local VERSION = "1.11"
local GOLD = "|cffe0b04a"

-- equipment slot id -> export slot key (same names as SimulationCraft)
local SLOTS = {
  {1, "head"}, {2, "neck"}, {3, "shoulder"}, {15, "back"}, {5, "chest"}, {9, "wrist"},
  {10, "hands"}, {6, "waist"}, {7, "legs"}, {8, "feet"}, {11, "finger1"}, {12, "finger2"},
  {13, "trinket1"}, {14, "trinket2"}, {16, "main_hand"}, {17, "off_hand"}, {18, "ranged"},
}

-- equip location of a bag item -> export slot key
local LOC2SLOT = {
  INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
  INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
  INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger1",
  INVTYPE_TRINKET = "trinket1", INVTYPE_WEAPON = "main_hand", INVTYPE_2HWEAPON = "main_hand",
  INVTYPE_WEAPONMAINHAND = "main_hand", INVTYPE_WEAPONOFFHAND = "off_hand", INVTYPE_HOLDABLE = "off_hand",
  INVTYPE_SHIELD = "off_hand", INVTYPE_RELIC = "ranged", INVTYPE_RANGED = "ranged",
  INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged",
}

-- strip colour codes, textures and the characters the export uses as separators
local function clean(s)
  if not s then return "" end
  s = tostring(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  s = s:gsub("|", "/"):gsub("[%^~\r\n]", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local GetDetailedLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local BagLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

local scanTip
local function addLine(out, text)
  local t = clean(text)
  if t ~= "" then out[#out + 1] = t end
end

-- tooltip text of an equipped item (kind "inv") or a bag item (kind "bag")
local function tooltipLines(kind, a, b)
  local out = {}
  if C_TooltipInfo then
    local ok, data = pcall(function()
      if kind == "inv" then return C_TooltipInfo.GetInventoryItem("player", a) end
      if kind == "link" then return C_TooltipInfo.GetHyperlink(a) end
      return C_TooltipInfo.GetBagItem(a, b)
    end)
    if ok and data and data.lines then
      for _, line in ipairs(data.lines) do
        addLine(out, line.leftText)
        addLine(out, line.rightText)
      end
      if #out > 0 then return out end
    end
  end
  -- fallback: read a hidden tooltip
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "TopRamenScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  if kind == "inv" then scanTip:SetInventoryItem("player", a)
  elseif kind == "link" then scanTip:SetHyperlink(a)
  else scanTip:SetBagItem(a, b) end
  for i = 1, scanTip:NumLines() do
    local l, r = _G["TopRamenScanTipTextLeft" .. i], _G["TopRamenScanTipTextRight" .. i]
    if l then addLine(out, l:GetText()) end
    if r and r:IsShown() then addLine(out, r:GetText()) end
  end
  scanTip:Hide()
  return out
end

ns.tooltipLines = tooltipLines

local function statString(link)
  local ok, st = pcall(GetStats, link)
  local parts = {}
  if ok and type(st) == "table" then
    for k, v in pairs(st) do parts[#parts + 1] = k .. ":" .. tostring(v) end
  end
  table.sort(parts)
  return table.concat(parts, ";")
end

local function itemInfo(link)
  local name, _, quality, ilvl, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID = GetInfo(link)
  if GetDetailedLevel then
    local ok, eff = pcall(GetDetailedLevel, link)
    if ok and eff then ilvl = eff end
  end
  return name, quality, ilvl, reqLevel, equipLoc, classID, subclassID
end

local function record(lines, where, slot, link, tip)
  local name, quality, ilvl, req, loc, classID, subID = itemInfo(link)
  local id = tonumber(link:match("item:(%d+)")) or 0
  lines[#lines + 1] = "tr_item=" .. table.concat({
    where, slot, id, clean(name or tip[1] or "?"), quality or 0, ilvl or 0, req or 0,
    loc or "", classID or 0, subID or 0, statString(link), table.concat(tip, "~"),
  }, "^")
end

-- character stats, written in the same format as the SimulationCraft addon's "Additional Character Info"
local function num(v, dec)
  v = tonumber(v) or 0
  if dec then return string.format("%." .. dec .. "f", v) end
  return tostring(math.floor(v + 0.5))
end
-- Forever's client marks some numbers "secret" (often in combat); addons can't do maths with them.
-- plain() turns a secret value into nil, and safe() calls a game function and does that to every result.
local isSecret = issecretvalue or function() return false end
local function plain(v) if isSecret(v) then return nil end return v end
local function safe(f, ...)
  local r = { n = 0 }
  local function pack(...) r.n = select("#", ...); for i = 1, r.n do r[i] = (select(i, ...)) end end
  pack(pcall(f, ...))
  if not r[1] then return end
  for i = 2, r.n do r[i] = plain(r[i]) end
  return unpack(r, 2, r.n)
end
ns.plain, ns.safe = plain, safe
-- combat: character numbers can be hidden while fighting, so some reads wait until it's over
function ns.InCombat()
  local ok, v = pcall(UnitAffectingCombat, "player")
  if ok and v == true then return true end
  return (InCombatLockdown and InCombatLockdown()) and true or false
end
local afterCombat = {}
function ns.AfterCombat(key, fn)
  if not ns.InCombat() then fn(); return false end
  afterCombat[key] = fn
  return true
end
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function()
    local todo = afterCombat
    afterCombat = {}
    for _, fn in pairs(todo) do pcall(fn) end
  end)
end

-- your level, remembering the last known value if the game hides it for a moment
function ns.Level()
  local l = safe(UnitLevel, "player")
  if l then ns.lastLevel = l end
  return ns.lastLevel
end

local function characterStats(lines)
  local st = {}
  local names = { "strength", "agility", "stamina", "intellect", "spirit" }
  for i, n in ipairs(names) do
    local _, eff = safe(UnitStat, "player", i)
    st[#st + 1] = n .. ":" .. num(eff)
  end
  table.insert(st, 1, "mana:" .. num(safe(UnitPowerMax, "player", 0)))
  table.insert(st, 1, "health:" .. num(safe(UnitHealthMax, "player")))
  lines[#lines + 1] = "# character_stats=" .. table.concat(st, "/")

  local base, pos, neg = safe(UnitAttackPower, "player")
  lines[#lines + 1] = "# attack_power=melee:" .. num((base or 0) + (pos or 0) + (neg or 0)) .. ":0:0"
  lines[#lines + 1] = "# crit=melee:" .. num(GetCritChance and safe(GetCritChance) or 0, 2)

  local _, armor = safe(UnitArmor, "player")
  local defBase, defMod = 0, 0
  if UnitDefense then defBase, defMod = safe(UnitDefense, "player") end
  lines[#lines + 1] = "# defense=armor:" .. num(armor) ..
    "/defense_skill:" .. num((defBase or 0) + (defMod or 0)) ..
    "/dodge:" .. num(GetDodgeChance and safe(GetDodgeChance) or 0, 2) ..
    "/parry:" .. num(GetParryChance and safe(GetParryChance) or 0, 2)

  local minD, maxD = safe(UnitDamage, "player")
  local speed = safe(UnitAttackSpeed, "player")
  lines[#lines + 1] = "# weapon_damage=mainhand:" .. num(minD, 2) .. ":" .. num(maxD, 2) .. ":" .. num(speed, 2)
end

local function buildExport()
  local lines = {}
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  lines[#lines + 1] = "# Top Ramen Feral Druid Gear Companion export v" .. VERSION
  lines[#lines + 1] = "# Paste this into Top Ramen: Feral Druid Gear Advisor"
  lines[#lines + 1] = "tr_char=" .. table.concat({
    clean(safe(UnitName, "player") or "?"), safe(UnitLevel, "player") or 0, string.lower(race or ""),
    string.lower(class or ""), clean(GetRealmName and GetRealmName() or ""),
  }, "^")

  local okStats = pcall(characterStats, lines)
  if not okStats then lines[#lines + 1] = "# character stats unavailable" end

  local count = 0
  for _, s in ipairs(SLOTS) do
    local link = GetInventoryItemLink("player", s[1])
    if link then
      record(lines, "equipped", s[2], link, tooltipLines("inv", s[1]))
      count = count + 1
    end
  end

  local missing = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (NumSlots(bag) or 0) do
      local link = BagLink(bag, slot)
      if link then
        local name, _, _, _, loc = itemInfo(link)
        if not name then
          missing = missing + 1
        elseif loc and LOC2SLOT[loc] then
          record(lines, "bag", LOC2SLOT[loc], link, tooltipLines("bag", bag, slot))
          count = count + 1
        end
      end
    end
  end
  return table.concat(lines, "\n"), count, missing
end

-- Adventure Guide (Encounter Journal) loot: every dungeon and raid, Druid loot only
local function lootExport()
  if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
  elseif LoadAddOn then pcall(LoadAddOn, "Blizzard_EncounterJournal") end
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_SelectInstance and EJ_GetNumLoot) then
    return nil, "this game version has no Adventure Guide data the addon can read"
  end
  local GetLoot = (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex) or EJ_GetLootInfoByIndex
  local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end
  local lines = {
    "# Top Ramen Feral Druid Gear Companion loot export v" .. VERSION,
    "# Paste this into Loot data on the Dungeons tab of Top Ramen: Feral Druid Gear Advisor",
  }
  local _, class = UnitClass("player")
  local classID = select(3, UnitClass("player"))
  if EJ_SetLootFilter then pcall(EJ_SetLootFilter, classID or 11, 0) end
  if EJ_SetDifficulty then pcall(EJ_SetDifficulty, 1) end
  local items, missing, instances = 0, 0, 0
  for tier = 1, (EJ_GetNumTiers() or 1) do
    pcall(EJ_SelectTier, tier)
    for _, isRaid in ipairs({ false, true }) do
      local i = 1
      while true do
        local instanceID, instanceName = EJ_GetInstanceByIndex(i, isRaid)
        if not instanceID then break end
        instances = instances + 1
        EJ_SelectInstance(instanceID)
        if EJ_SetLootFilter then pcall(EJ_SetLootFilter, classID or 11, 0) end
        local bossName = {}
        local e = 1
        while EJ_GetEncounterInfoByIndex do
          local name, _, encounterID = EJ_GetEncounterInfoByIndex(e, instanceID)
          if not name then break end
          bossName[encounterID] = name
          e = e + 1
        end
        for n = 1, (EJ_GetNumLoot() or 0) do
          local info = GetLoot(n)
          if type(info) ~= "table" then
            local itemID, encounterID, name, _, _, _, link = GetLoot(n)
            info = { itemID = itemID, encounterID = encounterID, name = name, link = link }
          end
          if info and info.itemID then
            if not info.link then
              missing = missing + 1
              RequestItem(info.itemID)
            else
              local _, _, _, _, loc = itemInfo(info.link)
              local slot = loc and LOC2SLOT[loc]
              if slot then
                local before = #lines
                record(lines, "loot", slot, info.link, tooltipLines("link", info.link))
                lines[#lines] = lines[#lines]:gsub("^tr_item=", "tr_loot=" .. table.concat({
                  clean(instanceName), clean(bossName[info.encounterID] or ""), isRaid and "raid" or "dungeon" }, "^") .. "^")
                if #lines > before then items = items + 1 end
              end
            end
          end
        end
        i = i + 1
      end
    end
  end
  if EJ_ResetLootFilter then pcall(EJ_ResetLootFilter) end
  return table.concat(lines, "\n"), items, missing, instances
end

-- DungeonJournal addon (ForeverDungeonJournal): read its loot lists in game, with exact stats from the game's item data
local function findJournal()
  local ns = _G.ForeverDungeonJournal_NS
  if type(ns) == "table" and type(ns.DB) == "table" then return ns end
  for _, v in pairs(_G) do
    if type(v) == "table" then
      local ok, db = pcall(rawget, v, "DB")
      local ok2, bl = pcall(rawget, v, "BOSS_LEVELS")
      if ok and ok2 and type(db) == "table" and type(bl) == "table" then return v end
    end
  end
end

ns.FindJournal = findJournal

local function journalExport()
  local fdj = findJournal()
  if not fdj then return nil, 0, 0, 0 end
  local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end
  local lines = {
    "# Top Ramen Feral Druid Gear Companion loot export v" .. VERSION .. " (from the DungeonJournal addon)",
    "# Paste this into Loot data on the Dungeons tab of Top Ramen: Feral Druid Gear Advisor",
  }
  local items, missing, instances = 0, 0, 0
  local function add(instanceName, boss, kind, id)
    if type(id) ~= "number" then return end
    local _, link = GetInfo(id)
    if not link then missing = missing + 1; RequestItem(id); return end
    local _, _, _, _, loc = itemInfo(link)
    local slot = loc and LOC2SLOT[loc]
    if not slot then return end
    record(lines, "loot", slot, link, tooltipLines("link", link))
    lines[#lines] = lines[#lines]:gsub("^tr_item=", "tr_loot=" .. table.concat({ clean(instanceName), clean(boss or ""), kind }, "^") .. "^")
    items = items + 1
  end
  local seen = {}
  local function addOnce(dname, boss, kind, id)
    local key = tostring(dname) .. "^" .. tostring(boss) .. "^" .. tostring(id)
    if seen[key] then return end
    seen[key] = true
    add(dname, boss, kind, id)
  end
  local order = fdj.ORDER
  if type(order) ~= "table" then order = {}; for n in pairs(fdj.DB) do order[#order + 1] = n end end
  for _, dname in ipairs(order) do
    local d = fdj.DB[dname]
    if type(d) == "table" then
      instances = instances + 1
      for _, b in ipairs(d.bosses or {}) do
        -- the "Recipes & Patterns" row only repeats items listed elsewhere
        if type(b) == "table" and not b.recipeTab then
          local boss = b.trash and "Trash drop" or b.name
          for _, x in ipairs(b.loot or {}) do if type(x) == "table" then addOnce(dname, boss, "dungeon", x[1]) end end
          local shared = fdj.GetBossSharedLoot and select(2, pcall(fdj.GetBossSharedLoot, dname, b))
          if type(shared) == "table" then
            for _, x in ipairs(shared) do if type(x) == "table" then addOnce(dname, boss, "dungeon", x[1]) end end
          end
        end
      end
      for _, q in ipairs(d.quests or {}) do
        if type(q) == "table" then
          for _, list in ipairs({ q.rewardItems or {}, q.additionalRewardItems or {} }) do
            for _, x in ipairs(list) do if type(x) == "table" then addOnce(dname, q.name or q.title, "quest", x[1]) end end
          end
        end
      end
    end
  end
  return table.concat(lines, "\n"), items, missing, instances
end

local frame
local function showExport(text)
  if not frame then
    frame = CreateFrame("Frame", "TopRamenExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Top Ramen gear export: press Ctrl+C, then paste it into the app")

    local scroll = CreateFrame("ScrollFrame", "TopRamenExportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -44)
    scroll:SetPoint("BOTTOMRIGHT", -42, 52)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(560)
    edit:SetAutoFocus(true)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(110, 24)
    close:SetPoint("BOTTOM", 0, 18)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    tinsert(UISpecialFrames, "TopRamenExportFrame")
  end
  frame.edit:SetText(text)
  frame:Show()
  frame.edit:SetFocus()
  frame.edit:HighlightText()
end

SLASH_TOPRAMEN1 = "/topramengear"
SLASH_TOPRAMEN2 = "/topramen"
SLASH_TOPRAMEN3 = "/ramen"
SLASH_TOPRAMEN4 = "/trg"
local lastMissing, stuck = nil, 0
local function runLoot(attempt)
  if attempt == 1 then lastMissing, stuck = nil, 0 end
  local ok, text, count, missing, instances = pcall(lootExport)
  -- the Adventure Guide is empty on Forever's classic client: use the DungeonJournal addon instead
  if not ok or not text or (count or 0) == 0 then
    local ok2, t2, c2, m2, i2 = pcall(journalExport)
    if not ok2 then print(GOLD .. "Top Ramen:|r DungeonJournal export failed: " .. tostring(t2)); return end
    if not t2 then
      print(GOLD .. "Top Ramen:|r the Adventure Guide has no loot data here. Install and enable the DungeonJournal addon, then run /trg loot again.")
      return
    end
    text, count, missing, instances = t2, c2, m2, i2
  end
  -- items the server never sends back after a few tries probably aren't in the game: stop waiting for them
  if missing == lastMissing then stuck = stuck + 1 else stuck = 0 end
  lastMissing = missing
  if missing > 0 and attempt < 10 and stuck < 2 and C_Timer then
    print(GOLD .. "Top Ramen:|r loading " .. missing .. " item(s) from the server, one moment...")
    C_Timer.After(2, function() runLoot(attempt + 1) end)
    return
  end
  showExport(text)
  print(GOLD .. "Top Ramen:|r exported " .. count .. " Druid items from " .. instances .. " dungeons. Press Ctrl+C, then paste into Loot data on the app's Dungeons tab.")
  if missing > 0 then print(GOLD .. "Top Ramen:|r skipped " .. missing .. " item(s) the server doesn't recognise (DungeonJournal lists them, but they're probably not in the game yet).") end
end

local runExportNow
local function runExport()
  if ns.AfterCombat("export", runExportNow) then
    print(GOLD .. "Top Ramen:|r you're in combat. The export will open as soon as combat ends.")
  end
end
runExportNow = function()
  local ok, text, count, missing = pcall(buildExport)
  if not ok then
    print(GOLD .. "Top Ramen:|r export failed: " .. tostring(text))
    return
  end
  showExport(text)
  print(GOLD .. "Top Ramen:|r exported " .. count .. " items. Press Ctrl+C, then paste into the app.")
  if missing > 0 then
    print(GOLD .. "Top Ramen:|r " .. missing .. " bag item(s) weren't loaded yet. Run /trg export again in a few seconds to include them.")
  end
end
ns.RunExport = runExport
ns.RunLoot = function() runLoot(1) end

SlashCmdList.TOPRAMEN = function(msg)
  ns.rawSlash = msg or "" -- as typed: item links break when lowercased
  msg = (msg or ""):lower()
  if msg:match("^%s*loot") then runLoot(1); return end
  if msg:match("^%s*export") then runExport(); return end
  if ns.Command and ns.Command(msg) then return end
  if msg:match("^%s*$") and ns.ToggleWindow then ns.ToggleWindow(); return end
  runExport()
end
