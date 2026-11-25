local addon, frames, timers = {}, {}, {}
local clock, profileClock = 0, 0
local calls = {}
local function hit(name) calls[name]=(calls[name] or 0)+1 end
function time() hit('time'); return 1000+clock end
function GetTime() hit('GetTime'); return clock end
function debugprofilestop() profileClock=profileClock+0.1; return profileClock end
function IsInInstance() hit('IsInInstance'); return true,'pvp' end
function GetInstanceInfo() hit('GetInstanceInfo'); return 'BG','pvp' end
function UnitGUID(unit) hit('UnitGUID'); return 'guid-'..unit end
function GetBattlefieldWinner() hit('GetBattlefieldWinner'); return nil end
function GetNumBattlefieldScores() hit('GetNumBattlefieldScores'); return 1 end
function GetNumWorldStateUI() hit('GetNumWorldStateUI'); return 0 end
function GetMaxBattlefieldID() hit('GetMaxBattlefieldID'); return 3 end
function GetBattlefieldStatus() hit('GetBattlefieldStatus'); return 'active' end
function CreateFrame()
 local f={events={}}
 function f:RegisterEvent(e) self.events[e]=true end
 function f:SetScript(_,fn) self.run=fn end
 frames[#frames+1]=f; return f
end
C_Timer={NewTimer=function(delay,fn)
 hit('NewTimer'); local t={delay=delay,fn=fn}; function t:Cancel() self.cancelled=true end
 timers[#timers+1]=t; return t
end}
local hidden={}
function issecretvalue(v) return rawequal(v,hidden) end
C_PvP={GetScoreInfo=function() hit('GetScoreInfo'); return {name='Test',guid=hidden,damageDone=hidden,healingDone=hidden} end}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
SlashCmdList={CHRONICLEFOREVER=function() end}
ChronicleCompanionForeverDB={sidekick_enabled=true}
assert(loadfile('ScoutingStorage.lua'))('test',addon)
local touch=addon.ScoutingStorage.TouchCollections
addon.ScoutingStorage.TouchCollections=function(...) hit('Touch'); return touch(...) end
assert(loadfile('BattlegroundDiagnostics.lua'))('test',addon)
assert(loadfile('Battlegrounds.lua'))('test',addon)
assert(loadfile('BattlegroundScoreboard.lua'))('test',addon)
local d,b=addon.BattlegroundDiagnostics,addon.BattlegroundScoreboard
local function dispatch(event,...)
 for _,f in ipairs(frames) do if f.events[event] then f.run(nil,event,...) end end
end
function RequestBattlefieldScoreData()
 hit('Request'); dispatch('UPDATE_BATTLEFIELD_SCORE') -- synchronous response must not recurse
end
dispatch('PLAYER_ENTERING_WORLD')
calls={}
for i=1,1000 do dispatch('UPDATE_MOUSEOVER_UNIT'); dispatch('PLAYER_TARGET_CHANGED') end
assert(next(calls)==nil) -- no broad calls, GUID calls, touches, or timer work
SlashCmdList.CHRONICLEFOREVER('bgguid')
assert(calls.UnitGUID==3 and not calls.GetInstanceInfo and not calls.GetNumWorldStateUI and not calls.GetBattlefieldWinner)
-- Full diagnostics bounded between lifecycle observations; every message remains exact.
calls={}
for i=1,100 do d:Observe('CHAT_MSG_SYSTEM','raw '..i) end
assert(not calls.GetInstanceInfo and not calls.GetNumWorldStateUI and not calls.GetBattlefieldStatus)
local events=ChronicleCompanionForeverDB.collections.battlegroundDiagnostics.Events
assert(events[#events].Args.Values[1].Value=='raw 100')
-- Score UI response storms cause no request/read/timer churn in scoreboard.
calls={}
for i=1,1000 do b:Observe('UPDATE_BATTLEFIELD_SCORE') end
assert(next(calls)==nil)
clock=30; calls={}; timers[#timers].fn()
assert(calls.Request==1 and calls.GetScoreInfo==1 and calls.NewTimer==1)
-- One scoreboard touch even when multiple fields are hidden, separate from sync diagnostic event touches.
local s=ChronicleCompanionForeverDB.collections.battlegroundScoreboard
assert(s.Counts.Requests==2 and s.Counts.TimedSamples==2)
local before=s.Counts.Requests
for i=1,1000 do b:Observe('UPDATE_BATTLEFIELD_SCORE') end -- asynchronous responses
assert(s.Counts.Requests==before and calls.Request==1)
-- completion and 5s retries are read-only within the ordinary refresh interval
b:Observe('PVP_MATCH_COMPLETE')
for i=1,3 do clock=clock+5; timers[#timers].fn() end
assert(s.Counts.Requests==before)
-- Test batched touches without synchronous dispatch into the other collectors.
function RequestBattlefieldScoreData() hit('Request') end
clock=75; calls={}; timers[#timers].fn()
assert(calls.Touch==1 and calls.Request==1 and calls.GetScoreInfo==1)
assert(s.Probes[#s.Probes].RequestAt.Value==75)
assert(s.Counts.TotalMicros>0 and s.Counts.MaxMicros>0)
local missingBefore=ChronicleCompanionForeverDB.collections.battlegroundDiagnostics.Counts.MissingAPIs
for i=1,100 do d:API('DefinitelyMissing') end
assert(ChronicleCompanionForeverDB.collections.battlegroundDiagnostics.Counts.MissingAPIs==missingBefore+1)
b:Stop()
print('battleground overhead tests passed: 2000 hot events=0 calls; 1000 score responses=0 scoreboard calls; 30s tick=1 request/1 row read/1 timer')
