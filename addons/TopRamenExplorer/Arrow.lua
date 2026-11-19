-- Top Ramen Explorer: the built-in guide arrow (used instead of TomTom's when you pick it:
-- /tre arrow, or the Arrow button in the window).
-- Points at the spot you're being guided to and turns as you turn. Shows the area and the
-- distance. Drag to move it; right-click to stop guiding.
local _, ns = ...

local f
local ARROW = "Interface\\Minimap\\MinimapArrow" -- points straight up when not rotated

local function build()
  f = CreateFrame("Button", "TopRamenExplorerArrow", UIParent)
  f:SetSize(64, 64)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.arrowPos = { p, rp, x, y }
  end)
  f:SetScript("OnClick", function() ns.StopGuide() end)
  if ns.db.arrowPos then
    f:ClearAllPoints()
    f:SetPoint(ns.db.arrowPos[1], UIParent, ns.db.arrowPos[2], ns.db.arrowPos[3], ns.db.arrowPos[4])
  end

  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetTexture(ARROW)
  f.tex:SetAllPoints()

  f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.name:SetPoint("TOP", f, "BOTTOM", 0, -2)
  f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.dist:SetPoint("TOP", f.name, "BOTTOM", 0, -2)

  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Top Ramen Explorer", 1, 0.82, 0)
    GameTooltip:AddLine("Drag to move. Right-click to stop guiding.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local t = 0
  f:SetScript("OnUpdate", function(self, dt)
    t = t + dt
    if t < 0.03 then return end
    t = 0
    ns.UpdateArrow()
  end)
  f:Hide()
end

-- world position of a map point: x grows north, y grows west
local function worldPos(mapID, x, y)
  if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if ok and pos then return pos.x, pos.y end
end

function ns.UpdateArrow()
  local g = ns.guide
  if not (f and g and ns.UsingOwnArrow() and not ns.db.arrowHidden) then
    if f then f:Hide() end
    return
  end
  local px, py = ns.PlayerXY(g.mapID)
  if not px then
    f.tex:SetRotation(0)
    f.tex:SetVertexColor(0.5, 0.5, 0.5)
    f.dist:SetText("not on this map")
    return
  end
  local north, west, yards
  local ax, ay = worldPos(g.mapID, px, py)
  local bx, by = worldPos(g.mapID, g.x, g.y)
  if ax and bx then
    north, west = bx - ax, by - ay
  else
    -- fall back to the map's size in yards
    local w, h = C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(g.mapID)
    if not w or w == 0 then w, h = 1000, 667 end
    north, west = -(g.y - py) * h, -(g.x - px) * w
  end
  yards = math.sqrt(north * north + west * west)

  -- bearing to the spot, counter-clockwise from north (the same way the game measures facing)
  local bearing = (math.atan2 or math.atan)(west, north)
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing then
    f.tex:SetRotation(bearing - facing)
  else
    f.tex:SetRotation(bearing) -- facing unknown here: points as on the map (north up)
  end
  -- green when close, yellow in between, white far away
  if yards < 40 then f.tex:SetVertexColor(0.3, 1, 0.3)
  elseif yards < 200 then f.tex:SetVertexColor(1, 0.85, 0.3)
  else f.tex:SetVertexColor(1, 1, 1) end
  f.dist:SetText(string.format("%d yd%s", yards, facing and "" or "  (map north is up)"))
end

-- show or hide the arrow to match the guide
function ns.RefreshArrow()
  if not ns.db then return end
  if ns.guide and ns.UsingOwnArrow() and not ns.db.arrowHidden then
    if not f then build() end
    local g = ns.guide
    f.name:SetText(g.name or ("Undiscovered: " .. ns.ZoneName(g.mapID)))
    f:Show()
    ns.UpdateArrow()
  elseif f then
    f:Hide()
  end
end
