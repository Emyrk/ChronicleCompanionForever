local PREFIX = "|cff4ec3ff[ChronProbe]|r "
local MARKER = "CHRON_PROBE_A"

local original
local armed = false
local frame = CreateFrame("Frame")

local function message(text)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
	end
end

local function restore()
	if original ~= nil then
		_G.SPELL_FAILED_MOVING = original
	end

	if armed then
		message("Restored SPELL_FAILED_MOVING.")
	end

	armed = false
end

local function arm()
	if type(_G.SPELL_FAILED_MOVING) ~= "string" then
		message("SPELL_FAILED_MOVING is missing or is not a string.")
		return
	end

	if original == nil then
		original = _G.SPELL_FAILED_MOVING
	end

	_G.SPELL_FAILED_MOVING = MARKER
	armed = true

	message("Armed with " .. MARKER .. ".")
	message("Now cast a cast-time spell while moving, then run /cfprobe restore.")
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		original = _G.SPELL_FAILED_MOVING

		if type(original) == "string" then
			message("Ready. Run /cfprobe arm.")
		else
			message("SPELL_FAILED_MOVING is unavailable.")
		end
	elseif event == "PLAYER_LOGOUT" then
		restore()
	end
end)

SLASH_CHRONFOREVERPROBE1 = "/cfprobe"

SlashCmdList.CHRONFOREVERPROBE = function(command)
	command = (command or ""):lower():match("^%s*(.-)%s*$")

	if command == "arm" then
		arm()
	elseif command == "restore" then
		restore()
	elseif command == "status" then
		message("armed=" .. tostring(armed)
			.. " value=" .. tostring(_G.SPELL_FAILED_MOVING))
	else
		message("/cfprobe arm")
		message("/cfprobe restore")
		message("/cfprobe status")
	end
end
