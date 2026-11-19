-- Top Ramen Explorer: the window (/tre)
-- Top: the zone you're looking at, the area names it still needs, and the guide buttons.
-- Bottom: every Explorer achievement. Click a zone to look at it and open its map.
local _, ns = ...
local GOLD, GREEN, RED, GREY, WHITE = ns.GOLD, ns.GREEN, ns.RED, ns.GREY, ns.WHITE

local f, rows, selected = nil, {}, nil
local ROW_H = 22

local function progressText(a)
  if a.done then return GREEN .. "done|r" end
  return string.format("%s%d/%d|r", a.have == 0 and RED or GOLD, a.have, a.need)
end

local function button(parent, text, w, onClick)
  return ns.UI.Button(parent, w, 24, text, onClick)
end

local function build()
  local UI = ns.UI
  f = UI.Window("TopRamenExplorerWindow")
  f:SetSize(540, 680)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.pos = { p, rp, x, y }
  end)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  table.insert(UISpecialFrames, "TopRamenExplorerWindow")
  if ns.db.pos then
    f:ClearAllPoints()
    f:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3], ns.db.pos[4])
  end
  -- resizable, so the achievement list can be taller
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(540, 560, 1000, 1200)
  elseif f.SetMinResize then f:SetMinResize(540, 560); f:SetMaxResize(1000, 1200) end
  if ns.db.size then f:SetSize(math.max(540, ns.db.size[1]), math.max(560, ns.db.size[2])) end
  UI.Grip(f, function() ns.db.size = { f:GetWidth(), f:GetHeight() } end)

  local head = UI.Header(f, "Explorer")
  f.refreshBtn = UI.Button(head, 76, 28, "Refresh", function() ns.FullRefresh() end)
  f.refreshBtn:SetPoint("RIGHT", head.close, "LEFT", -4, 0)
  f.exportBtn = UI.Button(head, 64, 28, "Export", function() ns.ShowExport() end)
  f.exportBtn:SetPoint("RIGHT", f.refreshBtn, "LEFT", -4, 0)
  f.importBtn = UI.Button(head, 64, 28, "Import", function() ns.ShowImport() end)
  f.importBtn:SetPoint("RIGHT", f.exportBtn, "LEFT", -4, 0)

  local top = -(UI.HEAD_H + 12)
  -- overall progress: summary text and a bar
  f.summary = UI.Text(f, "GameFontNormal", UI.C.text)
  f.summary:SetPoint("TOPLEFT", 16, top)
  f.summary:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  f.summary:SetWordWrap(true)
  f.progress = UI.Bar(f, 100, 6)
  f.progress:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -6)
  f.progress:SetPoint("RIGHT", f, "RIGHT", -16, 0)

  -- the zone you're looking at, on its own panel
  local zp = UI.Panel(f)
  zp:SetPoint("TOPLEFT", f.progress, "BOTTOMLEFT", -6, -10)
  zp:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  zp:SetHeight(292)

  f.zone = UI.Text(f, "GameFontNormalLarge", UI.C.gold)
  f.zone:SetPoint("TOPLEFT", zp, "TOPLEFT", 12, -12)
  f.zone:SetPoint("RIGHT", zp, "RIGHT", -12, 0)

  f.missing = UI.Text(f, "GameFontHighlightSmall", UI.C.text)
  f.missing:SetPoint("TOPLEFT", f.zone, "BOTTOMLEFT", 0, -10)
  f.missing:SetPoint("RIGHT", zp, "RIGHT", -12, 0)
  f.missing:SetJustifyV("TOP")
  f.missing:SetHeight(130)
  f.missing:SetWordWrap(true)
  f.missing:SetSpacing(4) -- room between wrapped lines

  f.status = UI.Text(f, "GameFontNormalSmall", UI.C.muted)
  f.status:SetPoint("TOPLEFT", f.missing, "BOTTOMLEFT", 0, -10)
  f.status:SetPoint("RIGHT", zp, "RIGHT", -12, 0)
  f.status:SetSpacing(3)

  f.guideBtn = button(f, "Guide me", 104, function()
    if ns.guide then ns.StopGuide() else ns.GuideNext() end
  end)
  f.guideBtn:SetPoint("BOTTOMLEFT", zp, "BOTTOMLEFT", 10, 40)
  f.skipBtn = button(f, "Skip spot", 92, function() ns.IgnoreCurrent() end)
  f.skipBtn:SetPoint("LEFT", f.guideBtn, "RIGHT", 6, 0)
  f.mapBtn = button(f, "Open map", 92, function()
    local id = selected or ns.PlayerZone()
    if id then
      if OpenWorldMap then OpenWorldMap(id) else ToggleWorldMap() end
    end
  end)
  f.mapBtn:SetPoint("LEFT", f.skipBtn, "RIGHT", 6, 0)
  f.hereBtn = button(f, "This zone", 92, function() selected = nil; ns.Refresh() end)
  f.hereBtn:SetPoint("LEFT", f.mapBtn, "RIGHT", 6, 0)

  -- waypoints on every trigger spot at once
  f.markBtn = button(f, "Mark zone", 90, function()
    local id = selected or ns.PlayerZone()
    local n = ns.MarkZone(id)
    if TomTom then ns.Print("marked " .. n .. " spots in " .. (id and ns.ZoneName(id) or "this zone") .. ".") end
    ns.Refresh()
  end)
  f.markBtn:SetPoint("TOPLEFT", f.guideBtn, "BOTTOMLEFT", 0, -6)
  f.markWholeBtn = button(f, "Mark whole zone", 120, function() ns.MarkWholeZone(selected or ns.PlayerZone()) end)
  f.markWholeBtn:SetPoint("LEFT", f.markBtn, "RIGHT", 6, 0)
  f.markAllBtn = button(f, "Mark all zones", 112, function() ns.MarkAllZones() end)
  f.markAllBtn:SetPoint("LEFT", f.markWholeBtn, "RIGHT", 6, 0)
  f.clearBtn = button(f, "Clear waypoints", 120, function() ns.ClearMarks() end)
  f.clearBtn:SetPoint("LEFT", f.markAllBtn, "RIGHT", 6, 0)

  -- achievement list
  local header = UI.Text(f, "GameFontNormal", UI.C.gold)
  header:SetPoint("TOPLEFT", zp, "BOTTOMLEFT", 6, -12)
  header:SetText("Explorer achievements")
  local well = UI.Panel(f, UI.C.well)
  well:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -6, -6)
  well:SetPoint("BOTTOMRIGHT", -10, 10)

  local sf = CreateFrame("ScrollFrame", "TopRamenExplorerScroll", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
  sf:SetPoint("BOTTOMRIGHT", -34, 16)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(440, 10)
  sf:SetScrollChild(content)
  sf:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)
  f.content = content
end

local function row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, f.content)
  r:SetHeight(ROW_H - 2)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 6, 0)
  r.name:SetJustifyH("LEFT")
  r.prog = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.prog:SetPoint("RIGHT", -6, 0)
  r.prog:SetJustifyH("RIGHT")
  r.prog:SetWidth(40)
  r.bar = ns.UI.Bar(r, 70, 4)
  r.bar:SetPoint("RIGHT", r.prog, "LEFT", -6, 0)
  r:SetScript("OnClick", function(self)
    if self.a and self.a.zone then
      selected = self.a.zone
      ns.Refresh()
    end
  end)
  r:SetScript("OnEnter", function(self)
    if not self.a then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.a.name, 1, 0.82, 0)
    for _, c in ipairs(self.a.criteria) do
      if c.done then GameTooltip:AddLine(c.name, 0.25, 0.8, 0.25) else GameTooltip:AddLine(c.name, 0.6, 0.6, 0.6) end
    end
    if self.a.zone then GameTooltip:AddLine("Click to look at this zone.", 1, 1, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function render()
  if not (f and f:IsShown()) then return end
  local list = ns.achievements or ns.ReadAchievements()

  if #list == 0 then
    f.summary:SetText(RED .. "No Adventure > Explorer achievements found on this client.|r  Try /tre probe.")
  else
    local done, zones, zonesDone = 0, 0, 0
    for _, a in ipairs(list) do
      if a.done then done = done + 1 end
      if not a.meta then zones = zones + 1; if a.done then zonesDone = zonesDone + 1 end end
    end
    f.summary:SetText(string.format("%s: %s%d/%d|r achievements, %s%d/%d|r zones explored",
      ns.categoryTitle or "Explorer", GOLD, done, #list, GOLD, zonesDone, zones))
    f.progress:SetValue(zones > 0 and zonesDone / zones or 0)
  end

  -- zone detail
  local here = ns.PlayerZone()
  local mapID = selected or here
  local a = mapID and ns.AchFor(mapID)
  f.zone:SetText((mapID and ns.ZoneName(mapID) or "?") .. (mapID == here and GREY .. "  (you are here)|r" or ""))
  if a then
    local missing = ns.MissingAreas(a)
    if a.done then
      f.missing:SetText(GREEN .. a.name .. " - complete.|r")
    else
      local zone = ns.ZoneName(mapID)
      local names, tips = {}, {}
      for _, n in ipairs(missing) do
        local x, y, kind = ns.KnownSpot(zone, n)
        local color, mark = "|cff4dccff", ""
        if kind == "unverified" then color, mark = "|cffff9933", "?"
        elseif kind == "cataclysm" then color, mark = "|cffb980ff", " Cataclysm" end
        names[#names + 1] = x and string.format("%s %s(%.1f, %.1f%s)|r%s", n, color, x, y, mark, WHITE) or n
        local tip = ns.Tip(zone, n)
        if tip then tips[#tips + 1] = GREY .. n .. ": " .. tip .. "|r" end
      end
      f.missing:SetText(string.format("%s %s\n%sStill needed:|r %s%s|r%s", a.name, progressText(a), GOLD, WHITE,
        table.concat(names, ", "), #tips > 0 and ("\n" .. table.concat(tips, "\n")) or ""))
    end
  else
    f.missing:SetText(GREY .. "No Explorer achievement for this map.|r")
  end

  local spots = mapID and ns.SortedSpots(mapID) or {}

  -- confirmed spots across ALL of the zone's areas, found or not (what you'd share)
  local confirmedLine = ""
  if a then
    local zone, conf, mine = ns.ZoneName(mapID), 0, 0
    for _, c in ipairs(a.criteria) do
      local _, _, kind = ns.KnownSpot(zone, c.name)
      if kind == "found" or kind == "shared" or kind == "confirmed" then conf = conf + 1 end
      if kind == "found" then mine = mine + 1 end
    end
    confirmedLine = string.format("|cff4dccffConfirmed in game: %d of %d areas|r (%d by you)", conf, #a.criteria, mine)
  end

  if a and a.done then
    f.status:SetText(confirmedLine)
  else
    local known, unv, cata, edge = 0, 0, 0, 0
    for _, s in ipairs(spots) do
      if s.kind == "cataclysm" then cata = cata + 1
      elseif s.unverified then unv = unv + 1
      elseif s.known then known = known + 1
      elseif s.edge then edge = edge + 1 end
    end
    -- where the spots for the areas you still need come from (only the kinds that are there)
    local parts = {}
    if known > 0 then parts[#parts + 1] = "|cff4dccff" .. known .. " confirmed|r" end
    if unv > 0 then parts[#parts + 1] = "|cffff9933" .. unv .. " Wowhead|r" end
    if cata > 0 then parts[#parts + 1] = "|cffb980ff" .. cata .. " Cataclysm|r" end
    local scan = #spots - known - unv - cata
    if scan > 0 then parts[#parts + 1] = scan .. " map scan" end
    local txt = string.format("Still needed: %s%d|r spots%s", GOLD, #spots,
      #parts > 0 and ("  (" .. table.concat(parts, ", ") .. ")") or "")
    if confirmedLine ~= "" then txt = confirmedLine .. "\n" .. txt end
    if not ns.CanScan() then txt = txt .. "\n" .. RED .. "This client doesn't report map exploration, so only confirmed spots show.|r" end
    local g = ns.guide
    if g then
      local px, py = ns.PlayerXY(g.mapID)
      local yd = ns.Yards(g.mapID, px, py, g.x, g.y)
      txt = txt .. string.format("\n%sGuiding:|r %s %.1f, %.1f%s", GREEN, ns.ZoneName(g.mapID), g.x * 100, g.y * 100,
        yd and string.format("  (%d yd)", yd) or "")
    end
    f.status:SetText(txt)
  end
  f.guideBtn:SetText(ns.guide and "Stop guide" or "Guide me")
  f.skipBtn:SetEnabled(ns.guide ~= nil)
  f.clearBtn:SetText(#ns.marks > 0 and ("Clear (" .. #ns.marks .. ")") or "Clear waypoints")
  f.markAllBtn:SetEnabled(TomTom ~= nil)

  -- list
  for i, ach in ipairs(list) do
    local r = row(i)
    r.a = ach
    local label = ach.meta and (GOLD .. ach.name .. "|r") or ach.name
    if ns.SameZone(ach, mapID) then label = "> " .. label end
    if ach.done then label = GREY .. ach.name .. "|r" end
    r.name:SetText(label)
    r.prog:SetText(progressText(ach))
    r.bar:SetValue((ach.need or 0) > 0 and (ach.have or 0) / ach.need or (ach.done and 1 or 0))
    if ns.SameZone(ach, mapID) then r.bg:SetColorTexture(1, 0.82, 0, 0.1)
    else r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0) end
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  f.content:SetHeight(math.max(10, #list * ROW_H))
end

local function report(err)
  ns.Print(ns.RED .. "window error:|r " .. tostring(err) .. "  (please send this to Crayon Ponyfish)")
end

function ns.ToggleWindow()
  if not f then
    -- build it hidden: a brand-new frame starts out shown, which made the first /tre close it.
    -- Even if building hits an error, keep going so the window still opens.
    local ok, err = pcall(build)
    if not ok then report(err) end
    if not f then return end
    f:Hide()
  end
  if f:IsShown() then
    f:Hide()
    return
  end
  f:Show()
  local ok, err = pcall(function() ns.ReadAchievements(); render() end)
  if not ok then report(err) end
end

-- ticker: keep the yardage fresh while guiding and the window is open
local tick = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
  tick = tick + dt
  if tick < 1 then return end
  tick = 0
  if ns.guide and f and f:IsShown() then render() end
end)

ns.Refresh = function()
  render()
  if ns.UpdatePins then ns.UpdatePins() end
end
