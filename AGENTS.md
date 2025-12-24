# QiDao Project Status & Guidelines (AGENTS.md)

This document serves as a source of truth for AI agents working on the QiDao project. It tracks confirmed requirements, technical decisions, architecture, and progress.

## 1. Project Overview
QiDao (Tao of Go) is a modern Go (Weiqi) board editor and AI analysis tool, primarily for macOS, inspired by Lizzieyzy.

## 2. Technical Stack
- **UI Layer**: SwiftUI (macOS Native)
- **Core Logic Layer**: Rust (Targeted for `qidao-core`)
  - *Note*: The exact scope of Rust usage is under evaluation. Potential areas: SGF parsing, GTP/Analysis API orchestration, move validation.
- **Interoperability**: Swift-Rust bridging (TBD: UniFFI, Swift-Bridge, or C-FFI).

## 3. Directory Structure
- `QiDao/`: SwiftUI application source code.
- `qidao-core/`: Rust-based core logic and cross-platform components.
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

## 7. Immediate TODOs
1. **Analysis**: Determine the boundary between Swift and Rust.
2. **Setup**: Initialize the Rust library in `qidao-core`.
3. **SGF**: Implement basic SGF parsing in the core layer.
4. **UI**: Create a basic 19x19 board view in SwiftUI.
5. **Bridge**: Establish the communication channel between Swift and Rust.
