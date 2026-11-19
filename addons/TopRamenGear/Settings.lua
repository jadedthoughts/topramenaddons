-- Top Ramen Gear: the Settings tab of the /trg window
-- Every slash option as a checkbox, slider, number box or button.
local _, ns = ...

local GOLD, GREY = "|cffe0b04a", "|cff9d9d9d"
local controls = {}

local function note(parent, text, x, y, width)
  local n = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  n:SetPoint("TOPLEFT", x, y)
  if width then n:SetWidth(width) end
  n:SetJustifyH("LEFT")
  n:SetText(GREY .. text .. "|r")
  return n
end

local function check(parent, key, text, x, y, onChange)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetPoint("TOPLEFT", x, y)
  c:SetSize(24, 24)
  local label = c.text or c.Text or c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:ClearAllPoints()
  label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  label:SetFontObject("GameFontHighlight")
  label:SetText(text)
  c.__label = label
  c:SetScript("OnClick", function(self)
    ns.db[key] = self:GetChecked() and true or false
    if onChange then onChange() end
  end)
  controls[#controls + 1] = function() c:SetChecked(ns.db[key] and true or false) end
  return c
end

local function focusSlider(parent, x, y)
  local ok, s = pcall(CreateFrame, "Slider", "TopRamenGearFocusSlider", parent, "OptionsSliderTemplate")
  if not ok or not s then
    s = CreateFrame("Slider", "TopRamenGearFocusSlider", parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if s.SetBackdrop then
      s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
                      tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    end
  end
  s:SetPoint("TOPLEFT", x, y)
  s:SetSize(300, 16)
  s:SetMinMaxValues(-100, 100)
  s:SetValueStep(10)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local low = _G["TopRamenGearFocusSliderLow"] or s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local high = _G["TopRamenGearFocusSliderHigh"] or s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local val = _G["TopRamenGearFocusSliderText"] or s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  low:ClearAllPoints(); low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2); low:SetText("Survival")
  high:ClearAllPoints(); high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2); high:SetText("Threat")
  val:ClearAllPoints(); val:SetPoint("BOTTOM", s, "TOP", 0, 3)
  local function label(v)
    if v == 0 then return "Balanced" end
    return (v < 0 and "Survival " or "Threat ") .. math.abs(v)
  end
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / 10 + 0.5) * 10
    val:SetText(label(v))
    if ns.db.bearFocus ~= v then ns.db.bearFocus = v; ns.ClearScores() end
  end)
  controls[#controls + 1] = function() s:SetValue(ns.db.bearFocus or 0); val:SetText(label(ns.db.bearFocus or 0)) end
  return s
end

function ns.ClearScores()
  if ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.RefreshSettings()
  for _, f in ipairs(controls) do pcall(f) end
end

-- a numbered setting on its own line, box at the right of the card
local function capRow(parent, key, text, y, onChange)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 16, y - 4)
  label:SetText(text)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e.__label = label
  e:SetSize(52, 20)
  e:SetPoint("TOPRIGHT", -18, y - 2)
  e:SetAutoFocus(false)
  e:SetJustifyH("CENTER")
  local function save(self)
    local n = tonumber(self:GetText())
    if n then ns.db[key] = math.max(0, n); if onChange then onChange() end end
    self:SetText(tostring(ns.db[key] or 0))
    self:ClearFocus()
  end
  e:SetScript("OnEnterPressed", save)
  e:SetScript("OnEditFocusLost", save)
  e:SetScript("OnEscapePressed", function(self) self:SetText(tostring(ns.db[key] or 0)); self:ClearFocus() end)
  controls[#controls + 1] = function() e:SetText(tostring(ns.db[key] or 0)) end
  return e
end

local cards, slider, content = {}, nil, nil
local function card(parent, title, height)
  local UI = ns.UI
  local c = UI.Frame(parent, UI.C.row, UI.C.line)
  c:SetHeight(height)
  local h = UI.Heading(c, title)
  h:SetPoint("TOPLEFT", 14, -12)
  cards[#cards + 1] = c
  return c
end

-- cards follow the window width: two side by side, then full-width ones
function ns.SettingsLayout()
  if not content or #cards == 0 then return end
  local sf = content:GetParent()
  local w = sf and sf:GetWidth() or 0
  if w < 100 then return end
  content:SetWidth(w)
  local half = math.floor((w - 12) / 2)
  local c1, c2, c3, c4 = cards[1], cards[2], cards[3], cards[4]
  c1:ClearAllPoints(); c1:SetPoint("TOPLEFT", 0, 0); c1:SetWidth(half)
  c2:ClearAllPoints(); c2:SetPoint("TOPLEFT", half + 12, 0); c2:SetWidth(half)
  c3:ClearAllPoints(); c3:SetPoint("TOPLEFT", 0, -(c1:GetHeight() + 12)); c3:SetWidth(w)
  c4:ClearAllPoints(); c4:SetPoint("TOPLEFT", c3, "BOTTOMLEFT", 0, -12); c4:SetWidth(w)
  if slider then slider:SetWidth(half - 48) end
end

function ns.BuildSettings(p)
  local UI = ns.UI
  local changed = function() ns.ClearScores() end
  local sf
  sf, content = ns.MakeScroll(p, "TopRamenGearSettingsScroll", -(58 + 14))
  content:SetHeight(300 + 12 + 124 + 12 + 108)

  -- Specs in tooltips
  local c1 = card(content, "Specs in tooltips", 300)
  local _, classTag = UnitClass("player")
  local cls = UI.Text(c1, "GameFontHighlightSmall", UI.C.muted)
  cls:SetPoint("TOPLEFT", 16, -34)
  local className = UnitClass("player")
  cls:SetText("Detected class: |cffff7c0a" .. tostring(className or "?") .. "|r")
  local y = -54
  check(c1, "tooltip", "Show Top Ramen lines on item tooltips", 14, y, changed); y = y - 30
  for _, sp in ipairs(ns.ClassSpecs()) do
    check(c1, sp.show, sp.group == "Feral" and ("Feral: " .. sp.name) or sp.name, 30, y, changed); y = y - 26
    if sp.key == "bear" then check(c1, "showBear3", "Bear, Swipe on 3 targets", 52, y, changed); y = y - 26 end
  end
  local div = c1:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], 1); div:SetHeight(1)
  div:SetPoint("TOPLEFT", 14, y - 4); div:SetPoint("TOPRIGHT", -14, y - 4)
  check(c1, "useTalents", "Include talents in scores", 14, y - 12, changed)

  -- Bear focus and caps
  local c2 = card(content, "Bear focus", 300)
  note(c2, "Survival (Stamina, Armor, Defense, Dodge) or threat (damage, Strength, hit).", 16, -32, 300)
  slider = focusSlider(c2, 24, -86)
  local capsHead = UI.Heading(c2, "Caps")
  capsHead:SetPoint("TOPLEFT", 14, -122)
  capRow(c2, "capHit", "Hit cap %", -146, changed)
  capRow(c2, "capExp", "Expertise cap %", -176, changed)
  capRow(c2, "capDef", "Bear Defense cap", -206, changed)
  capRow(c2, "capSpellHit", "Spell hit cap %", -236, changed)
  capRow(c2, "talHit", "Extra hit % (not talents)", -266, changed)

  -- Dungeons tab defaults
  local c3 = card(content, "Dungeons tab", 124)
  local within = check(c3, "dgWithinDefault", "Start with \"Usable within\" turned on, for", 14, -36)
  local lv = capRow(c3, "dgWithinLevels", "levels", -36)
  -- the number box follows the checkbox text, with "levels" after it
  lv:ClearAllPoints(); lv:SetPoint("LEFT", within.__label, "RIGHT", 12, 0)
  lv.__label:ClearAllPoints(); lv.__label:SetPoint("LEFT", lv, "RIGHT", 6, 0)
  check(c3, "dgShowAllDefault", "Start with \"Show non-upgrades\" turned on", 14, -64)
  check(c3, "dgMineDefault", "Start with \"Only what I can get\" turned on (hides other faction / class rewards)", 14, -92)

  -- Tools
  local c4 = card(content, "Tools", 108)
  local x = 14
  for _, t in ipairs({
    { "Export gear", 112, function() ns.RunExport() end, "Copies your character, gear and bags for the Top Ramen website. Same as /trg export." },
    { "Export dungeon loot", 160, function() ns.RunLoot() end, "Copies every dungeon's Druid loot, with exact stats, from the DungeonJournal addon. Same as /trg loot." },
    { "My talents", 100, function() ns.PrintTalents(true) end, "Lists every talent you've learned, with your rank in each. Same as /trg talents all." },
    { "Gear talents", 110, function() ns.PrintTalents() end, "Lists only the talents that change how gear is scored, and by how much. Same as /trg talents." },
    { "Reset settings", 120, function()
        local keepTab = ns.db.windowTab
        for k in pairs(ns.db) do ns.db[k] = nil end
        ns.InitDB()
        ns.db.windowTab = keepTab
        ns.RefreshSettings()
        print(GOLD .. "Top Ramen:|r settings reset to defaults.")
      end, "Puts every setting and stat weight back to the defaults." },
  }) do
    local b = UI.Button(c4, t[2], 30, t[1], t[3], t[4])
    b:SetPoint("TOPLEFT", x, -38)
    x = x + t[2] + 8
  end
  note(c4, "Tip: /trg help lists the slash commands. Everything here is saved between sessions.", 16, -80, 600)

  p:SetScript("OnShow", function() ns.SettingsLayout(); ns.RefreshSettings() end)
end
