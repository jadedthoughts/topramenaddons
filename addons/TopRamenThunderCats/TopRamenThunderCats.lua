-- Top Ramen ThunderCats: plays a ThunderCats clip when you cast Shifting Power.
-- Random from pool (tick the clips to shuffle) or Always one sound (pick one).
-- Group members who also have the addon hear the same clip, played from their own copy.
local ADDON, ns = ...
local UI = ns.UI
local C, HEX = UI.C, UI.HEX

-- Clips are looked for in two places, in this order:
--  1. Interface\AddOns\TopRamenThunderCats_Sounds\  (a folder of its own, which
--     addon updates never touch: the safest place for your clips)
--  2. Interface\AddOns\TopRamenThunderCats\Sounds\  (inside the addon; the
--     Top Ramen launcher keeps this folder when it updates the addon)
local SOUND_DIRS = {
  "Interface\\AddOns\\" .. ADDON .. "_Sounds\\",
  "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\",
}
local CLIPS = {
  { file = "ThunderCats1.mp3", name = "Clip 1", len = "9.6s", secs = 9.6 },
  { file = "ThunderCats2.mp3", name = "Clip 2", len = "9.8s", secs = 9.8 },
  { file = "ThunderCats3.mp3", name = "Clip 3", len = "4.6s", secs = 4.6 },
  { file = "ThunderCats4.mp3", name = "Clip 4", len = "4.3s", secs = 4.3 },
}
local CHANNELS = { "Master", "SFX", "Music", "Ambience" }
local CVARS = { Master = "Sound_MasterVolume", SFX = "Sound_SFXVolume", Music = "Sound_MusicVolume", Ambience = "Sound_AmbienceVolume" }
local PREFIX = "TRThunderCats"
local DEFAULT_SPELL = "Shifting Power"

local function say(msg) print(HEX.gold .. "Top Ramen ThunderCats|r: " .. msg) end
ns.say = say

---------------------------------------------------------------------------
-- settings
---------------------------------------------------------------------------
local function db()
  if type(TopRamenThunderCatsDB) ~= "table" then TopRamenThunderCatsDB = {} end
  local d = TopRamenThunderCatsDB
  if d.enabled == nil then d.enabled = true end
  if d.mode ~= "one" and d.mode ~= "random" then d.mode = "random" end
  if type(d.pick) ~= "number" or not CLIPS[d.pick] then d.pick = 1 end
  if type(d.pool) ~= "table" then d.pool = {} end
  for i = 1, #CLIPS do if d.pool[i] == nil then d.pool[i] = true end end
  if not tContains(CHANNELS, d.channel or "") then d.channel = "Master" end
  if type(d.spell) ~= "string" or d.spell:match("^%s*$") then d.spell = DEFAULT_SPELL end
  if d.share == nil then d.share = true end   -- send my clip to my group
  if d.hear == nil then d.hear = true end     -- play clips my group sends
  if type(d.volume) ~= "number" then d.volume = 100 end -- % of the channel's own volume
  d.volume = math.max(5, math.min(100, math.floor(d.volume / 5 + 0.5) * 5))
  if d.quiet == nil then d.quiet = false end           -- sometimes stay quiet on a cast
  if type(d.chance) ~= "number" then d.chance = 50 end -- % of casts that play a clip when quiet is on
  d.chance = math.max(10, math.min(90, math.floor(d.chance / 10 + 0.5) * 10))
  if type(d.window) ~= "table" then d.window = {} end
  return d
end
ns.db = db

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

---------------------------------------------------------------------------
-- playing
---------------------------------------------------------------------------
local handle, lastIdx, lastFrom, warned
local skipped -- the last cast stayed quiet
local startedAt = -100 -- when the current clip started
local debugOn = false
local function debug(msg) if debugOn then print(HEX.dim .. "TRTC debug|r: " .. msg) end end
local playEnds = 0
local refresh = function() end

-- Volume: WoW can't set one sound's volume, so below 100% the addon turns the chosen channel's
-- slider down while a clip plays and puts it back after. The old value is kept in the saved
-- variables, so it's put back on the next login even if the game closes mid-clip.
local gen = 0
local function getCVar(n)
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  return get and tonumber((get(n)))
end
local function setCVar(n, v)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  if set then pcall(set, n, v) end
end
local function restoreVolume()
  local d = db()
  if d.restore and d.restore.cvar then setCVar(d.restore.cvar, d.restore.value) end
  d.restore = nil
end
local function after(sec, fn)
  local my = gen
  if C_Timer then C_Timer.After(sec, function() if gen == my then fn() end end) end
end
-- set the channel to the clip volume for the next `seconds`
local function dimFor(seconds)
  local d = db()
  gen = gen + 1
  local cvar = CVARS[d.channel]
  if d.restore and d.restore.cvar ~= cvar then restoreVolume() end
  if d.volume >= 100 or not cvar then restoreVolume(); return end
  if not d.restore then
    local cur = getCVar(cvar)
    if not cur then return end
    d.restore = { cvar = cvar, value = cur }
  end
  setCVar(cvar, string.format("%.3f", d.restore.value * d.volume / 100))
  after(seconds + 0.4, restoreVolume)
end
-- the slider moved: change a clip that's playing right now too
local function volumeChanged()
  local left = playEnds - GetTime()
  if left > 0 then dimFor(left) else restoreVolume() end
end

local function stop()
  if handle and StopSound then StopSound(handle, 300) end
  handle = nil
  playEnds = 0
  gen = gen + 1
  after(0.35, restoreVolume)
end
ns.Stop = stop

-- from: nil for you, or the group member's name
-- why: what asked for it (for /trtc debug). force: a button you clicked, which always restarts.
-- Anything else is ignored when a clip started under 1.5 seconds ago, so one cast can't start
-- the clip twice (that cuts the first start off and sounds like a stutter).
local function play(idx, from, why, force)
  local clip = CLIPS[idx]
  if not clip then return end
  local since = GetTime() - startedAt
  if not force and since < 1.5 then
    debug(string.format("ignored %s (%s): a clip started %.2fs ago", clip.name, why or "?", since))
    return
  end
  debug(string.format("playing %s (%s)", clip.name, why or "?"))
  startedAt = GetTime()
  stop()
  dimFor(clip.secs)
  local ok, willPlay, h
  for _, dir in ipairs(SOUND_DIRS) do
    ok, willPlay, h = pcall(PlaySoundFile, dir .. clip.file, db().channel)
    if ok and willPlay then break end
  end
  if ok and willPlay then
    handle = h
    playEnds = GetTime() + clip.secs
  else
    gen = gen + 1
    restoreVolume()
  end
  if not (ok and willPlay) and not warned then
    warned = true
    say("the clip didn't play. Check that the " .. db().channel .. " sound channel is on (Esc > System > Sound), or pick another channel in /trtc. "
      .. "If you just installed the addon, quit and restart WoW: a /reload doesn't pick up new sound files. "
      .. "Clips go in Interface\\AddOns\\TopRamenThunderCats_Sounds (" .. clip.file .. " and so on).")
  end
  lastIdx, lastFrom = idx, from
  skipped = false
  refresh()
end
ns.Play = play

-- which clip a cast plays: the picked one, or a random one from the pool (not the same one twice in a row)
local function choose()
  local d = db()
  if d.mode == "one" then return d.pick end
  local list = {}
  for i = 1, #CLIPS do if d.pool[i] then list[#list + 1] = i end end
  if #list == 0 then return nil end
  if #list > 1 and lastIdx then
    for k, i in ipairs(list) do if i == lastIdx then table.remove(list, k); break end end
  end
  return list[math.random(#list)]
end
ns.Choose = choose

-- what a cast plays: nil when "Sometimes stay quiet" says not this time (then the group hears nothing either)
function ns.CastPick()
  local d = db()
  if d.quiet and math.random(100) > d.chance then
    skipped = true
    refresh()
    return nil
  end
  return choose()
end

---------------------------------------------------------------------------
-- group sharing (addon messages; only people with the addon get them)
---------------------------------------------------------------------------
local function groupChannel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0) then return "PARTY" end
end

local sentTags = {} -- tags on my own messages, so an echo of one is never played
local function share(idx)
  if not db().share then return end
  local ch = groupChannel()
  if not ch then return end
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  local tag = tostring(math.random(100000, 999999))
  sentTags[tag] = true
  if send then pcall(send, PREFIX, "P1:" .. idx .. ":" .. tag, ch) end
  debug("sent " .. CLIPS[idx].name .. " to " .. ch)
end

local heardAt = {}
local function received(msg, sender)
  if not db().hear then return end
  local name = Ambiguate and Ambiguate(sender or "", "none") or (sender or "")
  local me = UnitName("player")
  local n, tag = (msg or ""):match("^P%d+:(%d+):?(%w*)")
  if name == me or (name:match("^([^%-]+)") == me) or (tag ~= "" and sentTags[tag]) then
    debug("ignored my own message coming back (" .. tostring(sender) .. ")")
    return
  end
  local idx = tonumber(n)
  if not idx or not CLIPS[idx] then return end
  local now = GetTime()
  if heardAt[name] and now - heardAt[name] < 1.5 then return end
  heardAt[name] = now
  play(idx, name, "group: " .. name)
end

---------------------------------------------------------------------------
-- the cast
---------------------------------------------------------------------------
local lastSpell -- name of the last spell you cast, so the window can show it
local firedAt = 0

local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and n then return n end
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function onCast(id, event)
  local name = spellName(id)
  if not name then return end
  if name:lower() == trim(db().spell):lower() then debug(name .. " cast seen (" .. tostring(event) .. ")") end
  if name ~= lastSpell then lastSpell = name; refresh() end
  local d = db()
  if not d.enabled or name:lower() ~= trim(d.spell):lower() then return end
  local now = GetTime()
  if now - firedAt < 1.5 then return end -- a channel fires both "started" and "succeeded"
  firedAt = now
  local idx = ns.CastPick()
  if not idx then return end
  play(idx, nil, "your cast")
  share(idx)
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local W = {}
local WIDTH, HEIGHT = 390, 482

local function tip(f, title, body)
  f:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, C.gold[1], C.gold[2], C.gold[3])
    local b = type(body) == "function" and body() or body
    if b then GameTooltip:AddLine(b, C.text[1], C.text[2], C.text[3], true) end
    GameTooltip:Show()
  end)
  f:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function heading(parent, text, y)
  local t = UI.Text(parent, "GameFontNormal", C.gold)
  t:SetPoint("TOPLEFT", 16, y)
  t:SetText(text)
  local l = UI.Line(parent)
  l:SetPoint("LEFT", t, "RIGHT", 8, 0); l:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  return t
end

local function savePos(f)
  local p, _, rp, x, y = f:GetPoint()
  local w = db().window
  w.point, w.rel, w.x, w.y = p, rp, x, y
end

local function saveSpell()
  local v = trim(W.spell:GetText())
  if v == "" then v = DEFAULT_SPELL end
  db().spell = v
  W.spell:SetText(v)
  W.spell:ClearFocus()
  refresh()
end

local function build()
  if W.frame then return end
  local d = db()
  local f = UI.Window("TopRamenThunderCatsFrame")
  W.frame = f
  f:SetSize(WIDTH, HEIGHT)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
  if d.window.point then f:SetPoint(d.window.point, UIParent, d.window.rel or d.window.point, d.window.x or 0, d.window.y or 0)
  else f:SetPoint("CENTER") end
  tinsert(UISpecialFrames, "TopRamenThunderCatsFrame") -- Escape closes it
  f:Hide()

  local head = UI.Header(f, "ThunderCats")
  W.onoff = UI.Button(head, 70, 26, "", function() db().enabled = not db().enabled; refresh() end)
  W.onoff:SetPoint("RIGHT", head.close, "LEFT", -6, 0)
  tip(W.onoff, "On / Off", "Turns the clip on Shifting Power on or off. Play buttons below still work.")

  -- the spell
  local y = -(UI.HEAD_H + 14)
  heading(f, "Plays when you cast", y)
  y = y - 24
  W.spell = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  W.spell:SetSize(200, 22)
  W.spell:SetPoint("TOPLEFT", 24, y)
  W.spell:SetAutoFocus(false)
  W.spell:SetMaxLetters(60)
  W.spell:SetScript("OnEnterPressed", saveSpell)
  W.spell:SetScript("OnEditFocusLost", saveSpell)
  W.spell:SetScript("OnEscapePressed", function(self) self:SetText(db().spell); self:ClearFocus() end)
  W.reset = UI.Button(f, 120, 22, "Shifting Power", function() W.spell:SetText(DEFAULT_SPELL); saveSpell() end)
  W.reset:SetPoint("LEFT", W.spell, "RIGHT", 10, 0)
  tip(W.reset, "Back to Shifting Power", "Sets the spell name back to Shifting Power.")
  y = y - 28
  W.last = UI.Text(f, "GameFontHighlightSmall", C.muted)
  W.last:SetPoint("TOPLEFT", 18, y)
  W.useLast = UI.Button(f, 70, 18, "Use this", function()
    if lastSpell then W.spell:SetText(lastSpell); saveSpell() end
  end)
  W.useLast:SetPoint("LEFT", W.last, "RIGHT", 8, 0)
  tip(W.useLast, "Use this spell", "Makes the spell you cast last the one that plays a clip. Handy if the name is spelled differently on your realm.")

  -- the sound
  y = y - 30
  heading(f, "Sound", y)
  y = y - 26
  W.modeRandom = UI.Button(f, 170, 24, "Random from pool", function() db().mode = "random"; refresh() end)
  W.modeRandom:SetPoint("TOPLEFT", 16, y)
  tip(W.modeRandom, "Random from pool", "Each cast plays a random clip from the ones you tick, never the same one twice in a row.")
  W.modeOne = UI.Button(f, 170, 24, "Always one sound", function() db().mode = "one"; refresh() end)
  W.modeOne:SetPoint("LEFT", W.modeRandom, "RIGHT", 8, 0)
  tip(W.modeOne, "Always one sound", "Every cast plays the clip you pick.")
  y = y - 30
  W.hint = UI.Text(f, "GameFontHighlightSmall", C.muted)
  W.hint:SetPoint("TOPLEFT", 18, y)

  y = y - 18
  W.rows = {}
  for i, clip in ipairs(CLIPS) do
    local r = CreateFrame("Frame", nil, f)
    r:SetPoint("TOPLEFT", 16, y); r:SetPoint("RIGHT", f, "RIGHT", -16, 0); r:SetHeight(28)
    local bg = UI.Panel(r)
    bg:SetAllPoints(r)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetPoint("LEFT", 4, 0)
    r.check:SetScript("OnClick", function(self)
      local dd = db()
      if dd.mode == "one" then dd.pick = i else dd.pool[i] = self:GetChecked() and true or false end
      refresh()
    end)
    r.name = UI.Text(r, "GameFontHighlight", C.text)
    r.name:SetPoint("LEFT", r.check, "RIGHT", 6, 0)
    r.name:SetText(clip.name)
    r.len = UI.Text(r, "GameFontHighlightSmall", C.muted)
    r.len:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.len:SetText(clip.len)
    r.play = UI.Button(r, 64, 20, "Play", function() play(i, nil, "Play button", true) end)
    r.play:SetPoint("RIGHT", -4, 0)
    tip(r.play, "Play " .. clip.name, "Plays it just for you, so you can choose.")
    r.now = UI.Text(r, "GameFontHighlightSmall", C.gold)
    r.now:SetPoint("RIGHT", r.play, "LEFT", -8, 0)
    W.rows[i] = r
    y = y - 32
  end

  y = y - 2
  W.test = UI.Button(f, 170, 24, "Test a cast", function() local i = ns.CastPick(); if i then play(i, nil, "Test a cast", true) end end)
  W.test:SetPoint("TOPLEFT", 16, y)
  tip(W.test, "Test a cast", "Does what a Shifting Power cast would (including staying quiet sometimes, if that's on) and plays it just for you.")
  W.stop = UI.Button(f, 80, 24, "Stop", stop)
  W.stop:SetPoint("LEFT", W.test, "RIGHT", 8, 0)
  W.channel = UI.Button(f, 82, 24, "", function()
    local dd = db()
    stop()
    local k = 1
    for n, c in ipairs(CHANNELS) do if c == dd.channel then k = n end end
    dd.channel = CHANNELS[k % #CHANNELS + 1]
    refresh()
  end)
  W.channel:SetPoint("LEFT", W.stop, "RIGHT", 8, 0)

  -- volume
  y = y - 34
  local vl = UI.Text(f, "GameFontHighlight", C.text)
  vl:SetPoint("TOPLEFT", 18, y - 1)
  vl:SetText("Volume")
  local s = CreateFrame("Slider", nil, f, "BackdropTemplate")
  W.vol = s
  s:SetOrientation("HORIZONTAL")
  s:SetSize(200, 14)
  s:SetPoint("TOPLEFT", 80, y)
  UI.Skin(s, C.well, C.trim, 1)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetMinMaxValues(5, 100)
  s:SetValueStep(5)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * 5) end)
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / 5 + 0.5) * 5
    W.volText:SetText(v .. "%")
    if v ~= db().volume then db().volume = v; volumeChanged() end
  end)
  W.volText = UI.Text(f, "GameFontHighlight", C.gold)
  W.volText:SetPoint("LEFT", s, "RIGHT", 10, 0)
  tip(s, "Clip volume", function()
    return "How loud the clips are, as a share of your " .. db().channel .. " volume. At 100% nothing else changes. "
      .. "Lower than that, the addon turns the " .. db().channel .. " slider down while a clip plays and back up after, "
      .. "so other sounds on that channel dip for those few seconds too. Press Play while you drag to hear it."
  end)

  -- sometimes stay quiet
  y = y - 30
  W.quiet = UI.Button(f, 170, 24, "", function() db().quiet = not db().quiet; refresh() end)
  W.quiet:SetPoint("TOPLEFT", 16, y)
  tip(W.quiet, "Sometimes stay quiet", "So it doesn't get overdone: some casts play nothing at all. Use the slider to set how often a clip plays.")
  local q = CreateFrame("Slider", nil, f, "BackdropTemplate")
  W.chance = q
  q:SetOrientation("HORIZONTAL")
  q:SetSize(110, 14)
  q:SetPoint("LEFT", W.quiet, "RIGHT", 10, 0)
  UI.Skin(q, C.well, C.trim, 1)
  q:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  q:SetMinMaxValues(10, 90)
  q:SetValueStep(10)
  if q.SetObeyStepOnDrag then q:SetObeyStepOnDrag(true) end
  q:EnableMouseWheel(true)
  q:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * 10) end)
  q:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / 10 + 0.5) * 10
    db().chance = v
    W.chanceText:SetText(ns.ChanceText(v))
  end)
  W.chanceText = UI.Text(f, "GameFontHighlightSmall", C.gold)
  W.chanceText:SetPoint("LEFT", q, "RIGHT", 8, 0)
  tip(q, "How often it plays", function()
    local c = db().chance
    return "A clip plays on about " .. c .. "% of your casts and stays quiet on the other " .. (100 - c) .. "%."
  end)
  tip(W.channel, "Sound channel", "Which volume slider the clips follow. Master plays even with sound effects turned off. Click to change.")

  -- the group
  y = y - 36
  heading(f, "Group", y)
  y = y - 26
  W.share = UI.Button(f, 170, 24, "", function() db().share = not db().share; refresh() end)
  W.share:SetPoint("TOPLEFT", 16, y)
  tip(W.share, "Share my clip", "When you cast, party or raid members who have Top Ramen ThunderCats hear the same clip, played from their own copy of the addon.")
  W.hear = UI.Button(f, 170, 24, "", function() db().hear = not db().hear; refresh() end)
  W.hear:SetPoint("LEFT", W.share, "RIGHT", 8, 0)
  tip(W.hear, "Hear the group's clips", "Plays the clip when a party or raid member with the addon casts it.")
  y = y - 30
  W.status = UI.Text(f, "GameFontHighlightSmall", C.muted)
  W.status:SetPoint("TOPLEFT", 18, y)
  W.status:SetPoint("RIGHT", f, "RIGHT", -16, 0)

  f:HookScript("OnShow", function() refresh() end)
end

refresh = function()
  if not (W.frame and W.frame:IsShown()) then return end
  local d = db()
  W.onoff:SetText(d.enabled and "On" or "Off")
  if d.enabled then W.onoff:LockHighlight() else W.onoff:UnlockHighlight() end
  if not W.spell:HasFocus() then W.spell:SetText(d.spell) end
  W.last:SetText("Last spell you cast: " .. (lastSpell and (HEX.text .. lastSpell .. "|r") or "none yet"))
  W.useLast:SetShown(lastSpell ~= nil and lastSpell:lower() ~= trim(d.spell):lower())

  if d.mode == "one" then
    W.modeOne:LockHighlight(); W.modeRandom:UnlockHighlight()
    W.hint:SetText("Pick the clip that plays every time.")
  else
    W.modeRandom:LockHighlight(); W.modeOne:UnlockHighlight()
    local n = 0
    for i = 1, #CLIPS do if d.pool[i] then n = n + 1 end end
    W.hint:SetText(n == 0 and (HEX.red .. "Tick at least one clip, or nothing plays.|r") or "Tick the clips to shuffle between.")
  end
  for i, r in ipairs(W.rows) do
    local on = d.mode == "one" and d.pick == i or (d.mode ~= "one" and d.pool[i])
    r.check:SetChecked(on and true or false)
    local c = on and C.text or C.muted
    r.name:SetTextColor(c[1], c[2], c[3])
    r.now:SetText(lastIdx == i and "last played" or "")
  end
  W.channel:SetText(d.channel)
  if W.vol:GetValue() ~= d.volume then W.vol:SetValue(d.volume) end
  W.volText:SetText(d.volume .. "%")
  W.quiet:SetText("Sometimes stay quiet: " .. (d.quiet and "On" or "Off"))
  if d.quiet then W.quiet:LockHighlight() else W.quiet:UnlockHighlight() end
  W.chance:SetShown(d.quiet); W.chanceText:SetShown(d.quiet)
  if W.chance:GetValue() ~= d.chance then W.chance:SetValue(d.chance) end
  W.chanceText:SetText(ns.ChanceText(d.chance))
  W.share:SetText("Share my clip: " .. (d.share and "On" or "Off"))
  if d.share then W.share:LockHighlight() else W.share:UnlockHighlight() end
  W.hear:SetText("Hear the group: " .. (d.hear and "On" or "Off"))
  if d.hear then W.hear:LockHighlight() else W.hear:UnlockHighlight() end
  if skipped then
    W.status:SetText("Last cast: " .. HEX.text .. "stayed quiet|r (Sometimes stay quiet is on)")
  elseif lastIdx then
    W.status:SetText("Last: " .. HEX.text .. CLIPS[lastIdx].name .. "|r" .. (lastFrom and (" from " .. HEX.gold .. lastFrom .. "|r") or ""))
  else
    W.status:SetText("Group members need Top Ramen ThunderCats to hear your clip.")
  end
end

-- "plays 1 in 3" style, from a percentage
function ns.ChanceText(c)
  local ratios = { [10] = "1 in 10", [20] = "1 in 5", [30] = "3 in 10", [40] = "2 in 5", [50] = "1 in 2",
    [60] = "3 in 5", [70] = "7 in 10", [80] = "4 in 5", [90] = "9 in 10" }
  return "Plays " .. (ratios[c] or (c .. "%"))
end

local function toggle()
  build()
  W.frame:SetShown(not W.frame:IsShown())
end
ns.ToggleWindow = toggle

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("CHAT_MSG_ADDON")
if ev.RegisterUnitEvent then
  ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
else
  ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
    if a1 == "player" then onCast(a3, event) end
  elseif event == "CHAT_MSG_ADDON" then
    if a1 == PREFIX then received(a2, a4) end
  elseif event == "PLAYER_LOGOUT" then
    restoreVolume()
  elseif event == "PLAYER_LOGIN" then
    restoreVolume() -- in case the game closed while a clip was playing quieter
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then pcall(reg, PREFIX) end
  end
end)

---------------------------------------------------------------------------
-- slash commands: /trtc (or /thundercats)
---------------------------------------------------------------------------
SLASH_TOPRAMENTHUNDERCATS1 = "/trtc"
SLASH_TOPRAMENTHUNDERCATS2 = "/thundercats"
SlashCmdList.TOPRAMENTHUNDERCATS = function(msg)
  local cmd = trim(msg):lower():match("^(%S*)")
  local d = db()
  if cmd == "" then toggle()
  elseif cmd == "test" then local i = choose(); if i then play(i, nil, "/trtc test", true) else say("no clips ticked in the pool.") end
  elseif cmd == "stop" then stop()
  elseif cmd == "volume" then
    local v = tonumber(trim(msg):match("%S+%s+(%d+)"))
    if v then d.volume = math.max(5, math.min(100, math.floor(v / 5 + 0.5) * 5)); volumeChanged(); refresh() end
    say("clip volume: " .. d.volume .. "% of your " .. d.channel .. " volume.")
  elseif cmd == "debug" then
    debugOn = not debugOn
    say("debug messages " .. (debugOn and "on: each clip start (and anything ignored) shows in chat." or "off."))
  elseif cmd == "quiet" then
    local arg = trim(msg):lower():match("%S+%s+(%S+)")
    local v = tonumber(arg or "")
    if v then d.quiet = true; d.chance = math.max(10, math.min(90, math.floor(v / 10 + 0.5) * 10))
    elseif arg == "off" then d.quiet = false
    elseif arg == "on" then d.quiet = true
    else d.quiet = not d.quiet end
    say("sometimes stay quiet: " .. (d.quiet and ("on, " .. ns.ChanceText(d.chance):lower() .. " casts") or "off") .. ".")
    refresh()
  elseif cmd == "on" or cmd == "off" then d.enabled = (cmd == "on"); say("clip on " .. d.spell .. ": " .. cmd .. "."); refresh()
  else
    say("/trtc opens the window. /trtc test plays a clip the way a cast would. /trtc stop. /trtc on, /trtc off. /trtc volume 5-100. /trtc quiet (on/off), or /trtc quiet 30 to play on 30% of casts. /trtc debug shows what starts each clip.")
  end
end
