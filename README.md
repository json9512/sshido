# Project Overview

## Architecture
The project utilizes a modular Swift-based architecture designed for iOS/iPadOS, leveraging Swift Package Manager (SPM) to separate concerns into distinct modules:

* **sshidoModels**: Defines the core data structures such as `Host`, `Identity`, and `Session`.
* **sshidoCore**: Contains the business logic, including SSH channel management (via Citadel), keychain storage, network monitoring, and session orchestration.
* **sshidoUI**: Provides the user interface components, including a terminal emulator wrapper and specialized UI elements like the command palette and agent bar.
* **AppUI**: The main application layer that integrates the core logic and UI modules into a cohesive iOS experience.

## Core Functionality
- **Agentic Mobile Terminal**: A high-performance terminal interface optimized for interacting with AI agents (e.g., Claude Code) from mobile devices.
- **Resilient Connectivity**: Manages SSH sessions and leverages tools like Moshi/Mosh for stable connections in mobile environments.
- **Push Notification Integration**: Uses a relay service to provide real-time notifications from remote agents directly to the device via APNs.
- **Command & Control**: Features specialized UI components like a command palette and agent bar to streamline AI-driven workflows.

## Main Components
- **Core Engine (`sshidoCore`)**: Handles high-level workflow execution, SSH communication through `CitadelSSHChannel`, and state management via `SessionStore`.
- **Data Layer (`sshidoModels`)**: Manages the domain models that represent the system's state (Hosts, Identities, Sessions).
- **User Interface (`sshidoUI` & `AppUI`)**: Provides a rich terminal experience using web-based components and native SwiftUI views.
- **Connectivity Services**: Integrates keychain security for identity management and push services for real-time updates.