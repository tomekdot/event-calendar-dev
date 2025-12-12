# Changelog

All notable changes to this project are documented in this file.

## 1.0.0 - 2025-09-11

- Initial public release.

## 1.1.0 - 2025-12-12

- UI: Standardized button sizing and unified navigation/day button heights for consistent scaling.
- UI: Enforced minimum window width so date controls cannot be collapsed.
- Build: `tools/build-op.ps1` now creates `.op` in the plugin root (parent of `tools`) and writes a timestamped fallback if the versioned file is locked.
- Cleanup: Removed ManiaCalendar integration and related settings (stability/compatibility).
- Misc: Minor notification indentation/style fixes and other small refactors.
