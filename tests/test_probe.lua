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

local timers = {}
C_Timer = {}

function C_Timer.After(delay, callback)
	table.insert(timers, { delay = delay, callback = callback })
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
assert(not frame.events.COMBAT_LOG_EVENT_UNFILTERED)
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

SlashCmdList.CHRONFOREVERPROBE("sequence 3")
assert(SPELL_FAILED_MOVING == "CHRON_SEQ_001_OF_003")
assert(lastMessage():find("Trigger one moving cast failure", 1, true))

SlashCmdList.CHRONFOREVERPROBE("status")
assert(lastMessage():find("sequence=1/3", 1, true))
assert(lastMessage():find("pending=false", 1, true))

frame.OnEvent(frame, "UI_ERROR_MESSAGE", 57, SPELL_FAILED_MOVING)
assert(#timers == 1)
assert(timers[1].delay == 1)
assert(lastMessage():find("waiting one second", 1, true))
frame.OnEvent(frame, "UI_ERROR_MESSAGE", 57, SPELL_FAILED_MOVING)
assert(#timers == 1, "duplicate UI events must not schedule duplicate advancement")

timers[1].callback()
assert(SPELL_FAILED_MOVING == "CHRON_SEQ_002_OF_003")

SlashCmdList.CHRONFOREVERPROBE("next")
assert(SPELL_FAILED_MOVING == "CHRON_SEQ_003_OF_003")

frame.OnEvent(frame, "UI_ERROR_MESSAGE", 57, SPELL_FAILED_MOVING)
assert(#timers == 2)
timers[2].callback()
assert(SPELL_FAILED_MOVING == "Can't do that while moving")
assert(lastMessage():find("Restored", 1, true))

SlashCmdList.CHRONFOREVERPROBE("sequence 101")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")
assert(lastMessage():find("1 to 100", 1, true))

SlashCmdList.CHRONFOREVERPROBE("ARM")
assert(SPELL_FAILED_MOVING == "CHRON_PROBE_A")
frame.OnEvent(frame, "PLAYER_LOGOUT")
assert(SPELL_FAILED_MOVING == "Can't do that while moving")

SPELL_FAILED_MOVING = nil
SlashCmdList.CHRONFOREVERPROBE("arm")
assert(SPELL_FAILED_MOVING == nil)
assert(lastMessage():find("missing or is not a string", 1, true))

SlashCmdList.CHRONFOREVERPROBE("")
assert(messages[#messages - 4]:find("/cfprobe length", 1, true))
assert(messages[#messages - 3]:find("/cfprobe sequence", 1, true))
assert(lastMessage():find("/cfprobe status", 1, true))

print("probe behavior tests passed")
