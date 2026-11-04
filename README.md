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

## Upload Logs

View and upload your logs at **[forever.chronicleclassic.com](https://forever.chronicleclassic.com/?utm_source=github&utm_medium=referral&utm_campaign=log_upload&utm_content=readme_upload)**.

## Releasing to CurseForge

Version tags matching `v*`, such as `v1.0.0`, run the WoW Packager workflow and upload the packaged addon to CurseForge.

The GitHub repository must define an Actions secret named `CURSEFORGE_API_KEY` containing a CurseForge API token. The CurseForge project ID, `1782636`, is configured in the addon TOC file.

The workflow can also be started manually from the GitHub Actions page.

## License

Chronicle Companion Forever is available under the [MIT License](LICENSE).
