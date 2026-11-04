local state = {
	inInstance = false,
	instanceType = "none",
	logging = false,
	advanced = "0",
	loggingCalls = {},
	cvarCalls = {},
	timers = {},
}

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

function IsInInstance()
	return state.inInstance, state.instanceType
end

function GetCVar()
	return state.advanced
end

function SetCVar(name, value)
	state.advanced = tostring(value)
	table.insert(state.cvarCalls, { name, value })
end

function LoggingCombat(enabled)
	state.logging = enabled
	table.insert(state.loggingCalls, enabled)
	return enabled
end

C_Timer = {}

function C_Timer.After(delay, callback)
	table.insert(state.timers, { delay = delay, callback = callback })
end

local addon = {}
assert(loadfile("ChronicleCompanionForever.lua"))("ChronicleCompanionForever", addon)

local function fireEvent()
	frame.OnEvent(frame, "PLAYER_ENTERING_WORLD")
end

local function resetCalls()
	state.loggingCalls = {}
	state.cvarCalls = {}
	state.timers = {}
end

assert(frame.events.PLAYER_ENTERING_WORLD)
assert(frame.events.ZONE_CHANGED_NEW_AREA)

state.inInstance = true
state.instanceType = "party"
fireEvent()
assert(state.logging == true)
assert(state.advanced == "1")
assert(#state.loggingCalls == 1 and state.loggingCalls[1] == true)
assert(#state.timers == 6, "each transition should schedule six retries")

resetCalls()
state.inInstance = true
state.instanceType = "pvp"
fireEvent()
assert(state.logging == false, "battlegrounds should not be logged")
assert(state.advanced == "1", "advanced logging may remain enabled")
assert(#state.loggingCalls == 1 and state.loggingCalls[1] == false)

resetCalls()
state.inInstance = true
state.instanceType = "arena"
fireEvent()
assert(state.logging == true, "arenas are non-battleground instances")

resetCalls()
state.inInstance = false
state.instanceType = "none"
fireEvent()
assert(state.logging == false, "leaving an instance should stop logging")

state.inInstance = true
state.instanceType = "raid"
assert(addon.ShouldLogCombat() == true)
state.instanceType = "pvp"
assert(addon.ShouldLogCombat() == false)

resetCalls()
state.inInstance = true
state.instanceType = "party"
fireEvent()
local staleRetry = state.timers[1].callback

state.inInstance = false
state.instanceType = "none"
fireEvent()
local callsAfterLeaving = #state.loggingCalls
staleRetry()
assert(#state.loggingCalls == callsAfterLeaving, "retries from an old zone must be ignored")

state.timers[7].callback()
assert(state.logging == false, "current retries should preserve the stopped state")

print("addon behavior tests passed")
