import SwiftUI

extension View {
  /// Applies a Liquid Glass background on macOS 26+, falling back to a
  /// translucent material on earlier systems so the surface stays legible.
  ///
  /// `glassEffect(_:in:)` is only available on macOS 26, so callers that need
  /// to deploy to earlier systems route through this helper instead of calling
  /// it directly.
  @ViewBuilder
  func glassBackground(in shape: some Shape) -> some View {
    if #available(macOS 26, *) {
      glassEffect(.regular, in: shape)
    } else {
      background(.regularMaterial, in: shape)
    }
  }
}
