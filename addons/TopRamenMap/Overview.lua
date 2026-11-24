-- The whole-dungeon overview: map art (with level tabs), boss pins, the area
-- you're in lit up, and (where a walking net exists) a dotted route to the
-- boss you click. The game hides your exact spot inside dungeons, so "where
-- you are" is the named area the game reports above the minimap.
local ADDON, ns = ...
local UI = ns.UI
local C, HEX = UI.C, UI.HEX
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FDJ_PORTRAITS = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\Portraits\\"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local O = {}
ns.Overview = O

local pane, art, empty, status, status2
local tabs = {}
local glows, pins, dots, marks = {}, {}, {}, {}
local data, dungeonName, areas
local viewFloor = 1
local target, route, routeAreas
local rawSub, current, lastArea -- current = the area entry you're in

local function Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function HasJournal()
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("ForeverDungeonJournal") end
  return IsAddOnLoaded and IsAddOnLoaded("ForeverDungeonJournal")
end

local function Dead(boss) return ns.IsDead and ns.IsDead(boss.name) end

-- The level the game says you're on (nil if it won't say).
local function GameFloor()
  if not (data and C_Map and C_Map.GetBestMapForUnit) then return end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  id = ok and Plain(id) or nil
  if not id then return end
  for i, f in ipairs(data.floors) do if f.mapID == id then return i end end
end

---------------------------------------------------------------------------
-- Areas: the map's own plus any you placed with Ctrl-click
---------------------------------------------------------------------------
local function BuildAreas()
  areas = {}
  local learned = ns.Learned and ns.Learned(dungeonName) or {}
  for _, a in ipairs(data.areas or {}) do
    if not learned[a.name .. "@" .. a.floor] then areas[#areas + 1] = a end
  end
  for _, a in pairs(learned) do areas[#areas + 1] = a end
end

-- The entry for an area name: the one on the game's level, else the one on
-- the level shown, else the first.
local function FindArea(name)
  if not name then return end
  local list = {}
  for _, a in ipairs(areas) do if a.name == name then list[#list + 1] = a end end
  if #list <= 1 then return list[1] end
  local gf = GameFloor()
  for _, a in ipairs(list) do if a.floor == gf then return a end end
  for _, a in ipairs(list) do if a.floor == viewFloor then return a end end
  return list[1]
end

---------------------------------------------------------------------------
-- Routes (only where the dungeon has a walking net)
---------------------------------------------------------------------------
local function Dist(a, b)
  local A, B = data.nodes[a], data.nodes[b]
  local dx, dy = (A[1] - B[1]) * (1002 / 668), A[2] - B[2]
  return math.sqrt(dx * dx + dy * dy)
end

local function Neighbours()
  if data._nb then return data._nb end
  local nb = {}
  for _, e in ipairs(data.edges) do
    nb[e[1]] = nb[e[1]] or {}; nb[e[2]] = nb[e[2]] or {}
    table.insert(nb[e[1]], e[2]); table.insert(nb[e[2]], e[1])
  end
  data._nb = nb
  return nb
end

local function FindRoute(goal)
  local starts = {}
  if lastArea then
    for id, n in pairs(data.nodes) do if n[3] == lastArea then starts[#starts + 1] = id end end
  end
  if #starts == 0 then starts = { data.entrance } end
  local dist, prev, done = {}, {}, {}
  for _, s in ipairs(starts) do dist[s] = 0 end
  local nb = Neighbours()
  while true do
    local best, bd
    for id, d in pairs(dist) do
      if not done[id] and (not bd or d < bd) then best, bd = id, d end
    end
    if not best or best == goal then break end
    done[best] = true
    for _, n in ipairs(nb[best] or {}) do
      local nd = bd + Dist(best, n)
      if not dist[n] or nd < dist[n] then dist[n], prev[n] = nd, best end
    end
  end
  if not dist[goal] then return nil end
  local path, at = {}, goal
  while at do table.insert(path, 1, at); at = prev[at] end
  return path
end

local function AreasOf(path)
  local list, seen = {}, {}
  for _, id in ipairs(path) do
    local a = data.nodes[id][3]
    if a and not seen[a] then seen[a] = true; list[#list + 1] = a end
  end
  return list
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function ToArt(x, y)
  return x * art:GetWidth(), -y * art:GetHeight()
end

local function DrawDots()
  for _, d in ipairs(dots) do d:Hide() end
  if not route or #route < 2 or viewFloor ~= 1 then return end
  local n, step = 0, 9
  for i = 1, #route - 1 do
    local ax, ay = ToArt(data.nodes[route[i]][1], data.nodes[route[i]][2])
    local bx, by = ToArt(data.nodes[route[i + 1]][1], data.nodes[route[i + 1]][2])
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local count = math.max(1, math.floor(len / step))
    for k = 0, count - 1 do
      n = n + 1
      local d = dots[n]
      if not d then
        d = art:CreateTexture(nil, "OVERLAY", nil, 1)
        d:SetTexture(MEDIA .. "dot")
        d:SetSize(6, 6)
        dots[n] = d
      end
      local t = k / count
      d:ClearAllPoints()
      d:SetPoint("CENTER", art, "TOPLEFT", ax + (bx - ax) * t, ay + (by - ay) * t)
      d:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.95)
      d:Show()
    end
  end
end

local function PaintGlows()
  local onRoute = {}
  for _, a in ipairs(routeAreas or {}) do onRoute[a] = true end
  for a, g in pairs(glows) do
    if a.floor ~= viewFloor then
      g:Hide()
    elseif a == current then
      g:SetVertexColor(1, 0.82, 0.2, 0.75); g:Show()
    elseif onRoute[a.name] then
      g:SetVertexColor(1, 0.82, 0.2, 0.22); g:Show()
    else
      g:Hide()
    end
  end
end

local function PaintPins()
  for _, p in ipairs(pins) do
    p:SetShown(p.boss.floor == viewFloor)
    local dead = Dead(p.boss)
    p.icon:SetDesaturated(dead)
    p.icon:SetAlpha(dead and 0.45 or 1)
    p.x:SetShown(dead)
    if p.boss == target then
      p.ring:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1); p:SetSize(34, 34)
    else
      p.ring:SetVertexColor(C.trim[1] * 1.6, C.trim[2] * 1.6, C.trim[3] * 1.6, 1); p:SetSize(26, 26)
    end
  end
end

local function PaintMarks()
  for _, m in ipairs(marks) do m:SetShown(m.data.floor == viewFloor) end
end

local function PaintTabs()
  local n = data and #data.floors or 0
  local prev
  for i, t in ipairs(tabs) do
    if i <= n and n > 1 then
      local hasTarget = target and target.floor == i
      local here = current and current.floor == i
      t:SetText((data.floors[i].label or tostring(i)) .. (here and " •" or "") .. (hasTarget and " ★" or ""))
      t:SetWidth(math.max(44, (t.label:GetStringWidth() or 24) + 20))
      t:ClearAllPoints()
      if prev then t:SetPoint("LEFT", prev, "RIGHT", 4, 0)
      else t:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -6) end
      prev = t
      if i == viewFloor then t:LockHighlight() else t:UnlockHighlight() end
      t:Show()
    else
      t:Hide()
    end
  end
end

local function BossArea(boss)
  -- the named area nearest the boss on its level
  local best, bd
  for _, a in ipairs(areas) do
    if a.floor == boss.floor then
      local d = math.sqrt(((a.x - boss.x) * 1.5) ^ 2 + (a.y - boss.y) ^ 2)
      if d <= a.r * 1.6 and (not bd or d < bd) then best, bd = a, d end
    end
  end
  return best
end

local function PaintStatus()
  if not data then return end
  local left = 0
  for _, b in ipairs(data.bosses) do if not b.rare and not b.quest and not Dead(b) then left = left + 1 end end
  local multi = #data.floors > 1
  local where
  if current then
    where = HEX.gold .. current.name .. "|r" .. (multi and (HEX.muted .. " (level " .. current.floor .. ")|r") or "")
  elseif lastArea then
    where = HEX.muted .. "last seen in|r " .. HEX.gold .. lastArea .. "|r"
  else
    where = HEX.muted .. "an unmarked part|r"
  end
  local unknown = rawSub and not current

  if not target then
    status:SetText("You're in " .. where .. HEX.muted .. "   ·   bosses left: |r" .. HEX.text .. left .. "|r")
    if unknown then
      status2:SetText(HEX.muted .. "Ctrl-click the map where you're standing to mark |r" .. HEX.gold .. rawSub .. "|r")
    else
      status2:SetText(HEX.muted .. "Click a boss to select it. Shift-click marks it dead. Ctrl-click the map to place the area you're in.|r")
    end
    return
  end
  if Dead(target) then
    status:SetText(HEX.text .. target.name .. "|r " .. HEX.muted .. "is dead.|r")
    status2:SetText(HEX.muted .. "Click another boss.|r")
    return
  end

  if not data.nodes then
    local ba = BossArea(target)
    local spot = (ba and ba.name) or "this map"
    if multi then spot = spot .. " (level " .. target.floor .. ")" end
    status:SetText(HEX.gold .. target.name .. "|r" .. HEX.muted .. ":  |r" .. HEX.text .. spot .. "|r")
    if current and ba and current == ba then
      status2:SetText(HEX.green .. "You're in the boss's area.|r")
    elseif current and multi and current.floor ~= target.floor then
      status2:SetText(HEX.muted .. "You're on level " .. current.floor .. "; the boss is on level " .. target.floor .. ".|r")
    else
      status2:SetText(HEX.muted .. "You're in |r" .. where)
    end
    return
  end

  local chain = table.concat(routeAreas or {}, HEX.muted .. "  >  |r" .. HEX.text)
  if chain == "" then chain = "the next room" end
  status:SetText(HEX.muted .. "To|r " .. HEX.gold .. target.name .. "|r" .. HEX.muted .. ":  |r" .. HEX.text .. chain .. "|r")
  local idx
  for i, a in ipairs(routeAreas or {}) do if current and a == current.name then idx = i end end
  if current and not idx then
    status2:SetText(HEX.red .. "Off the route.|r " .. HEX.muted .. "Head back toward |r" .. HEX.gold
      .. (routeAreas[1] or "the entrance") .. "|r" .. HEX.muted .. ", or click the boss again to re-plan.|r")
  elseif idx and idx < #routeAreas then
    status2:SetText(HEX.green .. "On the route.|r " .. HEX.muted .. "Next: |r" .. HEX.gold .. routeAreas[idx + 1] .. "|r")
  elseif idx then
    status2:SetText(HEX.green .. "You're in the boss's area.|r")
  else
    status2:SetText(HEX.muted .. "Follow the dots. Areas light up as you enter them.|r")
  end
end

function O.Refresh()
  if not pane or not data then return end
  PaintGlows(); PaintPins(); PaintMarks(); PaintTabs(); PaintStatus()
end

function O.KeyByName(name)
  if not data then return end
  for _, b in ipairs(data.bosses) do
    if b.name == name or name:find(b.name, 1, true) or b.name:find(name, 1, true) then return b.name end
  end
end

local function ShowFloor(i)
  if not data or not data.floors[i] then return end
  viewFloor = i
  local f = data.floors[i]
  art.tex:SetTexture(f.art)
  art.tex:SetTexCoord(0, f.texRight, 0, f.texBottom)
  DrawDots()
  O.Refresh()
end

O.ShowFloor = function(i) ShowFloor(i) end

function O.Plan(boss)
  target = boss
  if boss and data.nodes and boss.node then
    route = FindRoute(boss.node)
    routeAreas = route and AreasOf(route) or nil
  else
    route, routeAreas = nil, nil
  end
  if boss and boss.floor ~= viewFloor then ShowFloor(boss.floor) else DrawDots(); O.Refresh() end
end

---------------------------------------------------------------------------
-- Build for a dungeon
---------------------------------------------------------------------------
local function PlaceAll()
  if not data then return end
  local w, h = art:GetSize()
  for a, g in pairs(glows) do
    local size = a.r * 2 * w
    g:ClearAllPoints(); g:SetSize(size, size)
    g:SetPoint("CENTER", art, "TOPLEFT", a.x * w, -a.y * h)
  end
  for _, p in ipairs(pins) do
    p:ClearAllPoints()
    p:SetPoint("CENTER", art, "TOPLEFT", p.boss.x * w, -p.boss.y * h)
  end
  for _, m in ipairs(marks) do
    m:ClearAllPoints()
    m:SetPoint("CENTER", art, "TOPLEFT", m.data.x * w, -m.data.y * h)
  end
  DrawDots()
end

local markPool = {}
local function MakeMark(md)
  local m = table.remove(markPool)
  if not m then
    m = CreateFrame("Button", nil, art)
    m:SetSize(18, 18)
    m:SetFrameLevel(art:GetFrameLevel() + 4)
    m.dot = m:CreateTexture(nil, "ARTWORK")
    m.dot:SetTexture(MEDIA .. "dot")
    m.dot:SetPoint("CENTER"); m.dot:SetSize(10, 10)
    m.ring = m:CreateTexture(nil, "OVERLAY")
    m.ring:SetTexture(MEDIA .. "ring")
    m.ring:SetAllPoints()
    m:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.data.label, 1, 1, 1)
      if self.data.to and data.floors[self.data.to] then
        GameTooltip:AddLine("Click: show " .. (data.floors[self.data.to].label or ("level " .. self.data.to)),
          C.muted[1], C.muted[2], C.muted[3])
      end
      GameTooltip:Show()
    end)
    m:SetScript("OnLeave", GameTooltip_Hide)
    m:SetScript("OnClick", function(self) if self.data.to then O.ShowFloor(self.data.to) end end)
  end
  m.data = md
  local c = md.color or C.gold
  m.dot:SetVertexColor(c[1], c[2], c[3], 1)
  m.ring:SetVertexColor(c[1], c[2], c[3], 1)
  return m
end

local glowPool = {}
local function MakeGlows()
  for _, g in pairs(glows) do g:Hide(); glowPool[#glowPool + 1] = g end
  wipe(glows)
  for _, a in ipairs(areas) do
    local g = table.remove(glowPool)
    if not g then
      g = art:CreateTexture(nil, "ARTWORK", nil, 2)
      g:SetTexture(MEDIA .. "glow")
      g:SetBlendMode("ADD")
    end
    g:Hide()
    glows[a] = g
  end
end

local pinPool = {}
local function MakePin()
  local p = table.remove(pinPool)
  if p then return p end
  p = CreateFrame("Button", nil, art)
  p:SetFrameLevel(art:GetFrameLevel() + 5)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetPoint("TOPLEFT", 3, -3); p.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  if p.icon.SetMask then pcall(p.icon.SetMask, p.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  p.ring = p:CreateTexture(nil, "OVERLAY")
  p.ring:SetAllPoints()
  p.ring:SetTexture(MEDIA .. "ring")
  p.x = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.x:SetPoint("CENTER", 0, 0)
  p.x:SetText(HEX.red .. "X|r")
  p:SetScript("OnClick", function(self, btn)
    if IsShiftKeyDown() then
      ns.SetDead(self.boss.name, not Dead(self.boss))
    elseif btn == "RightButton" or target == self.boss and not data.nodes then
      O.Plan(nil)
    else
      O.Plan(self.boss)
    end
  end)
  p:SetScript("OnEnter", function(self)
    local b = self.boss
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(b.name, C.gold[1], C.gold[2], C.gold[3])
    if b.rare then GameTooltip:AddLine("Rare, may not be up", C.muted[1], C.muted[2], C.muted[3]) end
    if b.quest then GameTooltip:AddLine("Quest target" .. (b.note and (": " .. b.note) or ""), C.muted[1], C.muted[2], C.muted[3]) end
    local ba = BossArea(b)
    if ba then GameTooltip:AddLine(ba.name, C.text[1], C.text[2], C.text[3]) end
    if Dead(b) then GameTooltip:AddLine("Dead", C.red[1], C.red[2], C.red[3]) end
    GameTooltip:AddLine(data.nodes and "Click: route here   Right-click: clear" or "Click: select   Right-click: clear",
      C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:AddLine("Shift-click: mark dead / alive", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", GameTooltip_Hide)
  return p
end

local function Clear()
  for _, p in ipairs(pins) do p:Hide(); pinPool[#pinPool + 1] = p end
  wipe(pins)
  for _, m in ipairs(marks) do m:Hide(); markPool[#markPool + 1] = m end
  wipe(marks)
  for _, d in ipairs(dots) do d:Hide() end
  target, route, routeAreas = nil, nil, nil
  current, lastArea = nil, nil
end

function O.SetDungeon(name)
  if not pane then return end
  if name == dungeonName then return end
  dungeonName = name
  Clear()
  -- the game may name a dungeon with or without "The"
  data = name and (ns.DUNGEONS[name] or ns.DUNGEONS["The " .. name]
    or ns.DUNGEONS[(name:gsub("^The ", ""))])
  -- the map images live in ForeverDungeonJournal's folder
  if data and not HasJournal() then
    data = nil -- nothing to draw; the rest of the overview treats this as "no dungeon"
    art:Hide(); empty:Show()
    status:SetText(""); status2:SetText("")
    for _, t in ipairs(tabs) do t:Hide() end
    empty:SetText(HEX.muted .. "The dungeon overview needs the " .. HEX.text .. "Forever Dungeon Journal|r"
      .. HEX.muted .. " addon.\nInstall it and enable it, then /reload.|r")
    return
  end
  art:SetShown(data ~= nil)
  empty:SetShown(data == nil)
  status:SetText(""); status2:SetText("")
  for _, t in ipairs(tabs) do t:Hide() end
  if not data then
    for _, g in pairs(glows) do g:Hide() end
    empty:SetText(HEX.muted .. (name and ("No overview for " .. HEX.text .. name .. "|r" .. HEX.muted .. " yet.|r")
      or "The overview appears inside a dungeon.") .. "|r")
    return
  end
  BuildAreas()
  MakeGlows()
  local journal = HasJournal()
  for i, b in ipairs(data.bosses) do
    local p = MakePin()
    p.boss = b
    p.icon:SetTexture((journal and b.portrait) and (FDJ_PORTRAITS .. b.portrait) or SKULL)
    pins[i] = p
  end
  for i, md in ipairs(data.markers or {}) do marks[i] = MakeMark(md) end
  O.lastKey = nil
  viewFloor = GameFloor() or 1
  ShowFloor(viewFloor)
  O.Layout()
  O.SetArea(GetSubZoneText())
end

-- The area the game reports. Unnamed tunnels keep the last named area.
function O.SetArea(sub)
  if not data then return end
  sub = Plain(sub)
  local zone = Plain(GetRealZoneText())
  if sub == "" or sub == zone then sub = nil end
  rawSub = sub
  local a = FindArea(sub)
  local gf = GameFloor()
  -- Only follow you to another level when where you are changed, so a
  -- level you picked by hand stays up.
  local key = (a and (a.name .. "@" .. a.floor) or "-") .. "/" .. tostring(gf)
  local moved = key ~= O.lastKey
  O.lastKey = key
  local changed = a ~= current
  current = a
  if a then lastArea = a.name end
  if moved then
    local want = (a and a.floor) or gf
    if want and want ~= viewFloor then ShowFloor(want) return end
  end
  if moved or changed then O.Refresh() end
end

-- Ctrl-click: put the area you're standing in where you clicked.
local function PlaceHere(x, y)
  if not rawSub then
    print(UI.HEX.gold .. "Top Ramen Map|r: the game doesn't name this spot, so there's nothing to place.")
    return
  end
  ns.Learn(dungeonName, { name = rawSub, floor = viewFloor, x = x, y = y, r = 0.07 })
  BuildAreas(); MakeGlows(); PlaceAll()
  O.SetArea(GetSubZoneText())
  print(UI.HEX.gold .. "Top Ramen Map|r: placed " .. rawSub .. string.format(" at %.3f, %.3f", x, y)
    .. (#data.floors > 1 and (" on level " .. viewFloor) or "") .. ".")
end

---------------------------------------------------------------------------
-- Pane
---------------------------------------------------------------------------
function O.Create(parent)
  pane = UI.Frame(parent, C.well, C.line, 1)

  art = CreateFrame("Frame", nil, pane)
  art.tex = art:CreateTexture(nil, "BACKGROUND")
  art.tex:SetAllPoints()
  art:EnableMouse(true)
  art:SetScript("OnMouseUp", function(self)
    if not IsControlKeyDown() or not data then return end
    local cx, cy = GetCursorPosition()
    local s = self:GetEffectiveScale()
    cx, cy = cx / s, cy / s
    local x = (cx - self:GetLeft()) / self:GetWidth()
    local y = (self:GetTop() - cy) / self:GetHeight()
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then PlaceHere(x, y) end
  end)

  for i = 1, 4 do
    local t = UI.Button(pane, 44, 20, tostring(i))
    t:SetPoint("TOPLEFT", pane, "TOPLEFT", 6 + (i - 1) * 48, -6)
    t:SetFrameLevel(pane:GetFrameLevel() + 20)
    t:SetScript("OnClick", function() ShowFloor(i) end)
    t:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Level " .. i)
      GameTooltip:AddLine("• you're here   ★ selected boss", C.muted[1], C.muted[2], C.muted[3])
      GameTooltip:Show()
    end)
    t:HookScript("OnLeave", GameTooltip_Hide)
    t:Hide()
    tabs[i] = t
  end

  empty = UI.Text(pane, "GameFontHighlight", C.muted)
  empty:SetPoint("CENTER")
  empty:SetJustifyH("CENTER")

  status = UI.Text(pane, "GameFontHighlight", C.text)
  status:SetPoint("BOTTOMLEFT", 10, 26)
  status:SetPoint("BOTTOMRIGHT", -10, 26)
  status:SetWordWrap(false)
  status2 = UI.Text(pane, "GameFontHighlightSmall", C.muted)
  status2:SetPoint("BOTTOMLEFT", 10, 9)
  status2:SetPoint("BOTTOMRIGHT", -24, 9)
  status2:SetWordWrap(false)

  pane:SetScript("OnSizeChanged", function() O.Layout() end)
  O.SetDungeon(nil)
  return pane
end

function O.Layout()
  if not pane or not data then return end
  local aspect = 1002 / 668
  local top = (#data.floors > 1) and 30 or 6
  local w, h = pane:GetWidth() - 12, pane:GetHeight() - top - 6 - 46
  if w < 20 or h < 20 then return end
  local aw = math.min(w, h * aspect)
  local ah = aw / aspect
  art:ClearAllPoints()
  art:SetSize(aw, ah)
  art:SetPoint("TOP", pane, "TOP", 0, -top - (h - ah) / 2)
  PlaceAll()
end

-- Areas you've placed, as data lines to send to the addon's author.
function O.DumpLearned()
  local any
  for dname, list in pairs(ns.AllLearned and ns.AllLearned() or {}) do
    for _, a in pairs(list) do
      any = true
      print(string.format('%s: { name = "%s", floor = %d, x = %.3f, y = %.3f, r = %.3f }', dname, a.name, a.floor, a.x, a.y, a.r))
    end
  end
  if not any then print(UI.HEX.gold .. "Top Ramen Map|r: you haven't placed any areas yet.") end
end
