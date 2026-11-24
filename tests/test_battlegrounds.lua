local clock, inside, kind, winner = 100, true, 'pvp', nil
local states = {{1, 1, 'Alliance flags: 0', 2, 'Horde flags: 0', 0, 0, 0}}
local frames = {}
function CreateFrame()
 local f = {events={}}
 function f:RegisterEvent(event) self.events[event] = true end
 function f:SetScript(_, fn) self.run = fn end
 frames[#frames+1] = f
 return f
end
function time() return clock end
function IsInInstance() return inside, kind end
function GetBattlefieldWinner() return winner end
function GetNumWorldStateUI() return #states end
local unpackValues = unpack or table.unpack
function GetWorldStateUIInfo(i) return unpackValues(states[i]) end
local messages = {}
DEFAULT_CHAT_FRAME = {AddMessage=function(_, s) messages[#messages+1] = s end}
local addon = {}
assert(loadfile('ScoutingStorage.lua'))('test', addon)
local function load(db)
 ChronicleCompanionForeverDB = db
 assert(loadfile('Battlegrounds.lua'))('test', addon)
 return addon.Battlegrounds
end
local function fire(event, text) frames[#frames].run(nil, event or 'PLAYER_ENTERING_WORLD', text) end
local db = {sidekick_enabled=false}
local c = load(db)
fire(); assert(db.collections == nil)
db.sidekick_enabled = 1; fire(); assert(db.collections == nil)
db.sidekick_enabled = true
inside, kind = false, 'none'; fire(); assert(db.collections == nil)
inside, kind = true, 'pvp'
local sibling = {opaque=true}
db.collections = {scouting=sibling, future=sibling}
fire()
local s = db.collections.battlegrounds
assert(s.Version == 1 and #s.Events == 2)
assert(s.Events[1].Kind == 'observed_enter' and s.Events[1].At == 100)
assert(s.Events[2].Rows[1][3] == 'Alliance flags: 0')
assert(db.collections.scouting == sibling and db.collections.future == sibling)
clock = 101; fire(); fire('ZONE_CHANGED_NEW_AREA'); fire('UPDATE_WORLD_STATES')
assert(#s.Events == 2 and db.collections.last_updated == 100)
for _, channel in ipairs({'ALLIANCE', 'HORDE', 'NEUTRAL'}) do fire('CHAT_MSG_BG_SYSTEM_'..channel, 'localized flag/base evidence') end
assert(#s.Events == 5 and s.Events[3].Source == 'CHAT_MSG_BG_SYSTEM_ALLIANCE')
assert(s.Events[3].Text == 'localized flag/base evidence' and s.Events[3].At == 101)
-- Identical chat messages are separate evidence: no reliable message identifier.
fire('CHAT_MSG_BG_SYSTEM_NEUTRAL', 'localized flag/base evidence'); assert(#s.Events == 6)
states[1][3] = 'Alliance flags: 1'; fire('UPDATE_WORLD_STATES')
assert(#s.Events == 7 and s.Events[2].Rows[1][3] == 'Alliance flags: 0')
fire('UPDATE_WORLD_STATES'); assert(#s.Events == 7)
winner = 0; fire('UPDATE_BATTLEFIELD_SCORE'); fire('UPDATE_BATTLEFIELD_SCORE')
assert(#s.Events == 8 and s.Events[8].Kind == 'completion_observed' and s.Events[8].Winner == 0)
inside, kind = false, 'none'; fire(); fire(); assert(#s.Events == 9 and s.Events[9].Kind == 'observed_leave')
inside, kind, winner = true, 'pvp', nil
clock = 102; fire(); assert(s.Events[10].Segment == 10)
-- Reload never merges a persisted unfinished segment or fabricates its ending.
c = load(db); clock = 103; fire()
assert(#s.Events == 13 and s.Events[12].Kind == 'observed_enter' and s.Events[12].Segment == 12)
db.sidekick_enabled = false; clock = 104; fire('CHAT_MSG_BG_SYSTEM_ALLIANCE', 'off')
assert(#s.Events == 13 and db.collections.last_updated == 103)
db.sidekick_enabled = true; fire(); assert(s.Events[14].Segment == 14)
-- Missing, throwing and secret APIs do not manufacture observations.
local oldInstance, oldCount, oldInfo = IsInInstance, GetNumWorldStateUI, GetWorldStateUIInfo
IsInInstance = nil; fire(); assert(#s.Events == 15)
IsInInstance = function() error('unsupported') end; fire(); assert(#s.Events == 15)
IsInInstance = oldInstance
GetNumWorldStateUI = nil; GetBattlefieldWinner = nil
fire(); assert(#s.Events == 15)
GetNumWorldStateUI = oldCount
GetWorldStateUIInfo = function() error('unsupported') end
fire(); assert(#s.Events == 15)
function issecretvalue(v) return v == 'secret' end
GetWorldStateUIInfo = function() return 1, 1, 'secret' end
fire('CHAT_MSG_BG_SYSTEM_ALLIANCE', 'secret'); assert(#s.Events == 15)
GetWorldStateUIInfo = oldInfo
fire('CHAT_MSG_BG_SYSTEM_NEUTRAL', string.rep('x', 4097)); assert(#s.Events == 15)
GetNumWorldStateUI = function() return 33 end; fire(); assert(#s.Events == 15)
GetNumWorldStateUI = oldCount
GetWorldStateUIInfo = function() return 1, 1, string.rep('x', 257) end
fire(); assert(#s.Events == 15)
GetWorldStateUIInfo = oldInfo
local savedTime = time
time = function() return 'secret' end; fire(); assert(#s.Events == 15)
time = savedTime
-- An unavailable snapshot is not evidence of zero objectives; a valid zero is.
states = {}; fire('UPDATE_WORLD_STATES'); assert(#s.Events == 16 and #s.Events[16].Rows == 0)
-- Preserve malformed/unknown stores and sibling data, without timestamp writes.
for _, bad in ipairs({false, 'bad', {Version=99, Events={}}, {Version=1, Events={false}}, {Version=1, Events={}, Future=true}, {Version=1, Events={[2]={}}}}) do
 local broken = {sidekick_enabled=true, collections={battlegrounds=bad, last_updated=7, scouting=sibling}}
 load(broken); fire()
 assert(broken.collections.battlegrounds == bad and broken.collections.last_updated == 7 and broken.collections.scouting == sibling)
end
local malformed = {sidekick_enabled=true, collections='opaque'}
load(malformed); fire(); assert(malformed.collections == 'opaque')
-- Count capacity freezes permanently, including across reload, never evicts.
local full = {sidekick_enabled=true}
c = load(full); fire()
local events = full.collections.battlegrounds.Events
for i = 1, 520 do fire('CHAT_MSG_BG_SYSTEM_NEUTRAL', 'event '..i) end
assert(#events == 512 and full.collections.battlegrounds.Stopped == 'capacity')
local first, last = events[1], events[512]
clock = 200; load(full); fire()
assert(#events == 512 and events[1] == first and events[512] == last and full.collections.last_updated == 104)
-- Weight capacity also stops without removing old events.
local heavy = {sidekick_enabled=true}
load(heavy); fire()
for i = 1, 100 do fire('CHAT_MSG_BG_SYSTEM_NEUTRAL', string.rep('x', 4096)) end
assert(heavy.collections.battlegrounds.Stopped == 'capacity' and #heavy.collections.battlegrounds.Events < 100)
local count = #heavy.collections.battlegrounds.Events
load(heavy); fire(); assert(#heavy.collections.battlegrounds.Events == count)
-- Sidekick offline clear permits fresh collection next load.
heavy.collections = {future=sibling}; load(heavy); fire()
assert(#heavy.collections.battlegrounds.Events == 2 and heavy.collections.future == sibling)
assert(frames[#frames].events.UPDATE_WORLD_STATES and frames[#frames].events.UPDATE_BATTLEFIELD_SCORE)
print('battleground collection tests passed')
