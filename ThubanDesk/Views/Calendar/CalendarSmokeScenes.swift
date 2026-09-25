import Foundation

/// Calendar screens for the smoke walk (owned by the Calendar engineer). Names sort the PNGs: 20–29.
enum CalendarSmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("20-calendar-week") { app in app.select(.calendar) },
    ]
}
