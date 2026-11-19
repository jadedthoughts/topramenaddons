-- Top Ramen Gear: shared look for the window (dark panels, gold trim, pill buttons,
-- quality-bordered item icons, gain bars). Matches the "window redesign" mockup.
local _, ns = ...

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.MEDIA = "Interface\\AddOns\\TopRamenGear\\Media\\"
UI.STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t"
-- broken armor: the game's repair (anvil) icon
UI.BROKEN = "|TInterface\\Minimap\\Tracking\\Repair:14:14|t"

local function hex(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
UI.C = {
  bg = hex("14110d"), panel = hex("1d1812"), row = hex("191510"), well = hex("0e0c09"),
  line = hex("3a3122"), trim = hex("6b5a2e"), active = hex("3a2b14"), button = hex("2a2116"),
  gold = hex("ffd100"), text = hex("ece6d8"), muted = hex("b8ae9c"), green = hex("4ade80"), red = hex("f87171"),
  druid = hex("ff7c0a"), track = hex("2a241b"),
}
local C = UI.C
UI.HEX = { gold = "|cffffd100", text = "|cffece6d8", muted = "|cffb8ae9c", green = "|cff4ade80", red = "|cfff87171", dim = "|cff8f877a" }

-- a flat panel: background colour and a thin border
function UI.Skin(f, bg, border, edge, alpha)
  if not f.SetBackdrop then
    if BackdropTemplateMixin then Mixin(f, BackdropTemplateMixin) else return end
  end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
  bg = bg or C.bg
  f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
  if border then f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
  else f:SetBackdropBorderColor(0, 0, 0, 0) end
end

function UI.Frame(parent, bg, border, edge, alpha)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  UI.Skin(f, bg, border, edge, alpha)
  return f
end

function UI.Text(parent, font, color, size)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  if size and t.GetFont then
    local file, _, flags = t:GetFont()
    if file then t:SetFont(file, size, flags) end
  end
  if color then t:SetTextColor(color[1], color[2], color[3]) end
  t:SetJustifyH("LEFT")
  return t
end

-- a pill button (tabs, spec switcher, tools). sub = optional small line above the label
function UI.Pill(parent, w, h, text, sub, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  UI.Skin(b, C.bg, nil, 1, 0)
  b.label = UI.Text(b, "GameFontNormal", C.muted)
  b.sub = false
  if sub then
    b.sub = UI.Text(b, "GameFontHighlightSmall", C.muted, 9)
    b.sub:SetPoint("TOPLEFT", 12, -7)
    b.sub:SetText(sub:upper())
    b.label:SetPoint("TOPLEFT", b.sub, "BOTTOMLEFT", 0, -2)
  else
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
  end
  b.label:SetText(text)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) if not self.active then self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1) end end)
  b:SetScript("OnLeave", function(self) if not self.active then self:SetBackdropColor(0, 0, 0, 0) end end)
  function b:SetActive(on, accent)
    self.active = on
    accent = accent or C.druid
    if on then
      self:SetBackdropColor(C.active[1], C.active[2], C.active[3], 1)
      self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
      self.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    else
      self:SetBackdropColor(0, 0, 0, 0)
      self:SetBackdropBorderColor(0, 0, 0, 0)
      self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end
    if self.sub then local c = on and C.gold or C.muted; self.sub:SetTextColor(c[1], c[2], c[3], 0.75) end
  end
  b:SetActive(false)
  return b
end

-- an always-visible flat button (Tools)
function UI.Button(parent, w, h, text, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  UI.Skin(b, C.button, C.trim, 1)
  b.label = UI.Text(b, "GameFontHighlight", C.text)
  b.label:SetPoint("CENTER"); b.label:SetJustifyH("CENTER")
  b.label:SetText(text)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
    if tip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(text, 1, 0.82, 0)
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.trim[1], C.trim[2], C.trim[3], 1); GameTooltip:Hide() end)
  return b
end

-- the four-spec switcher (Feral Bear / Feral Cat / Caster Balance / Healer Restoration)
function UI.SpecSwitcher(parent, onPick)
  local f = UI.Frame(parent, C.well, C.line)
  f.buttons = {}
  local x = 4
  for _, sp in ipairs(ns.ClassSpecs()) do
    local w = sp.key == "resto" and 106 or 84
    local b = UI.Pill(f, w, 40, sp.name, sp.group, function() onPick(sp.key) end)
    b:SetPoint("TOPLEFT", x, -4)
    x = x + w + 4
    f.buttons[sp.key] = b
  end
  f:SetSize(x, 48)
  function f:Update(mode) for k, b in pairs(self.buttons) do b:SetActive(k == mode) end end
  return f
end

-- item quality colour
function UI.QualityColor(q)
  if q and C_Item and C_Item.GetItemQualityColor then
    local r, g, b = C_Item.GetItemQualityColor(q)
    if r then return { r, g, b } end
  end
  if q and GetItemQualityColor then
    local r, g, b = GetItemQualityColor(q)
    if r then return { r, g, b } end
  end
  if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
    local c = ITEM_QUALITY_COLORS[q]; return { c.r, c.g, c.b }
  end
  return { 1, 1, 1 }
end

-- an item icon with a quality-coloured border and an optional gold glow
function UI.Icon(parent, size)
  local f = UI.Frame(parent, C.track, C.line, 2)
  f:SetSize(size, size)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", 2, -2); f.tex:SetPoint("BOTTOMRIGHT", -2, 2)
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.glow = f:CreateTexture(nil, "OVERLAY")
  f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  f.glow:SetBlendMode("ADD")
  f.glow:SetVertexColor(1, 0.82, 0, 0.9)
  f.glow:SetPoint("CENTER")
  f.glow:SetSize(size * 1.9, size * 1.9)
  f.glow:Hide()
  -- border: "quality", "red", or nil (quality)
  function f:SetItem(icon, quality, border, glow)
    self.tex:SetTexture(icon)
    local c = border == "red" and C.red or UI.QualityColor(quality)
    self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    self.glow:SetShown(glow and true or false)
    self:Show()
  end
  return f
end

-- a green gain bar: SetValue(fraction 0..1)
function UI.Bar(parent, w)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 6)
  f.track = f:CreateTexture(nil, "BACKGROUND")
  f.track:SetAllPoints(); f.track:SetColorTexture(C.track[1], C.track[2], C.track[3], 1)
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("TOPLEFT"); f.fill:SetPoint("BOTTOMLEFT")
  f.fill:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)
  if f.fill.SetGradient and CreateColor then
    f.fill:SetColorTexture(1, 1, 1, 1)
    local ok = pcall(f.fill.SetGradient, f.fill, "HORIZONTAL", CreateColor(0.09, 0.64, 0.29, 1), CreateColor(0.29, 0.87, 0.5, 1))
    if not ok then f.fill:SetColorTexture(C.green[1], C.green[2], C.green[3], 1) end
  end
  function f:SetValue(v)
    v = math.max(0, math.min(1, v or 0))
    self.fill:SetWidth(math.max(1, self:GetWidth() * v))
    self.fill:SetShown(v > 0)
  end
  return f
end

-- a small heading in the gold serif-ish style
function UI.Heading(parent, text)
  local h = UI.Text(parent, "GameFontNormal", C.gold)
  h:SetText(text)
  return h
end

-- "Shaldyn · Level 32 Druid"
function UI.WhoAmI()
  local name = UnitName and UnitName("player") or "?"
  local className = UnitClass and UnitClass("player") or ""
  return (name or "?") .. " · Level " .. tostring(ns.Level() or "?") .. " " .. (className or "")
end
