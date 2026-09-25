import SwiftUI
import ThubanDeskCore
import UIKit

/// A screen in the boards' shape: a 44 pt nav row under the status bar (leading back / pill, trailing 44 pt icon
/// buttons), a large serif title (34 pt) that scrolls away — its name then appears inline in the nav row — and the
/// content. The system navigation bar is hidden; the swipe-back gesture still works (see below).
struct PhoneScreen<NavLeading: View, NavTrailing: View, TitleAccessory: View, Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var subtitle: String?
    var scrolls = true
    @ViewBuilder var navLeading: () -> NavLeading
    @ViewBuilder var navTrailing: () -> NavTrailing
    @ViewBuilder var titleAccessory: () -> TitleAccessory
    @ViewBuilder var content: () -> Content
    @State private var collapsed = false

    init(title: String, subtitle: String? = nil, scrolls: Bool = true,
         @ViewBuilder navLeading: @escaping () -> NavLeading = { EmptyView() },
         @ViewBuilder navTrailing: @escaping () -> NavTrailing = { EmptyView() },
         @ViewBuilder titleAccessory: @escaping () -> TitleAccessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.navLeading = navLeading
        self.navTrailing = navTrailing
        self.titleAccessory = titleAccessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            navRow
            if scrolls {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleBlock
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 40
                } action: { _, isCollapsed in
                    withAnimation(.easeOut(duration: 0.15)) { collapsed = isCollapsed }
                }
            } else {
                titleBlock
                content()
            }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var navRow: some View {
        HStack(spacing: 4) {
            navLeading()
            Spacer(minLength: 8)
            navTrailing()
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: PhoneMetrics.navHeight)
        .overlay {
            if collapsed {
                Text(title).font(PhoneFont.inlineTitle).foregroundStyle(theme.inkColor).lineLimit(1)
                    .frame(maxWidth: 200)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .background(theme.bgColor)
        .overlay(alignment: .bottom) {
            if collapsed { Rectangle().fill(theme.lineColor).frame(height: 1) }
        }
        .zIndex(1)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(PhoneFont.largeTitle)
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                titleAccessory()
            }
            if let subtitle {
                Text(subtitle).font(PhoneFont.secondary).foregroundStyle(theme.inkDimColor)
            }
        }
        .padding(.horizontal, PhoneMetrics.gutter)
        .padding(.top, 2)
        .padding(.bottom, 14)
    }
}

// MARK: - Swipe back with a hidden navigation bar

/// SwiftUI disables the edge swipe when the navigation bar is hidden; every screen here hides it (custom nav rows),
/// so re-enable the interactive pop for stacks deeper than one.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
