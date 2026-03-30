import AppKit
import ComposableArchitecture
import SwiftUI

struct RepositorySettingsView: View {
  @Bindable var store: StoreOf<RepositorySettingsFeature>
  @State private var isBranchPickerPresented = false
  @State private var branchSearchText = ""

  @State private var selectedCustomCommandID: UserCustomCommand.ID?
  @State private var recordingCustomCommandID: UserCustomCommand.ID?
  @State private var recorderMonitor: Any?
  @State private var hoveredRecorderCommandID: UserCustomCommand.ID?
  @State private var invalidMessageByCommandID: [UserCustomCommand.ID: String] = [:]
  @State private var pendingShortcutConflict: CustomCommandShortcutConflict?
  @State private var pendingShortcut: PendingCustomShortcut?
  @State private var iconPickerCommandID: UserCustomCommand.ID?

  private let keyTokenResolver = ShortcutKeyTokenResolver()

  private static let symbolPresets = [
    "terminal",
    "terminal.fill",
    "play.fill",
    "stop.fill",
    "hammer.fill",
    "shippingbox.fill",
    "doc.text.fill",
    "sparkles",
    "bolt.fill",
    "flame.fill",
    "wand.and.stars",
    "wrench.and.screwdriver.fill",
    "checkmark.circle.fill",
    "xmark.circle.fill",
    "exclamationmark.triangle.fill",
    "ladybug.fill",
    "clock.fill",
    "repeat",
    "arrow.clockwise",
    "folder.fill",
    "archivebox.fill",
    "paperplane.fill",
    "cloud.fill",
    "tray.and.arrow.down.fill",
  ]

  var body: some View {
    let baseRefOptions =
      store.branchOptions.isEmpty ? [store.defaultWorktreeBaseRef] : store.branchOptions
    let settings = $store.settings
    let worktreeBaseDirectoryPath = Binding(
      get: { settings.worktreeBaseDirectoryPath.wrappedValue ?? "" },
      set: { settings.worktreeBaseDirectoryPath.wrappedValue = $0 },
    )
    let exampleWorktreePath = store.exampleWorktreePath

    Form {
      if store.showsWorktreeSettings {
        Section {
          if store.isBranchDataLoaded {
            Button {
              branchSearchText = ""
              isBranchPickerPresented = true
            } label: {
              HStack {
                Text(store.settings.worktreeBaseRef ?? "Automatic (\(store.defaultWorktreeBaseRef))")
                  .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                  .foregroundStyle(.secondary)
                  .font(.caption)
                  .accessibilityHidden(true)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isBranchPickerPresented) {
              BranchPickerPopover(
                searchText: $branchSearchText,
                options: baseRefOptions,
                automaticLabel: "Automatic (\(store.defaultWorktreeBaseRef))",
                selection: store.settings.worktreeBaseRef,
                onSelect: { ref in
                  store.settings.worktreeBaseRef = ref
                  isBranchPickerPresented = false
                }
              )
            }
          } else {
            ProgressView()
              .controlSize(.small)
          }
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Branch new workspaces from")
            Text("Each workspace is an isolated copy of your codebase.")
              .foregroundStyle(.secondary)
          }
        }

        Section {
          VStack(alignment: .leading) {
            TextField(
              "Inherit global default",
              text: worktreeBaseDirectoryPath
            )
            .textFieldStyle(.roundedBorder)

            Text("Set a repository-specific worktree base directory. Leave empty to inherit the global setting.")
              .foregroundStyle(.secondary)
            Text("Example new worktree path: \(exampleWorktreePath)")
              .foregroundStyle(.secondary)
              .monospaced()
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Toggle(
            "Copy ignored files to new worktrees",
            isOn: settings.copyIgnoredOnWorktreeCreate
          )
          .disabled(store.isBareRepository)

          Toggle(
            "Copy untracked files to new worktrees",
            isOn: settings.copyUntrackedOnWorktreeCreate
          )
          .disabled(store.isBareRepository)

          if store.isBareRepository {
            Text("Copy flags are ignored for bare repositories.")
              .foregroundStyle(.secondary)
          }
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Worktree")
            Text("Applies when creating a new worktree")
              .foregroundStyle(.secondary)
          }
        }
      }

      if store.showsPullRequestSettings {
        Section {
          Picker(
            "Merge strategy",
            selection: settings.pullRequestMergeStrategy
          ) {
            ForEach(PullRequestMergeStrategy.allCases) { strategy in
              Text(strategy.title)
                .tag(strategy)
            }
          }
          .labelsHidden()
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Pull Requests")
            Text("Used when merging PRs from the command palette")
              .foregroundStyle(.secondary)
          }
        }
      }

      if store.showsSetupScriptSettings {
        Section {
          ZStack(alignment: .topLeading) {
            PlainTextEditor(
              text: settings.setupScript
            )
            .frame(minHeight: 120)
            if store.settings.setupScript.isEmpty {
              Text("claude --dangerously-skip-permissions")
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .font(.body)
                .allowsHitTesting(false)
            }
          }
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Setup Script")
            Text("Initial setup script that will be launched once after worktree creation")
              .foregroundStyle(.secondary)
          }
        }
      }

      if store.showsArchiveScriptSettings {
        Section {
          ZStack(alignment: .topLeading) {
            PlainTextEditor(
              text: settings.archiveScript
            )
            .frame(minHeight: 120)
            if store.settings.archiveScript.isEmpty {
              Text("docker compose down")
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .font(.body)
                .allowsHitTesting(false)
            }
          }
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Archive Script")
            Text("Archive script that runs before a worktree is archived")
              .foregroundStyle(.secondary)
          }
        }
      }

      if store.showsRunScriptSettings {
        Section {
          ZStack(alignment: .topLeading) {
            PlainTextEditor(
              text: settings.runScript
            )
            .frame(minHeight: 120)
            if store.settings.runScript.isEmpty {
              Text("npm run dev")
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .font(.body)
                .allowsHitTesting(false)
            }
          }
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Run Script")
            Text("Run script launched on demand from the toolbar")
              .foregroundStyle(.secondary)
          }
        }
      }

      if store.showsCustomCommandsSettings {
        Section {
          customCommandsEditor
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Custom Commands")
            Text("Repository-local terminal actions. Custom command shortcuts take precedence in this repository.")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      store.send(.task)
      syncSelectedCommandID(with: store.userSettings.customCommands)
    }
    .onChange(of: store.userSettings.customCommands) { _, commands in
      syncSelectedCommandID(with: commands)
      clearRemovedCommandState(using: commands)
    }
    .onChange(of: recordingCustomCommandID) { _, commandID in
      if commandID == nil {
        stopRecorderMonitor()
      } else {
        startRecorderMonitor()
      }
    }
    .onDisappear {
      stopRecorderMonitor()
    }
    .alert(
      "Shortcut Conflict",
      isPresented: isShortcutConflictAlertPresented,
      presenting: pendingShortcutConflict
    ) { _ in
      Button("Replace", role: .destructive) {
        applyPendingShortcut(replacingConflict: true)
      }
      Button("Cancel", role: .cancel) {
        clearPendingShortcutConflict()
      }
    } message: { conflict in
      Text(
        "“\(conflict.newCommandTitle)” and “\(conflict.existingCommandTitle)” both use \(conflict.shortcutDisplay)."
          + "\n\nChoose Replace to keep the new shortcut and clear the conflicting command."
      )
    }
  }

  @ViewBuilder
  private var customCommandsEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      Table(store.userSettings.customCommands, selection: $selectedCustomCommandID) {
        TableColumn("") { command in
          Image(systemName: command.resolvedSystemImage)
            .foregroundStyle(.secondary)
            .frame(width: 16, alignment: .center)
            .accessibilityHidden(true)
        }
        .width(24)

        TableColumn("Name") { command in
          Text(command.resolvedTitle)
            .lineLimit(1)
        }

        TableColumn("Type") { command in
          Text(command.execution.title)
            .foregroundStyle(.secondary)
        }

        TableColumn("Shortcut") { command in
          Text(resolvedShortcutDisplay(for: command) ?? "Unassigned")
            .font(.body.monospaced())
            .foregroundStyle(resolvedShortcutDisplay(for: command) == nil ? .secondary : .primary)
            .lineLimit(1)
        }
      }
      .frame(minHeight: 220, maxHeight: 280)

      HStack(spacing: 8) {
        Button {
          addCustomCommand()
        } label: {
          Image(systemName: "plus")
            .frame(width: 16, height: 16)
            .accessibilityLabel("Add command")
        }
        .buttonStyle(.plain)
        .help("Add command")

        Button {
          removeSelectedCustomCommand()
        } label: {
          Image(systemName: "minus")
            .frame(width: 16, height: 16)
            .accessibilityLabel("Remove selected command")
        }
        .buttonStyle(.plain)
        .disabled(bindingForSelectedCustomCommand() == nil)
        .help("Remove selected command")

        Spacer(minLength: 0)

        Text("\(store.userSettings.customCommands.count) commands")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      if let command = bindingForSelectedCustomCommand() {
        customCommandDetail(for: command)
      } else {
        Text("Add a custom command to configure its name, script, icon, and shortcut.")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func customCommandDetail(for command: Binding<UserCustomCommand>) -> some View {
    let commandID = command.wrappedValue.id
    let resolvedBinding = resolvedCustomCommandBindings.keybinding(for: customCommandBindingID(for: commandID))
    let isRecording = recordingCustomCommandID == commandID
    let isHovering = hoveredRecorderCommandID == commandID

    VStack(alignment: .leading, spacing: 10) {
      TextField("Name", text: command.title)
        .textFieldStyle(.roundedBorder)

      HStack(spacing: 10) {
        TextField("SF Symbol", text: command.systemImage)
          .textFieldStyle(.roundedBorder)
        iconPickerButton(for: command)
        Image(systemName: command.wrappedValue.resolvedSystemImage)
          .frame(width: 20)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }

      Picker("Type", selection: command.execution) {
        ForEach(UserCustomCommandExecution.allCases) { execution in
          Text(execution.title)
            .tag(execution)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 280)

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          shortcutRecorderField(
            commandID: commandID,
            resolvedBinding: resolvedBinding,
            isRecording: isRecording,
            isHovering: isHovering
          )

          Button("Clear") {
            clearShortcut(for: commandID)
          }
          .disabled(command.wrappedValue.shortcut == nil)
        }

        if isRecording {
          Text(
            "Recording: press a key with modifiers (⌘ ⇧ ⌥ ⌃). Custom commands currently support character keys only."
              + " Press Esc to cancel."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if let invalidMessage = invalidMessageByCommandID[commandID] {
          Text(invalidMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      ZStack(alignment: .topLeading) {
        PlainTextEditor(
          text: command.command,
          isMonospaced: true
        )
        .frame(minHeight: 140)

        if command.wrappedValue.command.isEmpty {
          Text(scriptPlaceholder(for: command.wrappedValue.execution))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .font(.body.monospaced())
            .allowsHitTesting(false)
        }
      }

      Text(scriptDescription(for: command.wrappedValue.execution))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func iconPickerButton(for command: Binding<UserCustomCommand>) -> some View {
    let commandID = command.wrappedValue.id

    return Button {
      iconPickerCommandID = commandID
    } label: {
      Label("Icons", systemImage: "square.grid.3x3")
        .labelStyle(.iconOnly)
    }
    .help("Pick a common SF Symbol")
    .popover(
      isPresented: Binding(
        get: { iconPickerCommandID == commandID },
        set: { shouldPresent in
          if !shouldPresent {
            iconPickerCommandID = nil
          }
        }
      ),
      arrowEdge: .bottom
    ) {
      ScrollView {
        LazyVGrid(
          columns: Array(repeating: GridItem(.fixed(24), spacing: 12), count: 8),
          spacing: 12
        ) {
          ForEach(Self.symbolPresets, id: \.self) { symbol in
            Button {
              command.wrappedValue.systemImage = symbol
              iconPickerCommandID = nil
            } label: {
              Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .help(symbol)
          }
        }
        .padding(12)
      }
      .frame(width: 320, height: 124)
    }
  }

  private func scriptPlaceholder(for execution: UserCustomCommandExecution) -> String {
    switch execution {
    case .shellScript:
      return "npm test && swift test"
    case .terminalInput:
      return "pnpm test --watch"
    }
  }

  private func scriptDescription(for execution: UserCustomCommandExecution) -> String {
    switch execution {
    case .shellScript:
      return "Runs in a new terminal tab."
    case .terminalInput:
      return "Sends input to the currently focused terminal."
    }
  }

  private func shortcutRecorderField(
    commandID: UserCustomCommand.ID,
    resolvedBinding: Keybinding?,
    isRecording: Bool,
    isHovering: Bool
  ) -> some View {
    Button {
      toggleRecording(for: commandID)
    } label: {
      HStack(spacing: 6) {
        if isRecording {
          Image(systemName: "record.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
        }

        Text(shortcutRecorderTitle(resolvedBinding: resolvedBinding, isRecording: isRecording))
          .font(.body.monospaced())
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(shortcutRecorderForegroundColor(resolvedBinding: resolvedBinding, isRecording: isRecording))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(shortcutRecorderBorderColor(isRecording: isRecording, isHovering: isHovering), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        hoveredRecorderCommandID = commandID
      } else if hoveredRecorderCommandID == commandID {
        hoveredRecorderCommandID = nil
      }
    }
    .help(isRecording ? "Recording shortcut. Press Esc to cancel." : "Click to record a shortcut.")
  }

  private func shortcutRecorderTitle(resolvedBinding: Keybinding?, isRecording: Bool) -> String {
    if isRecording {
      return "Recording…"
    }
    return resolvedBinding?.display ?? "Unassigned"
  }

  private func shortcutRecorderForegroundColor(resolvedBinding: Keybinding?, isRecording: Bool) -> Color {
    if isRecording {
      return .accentColor
    }
    return resolvedBinding == nil ? .secondary : .primary
  }

  private func shortcutRecorderBorderColor(isRecording: Bool, isHovering: Bool) -> Color {
    if isRecording {
      return .accentColor
    }
    if isHovering {
      return Color(nsColor: .tertiaryLabelColor)
    }
    return Color(nsColor: .separatorColor)
  }

  private var resolvedCustomCommandBindings: ResolvedKeybindingMap {
    let commands = store.userSettings.customCommands
    let migration = LegacyCustomCommandShortcutMigration.migrate(commands: commands)
    return KeybindingResolver.resolve(
      schema: .appResolverSchema(customCommands: commands),
      userOverrides: store.keybindingUserOverrides,
      migratedOverrides: migration.overrides
    )
  }

  private func resolvedShortcutDisplay(for command: UserCustomCommand) -> String? {
    resolvedCustomCommandBindings.display(for: customCommandBindingID(for: command.id))
  }

  private func customCommandBindingID(for commandID: String) -> String {
    LegacyCustomCommandShortcutMigration.customCommandBindingID(for: commandID)
  }

  private func bindingForSelectedCustomCommand() -> Binding<UserCustomCommand>? {
    guard let selectedCustomCommandID else {
      return nil
    }
    guard let index = store.userSettings.customCommands.firstIndex(where: { $0.id == selectedCustomCommandID }) else {
      return nil
    }
    return $store.userSettings.customCommands[index]
  }

  private func syncSelectedCommandID(with commands: [UserCustomCommand]) {
    guard !commands.isEmpty else {
      selectedCustomCommandID = nil
      recordingCustomCommandID = nil
      iconPickerCommandID = nil
      return
    }

    if let selectedCustomCommandID,
      commands.contains(where: { $0.id == selectedCustomCommandID })
    {
      return
    }

    selectedCustomCommandID = commands[0].id
  }

  private func clearRemovedCommandState(using commands: [UserCustomCommand]) {
    let validIDs = Set(commands.map(\.id))

    invalidMessageByCommandID = invalidMessageByCommandID.filter { validIDs.contains($0.key) }

    if let recordingCustomCommandID,
      !validIDs.contains(recordingCustomCommandID)
    {
      self.recordingCustomCommandID = nil
    }

    if let iconPickerCommandID,
      !validIDs.contains(iconPickerCommandID)
    {
      self.iconPickerCommandID = nil
    }
  }

  private func addCustomCommand() {
    let current = store.userSettings.customCommands
    let next = current + [.default(index: current.count)]
    store.userSettings.customCommands = UserRepositorySettings.normalizedCommands(next)
    selectedCustomCommandID = store.userSettings.customCommands.last?.id
  }

  private func removeSelectedCustomCommand() {
    guard let selectedCustomCommandID else {
      return
    }

    store.userSettings.customCommands.removeAll { $0.id == selectedCustomCommandID }
  }

  private func clearShortcut(for commandID: UserCustomCommand.ID) {
    invalidMessageByCommandID[commandID] = nil
    updateCustomCommand(id: commandID) { command in
      command.shortcut = nil
    }
    if recordingCustomCommandID == commandID {
      recordingCustomCommandID = nil
    }
  }

  private func updateCustomCommand(
    id: UserCustomCommand.ID,
    update: (inout UserCustomCommand) -> Void
  ) {
    guard let index = store.userSettings.customCommands.firstIndex(where: { $0.id == id }) else {
      return
    }

    update(&store.userSettings.customCommands[index])
  }

  private func toggleRecording(for commandID: UserCustomCommand.ID) {
    invalidMessageByCommandID[commandID] = nil

    if recordingCustomCommandID == commandID {
      recordingCustomCommandID = nil
      return
    }

    recordingCustomCommandID = commandID
  }

  private func startRecorderMonitor() {
    stopRecorderMonitor()
    recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
      guard let commandID = recordingCustomCommandID else {
        return event
      }
      handleRecorderEvent(event, commandID: commandID)
      return nil
    }
  }

  private func stopRecorderMonitor() {
    if let recorderMonitor {
      NSEvent.removeMonitor(recorderMonitor)
      self.recorderMonitor = nil
    }
  }

  private func handleRecorderEvent(_ event: NSEvent, commandID: UserCustomCommand.ID) {
    if event.keyCode == 53 {  // Escape
      recordingCustomCommandID = nil
      return
    }

    guard
      let keyToken = keyTokenResolver.resolveKeyToken(
        keyCode: event.keyCode,
        charactersIgnoringModifiers: event.charactersIgnoringModifiers
      )
    else {
      invalidMessageByCommandID[commandID] = "Unsupported key. Use letters, numbers, or punctuation."
      return
    }

    let modifiers = KeybindingModifiers(
      command: event.modifierFlags.contains(.command),
      shift: event.modifierFlags.contains(.shift),
      option: event.modifierFlags.contains(.option),
      control: event.modifierFlags.contains(.control)
    )

    guard !modifiers.isEmpty else {
      invalidMessageByCommandID[commandID] = "Shortcut must include at least one modifier key."
      return
    }

    let binding = Keybinding(key: keyToken, modifiers: modifiers)
    guard let shortcut = binding.userCustomShortcut else {
      invalidMessageByCommandID[commandID] =
        "Custom command shortcuts support letters, numbers, and punctuation only."
      return
    }

    applyRecordedShortcut(shortcut.normalized(), to: commandID)
  }

  private func applyRecordedShortcut(
    _ shortcut: UserCustomShortcut,
    to commandID: UserCustomCommand.ID
  ) {
    invalidMessageByCommandID[commandID] = nil

    guard let existingCommand = firstConflictingCommand(for: commandID, shortcut: shortcut) else {
      updateCustomCommand(id: commandID) { command in
        command.shortcut = shortcut
      }
      recordingCustomCommandID = nil
      return
    }

    let newTitle =
      store.userSettings.customCommands.first(where: { $0.id == commandID })?.resolvedTitle ?? "Command"

    pendingShortcutConflict = CustomCommandShortcutConflict(
      newCommandID: commandID,
      newCommandTitle: newTitle,
      existingCommandID: existingCommand.id,
      existingCommandTitle: existingCommand.resolvedTitle,
      shortcutDisplay: shortcut.display
    )
    pendingShortcut = PendingCustomShortcut(commandID: commandID, shortcut: shortcut)
    recordingCustomCommandID = nil
  }

  private func firstConflictingCommand(
    for commandID: UserCustomCommand.ID,
    shortcut: UserCustomShortcut
  ) -> UserCustomCommand? {
    store.userSettings.customCommands.first { command in
      guard command.id != commandID else { return false }
      guard let existingShortcut = command.shortcut?.normalized() else { return false }
      return existingShortcut == shortcut
    }
  }

  private func applyPendingShortcut(replacingConflict: Bool) {
    guard let pendingShortcut else {
      clearPendingShortcutConflict()
      return
    }

    if replacingConflict,
      let existingCommandID = pendingShortcutConflict?.existingCommandID
    {
      updateCustomCommand(id: existingCommandID) { command in
        command.shortcut = nil
      }
    }

    updateCustomCommand(id: pendingShortcut.commandID) { command in
      command.shortcut = pendingShortcut.shortcut
    }

    clearPendingShortcutConflict()
  }

  private func clearPendingShortcutConflict() {
    pendingShortcutConflict = nil
    pendingShortcut = nil
  }

  private var isShortcutConflictAlertPresented: Binding<Bool> {
    Binding(
      get: { pendingShortcutConflict != nil },
      set: { shouldPresent in
        if !shouldPresent {
          clearPendingShortcutConflict()
        }
      }
    )
  }
}

private struct BranchPickerPopover: View {
  @Binding var searchText: String
  let options: [String]
  let automaticLabel: String
  let selection: String?
  let onSelect: (String?) -> Void
  @FocusState private var isSearchFocused: Bool

  var filteredOptions: [String] {
    if searchText.isEmpty { return options }
    return options.filter { $0.localizedCaseInsensitiveContains(searchText) }
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField("Filter branches...", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .focused($isSearchFocused)
        .padding(8)
      Divider()
      List {
        Button {
          onSelect(nil)
        } label: {
          HStack {
            Text(automaticLabel)
            Spacer()
            if selection == nil {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            }
          }
          .padding(.vertical, 6)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        ForEach(filteredOptions, id: \.self) { ref in
          Button {
            onSelect(ref)
          } label: {
            HStack {
              Text(ref)
              Spacer()
              if selection == ref {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
                  .accessibilityHidden(true)
              }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .listStyle(.plain)
    }
    .frame(width: 300, height: 350)
    .onAppear { isSearchFocused = true }
  }
}

private struct CustomCommandShortcutConflict: Equatable {
  let newCommandID: UserCustomCommand.ID
  let newCommandTitle: String
  let existingCommandID: UserCustomCommand.ID
  let existingCommandTitle: String
  let shortcutDisplay: String
}

private struct PendingCustomShortcut: Equatable {
  let commandID: UserCustomCommand.ID
  let shortcut: UserCustomShortcut
}
