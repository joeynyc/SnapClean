import XCTest
import SwiftUI
@testable import SnapClean

final class AnnotationModelTests: XCTestCase {
    func testAnnotationNormalizationRoundTripsThroughDisplayRect() throws {
        let rect = CGRect(x: 20, y: 10, width: 200, height: 100)

        let normalized = try XCTUnwrap(AnnotationElement.normalized(
            tool: .rectangle,
            color: .red,
            lineWidth: 4,
            startPoint: CGPoint(x: 70, y: 35),
            endPoint: CGPoint(x: 170, y: 85),
            in: rect
        ))

        XCTAssertEqual(normalized.startPoint?.x ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(normalized.startPoint?.y ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(normalized.endPoint?.x ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(normalized.endPoint?.y ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(normalized.lineWidth, 0.04, accuracy: 0.0001)

        let denormalized = normalized.denormalized(in: rect)
        XCTAssertEqual(denormalized.startPoint?.x ?? -1, 70, accuracy: 0.0001)
        XCTAssertEqual(denormalized.startPoint?.y ?? -1, 35, accuracy: 0.0001)
        XCTAssertEqual(denormalized.endPoint?.x ?? -1, 170, accuracy: 0.0001)
        XCTAssertEqual(denormalized.endPoint?.y ?? -1, 85, accuracy: 0.0001)
        XCTAssertEqual(denormalized.lineWidth, 4, accuracy: 0.0001)
    }

    func testEffectAnnotationProvidesRectAndAmount() {
        let blur = AnnotationElement(
            tool: .blur,
            lineWidth: 3,
            startPoint: CGPoint(x: 90, y: 40),
            endPoint: CGPoint(x: 10, y: 80)
        )

        XCTAssertEqual(blur.effectRect, CGRect(x: 10, y: 40, width: 80, height: 40))
        XCTAssertEqual(blur.effectAmount, 6, accuracy: 0.0001)

        let pixelate = AnnotationElement(
            tool: .pixelate,
            lineWidth: 5,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 40, y: 30)
        )

        XCTAssertEqual(pixelate.effectRect, CGRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(pixelate.effectAmount, 20, accuracy: 0.0001)
    }
}
