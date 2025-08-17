# 📅 Event Calendar for Openplanet

Lightweight plugin that shows upcoming moon phases and can optionally notify the user.

## ✨ Summary

- 🌙 Displays moon phase events in a small overlay UI.
- 🔔 Optional notifications with sound.
- 🧪 Small test harness and helper utilities for time parsing and timestamps.

## 🎯 Project goals

- Provide a small, focused overlay that shows relevant daily events (initially moon phases) and notifies the user when something is expected on a given day.
- Primary target: support for Pursuit Channel mode — display when to expect an event on the Pursuit Channel for a selected day and optionally notify the user.
- Keep the plugin lightweight, free of private data, and easily extensible so additional event sources (community events, tournaments, custom schedules) can be added later.

## 🚔 Pursuit Channel support

- The plugin is designed to show when to expect scheduled events on the Pursuit Channel (ManiaPlanet) for any given day. The UI highlights days with events and can show approximate times or time windows for channel events.
- Notifications (sound and visual) can be enabled per event so users on the Pursuit Channel don't miss channel broadcasts.
- The current implementation uses local schedule parsing and the plugin's event model. Future releases may add support for remote schedules or user-defined event lists.

## 🫂 Extensibility and contribution

- To add new event sources: implement a fetch/parse module and map parsed events to the plugin's event model (see `Fetch.as` and `Helpers.as`).
- Add tests for new parsers in `tests/` and include them during packaging with `-IncludeTests` when debugging.
- Contributions are welcome — please open an issue or a pull request (PR) with a short description of the new source and sample data.

## 🚀 Quick start

- Copy the `event-calendar-dev` folder into `Openplanet4/Plugins/` or install the generated `.op` package.
- Enable the plugin in Openplanet's plugin list.

## 🛠️ Build

- A PowerShell build script is included. From the plugin root, run:

  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File ./build-op.ps1
  ```

  Use `-IncludeTests` to include the `tests/` folder in the produced package (useful for debugging).

## ✅ Run tests locally

- There is also a small PowerShell verifier that checks the generated `.op` package and lists its contents:

  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File ./tools/verify-release.ps1
  ```

## 🔁 CI

- `.github/workflows/ci.yml` builds the package and uploads the artifact.

## 📁 Files of interest

- `info.toml` — plugin metadata used by Openplanet
- `build-op.ps1` — build script that produces the `.op` package
- `tools/verify-release.ps1` — artifact verification helper
- `tests/` — lightweight test harness

## ⚖️ License

- MIT — see `LICENSE`

## 👤 Contact

- Author: `tomekdot`
- Team: `vitalism-creative`
- Discord: `@tomekdot`