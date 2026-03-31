import ComposableArchitecture
import Foundation

struct TerminalLayoutPersistenceClient {
  var loadSnapshot: @Sendable () async -> TerminalLayoutSnapshotPayload?
  var saveSnapshot: @Sendable (TerminalLayoutSnapshotPayload) async -> Bool
  var clearSnapshot: @Sendable () async -> Bool
}

extension TerminalLayoutPersistenceClient: DependencyKey {
  static let liveValue = TerminalLayoutPersistenceClient(
    loadSnapshot: {
      loadTerminalLayoutSnapshot(
        at: SupacodePaths.terminalLayoutSnapshotURL,
        fileManager: .default
      )
    },
    saveSnapshot: { payload in
      saveTerminalLayoutSnapshot(
        payload,
        at: SupacodePaths.terminalLayoutSnapshotURL,
        cacheDirectory: SupacodePaths.cacheDirectory,
        fileManager: .default
      )
    },
    clearSnapshot: {
      discardTerminalLayoutSnapshot(at: SupacodePaths.terminalLayoutSnapshotURL, fileManager: .default)
    }
  )

  static let testValue = TerminalLayoutPersistenceClient(
    loadSnapshot: { nil },
    saveSnapshot: { _ in true },
    clearSnapshot: { true }
  )
}

extension DependencyValues {
  var terminalLayoutPersistence: TerminalLayoutPersistenceClient {
    get { self[TerminalLayoutPersistenceClient.self] }
    set { self[TerminalLayoutPersistenceClient.self] = newValue }
  }
}

private nonisolated let terminalLayoutPersistenceLogger = SupaLogger("TerminalLayoutPersistence")

@discardableResult
nonisolated func discardTerminalLayoutSnapshot(
  at url: URL,
  fileManager: FileManager
) -> Bool {
  let path = url.path(percentEncoded: false)
  guard fileManager.fileExists(atPath: path) else {
    return true
  }
  do {
    try fileManager.removeItem(at: url)
    return true
  } catch {
    terminalLayoutPersistenceLogger.warning(
      "Unable to remove terminal layout snapshot: \(error.localizedDescription)"
    )
    return false
  }
}

nonisolated func loadTerminalLayoutSnapshot(
  at url: URL,
  fileManager: FileManager
) -> TerminalLayoutSnapshotPayload? {
  guard let data = try? Data(contentsOf: url) else {
    return nil
  }
  guard !data.isEmpty else {
    _ = discardTerminalLayoutSnapshot(at: url, fileManager: fileManager)
    return nil
  }
  guard let payload = TerminalLayoutSnapshotPayload.decodeValidated(from: data) else {
    terminalLayoutPersistenceLogger.warning("Invalid terminal layout snapshot detected and reset")
    _ = discardTerminalLayoutSnapshot(at: url, fileManager: fileManager)
    return nil
  }
  return payload
}

nonisolated func saveTerminalLayoutSnapshot(
  _ payload: TerminalLayoutSnapshotPayload,
  at snapshotURL: URL,
  cacheDirectory: URL,
  fileManager: FileManager
) -> Bool {
  guard payload.isValid else {
    terminalLayoutPersistenceLogger.warning("Refusing to write invalid terminal layout snapshot")
    return false
  }
  if payload.worktrees.isEmpty {
    return discardTerminalLayoutSnapshot(at: snapshotURL, fileManager: fileManager)
  }
  do {
    try fileManager.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payload)
    guard data.count <= TerminalLayoutSnapshotPayload.maxSnapshotFileBytes else {
      terminalLayoutPersistenceLogger.warning("Terminal layout snapshot exceeded size fuse and was skipped")
      return false
    }
    try data.write(to: snapshotURL, options: .atomic)
    return true
  } catch {
    terminalLayoutPersistenceLogger.warning(
      "Unable to write terminal layout snapshot: \(error.localizedDescription)"
    )
    return false
  }
}
