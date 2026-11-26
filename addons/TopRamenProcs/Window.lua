-- Top Ramen Procs: the window (/trp) and the export box
local _, ns = ...
local UI = ns.UI
local C = UI.C
local HX = UI.HEX

local W, H = 820, 460
local ROW_H = 22
local TOP = UI.HEAD_H + 70 -- where the list starts

local frame, exportFrame
local rows = {}
local W_ = {}

-- columns: key, heading, width, right-aligned
local COLS = {
  { "name", "Item", 0 },
  { "worn", "Worn", 64, true },
  { "hits", "Hits", 70, true },
  { "procs", "Procs", 56, true },
  { "min", "Per min", 64, true },
  { "hit", "Per hit", 64, true },
  { "ppm", "PPM", 50, true },
  { "gear", "Gear assumes", 96, true },
  { "vs", "Real vs. assumed", 110, true },
}
local function fixedWidth() local w = 0; for i = 2, #COLS do w = w + COLS[i][3] end return w end

local function tip(widget, title, text)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function placeCells(parent, cells, width)
  local x = width - 10
  for i = #COLS, 2, -1 do
    local c = cells[i]
    c:ClearAllPoints()
    c:SetPoint("RIGHT", parent, "LEFT", x, 0)
    c:SetWidth(COLS[i][3] - 6)
    x = x - COLS[i][3]
  end
  cells[1]:ClearAllPoints()
  cells[1]:SetPoint("LEFT", parent, "LEFT", 10, 0)
  cells[1]:SetWidth(math.max(120, width - 20 - fixedWidth()))
end

local function makeRow(i)
  local r = CreateFrame("Button", nil, W_.child)
  r:SetHeight(ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(C.row[1], C.row[2], C.row[3], i % 2 == 0 and 0.6 or 0)
  r.cells = {}
  for c = 1, #COLS do
    local t = UI.Text(r, "GameFontHighlightSmall", C.text)
    t:SetJustifyH(COLS[c][4] and "RIGHT" or "LEFT")
    t:SetWordWrap(false)
    r.cells[c] = t
  end
  r:SetScript("OnEnter", function(self)
    if not self.tipFn then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tipFn(GameTooltip)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function setRow(r, values, color)
  for c = 1, #COLS do
    r.cells[c]:SetText(values[c] or "")
    local col = (c == 1 and color) or C.text
    r.cells[c]:SetTextColor(col[1], col[2], col[3])
  end
end

function ns.Refresh()
  if not frame or not frame:IsShown() then return end
  local width = W_.scroll:GetWidth()
  W_.child:SetWidth(width)
  placeCells(W_.head, W_.headCells, width)

  local on = ns.IsOn()
  W_.toggle:SetText(on and "Logging: on" or "Logging: off")
  if on then W_.toggle:UnlockHighlight() else W_.toggle:LockHighlight() end
  local since = ns.Since()
  W_.status:SetText((on and (HX.green .. "Counting in the background whenever you fight.|r") or (HX.red .. "Paused.|r"))
    .. HX.muted .. (since and ("  Since " .. date("%d %b", since) .. ".") or "") .. "|r")

  local list = ns.ProcRows()
  local n = 0
  for _, row in ipairs(list) do
    n = n + 1
    local r = rows[n] or makeRow(n)
    local rec = row.r
    local vals = { rec.n or ("item " .. row.id), ns.fmtTime(rec.s), tostring(row.hits), tostring(row.procs) }
    local a, aw = ns.Assumed(rec)
    if row.procs > 0 then
      vals[5] = string.format("%.2f", row.perMin)
      vals[6] = row.perHit and ns.pct(row.perHit) or "-"
      vals[7] = row.ppm and string.format("%.1f", row.ppm) or "-"
    else
      vals[5], vals[6], vals[7] = "-", "-", "-"
    end
    vals[8] = ns.pct(a)
    if row.perHit and row.procs > 0 then
      local ratio = row.perHit / a
      local col = ratio > 1.25 and HX.green or ratio < 0.8 and HX.red or HX.text
      vals[9] = col .. string.format("x%.1f", ratio) .. "|r" .. (row.procs < 10 and (HX.dim .. " early|r") or "")
    else
      vals[9] = HX.dim .. "no procs yet|r"
    end
    setRow(r, vals, C.gold)
    r.tipFn = function(tt)
      tt:AddLine(rec.n or ("item " .. row.id))
      if rec.fx then tt:AddLine(rec.fx, 1, 1, 1, true) end
      local _, hitWord = ns.ProcHitsFor(rec)
      tt:AddLine(string.format("%d %s in %s worn in combat", row.hits, hitWord, ns.fmtTime(rec.s)), 0.8, 0.8, 0.8)
      local bs = ns.BaseSpeed(rec)
      if bs then tt:AddLine(string.format("Weapon speed %.2f (the chance per hit is based on this, not on how fast you swing)", bs), 0.8, 0.8, 0.8, true) end
      if #row.spells > 0 then
        local names = {}
        for _, sp in ipairs(row.spells) do names[#names + 1] = sp.n .. " (" .. sp.c .. ")" end
        tt:AddLine("From: " .. table.concat(names, ", "), 0.8, 0.8, 0.8, true)
      end
      tt:AddLine("Gear assumes " .. ns.pct(a) .. " per hit (" .. aw .. ").", 0.8, 0.8, 0.8, true)
      local pl = ns.PartyLine(row.id)
      if pl then tt:AddLine(pl, 0.3, 0.87, 0.5, true) end
      if row.procs < 10 then tt:AddLine("Fewer than 10 procs: an early number, keep going.", 0.6, 0.6, 0.6, true) end
    end
    r:Show()
  end

  local loose = ns.Loose(false)
  if #loose > 0 then
    n = n + 1
    local r = rows[n] or makeRow(n)
    setRow(r, { "Not matched to an item yet (swap one piece of gear for a fight and it sorts itself out)" }, C.muted)
    r.tipFn = nil
    r:Show()
    for i, x in ipairs(loose) do
      if i > 12 then break end
      n = n + 1
      local rr = rows[n] or makeRow(n)
      setRow(rr, { "   " .. x.s.n .. "  " .. HX.dim .. x.from .. "|r", "", "", tostring(x.s.c) }, C.muted)
      rr.tipFn = nil
      rr:Show()
    end
  end

  for i = 1, n do
    local r = rows[i]
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    placeCells(r, r.cells, width)
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  W_.child:SetHeight(math.max(1, n * ROW_H))
  W_.empty:SetShown(n == 0)
end

local function build()
  frame = UI.Window("TopRamenProcsWindow")
  frame:SetSize(W, H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true); frame:SetResizable(true); frame:EnableMouse(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(720, 340, 1600, 1100)
  elseif frame.SetMinResize then frame:SetMinResize(720, 340) end
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "TopRamenProcsWindow")

  local head = UI.Header(frame, "Procs")
  -- header buttons, right to left from the close button
  W_.reset = UI.Button(head, 70, 24, "Reset")
  W_.reset:SetPoint("RIGHT", head.close, "LEFT", -10, 0)
  W_.reset:SetScript("OnClick", function(self)
    -- two clicks, so a stray one doesn't wipe the log
    if self.armed then
      self.armed = false; self:SetText("Reset")
      ns.Reset(); ns.say("proc log cleared"); ns.Refresh()
    else
      self.armed = true; self:SetText("Sure?")
      C_Timer.After(3, function() if self.armed then self.armed = false; self:SetText("Reset") end end)
    end
  end)
  tip(W_.reset, "Reset", "Clear everything counted so far. Click twice.")
  W_.export = UI.Button(head, 76, 24, "Export", function() ns.ShowExport(ns.ExportText()) end)
  W_.export:SetPoint("RIGHT", W_.reset, "LEFT", -6, 0)
  tip(W_.export, "Export", "Copy the whole log, to paste to Claude so Gear's scores can use real proc rates.")
  W_.share = UI.Button(head, 76, 24, "Share", function() ns.ShareProcs() end)
  W_.share:SetPoint("RIGHT", W_.export, "LEFT", -6, 0)
  tip(W_.share, "Share", "Send your counts to your group. Members with Top Ramen Procs add them to their log (shown on each item's tooltip).")
  W_.toggle = UI.Button(head, 110, 24, "Logging: on", function() ns.SetOn(not ns.IsOn()); ns.Refresh() end)
  W_.toggle:SetPoint("RIGHT", W_.share, "LEFT", -6, 0)
  tip(W_.toggle, "Logging", "Pause or resume counting.")

  W_.status = UI.Text(frame, "GameFontHighlightSmall", C.muted)
  W_.status:SetPoint("TOPLEFT", 14, -(UI.HEAD_H + 12))
  local intro = UI.Text(frame, "GameFontHighlightSmall", C.muted)
  intro:SetPoint("TOPLEFT", W_.status, "BOTTOMLEFT", 0, -6)
  intro:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  intro:SetText("How often each item with a \"Chance on hit\" or \"when struck\" effect really procs, next to what Top Ramen Gear assumes. Hover a row for details.")

  -- column headings
  W_.head = CreateFrame("Frame", nil, frame)
  W_.head:SetHeight(18)
  W_.head:SetPoint("TOPLEFT", 12, -(TOP - 20))
  W_.head:SetPoint("TOPRIGHT", -32, -(TOP - 20))
  W_.headCells = {}
  for c = 1, #COLS do
    local t = UI.Text(W_.head, "GameFontNormalSmall", C.gold)
    t:SetJustifyH(COLS[c][4] and "RIGHT" or "LEFT")
    t:SetText(COLS[c][2])
    W_.headCells[c] = t
  end

  local well = UI.Panel(frame, C.well)
  well:SetPoint("TOPLEFT", 10, -TOP)
  well:SetPoint("BOTTOMRIGHT", -10, 34)
  W_.scroll = CreateFrame("ScrollFrame", "TopRamenProcsScroll", frame, "UIPanelScrollFrameTemplate")
  W_.scroll:SetPoint("TOPLEFT", 12, -(TOP + 2))
  W_.scroll:SetPoint("BOTTOMRIGHT", -32, 36)
  W_.child = CreateFrame("Frame", nil, W_.scroll)
  W_.child:SetSize(1, 1)
  W_.scroll:SetScrollChild(W_.child)
  W_.empty = UI.Text(frame, "GameFontHighlight", C.muted)
  W_.empty:SetPoint("TOP", W_.scroll, "TOP", 0, -40)
  W_.empty:SetJustifyH("CENTER")
  W_.empty:SetText("Nothing yet. Wear an item with a \"Chance on hit\" effect and fight:\nit counts in the background.")

  local foot = UI.Text(frame, "GameFontHighlightSmall", C.muted)
  foot:SetPoint("BOTTOMLEFT", 14, 12)
  foot:SetText("/trp help lists the commands · PPM = chance per hit x 60 / the weapon's printed speed (the game's own rule)")

  UI.Grip(frame, function() ns.Refresh() end)
  frame:SetScript("OnSizeChanged", function() ns.Refresh() end)
  frame:SetScript("OnShow", function() ns.Refresh() end)
  -- keep it current while it's open, a couple of times a second at most
  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc > 2 then acc = 0; ns.Refresh() end
  end)
  frame:Hide()
end

function ns.ToggleWindow()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end
ns.Open = function() if not frame then build() end frame:Show() end

---------------------------------------------------------------------------
-- the export box
---------------------------------------------------------------------------
function ns.ShowExport(text)
  if not exportFrame then
    local f = UI.Window("TopRamenProcsExport")
    exportFrame = f
    f:SetSize(680, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local head = UI.Header(f, "Procs export: press Ctrl+C, then paste it to Claude")
    local well = UI.Panel(f, C.well)
    well:SetPoint("TOPLEFT", 10, -(UI.HEAD_H + 10))
    well:SetPoint("BOTTOMRIGHT", -10, 46)
    local scroll = CreateFrame("ScrollFrame", "TopRamenProcsExportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -(UI.HEAD_H + 16))
    scroll:SetPoint("BOTTOMRIGHT", -34, 50)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(610)
    edit:SetAutoFocus(true)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    local close = UI.Button(f, 110, 26, CLOSE or "Close", function() f:Hide() end)
    close:SetPoint("BOTTOM", 0, 12)
    tinsert(UISpecialFrames, "TopRamenProcsExport")
  end
  exportFrame.edit:SetText(text or "")
  exportFrame:Show()
  exportFrame.edit:SetFocus()
  exportFrame.edit:HighlightText()
end
