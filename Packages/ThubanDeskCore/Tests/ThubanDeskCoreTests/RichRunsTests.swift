import XCTest
@testable import ThubanDeskCore

final class RichRunsTests: XCTestCase {
    func testParagraphsAndRunsBecomeHTML() {
        let paragraphs = [
            RichRuns.Paragraph([RichRuns.Run("Hi Priya,")]),
            RichRuns.Paragraph([]),
            RichRuns.Paragraph([RichRuns.Run("Confirmed for "), RichRuns.Run("Friday", bold: true), RichRuns.Run(" at 3 <PM>", italic: true)]),
        ]
        XCTAssertEqual(RichRuns.html(paragraphs), "<div>Hi Priya,</div><div><br></div><div>Confirmed for <b>Friday</b><i> at 3 &lt;PM&gt;</i></div>")
        XCTAssertEqual(RichRuns.plainText(paragraphs), "Hi Priya,\n\nConfirmed for Friday at 3 <PM>")
    }

    func testBulletsGroupIntoOneList() {
        let lines: [[RichRuns.Run]] = [
            [RichRuns.Run("Bring:")],
            [RichRuns.Run("• "), RichRuns.Run("markers", bold: true)],
            [RichRuns.Run("• Q3 & Q4")],
            [RichRuns.Run("Thanks")],
        ]
        let paragraphs = RichRuns.paragraphs(fromLines: lines)
        XCTAssertEqual(paragraphs.map(\.bullet), [false, true, true, false])
        XCTAssertEqual(paragraphs[1].runs, [RichRuns.Run("markers", bold: true)])
        XCTAssertEqual(RichRuns.html(paragraphs), "<div>Bring:</div><ul><li><b>markers</b></li><li>Q3 &amp; Q4</li></ul><div>Thanks</div>")
        XCTAssertEqual(RichRuns.plainText(paragraphs), "Bring:\n- markers\n- Q3 & Q4\nThanks")
    }

    func testBoldItalicNesting() {
        XCTAssertEqual(RichRuns.runHTML(RichRuns.Run("x", bold: true, italic: true)), "<b><i>x</i></b>")
        XCTAssertEqual(RichRuns.runHTML(RichRuns.Run("")), "")
    }
}
