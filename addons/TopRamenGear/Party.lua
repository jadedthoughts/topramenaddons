-- Top Ramen Gear: party loot roll compare
-- When a loot roll starts, every party member with Top Ramen Gear scores the item for the spec they've picked
-- in their Gear window and tells the group: "+14% Cat", "new slot", "no upgrade" or "can't use".
-- A small window lists everyone, with a green bar for each upgrade and a star on the biggest one.
-- Only the result is sent, never anyone's gear. The window can be moved anywhere and remembers where.
local _, ns = ...

local PREFIX = "TRGear"
local GOLD, GREY, GREEN = "|cffe0b04a", "|cff9d9d9d", "|cff4ade80"
local ROLL_KEEP = 8      -- seconds a roll stays listed after its timer ends
local MAX_ROLLS = 4      -- rolls shown at once (newest first)

local known = {}         -- name -> Gear version, for party members who have the addon
local rolls = {}         -- list of { itemID, link, rollID, ends, results = { [name] = {code, pct, spec} }, test }
local frame              -- the window
local lastHello, replied = 0, {}

local short
local function myName() return short(UnitName("player")) end
-- names without the realm: messages from players on another realm arrive as "Name-Realm",
-- but the party list (UnitName) gives just "Name"
-- (WoW Forever has also been seen sending "Name Something", so cut at a space too)
short = function(name) if not name then return nil end return (name:match("^([^%-%s]+)")) end
local function version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return (get and get("TopRamenGear", "Version")) or "?"
end
local function enabled() return ns.db and ns.db.rollCompare ~= false end

---------------------------------------------------------------------------
-- talking to the group
---------------------------------------------------------------------------
local function channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
     and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

local diag = { sent = 0, got = 0, lastFrom = nil, lastSend = nil }
local function trySend(fn, msg, ch)
  local ok, res = pcall(fn, PREFIX, msg, ch)
  -- newer clients return a result: 0 (or true / nil on older ones) means it went out
  local good = ok and (res == nil or res == true or res == 0)
  diag.lastSend = ch .. (good and " ok" or (" failed (" .. tostring(res) .. ")"))
  return good
end
local function send(msg)
  local ch = channel()
  if not ch then return end
  local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not fn then return end
  diag.sent = diag.sent + 1
  if not trySend(fn, msg, ch) then
    -- dungeon finder groups and normal parties use different channels: try the others
    for _, other in ipairs({ "INSTANCE_CHAT", "PARTY", "RAID" }) do
      if other ~= ch and trySend(fn, msg, other) then break end
    end
  end
end

local function hello(force)
  local now = GetTime and GetTime() or 0
  if not force and now - lastHello < 5 then return end
  lastHello = now
  send("H|" .. version())
end

-- everyone in the group, you first: { name, classFile }
local function roster()
  local list = { { name = myName(), class = select(2, UnitClass("player")), unit = "player" } }
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, (raid and n or math.max(0, n - 1)) do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local name = short(UnitName(unit))
    if name and name ~= myName() and name ~= UNKNOWNOBJECT then
      list[#list + 1] = { name = name, class = select(2, UnitClass(unit)), unit = unit }
    end
  end
  return list
end

---------------------------------------------------------------------------
-- scoring the item for yourself
---------------------------------------------------------------------------
-- returns code, pct, spec: "u" upgrade (pct), "n" no upgrade (pct <= 0), "e" empty slot (new), "x" can't use
function ns.RollResult(link)
  local mode = ns.CurrentMode()
  local sp = ns.SpecInfo and ns.SpecInfo(mode)
  local specName = sp and sp.name or mode
  local it = ns.ItemStats(link)
  if not it then return "x", 0, specName end
  if not ns.Gain then return "x", 0, specName end
  local d = ns.Gain(it, mode, 1)
  if d == nil then return "x", 0, specName end
  local old = ns.RollOldScore and ns.RollOldScore(it, mode) or 0
  if old <= 0.05 then
    if d > 0.05 then return "e", 0, specName end
    return "n", 0, specName
  end
  local pct = d / old * 100
  if pct > 0.5 then return "u", pct, specName end
  return "n", pct, specName
end

---------------------------------------------------------------------------
-- the rolls
---------------------------------------------------------------------------
local function findRoll(itemID, rollID, test)
  for _, r in ipairs(rolls) do
    if rollID and r.rollID == rollID and r.itemID == itemID and not r.test == not test then return r end
  end
  for _, r in ipairs(rolls) do
    if r.itemID == itemID and not r.test == not test then return r end
  end
end

local function addRoll(itemID, link, rollID, seconds, test)
  local r = findRoll(itemID, rollID, test)
  local now = GetTime and GetTime() or 0
  if not r then
    r = { itemID = itemID, results = {} }
    table.insert(rolls, 1, r)
    while #rolls > MAX_ROLLS do table.remove(rolls) end
  end
  r.link = link or r.link
  r.rollID = rollID or r.rollID
  r.ends = now + (seconds or 60) + ROLL_KEEP
  r.test = test or r.test
  return r
end

local refresh -- defined with the window

local function itemInfo(x)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(x) end
  if GetItemInfo then return GetItemInfo(x) end
end
local function scoreAndShare(r, tries)
  -- a roll someone else told us about may arrive before the game has the item: ask for it, then try again
  if not r.link and r.itemID then r.link = select(2, itemInfo(r.itemID)) end
  if not r.link then
    if (tries or 0) < 10 and C_Timer then C_Timer.After(0.6, function() scoreAndShare(r, (tries or 0) + 1) end) end
    return
  end
  local name = itemInfo(r.link)
  -- the item may not be loaded yet: try again shortly
  if not name and (tries or 0) < 10 and C_Timer then
    C_Timer.After(0.6, function() scoreAndShare(r, (tries or 0) + 1) end)
    return
  end
  local ok, code, pct, spec = pcall(ns.RollResult, r.link)
  if not ok then code, pct, spec = "x", 0, "?" end
  r.results[myName()] = { code = code, pct = pct or 0, spec = spec }
  if not r.test then
    send(string.format("R|%d|%d|%s|%.1f|%s", r.itemID or 0, r.rollID or 0, code, pct or 0, (spec or ""):gsub("|", "")))
  end
  if refresh then refresh() end
end

local function onRollStart(rollID, rollTime)
  if not enabled() then return end
  local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
  if not link then return end
  local itemID = tonumber(link:match("item:(%d+)"))
  local r = addRoll(itemID, link, rollID, (rollTime or 60000) / 1000)
  scoreAndShare(r)
  hello()
end

local function onMessage(prefix, msg, _, sender)
  if prefix ~= PREFIX or not msg then return end
  local who = short(sender)
  if not who then return end
  diag.got = diag.got + 1; diag.lastFrom = (sender .. ": " .. msg):gsub("|", "||")
  local kind = msg:sub(1, 1)
  if kind == "H" or kind == "h" then
    known[who] = msg:match("^.|(.*)$") or "?"
    -- say hello back once in a while, so newcomers learn you have the addon too
    local now = GetTime and GetTime() or 0
    if kind == "H" and who ~= myName() and (not replied[who] or now - replied[who] > 30) then
      replied[who] = now
      send("h|" .. version())
    end
    if refresh then refresh() end
  elseif kind == "R" and enabled() then
    local itemID, rollID, code, pct, spec = msg:match("^R|(%d+)|(%d+)|(%a)|(%-?[%d%.]+)|(.*)$")
    if not itemID then return end
    known[who] = known[who] or "?"
    if who == myName() then return end
    itemID, rollID = tonumber(itemID), tonumber(rollID)
    local r = findRoll(itemID, rollID)
    if not r then
      -- a roll we don't have a window for (yet): list it anyway
      local link
      if C_Item and C_Item.GetItemInfo then link = select(2, C_Item.GetItemInfo(itemID))
      elseif GetItemInfo then link = select(2, GetItemInfo(itemID)) end
      r = addRoll(itemID, link, rollID, 60)
      if rollID == 0 then r.label = "party test" end
      scoreAndShare(r)
    end
    r.results[who] = { code = code, pct = tonumber(pct) or 0, spec = spec }
    if refresh then refresh() end
  end
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------
local W, ROW_H, HEAD_H = 300, 18, 26

local function savePos(f)
  local p, _, rp, x, y = f:GetPoint(1)
  ns.db.rollPos = { p, rp, x, y }
end

local function build()
  local UI = ns.UI
  local f = UI.Frame(UIParent, UI.C.bg, UI.C.trim, 1, 0.96)
  f:SetSize(W, 120)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
  local p = ns.db.rollPos
  if p and p[1] then f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80) end
  if UI.RegisterWindow then UI.RegisterWindow(f) end

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(UI.MEDIA .. "trIcon"); icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 8, -5)
  f.title = UI.Text(f, "GameFontNormal", UI.C.gold)
  f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  f.title:SetText("Party loot")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() wipe(rolls); f:Hide() end)
  f.hint = UI.Text(f, "GameFontHighlightSmall", UI.C.muted)
  f.hint:SetPoint("RIGHT", close, "LEFT", -2, 0)
  f.hint:SetText("drag to move")
  f.blocks = {}
  f:Hide()
  return f
end

local function block(i)
  local UI = ns.UI
  local b = frame.blocks[i]
  if b then return b end
  b = CreateFrame("Frame", nil, frame)
  b:SetWidth(W - 16)
  b.icon = UI.Icon(b, 22); b.icon:SetPoint("TOPLEFT", 0, 0)
  b.name = UI.Text(b, "GameFontHighlight")
  b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 4); b.name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.name:SetWordWrap(false)
  b.verdict = UI.Text(b, "GameFontHighlightSmall", UI.C.muted)
  b.verdict:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
  -- the item's tooltip on hover
  b.icon:EnableMouse(true)
  b.icon:SetScript("OnEnter", function(self)
    if b.link then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetHyperlink(b.link); GameTooltip:Show() end
  end)
  b.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b.rows = {}
  frame.blocks[i] = b
  return b
end

local function row(b, j)
  local UI = ns.UI
  local r = b.rows[j]
  if r then return r end
  r = CreateFrame("Frame", nil, b)
  r:SetSize(W - 16, ROW_H)
  r.star = UI.Text(r, "GameFontHighlightSmall"); r.star:SetPoint("LEFT", 0, 0); r.star:SetWidth(16)
  r.name = UI.Text(r, "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 16, 0); r.name:SetWidth(92)
  r.name:SetWordWrap(false)
  r.bar = UI.Bar(r, 80); r.bar:SetPoint("LEFT", 112, 0)
  r.text = UI.Text(r, "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r.bar, "RIGHT", 8, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0); r.text:SetWordWrap(false)
  b.rows[j] = r
  return r
end

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255)) end
  return "|cffece6d8"
end

refresh = function()
  if not enabled() then if frame then frame:Hide() end return end
  local now = GetTime and GetTime() or 0
  for i = #rolls, 1, -1 do if rolls[i].ends and rolls[i].ends < now then table.remove(rolls, i) end end
  if #rolls == 0 then if frame then frame:Hide() end return end
  frame = frame or build()
  local people = roster()
  local y = -HEAD_H - 4
  for i, r in ipairs(rolls) do
    local b = block(i)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8, y)
    local name, _, quality, _, _, _, _, _, _, tex = nil
    if r.link then
      if C_Item and C_Item.GetItemInfo then name, _, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(r.link)
      elseif GetItemInfo then name, _, quality, _, _, _, _, _, _, tex = GetItemInfo(r.link) end
    end
    b.link = r.link
    b.icon:SetItem(tex or "Interface\\Icons\\INV_Misc_QuestionMark", quality or 1)
    local qc = ns.UI.QualityColor(quality or 1)
    b.name:SetText(string.format("|cff%02x%02x%02x%s|r", math.floor(qc[1] * 255), math.floor(qc[2] * 255), math.floor(qc[3] * 255), name or (r.link or "Loading...")) ..
      ((r.test or r.label) and (GREY .. "  (" .. (r.label or "test") .. ")|r") or ""))

    -- the people, best upgrade first
    local list = {}
    for _, p in ipairs(r.test and { people[1] } or people) do
      local res = r.results[p.name]
      local rank
      if res and res.code == "e" then rank = 10000
      elseif res and res.code == "u" then rank = res.pct
      elseif res and res.code == "n" then rank = -1000 + (res.pct or 0)
      elseif res then rank = -3000
      elseif known[p.name] or p.name == myName() then rank = -4000
      else rank = -5000 end
      list[#list + 1] = { p = p, res = res, rank = rank }
    end
    if r.test then
      list[#list + 1] = { p = { name = "Example", class = "MAGE" }, res = { code = "u", pct = 6, spec = "Fire" }, rank = 6 }
      list[#list + 1] = { p = { name = "Example", class = "WARRIOR" }, res = { code = "x", pct = 0, spec = "Arms" }, rank = -3000 }
    end
    table.sort(list, function(a, c) return a.rank > c.rank end)
    local top = list[1] and list[1].rank > 0 and list[1] or nil
    local maxPct = 0
    for _, e in ipairs(list) do if e.res and e.res.code == "u" then maxPct = math.max(maxPct, e.res.pct) end end

    for j, e in ipairs(list) do
      local rw = row(b, j)
      rw:ClearAllPoints(); rw:SetPoint("TOPLEFT", 0, -26 - (j - 1) * ROW_H)
      rw.star:SetText(e == top and ns.UI.STAR or "")
      rw.name:SetText(classColor(e.p.class) .. e.p.name .. "|r")
      local res = e.res
      if res and res.code == "u" then
        rw.bar:Show(); rw.bar:SetValue(maxPct > 0 and res.pct / maxPct or 0)
        rw.text:SetText(GREEN .. string.format("+%.0f%%", res.pct) .. "|r " .. GREY .. res.spec .. "|r")
      elseif res and res.code == "e" then
        rw.bar:Show(); rw.bar:SetValue(1)
        rw.text:SetText(GREEN .. "New slot|r " .. GREY .. res.spec .. "|r")
      elseif res and res.code == "n" then
        rw.bar:Show(); rw.bar:SetValue(0)
        rw.text:SetText(GREY .. "No upgrade · " .. res.spec .. "|r")
      elseif res then
        rw.bar:Hide()
        rw.text:SetText(GREY .. "Can't use|r")
      elseif known[e.p.name] or e.p.name == myName() then
        rw.bar:Hide(); rw.text:SetText(GREY .. "checking...|r")
      else
        rw.bar:Hide(); rw.text:SetText(GREY .. "Needs TR Gear Addon|r")
      end
      rw:Show()
    end
    for j = #list + 1, #b.rows do b.rows[j]:Hide() end

    if top then
      b.verdict:SetText(GREEN .. "Upgrade for " .. top.p.name .. "|r" .. GREY .. " (need)|r")
    elseif #list > 0 and list[1].res then
      b.verdict:SetText(GREY .. "No upgrades here: greed it for gold|r")
    else
      b.verdict:SetText(GREY .. "Waiting for the party...|r")
    end
    local h = 26 + #list * ROW_H
    b:SetHeight(h); b:Show()
    y = y - h - 10
  end
  for i = #rolls + 1, #frame.blocks do frame.blocks[i]:Hide() end
  frame:SetHeight(-y + 2)
  if not frame:IsShown() then frame:Show() end
end
ns.RefreshRolls = function() if refresh then refresh() end end

-- /trg party: what the party loot window knows (to sort out "Needs TR Gear Addon")
function ns.PartyStatus()
  local say = function(s) print(GOLD .. "Top Ramen:|r " .. s) end
  local registered = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)
  say("party loot " .. (enabled() and "on" or "off") .. ", version " .. version() .. ", channel " .. tostring(channel() or "none (not in a group)")
    .. ", listening " .. tostring(registered == nil and "?" or registered))
  say("sent " .. diag.sent .. " (last: " .. tostring(diag.lastSend or "-") .. "), received " .. diag.got
    .. (diag.lastFrom and (" (last: " .. diag.lastFrom .. ")") or ""))
  for _, p in ipairs(roster()) do
    if p.name ~= myName() then
      say("  " .. p.name .. ": " .. (known[p.name] and ("has Gear " .. known[p.name]) or "no reply yet"))
    end
  end
  hello(true)
  say("(asked the group again - type /trg party in a few seconds to see who answered)")
end

-- /trg rolltest [item link]: try the window with an item from your bags
function ns.RollTest(arg)
  local link = arg and arg:match("|H(item:[^|]+)|h") and arg:match("(|c%x+|Hitem:.-|h.-|h|r)")
  local party = arg and arg:lower():match("^%s*%S*%s*party") and channel() ~= nil
  -- a typed item name ("/trg rolltest party Rune-Etched Epaulets"): look for it in your bags and on you
  local typed = arg and not link and arg:match("^%s*%S+%s+party%s+(.-)%s*$") or (arg and not link and arg:match("^%s*rolltest%s+(.-)%s*$"))
  if typed and typed:lower() == "party" then typed = nil end
  if typed and typed ~= "" then
    local want = typed:lower():gsub("^%[", ""):gsub("%]$", "")
    local function check(l) if l and not link then local n = itemInfo(l); if n and n:lower() == want then link = l end end end
    if C_Container then
      for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do check(C_Container.GetContainerItemLink(bag, slot)) end
      end
    end
    for slot = 1, 19 do check(GetInventoryItemLink and GetInventoryItemLink("player", slot)) end
    if not link then
      print(GOLD .. "Top Ramen:|r couldn't find \"" .. typed .. "\" in your bags or on you. Shift-click the item to put its link after the command instead.")
      return
    end
  end
  if not link and C_Container then
    for bag = 0, 4 do
      for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
        local l = C_Container.GetContainerItemLink(bag, slot)
        if l and ns.ItemStats(l) then link = l; break end
      end
      if link then break end
    end
  end
  if not link then print(GOLD .. "Top Ramen:|r no gear in your bags to test with. Try /trg rolltest [item link].") return end
  local itemID = tonumber(link:match("item:(%d+)"))
  if party then
    -- a pretend roll shared with the group (roll number 0): everyone with Gear scores it and answers,
    -- so everyone sees the same window as on a real roll
    local r = addRoll(itemID, link, 0, 40, false)
    r.label = "party test"
    scoreAndShare(r)
    print(GOLD .. "Top Ramen:|r party test roll for " .. link .. " sent to your group.")
    return
  end
  local r = addRoll(itemID, link, nil, 30, true)
  scoreAndShare(r)
  print(GOLD .. "Top Ramen:|r test roll for " .. link .. ". Drag the window where you want it; it remembers. /trg rolltest party sends one to your group.")
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("START_LOOT_ROLL")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    if C_Timer then C_Timer.After(3, function() hello(true) end) end
    -- drop finished rolls once a second while the window is up
    if C_Timer and C_Timer.NewTicker then
      C_Timer.NewTicker(1, function() if frame and frame:IsShown() then refresh() end end)
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    hello()
    if frame and frame:IsShown() then refresh() end
  elseif event == "START_LOOT_ROLL" then
    onRollStart(...)
  elseif event == "CHAT_MSG_ADDON" then
    onMessage(...)
  end
end)
