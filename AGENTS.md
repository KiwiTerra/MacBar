# Repository instructions

## Project

MacBar is a native macOS taskbar built with Swift, AppKit, and SwiftUI. The repository, application, executable, Swift module, and bundle are named MacBar. Target macOS 13 or later, with ScreenCaptureKit thumbnails available on macOS 14 or later. Keep the application local, without accounts, telemetry, or third-party application dependencies.

## Language

Write all documentation, code comments, identifiers, interface labels, accessibility text, error messages, script output, and commit messages in English. Apply this rule to every maintained text file, including README.md, PRODUCT.md, DESIGN.md, VALIDATION.md, tests, and scripts.

Preserve external data that must match its source: system-localized menu titles, application/window names, and Unicode test inputs. Such strings are compatibility or test data, not interface copy. Explain their purpose in English; do not translate them in ways that break matching or accent-insensitive search coverage.

## Structure

- `Sources/MacBar/`: application code and macOS integrations.
- `Tests/`: model assertions, XCTest tests, and native integration fixtures.
- `scripts/`: compiler wrapper, build, signing, installation, and test commands.
- `Resources/` and `docs/assets/`: application icons and documentation images.
- `PRODUCT.md` and `DESIGN.md`: product constraints and interface conventions.
- `VALIDATION.md`: historical validation results; preserve recorded outcomes and limitations.

## Development

Follow existing Swift conventions and keep changes focused. Preserve grouped taskbar behavior, persistent pinning and ordering, native window interactions, and permission fallbacks. Keep slow Accessibility and capture work off the main thread; perform UI updates on the main thread.

Use `scripts/swiftc.sh` for compilation: it handles a known Command Line Tools duplicate-module issue without changing the SDK. Build artifacts belong in the ignored `.build/` or `build/` directories.

## Verification

Run `./scripts/test.sh` for model changes and relevant source or fixture changes. For application changes, also compile all sources:

```sh
mkdir -p .build/local
./scripts/swiftc.sh -O -module-name MacBar Sources/MacBar/*.swift -o .build/local/MacBar
```

Use `./scripts/build.sh` when a signed bundle is needed; it requires an existing local signing identity. Keep that identity stable across updates. Never commit private keys, signing credentials, generated bundles, or local logs.

Native integration fixtures can interact with desktop windows and require macOS permissions. Use dedicated test windows and isolated preferences, clean up resources created by the test, and avoid disrupting unrelated applications. Distinguish model assertions, compilation, and actual desktop validation when reporting results. Documentation-only changes need a language review and `git diff --check`, not a new desktop test run.
