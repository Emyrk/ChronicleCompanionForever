# SavedVariables scouting

Status: agreed design for future implementation, not a shipped feature. This document changes no addon behavior. The experimental failed-cast probe is not part of this design or the production feature set.

## Scope and integration

Record player levels, guilds, and party/raid presence as enrichment for combat logs. Talents and battleground events come later, in separate collections rather than extra meanings for these arrays. Do not change automatic combat logging.

`ChronicleCompanionForever.toc` already declares the account-wide `ChronicleCompanionForeverDB`. `MinimapButton.lua` initializes that table at the addon's `ADDON_LOADED` and stores `minimapHidden`. Extend the existing table without replacing valid data or unrelated settings. Initialize scouting only after SavedVariables are available. Recording is enabled only when `sidekick_enabled == true`; missing, false, or other values disable recording. This gate does not control combat logging or prevent acknowledged-data cleanup.

## Storage contract

Proposed collection name and example Lua representation:

```lua
ChronicleCompanionForeverDB = {
    minimapHidden = false, -- existing setting, preserved
    sidekick_enabled = true,
    scouting_ack = 1700000000,
    scouting = {
        Players = {
            ["Player-example-guid"] = {
                Name = "Example",
                At     = {1700000010, 1700000010, 1700000020},
                Levels = {60,         "_",        "_"},
                Guilds = {"Guild",    "",         "_"},
                Party  = {true,       "_",        false},
            },
        },
    },
}
```

- Key players by GUID, not name. `Name` is the latest observed name-and-realm identity label, not a join key or historical name timeline. Do not create entries without a usable GUID and name.
- `At`, `Levels`, `Guilds`, and `Party` are dense, equal-length arrays. A shared index is one observation. Never use nil for an unknown array value.
- `At` holds Unix timestamps in seconds. Timestamps can collide; array order preserves observation order for each player. There are no session IDs or sequence IDs, and no implied ordering between different players' arrays.
- `Levels` holds observed numeric levels. `Guilds` holds guild names; `""` specifically means known guildless. Proposed unknown marker: `false` for unavailable level or guild information. An API query failure must not become a guildless observation.
- Proposed `Party` encoding: `true` means present in the observer's party or raid; `false` means an observed departure. This is membership, not the unit-token name or a distinction between party and raid.
- The literal Lua string `"_"` means unchanged from the preceding decoded value in that array. It is never a bare Lua variable. It is allowed in `Levels`, `Guilds`, and `Party`, never in `At`. Emit it only when the value is unchanged. Unknown is a value distinct from unchanged.
- The first row of every player entry must contain explicit level, guild, and membership values, using unknown markers for unavailable level or guild data. Membership is always explicitly present or departed; unknown membership produces no row. It must decode without earlier data. Every later row must decode by walking forward from that row.

The collection name, unknown marker, and membership encoding above are concrete proposals for implementation review. The aligned arrays, GUID keys, identity label, literal unchanged marker, and self-contained retained history are the agreed requirements.

## Observation behavior

While enabled, snapshot the current party or raid, then reconcile on roster and world events. A load or reload starts a fresh in-memory observation baseline. Record current players as present, even if an earlier persisted row also says present. Do not interpret that row as proof of a newly observed join time.

Within one loaded addon lifetime, compare successful roster snapshots to detect joins and leaves. Include the local player when grouped. A confirmed transition to solo ends the observed group membership. A party-to-raid transition must not manufacture departures for players who remain present.

Record present/join rows, changed level or guild observations, and observed leave rows. Leave rows retain the last known enrichment, or explicit unknowns if none was known. Avoid redundant rows for unchanged snapshots within the same loaded lifetime. A transient unavailable roster or unresolved unit must not by itself imply a departure.

On reload, login, or logout, do not fabricate leave rows for previously saved players. Saved history is not a live roster. Reconcile the newly observable roster without asserting when an unobserved departure occurred. Events during disabled recording or while the addon is not loaded are unknown.

Exact event subscriptions and refresh opportunities for enrichment are subject to client API validation below. Recording is not limited to the combat logger's instance eligibility.

## Acknowledgement and pruning

`scouting_ack` is an optional Unix timestamp, an inclusive cutoff. On the next addon load, rows with `At <= scouting_ack` may be removed. Missing or invalid acknowledgement means no acknowledgement-based pruning. The cutoff is not a row cursor and must not identify only some rows within a timestamp collision.

Before removing rows, decode their carried-forward values. Re-encode the retained rows in their original array order, compact all four arrays together, and materialize explicit values in the first retained row of each player. If wall-clock changes make timestamps non-monotonic, preserve decoded values across any removed interior rows too. Remove empty player entries. Retained history must remain self-contained even when its first row originally used `"_"`. Preserve the enable flag, acknowledgement, minimap settings, and unrelated database fields.

Sidekick may advance the cutoff only after capturing all scouting data through it, including every row sharing the cutoff timestamp. It writes SavedVariables only while WoW is fully closed. The cutoff never decreases. Before rewriting, verify that the SavedVariables snapshot is unchanged and that no WoW process using it has restarted; otherwise defer capture and cleanup. Serialize Sidekick writers for the same file. The supported lifecycle assumes no concurrent WoW writers sharing that SavedVariables file.

## Sidekick and Chronicle ownership

1. Sidekick waits for WoW to close, then captures the combat log and the full available scouting enrichment together. It does not select players or correlate player identities or timestamps with the log.
2. Sidekick durably uploads the pair, or durably archives the pair locally for retry. A queued request or an incomplete archive is not durable capture.
3. After either durable outcome, Sidekick can always clear the captured scouting data, even if upload is pending from the archive. Preserve `sidekick_enabled`, `scouting_ack`, and unrelated settings such as `minimapHidden`. Alternatively, leave captured rows in place and advance `scouting_ack` for pruning at the next addon load. Never clear data outside the captured set.
4. Chronicle correlates combat logs with enrichment. Sidekick is transport and retention plumbing, not the correlation engine.

The retry archive must retain both members of the pair independently of the cleared SavedVariables. No Sidekick repository code is part of this addon change.

WoW flushes SavedVariables on logout or UI reload. In-memory observations are not a realtime disk stream. Crashes can lose observations since the last flush. Logout or reload does not make external writes safe while the WoW process remains open.

## Deferred decisions and validation

- Growth limits are explicitly deferred. No fixed 72-hour, row-count, or byte-size limit is agreed or enforced. Acknowledgement cleanup is not an age-based retention policy.
- Validate Forever's actual roster enumeration, GUID/name, level, guild, Unix-time, and event APIs before implementation. Candidate lifecycle events include `ADDON_LOADED`, `PLAYER_ENTERING_WORLD`, and the client's supported roster-change events. This document makes no claim of tested Forever API support.
- Verify how the client distinguishes known guildless from unavailable guild data, handles temporarily unresolved roster members, and exposes reliable group departure. Choose event subscriptions and any bounded retries from that evidence.
- Unknown schema versions or malformed aligned arrays must be preserved without recording into or pruning the affected data; report the unsupported state rather than silently resetting it. Confirm the proposed collection/unknown/membership encodings during storage review. Future talents and battleground collections require their own contracts.

## Proposed implementation stack

1. **Spec:** this document only. No runtime changes or probe promotion.
2. **Storage + tests:** initialization and exact-true gate; aligned arrays and literal unchanged encoding; unknown versus guildless; timestamp collisions; inclusive acknowledgement pruning; materialized first retained rows; empty-player cleanup; preservation of minimap and unrelated fields.
3. **Roster + tests:** validated API adapter; party/raid snapshots and reconciliation; joins, departures, level/guild changes, unresolved units, party-to-raid transitions, disabled recording, and reload without fabricated leaves. Keep combat logging behavior unchanged. Validate client behavior separately from mocked unit tests.
