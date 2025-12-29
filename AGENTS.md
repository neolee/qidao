# AGENTS.md

This AGENTS.md provides context and instructions for AI agents (e.g., Copilot, Aider, Codex, Claude Code, etc.) working on this project. It supplements the README.md by offering project-specific setup, guidelines, and technical details to enable efficient code generation, debugging, and contributions without cluttering human-facing docs.

## Project Overview
QiDao (Tao of Go) is a modern Go (Weiqi) tool targeted primarily for macOS, inspired by Lizzieyzy. It provides three main modes (Analysis, Edit and Play) for different scenario. Key features include SGF file handling, real-time AI analysis via KataGo APIs and GTP, graphical variation trees, and high-performance board rendering. The project uses a hybrid Swift-Rust architecture for native UI and optimized core logic.

## Directory Structure
- `QiDao/`: Xcode project for the SwiftUI application.
- `qidao-core/`: Rust-based core logic.
  - `src/lib.rs`: Main entry point for UniFFI exports.
  - `src/bin/uniffi-bindgen.rs`: CLI tool for generating bindings.
  - `src/bin/test-**.rs`: CLI tool for testing.
  - `out/`: Generated Swift/C bindings.
- `resource`: Miscellaneous resource (reference docs, samples games, screens, etc.).
- `tools`: Python tools for specific tasks (generate app icon, etc.).
- `appcast.xml` and `exportOptions.plist`: for CI and auto-update.
- `INIT.md`: Initial motivation at the start of this project, as functional and non-functional requirements.
- `MEMO.md`: Detailed information for coding agents, including specification, technical architecture, project progression, and other useful notes.
- `TODO.md`: specification for highly complex tasks, written by human.
- `AGENTS.md`: this document, for coding agents use.

## Code Style Guidelines
- **General**:
  - Naming and Style: follow programming language's best practice and most idiomatic usage.
  - Consistent indentation: 4 spaces (no tabs).
  - No trailing whitespace, no unnecessary blank line.
  - Comments: Doc comments for public APIs; inline for complex logic.
- **Swift**:
  - Swift language version 5+.
  - Follow SwiftUI best practices: Use `@State`, `@ObservedObject`, and `@FocusState` for reactive UI.
  - Prefer declarative views; avoid imperative loops in rendering.
  - Concurrency: Use `nonisolated` actors minimally; prefer `MainActor` for UI updates.
  - Localization: Use customized language manager (`Localization.swift`).
  - Performance: Optimize for 60/120fps rendering; use `Canvas` over heavy View hierarchies.
- **Rust**:
  - Use Rust 1.70+ idioms: Prefer `Arc<Mutex<>>` for shared state, async with Tokio for engine I/O.
  - Error handling: Use `Result` with custom errors; avoid panics in library code.
  - UniFFI exports: Keep interfaces simple; use structs/enums for data transfer; support proc-macro (`[uniffi::export]` on exporting function and structure interfaces).
- **Error Handling**:
  - **Rust**: Use `thiserror` and `#[derive(uniffi::Error)]` for all fallible APIs.
  - **Swift**: Managers propagate errors using `throws`; `BoardViewModel` catches them to update UI state.
  - **Display States**:
    1. **AI Engine Errors**: Displayed in `AIEngineLogView` (readable logs).
    2. **Non-AI Core Errors**: Displayed concisely in the engine message area via `model.engineMessage`.
    3. **GUI Errors**: Logged to the app console.
  - **L10n**: Always use `.localized` for user-facing error strings.

## Developing Environment
- **GitHub Repository**: `https://github.com/neolee/qidao`
- **Toolchain**:
  - Rust: `rustup` `cargo` `uniffi-bindgen`.
  - Swift: Xcode 16+ on macOS (Apple Silicon recommended).
- **Editor**: VS Code for Swift and Rust code generating and editing, Xcode for SwiftUI app building and debugging, `cargo` for Rust syntax checking, building and testing.
- **Workflow**:
  - **Swift-Rust Bridge**：Run `./build_core.sh` to build Rust `qidao-core`, generate Swift bindings and copy necessary file to the SwiftUI project.
  - **Build macOS App**: Open `QiDao.xcodeproj` in Xcode and run `Product > Build` (or `xcodebuild build`)
  - **Run App**: In Xcode, select QiDao scheme and run (⌘R); ensure KataGo engine path is configured for AI features
  - **Unit Tests**:
    - Rust: `cargo test` in `qidao-core/` for core logic tests; `cargo run --bin test-analysis` and so on for specific feature tests. 
    - Swift: *TBD*
    - **Integration Tests**: Manually run app and check features.
    - **CI Release**: `.github/workflows/release.yml` (automatically builds DMG for distribution and config Sparkle auto-update release).
  - **Test Rust Core**: several test scripts in `./qidao-core/src/bin`, can be extended when necessary.
  - **Performance Profiling**: Use Instruments.app for CPU/GPU spikes; focus on engine buffer draining and lock contention.
- **Settings**
  - **Xcode Settings** (for QiDao target):
    - Architectures: arm64 only (Apple Silicon).
    - Swift Language Version: 5.
    - App Sandbox: Disabled.
    - Strict Concurrency Checking: Minimal.
    - Default Actor Isolation: nonisolated.
    - Link Rust lib: Add `libqidao_core.a` to "Link Binary With Libraries".
  - **AI Engine**: Download KataGo binary/model; set path in app preferences. Test communication standalone via `cargo run --bin test-analysis` and `cargo run --bin test-gtp`.

## Architecture Overview
- **Layers**:
  - UI: SwiftUI views (e.g., `CenterView`, `VariationTreeView`).
  - State: `BoardViewModel` manages game state, engine life-cycle.
  - Core: Rust `qidao-core` handles SGF tree, rules, GTP/Analysis APIs via UniFFI.
- **Key Patterns**:
  - MVVM for Swift.
  - Async engine communication with Tokio in Rust.
  - High-performance rendering: SwiftUI `Canvas` for trees/boards.

## Boundaries
- **Always do**:
  - Keep code clean and modular, easy to understand and maintainable.
  - Update project progression in `MEMO.md` after user confirmation of major task completion.
  - Run `./build_core.sh` after any change in `qidao-core` source code.
  - L10n: Add to Localizable.strings before using new UI strings.
- **Ask before doing**:
  - Before modifying existing source code in a major way (i.e. more than 3 source files).
  - Change Xcode project settings.
- **Never do**:
  - Commit more than one major task in a single iteration.
  - Modify UniFFI generated bindings directly (files under `QiDao/QiDao/Core`), use `./build_core.sh` instead.
  - Use `cat` to create or edit files.

## Immediate TODOs and Phases
Refer to MEMO.md for detailed progress and plans. Current focus (Dec 29, 2025):
- Phase 12: Separate logs/comments into tabbed views.
- Phase 13: Implement multi-mode (Analysis/Edit/Play) with dynamic sidebars.
- Phase 14: Add advanced features like SGF export and game setup dialogs.

This document is a living reference—update as the project evolves. For contributions, prioritize TODOs and maintain macOS-native performance.
