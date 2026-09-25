import Foundation
import XCTest
@testable import ThubanDeskCore

final class ClientSecretFileTests: XCTestCase {
    func testDesktopClientFile() throws {
        let json = #"{"installed":{"client_id":"123-abc.apps.googleusercontent.com","project_id":"thuban-desk","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","client_secret":"GOCSPX-secret","redirect_uris":["http://localhost"]}}"#
        let config = try ClientSecretFile.parse(Data(json.utf8))
        XCTAssertEqual(config.clientID, "123-abc.apps.googleusercontent.com")
        XCTAssertEqual(config.clientSecret, "GOCSPX-secret")
    }

    func testWebClientAndJunkAreRefused() {
        let web = #"{"web":{"client_id":"123-abc.apps.googleusercontent.com","client_secret":"x"}}"#
        XCTAssertThrowsError(try ClientSecretFile.parse(Data(web.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Desktop app"), error.localizedDescription)
        }
        XCTAssertThrowsError(try ClientSecretFile.parse(Data("hello".utf8)))
        let badID = #"{"installed":{"client_id":"not-a-client","client_secret":"x"}}"#
        XCTAssertThrowsError(try ClientSecretFile.parse(Data(badID.utf8)))
    }
}
