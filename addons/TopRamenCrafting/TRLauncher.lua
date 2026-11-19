-- Top Ramen launcher: one bowl button on the minimap for every Top Ramen addon.
-- Every Top Ramen addon ships an identical copy of this file. The first copy to load
-- makes the shared launcher; the newest copy's code wins; each addon adds its own row.
-- An addon describes its row in its .toc:
--   ## X-TR-Letter: G          ## X-TR-Label: Gear        ## X-TR-Cmd: /trg
--   ## X-TR-Slash: TOPRAMEN    ## X-TR-Color: 4ade80      ## X-TR-Icon: INV_Helmet_03
--   ## X-TR-Order: 1
-- Also: /tr opens the menu, /tr button shows or hides the minimap button,
-- /tr macro <name> makes that addon's macro.
local ADDON = ...
local VERSION = 1

local L = _G.TopRamenLauncher
if type(L) ~= "table" then L = { version = 0, entries = {}, byKey = {} }; _G.TopRamenLauncher = L end

local function meta(addon, field)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not get then return nil end
  local ok, v = pcall(get, addon, field)
  if ok and v and v ~= "" then return v end
end

-- this addon's row (done by every copy, whatever its version)
do
  local title = meta(ADDON, "Title") or ADDON
  local e = {
    key = ADDON,
    letter = meta(ADDON, "X-TR-Letter") or title:gsub("^Top Ramen%s*", ""):sub(1, 1):upper(),
    label = meta(ADDON, "X-TR-Label") or title:gsub("^Top Ramen%s*", ""),
    cmd = meta(ADDON, "X-TR-Cmd") or "",
    slash = meta(ADDON, "X-TR-Slash"),
    color = meta(ADDON, "X-TR-Color") or "ffd100",
    icon = meta(ADDON, "X-TR-Icon") or "INV_Misc_QuestionMark",
    order = tonumber(meta(ADDON, "X-TR-Order") or "") or 50,
    media = "Interface\\AddOns\\" .. ADDON .. "\\Media\\",
  }
  if not L.byKey[ADDON] then
    L.entries[#L.entries + 1] = e
    L.byKey[ADDON] = e
    table.sort(L.entries, function(a, b) return a.order < b.order end)
  end
  -- the addon list's built-in launcher (## AddonCompartmentFunc in the .toc) and key bindings
  _G[ADDON .. "_TRLaunch"] = function() if L.Open then L.Open(ADDON) end end
  local up = ADDON:upper()
  _G["BINDING_HEADER_" .. up] = title
  _G["BINDING_NAME_" .. up .. "_OPEN"] = "Open " .. e.label
end

if VERSION <= (L.version or 0) then return end
L.version = VERSION

---------------------------------------------------------------------------
-- look (same colours as the Top Ramen windows)
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function hex(h)
  h = tostring(h or "ffffff"):gsub("#", "")
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local C = { bg = "14110d", row = "1d1812", hover = "3a2b14", trim = "6b5a2e", gold = "ffd100", text = "ece6d8", muted = "b8ae9c" }
local GOLD, MUTED = "|cffffd100", "|cffb8ae9c"

local function skin(f, bg, border)
  if not f.SetBackdrop then
    if BackdropTemplateMixin then Mixin(f, BackdropTemplateMixin) else return end
  end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  local r, g, b = hex(bg); f:SetBackdropColor(r, g, b, 0.97)
  if border then r, g, b = hex(border); f:SetBackdropBorderColor(r, g, b, 1)
  else f:SetBackdropBorderColor(0, 0, 0, 0) end
end

local function say(msg) print(GOLD .. "Top Ramen|r: " .. msg) end
L.Say = say

local function db()
  if type(TopRamenLauncherDB) ~= "table" then TopRamenLauncherDB = {} end
  local d = TopRamenLauncherDB
  if d.angle == nil then d.angle = 200 end
  if d.show == nil then d.show = true end
  return d
end
L.DB = db

---------------------------------------------------------------------------
-- opening an addon
---------------------------------------------------------------------------
function L.Open(key)
  local e = L.byKey[key]
  if not e then return end
  local fn = e.slash and SlashCmdList and SlashCmdList[e.slash]
  if fn then
    db().last = key
    local ok, err = pcall(fn, "")
    if not ok then say("couldn't open " .. e.label .. ": " .. tostring(err)) end
  elseif e.cmd ~= "" then
    say("type " .. e.cmd .. " to open " .. e.label .. ".")
  end
  if L.menu then L.menu:Hide() end
end

---------------------------------------------------------------------------
-- macros: find yours if you already made one, otherwise make it, then put it on the cursor
---------------------------------------------------------------------------
local function aliases(e)
  local set = {}
  if e.cmd ~= "" then set[e.cmd:lower()] = true end
  if e.slash then
    for i = 1, 9 do
      local s = _G["SLASH_" .. e.slash .. i]
      if s then set[s:lower()] = true end
    end
  end
  return set
end

local function findMacro(e)
  if not GetMacroInfo then return nil end
  local set = aliases(e)
  local numAcc, numChar = 0, 0
  if GetNumMacros then numAcc, numChar = GetNumMacros() end
  local maxAcc = MAX_ACCOUNT_MACROS or 120
  local function check(i)
    local name, _, body = GetMacroInfo(i)
    if not name or not body then return end
    for raw in body:gmatch("[^\r\n]+") do
      local line = raw:lower():match("^%s*(.-)%s*$")
      if line ~= "" then
        if set[line] then return true end
        return false -- only the first line counts
      end
    end
  end
  for i = 1, numAcc or 0 do if check(i) then return i end end
  for i = maxAcc + 1, maxAcc + (numChar or 0) do if check(i) then return i end end
end
L.FindMacro = function(key) return L.byKey[key] and findMacro(L.byKey[key]) end

function L.MakeMacro(key)
  local e = L.byKey[key]
  if not e then return end
  if InCombatLockdown and InCombatLockdown() then say("can't make macros in combat - try again after the fight."); return end
  if not CreateMacro or not GetMacroInfo then say("this client can't make macros from an addon - type /macro and make one with " .. e.cmd .. "."); return end
  local index = findMacro(e)
  local made = false
  if not index then
    local body = e.cmd ~= "" and e.cmd or ("/" .. e.label:lower())
    local numAcc, numChar = GetNumMacros()
    local perChar = nil
    if (numAcc or 0) >= (MAX_ACCOUNT_MACROS or 120) then
      if (numChar or 0) >= (MAX_CHARACTER_MACROS or 18) then
        say("your macro slots are full. Delete one in /macro, then try again.")
        return
      end
      perChar = 1
    end
    local ok, res = pcall(CreateMacro, e.label, e.icon, body, perChar)
    if not ok or not res then
      ok, res = pcall(CreateMacro, e.label, "INV_Misc_QuestionMark", body, perChar)
    end
    if not ok or not res then say("couldn't make the macro (" .. tostring(res) .. "). Make it in /macro with " .. body .. "."); return end
    index, made = res, true
  end
  local picked = PickupMacro and pcall(PickupMacro, index)
  local what = made and ("Made the " .. GOLD .. e.label .. "|r macro") or ("You already have a macro for " .. e.label)
  if picked and GetCursorInfo and GetCursorInfo() == "macro" then
    say(what .. " - it's on your cursor. Click an action bar slot to put it there.")
  else
    say(what .. ". Drag it from /macro onto an action bar.")
  end
  if L.menu then L.menu:Hide() end
end

---------------------------------------------------------------------------
-- the menu
---------------------------------------------------------------------------
local ROW_H, MENU_W = 26, 230

local function badge(parent, e, size)
  local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  b:SetSize(size, size)
  skin(b, "14110d", e.color)
  local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:SetPoint("TOPLEFT", 1, -1); t:SetPoint("BOTTOMRIGHT", -1, 1)
  local r, g, bl = hex(e.color); t:SetColorTexture(r, g, bl, 0.22)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText(e.letter); fs:SetTextColor(r, g, bl)
  return b
end

local function buildMenu()
  local m = CreateFrame("Frame", "TopRamenLauncherMenu", UIParent, "BackdropTemplate")
  skin(m, C.bg, C.trim)
  m:SetFrameStrata("DIALOG")
  m:SetClampedToScreen(true)
  m:EnableMouse(true)
  m:Hide()
  if UISpecialFrames then tinsert(UISpecialFrames, "TopRamenLauncherMenu") end

  m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  m.title:SetPoint("TOPLEFT", 10, -9)
  m.title:SetText("Top Ramen")
  m.rows = {}

  m.foot = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  m.foot:SetPoint("BOTTOMLEFT", 10, 8); m.foot:SetPoint("BOTTOMRIGHT", -10, 8)
  m.foot:SetJustifyH("LEFT")
  m.foot:SetText(MUTED .. "Macro puts a button on your cursor for your action bar.|r")
  m.foot:SetWordWrap(true)

  -- close when the mouse has been away for a moment
  m.away = 0
  m:SetScript("OnUpdate", function(self, el)
    local over = self:IsMouseOver() or (L.button and L.button:IsMouseOver())
    if over then self.away = 0 else self.away = self.away + el end
    if self.away > 1.5 then self:Hide() end
  end)
  m:SetScript("OnShow", function(self) self.away = 0 end)
  return m
end

local function menuRow(m, i)
  local r = m.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, m, "BackdropTemplate")
  r:SetSize(MENU_W - 12, ROW_H)
  skin(r, C.row)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("LEFT", 34, 0)
  r.cmd = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.cmd:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
  r.cmd:SetTextColor(hex(C.muted))
  -- the Macro button on the right
  r.mac = CreateFrame("Button", nil, r, "BackdropTemplate")
  r.mac:SetSize(48, 18); r.mac:SetPoint("RIGHT", -4, 0)
  skin(r.mac, "2a2116", C.trim)
  r.mac.t = r.mac:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.mac.t:SetPoint("CENTER"); r.mac.t:SetText("Macro")
  r.mac:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(hex(C.gold))
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Make a macro", 1, 0.82, 0)
    local has = r.entry and findMacro(r.entry)
    GameTooltip:AddLine(has and "You already have one - this puts it on your cursor so you can drop it on an action bar."
      or "Makes a " .. (r.entry and r.entry.label or "") .. " macro and puts it on your cursor so you can drop it on an action bar.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  r.mac:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(hex(C.trim)); GameTooltip:Hide() end)
  r.mac:SetScript("OnClick", function() if r.entry then L.MakeMacro(r.entry.key) end end)

  r:SetScript("OnEnter", function(self) local a, b, c = hex(C.hover); self:SetBackdropColor(a, b, c, 1) end)
  r:SetScript("OnLeave", function(self) local a, b, c = hex(C.row); self:SetBackdropColor(a, b, c, 0.97) end)
  r:SetScript("OnClick", function(self) if self.entry then L.Open(self.entry.key) end end)
  m.rows[i] = r
  return r
end

function L.RefreshMenu()
  local m = L.menu
  if not m then return end
  for i, e in ipairs(L.entries) do
    local r = menuRow(m, i)
    r.entry = e
    if r.badge then r.badge:Hide() end
    r.badge = r.badges and r.badges[e.key]
    if not r.badge then
      r.badges = r.badges or {}
      r.badge = badge(r, e, 20); r.badge:SetPoint("LEFT", 6, 0)
      r.badges[e.key] = r.badge
    end
    r.badge:Show()
    r.name:SetText(e.label)
    r.cmd:SetText(e.cmd)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 6, -28 - (i - 1) * (ROW_H + 2))
    r:Show()
  end
  for i = #L.entries + 1, #m.rows do m.rows[i]:Hide() end
  m:SetSize(MENU_W, 28 + #L.entries * (ROW_H + 2) + 34)
end

function L.ToggleMenu(anchor)
  L.menu = L.menu or buildMenu()
  local m = L.menu
  if m:IsShown() then m:Hide(); return end
  L.RefreshMenu()
  m:ClearAllPoints()
  if anchor and anchor:IsVisible() then
    -- open away from the screen edge the button sits on
    local x, y = anchor:GetCenter()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local v = (y or 0) > H / 2 and "TOP" or "BOTTOM"
    local h = (x or 0) > W / 2 and "RIGHT" or "LEFT"
    local ov = v == "TOP" and "BOTTOM" or "TOP"
    m:SetPoint(v .. h, anchor, ov .. (h == "RIGHT" and "LEFT" or "RIGHT"), 0, 0)
  else
    m:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
  m:Show()
end

---------------------------------------------------------------------------
-- the minimap button
---------------------------------------------------------------------------
local function place(btn)
  local a = math.rad(db().angle or 200)
  local w = (Minimap:GetWidth() / 2) + 5
  local h = (Minimap:GetHeight() / 2) + 5
  local x, y = math.cos(a), math.sin(a)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function buildButton()
  if not Minimap then return end
  local b = CreateFrame("Button", "TopRamenLauncherButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(22, 22); bg:SetPoint("TOPLEFT", 5, -5)
  bg:SetVertexColor(0.08, 0.07, 0.05, 1)

  local media = (L.entries[1] and L.entries[1].media) or ("Interface\\AddOns\\" .. ADDON .. "\\Media\\")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(media .. "trIcon")
  icon:SetSize(22, 22); icon:SetPoint("TOPLEFT", 5, -5)
  if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  b.icon = icon

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" and db().last and L.byKey[db().last] then
      L.Open(db().last)
    else
      L.ToggleMenu(self)
    end
  end)
  b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 6, -6) end)
  b:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 5, -5) end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      cx, cy = cx / s, cy / s
      db().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
      place(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self.dragging = nil
    self:SetScript("OnUpdate", nil)
    icon:SetPoint("TOPLEFT", 5, -5)
  end)
  b:SetScript("OnEnter", function(self)
    if self.dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Top Ramen", 1, 0.82, 0)
    for _, e in ipairs(L.entries) do
      local r, g, bl = hex(e.color)
      GameTooltip:AddDoubleLine(e.letter .. "  " .. e.label, e.cmd, r, g, bl, 0.72, 0.68, 0.61)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: choose an addon", 1, 1, 1)
    local last = db().last and L.byKey[db().last]
    if last then GameTooltip:AddLine("Right-click: open " .. last.label .. " again", 1, 1, 1) end
    GameTooltip:AddLine("Drag: move around the minimap", 0.72, 0.68, 0.61)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place(b)
  return b
end

function L.SetShown(show)
  db().show = show and true or false
  if show and not L.button then L.button = buildButton() end
  if L.button then L.button:SetShown(db().show) end
  if L.onChange then for _, fn in ipairs(L.onChange) do pcall(fn, db().show) end end
end
function L.IsShown() return db().show end
-- settings pages can listen so their checkbox stays right when /tr button is used
function L.OnChange(fn) L.onChange = L.onChange or {}; L.onChange[#L.onChange + 1] = fn end

---------------------------------------------------------------------------
-- start up, and /tr
---------------------------------------------------------------------------
if not L.boot then
  L.boot = CreateFrame("Frame")
  L.boot:RegisterEvent("PLAYER_LOGIN")
  -- L.Init is looked up when the event fires, so the newest copy's version runs
  L.boot:SetScript("OnEvent", function() if L.Init then L.Init() end end)
end
function L.Init()
  if db().show then L.button = L.button or buildButton() end
end

local function findEntry(word)
  word = (word or ""):lower()
  if word == "" then return nil end
  for _, e in ipairs(L.entries) do
    if e.label:lower():sub(1, #word) == word or e.letter:lower() == word or e.cmd:lower() == word or e.cmd:lower() == "/" .. word then return e end
  end
end

SLASH_TOPRAMENLAUNCHER1 = "/tr"
SlashCmdList.TOPRAMENLAUNCHER = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" then
    L.ToggleMenu(L.button and L.button:IsShown() and L.button or nil)
  elseif cmd == "button" or cmd == "minimap" then
    L.SetShown(not db().show)
    say("minimap button " .. (db().show and "shown" or "hidden - /tr button brings it back") .. ".")
  elseif cmd == "macro" then
    local e = findEntry(rest)
    if e then L.MakeMacro(e.key)
    else
      local names = {}
      for _, x in ipairs(L.entries) do names[#names + 1] = x.label:lower() end
      say("/tr macro <" .. table.concat(names, " | ") .. ">")
    end
  elseif findEntry(cmd) then
    L.Open(findEntry(cmd).key)
  else
    say("/tr opens the Top Ramen menu. /tr button shows or hides the minimap button. /tr macro <addon> makes a macro. /tr <addon> opens one.")
  end
end
