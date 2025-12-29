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
2. **Application State (Swift)**: ViewModel layer, managing engine life-cycle and UI state.
3. **UI (SwiftUI)**: View layer, high-performance board rendering.

## 6. Project Progress
- [x] Initial requirements defined ([init-spec.md](init-spec.md)).
- [x] Requirements updated with AI Analysis API, Variation Tree, and GPU acceleration.
- [x] Project structure initialized with `QiDao/` and `qidao-core/`.
- [x] **Swift-Rust Bridge**: Confirmed UniFFI as the bridging solution.
- [x] **Core Setup**: Initialized Rust library in `qidao-core` with UniFFI support.
- [x] **GUI Prototype**: Created basic `CenterView` and `BoardViewModel` in SwiftUI.
- [x] **Core Integration**: Built Rust static library and generated Swift bindings; integrated into Xcode with a modular `qidao_coreFFI` structure.
- [x] **SGF Parsing**: Implemented basic SGF parsing in Rust using `sgf-parse` 4.2 and exported via UniFFI.
- [x] **GUI Framework**: Built interactive `CenterView` and `BoardViewModel` in SwiftUI, supporting stone placement, real-time board updates, and a three-column layout with theme support.
- [x] **SGF Navigation & Persistence**: Implemented `Game` controller in Rust for tree navigation and branch management. Added SGF loading and saving functionality with macOS file picker integration.

## 7. Technical Notes & Best Practices
### Xcode Build Settings for UniFFI
To avoid concurrency warnings and architecture mismatches (e.g., "symbol(s) not found for architecture x86_64"), use the following settings in the Xcode target:
- **Architectures**: `arm64` (Restricted to Apple Silicon to match Rust core build)
- **Default Actor Isolation**: `nonisolated`
- **Strict Concurrency Checking**: `Minimal` (or `Targeted`)
- **Swift Language Version**: `5`

### Variation Tree Implementation
- **Rendering**: Uses SwiftUI `Canvas` (GraphicsContext) for high-performance drawing. This avoids the overhead of thousands of individual `View` objects in large SGF trees.
- **Auto-Positioning**: Implemented `centerCurrentNode` logic. It calculates the coordinate of the active node and updates the `offset` of the tree container. Triggered via `onChange(of: viewModel.currentNodeId)`.
- **Navigation**: Supports global "Jump to Move". The Rust core performs a DFS search across all branches to find the first occurrence of a specific move number, allowing navigation outside the current branch.

### Focus & Keyboard Shortcuts
- **Global Shortcuts**: Keyboard listeners (`.onKeyPress`) are attached to the root `HSplitView` to ensure they capture events regardless of which sub-view is active.
- **Delete Command**: Use `.onDeleteCommand` instead of raw `.onKeyPress` for the Delete/Backspace key. This is the standard macOS way to handle deletion and avoids system beeps or conflicts with text input.
- **Focus Restoration**: SwiftUI focus can be lost when a focused element (like an inline `TextField`) is removed from the hierarchy. We use `@FocusState` combined with `DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)` to explicitly restore focus to the main container after operations like "Jump to Move" or closing dialogs.

### AI Engine Performance & Stability
- **Concurrency Model**: Rust core uses independent `Arc<Mutex<Option<...>>>` for `stdin`, `stdout`, and `stderr`. This prevents `get_next_result` (reading) from blocking `analyze` (writing), eliminating deadlocks during high-frequency navigation.
- **Buffer Management**: The `analyze` method in Rust automatically drains the `stdout` buffer before sending a new query. This prevents "Backlog Spin" where the GUI wastes CPU parsing thousands of obsolete JSON results from previous board states.
- **Lifecycle Control**: The GUI explicitly sends `terminate_all` when reaching `maxVisits` or switching moves. This forces KataGo to drop pending GPU batches and clear its internal queue immediately.
- **Logging Optimization**: Communication logs (`>>>`/`<<<`) are truncated to 500 chars in the core and completely skipped (including string formatting/serialization) when `logging_enabled` is false.

### SwiftUI State Management & UI Updates
- **Avoiding "Publishing changes from within view updates"**: When binding a `@Published` property from a ViewModel to a SwiftUI control (like `Picker` or `Toggle`), it may trigger a state change during the view's rendering cycle, leading to runtime warnings or undefined behavior. 
  - **Solution**: Use a custom `Binding` to wrap the property. In the `set` block, perform the update inside `DispatchQueue.main.async`.
  - **Example**:
    ```swift
    private var modeBinding: Binding<AppMode> {
        Binding(
            get: { viewModel.appMode },
            set: { newValue in
                DispatchQueue.main.async {
                    viewModel.appMode = newValue
                }
            }
        )
    }
    ```

## 8. Immediate TODOs

1. **Multi-Mode Support**: Implement `AppMode` (Analysis, Edit, Play) with dynamic sidebars.
2. **Edit Mode**: Add/remove stones and notations (Triangle, Circle, Square, Cross, Label), export to SGF.
3. **Gameplay**: Implement Human-vs-AI (Play against Engine) mode with handicap and komi settings.
4. **SGF Comments**: Display and edit node comments in the sidebar.
5. **AI Play UX Refinement**:
    - Move play-mode console logs to `AIEngineLogView`.
    - Add `AIEngineLogView` to Play mode sidebar.
    - Redesign engine message and log display for consistency and localization.
    - Disable AI analysis and play in Edit mode.

## 9. Implementation Plan (Dec 29, 2025)

### Phase 13: Multi-Mode Support
- **AppMode State**: Define `AppMode` enum in `BoardViewModel` and implement a `Segmented Picker` in the top toolbar for switching.
- **Dynamic Sidebars**:
    - **Left Sidebar**: 
      - Common: `GameInfoView` at the top, and
      - Analysis Mode: `WinRateView`, `AIEngineView`, `AIEngineLogView`, `GameCommentView`.
      - Edit Mode: `EditToolboxView`.
      - Play Mode: `PlayControlView`.
    - **Right Sidebar**:
      - Common: `VariationTreeView` at the top, and
      - Analysis Mode: `MoveEvaluationView`, `EvaluationBoardView`.
      - Edit Mode: `GameCommentView`.
      - Play Mode: `PlayLogView`.
- **Edit Mode Logic**:
    - Implement tools for placing stones (Black, White, Auto) and marks (TR, CR, SQ, MA, LB).
    - Update Rust core to handle SGF property updates for marks and comments.
- **Play Mode Logic**:
    - Disable all AI overlays and real-time analysis.
    - Implement `genmove` flow: Player moves -> Engine generates move -> Update board.
    - Add game controls: Pass, Resign, Score, Undo.
    - **UX Refinement (Dec 30)**:
        - Integrate `AIEngineLogView` into the Play mode sidebar (left).
        - Redirect useful play-mode logs (e.g., "AI is thinking", "Found move") from console to `AIEngineLogView`.
        - Redesign `AIEngineView`'s message area for better consistency and localization.
        - Filter analysis logs to show only high-value information.

### Phase 14: Advanced Edit & Play Features
- **SGF Export**: Support exporting the current tree (including marks and comments) to SGF string/file.
- **Game Setup**: Implement a "New Game" dialog for Play Mode to set board size, handicap, and komi.
- **Clock System**: (Optional) Add basic timing support for Play Mode.

## 10. Progress Log
- [x] **Phase 1: Board Logic & Rules**: Implemented `Board` struct in Rust with capture logic, suicide prevention, and simple Ko rule. Exported to Swift via UniFFI.
- [x] **Phase 2: UI/UX Foundation**: Refined 3D stone visuals, sound effects system, and multi-language support. Fixed sandbox-related permission issues.
- [x] **Phase 3: Variation Tree & Navigation**: Implemented graphical variation tree using `Canvas`, keyboard-based branch switching, and optimized sound feedback. Added global "Jump to Move" with inline UI and focus management.
- [x] **Phase 4: AI Engine Integration (Core)**: Implemented `GtpEngine` and `AnalysisEngine` in Rust. Added support for KataGo Analysis API with JSON-based queries. Verified with standalone test tools.
- [x] **Phase 5: AI UI Integration**: Integrated `AnalysisEngine` into `BoardViewModel`. Added real-time win rate analysis, score lead display, and AI suggested moves overlay on the board. Implemented engine lifecycle management and localization.
- [x] **Bug Fix: AI Engine Stability**: Resolved KataGo startup issues (missing model path, log directory permissions) and coordinate format errors (SGF vs GTP). Fixed SwiftUI `ProgressView` layout crashes by using custom drawing.
- [x] **Bug Fix: Tokio Runtime Integration**: Resolved "no reactor running" and "future not Send" errors by implementing a global Tokio runtime and using `spawn` to ensure async operations run in the correct context.
- [x] **Phase 6: AI UI Refinement & Visualization**: Refined AI move markers with transparency and rank styling. Implemented dynamic Win Rate Graph with history persistence. Added PV preview on hover and stabilized sidebar layouts to prevent flickering. Optimized variation marker visibility.
- [x] **Phase 7: Core Optimization & Evaluation Board**: Refactored Rust engine locks for zero-latency navigation. Implemented "Evaluation Board" (mini-board) with grayscale ownership map and PV sequence. Added centralized logging control and buffer draining to prevent CPU spikes.
- [x] **Phase 8: Branch Management & UX Refinement**: Implemented "Delete Current Branch" with confirmation dialog. Optimized file dialogs to be non-blocking and path-aware. Synchronized and cleaned up localization files. Refined keyboard focus and shortcut handling using `.onDeleteCommand`.
- [x] **Phase 9: Sparkle Integration & CI/CD**: Integrated Sparkle framework for auto-updates. Configured GitHub Actions for automated release creation, DMG packaging, and appcast generation. Added "Check for Updates" menu item and configured `Info.plist` keys.
- [x] **Phase 10: 13x13 and 9x9 Board Support**.
- [x] **Phase 11: Refactoring and Enhancements**: Improved code organization in views and view model. Win rate graph and ownership map toggles, incremental full game analysis, etc.
- [x] **Phase 12: View Improvement**: Separated logs and comments into a tabbed view; implemented `GameCommentView` for SGF comment editing.
- [x] **Bug Fix: AI Play Logic (Dec 30)**: Fixed AI "double-playing" or playing on wrong turns during navigation by implementing `initialPlayer` tracking and node-ID validation before applying AI moves.
