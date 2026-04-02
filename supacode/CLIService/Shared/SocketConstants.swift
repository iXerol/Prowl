// ProwlShared/SocketConstants.swift
// Shared socket path convention between CLI client and app server.

import Foundation

public enum ProwlSocket {
  /// Default Unix domain socket path.
  /// Located in user's temporary directory to avoid permission issues.
  public static var defaultPath: String {
    let tmpDir = NSTemporaryDirectory()
    return (tmpDir as NSString).appendingPathComponent("prowl-cli.sock")
  }
}
