local messages = {}
local frame = { events = {} }

function frame:RegisterEvent(event)
	self.events[event] = true
end

function frame:SetScript(script, callback)
	self[script] = callback
end

function CreateFrame()
	return frame
end

DEFAULT_CHAT_FRAME = {}

function DEFAULT_CHAT_FRAME:AddMessage(text)
	table.insert(messages, text)
end

SlashCmdList = {}
SPELL_FAILED_MOVING = "Can't do that while moving"

assert(loadfile("ChronForeverProbe/ChronForeverProbe.lua"))()

local function lastMessage()
	return messages[#messages]
end

assert(frame.events.PLAYER_LOGIN)
assert(frame.events.PLAYER_LOGOUT)
assert(SLASH_CHRONFOREVERPROBE1 == "/cfprobe")
assert(type(SlashCmdList.CHRONFOREVERPROBE) == "function")

frame.OnEvent(frame, "PLAYER_LOGIN")
assert(lastMessage():find("Ready", 1, true))

SlashCmdList.CHRONFOREVERPROBE(" arm ")
assert(SPELL_FAILED_MOVING == "CHRON_PROBE_A")
assert(messages[#messages - 1]:find("Armed with CHRON_PROBE_A", 1, true))

SlashCmdList.CHRONFOREVERPROBE("status")
assert(lastMessage():find("armed=true", 1, true))
assert(lastMessage():find("value=CHRON_PROBE_A", 1, true))

SlashCmdList.CHRONFOREVERPROBE("restore")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")
assert(lastMessage():find("Restored", 1, true))

SlashCmdList.CHRONFOREVERPROBE("ARM")
assert(SPELL_FAILED_MOVING == "CHRON_PROBE_A")
frame.OnEvent(frame, "PLAYER_LOGOUT")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")

SPELL_FAILED_MOVING = nil
SlashCmdList.CHRONFOREVERPROBE("arm")
assert(SPELL_FAILED_MOVING == nil)
assert(lastMessage():find("missing or is not a string", 1, true))

SlashCmdList.CHRONFOREVERPROBE("")
assert(lastMessage():find("/cfprobe status", 1, true))

print("probe behavior tests passed")
