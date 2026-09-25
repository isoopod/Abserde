# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- (CLI): Added command to automatically generate and publish RTBF templates for your abserde project.
- (CLI): Secure storage for user API keys or OAuth (not implemented yet).
- (CLI): Prompt for Universe Id and improve Init UX with the Inquire crate.

### Fixed

- Fix error when attempting to cancel a save on a destroyed key while closing a session.

### Changed

- (CLI): Config is now stored in `.abserde/config.json`. Manual migration will be needed for existing projects.
  The file containing the path to the abserde_project should be a key called "project_path", and the universe
  associated with the project should be "universe_id" as a number.

## [0.2.1] - 2026-09-10

### Fixed

- Fix error when closing a session caused by the promise handler tombstoning self before the closingPromise was set.
- Make returning a cached key respect autoload.
- Move key autoloading to after Data proxy is set, ensuring cached keys will be loaded correctly when autoloading is enabled.
- Various improvements to promise deduplication throughout the library.

## [0.2.0] - 2026-09-09

### Added

- `Profile.SlotPath`: A `/` separate path to a value that can be used to source the `slot` argument for loading multislot keys with. The first component of this path is one of the Keys in the profile, the rest is a path within that key to the value. The Key used should not have `MultiSlot` enabled.

### Changed

- Rescopes the session-locking to apply to entire sessions, not per key. Moves the `LockInterval` setting to Session instead of Key.

### Fixed

- Various fixes related to concurrency.

## [0.1.6] - 2026-08-16

### Fixed

- Re-enables support for `Data.A = Data.A or {}` and similar statements.
  `KeyA.Data.A = KeyB.Data.A` are still unsupported, but acyclic references within the same key are now permitted.
- Fixes the **iter and**len metamethods.

## [0.1.5] - 2026-08-16

### Added

- Implements autosaving on keys, by default a key is autosaved every 5 minutes. Can be disabled by setting the key's AutosaveInterval to 0

### Fixed

- Key autoloading condition only being true if autoload was set to false. Now nil and true will enable autoloading and false will disable it as intended.
- Fix Key:Wipe and other incorrect behaviour due to not properly defaulting the Lockable option to true.
- Cleans up any active threads inside a Key when destroying it.

## [0.1.4] - 2026-08-15

### Added

- Key:Wipe() - resets the keys data to the default

### Fixed

- Various edge cases with the proxy system.
- Key.Data being reassignable.
- Prevents the proxy interface tables from being accidentally used instead of the underlying data.

## [0.1.3] - 2026-07-24

## [0.1.2] - 2026-06-05

### Fixed

- Session not initializing correctly.
- Several errors related to opening, using, and closing Keys.

## [0.1.1] - 2026-06-02

## [0.1.0] - 2026-06-01

### Added

- Initial release

[unreleased]: https://github.com/isoopod/Abserde/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/isoopod/Abserde/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/isoopod/Abserde/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/isoopod/Abserde/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/isoopod/Abserde/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/isoopod/Abserde/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/isoopod/Abserde/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/isoopod/Abserde/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/isoopod/Abserde/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/isoopod/Abserde/compare/v0.1.0...v0.1.0
