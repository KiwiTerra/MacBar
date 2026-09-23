# MacBar
<!-- impeccable:product-schema 1 -->

## Platform
macOS (native desktop)

## Stack
Swift + AppKit, as proposed and accepted in the conversation. SwiftUI for the bar and launcher contents. No third-party dependencies.

## Users
The owner of this Mac wants a Windows-like taskbar without buying uBar or WinBar.

## Product Purpose
Switch between running apps and windows, pin favorites, and find installed applications from a compact desktop bar.

## Capabilities and Constraints
Grouped application icons are explicitly chosen by the user, in the style of Windows 11. Accessibility authorization is required to inspect and control other applications' windows. The launcher and application switching work without this permission. Icons align left, can be pinned and reordered, and retain their order across restarts. Hover previews use ScreenCaptureKit on macOS 14+ with Screen Recording authorization; titles and icons remain available without capture permission. No replacement of the system tray. No networking, telemetry, or account.

## Brand Commitments
Windows 11-style grouped taskbar behavior. English interface. The application is named MacBar.

## Open Decisions
Assumptions for the initial version: dark native appearance; primary screen by default; multi-screen optional; native Dock preferences remain under user control.
