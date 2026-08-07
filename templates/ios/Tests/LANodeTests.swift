import XCTest
import SwiftUI
@testable import Runner

/// Swift-side decoder tests.
///
/// Add this file to a unit-test target that also compiles
/// `ios/LiveActivityKitWidget/LANode.swift`, `LAStyle.swift` and
/// `LANodeRenderer.swift`, then run it with ⌘U. The payloads below are copied
/// verbatim from what the Dart `toJson()` produces, which is what makes the two
/// halves of the schema testable independently.
final class LANodeTests: XCTestCase {

    // MARK: - Colors

    func testParsesSixDigitHex() throws {
        XCTAssertNotNil(LAColor.parse("#34c759"))
        XCTAssertNotNil(LAColor.parse("34c759"))
    }

    func testParsesEightDigitHexWithAlpha() throws {
        XCTAssertNotNil(LAColor.parse("#11223380"))
    }

    func testParsesShorthandHex() throws {
        XCTAssertNotNil(LAColor.parse("#f00"))
    }

    func testRejectsGarbageInsteadOfPaintingBlack() throws {
        // A malformed colour must fall through to the inherited foreground.
        XCTAssertNil(LAColor.parse("not-a-color"))
        XCTAssertNil(LAColor.parse(42))
        XCTAssertNil(LAColor.parse(nil))
    }

    // MARK: - Nodes

    func testDecodesText() throws {
        let node = LANode.parse([
            "type": "text",
            "value": "Lunch",
            "size": 20.0,
            "weight": "bold",
            "color": "#34c759",
            "mono": true,
        ])
        guard case .text(let text)? = node else {
            return XCTFail("expected a text node")
        }
        XCTAssertEqual(text.value, "Lunch")
        XCTAssertEqual(text.size, 20)
        XCTAssertEqual(text.weight, .bold)
        XCTAssertTrue(text.monospacedDigit)
    }

    func testAppliesUppercaseAtDecodeTime() throws {
        let node = LANode.parse(["type": "text", "value": "live", "uppercase": true])
        guard case .text(let text)? = node else { return XCTFail("expected text") }
        XCTAssertEqual(text.value, "LIVE")
    }

    func testClampsProgressToUnitRange() throws {
        guard case .progress(let low)? = LANode.parse(["type": "progress", "value": -3.0]),
              case .progress(let high)? = LANode.parse(["type": "progress", "value": 7.0])
        else { return XCTFail("expected progress nodes") }
        XCTAssertEqual(low.value, 0)
        XCTAssertEqual(high.value, 1)
    }

    func testStackDefaultsDifferPerAxis() throws {
        // Rows centre their children on the cross axis; columns lead them.
        guard case .row(let row)? = LANode.parse(["type": "row", "children": []]),
              case .column(let column)? = LANode.parse(["type": "column", "children": []])
        else { return XCTFail("expected stacks") }
        XCTAssertEqual(row.align, .center)
        XCTAssertEqual(column.align, .start)
    }

    func testDecodesNestedChildren() throws {
        let node = LANode.parse([
            "type": "column",
            "children": [
                ["type": "text", "value": "a"],
                ["type": "row", "children": [["type": "text", "value": "b"]]],
            ],
        ])
        guard case .column(let column)? = node else { return XCTFail("expected column") }
        XCTAssertEqual(column.children.count, 2)
        guard case .row(let row) = column.children[1] else { return XCTFail("expected row") }
        XCTAssertEqual(row.children.count, 1)
    }

    func testSkipsUnknownNodesWithoutLosingSiblings() throws {
        // Forward compatibility: an old extension paired with a newer Dart
        // package must still draw the nodes it does understand.
        let node = LANode.parse([
            "type": "column",
            "children": [
                ["type": "text", "value": "kept"],
                ["type": "hologram", "value": "???"],
            ],
        ])
        guard case .column(let column)? = node else { return XCTFail("expected column") }
        XCTAssertEqual(column.children.count, 1)
    }

    func testCountdownDecodesEpochSeconds() throws {
        let node = LANode.parse([
            "type": "countdown",
            "until": 1_893_456_000.0,
            "style": "relative",
        ])
        guard case .countdown(let countdown)? = node else {
            return XCTFail("expected countdown")
        }
        XCTAssertEqual(countdown.date.timeIntervalSince1970, 1_893_456_000)
        XCTAssertEqual(countdown.style, .relative)
    }

    func testInsetsAcceptScalarAndArray() throws {
        let uniform = LAInsets.parse(8.0)
        XCTAssertEqual(uniform?.top, 8)
        XCTAssertEqual(uniform?.right, 8)

        let explicit = LAInsets.parse([1.0, 2.0, 3.0, 4.0])
        XCTAssertEqual(explicit?.top, 1)
        XCTAssertEqual(explicit?.left, 2)
        XCTAssertEqual(explicit?.bottom, 3)
        XCTAssertEqual(explicit?.right, 4)
    }

    // MARK: - Layout

    func testDecodesRegions() throws {
        let payload = """
        {"regions":{
          "lockScreen":{"type":"text","value":"lock"},
          "compactTrailing":{"type":"text","value":"trail"}
        },"theme":{"tint":"#ff0000"},"deepLink":"myapp://order/42"}
        """
        let layout = LALayout.decode(payload)
        XCTAssertNotNil(layout.node(.lockScreen))
        XCTAssertNotNil(layout.node(.compactTrailing))
        XCTAssertNil(layout.node(.minimal))
        XCTAssertNotNil(layout.theme.tint)
        XCTAssertEqual(layout.deepLink?.absoluteString, "myapp://order/42")
    }

    func testMalformedPayloadRendersNothingRatherThanCrashing() throws {
        XCTAssertTrue(LALayout.decode("{ not json").regions.isEmpty)
        XCTAssertTrue(LALayout.decode("").regions.isEmpty)
        XCTAssertTrue(LALayout.decode("[]").regions.isEmpty)
    }

    func testUnknownRegionsAreIgnored() throws {
        let layout = LALayout.decode(
            #"{"regions":{"holodeck":{"type":"text","value":"x"}}}"#
        )
        XCTAssertTrue(layout.regions.isEmpty)
    }

    // MARK: - Cache keys

    func testImageCacheKeyIsStableAndContentAddressed() throws {
        let a = LAImageLoader.cacheKey(for: "https://example.com/a.png")
        let b = LAImageLoader.cacheKey(for: "https://example.com/a.png")
        let c = LAImageLoader.cacheKey(for: "https://example.com/b.png")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Rendering smoke test

    @available(iOS 16.1, *)
    func testEveryNodeTypeRenders() throws {
        // Instantiating the view graph is enough to catch a `@ViewBuilder`
        // regression or a crash in a node initialiser; snapshot assertions
        // belong in the XCUITest target, where a real Live Activity can run.
        let payload = """
        {"regions":{"lockScreen":{"type":"column","children":[
          {"type":"text","value":"t"},
          {"type":"image","source":"systemName","value":"flame"},
          {"type":"row","children":[{"type":"spacer"},{"type":"divider"}]},
          {"type":"progress","value":0.5},
          {"type":"circularProgress","value":0.5,"center":{"type":"text","value":"50"}},
          {"type":"metric","value":"4.2","label":"km","unit":"km","symbol":"figure.run"},
          {"type":"countdown","until":1893456000},
          {"type":"padding","insets":[4,4,4,4],"child":{"type":"text","value":"p"}},
          {"type":"container","radius":12,"background":"#101010",
           "child":{"type":"text","value":"c"}}
        ]}}}
        """
        let layout = LALayout.decode(payload)
        let view = LARegionView(layout: layout, region: .lockScreen)
        XCTAssertNotNil(view.body)
    }
}
