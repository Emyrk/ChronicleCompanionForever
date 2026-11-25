local addon, timers, frames = {}, {}, {}
local clock, inside = 0, true
local token, other = {}, {}
local hidden = {[token]=true,[other]=true}
function issecretvalue(v) return hidden[v] == true end
function time() return clock+1000 end
function GetTime() return clock end
function IsInInstance() return inside,'pvp' end
function GetBattlefieldWinner() return nil end
function GetNumBattlefieldScores() return 2 end
local original = {guid='a',name='Alpha',damageDone=token,healingDone=other}
local rows = {original,{guid='b',name='Beta',damageDone=0,healingDone=0}}
C_PvP={GetScoreInfo=function(i) return rows[i] end}
C_Timer={NewTimer=function(delay,fn)
 local t={delay=delay,fn=fn}; function t:Cancel() self.cancelled=true end
 timers[#timers+1]=t; return t
end}
function CreateFrame()
 local f={}; function f:RegisterEvent() end; function f:SetScript(_,fn) self.run=fn end
 frames[#frames+1]=f; return f
end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
assert(loadfile('ScoutingStorage.lua'))('test',addon)
local function load(db)
 ChronicleCompanionForeverDB=db
 assert(loadfile('BattlegroundScoreboard.lua'))('test',addon)
 return addon.BattlegroundScoreboard
end
local db={sidekick_enabled=true,collections={future={opaque=true}}}
local b=load(db)
local function tick() local t=timers[#timers]; clock=clock+t.delay; t.fn() end
local function latest() local p=db.collections.battlegroundScoreboard.Probes; return p[#p].Retention end
local function safe(v,seen)
 assert(not rawequal(v,token) and not rawequal(v,other),'original scalar escaped private memory')
 assert(not rawequal(v,original),'original table escaped private memory')
 if type(v)=='table' then
  seen=seen or {}; if seen[v] then return end; seen[v]=true
  for k,x in pairs(v) do safe(k,seen); safe(x,seen) end
 end
end
b:Observe('PLAYER_ENTERING_WORLD')
local first=latest().Samples[1]
assert(first.ID==1 and first.Initial.damageDone=='secret')
assert(first.Copied.damageDone.Secrecy=='secret' and first.Copied.damageDone.Value==nil)
safe(db); safe(addon)
-- Original API row can mutate independently; copied scalar remains the old value.
original.damageDone=123
rows={rows[2],original}
tick()
local sample=latest().Samples[1]
assert(sample.ID==1 and sample.CapturedAt.Value==1000)
assert(sample.RetainedTable.damageDone.Value==123 and sample.Copied.damageDone.Secrecy=='secret')
assert(sample.FreshCorrelation=='readable-identity' and sample.Fresh.damageDone.Value==123)
-- Fresh readable row is distinct from retained table and copied secret.
rows[2]={guid='a',name='Alpha',damageDone=456,healingDone=789}
tick(); sample=latest().Samples[1]
assert(sample.Fresh.damageDone.Value==456 and sample.RetainedTable.damageDone.Value==123)
assert(sample.Copied.damageDone.Secrecy=='secret')
-- Simulated declassification: same retained object is checked again, never replaced.
hidden[token]=false
b:Observe('PLAYER_REGEN_ENABLED'); sample=latest().Samples[1]
assert(sample.Copied.damageDone.Secrecy=='public' and sample.Copied.damageDone.Value==nil) -- public table is not numeric
assert(sample.FreshCorrelation=='unavailable' and sample.Copied.healingDone.Secrecy=='secret')
assert(db.collections.battlegroundScoreboard.Counts.RetentionPublic>0)
safe(db); safe(addon)
-- Missing/throwing checker fails closed, including originally readable fields.
issecretvalue=nil; b:Observe('PLAYER_REGEN_ENABLED'); sample=latest().Samples[1]
assert(sample.Copied.damageDone.Secrecy=='unavailable' and sample.RetainedTable.damageDone.Secrecy=='unavailable')
function issecretvalue() error('guard unavailable') end
-- Presence fails closed through the general collector guard: buffer cleared, no saved values.
b:Observe('PLAYER_REGEN_ENABLED')
function issecretvalue(v) return hidden[v]==true end
-- New window: model a number that switches from marked secret to public; only then may serialize it.
local numericSecret=true
function issecretvalue(v) return (type(v)=='number' and v==98765 and numericSecret) or hidden[v]==true end
rows={{guid='a',name='Alpha',damageDone=98765,healingDone=other}, {guid='b',name='Beta'}}
b:Observe('PLAYER_ENTERING_WORLD')
assert(latest().Samples[1].Copied.damageDone.Value==nil)
numericSecret=false
b:Observe('PVP_MATCH_COMPLETE'); sample=latest().Samples[1]
assert(sample.Copied.damageDone.Secrecy=='public' and sample.Copied.damageDone.Value==98765)
-- Post-completion polls cannot create new active samples; retries check same sample ID.
local captured=sample.CapturedAt.Value
for i=1,3 do tick(); assert(latest().Samples[1].CapturedAt.Value==captured and #latest().Samples==1) end
local count=#db.collections.battlegroundScoreboard.Probes
db.sidekick_enabled=false; b:Observe('PLAYER_REGEN_ENABLED')
assert(#db.collections.battlegroundScoreboard.Probes==count)
db.sidekick_enabled=true; b:Observe('PLAYER_ENTERING_WORLD')
-- Fresh window with secret healing fields reaches exactly three immutable moments.
for i=1,5 do tick() end
assert(#latest().Samples==3)
local firstTime=latest().Samples[1].CapturedAt.Value
tick(); assert(#latest().Samples==3 and latest().Samples[1].CapturedAt.Value==firstTime)
inside=false; b:Observe('ZONE_CHANGED_NEW_AREA'); inside=true
rows={{guid='a',damageDone=1,healingDone=1},{guid='b'}}
b:Observe('PLAYER_ENTERING_WORLD')
assert(latest()==nil) -- no past retained samples fabricated on reentry
safe(db); safe(addon)
b:Stop()
-- Live-shaped transition: name fallback at capture, readable GUID at completion.
local transitionDB={sidekick_enabled=true}
db=transitionDB
hidden[token],hidden[other]=true,true
rows={{name='Alias',guid=token,damageDone=token,healingDone=other},{name='Other',guid='other'}}
b=load(db); b:Observe('PLAYER_ENTERING_WORLD')
assert(latest().Samples[1].Initial.damageDone=='secret')
local capturedRow=rows[1]
rows={{name='Alias',guid='now-readable',damageDone=55,healingDone=66},{name='Other',guid='other'}}
b:Observe('PVP_MATCH_COMPLETE')
sample=latest().Samples[1]
assert(sample.FreshCorrelation=='readable-identity' and sample.Fresh.damageDone.Value==55)
assert(sample.Copied.damageDone.Secrecy=='secret' and sample.RetainedTable.damageDone.Secrecy=='secret')
-- Different readable GUIDs do not make a duplicate name alias unambiguous.
rows[2]={name='Alias',guid='different-guid',damageDone=77,healingDone=88}
tick(); sample=latest().Samples[1]
assert(sample.FreshCorrelation=='unavailable' and sample.Fresh.damageDone.Value==nil)
assert(sample.Copied.damageDone.Secrecy=='secret')
b:Stop()
print('battleground secret retention tests passed')
