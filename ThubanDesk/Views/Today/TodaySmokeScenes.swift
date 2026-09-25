import Foundation

/// Today screens for the smoke walk (owned by the Today + Settings engineer). Names sort the PNGs: 40–49.
enum TodaySmokeScenes {
    static let scenes: [SmokeScene] = [
        SmokeScene("40-today") { app in app.select(.today) },
    ]
}
