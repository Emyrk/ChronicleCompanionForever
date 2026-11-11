<p align="center">
  <a href="https://forever.chronicleclassic.com/?utm_source=github&amp;utm_medium=referral&amp;utm_campaign=evergreen&amp;utm_content=readme_logo">
    <img src="assets/ChronicleLogoCenter.svg" alt="Chronicle" width="400" />
  </a>
</p>

# Chronicle Companion Forever

> Automatic combat logging for World of Warcraft: Forever.

Chronicle Companion Forever starts and stops combat logging automatically so your logs are ready to upload to **[Chronicle Forever](https://forever.chronicleclassic.com/?utm_source=github&utm_medium=referral&utm_campaign=evergreen&utm_content=readme_intro)**. There are no prompts and no settings to manage.

## Features

- Enables combat logging and Advanced Combat Logging when you enter an instance.
- Automatically stops combat logging when you leave the instance.
- Logs dungeons, raids, arenas, scenarios, and other non-battleground instances.
- Does not record battlegrounds.
- Retries after loading screens when WoW Forever temporarily ignores a logging request.
- Shows a green minimap icon while recording and a red icon when not recording.

Combat logs are written to the game's normal `Logs/WoWCombatLog.txt` location.

## Recommended: Chronicle Sidekick

For the most convenient experience, use **[Chronicle Sidekick](https://github.com/Emyrk/chronicle-sidekick)** alongside this addon. The desktop app runs on Windows, macOS, and Linux and helps send your WoW combat logs to the correct Chronicle community.

Download it from the **[Chronicle Sidekick releases page](https://github.com/Emyrk/chronicle-sidekick/releases/latest)**.

## Installation

1. Download the latest release of Chronicle Companion Forever.
2. Extract the addon into your WoW Forever `Interface/AddOns` directory.
3. Ensure the folder is named `ChronicleCompanionForever`.
4. Enable **Chronicle Companion Forever** from the AddOns menu.

No configuration is required.

### Minimap icon

The minimap icon uses the green/red textures from [Chronicle Companion WoTLK](https://github.com/Emyrk/ChronicleCompanionWoTLK). It reflects the actual combat-logging state and updates automatically.

- **Ctrl-click** the icon to hide it without stopping recording.
- Use **`/clog minimap`** to show or hide it again (`/chronicle minimap` also works).
- Visibility is saved across reloads and logins (account-wide).

## Experimental failed-cast transport probe

The `ChronForeverProbe` directory is a separate, two-file test addon. It changes only the mutable `SPELL_FAILED_MOVING` Lua global so we can determine whether WoW Forever copies that value into the final field of a `SPELL_CAST_FAILED` combat-log row.

This probe is not part of Chronicle Companion Forever. Copy `ChronForeverProbe` beside the main addon in `Interface/AddOns`, then enable **Chronicle Forever Transport Probe** from the AddOns menu.

1. Enable logging with `/console advancedCombatLogging 1` and `/combatlog`.
2. Trigger one normal baseline by starting a cast-time spell and moving before it finishes.
3. Run `/cfprobe arm`.
4. Trigger the same moving failure once.
5. Immediately run `/cfprobe restore`.
6. Stop logging with `/combatlog`.
7. Search the newest `Logs/WoWCombatLog*.txt` for `CHRON_PROBE_A`.

PowerShell example:

```powershell
Select-String -Path .\Logs\WoWCombatLog*.txt `
    -Pattern 'CHRON_PROBE_A' |
    Select-Object -Last 5
```

| Result | Meaning |
|---|---|
| The final `SPELL_CAST_FAILED` field is `"CHRON_PROBE_A"` | The failed-cast transport primitive works on Forever. |
| The red UI error shows the marker, but the disk log keeps the normal reason | The Lua global affects the UI only. |
| Both the UI and disk log keep the normal reason | Forever uses internal or cached failure text. |
| No `SPELL_CAST_FAILED` row appears | Fix the trigger or logging setup and establish the baseline before interpreting the probe. |

The probe intentionally has no UI suppression, compression, framing, combat-log listeners, or chunking.

### Payload-length experiment

After confirming the short marker, test exact payload lengths with:

```text
/cfprobe length 64
/cfprobe length 128
/cfprobe length 256
/cfprobe length 512
/cfprobe length 1024
```

The command accepts any whole number from 32 through 4096. It creates an ASCII payload of exactly that length with a recognizable prefix and ending marker. For example, a 512-byte payload starts with `CHRON_LEN_0512|` and ends with `|END_0512`.

For each length:

1. Run `/cfprobe length <bytes>`.
2. Trigger one moving cast failure.
3. Read the automatic `UI_ERROR_MESSAGE` report in chat.
4. Run `/cfprobe restore` immediately.
5. Search the combat log for `CHRON_LEN_` and confirm the ending marker is present.

A complete UI delivery reports values like:

```text
[ChronProbe] UI_ERROR_MESSAGE type=57 length=512 expected=512 exact=true end=true
```

`exact=false` or `end=false` indicates that the UI event payload changed or was truncated. The combat-log field must be checked separately because its limit may differ from the UI event limit. Duplicate reports are expected because Forever can emit the same failed-cast event more than once.

## Upload Logs

View and upload your logs at **[forever.chronicleclassic.com](https://forever.chronicleclassic.com/?utm_source=github&utm_medium=referral&utm_campaign=log_upload&utm_content=readme_upload)**.

## Releasing to CurseForge

Version tags matching `v*`, such as `v1.0.0`, run the WoW Packager workflow and upload the packaged addon to CurseForge.

The GitHub repository must define an Actions secret. The CurseForge project ID, `1782636`, is configured in the addon TOC file.

The workflow can also be started manually from the GitHub Actions page.

## License

Chronicle Companion Forever is available under the [MIT License](LICENSE).
