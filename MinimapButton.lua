local ADDON_NAME = ...
local ICON_PATH = "Interface\\AddOns\\ChronicleCompanionForever\\textures\\"
local button = CreateFrame("Button", "ChronicleForeverMinimapButton", Minimap)
button:SetSize(33, 33)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:RegisterForClicks("LeftButtonUp")
button:Hide()

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", button, "CENTER", 0, 0)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("CENTER", button, "CENTER", 11, -12)

local function refreshIcon()
	-- Derive the lower-left rim position from the minimap's current size.
	-- Keep the button center outside the rim rather than inside larger minimaps.
	local diagonal = math.sqrt(0.5)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER",
		-(Minimap:GetWidth() / 2 + 16) * diagonal,
		-(Minimap:GetHeight() / 2 + 16) * diagonal)
	-- Query the actual state, not the desired state: zone changes may need retries.
	icon:SetTexture(ICON_PATH .. (LoggingCombat() and "On" or "Off"))
end

local function showTooltip()
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:AddLine("Chronicle Companion Forever", 0.31, 0.76, 1)
	GameTooltip:AddLine(LoggingCombat() and "|cff44ff44Recording|r" or "|cffff4444Not recording|r")
	GameTooltip:AddLine("Recording is managed automatically in instances.", 1, 1, 1)
	GameTooltip:AddLine("Ctrl-click: hide icon", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("/clog minimap: show or hide icon", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local elapsed = 0
button:SetScript("OnUpdate", function(self, dt)
	elapsed = elapsed + dt
	if elapsed < 0.5 then return end
	elapsed = 0
	refreshIcon()
	if GameTooltip:IsOwned(self) then showTooltip() end
end)
button:SetScript("OnEnter", showTooltip)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function setHidden(hidden)
	ChronicleCompanionForeverDB.minimapHidden = hidden
	if hidden then
		button:Hide()
		if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
	else
		refreshIcon()
		button:Show()
	end
end

button:SetScript("OnClick", function()
	if IsControlKeyDown() then
		setHidden(true)
		DEFAULT_CHAT_FRAME:AddMessage("Chronicle: minimap icon hidden. Use /clog minimap to show it again.")
	end
end)

-- Saved variables are available at ADDON_LOADED; never overwrite a saved preference.
button:RegisterEvent("ADDON_LOADED")
button:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON_NAME then return end
	if type(ChronicleCompanionForeverDB) ~= "table" then
		ChronicleCompanionForeverDB = {}
	end
	setHidden(ChronicleCompanionForeverDB.minimapHidden == true)
	self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_CHRONICLEFOREVER1 = "/clog"
SLASH_CHRONICLEFOREVER2 = "/chronicle"
SlashCmdList.CHRONICLEFOREVER = function(message)
	if message:lower():match("^%s*minimap%s*$") then
		setHidden(not ChronicleCompanionForeverDB.minimapHidden)
	else
		DEFAULT_CHAT_FRAME:AddMessage("Chronicle: /clog minimap toggles the minimap icon. Ctrl-click the icon to hide it.")
	end
end
