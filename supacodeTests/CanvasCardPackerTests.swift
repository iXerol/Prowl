import CoreGraphics
import Testing

@testable import supacode

struct CanvasCardPackerTests {
  private let packer = CanvasCardPacker(spacing: 20, titleBarHeight: 28)

  private func card(_ key: String, width: CGFloat = 800, height: CGFloat = 550) -> CanvasCardPacker.CardInfo {
    CanvasCardPacker.CardInfo(key: key, size: CGSize(width: width, height: height))
  }

  // MARK: - Basic packing

  @Test func singleCardPacks() throws {
    let result = packer.pack(cards: [card("a")], targetRatio: 16.0 / 9.0)

    let layout = try #require(result.layouts["a"])
    #expect(layout.size == CGSize(width: 800, height: 550))
    #expect(result.boundingSize.width > 0)
    #expect(result.boundingSize.height > 0)
  }

  @Test func preservesOriginalCardSizes() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    #expect(result.layouts["a"]?.size == CGSize(width: 600, height: 400))
    #expect(result.layouts["b"]?.size == CGSize(width: 800, height: 300))
  }

  @Test func allCardsArePlaced() {
    let cards = (0..<5).map { card("card\($0)") }
    let result = packer.pack(cards: cards, targetRatio: 16.0 / 9.0)
    #expect(result.layouts.count == 5)
  }

  // MARK: - Row wrapping

  @Test func picksClosestRatioForWidePlusNarrowCards() throws {
    // 1 wide + 2 narrow cards with 16:9 target.
    // [wide+narrow1][narrow2] gives ratio ~1.25 (closer to 1.78)
    // [wide][narrow1+narrow2] gives ratio ~0.87 (further from 1.78)
    // So the algorithm correctly groups wide+narrow1 on the first row.
    let cards = [
      card("wide", width: 960, height: 550),
      card("narrow1", width: 500, height: 550),
      card("narrow2", width: 500, height: 550),
    ]
    let result = packer.pack(cards: cards, targetRatio: 16.0 / 9.0)

    let wide = try #require(result.layouts["wide"])
    let narrow1 = try #require(result.layouts["narrow1"])
    let narrow2 = try #require(result.layouts["narrow2"])

    // Wide and narrow1 share row 1, narrow2 is on row 2.
    #expect(wide.position.y == narrow1.position.y)
    #expect(narrow1.position.y < narrow2.position.y)
  }

  @Test func wideCardAloneWhenNarrowCardsAreBroader() throws {
    // When narrow cards' combined width exceeds the wide card, placing them
    // on their own row gives a ratio closer to a near-square target.
    let cards = [
      card("wide", width: 800, height: 400),
      card("narrow1", width: 700, height: 400),
      card("narrow2", width: 700, height: 400),
    ]
    // [wide][n1+n2]: width=max(840,1440)=1440, height=20+428+20+428+20=916, ratio=1.57
    // [wide+n1][n2]: width=max(1560,740)=1560, height=916, ratio=1.70
    // Target 1.5 → diff 0.07 vs 0.20; [wide][n1+n2] wins.
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    let wide = try #require(result.layouts["wide"])
    let narrow1 = try #require(result.layouts["narrow1"])
    let narrow2 = try #require(result.layouts["narrow2"])

    // Wide card alone on row 1, both narrow cards on row 2.
    let wideBottom = wide.position.y + (wide.size.height + 28) / 2
    let narrow1Top = narrow1.position.y - (narrow1.size.height + 28) / 2
    #expect(narrow1Top >= wideBottom)
    #expect(narrow1.position.y == narrow2.position.y)
  }

  @Test func uniformCardsFormGrid() throws {
    // 4 equal cards with square target → should form 2×2 grid.
    // Using 400-wide cards so the 2×2 ratio (0.94) beats 3-row configs (0.63).
    let cards = (0..<4).map { card("card\($0)", width: 400, height: 400) }
    let result = packer.pack(cards: cards, targetRatio: 1.0)

    let c0 = try #require(result.layouts["card0"])
    let c1 = try #require(result.layouts["card1"])
    let c2 = try #require(result.layouts["card2"])
    let c3 = try #require(result.layouts["card3"])

    // Row 1: card0, card1; Row 2: card2, card3
    #expect(c0.position.y == c1.position.y)
    #expect(c2.position.y == c3.position.y)
    #expect(c0.position.y < c2.position.y)
    #expect(c0.position.x == c2.position.x)
  }

  // MARK: - No overlap

  @Test func cardsDoNotOverlap() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
      card("c", width: 500, height: 500),
      card("d", width: 700, height: 350),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    let rects = result.layouts.map { (_, layout) -> CGRect in
      CGRect(
        x: layout.position.x - layout.size.width / 2,
        y: layout.position.y - (layout.size.height + 28) / 2,
        width: layout.size.width,
        height: layout.size.height + 28
      )
    }

    for i in 0..<rects.count {
      for j in (i + 1)..<rects.count {
        let insetA = rects[i].insetBy(dx: 1, dy: 1)
        let insetB = rects[j].insetBy(dx: 1, dy: 1)
        #expect(!insetA.intersects(insetB), "Cards \(i) and \(j) overlap")
      }
    }
  }

  // MARK: - Aspect ratio targeting

  @Test func resultRatioApproachesTarget() {
    let cards = [
      card("a", width: 700, height: 500),
      card("b", width: 500, height: 400),
      card("c", width: 600, height: 350),
      card("d", width: 800, height: 450),
      card("e", width: 550, height: 500),
      card("f", width: 650, height: 380),
    ]
    let targetRatio: CGFloat = 16.0 / 9.0
    let result = packer.pack(cards: cards, targetRatio: targetRatio)

    guard result.boundingSize.height > 0 else { return }
    let actualRatio = result.boundingSize.width / result.boundingSize.height
    #expect(actualRatio > targetRatio / 2 && actualRatio < targetRatio * 2)
  }

  // MARK: - Edge cases

  @Test func emptyCardsReturnsEmptyResult() {
    let result = packer.pack(cards: [], targetRatio: 1.5)
    #expect(result.layouts.isEmpty)
    #expect(result.boundingSize == .zero)
  }

  // MARK: - Spacing

  @Test func cardsOnSameRowHaveMinimumSpacing() throws {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 600, height: 400),
    ]
    // Wide target → both cards on the same row.
    let result = packer.pack(cards: cards, targetRatio: 3.0)

    let a = try #require(result.layouts["a"])
    let b = try #require(result.layouts["b"])

    #expect(a.position.y == b.position.y)
    let aRight = a.position.x + a.size.width / 2
    let bLeft = b.position.x - b.size.width / 2
    #expect(bLeft - aRight >= 20 - 1, "Horizontal gap too small: \(bLeft - aRight)")
  }

  @Test func rowsHaveMinimumSpacing() throws {
    let cards = [
      card("a", width: 800, height: 400),
      card("b", width: 800, height: 400),
    ]
    // Narrow target → each card on its own row.
    let result = packer.pack(cards: cards, targetRatio: 0.5)

    let a = try #require(result.layouts["a"])
    let b = try #require(result.layouts["b"])

    let aBottom = a.position.y + (a.size.height + 28) / 2
    let bTop = b.position.y - (b.size.height + 28) / 2
    #expect(bTop - aBottom >= 20 - 1, "Vertical gap too small: \(bTop - aBottom)")
  }
}
