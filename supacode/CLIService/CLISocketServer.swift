// supacode/CLIService/CLISocketServer.swift
// Unix domain socket server that listens for CLI command requests.

import Foundation

@MainActor
final class CLISocketServer {
  private let router: CLICommandRouter
  private let socketPath: String
  private var serverFD: Int32 = -1
  private var isRunning = false
  private var acceptTask: Task<Void, Never>?

  init(router: CLICommandRouter, socketPath: String = ProwlSocket.defaultPath) {
    self.router = router
    self.socketPath = socketPath
  }

  /// Start listening for CLI connections.
  func start() throws {
    // Clean up stale socket file
    unlink(socketPath)

    // Create socket
    serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
      throw CLIServiceError.socketCreationFailed
    }

    // Bind
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
      close(serverFD)
      throw CLIServiceError.socketPathTooLong
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
        for (i, byte) in pathBytes.enumerated() {
          dest[i] = byte
        }
      }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }

    guard bindResult == 0 else {
      close(serverFD)
      throw CLIServiceError.bindFailed
    }

    // Listen
    guard listen(serverFD, 5) == 0 else {
      close(serverFD)
      throw CLIServiceError.listenFailed
    }

    isRunning = true

    // Accept connections in background
    acceptTask = Task { [weak self] in
      await self?.acceptLoop()
    }
  }

  /// Stop the server and clean up.
  func stop() {
    isRunning = false
    acceptTask?.cancel()
    if serverFD >= 0 {
      close(serverFD)
      serverFD = -1
    }
    unlink(socketPath)
  }

  // MARK: - Accept loop

  private func acceptLoop() async {
    while isRunning, !Task.isCancelled {
      let clientFD = accept(serverFD, nil, nil)
      guard clientFD >= 0 else {
        if isRunning {
          // Brief pause before retrying
          try? await Task.sleep(for: .milliseconds(100))
        }
        continue
      }

      // Handle each client connection concurrently
      Task { [weak self] in
        await self?.handleClient(fd: clientFD)
      }
    }
  }

  private func handleClient(fd clientFD: Int32) async {
    defer { close(clientFD) }

    do {
      // Read length-prefixed request
      let lengthData = try socketRead(fd: clientFD, count: 4)
      let length = lengthData.withUnsafeBytes {
        UInt32(bigEndian: $0.load(as: UInt32.self))
      }
      guard length > 0, length < 10_000_000 else { return }

      let requestData = try socketRead(fd: clientFD, count: Int(length))

      // Decode envelope
      let decoder = JSONDecoder()
      let envelope = try decoder.decode(CommandEnvelope.self, from: requestData)

      // Route to handler
      let response = await router.route(envelope)

      // Encode and send response
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let responseData = try encoder.encode(response)

      var responseLength = UInt32(responseData.count).bigEndian
      let responseLengthData = Data(bytes: &responseLength, count: 4)
      try socketWrite(fd: clientFD, data: responseLengthData)
      try socketWrite(fd: clientFD, data: responseData)
    } catch {
      // Connection-level errors are silently dropped
    }
  }

  // MARK: - Socket I/O helpers

  private func socketRead(fd: Int32, count: Int) throws -> Data {
    var data = Data(capacity: count)
    var remaining = count
    let bufferSize = min(count, 65536)
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while remaining > 0 {
      let toRead = min(remaining, bufferSize)
      let bytesRead = Foundation.read(fd, &buffer, toRead)
      guard bytesRead > 0 else {
        throw CLIServiceError.readFailed
      }
      data.append(buffer, count: bytesRead)
      remaining -= bytesRead
    }
    return data
  }

  private func socketWrite(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let written = Foundation.write(
          fd,
          buffer.baseAddress!.advanced(by: offset),
          buffer.count - offset
        )
        guard written > 0 else {
          throw CLIServiceError.writeFailed
        }
        offset += written
      }
    }
  }
}

// MARK: - Errors

enum CLIServiceError: Error {
  case socketCreationFailed
  case socketPathTooLong
  case bindFailed
  case listenFailed
  case readFailed
  case writeFailed
}
