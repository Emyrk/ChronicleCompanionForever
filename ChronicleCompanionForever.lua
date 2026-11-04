local _, addon = ...

local ADVANCED_COMBAT_LOGGING_CVAR = "advancedCombatLogging"
local RETRY_DELAYS = { 3, 6, 10, 15, 20, 30 }

local frame = CreateFrame("Frame")
local transitionToken = 0

local function shouldLogCombat()
	local inInstance, instanceType = IsInInstance()

	-- Battlegrounds report "pvp". Other instanced content, including arenas,
	-- dungeons, raids, and scenarios, should be logged.
	return inInstance and instanceType ~= "pvp"
end

local function enableAdvancedCombatLogging()
	if GetCVar(ADVANCED_COMBAT_LOGGING_CVAR) ~= "1" then
		pcall(SetCVar, ADVANCED_COMBAT_LOGGING_CVAR, 1)
	end
end

local function setCombatLogging(enabled)
	pcall(LoggingCombat, enabled)
end

local function applyCurrentState(token)
	if token ~= transitionToken then
		return
	end

	local enabled = shouldLogCombat()

	if enabled then
		enableAdvancedCombatLogging()
	end

	setCombatLogging(enabled)
end

local function reconcileCombatLogging()
	transitionToken = transitionToken + 1
	local token = transitionToken

	applyCurrentState(token)

	-- WoW Forever can ignore logging changes briefly after a loading screen.
	-- Repeating the explicit desired state is safe and never toggles it backward.
	for _, delay in ipairs(RETRY_DELAYS) do
		C_Timer.After(delay, function()
			applyCurrentState(token)
		end)
	end
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:SetScript("OnEvent", reconcileCombatLogging)

addon.ShouldLogCombat = shouldLogCombat
