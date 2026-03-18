import CoreGraphics
import Foundation

struct CanvasCardLayout: Codable, Equatable, Hashable, Sendable {
  var positionX: CGFloat
  var positionY: CGFloat
  var width: CGFloat
  var height: CGFloat

  var position: CGPoint {
    get { CGPoint(x: positionX, y: positionY) }
    set {
      positionX = newValue.x
      positionY = newValue.y
    }
  }

  var size: CGSize {
    get { CGSize(width: width, height: height) }
    set {
      width = newValue.width
      height = newValue.height
    }
  }

  static let defaultSize = CGSize(width: 800, height: 550)

  init(position: CGPoint, size: CGSize = Self.defaultSize) {
    self.positionX = position.x
    self.positionY = position.y
    self.width = size.width
    self.height = size.height
  }
}

// MARK: - Card Packing

struct CanvasCardPacker {
  var spacing: CGFloat
  var titleBarHeight: CGFloat

  struct CardInfo {
    var key: String
    var size: CGSize
  }

  struct PackResult {
    var layouts: [String: CanvasCardLayout]
    var boundingSize: CGSize
  }

  /// The maximum card count for exhaustive row-break enumeration.
  /// 2^(N-1) configurations — 2^19 ≈ 500K is still sub-millisecond.
  private static let exhaustiveLimit = 20

  /// Pack cards into rows whose bounding aspect ratio best matches `targetRatio`.
  ///
  /// For up to 20 cards, every possible row-break configuration is evaluated
  /// and the one whose bounding rectangle ratio is closest to `targetRatio` wins.
  /// For larger counts, a greedy first-fit row packing with binary search is used.
  func pack(cards: [CardInfo], targetRatio: CGFloat) -> PackResult {
    guard !cards.isEmpty, targetRatio > 0 else {
      return PackResult(layouts: [:], boundingSize: .zero)
    }

    if cards.count <= Self.exhaustiveLimit {
      return exhaustivePack(cards: cards, targetRatio: targetRatio)
    }
    return greedyPack(cards: cards, targetRatio: targetRatio)
  }

  // MARK: - Exhaustive search

  /// Try every possible row-break configuration and pick the best ratio match.
  private func exhaustivePack(cards: [CardInfo], targetRatio: CGFloat) -> PackResult {
    let n = cards.count
    let maskCount = 1 << (n - 1)
    var bestMask = 0
    var bestDiff = CGFloat.infinity
    var bestArea = CGFloat.infinity

    for mask in 0..<maskCount {
      let (w, h) = boundingSize(cards: cards, breakMask: mask)
      let ratio = w / h
      let diff = abs(ratio - targetRatio)
      let area = w * h
      if diff < bestDiff || (diff == bestDiff && area < bestArea) {
        bestDiff = diff
        bestMask = mask
        bestArea = area
      }
    }

    return layoutFromMask(cards: cards, breakMask: bestMask)
  }

  /// Compute bounding width and height for a row-break configuration
  /// without allocating layout dictionaries.
  private func boundingSize(cards: [CardInfo], breakMask: Int) -> (CGFloat, CGFloat) {
    var maxWidth = spacing
    var totalHeight = spacing
    var rowWidth = spacing
    var rowHeight: CGFloat = 0

    for i in 0..<cards.count {
      if i > 0 && (breakMask & (1 << (i - 1))) != 0 {
        maxWidth = max(maxWidth, rowWidth)
        totalHeight += rowHeight + spacing
        rowWidth = spacing
        rowHeight = 0
      }
      rowWidth += cards[i].size.width + spacing
      rowHeight = max(rowHeight, cards[i].size.height + titleBarHeight)
    }

    maxWidth = max(maxWidth, rowWidth)
    totalHeight += rowHeight + spacing
    return (maxWidth, totalHeight)
  }

  /// Build actual card layouts from a chosen row-break mask.
  private func layoutFromMask(cards: [CardInfo], breakMask: Int) -> PackResult {
    var rows: [[Int]] = [[0]]
    for i in 1..<cards.count {
      if breakMask & (1 << (i - 1)) != 0 {
        rows.append([i])
      } else {
        rows[rows.count - 1].append(i)
      }
    }

    var layouts: [String: CanvasCardLayout] = [:]
    var y = spacing
    var maxRowEndX: CGFloat = 0

    for row in rows {
      let rowHeight = row.map { cards[$0].size.height + titleBarHeight }.max() ?? 0
      var x = spacing

      for idx in row {
        let card = cards[idx]
        let cardHeight = card.size.height + titleBarHeight
        layouts[card.key] = CanvasCardLayout(
          position: CGPoint(
            x: x + card.size.width / 2,
            y: y + cardHeight / 2
          ),
          size: card.size
        )
        x += card.size.width + spacing
      }

      maxRowEndX = max(maxRowEndX, x)
      y += rowHeight + spacing
    }

    return PackResult(
      layouts: layouts,
      boundingSize: CGSize(width: maxRowEndX, height: y)
    )
  }

  // MARK: - Greedy fallback (N > 20)

  /// Binary search over row widths with greedy first-fit row packing.
  private func greedyPack(cards: [CardInfo], targetRatio: CGFloat) -> PackResult {
    let maxCardWidth = cards.map(\.size.width).max()!
    var lo = maxCardWidth + 2 * spacing
    var hi = cards.reduce(0.0) { $0 + $1.size.width } + CGFloat(cards.count + 1) * spacing
    hi = max(lo, hi)
    var bestResult: PackResult?
    var bestDiff = CGFloat.infinity

    // Try the endpoints explicitly to avoid binary search boundary issues.
    for width in [lo, hi] {
      let result = greedyRowPack(cards: cards, rowWidth: width)
      let ratio = result.boundingSize.width / result.boundingSize.height
      let diff = abs(ratio - targetRatio)
      if diff < bestDiff {
        bestDiff = diff
        bestResult = result
      }
    }

    for _ in 0..<30 {
      let mid = (lo + hi) / 2
      let result = greedyRowPack(cards: cards, rowWidth: mid)
      let ratio = result.boundingSize.width / result.boundingSize.height
      let diff = abs(ratio - targetRatio)
      if diff < bestDiff {
        bestDiff = diff
        bestResult = result
      }
      if ratio > targetRatio {
        hi = mid
      } else {
        lo = mid
      }
    }

    return bestResult ?? PackResult(layouts: [:], boundingSize: .zero)
  }

  private func greedyRowPack(cards: [CardInfo], rowWidth: CGFloat) -> PackResult {
    var rows: [[Int]] = [[]]
    var currentX = spacing

    for (i, card) in cards.enumerated() {
      let neededWidth = card.size.width + spacing
      if currentX + neededWidth > rowWidth && !rows[rows.count - 1].isEmpty {
        rows.append([])
        currentX = spacing
      }
      rows[rows.count - 1].append(i)
      currentX += neededWidth
    }

    var layouts: [String: CanvasCardLayout] = [:]
    var y = spacing
    var maxRowEndX: CGFloat = 0

    for row in rows {
      let rowHeight = row.map { cards[$0].size.height + titleBarHeight }.max() ?? 0
      var x = spacing

      for idx in row {
        let card = cards[idx]
        let cardHeight = card.size.height + titleBarHeight
        layouts[card.key] = CanvasCardLayout(
          position: CGPoint(
            x: x + card.size.width / 2,
            y: y + cardHeight / 2
          ),
          size: card.size
        )
        x += card.size.width + spacing
      }

      maxRowEndX = max(maxRowEndX, x)
      y += rowHeight + spacing
    }

    return PackResult(
      layouts: layouts,
      boundingSize: CGSize(width: maxRowEndX, height: y)
    )
  }
}

@MainActor
@Observable
final class CanvasLayoutStore {
  private static let storageKey = "canvasCardLayouts"

  var cardLayouts: [String: CanvasCardLayout] {
    didSet { save() }
  }

  init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let layouts = try? JSONDecoder().decode([String: CanvasCardLayout].self, from: data)
    {
      self.cardLayouts = layouts
    } else {
      self.cardLayouts = [:]
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(cardLayouts) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
