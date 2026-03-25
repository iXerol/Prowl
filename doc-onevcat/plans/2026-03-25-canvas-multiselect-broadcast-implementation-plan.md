# Canvas Multi-Select Broadcast Implementation Plan

**Goal:** Implement Canvas multi-card selection with direct broadcast input, including committed-text IME fan-out, while preserving current single-card behavior when multi-select is inactive.

**Scope:**
- In:
  - Canvas-local multi-selection state and transitions
  - Cmd+Click selection across full card area
  - Primary vs follower selected styling
  - Broadcast of committed text plus a small set of normalized special keys
  - Whitelisted Cmd+key broadcast (Cmd+Backspace, Cmd+Arrow)
  - Cmd+V paste broadcast via pasteboard string
  - Cmd+Opt+A select all, Escape to clear
  - Per-card selection shield during broadcasting
  - IME-safe follower behavior using committed text only
  - Tests for selection state transitions and input normalization/filtering
- Out:
  - Mouse broadcast
  - Full TUI parity for all applications
  - Follower-side IME candidate/preedit UI

**Architecture:**
- Keep selection state local to Canvas as `@State var selectionState = CanvasSelectionState()`.
- Add a transparent selection shield so Cmd+Click works across the whole card, including terminal content. Shield visibility is per-card during broadcasting (follower cards keep shield, primary does not).
- Keep one primary card as the real first responder; mirror input from it to follower cards.
- Use `NSEvent.modifierFlags` for immediate Cmd detection in tap handlers (bypasses `CommandKeyObserver`'s 300ms hold delay).
- Introduce `MirroredTerminalKey` (Sendable) for normalized key replay with a Cmd-key whitelist.
- Treat IME specially: only committed text fans out; preedit stays primary-only.
- Broadcast paste content by reading `NSPasteboard.general` string in `paste()` and firing `onCommittedText`.

**Acceptance / Verification:**
- Cmd+Click anywhere on a card toggles selection.
- Non-Cmd click exits selection mode and returns to single-card interaction.
- Non-Cmd click on a follower during broadcasting promotes it to primary.
- Non-Cmd click on the primary during broadcasting passes through to terminal.
- Clicking blank canvas clears selection and focus.
- Escape clears broadcast selection.
- Cmd+Opt+A selects all visible cards.
- Multiple selected cards receive mirrored committed text.
- Cmd+V paste text is broadcast to followers.
- Cmd+Backspace and Cmd+Arrow are broadcast to followers.
- Followers receive committed Chinese/Japanese text, not phonetic intermediate input.
- Build passes and targeted tests pass.

## Task 1: Add pure Canvas selection state machine ✅

**Files:**
- Created: `supacode/Features/Canvas/Models/CanvasSelectionState.swift`
- Created: `supacodeTests/CanvasSelectionStateTests.swift`

**Delivered:**
- Pure `CanvasSelectionState` struct with `focusSingle`, `toggleSelection`, `setPrimary`, `selectAll`, `beginBroadcastInteractionIfNeeded`, `clear`, `prune`.
- 10 tests covering all state transitions.

## Task 2: Integrate selection model into CanvasView ✅

**Files:**
- Modified: `supacode/Features/Canvas/Views/CanvasView.swift`

**Delivered:**
- Replaced `focusedTabID` with `selectionState: CanvasSelectionState`.
- `mutateSelection` helper centralizes state mutation, pruning, focus sync, and callback sync.
- z-order respects primary > selected > unselected.

## Task 3: Add selected/follower visuals and selection shield hooks ✅

**Files:**
- Modified: `supacode/Features/Canvas/Views/CanvasCardView.swift`

**Delivered:**
- Primary: 2pt accent border. Follower: 1.5pt accent at 65% opacity + background tint.
- `selectionShield` overlay intercepts clicks via `onSelectionTap`.
- Resize handles hidden when shield is active.
- Terminal hit testing: `allowsHitTesting(isFocused && !showsSelectionShield)`.

## Task 4: Wire Cmd+Click anywhere on card ✅

**Files:**
- Modified: `supacode/Features/Canvas/Views/CanvasView.swift`
- Modified: `supacode/Features/Canvas/Views/CanvasCardView.swift`

**Delivered:**
- `showsSelectionShield(for:)` is per-card: all cards during `Cmd`/selecting; only followers during broadcasting.
- `onTap` checks `NSEvent.modifierFlags.contains(.command)` directly for reliable Cmd detection (bypasses 300ms observer delay).
- `handleSelectionShieldTap` dispatches to `toggleSelection`, `setPrimary`, or `focusSingle` based on Cmd state and broadcasting state.
- Blank-canvas click clears selection.

## Task 5: Add normalized mirrored-key model ✅

**Files:**
- Created: `supacode/Infrastructure/Ghostty/MirroredTerminalKey.swift`
- Created: `supacodeTests/MirroredTerminalKeyTests.swift`

**Delivered:**
- `MirroredTerminalKey: Equatable, Sendable` with kinds: enter, backspace, deleteForward, arrows, tab, escape, controlCharacter.
- Stores `modifierFlagsRawValue: UInt` for Sendable (computed `modifiers` property).
- `commandAllowedKeyCodes` whitelist: Cmd+Backspace (51), Cmd+Arrow (123–126). All other Cmd combos rejected.
- 6 tests covering normalization, Cmd filtering, whitelist, and plain-text rejection.

## Task 6: Add Ghostty broadcast hooks and safe follower APIs ✅

**Files:**
- Modified: `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`

**Delivered:**
- `onCommittedText` callback: fires in `insertText()` and in `paste()` (reads pasteboard string).
- `onMirroredKey` callback: fires in `keyDown()` for normalized keys.
- `insertCommittedTextForBroadcast(_:)`: writes UTF-8 text via `ghostty_surface_text`.
- `applyMirroredKeyForBroadcast(_:)`: replays NSEvent via `keyDown`/`keyUp` without stealing responder.

## Task 7: Add tab-scoped terminal broadcast helpers ✅

**Files:**
- Modified: `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- Modified: `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`

**Delivered:**
- `WorktreeTerminalState.insertCommittedText(_:in:)` and `applyMirroredKey(_:in:)`.
- `WorktreeTerminalManager.stateContaining(tabId:)` lookup.
- `broadcastCommittedText` / `broadcastMirroredKey` fan-out methods with `@discardableResult` return count.
- Debug logging via `SupaLogger` for broadcast failures.

## Task 8: Connect primary-card input to follower broadcast ✅

**Files:**
- Modified: `supacode/Features/Canvas/Views/CanvasView.swift`

**Delivered:**
- `syncBroadcastCallbacks` sets `onCommittedText`/`onMirroredKey` on primary surface's leaves only when broadcasting.
- `clearBroadcastCallbacks` nils out all callbacks on all surfaces.
- Callbacks use explicit capture list with `beginBroadcast` closure for safe `selectionState` mutation.
- Callbacks re-sync after split operations on primary card.
- Callbacks sync on `onAppear`, `onChange(allCardKeys)`, `onChange(allTabIDs)`, `mutateSelection`, `pruneSelection`, `deactivateCanvas`.

## Task 9: Add Canvas keyboard shortcuts and toolbar ✅

**Files:**
- Modified: `supacode/Features/Canvas/Views/CanvasView.swift`

**Delivered:**
- `.onKeyPress(.escape)`: clears selection when broadcasting.
- `.onKeyPress("a", phases: .down)` with `keyPress.modifiers == [.command, .shift]`: selects all cards.
- Toolbar: select-all button + broadcasting badge + arrange + organize.

## Task 10: Polish and verification ✅

**Delivered:**
- Fixed reversed canvas scroll direction (removed incorrect delta negation in `CanvasScrollContainerView`).
- Fixed unsafe `selectionState` capture in broadcast callbacks.
- Made `MirroredTerminalKey` Sendable via raw UInt storage.
- Added Cmd+Backspace/Arrow whitelist.
- Added Cmd+V paste broadcast.
- All tests pass. Build passes. Lint passes.
- Design and implementation plan docs updated to match final implementation.
