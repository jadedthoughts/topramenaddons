-- Top Ramen Explorer: Export and Import of confirmed spots.
--   Export: shows your confirmed spots as text (one "Zone / Area / x, y" per line), read-only,
--           with a Copy button. Hand that text to another player.
--   Import: an empty box to paste someone's list into; Import saves their spots as confirmed.
-- WoW doesn't let addons use the clipboard, so Copy selects all the text (then Ctrl+C), and the
-- Import box opens with the cursor in it, ready for Ctrl+V.
local _, ns = ...

local HEADER = "TopRamenExplorer spots v1"
local exportFrame, importFrame

---------------------------------------------------------------------------
-- the data
---------------------------------------------------------------------------
function ns.ExportText()
  local lines, zones = { HEADER }, {}
  for z in pairs(ns.db.found) do zones[#zones + 1] = z end
  table.sort(zones)
  for _, z in ipairs(zones) do
    local areas = {}
    for a in pairs(ns.db.found[z]) do areas[#areas + 1] = a end
    table.sort(areas)
    for _, a in ipairs(areas) do
      local p = ns.db.found[z][a]
      lines[#lines + 1] = string.format("%s / %s / %.1f, %.1f", z, a, p[1], p[2])
    end
  end
  return table.concat(lines, "\n"), #lines - 1
end

-- returns added, skipped
function ns.ImportText(text)
  local added, skipped = 0, 0
  for line in (text or ""):gmatch("[^\r\n]+") do
    local z, a, x, y = line:match("^%s*(.-)%s*/%s*(.-)%s*/%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
    x, y = tonumber(x), tonumber(y)
    if z and a and x and y and x > 0 and x < 100 and y > 0 and y < 100 and z ~= "" and a ~= "" then
      if ns.Lookup(ns.db.found, z, a) then
        skipped = skipped + 1 -- you found it yourself; yours wins
      else
        ns.db.shared[z] = ns.db.shared[z] or {}
        ns.db.shared[z][a] = { x, y }
        added = added + 1
      end
    end
  end
  return added, skipped
end

---------------------------------------------------------------------------
-- a Top Ramen style dialog: header, instructions, a text box, a row of buttons
---------------------------------------------------------------------------
local function dialog(name, subtitle, help)
  local UI = ns.UI
  local f = UI.Window(name)
  f:SetSize(480, 400)
  f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  table.insert(UISpecialFrames, name)
  f:Hide()

  f.head = UI.Header(f, subtitle)

  local well = UI.Frame(f, UI.C.well, UI.C.line, 1)
  if help and help ~= "" then
    f.help = UI.Text(f, "GameFontHighlightSmall", UI.C.muted)
    f.help:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 12, -8)
    f.help:SetPoint("TOPRIGHT", f.head, "BOTTOMRIGHT", -12, -8)
    f.help:SetWordWrap(true)
    f.help:SetText(help)
    well:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", -2, -8)
  else
    well:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 10, -10)
  end

  -- the text box, on a dark well
  well:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 48)
  local sf = CreateFrame("ScrollFrame", name .. "Scroll", well, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -26, 6)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(410)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sf:SetScrollChild(eb)
  well:EnableMouse(true)
  well:SetScript("OnMouseDown", function() eb:SetFocus() end)
  f.box = eb

  -- faded instructions shown inside the box while it's empty
  f.placeholder = UI.Text(well, "GameFontHighlight", UI.C.muted)
  f.placeholder:SetPoint("TOPLEFT", 10, -10)
  f.placeholder:SetPoint("RIGHT", well, "RIGHT", -30, 0)
  f.placeholder:SetWordWrap(true)
  f.placeholder:SetJustifyV("TOP")
  f.placeholder:Hide()

  -- a line for feedback ("press Ctrl+C now", "imported 5 spots")
  f.note = UI.Text(f, "GameFontNormalSmall", UI.C.gold)
  f.note:SetPoint("BOTTOMLEFT", 14, 18)
  f.note:SetPoint("RIGHT", f, "RIGHT", -200, 0)
  f.note:SetWordWrap(true)
  return f
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function buildExport()
  local UI = ns.UI
  local f = dialog("TopRamenExplorerExport", "Explorer - Export spots",
    "These are the spots you've confirmed in game. Click Copy, press Ctrl+C, then paste the text " ..
    "to another player. They add it with Import in their own Top Ramen Explorer.")
  -- read-only: put the text back if anyone types in it
  f.box:SetScript("OnTextChanged", function(self, userInput)
    if userInput and f.text then self:SetText(f.text); self:HighlightText() end
  end)
  local copy = UI.Button(f, 90, 26, "Copy", function()
    f.box:SetFocus()
    f.box:HighlightText()
    f.note:SetText("Selected - now press Ctrl+C to copy.")
  end)
  copy:SetPoint("BOTTOMRIGHT", -12, 12)
  exportFrame = f
end

function ns.ShowExport()
  if not exportFrame then buildExport() end
  if importFrame then importFrame:Hide() end
  local text, n = ns.ExportText()
  exportFrame.text = text
  exportFrame.box:SetText(text)
  exportFrame.box:ClearFocus()
  exportFrame.note:SetText(n == 0 and "No confirmed spots yet - they're saved as you discover areas."
    or (n .. " spot" .. (n == 1 and "" or "s") .. " ready to copy."))
  exportFrame:Show()
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
local function buildImport()
  local UI = ns.UI
  local f = dialog("TopRamenExplorerImport", "Explorer - Import spots", nil)
  f.placeholder:SetText("Paste confirmed coordinates from another player here (Ctrl+V), then click Import.\n\n" ..
    "Lines look like:  Ashenvale / The Howling Vale / 52.7, 37.7\n\n" ..
    "Spots you found yourself are kept.")
  -- the placeholder shows, and Clear and Import are greyed out, while the box is empty
  local function syncPlaceholder()
    local empty = (f.box:GetText() or "") == ""
    f.placeholder:SetShown(empty)
    if f.clearBtn then f.clearBtn:SetEnabled(not empty) end
    if f.importBtn then f.importBtn:SetEnabled(not empty) end
  end
  f.box:SetScript("OnTextChanged", syncPlaceholder)
  local imp = UI.Button(f, 90, 26, "Import", function()
    local added, skipped = ns.ImportText(f.box:GetText())
    if added + skipped == 0 then
      f.note:SetText("Nothing to import - paste lines like  Zone / Area / x, y")
    else
      f.note:SetText(string.format("Imported %d spot%s%s.", added, added == 1 and "" or "s",
        skipped > 0 and (" (" .. skipped .. " skipped - you found those yourself)") or ""))
      ns.Print(string.format("imported %d spots.", added))
      wipe(ns.spots)
      ns.Refresh()
    end
  end)
  imp:SetPoint("BOTTOMRIGHT", -12, 12)
  f.importBtn = imp
  local clear = UI.Button(f, 70, 26, "Clear", function()
    f.box:SetText("")
    f.note:SetText("")
    f.box:SetFocus()
    syncPlaceholder()
  end)
  clear:SetPoint("RIGHT", imp, "LEFT", -6, 0)
  f.clearBtn = clear
  f.syncPlaceholder = syncPlaceholder
  syncPlaceholder()
  importFrame = f
end

function ns.ShowImport()
  if not importFrame then buildImport() end
  if exportFrame then exportFrame:Hide() end
  importFrame.box:SetText("")
  importFrame.note:SetText("")
  importFrame:Show()
  importFrame.box:SetFocus()
  importFrame.syncPlaceholder()
end
