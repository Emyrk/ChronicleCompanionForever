local addon, frames, messages = {}, {}, {}
local forwarded = 0
SlashCmdList = {CHRONICLEFOREVER=function() forwarded = forwarded + 1 end}
DEFAULT_CHAT_FRAME = {AddMessage=function(_, text) messages[#messages+1] = text end}
function CreateFrame()
 local f = {}
 function f:RegisterEvent(event) if event == 'RAID_BOSS_WHISPER' then error('not supported') end end
 function f:SetScript(_, fn) self.run = fn end
 frames[#frames+1] = f
 return f
end
local inside, kind = false, 'none'
function IsInInstance() return inside, kind end
function time() return 123 end
function GetTime() return 4.5 end
function GetBuildInfo() return 'Forever', '12345', nil, 16001 end
function GetLocale() return 'enUS' end
function UnitGUID(unit) return unit == 'player' and 'Player-1' or 'Creature-0-1-2-3-4' end
function UnitName() return 'Tester', 'Realm' end
function GetInstanceInfo() return 'Warsong', 'pvp', 0, nil, 10, false, nil, 489 end
function GetBattlefieldStatus(i) return 'active', 'Warsong', 13, nil, i end
function GetNumWorldStateUI() return 1 end
function GetWorldStateUIInfo() return 1, nil, false, 'raw' end
function GetBattlefieldWinner() return nil end
assert(loadfile('ScoutingStorage.lua'))('test', addon)
assert(loadfile('BattlegroundDiagnostics.lua'))('test', addon)
assert(loadfile('Battlegrounds.lua'))('test', addon)
local d = addon.BattlegroundDiagnostics
local function fire(e, ...) frames[1].run(nil, e or 'PLAYER_ENTERING_WORLD', ...) end
-- Safe pre-init routing and no disabled mutations, including literal truthy values.
SlashCmdList.CHRONICLEFOREVER('bgstatus')
SlashCmdList.CHRONICLEFOREVER('on'); assert(forwarded == 1)
for _, enabled in ipairs({false, 1, 'true'}) do
 ChronicleCompanionForeverDB = {sidekick_enabled=enabled}
 fire(); SlashCmdList.CHRONICLEFOREVER(' BGSTATUS ')
 assert(ChronicleCompanionForeverDB.collections == nil)
end
local sibling = {opaque='preserve'}
local db = {sidekick_enabled=true, collections={scouting=sibling, future=sibling}}
ChronicleCompanionForeverDB = db
fire()
local s = db.collections.battlegroundDiagnostics
assert(#s.Events == 1 and db.collections.battlegrounds == nil)
assert(s.Events[1].Metadata[1].Returns.n == 4)
local failed
for _, r in ipairs(s.Events[1].Registration) do if r.Event == 'RAID_BOSS_WHISPER' then failed = not r.OK end end
assert(failed)
fire('CHAT_MSG_SYSTEM', 'outside'); assert(#s.Events == 1)
inside, kind = true, 'arena'; fire('CHAT_MSG_MONSTER_YELL', 'arena'); assert(#s.Events == 1)
inside, kind = true, 'pvp'
fire('CHAT_MSG_MONSTER_YELL', 'hello', nil, false, 7, {})
local e = s.Events[2]
assert(e.Args.n == 5 and e.Args.Values[2].Type == 'nil' and e.Args.Values[3].Value == false)
assert(e.Args.Values[5].Type == 'unsupported' and s.Counts.Skipped == 1)
assert(e.Observations[1].Returns.Values[8].Value == 489)
assert(e.Queues[1].Returns.n == 5 and e.Queues[1].Returns.Values[3].Value == 13)
assert(e.QueueFallback and #e.Queues == 3)
assert(e.Monotonic.Returns.Values[1].Value == 4.5 and e.WallTime.Returns.Values[1].Value == 123)
assert(e.Observations[3].Status == 'missing')
assert(db.collections.scouting == sibling and db.collections.future == sibling)
function issecretvalue(v) return v == 'secret' end
GetInstanceInfo = function() error('protected') end
fire('CHAT_MSG_SYSTEM', 'secret', string.rep('x', 9000))
e = s.Events[3]
assert(e.Args.Values[1].Type == 'secret' and #e.Args.Values[2].Value == 8192)
assert(e.Args.Values[2].Bytes == 9000 and s.Counts.Truncated == 1)
assert(e.Observations[1].Status == 'error' and s.Counts.APIErrors == 1)
GetNumWorldStateUI = function() return 'secret' end
fire('UPDATE_WORLD_STATES'); assert(s.Events[4].WorldCount.Returns.Values[1].Type == 'secret')
IsInInstance = nil; fire(); assert(s.Events[5].Presence.Status == 'missing')
IsInInstance = function() error('protected') end; fire(); assert(s.Events[6].Presence.Status == 'error')
issecretvalue = function() error('guard failure') end
fire(); assert(s.Events[7].Presence.Error.Values[1].Type == 'secret')
issecretvalue = nil
-- Disabled collection is immutable even after active recording.
local count, bytes = #s.Events, s.Bytes
db.sidekick_enabled = false; fire(); assert(#s.Events == count and s.Bytes == bytes)
db.sidekick_enabled = true
SlashCmdList.CHRONICLEFOREVER('bgstatus')
assert(table.concat(messages, '\n'):find('API observed failure: GetInstanceInfo', 1, true))
-- Capacity never evicts, counters persist and both budgets are exercised cheaply.
d:Open(db)
local first = s.Events[1]
for i = #s.Events + 1, 20000 do d:Append({Source='test'}) end
d:Append({Source='overflow'})
assert(#s.Events == 20000 and s.Counts.Dropped == 1 and s.Events[1] == first)
local heavy = {sidekick_enabled=true}
d:Open(heavy)
for i = 1, 2100 do d:Append({Source=string.rep('x', 8192)}) end
assert(d.store.Counts.Dropped > 0 and #d.store.Events < 2100)
-- Malformed/unknown diagnostic data preserved, including unknown top-level fields.
for _, bad in ipairs({false, {Version=99}, {Version=1, Events={}, Counts={}, Bytes=0, Future=true}}) do
 local broken = {sidekick_enabled=true, collections={battlegroundDiagnostics=bad, scouting=sibling}}
 assert(d:Open(broken) == nil and broken.collections.battlegroundDiagnostics == bad)
 assert(broken.collections.scouting == sibling)
end
-- Reopening recalculates weight and retains capped pending evidence.
d.db = nil
assert(d:Open(heavy) and #d.store.Events < 2100)
local held = #d.store.Events
d:Append({Source=string.rep('x', 8192)}); assert(#d.store.Events == held)
local fresh = {sidekick_enabled=true}
d:Open(fresh)
local args = {}; for i=1,70 do args[i]=i end
local raw = d:Raw((unpack or table.unpack)(args))
assert(raw.n == 70 and raw.Omitted == 6 and #raw.Values == 64 and d.store.Counts.Truncated == 1)
local bad = {Version=1, Events={{Source='future', Unknown=true}}, Counts={}, Bytes=0}
assert(d:Open({sidekick_enabled=true, collections={battlegroundDiagnostics=bad}}) == nil)
-- A future legacy schema blocks both writes, rather than changing any sibling.
local future = {sidekick_enabled=true, collections={battlegrounds={Version=99}, last_updated=7}}
ChronicleCompanionForeverDB = future
fire(); assert(future.collections.battlegroundDiagnostics == nil and future.collections.last_updated == 7)
for _, registration in ipairs(d.registrations) do
 assert(not registration.Event:match('^CHAT_MSG_PARTY') and registration.Event ~= 'CHAT_MSG_SAY')
end
-- Disable/re-enable must invalidate the cached handle, including direct Observe.
local resumed = {sidekick_enabled=true}
ChronicleCompanionForeverDB = resumed
IsInInstance = function() return true, 'pvp' end
GetNumWorldStateUI = function() return 0 end
d:Observe('PLAYER_ENTERING_WORLD')
local pending = resumed.collections.battlegroundDiagnostics
local before = #pending.Events
resumed.sidekick_enabled = false
d:Observe('PLAYER_ENTERING_WORLD'); assert(d.store == nil)
resumed.sidekick_enabled = true
d:Observe('PLAYER_ENTERING_WORLD'); assert(#pending.Events == before + 1)
resumed.sidekick_enabled = false; assert(d:Open(resumed) == nil)
resumed.sidekick_enabled = true; assert(d:Open(resumed) == pending)
-- Outside-BG rejected announcements still mark changed support counters.
resumed.collections.last_updated = 1
IsInInstance = nil
d:Observe('CHAT_MSG_SYSTEM', 'not retained')
assert(resumed.collections.last_updated == 123 and #pending.Events == before + 1)
resumed.collections.last_updated = 1
IsInInstance = function() error('blocked') end
d:Observe('CHAT_MSG_SYSTEM', 'not retained')
assert(resumed.collections.last_updated == 123 and #pending.Events == before + 1)
-- Correcting persisted weight marks the mutation; no-op reopening does not.
pending.Bytes = 0; resumed.collections.last_updated = 1; d.db = nil
d:Open(resumed); assert(pending.Bytes > 0 and resumed.collections.last_updated == 123)
resumed.collections.last_updated = 1; d.db = nil
d:Open(resumed); assert(resumed.collections.last_updated == 1)
-- Counters are known, finite bounded integers; invalid stores stay untouched.
for _, counts in ipairs({{Skipped=-1}, {Skipped=0.5}, {Skipped=math.huge},
 {Skipped=9007199254740992}, {Skipped=0/0}, {Future=1}}) do
 local badCounts = {Version=1, Events={}, Counts=counts, Bytes=0}
 local malformed = {sidekick_enabled=true, collections={battlegroundDiagnostics=badCounts, last_updated=1}}
 assert(d:Open(malformed) == nil and malformed.collections.last_updated == 1)
 assert(malformed.collections.battlegroundDiagnostics == badCounts)
end
d:Open(resumed); pending.Counts.Dropped = 9007199254740991
resumed.collections.last_updated = 1; d:Count('Dropped')
assert(pending.Counts.Dropped == 9007199254740991 and resumed.collections.last_updated == 1)
print('battleground diagnostic tests passed')
