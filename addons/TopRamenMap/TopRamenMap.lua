-- Top Ramen Map: a big live minimap plus a whole-dungeon overview.
-- The real minimap is moved into the window while it's open and put back
-- exactly as it was (minus nothing: its round mask is never touched).

local ADDON, ns = ...
local UI = ns.UI
local GOLD = UI.HEX.gold

local defaults = {
  w = 560, h = 880,   -- stacked: minimap on top, overview below
  stack = true,
  point = { "CENTER", "CENTER", 0, 0 },
  autoOpen = true,    -- open automatically in dungeons/raids
  overview = true,    -- show the whole-dungeon overview beside the minimap
  zoom = 0,           -- 0 = most zoomed out
}

local db
local attached = false
local autoOpened = false
local saved

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame = UI.Window("TopRamenMapFrame", 1) -- fully opaque: nothing behind shows through
frame:Hide()
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
if frame.SetResizeBounds then frame:SetResizeBounds(320, 360, 2000, 1400)
elseif frame.SetMinResize then frame:SetMinResize(320, 360) end
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
tinsert(UISpecialFrames, "TopRamenMapFrame") -- Escape closes it

local head = UI.Header(frame, "Map")
local title = head.sub

local function Tip(b, text)
  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(text); GameTooltip:Show()
  end)
  b:HookScript("OnLeave", GameTooltip_Hide)
end
local zoomIn = UI.Button(head, 24, 22, "+")
local zoomOut = UI.Button(head, 24, 22, "-")
local overBtn = UI.Button(head, 84, 22, "Overview")
zoomIn:SetPoint("RIGHT", head.close, "LEFT", -6, 0)
zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -4, 0)
overBtn:SetPoint("RIGHT", zoomOut, "LEFT", -10, 0)
local layoutBtn = UI.Button(head, 64, 22, "Stack")
layoutBtn:SetPoint("RIGHT", overBtn, "LEFT", -4, 0)
local autoBtn = UI.Button(head, 50, 22, "Auto")
autoBtn:SetPoint("RIGHT", layoutBtn, "LEFT", -4, 0)
Tip(zoomIn, "Zoom in"); Tip(zoomOut, "Zoom out"); Tip(overBtn, "Show or hide the whole-dungeon map")
Tip(layoutBtn, "Switch between the minimap above the overview and side by side")
Tip(autoBtn, "Open this window automatically when you enter a dungeon")
-- keep the zone/area line from running under the buttons
title:SetPoint("RIGHT", autoBtn, "LEFT", -8, 0)
title:SetWordWrap(false)

-- Left: where the minimap sits. Right: the overview.
local well = UI.Frame(frame, UI.C.well, UI.C.line, 1)
local holder = CreateFrame("Frame", nil, well)
holder:SetPoint("TOPLEFT", 1, -1)
holder:SetPoint("BOTTOMRIGHT", -1, 1)
local overview = ns.Overview.Create(frame)

local grip = UI.Grip(frame)
grip:SetFrameLevel(frame:GetFrameLevel() + 30)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function UpdateTitle()
  local zone, sub = GetRealZoneText() or "", GetSubZoneText() or ""
  local text = "Map  " .. UI.HEX.text .. zone .. "|r"
  if sub ~= "" and sub ~= zone then text = text .. "  ·  " .. UI.HEX.gold .. sub .. "|r" end
  title:SetText(text)
end

local function ClampZoom(z)
  local max = (Minimap:GetZoomLevels() or 1) - 1
  return math.max(0, math.min(max, z))
end

-- Nudging the zoom makes the game redraw the minimap.
local function RefreshMinimap()
  local z = Minimap:GetZoom()
  local other = ClampZoom((z > 0) and (z - 1) or (z + 1))
  if other ~= z then Minimap:SetZoom(other) end
  Minimap:SetZoom(z)
end

local function SetZoom(z)
  z = ClampZoom(z)
  db.zoom = z
  if attached then Minimap:SetZoom(z) end
end
zoomIn:SetScript("OnClick", function() SetZoom(Minimap:GetZoom() + 1) end)
zoomOut:SetScript("OnClick", function() SetZoom(Minimap:GetZoom() - 1) end)

---------------------------------------------------------------------------
-- Borrow / return the minimap
---------------------------------------------------------------------------
local hidden, hiddenSet, sweeper = {}, {}, nil

local function Protected(obj)
  return obj and obj.IsProtected and obj:IsProtected()
end

-- While fighting, the game won't let addons move, resize or hide protected
-- frames. If the minimap is one of them, wait for the fight to end.
local pending
local function Locked()
  return InCombatLockdown() and (Protected(Minimap) or Protected(MinimapCluster))
end

local function HideThing(obj)
  if obj and obj ~= Minimap and not Protected(obj) and obj:IsShown() then
    obj:Hide()
    if not hiddenSet[obj] then hiddenSet[obj] = true; hidden[#hidden + 1] = obj end
  end
end

-- The border, buttons and addon icons on the minimap. Some addon buttons
-- show themselves again, so this runs every half second while open.
local function HideExtras()
  for _, child in ipairs({ Minimap:GetChildren() }) do HideThing(child) end
end

local function Layout()
  if not attached then return end
  if Locked() then pending = pending or "layout"; return end
  local w, h = holder:GetSize()
  local s = math.floor(math.min(w, h))
  if s < 50 then return end
  Minimap:SetSize(s, s)
  C_Timer.After(0, RefreshMinimap)
end

local clusterHidden = false
local function Attach()
  if attached then return end
  if Locked() then pending = "attach"; return end
  saved = {
    parent = Minimap:GetParent(),
    points = {},
    w = Minimap:GetWidth(), h = Minimap:GetHeight(),
    scale = Minimap:GetScale(),
    strata = Minimap:GetFrameStrata(),
    level = Minimap:GetFrameLevel(),
    zoom = Minimap:GetZoom(),
    wheel = Minimap:IsMouseWheelEnabled(),
  }
  for i = 1, Minimap:GetNumPoints() do saved.points[i] = { Minimap:GetPoint(i) } end

  wipe(hidden); wipe(hiddenSet)
  HideExtras()
  Minimap:SetParent(holder)
  Minimap:ClearAllPoints()
  Minimap:SetPoint("CENTER", holder, "CENTER")
  Minimap:SetScale(1)
  Minimap:SetFrameStrata(frame:GetFrameStrata())
  Minimap:SetFrameLevel(holder:GetFrameLevel() + 2)
  Minimap:EnableMouseWheel(true)

  -- The empty corner (zone text, clock, tracking...)
  clusterHidden = false
  if MinimapCluster and MinimapCluster:IsShown() and not Protected(MinimapCluster) then
    MinimapCluster:Hide(); clusterHidden = true
  end

  attached = true
  Minimap:SetZoom(ClampZoom(db.zoom))
  Layout()
  if sweeper then sweeper:Cancel() end
  sweeper = C_Timer.NewTicker(0.5, function() if attached and not InCombatLockdown() then HideExtras() end end)
end

local function Detach()
  if pending == "attach" then pending = nil end
  if not attached or not saved then return end
  if Locked() then pending = "detach"; return end
  attached = false
  if sweeper then sweeper:Cancel(); sweeper = nil end
  Minimap:SetParent(saved.parent)
  Minimap:ClearAllPoints()
  for _, p in ipairs(saved.points) do Minimap:SetPoint(unpack(p)) end
  Minimap:SetScale(saved.scale)
  Minimap:SetSize(saved.w, saved.h)
  Minimap:SetFrameStrata(saved.strata)
  Minimap:SetFrameLevel(saved.level)
  Minimap:EnableMouseWheel(saved.wheel)
  Minimap:SetZoom(ClampZoom(saved.zoom))
  for _, obj in ipairs(hidden) do
    if not Protected(obj) then obj:Show() end
  end
  wipe(hidden); wipe(hiddenSet)
  if clusterHidden and MinimapCluster then MinimapCluster:Show() end
  clusterHidden = false
  -- Make the game redraw it at its normal size.
  Minimap:Hide(); Minimap:Show()
  C_Timer.After(0, RefreshMinimap)
  C_Timer.After(0.25, RefreshMinimap)
end

Minimap:HookScript("OnMouseWheel", function(_, delta)
  if attached then SetZoom(Minimap:GetZoom() + (delta > 0 and 1 or -1)) end
end)

---------------------------------------------------------------------------
-- Layout of the two panes
---------------------------------------------------------------------------
local function LayoutPanes()
  local top = -(UI.HEAD_H + 2 + 6)
  local W = frame:GetWidth() - 16
  local H = frame:GetHeight() - (UI.HEAD_H + 2 + 6) - 10
  well:ClearAllPoints()
  overview:ClearAllPoints()
  if db and db.overview and db.stack then
    -- minimap on top (as tall as it is wide, at most ~45% of the height)
    local L = math.max(160, math.min(W, H * 0.45))
    well:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, top)
    well:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, top)
    well:SetHeight(L)
    overview:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 0, -8)
    overview:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 10)
    overview:Show()
    overBtn:LockHighlight()
  elseif db and db.overview then
    local L = math.max(200, math.min(H, W * 0.45))
    well:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, top)
    well:SetSize(L, H)
    overview:SetPoint("TOPLEFT", well, "TOPRIGHT", 8, 0)
    overview:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 10)
    overview:Show()
    overBtn:LockHighlight()
  else
    well:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, top)
    well:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 10)
    overview:Hide()
    overBtn:UnlockHighlight()
  end
  Layout()
end
frame:SetScript("OnSizeChanged", LayoutPanes)
overBtn:SetScript("OnClick", function()
  db.overview = not db.overview
  LayoutPanes()
end)

local ApplyPosition -- (defined below)
local function PaintToggles()
  if not db then return end
  layoutBtn:SetText(db.stack and "Stack" or "Side")
  if db.autoOpen then autoBtn:LockHighlight() else autoBtn:UnlockHighlight() end
end

local function SetLayout(stack)
  db.stack = stack
  -- keep the window's top-left corner where it is
  local left, top = frame:GetLeft(), frame:GetTop()
  if db.stack then db.w, db.h = 560, 880 else db.w, db.h = 1040, 600 end
  if left and top then
    db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
  end
  ApplyPosition(); LayoutPanes(); PaintToggles()
end

local function SetAuto(on)
  db.autoOpen = on
  PaintToggles()
end

layoutBtn:SetScript("OnClick", function() SetLayout(not db.stack) end)
autoBtn:SetScript("OnClick", function() SetAuto(not db.autoOpen) end)

---------------------------------------------------------------------------
-- Boss kills
-- Forever hides unit IDs inside dungeons ("secret" values), and touching
-- them makes the game distrust the addon. So kills come from the game's
-- encounter-end message (boss name only), plus shift-click on a pin to
-- mark one by hand. A run is forgotten after 2 hours or with /trmap newrun.
---------------------------------------------------------------------------
local RUN_TIMEOUT = 2 * 60 * 60

local function Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function Run(dungeon)
  if dungeon and (not db.run or db.run.dungeon ~= dungeon or (time() - (db.run.last or 0)) > RUN_TIMEOUT) then
    db.run = { dungeon = dungeon, dead = {}, last = time() }
  end
  return db.run
end

function ns.IsDead(key)
  return db and db.run and db.run.dead[key] or false
end

function ns.SetDead(key, dead)
  local run = db.run
  if not run then return end
  run.dead[key] = dead or nil
  run.last = time()
  ns.Overview.Refresh()
end

-- Areas placed by Ctrl-click, per dungeon: [dungeon]["name@level"] = area
function ns.Learned(dungeon)
  return db and dungeon and db.learned and db.learned[dungeon] or {}
end
function ns.Learn(dungeon, area)
  db.learned = db.learned or {}
  db.learned[dungeon] = db.learned[dungeon] or {}
  db.learned[dungeon][area.name .. "@" .. area.floor] = area
end
function ns.AllLearned() return db and db.learned or {} end

-- Which dungeon you're in, by the overview's names. ForeverDungeonJournal
-- knows the game's instance IDs and tells the Scarlet Monastery wings, Dire
-- Maul and Stratholme apart, and its names are the ones our data uses. If it
-- can't say, fall back to the game's instance name.
local function CurrentDungeonName()
  local FDJ = _G.ForeverDungeonJournal_NS
  if FDJ and FDJ.CurrentDungeon then
    local ok, n = pcall(FDJ.CurrentDungeon)
    if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then return n end
  end
  local name = GetInstanceInfo()
  if issecretvalue and issecretvalue(name) then return nil end
  return name
end
ns.CurrentDungeonName = CurrentDungeonName

---------------------------------------------------------------------------
-- Window scripts
---------------------------------------------------------------------------
local function SavePosition()
  local p, _, rp, x, y = frame:GetPoint(1)
  db.point = { p, rp, x, y }
  db.w, db.h = frame:GetSize()
end

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); SavePosition(); LayoutPanes() end)
holder:SetScript("OnSizeChanged", Layout)
frame:SetScript("OnShow", function()
  UpdateTitle(); PaintToggles(); LayoutPanes(); Attach()
  local _, kind = GetInstanceInfo()
  local name = CurrentDungeonName()
  local inside = (kind == "party" or kind == "raid")
  if inside then Run(name) end
  ns.Overview.SetDungeon(inside and name or nil)
  ns.Overview.SetArea(GetSubZoneText())
end)
local areaTicker
frame:HookScript("OnShow", function()
  if areaTicker then areaTicker:Cancel() end
  areaTicker = C_Timer.NewTicker(1, function()
    -- the Scarlet wing (and the like) can only be told once you're inside
    local _, kind = GetInstanceInfo()
    if kind == "party" or kind == "raid" then
      local name = CurrentDungeonName()
      if name then Run(name); ns.Overview.SetDungeon(name) end
    end
    ns.Overview.SetArea(GetSubZoneText())
  end)
end)
frame:SetScript("OnHide", function()
  Detach(); autoOpened = false
  if areaTicker then areaTicker:Cancel(); areaTicker = nil end
end)

-- Layering: join the other Top Ramen windows (the one opened or clicked last
-- is on the "HIGH" layer above the game's bars and frames, the rest drop to
-- "MEDIUM"). The borrowed minimap has to follow the window's layer, or it
-- would be drawn under the window or poke through windows above it.
-- (Registered after the scripts above, so their hooks stay in place.)
local function SyncMinimapLayer()
  if not attached then return end
  Minimap:SetFrameStrata(frame:GetFrameStrata())
  Minimap:SetFrameLevel(holder:GetFrameLevel() + 2)
end
UI.RegisterWindow(frame)
hooksecurefunc(frame, "SetFrameStrata", SyncMinimapLayer)
hooksecurefunc(frame, "Raise", SyncMinimapLayer)
frame:HookScript("OnMouseDown", SyncMinimapLayer)

function ApplyPosition()
  frame:ClearAllPoints()
  local p = db.point
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  frame:SetSize(db.w, db.h)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function InDungeon()
  local inInstance, kind = IsInInstance()
  return inInstance and (kind == "party" or kind == "raid")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:SetScript("OnEvent", function(_, event, arg1, ...)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    TopRamenMapDB = TopRamenMapDB or {}
    db = TopRamenMapDB
    for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
    if not db.v4 then -- 0.4: stacked layout
      db.stack, db.w, db.h, db.v3, db.v4 = true, defaults.w, defaults.h, true, true
    end
    db.square = nil
    ApplyPosition()
    return
  end
  if not db then return end

  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if arg1 == ADDON then
      local fn = ...   -- (addon, function) arrive as arg1, ...
      print(GOLD .. "Top Ramen Map|r was blocked from: " .. tostring(fn) .. (InCombatLockdown() and " (in combat)" or ""))
    end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    local todo = pending
    pending = nil
    if todo == "attach" then if frame:IsShown() then Attach() end
    elseif todo == "detach" then if not frame:IsShown() then Detach() end
    elseif todo == "layout" then Layout() end
    return
  end

  if event == "ENCOUNTER_END" then
    local name, _, _, success = ...
    name, success = Plain(name), Plain(success)
    if success == 1 and type(name) == "string" then
      local key = ns.Overview.KeyByName(name)
      if key then ns.SetDead(key, true) end
    end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    if InDungeon() then
      if db.autoOpen and not frame:IsShown() then autoOpened = true; frame:Show() end
      local name = CurrentDungeonName()
      Run(name)
      ns.Overview.SetDungeon(name)
    else
      if autoOpened and frame:IsShown() then frame:Hide() end
      ns.Overview.SetDungeon(nil)
    end
    UpdateTitle()
    ns.Overview.SetArea(GetSubZoneText())
  else
    UpdateTitle()
    ns.Overview.SetArea(GetSubZoneText())
  end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_TOPRAMENMAP1 = "/trmap"
SLASH_TOPRAMENMAP2 = "/topramenmap"
SlashCmdList.TOPRAMENMAP = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "auto" then
    SetAuto(not db.autoOpen)
    print(GOLD .. "Top Ramen Map|r auto-open in dungeons: " .. (db.autoOpen and "on" or "off"))
  elseif msg == "reset" then
    db.point = { "CENTER", "CENTER", 0, 0 }
    if db.stack then db.w, db.h = 560, 880 else db.w, db.h = 1040, 600 end
    ApplyPosition()
  elseif msg == "newrun" then
    db.run = nil
    ns.Overview.Refresh()
    print(GOLD .. "Top Ramen Map|r boss kills cleared.")
  elseif msg == "stack" or msg == "side" then
    SetLayout(msg == "stack")
    print(GOLD .. "Top Ramen Map|r layout: " .. (db.stack and "stacked (minimap on top)" or "side by side"))
  elseif msg == "areas" then
    ns.Overview.DumpLearned()
  elseif msg == "forget" then
    local name = CurrentDungeonName()
    if db.learned then db.learned[name] = nil end
    print(GOLD .. "Top Ramen Map|r: forgot the areas you placed in " .. tostring(name) .. ". /reload to redraw.")
  elseif msg == "help" then
    print(GOLD .. "Top Ramen Map|r: /trmap (open/close), /trmap auto, /trmap reset, /trmap stack | side (layout), /trmap newrun, /trmap areas (list placed areas), /trmap forget (this dungeon's placed areas)")
  else
    frame:SetShown(not frame:IsShown())
  end
end
