local addon, frames, timers, messages = {}, {}, {}, {}
local clock, inside, kind, winner = 0, true, 'pvp', nil
local secretValue = {}
local rows = {{guid='guid-a', name='Alpha', damageDone=10, healingDone=0, deaths=0,
 stats={{pvpStatID=1, pvpStatValue=2, name='Objective', tooltip='raw', orderIndex=1, iconName='icon'}}},
 {guid='guid-b', name='Beta', damageDone=20, healingDone=1}}
local requests = 0
function issecretvalue(v) return rawequal(v, secretValue) end
function time() return 1000 + clock end
function GetTime() return clock end
function IsInInstance() return inside, kind end
function GetBattlefieldScoreFaction() return 0 end
function GetBattlefieldWinner() return winner end
function GetNumBattlefieldScores() return #rows end
function RequestBattlefieldScoreData() requests = requests + 1 end
C_PvP = {GetScoreInfo=function(i) return rows[i] end}
C_Timer = {NewTimer=function(delay, fn)
 local timer = {delay=delay, fn=fn, cancelled=false}
 function timer:Cancel() self.cancelled = true end
 timers[#timers+1] = timer
 return timer
end}
function CreateFrame()
 local f = {}
 function f:RegisterEvent() end
 function f:SetScript(_, fn) self.run = fn end
 frames[#frames+1] = f
 return f
end
DEFAULT_CHAT_FRAME = {AddMessage=function(_, message) messages[#messages+1] = message end}
local forwarded = 0
SlashCmdList = {CHRONICLEFOREVER=function() forwarded=forwarded+1 end}
assert(loadfile('ScoutingStorage.lua'))('test', addon)
assert(loadfile('BattlegroundDiagnostics.lua'))('test', addon)
local function load(db)
 ChronicleCompanionForeverDB = db
 assert(loadfile('BattlegroundScoreboard.lua'))('test', addon)
 return addon.BattlegroundScoreboard
end
local sibling = {opaque=true}
local db = {sidekick_enabled=false, collections={future=sibling}}
local b = load(db)
local function fire(event) frames[#frames].run(nil, event or 'PLAYER_ENTERING_WORLD') end
local function tick()
 local t = timers[#timers]; clock=clock+t.delay; t.fn()
end
fire(); assert(db.collections.battlegroundScoreboard == nil and #timers == 0)
db.sidekick_enabled=1; fire(); assert(#timers == 0)
db.sidekick_enabled=true; inside=false; fire(); assert(db.collections.battlegroundScoreboard == nil)
inside=true; kind='arena'; fire(); assert(#timers == 0)
kind='pvp'; fire()
local s = db.collections.battlegroundScoreboard
assert(#s.Probes == 1 and #s.Probes[1].Changes == 2 and requests == 1)
assert(s.Probes[1].Filter.Value == 0)
assert(s.Probes[1].Changes[1].Baseline and s.Probes[1].Changes[1].IdentityKind == 'guid')
assert(s.Probes[1].Changes[1].Fields.stats.Values[1].Fields.pvpStatID.Value == 1)
assert(s.Probes[1].Changes[1].Fields.roleAssigned.Type == 'nil')
assert(db.collections.future == sibling and timers[#timers].delay == 30)
fire('UPDATE_BATTLEFIELD_SCORE'); fire(); assert(#s.Probes == 1 and #timers == 1)
-- Polling unchanged snapshots is visible without duplicating per-player baselines.
rows[1], rows[2] = rows[2], rows[1]
tick(); assert(#s.Probes == 2 and #s.Probes[2].Changes == 0)
assert(s.Counts.Polls == 2)
rows[2].damageDone=15; rows[2].roleAssigned=false; rows[2].healingDone=secretValue
rows[2].stats[1].pvpStatValue=secretValue
tick()
local change=s.Probes[3].Changes[1]
assert(change.Identity == 'guid-a' and not change.Baseline)
assert(change.Fields.damageDone.Value == 15 and change.Fields.healingDone.Type == 'secret')
assert(change.Fields.roleAssigned.Type == 'boolean' and change.Fields.roleAssigned.Value == false)
assert(change.Fields.stats.Values[1].Fields.pvpStatValue.Type == 'secret')
assert(change.Fields.name == nil and s.Probes[3].Fields.healingDone.secret == 1)
rows[2].healingDone=nil; rows[2].roleAssigned=nil; rows[2].stats=nil
tick(); change=s.Probes[4].Changes[1]
assert(change.Fields.healingDone.Type == 'nil' and change.Fields.roleAssigned.Type == 'nil' and change.Fields.stats.Type == 'nil')
-- Secret identity falls back only to readable name, never index.
rows={{guid=secretValue,name='Fallback', damageDone=secretValue}, secretValue, {damageDone=7}}
tick(); local probe=s.Probes[#s.Probes]
assert(#probe.Changes == 1 and probe.Changes[1].IdentityKind == 'name' and #probe.Unidentified == 2)
assert(probe.Fields.row.secret == 1 and probe.Changes[1].Fields.damageDone.Type == 'secret')
rows={{name='Collision',damageDone=1},{name='Collision',damageDone=2}}
tick(); assert(#s.Probes[#s.Probes].Changes == 0 and b.baseline['name:Collision'] == nil)
-- A missing row never fabricates a departure; restored identity diffs against its last observation.
rows={{guid='guid-a',name='Alpha',damageDone=16,healingDone=nil,deaths=0}}
tick(); assert(not s.Probes[#s.Probes].Changes[1].Baseline)
-- Completion triggers one immediate probe and three bounded five-second retries.
winner=0; fire('UPDATE_BATTLEFIELD_SCORE')
local completion=#s.Probes
assert(s.Probes[completion].Source == 'completion' and timers[#timers].delay == 5)
fire('UPDATE_BATTLEFIELD_SCORE'); assert(#s.Probes == completion)
for i=1,3 do tick() end
assert(#s.Probes == completion+3 and timers[#timers].delay == 30)
-- Disabled and late callbacks cannot write; re-entry starts a self-contained baseline.
local oldTimer=timers[#timers]; local count=#s.Probes; local polls=s.Counts.Polls
db.sidekick_enabled=false; oldTimer.fn(); assert(#s.Probes == count and s.Counts.Polls == polls)
db.sidekick_enabled=true; winner=nil; fire(); assert(s.Probes[#s.Probes].Changes[1].Baseline)
count=#s.Probes; oldTimer.fn(); assert(#s.Probes == count)
inside=false; fire(); assert(not b.active and timers[#timers].cancelled)
inside=true; fire(); assert(s.Probes[#s.Probes].Changes[1].Baseline)
-- Reload creates baseline, no merge with persisted session.
b:Stop(); b=load(db); fire(); assert(s.Probes[#s.Probes].Changes[1].Baseline)
-- Missing/throwing APIs and whole-row secret access produce explicit availability evidence.
C_PvP.GetScoreInfo=nil; tick(); assert(s.Probes[#s.Probes].Unidentified[1].Row.Type == 'missing')
C_PvP.GetScoreInfo=function() error('protected') end; tick()
assert(s.Probes[#s.Probes].Unidentified[1].Row.Type == 'error')
GetNumBattlefieldScores=function() return secretValue end; tick(); assert(s.Probes[#s.Probes].Count.Type == 'secret')
GetNumBattlefieldScores=function() return 1 end
C_PvP.GetScoreInfo=function() return setmetatable({}, {__index=function() error('protected field') end}) end
tick(); assert(#s.Probes[#s.Probes].Changes == 0 and s.Counts.APIErrors > 0)
assert(s.Probes[#s.Probes].Fields.damageDone.unavailable == 1)
-- Successful known fields and nested stats are bounded; secret container is not indexed.
C_PvP.GetScoreInfo=function() return {name='Name',guid='GUID',stats=secretValue} end
tick(); assert(s.Probes[#s.Probes].Changes[1].Fields.stats.Type == 'secret')
C_PvP.GetScoreInfo=function()
 local stats={}; for i=1,40 do stats[i]={pvpStatID=i,pvpStatValue=i} end
 return {guid='GUID',name='Name',stats=stats}
end
tick(); assert(s.Probes[#s.Probes].Changes[1].Fields.stats.Omitted == 8)
-- Command routing includes scoreboard, without changing other commands.
SlashCmdList.CHRONICLEFOREVER('bgstatus'); SlashCmdList.CHRONICLEFOREVER('on')
assert(forwarded == 1 and table.concat(messages,'\n'):find('Scoreboard:',1,true))
-- Full capacity preserves data and does not advance rejected baselines.
while #s.Probes < 4000 do assert(b:Append({Source='filler'})) end
local baseline=b.baseline['guid:GUID']
C_PvP.GetScoreInfo=function() return {guid='GUID',name='Name',damageDone=99} end
tick(); assert(#s.Probes == 4000 and s.Counts.Dropped > 0 and b.baseline['guid:GUID'] == baseline)
b:Stop()
for _, bad in ipairs({false, {Version=99}, {Version=1, Probes={}, Counts={}, Bytes=0, Future=true}}) do
 local broken={sidekick_enabled=true, collections={battlegroundScoreboard=bad,future=sibling,last_updated=1}}
 b=load(broken); fire(); assert(broken.collections.battlegroundScoreboard == bad and broken.collections.last_updated == 1)
 assert(broken.collections.future == sibling)
end
-- Missing timer remains visible, while bounded score events can still sample.
C_Timer=nil
local noTimer={sidekick_enabled=true}; b=load(noTimer); fire()
assert(noTimer.collections.battlegroundScoreboard.Counts.TimerFailures == 1)
clock=clock+30; fire('UPDATE_BATTLEFIELD_SCORE')
assert(#noTimer.collections.battlegroundScoreboard.Probes == 2)
b:Stop()
-- Explicit completion event supports clients with unavailable winner evidence.
C_Timer={NewTimer=function(delay, fn)
 local t={delay=delay,fn=fn}; function t:Cancel() self.cancelled=true end
 timers[#timers+1]=t; return t
end}
GetBattlefieldWinner=nil
local completionDB={sidekick_enabled=true}; b=load(completionDB); fire()
fire('PVP_MATCH_COMPLETE'); assert(timers[#timers].delay == 5)
local late=timers[#timers]; local total=#completionDB.collections.battlegroundScoreboard.Probes
fire('PLAYER_LEAVING_WORLD'); assert(late.cancelled)
late.fn(); assert(#completionDB.collections.battlegroundScoreboard.Probes == total)
-- Timer creation failures and byte capacity are explicit, with retained baseline.
C_Timer.NewTimer=function() error('timer unavailable') end
local heavy={sidekick_enabled=true}; b=load(heavy); fire()
assert(heavy.collections.battlegroundScoreboard.Counts.TimerFailures == 1)
local store=heavy.collections.battlegroundScoreboard
for i=1,2100 do b:Append({Source=string.rep('x',8192)}) end
assert(#store.Probes < 2100 and store.Counts.Dropped > 0)
b:Stop()
-- Unknown probe fields are preserved rather than rewritten on load.
local unknown={Version=1,Probes={{Source='future',Future=true}},Counts={},Bytes=1}
local unknownDB={sidekick_enabled=true,collections={battlegroundScoreboard=unknown,last_updated=3}}
b=load(unknownDB); fire()
assert(unknownDB.collections.battlegroundScoreboard == unknown and unknownDB.collections.last_updated == 3)
-- Invalid persisted counters and sparse probes are not repaired destructively.
for _, value in ipairs({-1,0.5,math.huge,9007199254740992}) do
 local bad={Version=1,Probes={},Counts={Polls=value},Bytes=0}
 local malformed={sidekick_enabled=true,collections={battlegroundScoreboard=bad,last_updated=3}}
 b=load(malformed); fire(); assert(malformed.collections.last_updated == 3 and malformed.collections.battlegroundScoreboard == bad)
end
local sparse={Version=1,Probes={[2]={Source='gap'}},Counts={},Bytes=0}
b=load({sidekick_enabled=true,collections={battlegroundScoreboard=sparse}}); fire(); assert(b.store == nil)
print('battleground scoreboard tests passed')
