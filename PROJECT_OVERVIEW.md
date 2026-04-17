# Project Overview

## Purpose
sshido is a mobile terminal application designed specifically for agentic coding workflows on iPhone and iPad. It provides a high-performance, agent-native interface that integrates seamlessly with tools like Claude Code, offering features such as a command palette, plan-mode toggles, and slash menus to facilitate AI-driven development from a mobile device.

## Architecture
The project follows a modular Swift-based architecture designed for iOS/iPadOS:

*   **Mobile App (Swift):** A native iOS application built using Swift and SwiftUI, organized into several SPM modules:
    *   `sshidoModels`: Core data models (Host, Identity, Session, etc.).
    *   `sshidoCore`: Business logic and services (SSH handling, session management, push notifications, keychain).
    *   `sshidoUI`: Reusable UI components and terminal wrappers.
    *   `sshido (AppUI)`: The main application entry point and high-level views.
*   **Server Component:** A lightweight server environment installed on the developer's machine to facilitate connectivity. It includes:
    *   A shell installer that sets up `mosh` and `tmux`.
    *   A Claude Code notification hook.
    *   An `sshido-relay` service (written in Go) that handles APNs (Apple Push Notification service) relaying for push alerts.

## Key Components
*   **Terminal Interface:** A robust terminal emulator leveraging SwiftTerm and web-based components for high performance.
*   **Agentic UI:** Specialized UI elements like the `CommandPalette` and `AgentBar` tailored for interacting with AI agents.
*   **Connectivity Engine:** Supports SSH (via SwiftSH/Citadel) and Moshi for resilient mobile connections.
*   **Push Notification System:** Integrated via a dedicated relay server to provide real-time alerts from coding agents.
*   **Voice Input:** On-device voice dictation capabilities (planned with WhisperKit) for hands-free interaction.

## Navigation Rules (iOS 26 / SwiftUI)
All app navigation flows through `AppRouter` (`Sources/Core/AppRouter.swift`). These rules prevent a class of bug where iOS 26 renders a "broken view" placeholder (yellow triangle) when internal `NavigationStack` state diverges from `$path`:

1. **Never mix navigation APIs in a stack bound to `$path`.** Do not write `NavigationLink { SomeView() } label: { ... }` inside a `NavigationStack(path:)`. Use `NavigationLink(value: AppRouter.Destination.x)` or `router.push(.x)`. The one exception: self-contained modal `NavigationStack`s with no `path:` binding (e.g. `SettingsView` inside its sheet) may use legacy `NavigationLink { View() }`.
2. **Exactly one `.navigationDestination(for: AppRouter.Destination.self)`** per `NavigationStack`. The enum carries all drill-down cases.
3. **Sheets are driven by `router.sheet`**, not by local `@State` flags inside children of the `NavigationStack`.
4. **Never mutate App-root `@State` in response to a global notification while views are pushed.** Bind notification observers to the leaf view that consumes the value.
5. **No continuous polling that writes to navigation-adjacent `@State`.** Scope periodic refresh to the leaf view.

Regression gate: `rg 'NavigationLink\s*\{' Sources/AppUI/HostListView.swift Sources/AppUI/SessionsListView.swift Sources/AppUI/SessionView.swift` must return zero hits.