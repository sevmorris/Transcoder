import SwiftUI

/// The panel type scale, in one place. The sizes are WaxOnWaxOff's `AppFont`,
/// the house scale the sibling apps' settings panels follow, so a label or a
/// caption reads the same size in each. Change them here, not at call sites.
///
/// The settings pane is a fixed 272 pt wide inside a vertical ScrollView, so a
/// larger size costs extra wrapping, never clipping.
enum AppFont {
    /// ALL-CAPS section and control labels: FORMAT, BITRATE, OUTPUT FOLDER.
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    /// Values and inline control text.
    static let value = Font.system(size: 13)
    /// Explanatory text under a control.
    static let help = Font.system(size: 12)
    /// A queue row's file name, and the line under it.
    static let rowTitle = Font.system(size: 13)
    static let rowDetail = Font.system(size: 11)
}

extension View {
    /// An ALL-CAPS panel label in the house style: small, semibold, spaced,
    /// in the accent colour.
    func panelLabel() -> some View {
        font(AppFont.sectionLabel)
            .foregroundStyle(Color.accentColor.opacity(0.8))
            .kerning(0.4)
    }
}
