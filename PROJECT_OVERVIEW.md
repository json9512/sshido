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