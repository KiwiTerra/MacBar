# Validation — September 22, 2026

- Optimized Swift compilation: passed, targeting macOS 13 / Apple Silicon.
- 16 behavior assertions: passed (`scripts/test.sh`).
- Live startup test: passed; 1 taskbar, 11 running applications detected, 102 applications in the catalog, grouping enabled, valid geometry.
- Taskbar and launcher rendering inspected using exports of their own views (`.build/screenshots/`).
- Local signature of the installed bundle: verified with `codesign --verify --deep --strict`.
- Info.plist: valid.
- Installation: `~/Applications/MacBar.app`.

## Pending checks after the user grants permission

Accessibility was not granted during the startup test. Actual control of external windows (selection, minimization, closing), switching Spaces, and multiple-monitor display were therefore not validated in practice. Launch at login is available through the menu, but was neither enabled nor tested after restarting.

## Build environment

The installed Command Line Tools contain an obsolete duplicate `SwiftBridging` declaration. The `scripts/swiftc.sh` wrapper applies a project-local VFS overlay when it detects this condition. No SDK or system files were modified. Swift Package Manager also fails in this environment; the build and test scripts do not depend on it.

## Fix 0.1.1 — maximized windows

- 27 assertions passed, including 11 regression checks covering reserved height, half-screen tiles, normal windows, full screen, minimized windows, displays without a taskbar, and multiple-display coordinates.
- Optimized compilation and installed bundle signature verified.
- Startup test passed after installation; Accessibility was not granted to this version at test time.
- The fix listens for size and position notifications from the active window, with periodic polling as a fallback. It waits until mouse dragging ends and limits retries when the application refuses the requested size.
- The work area accounts for the actual taskbar height and leaves an 8-point gap above it.
- Additional check through Launch Services (`open -n -W … --args --smoke-test`): Accessibility was still denied to version 0.1.1 after the first attempt to enable it. The first real test window was not fitted; this does not count as a pass. Removing and re-adding the new application in permissions was requested.
- The stability of screen objects used to associate the taskbar with its monitor was verified on this machine.

## Live validation after granting permission again and restarting

After removing and re-adding MacBar in Accessibility and fully restarting it, the dedicated native test launched through Launch Services passed two consecutive maximizations: height corrected from 1084 to 1012 points. The window stopped 72 points above the bottom of the usable area (taskbar and margins). Results: `.build/fit-result.log`. The test window closed automatically; MacBar remained running.

## Version 0.1.2 — margins and zoom toggling

- Taskbar without outer margins or container padding; square outer corners. Reserved space reduced to its 56-point height alone.
- Normal size and position remembered per window, with confirmation of changes actually applied. A second native zoom restores the previous rectangle; a delayed or refused AX write does not count as a new zoom.
- 46 assertions passed, including three maximize/restore cycles and updating the restore rectangle after manual resizing.
- Compilation and installed signature verified. Actual taskbar rendering inspected in `.build/screenshots-v012/bar.png`.
- The integration test now uses `NSWindow.performZoom` instead of two manual calls to `setFrame`. Reproducible source: `Tests/Integration/ZoomFixture.swift`.
- First live attempt for this version: Accessibility permission denied after recompilation, so the lack of resizing was expected. Permission requested again; this test must not count as a pass.

### Final validation of 0.1.2

After confirming Accessibility access (`.build/zoom-permission.log`) and restarting the main instance, all six native transitions passed: three maximizations stopped above the taskbar, each followed by an exact restoration of the initial rectangle. Result: `.build/zoom-confirmed-result.log` (PASS 1 through PASS 6). The test window closed automatically. Version 0.1.2 remained installed and running.

## Version 0.1.3 — Terminal investigation

The user reported that the `performZoom` test did not reproduce double-clicking Terminal's title bar. The observed macOS setting was `AppleActionOnDoubleClick = Maximize`. The new explicit `--terminal-zoom-test` mode creates a Terminal window identified by a unique marker, generates real double-clicks on its title bar, checks six transitions, and terminates only its own script/window. It does not reuse any user tabs.

Zoom tracking now accepts an applied size rounded to the character grid, preserves the previous normal size, and still distinguishes refused resizing from a rounded result. Bottom-edge overflow is corrected by requesting a smaller height. 52 assertions passed; compilation and signature verified. Live validation pending permission being granted again for this version.

### First live Terminal test result

Double-clicking with the macOS Maximize setting was reproduced. Restoring the smaller window worked, but the exact check found width drift from 898 to 895 points. This test stopped at transition 2, so it does not validate all six transitions. Source: `.build/terminal-zoom-result.log`.

## Version 0.1.4

- Bounded compensation for deviations actually applied by Terminal to prevent size drift on each restoration.
- Additional case fixed: a window already fitted when MacBar starts no longer becomes its own restore size. Without history, restoration uses a smaller size (75%).
- 55 assertions passed; compilation and signature verified.
- Live validation of this version pending permission being granted again after recompilation.

## Version 0.2.0 — pinning, ordering, and previews

- Left-aligned icons, pin button, internal drag and drop, and application drops from Finder or the launcher. Persistent ordering and movement commands in the context menu.
- Hover panel with ScreenCaptureKit thumbnails, window selection/closing, and a fallback without permission. Captures remain in memory only.
- 63/63 assertions passed: new cases for movement, persistence, and matching windows with identical titles by geometry.
- Optimized compilation and installed signature verified. Launch Services test passed: one taskbar, 13 tasks, 102 applications, valid geometry. Left-aligned rendering inspected in `.build/features-snapshots/bar.png`.
- Accessibility was denied to this new build during the test. Captures and external-window interactions were therefore not validated in practice; they require macOS permissions. Physical drag and drop was not automated; reordering logic is covered by assertions.
- No Terminal test was rerun for this request.

## Version 0.2.1 — preview and reordering feedback

- Card appearances are batched before capture, with an immediate follow-up if a new card appears during capture; window captures start in parallel.
- A single drop destination calculates the index and half of the hovered icon. Internal drops read their own payload and explicitly preserve pinning intent from the launcher.
- Width calculated exactly from cards, gaps, and margins: 248 points for one window, 478 for two. Titles truncated and height adjusted to permission messages.
- 71/71 assertions passed; compilation and installed signature verified. Visual fixture with two long titles: 478 × 291 points with the banner, rendering inspected in `.build/preview-two-windows.png`; source `Tests/PreviewLayout/main.swift`.
- Startup test: one taskbar, 13 tasks, valid geometry, Accessibility denied after recompilation. Actual capture latency and physical drag and drop were not measured in this validation. No Terminal test was run.

## Persistent local signing

- “MacBar Local Code Signing” certificate created and non-exportable private key imported into the login keychain; no system trust changes.
- Build configured to use only the recorded certificate, without an ad hoc fallback. Designated requirement tied to the certificate and bundle ID.
- `scripts/test-signing.sh` passed: two distinct versions satisfy each other's signing requirements, without depending on cdhash.
- Migration installed after stopping the process; previous version preserved under `.build/MacBar-before-stable-signature.app`.
- Actual TCC permission retention between updates remains to be checked after initially authorizing this new identity.

## Version 0.2.2 — native reordering

- Replaced SwiftUI dragging on taskbar buttons with local AppKit tracking of press, movement, and release. 4-point threshold, insertion indicator, cancellation outside the taskbar and with Escape. External drops from Finder/the launcher remain available.
- Integration test `Tests/Reordering/main.swift` run on the actual BarView in an inactive TaskbarPanel: synthetic mouse events routed through NSApplication.sendEvent, movement right then left, cancellation outside the taskbar, and persistence. Isolated test preferences. All passed.
- 71/71 model assertions passed; compilation and signature verified.
- Accessibility was actually enabled both before AND after this update (reports `.build/pre-reorder-permissions.log` and `.build/post-reorder-permissions.log`). Accessibility permission retention through the permanent signature is therefore confirmed on this Mac. Screen recording permission was not measured by this test.

## Version 0.2.3 — hiding applications without windows

- Excluded apps whose Accessibility scan confirms they have no windows. Pinned apps remain as shortcuts without an active indicator; clicking them opens the application to recreate a window.
- Preserved minimized windows and fallback mode when Accessibility is denied or an app scan fails.
- 76/76 assertions passed, including closing the last window in grouped/ungrouped modes, pinned apps, minimized windows, and scan errors.
- Compilation and installed signature verified. No user favorites deleted.

## Version 0.2.4 — left-clicking a group

- Left-clicking an app with multiple windows directly shows its last-used window. The focused window is read at click time, with history as a fallback and recovery if that window has closed.
- Minimized windows can be restored. Explicit selections from previews update history. Right-clicking and previews remain available.
- 82/82 assertions passed; six new cases cover recent focus, history, minimization, closing, and empty groups. Compilation and signature verified.

## Version 0.2.5 — hover responsiveness

- Hover-intent delay reduced from 350 to 120 ms; the first four cards begin capturing as soon as the pointer enters the icon, without waiting for the panel to appear or onAppear.
- Thumbnails less than five seconds old are reused through a bounded memory cache (24 images / 16 MB), followed by a fresh capture. Generations canceled and preloading stopped when hover is abandoned.
- Compilation and installed signature verified. The 120 ms delay concerns opening the panel, not a guaranteed ScreenCaptureKit capture duration; actual capture latency was not measured.

## Version 0.2.6 — Dock actions on right-click

- Read the menu of the correct Dock tile, identified by application URL, through AXShowMenu. Copy exposed titles, states, and submenus into a native MacBar menu.
- On selection, reopen the Dock menu and resolve the path by title and occurrence; do not reuse AX references destroyed when the menu closes. Fail explicitly if the action no longer exists.
- MacBar management commands remain appended to the bottom of the menu. Local fallback if the app is absent from the Dock or reading fails. Right-click and Control-click supported by native mouse tracking.
- Live Finder test passed: loading actions, executing “New Finder Window,” increasing the window count by 1, and closing that test window (AX success). Report: `.build/dock-actions-final.log`.
- The first two attempts each left a new Finder window open: the AX identity test confused renewed references with new windows and deliberately avoided closing ambiguous windows. The final test uses the window count and closes the newly focused window.
- Limitation: the Dock must create its menu; it may appear briefly during reading/execution. The actual action was validated with Finder, not every application or submenu.

## Version 0.2.7 — Dock badges

- Read AXStatusLabel on Dock tiles identified by URL, on a dedicated queue, without opening menus. Updated with the 1.5-second cycle; no user notifications accessed elsewhere.
- Red badge takes priority over the window count, visually capped at 99+, with full text accessible to screen readers. Text badges and dots without text supported; badge disappears when the Dock removes it.
- 88/88 assertions passed. Dedicated live test: temporary application with badge 7, then 120, then no badge; all three states detected (report `.build/badge-reading.log`). Test application terminated after validation.
- Compilation and signature verified. Limitation: only badges exposed by the Dock are available; drawings embedded by apps in their icons are not interpreted.

## Version 0.2.8 — Cmd+H-style hiding

- Clicking the active app's grouped icon calls NSRunningApplication.hide, hiding the whole app. The next click immediately calls unhide then activate, without native minimization or waiting for an AX scan.
- A hidden app stays in the taskbar even if it no longer exposes windows through AX. Previews can still restore a manually minimized window.
- 90/90 model assertions passed. Integration test with a dedicated external app and two windows: whole-app hiding, no minimized windows, showing and activation, windows still not minimized after returning. Report: `.build/hide-toggle-final.log`.
- On this Mac, hide() can return false even when hiding succeeds. Verification uses isHidden after AppKit processes the request instead of that return value.
- Compilation and installed signature verified. Tests did not hide working applications.

## Version 0.2.9 — cursor inherited from window edges

- Taskbar and preview hosting views have an AppKit tracking area that remains active even when the panel is inactive: entry, movement, and cursor updates restore the arrow. No intervention while a mouse button is held.
- Test in an inactive TaskbarPanel: vertical/horizontal resize cursors replaced by the arrow. Right/left dragging, cancellation outside the taskbar, and persistence regressions passed in the same view.
- Compilation and installed signature verified. The test injects events/cursors into the view; physical pointer movement from another application's edge was not automated.
- Maximized applications retain native macOS resizing behavior; they are not locked as in full-screen mode.
