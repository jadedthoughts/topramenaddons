-- Top Ramen Explorer: undiscovered spots drawn on the world map.
-- Blue = confirmed trigger spot for an area you still need. Orange = unverified (classic-era
-- Wowhead comment). Purple = Cataclysm-era Wowhead comment (may be off on Forever).
-- Gold = enclosed undiscovered patch from the map scan.
-- Grey = patch at the map edge (may be unreachable). Green = the one you're being guided to.
-- Click a spot to be guided to it. Right-click to ignore it.
local _, ns = ...

local pins, used = {}, 0

local function canvas()
  return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function getPin(parent)
  used = used + 1
  local p = pins[used]
  if not p then
    p = CreateFrame("Button", nil, parent)
    p:SetSize(20, 20)
    p:SetFrameStrata("HIGH")
    -- the soup bowl, with a thin colored border that says what kind of spot it is
    p.border = p:CreateTexture(nil, "BACKGROUND")
    p.border:SetAllPoints()
    p.border:SetColorTexture(1, 1, 1, 1)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 2, -2)
    p.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    p.icon:SetTexture("Interface\\Icons\\INV_Misc_Food_63")
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.spot.name or "Undiscovered spot", 1, 0.82, 0)
      GameTooltip:AddLine(string.format("%.1f, %.1f", self.spot.x * 100, self.spot.y * 100), 1, 1, 1)
      if self.spot.known and self.spot.note then
        if self.spot.kind == "cataclysm" then GameTooltip:AddLine(self.spot.note, 0.73, 0.5, 1, true)
        elseif self.spot.unverified then GameTooltip:AddLine(self.spot.note, 1, 0.6, 0.2, true)
        else GameTooltip:AddLine(self.spot.note, 0.3, 0.8, 1, true) end
      end
      if self.spot.edge then GameTooltip:AddLine("At the map edge - may be unreachable.", 0.6, 0.6, 0.6, true) end
      GameTooltip:AddLine("Click: guide me here.  Right-click: ignore.", 0.25, 0.8, 0.25, true)
      GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
        ns.db.ignore[ns.SpotKey(self.mapID, self.spot.x, self.spot.y)] = true
        ns.spots[self.mapID] = nil
        if ns.guide and ns.guide.mapID == self.mapID and ns.guide.x == self.spot.x and ns.guide.y == self.spot.y then
          ns.StopGuide(true)
        end
        ns.Refresh()
      else
        ns.GuideTo(self.mapID, self.spot)
      end
    end)
    pins[used] = p
  end
  return p
end

function ns.UpdatePins()
  local child = canvas()
  for i = 1, #pins do pins[i]:Hide() end
  used = 0
  if not (child and ns.db and ns.db.pins and WorldMapFrame:IsShown()) then return end
  local mapID = WorldMapFrame:GetMapID()
  local info = mapID and C_Map.GetMapInfo(mapID)
  if not info or info.mapType ~= Enum.UIMapType.Zone then return end
  -- only zones you marked (Mark zone / whole zone / all zones), or the one you're being guided in
  local guided = ns.guide and ns.guide.mapID == mapID
  if not (ns.shownZones[mapID] or guided) then return end
  local a = ns.AchFor(mapID)
  if a and a.done then return end
  local list = ns.SortedSpots(mapID)
  local w, h = child:GetWidth(), child:GetHeight()
  local scale = child:GetScale()
  for _, s in ipairs(list) do
    local p = getPin(child)
    p.spot, p.mapID = s, mapID
    p:SetScale(1 / math.max(scale, 0.01))
    p:ClearAllPoints()
    p:SetPoint("CENTER", child, "TOPLEFT", s.x * w * scale, -s.y * h * scale)
    local guided = ns.guide and ns.guide.mapID == mapID and ns.guide.x == s.x and ns.guide.y == s.y
    local b = p.border
    if guided then b:SetColorTexture(0.3, 1, 0.3, 1)
    elseif s.kind == "cataclysm" then b:SetColorTexture(0.73, 0.5, 1, 1)
    elseif s.unverified then b:SetColorTexture(1, 0.6, 0.2, 1)
    elseif s.known then b:SetColorTexture(0.3, 0.8, 1, 1)
    elseif s.edge then b:SetColorTexture(0.6, 0.6, 0.6, 1)
    else b:SetColorTexture(1, 0.85, 0.3, 1) end
    p:Show()
  end
end

function ns.InitPins()
  local function hook()
    if not WorldMapFrame or WorldMapFrame.TopRamenExplorerHooked then return end
    WorldMapFrame.TopRamenExplorerHooked = true
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function() ns.UpdatePins() end)
    WorldMapFrame:HookScript("OnShow", function() ns.UpdatePins() end)
    WorldMapFrame:HookScript("OnHide", function() ns.UpdatePins() end)
    -- keep pins the same size while zooming
    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.HookScript then
      sc:HookScript("OnMouseWheel", function() C_Timer.After(0.05, ns.UpdatePins) end)
    end
  end
  if WorldMapFrame then hook()
  elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", hook)
  end
end
