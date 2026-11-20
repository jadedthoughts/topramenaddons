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
  content:SetHeight(330 + 12 + 124 + 12 + 150)

  -- Specs in tooltips
  local c1 = card(content, "Specs in tooltips", 330)
  local _, classTag = UnitClass("player")
  local cls = UI.Text(c1, "GameFontHighlightSmall", UI.C.muted)
  cls:SetPoint("TOPLEFT", 16, -34)
  local className = UnitClass("player")
  cls:SetText("Detected class: |cffff7c0a" .. tostring(className or "?") .. "|r" ..
    (ns.Previewing() and ("  ·  previewing " .. ns.PlayerClass():sub(1, 1) .. ns.PlayerClass():sub(2):lower()) or ""))
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

  -- preview another class on this character (talents are left out while previewing)
  local pv = UI.Text(c1, "GameFontHighlight", UI.C.text)
  pv:SetPoint("TOPLEFT", 16, y - 48)
  pv:SetText("Preview as")
  local function previewName()
    local p = ns.db.previewClass
    if not p or not ns.SPECS[p] then return "My class" end
    return p:sub(1, 1) .. p:sub(2):lower()
  end
  -- the classes to pick from: "My class", then every other class Top Ramen scores, A to Z
  local function choices()
    local list = {}
    for k in pairs(ns.SPECS) do if k ~= ns.RealClass() then list[#list + 1] = k end end
    table.sort(list)
    table.insert(list, 1, false) -- "My class" first
    return list
  end
  local function choiceName(k)
    if not k then
      local real = ns.RealClass() or ""
      return "My class (" .. real:sub(1, 1) .. real:sub(2):lower() .. ")"
    end
    return k:sub(1, 1) .. k:sub(2):lower()
  end
  local setLabel
  local function pick(k)
    ns.db.previewClass = k or nil
    if setLabel then setLabel(previewName()) end
    ns.ClearCache(); ns.ClearScores()
    print("|cffffd100Top Ramen:|r preview set to " .. previewName() .. ". Type /reload (or click Reload) to see it in the window.")
  end
  local anchor
  -- a dropdown list of classes (the game's dropdown menu; a cycling button if it isn't available)
  if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo then
    local ok, dd = pcall(CreateFrame, "Frame", "TopRamenGearPreviewDropDown", c1, "UIDropDownMenuTemplate")
    if ok and dd then
      dd:SetPoint("LEFT", pv, "RIGHT", -6, -2)
      UIDropDownMenu_SetWidth(dd, 110)
      UIDropDownMenu_Initialize(dd, function(_, level)
        for _, k in ipairs(choices()) do
          local info = UIDropDownMenu_CreateInfo()
          info.text = choiceName(k)
          info.checked = ((ns.db.previewClass or false) == k)
          info.func = function() pick(k); CloseDropDownMenus() end
          UIDropDownMenu_AddButton(info, level)
        end
      end)
      setLabel = function(t) UIDropDownMenu_SetText(dd, t) end
      setLabel(previewName())
      dd:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Preview as", 1, 0.82, 0)
        GameTooltip:AddLine("See Top Ramen as another class would, on this character: its specs, tooltips and Dungeons tab. Your own talents are left out while previewing. Needs a /reload.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      dd:HookScript("OnLeave", function() GameTooltip:Hide() end)
      anchor = dd
    end
  end
  if not anchor then
    local pvBtn
    pvBtn = UI.Button(c1, 110, 24, previewName(), function()
      local list = choices()
      local i = 1
      for n, k in ipairs(list) do if k == (ns.db.previewClass or false) then i = n end end
      pick(list[i % #list + 1])
    end, "See Top Ramen as another class would, on this character. Needs a /reload.")
    pvBtn:SetPoint("LEFT", pv, "RIGHT", 10, 0)
    setLabel = function(t) pvBtn.label:SetText(t) end
    pvBtn.isTRButton = true
    anchor = pvBtn
  end
  local rl = UI.Button(c1, 70, 24, "Reload", function() ReloadUI() end)
  -- (a dropdown frame has empty space on its right; a button doesn't)
  if anchor.isTRButton then rl:SetPoint("LEFT", anchor, "RIGHT", 6, 0) else rl:SetPoint("LEFT", anchor, "RIGHT", -8, 2) end

  -- Bear focus and caps
  local c2 = card(content, "Tank focus", 330)
  local fnote = note(c2, "For tank specs (Bear): survival (Stamina, Armor, Defense, Dodge) or threat (damage, Strength, hit).", 16, -32, 300)
  slider = focusSlider(c2, 24, -86)
  -- no tank spec for this class (yet): show the slider greyed out and disabled
  if not ns.HasTankSpec() then
    slider:EnableMouse(false)
    if slider.Disable then slider:Disable() end
    slider:SetAlpha(0.35)
    fnote:SetText(GREY .. "Only for tank specs (Bear now; Protection Warrior and Paladin later). " ..
      "Your class has no tank spec, so this doesn't change your scores.|r")
    fnote:SetAlpha(0.8)
  end
  local capsHead = UI.Heading(c2, "Caps")
  capsHead:SetPoint("TOPLEFT", 14, -122)
  -- who you're fighting decides the hit and expertise caps
  local ctl = c2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ctl:SetPoint("TOPLEFT", 16, -150); ctl:SetText("Caps for")
  local function targetText()
    local t = ns.db.capTarget or "auto"
    for _, o in ipairs(ns.CAP_TARGETS) do
      if o.key == t then
        if t == "auto" then
          local now = ns.CapTarget() == "raid" and "raid bosses" or "my level"
          return o.text .. " (" .. now .. ")"
        end
        return o.text
      end
    end
    return "Automatic"
  end
  local capRows = {}
  local tbtn = UI.Button(c2, 180, 22, targetText(), function(self)
    local t, idx = ns.db.capTarget or "auto", 1
    for i, o in ipairs(ns.CAP_TARGETS) do if o.key == t then idx = i end end
    ns.db.capTarget = ns.CAP_TARGETS[idx % #ns.CAP_TARGETS + 1].key
    ns.RefreshSettings(); changed()
    if GameTooltip:IsOwned(self) and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
  end)
  tbtn:SetPoint("TOPRIGHT", -18, -146)
  tbtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Caps for (click to change)", 1, 0.82, 0)
    for _, o in ipairs(ns.CAP_TARGETS) do
      local on = o.key == (ns.db.capTarget or "auto")
      GameTooltip:AddDoubleLine((on and "> " or "   ") .. o.text, o.tip, on and 1 or 0.8, on and 0.82 or 0.8, on and 0 or 0.8, 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("WoW Forever caps (spells / attacks / dodge): my level 4 / 5 / 5%, dungeon +2 6 / 5.4 / 6%, raid boss 17 / 8 / 6.5%.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  tbtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  capRows.capHit = capRow(c2, "capHit", "Hit cap %", -176, changed)
  capRows.capExp = capRow(c2, "capExp", "Expertise cap %", -206, changed)
  capRow(c2, "capDef", "Tank Defense cap", -236, changed)
  capRows.capSpellHit = capRow(c2, "capSpellHit", "Spell hit cap %", -266, changed)
  capRow(c2, "talHit", "Extra hit % (not talents)", -296, changed)
  -- outside Custom the three boxes show the cap in use, greyed out (they run after the boxes' own refresh)
  controls[#controls + 1] = function()
    if tbtn.label then tbtn.label:SetText(targetText()) elseif tbtn.SetText then tbtn:SetText(targetText()) end
    local custom = (ns.db.capTarget or "auto") == "custom"
    for key, e in pairs(capRows) do
      e:SetText(tostring(ns.CapValue(key)))
      if custom then e:Enable() else e:Disable() end
      e:SetAlpha(custom and 1 or 0.55); e.__label:SetAlpha(custom and 1 or 0.55)
    end
  end

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
  local c4 = card(content, "Tools", 150)
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
  -- the shared Top Ramen launcher: minimap bowl button and a macro for your action bar
  local TRL = _G.TopRamenLauncher
  if TRL and TRL.SetShown then
    local mm = CreateFrame("CheckButton", nil, c4, "UICheckButtonTemplate")
    mm:SetPoint("TOPLEFT", 12, -76); mm:SetSize(24, 24)
    local ml = mm.text or mm.Text or mm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ml:ClearAllPoints(); ml:SetPoint("LEFT", mm, "RIGHT", 2, 0); ml:SetFontObject("GameFontHighlight")
    ml:SetText("Show the Top Ramen minimap button")
    mm:SetScript("OnClick", function(self) TRL.SetShown(self:GetChecked()) end)
    controls[#controls + 1] = function() mm:SetChecked(TRL.IsShown() and true or false) end
    if TRL.OnChange then TRL.OnChange(function(v) mm:SetChecked(v and true or false) end) end
    local mk = UI.Button(c4, 110, 24, "Make Macro", function() TRL.MakeMacro("TopRamenGear") end,
      "Makes a Gear macro (or finds the one you already have) and puts it on your cursor. Click an action bar slot to drop it there.")
    mk:SetPoint("LEFT", ml, "RIGHT", 18, 0)
  end
  note(c4, "Tip: /trg help lists the slash commands, /tr opens the Top Ramen menu. Everything here is saved between sessions.", 16, -118, 600)

  p:SetScript("OnShow", function() ns.SettingsLayout(); ns.RefreshSettings() end)
end
