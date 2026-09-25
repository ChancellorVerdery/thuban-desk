import SwiftUI
import ThubanDeskCore

/// A quiet centered spinner with a caption.
struct LoadingView: View {
    @Environment(\.thubanTheme) private var theme
    var text: String = "Loading…"

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Thin warn-tinted strip above content served from the cache after a failed refresh.
struct OfflineBanner: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var retry: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 12, weight: .semibold))
            Text(text).font(ThubanFont.small).lineLimit(1)
            Spacer()
            Button("Retry") { Task { await retry() } }.buttonStyle(GhostButtonStyle(height: 24, tinted: true, horizontalPadding: 8))
        }
        .foregroundStyle(theme.brassInkColor)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(theme.warnSoftColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}

/// Wraps a `Resource`: content when there is a value (cached or fresh), a spinner during the first load, an error
/// with Retry when nothing could be loaded, and an offline banner over cached content after a failed refresh.
struct ResourceStateView<Value: Codable & Sendable, Content: View>: View {
    let resource: Resource<Value>
    var emptyTitle: String = "Nothing here yet"
    var emptyMessage: String? = nil
    var isEmpty: (Value) -> Bool = { _ in false }
    var retry: () async -> Void
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        VStack(spacing: 0) {
            if let error = resource.error, resource.hasValue {
                OfflineBanner(text: "Showing saved data — \(error.localizedDescription)", retry: retry)
            }
            if let value = resource.value, !isEmpty(value) {
                content(value)
            } else if resource.isLoading && !resource.hasValue {
                LoadingView()
            } else if let error = resource.error, !resource.hasValue {
                EmptyState(title: "Couldn’t load", message: error.localizedDescription) {
                    Button("Try again") { Task { await retry() } }.buttonStyle(.thubanSecondary)
                }
            } else if resource.hasAttempted || resource.hasValue {
                EmptyState(title: emptyTitle, message: emptyMessage)
            } else {
                LoadingView()
            }
        }
    }
}
