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
assert(frame.events.UI_ERROR_MESSAGE)
assert(SLASH_CHRONFOREVERPROBE1 == "/cfprobe")
assert(type(SlashCmdList.CHRONFOREVERPROBE) == "function")

frame.OnEvent(frame, "PLAYER_LOGIN")
assert(lastMessage():find("Ready", 1, true))

SlashCmdList.CHRONFOREVERPROBE(" arm ")
assert(SPELL_FAILED_MOVING == "CHRON_PROBE_A")
assert(messages[#messages - 1]:find("Armed with CHRON_PROBE_A", 1, true))

SlashCmdList.CHRONFOREVERPROBE("status")
assert(lastMessage():find("armed=true", 1, true))
assert(lastMessage():find("length=13", 1, true))

frame.OnEvent(frame, "UI_ERROR_MESSAGE", 57, SPELL_FAILED_MOVING)
assert(lastMessage():find("type=57", 1, true))
assert(lastMessage():find("length=13", 1, true))
assert(lastMessage():find("exact=true", 1, true))
assert(lastMessage():find("end=true", 1, true))

SlashCmdList.CHRONFOREVERPROBE("restore")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")
assert(lastMessage():find("Restored", 1, true))

SlashCmdList.CHRONFOREVERPROBE("length 512")
assert(#SPELL_FAILED_MOVING == 512)
assert(SPELL_FAILED_MOVING:sub(1, 15) == "CHRON_LEN_0512|")
assert(SPELL_FAILED_MOVING:sub(-9) == "|END_0512")

frame.OnEvent(frame, "UI_ERROR_MESSAGE", 57, SPELL_FAILED_MOVING)
assert(lastMessage():find("length=512", 1, true))
assert(lastMessage():find("expected=512", 1, true))
assert(lastMessage():find("exact=true", 1, true))
assert(lastMessage():find("end=true", 1, true))

frame.OnEvent(frame, "UI_ERROR_MESSAGE", 57, SPELL_FAILED_MOVING:sub(1, 128))
assert(lastMessage():find("length=128", 1, true))
assert(lastMessage():find("expected=512", 1, true))
assert(lastMessage():find("exact=false", 1, true))
assert(lastMessage():find("end=false", 1, true))

SlashCmdList.CHRONFOREVERPROBE("restore")
SlashCmdList.CHRONFOREVERPROBE("length 31")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")
assert(lastMessage():find("32 to 4096", 1, true))

SlashCmdList.CHRONFOREVERPROBE("length 4097")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")
assert(lastMessage():find("32 to 4096", 1, true))

SlashCmdList.CHRONFOREVERPROBE("ARM")
assert(SPELL_FAILED_MOVING == "CHRON_PROBE_A")
frame.OnEvent(frame, "PLAYER_LOGOUT")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")

SPELL_FAILED_MOVING = nil
SlashCmdList.CHRONFOREVERPROBE("arm")
assert(SPELL_FAILED_MOVING == nil)
assert(lastMessage():find("missing or is not a string", 1, true))

SlashCmdList.CHRONFOREVERPROBE("")
assert(messages[#messages - 2]:find("/cfprobe length", 1, true))
assert(lastMessage():find("/cfprobe status", 1, true))

print("probe behavior tests passed")
