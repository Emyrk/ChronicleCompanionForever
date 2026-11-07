local logging, control = false, false
local button, icon
local messages = {}
Minimap = { width = 200, height = 200 }
function Minimap:GetWidth() return self.width end
function Minimap:GetHeight() return self.height end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(messages, message) end }
GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
function GameTooltip:AddLine(text) table.insert(self.lines, text) end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false; self.owner = nil end
function GameTooltip:IsOwned(owner) return self.owner == owner end
function LoggingCombat(...)
	assert(select("#", ...) == 0, "the minimap must never change recording state")
	return logging
end
function IsControlKeyDown() return control end
function CreateFrame()
	local frame = { events = {}, scripts = {}, shown = true }
	function frame:SetSize() end
	function frame:SetFrameStrata() end
	function frame:SetFrameLevel() end
	function frame:ClearAllPoints() self.point = nil end
	function frame:SetPoint(...) self.point = {...} end
	function frame:SetHighlightTexture() end
	function frame:RegisterForClicks(...) self.clicks = {...} end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:RegisterEvent(event) self.events[event] = true end
	function frame:UnregisterEvent(event) self.events[event] = nil end
	function frame:SetScript(name, fn) self.scripts[name] = fn end
	function frame:CreateTexture()
		local texture = {}
		function texture:SetSize() end
		function texture:SetPoint() end
		function texture:SetTexture(path) self.path = path end
		if not icon then icon = texture end
		return texture
	end
	button = frame
	return frame
end

local function loadAddon(saved)
	ChronicleCompanionForeverDB = saved
	icon = nil
	assert(loadfile("MinimapButton.lua"))("ChronicleCompanionForever", {})
	assert(not button.shown, "wait for saved variables before displaying")
	button.scripts.OnEvent(button, "ADDON_LOADED", "OtherAddon")
	assert(not button.shown)
	button.scripts.OnEvent(button, "ADDON_LOADED", "ChronicleCompanionForever")
	assert(not button.events.ADDON_LOADED)
end

loadAddon(nil)
assert(button.shown)
local function assertOutsideRim()
	local x, y = button.point[4], button.point[5]
	assert(x < 0 and y < 0, "icon should sit at the lower-left rim")
	assert((x / (Minimap.width / 2))^2 + (y / (Minimap.height / 2))^2 > 1,
		"icon center must be outside the minimap")
end
assertOutsideRim()
Minimap.width, Minimap.height = 300, 240
button.scripts.OnUpdate(button, 0.5)
assertOutsideRim()
assert(math.abs(button.point[4] + 166 * math.sqrt(0.5)) < 0.001)
assert(math.abs(button.point[5] + 136 * math.sqrt(0.5)) < 0.001)
assert(ChronicleCompanionForeverDB.minimapHidden == false)
assert(icon.path == "Interface\\AddOns\\ChronicleCompanionForever\\textures\\Off")
logging = true
button.scripts.OnUpdate(button, 0.5)
assert(icon.path:match("On$"), "actual recording should turn the icon green")
button.scripts.OnEnter(button)
assert(GameTooltip.lines[2]:find("Recording"))
logging = false
button.scripts.OnUpdate(button, 0.5)
assert(icon.path:match("Off$"))
assert(GameTooltip.lines[2]:find("Not recording"), "hovered tooltip should refresh")
button.scripts.OnClick(button)
assert(button.shown, "plain clicks should not hide or toggle recording")
control = true
button.scripts.OnClick(button)
assert(not button.shown and ChronicleCompanionForeverDB.minimapHidden)
assert(not GameTooltip.shown)
assert(messages[#messages]:find("/clog minimap"))
logging = true
SlashCmdList.CHRONICLEFOREVER(" MINIMAP ")
assert(button.shown and not ChronicleCompanionForeverDB.minimapHidden)
assert(icon.path:match("On$"), "restoring should refresh immediately")
SlashCmdList.CHRONICLEFOREVER("minimap")
assert(not button.shown and ChronicleCompanionForeverDB.minimapHidden)
local saved = ChronicleCompanionForeverDB
loadAddon(saved)
assert(not button.shown, "hidden preference should survive reload")
assert(ChronicleCompanionForeverDB == saved)
SlashCmdList.CHRONICLEFOREVER("help")
assert(not button.shown, "help should not toggle visibility")
loadAddon("invalid saved data")
assert(button.shown)
assert(SLASH_CHRONICLEFOREVER1 == "/clog")
assert(SLASH_CHRONICLEFOREVER2 == "/chronicle")
print("minimap behavior tests passed")
