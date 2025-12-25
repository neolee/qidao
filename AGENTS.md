# QiDao Project Status & Guidelines (AGENTS.md)

This document serves as a source of truth for AI agents working on the QiDao project. It tracks confirmed requirements, technical decisions, architecture, and progress.

## 1. Project Overview
QiDao (Tao of Go) is a modern Go (Weiqi) board editor and AI analysis tool, primarily for macOS, inspired by Lizzieyzy.

## 2. Technical Stack
- **UI Layer**: SwiftUI (macOS Native)
- **Core Logic Layer**: Rust (`qidao-core`)
  - **Scope**: SGF parsing & tree management, GTP/Analysis API orchestration, Go rules engine (validation, capture logic).
- **Interoperability**: **UniFFI** (Swift-Rust bridging).
  - **Status**: Initialized with proc-macro support and Swift binding generation.

## 3. Directory Structure
- `QiDao/`: SwiftUI application source code.
- `qidao-core/`: Rust-based core logic.
  - `src/lib.rs`: Main entry point for UniFFI exports.
  - `src/bin/uniffi-bindgen.rs`: CLI tool for generating bindings.
  - `out/`: Generated Swift/C bindings.
- `screens/`: UI reference images.
- `init-spec.md`: Detailed functional and non-functional requirements.

## 4. Key Confirmed Requirements
- **SGF Handling**: Full support for SGF tree, editing, and saving.
- **AI Integration**: 
  - Support for GTP and KataGo Analysis API.
  - Real-time analysis, win-rate graphs, and blunder detection.
- **UI/UX**:
  - Modern macOS native look and feel.
  - Graphical Variation Tree visualization.
  - GPU-accelerated board rendering (60/120fps).
  - **Localization**: Architecture must support i18n; Chinese-only for the initial phase.
- **Performance**: Multi-threaded engine communication, low latency.

## 5. Architecture Design
1. **Core Logic (Rust)**: SGF Tree, Rules Engine, Engine Communication.
2. **Application State (Swift)**: ViewModel layer, managing engine lifecycle and UI state.
3. **UI (SwiftUI)**: View layer, high-performance board rendering.

## 6. Project Progress
- [x] Initial requirements defined ([init-spec.md](init-spec.md)).
- [x] Requirements updated with AI Analysis API, Variation Tree, and GPU acceleration.
- [x] Project structure initialized with `QiDao/` and `qidao-core/`.
- [x] **Swift-Rust Bridge**: Confirmed UniFFI as the bridging solution.
- [x] **Core Setup**: Initialized Rust library in `qidao-core` with UniFFI support.
- [x] **GUI Prototype**: Created basic `BoardView` and `BoardViewModel` in SwiftUI.
- [x] **Core Integration**: Built Rust static library and generated Swift bindings; integrated into Xcode with a modular `qidao_coreFFI` structure.
- [x] **SGF Parsing**: Implemented basic SGF parsing in Rust using `sgf-parse` 4.2 and exported via UniFFI.
- [x] **GUI Framework**: Built interactive `BoardView` and `BoardViewModel` in SwiftUI, supporting stone placement, real-time board updates, and a three-column layout with theme support.
- [x] **SGF Navigation & Persistence**: Implemented `Game` controller in Rust for tree navigation and branch management. Added SGF loading and saving functionality with macOS file picker integration.

## 7. Technical Notes & Best Practices
### Xcode Build Settings for UniFFI
To avoid concurrency warnings (e.g., "call to main actor-isolated static method 'lift' in a synchronous nonisolated context") in generated UniFFI code, use the following settings in the Xcode target:
- **Default Actor Isolation**: `nonisolated`
- **Strict Concurrency Checking**: `Minimal` (or `Targeted`)
- **Swift Language Version**: `5`

## 8. Immediate TODOs
1. **UI**: Implement Variation Tree visualization (graphical view of branches).
2. **Engine**: Implement basic GTP communication in Rust for AI analysis.
3. **UI**: Add AI analysis overlay on the board (win rates, suggested moves).

## 9. Progress Log
- [x] **Phase 1: Board Logic & Rules**: Implemented `Board` struct in Rust with capture logic, suicide prevention, and simple Ko rule. Exported to Swift via UniFFI.
- [x] **Phase 2: UI/UX Foundation**: Refined 3D stone visuals, sound effects system, and multi-language support. Fixed sandbox-related permission issues.

