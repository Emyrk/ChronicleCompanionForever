local PREFIX = "|cff4ec3ff[ChronProbe]|r "
local MARKER = "CHRON_PROBE_A"
local MIN_PAYLOAD_LENGTH = 32
local MAX_PAYLOAD_LENGTH = 4096

local original
local armed = false
local expectedPayload
local expectedSuffix
local sequenceCurrent
local sequenceTotal
local sequenceAdvancePending = false
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
	expectedPayload = nil
	expectedSuffix = nil
	sequenceCurrent = nil
	sequenceTotal = nil
	sequenceAdvancePending = false
end

local function armPayload(payload, label, suffix)
	if type(_G.SPELL_FAILED_MOVING) ~= "string" then
		message("SPELL_FAILED_MOVING is missing or is not a string.")
		return
	end

	if original == nil then
		original = _G.SPELL_FAILED_MOVING
	end

	_G.SPELL_FAILED_MOVING = payload
	armed = true
	expectedPayload = payload
	expectedSuffix = suffix

	message("Armed with " .. label .. ".")
	message("Now cast a cast-time spell while moving, then run /cfprobe restore.")
end

local function arm()
	armPayload(MARKER, MARKER, MARKER)
end

local function armLength(length)
	if not length or length ~= math.floor(length)
			or length < MIN_PAYLOAD_LENGTH or length > MAX_PAYLOAD_LENGTH then
		message("Length must be a whole number from "
			.. MIN_PAYLOAD_LENGTH .. " to " .. MAX_PAYLOAD_LENGTH .. ".")
		return
	end

	local lengthLabel = string.format("%04d", length)
	local payloadPrefix = "CHRON_LEN_" .. lengthLabel .. "|"
	local payloadSuffix = "|END_" .. lengthLabel
	local bodyLength = length - #payloadPrefix - #payloadSuffix
	local payload = payloadPrefix .. string.rep("A", bodyLength) .. payloadSuffix

	armPayload(payload, "length " .. length, payloadSuffix)
end

local function sequencePayload(index, total)
	return string.format("CHRON_SEQ_%03d_OF_%03d", index, total)
end

local function setSequencePayload(index)
	local payload = sequencePayload(index, sequenceTotal)
	_G.SPELL_FAILED_MOVING = payload
	expectedPayload = payload
	expectedSuffix = payload
	sequenceCurrent = index
	sequenceAdvancePending = false
	message("Sequence armed: " .. payload .. ".")
end

local function armSequence(total)
	if not total or total ~= math.floor(total) or total < 1 or total > 100 then
		message("Sequence count must be a whole number from 1 to 100.")
		return
	end

	if type(_G.SPELL_FAILED_MOVING) ~= "string" then
		message("SPELL_FAILED_MOVING is missing or is not a string.")
		return
	end

	if original == nil then
		original = _G.SPELL_FAILED_MOVING
	end

	armed = true
	sequenceTotal = total
	setSequencePayload(1)
	message("Trigger one moving cast failure per marker. Advancement waits one second.")
end

local function advanceSequence()
	if not armed or not sequenceCurrent then
		message("No sequence is armed.")
		return
	end

	if sequenceCurrent >= sequenceTotal then
		message("Sequence complete after " .. sequenceTotal .. " UI attempts.")
		restore()
		return
	end

	setSequencePayload(sequenceCurrent + 1)
end

local function reportUIError(errorType, errorText)
	if not armed or type(errorText) ~= "string" then
		return
	end

	local exact = errorText == expectedPayload
	local hasEnd = expectedSuffix ~= nil
		and errorText:sub(-#expectedSuffix) == expectedSuffix

	message("UI_ERROR_MESSAGE type=" .. tostring(errorType)
		.. " length=" .. #errorText
		.. " expected=" .. #expectedPayload
		.. " exact=" .. tostring(exact)
		.. " end=" .. tostring(hasEnd))

	if sequenceCurrent and exact and not sequenceAdvancePending then
		sequenceAdvancePending = true
		local observedIndex = sequenceCurrent
		message("UI sequence " .. observedIndex .. " observed; waiting one second.")

		if C_Timer and C_Timer.After then
			C_Timer.After(1, function()
				if armed and sequenceCurrent == observedIndex then
					advanceSequence()
				end
			end)
		else
			message("Timer unavailable. Run /cfprobe next.")
		end
	end
end

local function packEventArgs(...)
	return { n = select("#", ...), ... }
end

local function reportCombatLogEvent(...)
	local eventArgs = packEventArgs(...)

	if eventArgs.n == 0 and type(CombatLogGetCurrentEventInfo) == "function" then
		eventArgs = packEventArgs(CombatLogGetCurrentEventInfo())
	end

	local subevent = eventArgs[2]
	if subevent ~= "SPELL_CAST_FAILED" then
		return
	end

	for index = 1, eventArgs.n do
		local value = eventArgs[index]
		if type(value) == "string" and value:find("^CHRON_") then
			message("CLEU observed " .. value .. ".")
			return
		end
	end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		original = _G.SPELL_FAILED_MOVING

		if type(original) == "string" then
			message("Ready. Run /cfprobe arm or /cfprobe length 512.")
		else
			message("SPELL_FAILED_MOVING is unavailable.")
		end
	elseif event == "PLAYER_LOGOUT" then
		restore()
	elseif event == "UI_ERROR_MESSAGE" then
		reportUIError(...)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		reportCombatLogEvent(...)
	end
end)

SLASH_CHRONFOREVERPROBE1 = "/cfprobe"

SlashCmdList.CHRONFOREVERPROBE = function(command)
	command = (command or ""):lower():match("^%s*(.-)%s*$")
	local length = command:match("^length%s+(%d+)$")
	local sequence = command:match("^sequence%s+(%d+)$")

	if command == "arm" then
		arm()
	elseif length then
		armLength(tonumber(length))
	elseif sequence then
		armSequence(tonumber(sequence))
	elseif command == "next" then
		advanceSequence()
	elseif command == "restore" then
		restore()
	elseif command == "status" then
		if sequenceCurrent then
			message("armed=true sequence=" .. sequenceCurrent .. "/" .. sequenceTotal
				.. " marker=" .. expectedPayload
				.. " pending=" .. tostring(sequenceAdvancePending))
		elseif armed then
			message("armed=true length=" .. #expectedPayload
				.. " end=" .. tostring(expectedSuffix))
		else
			message("armed=false value=" .. tostring(_G.SPELL_FAILED_MOVING))
		end
	else
		message("/cfprobe arm")
		message("/cfprobe length <32-4096>")
		message("/cfprobe sequence <1-100>")
		message("/cfprobe next")
		message("/cfprobe restore")
		message("/cfprobe status")
	end
end
