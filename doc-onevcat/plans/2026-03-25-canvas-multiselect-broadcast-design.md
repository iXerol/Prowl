# Canvas Multi-Select and Broadcast Input Design

## Goal

Let Canvas select multiple cards and send the same user input to all selected cards, with a strong emphasis on:

- natural multi-card selection on macOS (`Cmd+Click`)
- direct typing into Canvas without a separate batch-input textbox
- correct non-English input behavior
- preserving current single-card interaction when multi-select is not active

This design targets the two main user scenarios discussed:

1. Open multiple cards backed by different agents and send the same prompt to compare results.
2. Operate multiple remote SSH sessions and apply the same command/configuration to all of them.

---

## Non-Goals

This design does **not** try to make multiple terminals behave like a perfectly synchronized remote desktop.

Out of scope for v1:

- broadcasting mouse interactions to multiple cards
- broadcasting search UI, text selection, or context menus
- mirroring IME candidate windows/preedit UI to follower cards
- guaranteeing perfect behavior for all full-screen TUIs (`vim`, `fzf`, `less`, `top`, etc.)
- changing sidebar multi-selection or worktree detail selection behavior outside Canvas

---

## Current Architecture Summary

Canvas today is fundamentally a **single-focus** experience:

- `CanvasView` stores a single `focusedTabID`.
- `CanvasCardView` only allows terminal hit testing when the card is focused.
- Canvas exit behavior uses the focused canvas card to decide which worktree/tab to return to.
- Terminal command routing is mostly **worktree-scoped**, while Canvas cards are effectively **tab-scoped**.

Relevant current implementation points:

- `supacode/Features/Canvas/Views/CanvasView.swift`
- `supacode/Features/Canvas/Views/CanvasCardView.swift`
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`
- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`
- `supacode/App/CommandKeyObserver.swift`

Important constraints from current code:

1. A card maps to a **tab**, not only a worktree.
2. Input routing for active terminals depends on the focused `GhosttySurfaceView`.
3. `GhosttySurfaceView` already supports AppKit IME (`NSTextInputClient`) and distinguishes:
   - marked/preedit text (`setMarkedText` / `syncPreedit`)
   - committed text (`insertText`)
4. `CommandKeyObserver` already exists app-wide and can be reused to drive `Cmd`-based selection affordances.

---

## User Experience Design

## High-Level Model

Canvas supports:

- **primary focus**: the card that owns the real first responder and drives local input/IME
- **multi-selection**: zero, one, or many selected cards
- **selection mode**: a temporary click-interpretation mode entered by `Cmd+Click`

The key distinction is:

- **focus** decides where real AppKit/Ghostty input originates
- **selection** decides which cards receive mirrored input

These are related but not identical.

---

## Selection Rules

### Entering selection mode

- `Cmd+Click` on any unselected card region enters selection mode.
- The clicked card is added to selection.
- The clicked card becomes the **primary selected card**.

"Any card region" includes the terminal content area, not only the title bar.

### While selection mode is active

- `Cmd+Click` on an unselected card adds it to selection.
- `Cmd+Click` on a selected card removes it from selection.
- If removal leaves one selected card, Canvas may stay visually selected but effectively returns to single-card behavior.
- Clicking empty canvas clears selection and exits selection mode.

### Select all

- `Cmd+Opt+A` selects all visible cards for broadcast.
- A toolbar button provides the same action with tooltip showing the hotkey.
- If a primary card already exists, it is preserved; otherwise the last visible card becomes primary.

### While broadcasting (multiple cards selected, mode idle)

When multiple cards are selected and the user has begun typing (mode transitions from `.selecting` to `.idle`), the following behaviors apply:

- **Non-Cmd click on a follower card**: promotes it to primary without clearing multi-selection.
- **Non-Cmd click on the primary card**: passes through to the terminal (shield is not shown on primary during broadcasting).
- **Non-Cmd click on an unselected card**: clears multi-selection and focuses that single card.
- **`Cmd+Click`**: toggles selection as usual.
- **`Escape`**: clears all selection and exits broadcast mode.

### Leaving selection mode

The mode should be intentionally short-lived and should end on the first normal interaction.

- Any **non-Command keyboard input** when multiple cards are selected:
  - exits the pure selection state
  - immediately becomes a broadcast-input interaction
- Clicking empty canvas:
  - clears all selected cards
  - clears primary focus in Canvas (0-selection is allowed)

This keeps selection lightweight and avoids sticky modifier-heavy behavior.

---

## Focus and Primary Card Semantics

When multiple cards are selected, exactly one selected card is still the **primary** card.

The primary card is responsible for:

- owning the real first responder
- owning the visible IME composition/preedit state
- serving as the source of mirrored input
- deciding the worktree/tab used when exiting Canvas back to the normal terminal view

Selection without a primary card is invalid.

If the primary card is removed from selection:

- pick the most recently added remaining selected card as the new primary, or
- if that history is unavailable, pick a deterministic fallback (e.g. the last card toggled on)

---

## Visual Design

### Selected card styling

Cards have two visual states:

- **primary focused/selected** card: 2pt accent-colored focus ring
- **follower selected** cards: 1.5pt accent ring at 65% opacity + subtle background tint

### Broadcast hint

When more than one card is selected, a capsule badge appears in the bottom-right toolbar:

- `Broadcasting to N cards`

This is informational only, not a dedicated text entry field.

A separate textbox is intentionally rejected because it makes the interaction feel unlike a terminal.

### Toolbar

The canvas toolbar (bottom-right) contains:

- **Select All** button (`checkmark.rectangle.stack` icon) — tooltip: "Select all cards for broadcast (⌘⌥A)"
- **Arrange** button — preserves card sizes
- **Organize** button — uniform grid layout

---

## Input Behavior Design

## Core Principle

When multiple cards are selected, the user still types **once** into the primary card.
Canvas mirrors that input to follower cards.

This should feel like:

- one real terminal under the cursor
- N-1 follower terminals receiving mirrored input

---

## IME / Non-English Input Behavior

This is the most important rule:

> Followers must receive committed characters/words, not the phonetic keystrokes used to compose them.

Examples:

- Chinese Pinyin input should mirror `你好`, not `nihao`
- Japanese input should mirror committed kana/kanji text, not unfinished romaji sequences

### IME behavior in v1

#### Primary card

The primary card handles the full native IME lifecycle as it does today:

- marked text / preedit
- candidate window
- commit
- cancel

#### Follower cards

Follower cards do **not** render IME preedit/candidate UI.
They receive only the final committed text.

That means:

- while the user is composing, followers may show no change yet
- once composition commits, followers receive the committed string immediately

This is the intended design, not a degradation.
It is the safest way to guarantee that non-English input remains semantically correct.

---

## Broadcast Categories

Input fan-out is split into two classes.

### 1. Committed text broadcast

Used for:

- English text input that arrives as text
- committed IME text
- pasted text (Cmd+V: after Ghostty handles the paste binding in `performKeyEquivalent`, reads `NSPasteboard.general` string and fires `onCommittedText`)

Behavior:

- take the committed string from the primary card
- insert the same committed string into each follower card

### 2. Normalized special-key broadcast

Used for:

- `Enter`
- `Backspace` / `Delete`
- arrow keys (`↑ ↓ ← →`)
- `Tab`
- `Escape`
- common shell control keys (for example `Ctrl-C`, `Ctrl-D`, `Ctrl-L`)
- `Cmd+Backspace` (delete line)
- `Cmd+Arrow` keys (line/word navigation)

Behavior:

- normalize the originating primary-card key event into a small mirror-safe model
- replay that normalized input on followers

### Whitelisted Cmd combinations

A static whitelist (`commandAllowedKeyCodes`) controls which Cmd+key combinations pass through. Currently allowed:

- `Cmd+Backspace` (keyCode 51)
- `Cmd+Arrow Left/Right/Down/Up` (keyCodes 123–126)

All other Cmd combinations are filtered out.

### Explicitly excluded from broadcast

Do not broadcast:

- `Cmd` shortcuts not in the whitelist (e.g. `Cmd+C`, `Cmd+W`, `Cmd+Q`)
- menu shortcuts
- window/app commands
- mouse events
- IME marked/preedit updates

This keeps the feature aligned with terminal input rather than app control.

---

## Implementation Design

## 1. Canvas Selection State

Selection state lives in `CanvasView` as `@State private var selectionState = CanvasSelectionState()`.

`CanvasSelectionState` is a pure value type with:

```swift
struct CanvasSelectionState: Equatable {
  enum Mode: Equatable { case idle, selecting }

  private(set) var mode: Mode
  private(set) var selectedTabIDs: Set<TerminalTabID>
  private(set) var primaryTabID: TerminalTabID?
  private(set) var selectionOrder: [TerminalTabID]

  var isSelecting: Bool    // mode == .selecting
  var isBroadcasting: Bool // selectedTabIDs.count > 1

  mutating func focusSingle(_ tabID: TerminalTabID)
  mutating func toggleSelection(_ tabID: TerminalTabID)
  mutating func setPrimary(_ tabID: TerminalTabID)
  mutating func selectAll(_ tabIDs: [TerminalTabID])
  mutating func beginBroadcastInteractionIfNeeded()
  mutating func clear()
  mutating func prune(to visibleTabIDs: Set<TerminalTabID>)
}
```

### Why keep this in `CanvasView` for v1

The behavior is Canvas-local and highly UI-driven.
There is no strong need to move it into TCA reducer state yet.

The pure `CanvasSelectionState` struct makes the transition logic fully testable without SwiftUI.

---

## 2. Cmd+Click Anywhere on a Card

### Problem

Today the focused terminal content receives hit testing, which means the terminal area would normally steal clicks.
A title-bar-only approach is not acceptable.

### Implemented solution: selection shield overlay + per-card visibility

When either of the following is true:

- `CommandKeyObserver.isPressed == true`, or
- `selectionMode == .selecting`

Canvas places a transparent hit-testing layer over every visible card.

Additionally, during **broadcasting** (multiple cards selected, mode idle):

- follower cards keep the shield (intercept clicks for `setPrimary` behavior)
- the primary card does **not** show the shield (allows terminal click-through)

This is computed per-card via `showsSelectionShield(for: TerminalTabID) -> Bool`.

### Cmd key detection

**Important**: `CommandKeyObserver` has a 300ms hold delay (designed for shortcut hints UI). This means the shield may not render in time for fast Cmd+Click.

To handle this, `onTap` and `handleSelectionShieldTap` read `NSEvent.modifierFlags.contains(.command)` directly from hardware state, bypassing the observer's delay. The observer is still used for shield rendering (a brief visual delay is acceptable).

---

## 3. Make Broadcast Tab-Scoped, Not Worktree-Scoped

Current terminal commands are mostly scoped by `Worktree`.
Canvas cards are scoped by `TerminalTabID`.

### Tab-targeted helpers on `WorktreeTerminalState`

```swift
func insertCommittedText(_ text: String, in tabId: TerminalTabID) -> Bool
func applyMirroredKey(_ key: MirroredTerminalKey, in tabId: TerminalTabID) -> Bool
```

### Lookup and broadcast helpers on `WorktreeTerminalManager`

```swift
func stateContaining(tabId: TerminalTabID) -> WorktreeTerminalState?
func broadcastCommittedText(_ text: String, from: TerminalTabID, to: Set<TerminalTabID>) -> Int
func broadcastMirroredKey(_ key: MirroredTerminalKey, from: TerminalTabID, to: Set<TerminalTabID>) -> Int
```

Broadcast failures are logged via `SupaLogger` for debugging.

---

## 4. Broadcast Hooks on `GhosttySurfaceView`

### Callbacks

```swift
var onCommittedText: ((String) -> Void)?
var onMirroredKey: ((MirroredTerminalKey) -> Void)?
```

- `onCommittedText` fires in `insertText()` after text is committed, and in `performKeyEquivalent` after Ghostty handles a Cmd+V binding.
- `onMirroredKey` fires in `keyDown()` when the event normalizes to a `MirroredTerminalKey`.

Note: A separate `onPasteText` callback was considered but rejected. Paste is handled by firing `onCommittedText` from `performKeyEquivalent` after Ghostty processes the Cmd+V binding. The `paste(_ sender:)` IBAction is not used because Cmd+V is intercepted by Ghostty's binding system before reaching the responder chain's paste action.

### `MirroredTerminalKey`

```swift
struct MirroredTerminalKey: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case enter, backspace, deleteForward
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case tab, escape, controlCharacter
  }

  let kind: Kind
  let keyCode: UInt16
  let characters: String
  let charactersIgnoringModifiers: String
  let modifierFlagsRawValue: UInt  // raw UInt for Sendable conformance
  let isRepeat: Bool

  var modifiers: NSEvent.ModifierFlags { ... }  // computed from raw value
}
```

The struct stores `modifierFlagsRawValue` (raw `UInt`) instead of `NSEvent.ModifierFlags` to satisfy `Sendable` conformance, since callbacks cross async boundaries via `Task { @MainActor in }`.

A static whitelist (`commandAllowedKeyCodes`) allows specific Cmd+key combinations through; all other Cmd events return `nil` from the initializer.

---

## 5. Safe Follower Insertion APIs

```swift
func insertCommittedTextForBroadcast(_ text: String)
func applyMirroredKeyForBroadcast(_ key: MirroredTerminalKey) -> Bool
```

- `insertCommittedTextForBroadcast(_:)` writes committed UTF-8 text directly to the surface via `ghostty_surface_text`.
- `applyMirroredKeyForBroadcast(_:)` replays a normalized key on the target surface via `keyDown`/`keyUp` without making it the app first responder.

Follower cards **never** steal first responder during broadcast. The primary card remains the real focused AppKit responder.

---

## 6. Event Flow

### A. Multi-select click flow

1. User holds `Cmd`.
2. Canvas enables selection shield overlays (may have up to 300ms delay from observer).
3. User clicks any card region.
4. `onTap` or `onSelectionTap` fires; both check `NSEvent.modifierFlags.contains(.command)` for reliable detection.
5. Canvas toggles that `tabID` in `selectedTabIDs`.
6. Canvas updates `primaryTabID` if needed.
7. Ghostty does not consume that click.

### B. Click during broadcasting (multiple cards selected)

1. User clicks a follower card without `Cmd`.
2. Follower card has selection shield (per-card shield logic).
3. `handleSelectionShieldTap` detects `isBroadcasting` and the card is selected.
4. Canvas calls `setPrimary` — promotes the clicked card to primary without clearing multi-selection.
5. If the user clicks the **primary** card (no shield), the click passes through to the terminal.

### C. IME composition on primary card

1. User types with IME on the primary card.
2. Primary card receives `setMarkedText(...)` and updates preedit locally.
3. No follower update happens yet.
4. User commits a candidate.
5. Primary card receives `insertText(...)` with committed text.
6. `onCommittedText` callback fires, broadcasting committed string to followers.

### D. Paste broadcast (Cmd+V)

1. User presses Cmd+V on the primary card.
2. `performKeyEquivalent` detects Cmd+V has a Ghostty binding, calls `keyDown(with: event)`.
3. Ghostty internally performs `paste_from_clipboard` and writes clipboard content to the primary surface.
4. After `keyDown` returns, `performKeyEquivalent` reads `NSPasteboard.general.string(forType: .string)` and fires `onCommittedText`.
4. Broadcast callbacks mirror the pasted text to all follower cards.

### E. Enter key broadcast

1. Primary card receives Enter.
2. Primary card submits normally.
3. `onMirroredKey` emits `.enter` mirrored key.
4. Followers receive `.enter` via `applyMirroredKeyForBroadcast`.

---

## 7. Interaction With Existing Canvas Exit Behavior

Current Canvas exit uses the focused canvas card to decide which worktree/tab to restore.
That continues to use the **primary selected card** via `canvasFocusedWorktreeID`.

Rules:

- if multiple cards are selected, exiting Canvas returns to the primary card's owning worktree/tab
- if selection was cleared and no primary remains, Canvas exits to the prior normal fallback behavior
- clicking empty canvas may leave Canvas with 0 selection and 0 focused card; this is acceptable

---

## Alternatives Considered

## Rejected: title-bar-only multi-select

Rejected because users must be able to select from the terminal area too.
In Canvas, the card is the object, not only its title bar.

## Rejected: dedicated batch-input textbox

Rejected because it makes terminal broadcast feel indirect and unlike the rest of Prowl.
Direct typing is the intended interaction.

## Rejected: full raw-event mirroring for IME

Rejected because it would risk propagating phonetic composition keys (`nihao`, romaji, etc.) instead of committed text.
Correct multilingual output is more important than perfect preedit mirroring.

## Rejected: separate `onPasteText` callback

Rejected because paste can be handled by firing `onCommittedText` from `paste()` after Ghostty completes the paste action. This avoids an extra callback and reuses the existing broadcast plumbing.

---

## Suggested File-Level Changes

### Primary feature files

- `supacode/Features/Canvas/Views/CanvasView.swift`
  - selection state (`CanvasSelectionState`)
  - selection-mode transitions via `mutateSelection`
  - broadcast callback setup/teardown via `syncBroadcastCallbacks`
  - broadcast status UI in toolbar
  - selection shield (per-card via `showsSelectionShield(for:)`)
  - `Cmd+Opt+A` select all, `Escape` to clear
  - `NSEvent.modifierFlags` for reliable Cmd detection in tap handlers

- `supacode/Features/Canvas/Views/CanvasCardView.swift`
  - selected/follower styling (border color, line width, background tint)
  - selection shield overlay (`onSelectionTap`)
  - normal terminal hit testing preserved outside selection/broadcast mode

### Selection model

- `supacode/Features/Canvas/Models/CanvasSelectionState.swift`
  - pure value type for selection transitions

### Terminal model / manager

- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
  - tab-scoped `insertCommittedText` and `applyMirroredKey`

- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`
  - `stateContaining(tabId:)` lookup
  - `broadcastCommittedText` / `broadcastMirroredKey` fan-out with debug logging

### Ghostty bridge

- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`
  - `onCommittedText` / `onMirroredKey` callbacks
  - `insertCommittedTextForBroadcast` / `applyMirroredKeyForBroadcast` follower APIs
  - paste broadcast via `onCommittedText` in `paste()`
  - IME preedit stays primary-only

- `supacode/Infrastructure/Ghostty/MirroredTerminalKey.swift`
  - normalized key model with `Sendable` conformance
  - `commandAllowedKeyCodes` whitelist for Cmd+Backspace/Arrow

---

## Verification Strategy

## Automated

### Pure selection-state tests (`CanvasSelectionStateTests`)

- `focusSingle` sets primary and clears selection mode
- `toggleSelection` enters selection mode and appends order
- toggling selected primary promotes previous selection
- toggling last selected card clears state
- `beginBroadcastInteraction` leaves selection set but exits selection mode
- `setPrimary` promotes follower without clearing selection
- `setPrimary` ignores unselected tab
- `selectAll` selects every tab and keeps existing primary
- `selectAll` from empty picks last tab
- `prune` drops missing tabs and preserves newest visible primary

### Mirrored key tests (`MirroredTerminalKeyTests`)

- Enter event normalizes correctly
- Command-modified events are filtered out (e.g. Cmd+C returns nil)
- Cmd+Backspace is allowed through whitelist
- Cmd+Arrow is allowed through whitelist
- Control character event normalizes correctly
- Plain text event does not normalize as mirrored key

## Manual

### Shell / SSH

- select 2+ SSH cards
- type a command like `pwd`
- verify all cards receive the same text
- press Enter
- verify all cards execute once
- test `Ctrl-C`
- test `Cmd+Backspace` (delete line)
- test `Cmd+V` paste

### Agent prompt comparison

- select 2+ agent cards
- type the same prompt
- verify all cards receive the same committed prompt text

### IME

- use Chinese Pinyin
- compose text in primary card
- verify followers do not show phonetic intermediate text
- commit the candidate
- verify followers receive committed Chinese text

- repeat with Japanese input

### Selection UX

- `Cmd+Click` terminal area of focused and unfocused cards
- ordinary click exits selection mode correctly
- blank-canvas click clears selection
- `Cmd+Opt+A` selects all cards
- `Escape` clears broadcast selection
- click follower during broadcasting promotes to primary
- click primary during broadcasting passes through to terminal
- exit Canvas returns to the primary card's worktree/tab

---

## Risks

1. **Ghostty/AppKit event ordering**
   - follower replay must not interfere with the primary first responder

2. **IME edge cases**
   - candidate confirmation behavior may differ by input method
   - design intentionally limits follower behavior to committed text

3. **Complex TUIs**
   - some full-screen or mouse-driven apps may not behave intuitively under broadcast
   - acceptable for v1

4. **Click/drag interaction overlap**
   - card drag gestures and selection clicks must be thresholded cleanly

5. **CommandKeyObserver delay**
   - 300ms hold delay means shield may not render for fast Cmd+Click
   - mitigated by reading `NSEvent.modifierFlags` directly in tap handlers

---

## Recommended Delivery Shape

Implement this in slices:

### Slice 1
- selection state model
- Cmd+Click anywhere using selection shield
- follower selected styling
- clear/exit behavior

### Slice 2
- tab-scoped terminal helpers
- primary/follower broadcast plumbing
- committed text broadcast
- Enter/backspace/arrows/basic control keys

### Slice 3
- IME hardening
- paste behavior (Cmd+V broadcast)
- Cmd+Backspace/Arrow whitelist
- select all (Cmd+Opt+A)
- Escape to clear broadcast
- per-card shield during broadcasting
- edge-case polish and manual verification

This keeps UX validation separate from lower-level Ghostty input fan-out.

---

## Final Recommendation

Proceed with a design that treats Canvas multi-select as:

- **card-level selection anywhere on the card**, not title-bar-only
- **primary-card-driven live broadcast**, not a separate textbox
- **IME commit-text mirroring**, not phonetic keystroke mirroring

That combination best matches the requested UX while staying implementable in the current Prowl/Ghostty architecture.
