# Experimental battleground evidence and diagnostics

**No API or event behavior here has been live-verified on WoW Forever.** This PR
collects raw evidence to decide future API contracts, schema and classification.
There is no localized objective classifier and no asserted globally unique match ID.

Collection and diagnostics run automatically only when
`ChronicleCompanionForeverDB.sidekick_enabled == true` (literal boolean). There is
no second diagnostic opt-in. The addon does not enable Sidekick for you. Disabled
observations/status do not mutate SavedVariables. This is **not combat logging**:
no `LoggingCombat`/CVar/minimap-light changes and no `WoWCombatLog.txt` output.
The existing combat logger continues to exclude battlegrounds.

## One-match capture checklist

1. Arrange Sidekick enablement using your existing setup; verify `/clog bgstatus`
   says `Sidekick gate=true; diagnostics=automatic` before queueing. The command
   works outside BG and before initialization, shows counts/caps, registration
   failures, missing APIs and previously observed API failures; it never clears data.
   When enabled it may initialize diagnostic storage. Missing optional APIs are
   expected, not evidence that the remaining collector is broken.
2. Play a battleground normally. Run `/clog bgstatus` inside and after the match;
   retain screenshots/text of any warnings. Target a recognizable BG NPC and run `/clog bgguid` to capture raw GUID
   candidates once (player, target and mouseover). If possible, have another enabled
   player in the **same match** target the **same NPC** and collect their artifact
   too. Note approximate real time, map, locale, character, result and NPC identity.
3. **Exit WoW completely** to flush SavedVariables. Do not rely on copying the file
   while playing or on `/reload` as a safe offline capture window.
4. **Before Sidekick clears collections**, copy the complete
   `WTF/Account/<ACCOUNT>/SavedVariables/ChronicleCompanionForever.lua` (relative to
   the actual Forever client installation) to a safe artifact location. Retain the
   original file unedited; `.bak` is optional and may describe an older session.
   Alternatively retain Sidekick's full-container capture artifact and verify it
   includes both paths below. Coordinate/temporarily pause external clearing if
   necessary; this addon has no upload acknowledgment or live-clear protocol.
5. Share the artifact(s), capture notes and status output for analysis. The file
   includes player names/GUIDs, NPC/message text and other addon collections;
   handle it as potentially identifying data. Sidekick may capture and clear the
   **whole `collections` container only while WoW is closed**. Never discard the
   sole copy of pending evidence. Restarting after an offline clear creates fresh
   storage; there is no automatic eviction.

Exact persisted paths (both included by existing full-container Sidekick capture):

- `ChronicleCompanionForeverDB.collections.battlegrounds`
- `ChronicleCompanionForeverDB.collections.battlegroundDiagnostics`

Other collection siblings, including scouting and unknown entries, are preserved.
Malformed containers/unsupported owned schemas are preserved rather than reset.
The `collections.last_updated` marker uses observed wall time when available.
Missing time does not prevent diagnostic evidence, but prevents legacy events.

## Diagnostic evidence (`battlegroundDiagnostics.Version = 1`)

Top-level fields are `Version`, `Events`, `Bytes` and `Counts`. Records retain
`Source`, raw `WallTime` (`time()`), `Monotonic` (`GetTime()`) and `Presence`
(`IsInInstance()`). First observation per addon load/container includes registration
success/failure and raw `GetBuildInfo`, `GetLocale`, `UnitGUID("player")`,
`UnitName("player")`. Time values are observation evidence, not event occurrence
or match-start times; monotonic clocks are client-local, not cross-player clocks.

Only an observed `IsInInstance() == true, "pvp"` admits announcement arguments or
BG snapshots. Arena and outside-BG announcements are not saved. Lifecycle/status
API observations can be saved outside BG to diagnose unsupported clients.
No player-chat channels, combat-log streams, or scoreboard statistics are registered.

Candidate announcements are recorded **without semantic interpretation**:

- `CHAT_MSG_BG_SYSTEM_ALLIANCE`, `CHAT_MSG_BG_SYSTEM_HORDE`, `CHAT_MSG_BG_SYSTEM_NEUTRAL`
- `RAID_BOSS_EMOTE`, `RAID_BOSS_WHISPER`, `CHAT_MSG_RAID_BOSS_EMOTE`, `CHAT_MSG_RAID_BOSS_WHISPER`
- `CHAT_MSG_MONSTER_SAY`, `CHAT_MSG_MONSTER_YELL`, `CHAT_MSG_MONSTER_EMOTE`, `CHAT_MSG_MONSTER_WHISPER`
- `CHAT_MSG_SYSTEM`

Other triggers are `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
`UPDATE_WORLD_STATES`, `UPDATE_BATTLEFIELD_STATUS`, `UPDATE_BATTLEFIELD_SCORE`,
`PVP_MATCH_COMPLETE` where supported by the scoreboard collector. Target and
mouseover events are no longer registered: `/clog bgguid` explicitly captures a
small GUID-only diagnostic record in BG. Broad diagnostic snapshots occur on
world/zone lifecycle observations or the first subsequent event at least 30 seconds
after the previous snapshot. Every announcement still retains its exact raw args,
source, wall/monotonic time and presence; messages are never throttled. Snapshot
fields are omitted between broad probes, not asserted unavailable:

- All raw `GetInstanceInfo()` returns: name, type and conventional eighth return
  map/instance ID are candidates, **not a unique match identifier**.
- `GetBattlefieldWinner()`, including nil and unconventional values.
- Optional `C_PvP.GetActiveMatchState()` / `GetActiveMatchDuration()`.
- `GetNumWorldStateUI()` and up to 64 `GetWorldStateUIInfo(index)` raw rows.
- `GetMaxBattlefieldID()` and `GetBattlefieldStatus(slot)` for up to 16 slots;
  fallback to three conventional slots when the count is unavailable/invalid.
- Raw `UnitGUID("player")`, `UnitGUID("target")`, `UnitGUID("mouseover")` samples.
  Samples can include players or NPCs and are not interpreted/deduplicated as
  instance identifiers. No enumeration of nearby units is attempted.

### Instance identity investigation

`GetBattlefieldStatus` return meanings differ between client versions. The
[Classic API documentation](https://warcraft.wiki.gg/wiki/API_GetBattlefieldStatus/Classic)
labels its third return a displayed instance number (e.g. Warsong Gulch 13), while
other versions label it team size. **All returns are retained without assigning
that position a meaning.** Neither a map ID, displayed server instance number,
nor a GUID component is proven globally unique. Compare same-match multi-player
artifacts and later different-match artifacts before choosing identity semantics.
A single run can discover candidate evidence but cannot prove global uniqueness.

### Raw value representation and support failures

API envelopes contain `API`, positional `Args`, and `Status = "ok"`, `"missing"`
or `"error"`; successful `Returns` and failed `Error` use the same representation.
A raw argument list is `{ n = original_count, Values = { ... }, Omitted = ... }`.
Each position is a tagged table: `Type = "nil"`, `"string"`, `"number"`,
`"boolean"`, `"secret"` or `"unsupported"`; admitted primitives have `Value`.
Thus nil and false remain distinct, including trailing nil returns. Unsupported
values retain `LuaType`, never unsafe object serialization/string conversion.
Secret values (or a throwing secret-value guard) are redacted before comparison.
Strings over 8,192 bytes retain a prefix and original `Bytes`; argument/return
positions beyond 64 are omitted with an explicit count. API failures are protected
and retain safe raw error evidence. Optional APIs may be entirely absent.

### Bounds and counters

Diagnostics retain at most **20,000 records** and **16,777,216 storage-weight
units**, reserving 4,096 units for bookkeeping. `Bytes` is recursive key/value
weight, not serialized file size or Lua heap usage. Counters are bounded numbers:
`Dropped` (record capacity), `Skipped` (unsupported/secret values or unusable
world count), `Truncated` (oversized values/rows/slots), `APIErrors`, `MissingAPIs`,
and `LegacyDropped` (legacy event capacity). Missing-API diagnostics are cached by API/argument and counted once per
load until the API becomes available; other counters count observations; they can continue increasing when record storage is full. Raw records
are never evicted. Capacity warns once per load and `/clog bgstatus` summarizes
counts/caps. A long/noisy match or existing backlog can still exhaust storage;
this is not a lossless guarantee. Registration failures are retained separately
in the first record and reported by status.

## Legacy structured evidence (`battlegrounds.Version = 1`)

Existing schema is unchanged: `Events` contains `observed_enter` (with `Source`),
`announcement` (`Source`, `Text`, only BG-system channels), `world_states` (`Rows`),
`completion_observed` (`Winner` 0/1/2), and `observed_leave`. Every event has `At`
(integer wall seconds) and `Segment` (index of observed entry, **not match ID**).
Reload/re-enable starts another observation window. No actual start/end, faction
winner mapping, or objective actions are inferred. World rows retain the first
eight returns, replacing nil with false, deduplicate identical snapshots, and
require at most 32 rows and 256-byte strings. Legacy announcement strings above
4,096 bytes are skipped; diagnostics retain safer richer raw evidence separately.

Legacy capacity is now **20,000 events / 8,388,608 weight units**, rather than 512
small events. Capacity sets `Stopped = "capacity"`, warns, and never evicts history.
Malformed/unknown legacy stores pause the collector without changing them or their
siblings. Missed exits, disabled intervals and continuous pvp-to-pvp transitions
cannot be reliably reconstructed by the legacy segment logic; raw instance
observations are provided for investigation, not speculative merging.

## Regression validation

Run `nix shell nixpkgs#lua -c sh -c 'for test in tests/test_*.lua; do lua "$test" || exit; done'`.
Tests use deterministic clocks/APIs, not live servers: gating, raw nil/false and
secret/unsupported values, API/registration failures, optional identity APIs,
command routing, caps/counters, and preserved collections. Passing tests does not
establish live Forever API support, event delivery, winner timing or global IDs.

## Scoreboard field-availability probe and absolute-value diffs

The experimental scoreboard sampler is automatic with the same literal Sidekick
setting, and records only while `IsInInstance()` safely reports `true, "pvp"`.
Its additional full-container capture path is:

`ChronicleCompanionForeverDB.collections.battlegroundScoreboard`

Include this sibling in the **exit-WoW-before-copy / before-Sidekick-clear** capture
workflow above. Run `/clog bgstatus` to check scoreboard polling, hidden-field,
unidentified-row, dropped-probe and API/timer counters. The scoreboard may show
no changes because values are unchanged **or because the client hides them**;
probe metadata distinguishes those cases without trying to defeat restrictions.

### Cadence and client restrictions

An observed BG entry starts an immediate baseline probe and one cancellable
30-second timer. Each timer verifies the Sidekick/BG gates before sampling and
rescheduling. Repeated zone/score events do not create duplicate timers.
`UPDATE_BATTLEFIELD_SCORE` responses are ignored by the scoreboard sampler while
a timer is active; without a timer they may sample after 30 elapsed seconds.
`RequestBattlefieldScoreData()` is invoked at most once per 30 seconds across
normal and completion probes; without a clock it is attempted only once per load;
synchronous update events cannot recursively trigger probes. The sampled rows are
the currently available client cache; a refresh response may arrive asynchronously
and appear in a later probe. This does not promise a server snapshot at exact
30-second boundaries. No score filter is
changed. Missing timers are reported; elapsed-time-gated score events can still
provide observations if a monotonic clock is available.

`PVP_MATCH_COMPLETE` or a readable conventional winner code (0/1/2) triggers one
immediate completion read and at most **three five-second read retries**, only while
still in BG. Then ordinary 30-second cadence resumes. No hidden winner value is
compared. Leaving the world, leaving BG or noticing disabled Sidekick cancels the
timer and clears in-memory baselines. Late cancelled callbacks cannot append.
Reload or re-entry begins self-contained player baselines, not continuations of
unpersisted state. Timer/event delivery still requires live verification.

The Forever-generated API contract marks `C_PvP.GetScoreInfo(index)`
`SecretInActivePvPMatch=true`. This code checks secrecy before indexing or
comparing the returned row, each known field, the nested stats table and each
nested stat value. Hidden values are recorded only as `Type="secret"`;
there is **no bypass**, unsafe conversion, arithmetic on secret values, or
inference of their contents. API calls and field accesses are protected.
`GetNumBattlefieldScores()` and optional `GetBattlefieldScoreFaction()` are probed
and their availability is explicit. Returned rows may reflect the UI's faction
filter; **this is an observable subset, not a proven full match roster**. Missing
or unavailable rows never infer player departure.

### Schema (`Version = 1`)

Top level: `{ Version=1, Probes={...}, Counts={...}, Bytes=... }`.
Each admitted probe stores:

- `Source`, tagged `At`/`Monotonic`, `Request` API status, tagged `Count` and
  `Filter`, plus optional `Omitted` row count.
- `Fields`: counts by known field path and observed type for that probe, e.g.
  `Fields.damageDone.secret = 10`. These describe field availability without
  retaining hidden contents. Polls with no player changes still store this summary.
- `Changes`: per-player `{ Identity, IdentityKind, Baseline, Fields }` records.
  Identity prefers readable, untruncated `guid`, otherwise readable `name` with
  `IdentityKind="name"`. Name fallback is weaker and may collide; duplicate or
  missing identities are not merged by row index. A change in identity kind
  starts a new baseline. First observation includes all known fields; subsequent
  observations include **only changed fields, with their current absolute values**,
  never arithmetic deltas. Nil/false/secret/unavailable transitions are changes.
- `Unidentified`: `{ Index, Row }` availability markers for inaccessible rows or
  missing/duplicate identity. `Index` is diagnostic position only, not identity.

Known scalar fields: `name`, `guid`, `killingBlows`, `honorableKills`, `deaths`,
`honorGained`, `faction`, `raceName`, `gender`, `className`, `classToken`,
`damageDone`, `healingDone`, `rating`, `ratingChange`, `prematchMMR`, `mmrChange`,
`postmatchMMR`, `talentSpec`, `honorLevel`, `roleAssigned`.

Each scalar has `Type` (`nil`, `boolean`, `number`, `string`, `secret`,
`unsupported`, `unavailable`, or `truncated`) and safe `Value` where applicable.
Strings are limited to 512 bytes; truncation retains original `Bytes`.
`stats` is a tagged ordered snapshot of up to 32 objective-stat rows containing
`pvpStatID`, `pvpStatValue`, `orderIndex`, `name`, `tooltip`, and `iconName`, each
individually tagged. IDs/labels/values remain raw and unclassified. A changed
stats snapshot replaces that field as a whole; no speculative objective matching.
Only fixed known API keys are accessed, never arbitrary API-returned table keys.

### Bounds and replay

At most **4,000 probes**, **120 player rows per probe**, **32 stats per player**,
and **16,777,216 storage-weight units** (with 4,096 reserved for bookkeeping).
Capacity never evicts pending evidence. The entire probe and its changes append
atomically; a rejected probe does **not** advance player baselines. Counters still
show attempted polling and drops. `Counts` contains bounded integer counters:
`Polls`, `Dropped`, `Hidden`, `Unidentified`, `Unavailable`, `Truncated`, `APIErrors`,
`MissingAPIs`, `TimerFailures`, `Requests`, `TimedSamples`, `TotalMicros`, `MaxMicros`.
`Requests` counts actual request API invocations (including failures), separately
from `Polls`/row reads. Each probe records request status (`throttled` when skipped)
and `RequestAt` when attempted. Completion retries do not raise request cadence. Hidden counts are observations, not distinct fields
or players. Unknown/malformed scoreboard stores are preserved with a warning.
Other collection siblings and combat logging remain untouched.

Availability and counter visibility are as important as readable damage/healing:
a successful test may establish that mid-match fields are restricted and only
become readable at completion. Capturing a full match including a short stay on
the final scoreboard gives the bounded completion retries an opportunity to
observe that transition. No live field availability is guaranteed by mock tests.


### Overhead cleanup and timing evidence

Target/mouseover event bursts now perform **zero collector API calls**, because
neither the legacy nor raw diagnostic collector registers those events. Use
`/clog bgguid` when GUID evidence is needed; no extra opt-in is required for normal
collection. Broad diagnostic snapshots are limited as described above; raw
announcements are not throttled. Missing APIs are cached rather than repeatedly
counted/allocated. Counter mutations and record appends share one timestamp touch
per diagnostic observation or scoreboard probe, rather than one per hidden field.

Both collectors optionally summarize local sample durations from
`debugprofilestop()` in bounded `Counts.TimedSamples`, `TotalMicros`, `MaxMicros`.
The diagnostic measurement covers preparation before append; scoreboard measurement
includes its append but excludes the final timestamp flush. These are local
execution-duration evidence, **not network RTT**. `GetTime()` remains scheduling
and observation-time evidence, not a fallback CPU measurement. Missing profiling
APIs simply omit duration counters. Request outcomes/timestamps are separate from
CPU-duration counters. No network tracing or extra server requests are introduced.

### Findings from the supplied captures (not universal API guarantees)

On the reported Forever **1.60.1 build 71091 enUS** client, the old world-state
API/event were unavailable. The second capture contained 14 scoreboard probes
at 30-second cadence and 347 row observations: score tables were readable, but
combat totals, GUIDs, specialization/rating and objective numerical fields were
secret; names, faction/classes and objective labels were readable. There was no
second-match completion/exit in that artifact, so postmatch visibility remains
unverified. The cumulative diagnostic stream across two matches contained 1,759
records, including 1,354 mouseover and 251 target events; those are **not all new
records from the second match**. No personal capture data is committed here.

The user described smooth rendering with network-style delays and subsequently
suspected their network. Removing gratuitous collector work is precautionary;
neither an addon cause nor a live lag fix has been established. Deterministic
operation-count tests verify request bounds and reduced calls, not live performance.

### Secret-retention experiment (testing branch only)

This probe tests an **unknown**, not an assumed capability: whether the *same*
scalar copied while secret later becomes public. Storing a secret as a local/table
value does not imply that it will declassify, or that it can be used for arithmetic,
comparison or serialization. No bypass is attempted.

At up to **three existing scoreboard sampling moments**, while completion has not
been observed, the module retains one identifiable row's original `damageDone`
and `healingDone` scalars plus its original API row reference. A sampling moment
is admitted only if at least one scalar is positively reported secret. Immutable
sample IDs/timestamps distinguish these copies; later samples never replace them.
The original values and row references live **only in module-private closure
memory**, never on the addon export object or in SavedVariables.

The probe rechecks these exact copied scalars at existing scoreboard probes,
`PLAYER_REGEN_ENABLED` while still in BG, completion, and existing completion
retries. It separately checks the fields of the retained table (which the client
could mutate), and fresh rows already read by that scoreboard probe. There are
**no additional scoreboard API calls, refresh requests or timers**. Fresh row
comparison requires the same readable GUID/name identity; row position is never
identity. Unavailable/duplicate identities produce no claimed correlation.

Safe summaries are stored as optional `Retention` on the existing bounded
`collections.battlegroundScoreboard.Probes` entries. Combat-exit checks append a
small `Source="retention"` probe under the same 4,000-probe/16 MiB limits. A summary
contains `Stage`, `CheckedAt`, and at most three `Samples`, each with:

- `ID`, `CapturedAt`, and original `Initial.damageDone/healingDone` secrecy labels;
- `Copied`, `RetainedTable`, and `Fresh` field results, kept explicitly separate;
- `FreshCorrelation="readable-identity"` or `"unavailable"`.

Each result contains `Secrecy="secret"`, `"public"`, or `"unavailable"`.
Only after `issecretvalue` returns **literal false now**, and only for a finite
ordinary numeric scalar, can a `Value` be copied into the summary. Missing,
throwing or unexpected checker results fail closed. No secret is stringified,
formatted, compared with another value, written to SavedVariables, or serialized
as part of this experiment—even temporarily. Public nonnumeric results retain
only their secrecy label.

`/clog bgstatus` shows the current private sample count (0–3), persisted
`RetentionChecks` and `RetentionPublic`. The latter counts observations where a
copied scalar originally marked secret is now marked public, not distinct
successful declassifications or proof of a supported feature. Zero samples can
mean no eligible secret/identity was observed. No live outcome is asserted.

For a meaningful capture, **do not `/reload` between sampling and completion**.
Remain in the battleground/on the final scoreboard for about **15 seconds after
completion**, if the client permits, so the three existing retries can check the
same samples. Exit/disable/reload clears the private buffer; a new observation
window never fabricates past samples. Then exit WoW completely and preserve the
full SavedVariables artifact before Sidekick clears it, as above. No retained
secrets survive that exit; only the safe experimental summaries do.
