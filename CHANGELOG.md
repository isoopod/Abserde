# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[unreleased]: https://github.com/isoopod/Abserde/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/isoopod/Abserde/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/isoopod/Abserde/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/isoopod/Abserde/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/isoopod/Abserde/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/isoopod/Abserde/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/isoopod/Abserde/compare/v0.1.0...v0.1.0
