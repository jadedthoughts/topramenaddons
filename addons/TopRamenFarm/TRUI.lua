-- Top Ramen shared look (same style as Top Ramen Gear): dark panels, gold trim,
-- the TR bowl header, pill tabs, flat buttons and progress bars.
local addonName, ns = ...

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

local function hex(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
UI.C = {
  bg = hex("14110d"), panel = hex("1d1812"), row = hex("191510"), well = hex("0e0c09"),
  line = hex("3a3122"), trim = hex("6b5a2e"), active = hex("3a2b14"), button = hex("2a2116"),
  gold = hex("ffd100"), text = hex("ece6d8"), muted = hex("b8ae9c"), green = hex("4ade80"), red = hex("f87171"),
  accent = hex("ff7c0a"), track = hex("2a241b"),
}
local C = UI.C
UI.HEX = { gold = "|cffffd100", text = "|cffece6d8", muted = "|cffb8ae9c", green = "|cff4ade80", red = "|cfff87171", dim = "|cff8f877a" }
UI.HEAD_H = 58

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

function UI.Line(parent, anchor)
  local l = parent:CreateTexture(nil, "ARTWORK")
  l:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  l:SetHeight(1)
  return l
end

-- a flat button that behaves like UIPanelButtonTemplate (SetText, GetText, Enable/Disable,
-- LockHighlight / UnlockHighlight show it as the selected one)
function UI.Button(parent, w, h, text, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h or 24)
  UI.Skin(b, C.button, C.trim, 1)
  b.label = UI.Text(b, (h or 24) < 20 and "GameFontHighlightSmall" or "GameFontHighlight", C.text)
  b.label:SetPoint("CENTER"); b.label:SetJustifyH("CENTER")
  b.label:SetText(text or "")
  if onClick then b:SetScript("OnClick", onClick) end
  local function paint(self)
    if self.selected then
      self:SetBackdropColor(C.active[1], C.active[2], C.active[3], 1)
      self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
      self.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    elseif self.hover and self:IsEnabled() then
      self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
      self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
      self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    else
      self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
      self:SetBackdropBorderColor(C.trim[1], C.trim[2], C.trim[3], 1)
      local c = self:IsEnabled() and C.text or C.muted
      self.label:SetTextColor(c[1], c[2], c[3], self:IsEnabled() and 1 or 0.5)
    end
  end
  b.SetText = function(self, t) self.label:SetText(t) end
  b.GetText = function(self) return self.label:GetText() end
  b.LockHighlight = function(self) self.selected = true; paint(self) end
  b.UnlockHighlight = function(self) self.selected = false; paint(self) end
  b:HookScript("OnEnter", function(self) self.hover = true; paint(self) end)
  b:HookScript("OnLeave", function(self) self.hover = false; paint(self) end)
  b:HookScript("OnEnable", paint)
  b:HookScript("OnDisable", paint)
  b.Repaint = paint
  paint(b)
  return b
end

-- a green progress bar: SetValue(0..1)
function UI.Bar(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w or 60, h or 4)
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
  function f:SetValue(v, color)
    v = math.max(0, math.min(1, v or 0))
    self.fill:SetWidth(math.max(1, (self:GetWidth() or 0) * v))
    self.fill:SetShown(v > 0)
    if color then self.fill:SetColorTexture(color[1], color[2], color[3], 1) end
  end
  return f
end

-- the window frame: dark fill, gold trim
function UI.Window(name, alpha)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  UI.Skin(f, C.bg, C.trim, 2, alpha or 0.97)
  -- comes to the front when opened or clicked (not the Map window: it carries the minimap and sets its own layer)
  if not (name and name:find("Map")) then UI.RegisterWindow(f) end
  return f
end

-- the header: TR bowl, "Top Ramen", a subtitle, close button. Returns the header frame;
-- put header buttons to the left of header.close.
function UI.Header(f, subtitle)
  local head = UI.Frame(f, C.panel)
  head:SetPoint("TOPLEFT", 2, -2); head:SetPoint("TOPRIGHT", -2, -2); head:SetHeight(UI.HEAD_H)
  local line = UI.Line(head)
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  local logo = head:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(UI.MEDIA .. "trBowl")
  logo:SetSize(84, 42)
  logo:SetPoint("LEFT", 8, 0)
  head.title = UI.Text(head, "GameFontNormalLarge", C.gold)
  head.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 6, -3)
  head.title:SetText("Top Ramen")
  head.sub = UI.Text(head, "GameFontHighlightSmall", C.muted)
  head.sub:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -3)
  head.sub:SetText(subtitle or "")
  head.close = CreateFrame("Button", nil, head, "UIPanelCloseButton")
  head.close:SetPoint("RIGHT", -8, 0)
  head.close:SetScript("OnClick", function() f:Hide() end)
  return head
end

-- a resize grip in the bottom-right corner
function UI.Grip(f, onDone)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -6, 6)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); if onDone then onDone() end end)
  return grip
end

-- a flat panel drawn as textures on the parent (so it always sits under the parent's controls).
-- Position the returned texture with SetPoint / SetHeight; its 1px border follows it.
function UI.Panel(parent, bg, border)
  bg, border = bg or C.row, border or C.line
  local fill = parent:CreateTexture(nil, "BORDER", nil, -2)
  fill:SetColorTexture(bg[1], bg[2], bg[3], 1)
  local function edge(p1, p2, horiz)
    local e = parent:CreateTexture(nil, "BORDER", nil, -1)
    e:SetColorTexture(border[1], border[2], border[3], 1)
    e:SetPoint(p1, fill, p1); e:SetPoint(p2, fill, p2)
    if horiz then e:SetHeight(1) else e:SetWidth(1) end
  end
  edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
  return fill
end

-- Top Ramen windows share one list (every Top Ramen addon adds its windows): the one you opened or clicked
-- last is drawn on the "HIGH" layer and the others drop to "MEDIUM", so two windows never mix their parts.
local stack = _G.TopRamenWindows or {}
_G.TopRamenWindows = stack
function UI.BringToFront(f)
  for _, w in ipairs(stack) do
    if w ~= f and w.SetFrameStrata then w:SetFrameStrata("MEDIUM") end
  end
  f:SetFrameStrata("HIGH")
  if f.Raise then f:Raise() end
end
function UI.RegisterWindow(f)
  for _, w in ipairs(stack) do if w == f then return end end
  stack[#stack + 1] = f
  if f.SetToplevel then f:SetToplevel(true) end
  f:HookScript("OnShow", function(self) UI.BringToFront(self) end)
  f:HookScript("OnMouseDown", function(self) UI.BringToFront(self) end)
end
