# Chronicle Companion Forever

A lightweight World of Warcraft: Forever addon that manages combat logging automatically.

## Behavior

- Enables combat logging and Advanced Combat Logging when you enter an instance.
- Does not enable logging in battlegrounds.
- Stops combat logging automatically when you leave the instance.
- Never displays a confirmation prompt or asks you to start or stop logging.
- Repeats the desired logging state after loading screens because WoW Forever can briefly ignore the first request.

Arenas, dungeons, raids, and scenarios count as instances. Battlegrounds do not.

Combat logs are written by the game to its normal `Logs/WoWCombatLog.txt` location.

## Installation

1. Copy this repository folder into your WoW Forever `Interface/AddOns` directory.
2. Ensure the folder is named `ChronicleCompanionForever`.
3. Enable **Chronicle Companion Forever** from the AddOns menu.

No configuration is required.
