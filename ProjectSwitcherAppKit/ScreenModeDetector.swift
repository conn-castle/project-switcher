import AppKit
import ProjectSwitcherCore

/// Detects screen mode based on physical monitor dimensions.
///
/// Uses `NSScreen` and `CGDisplayScreenSize` internally, but exposes only
/// Foundation/CoreGraphics types through the `ScreenModeDetecting` protocol.
public struct ScreenModeDetector: ScreenModeDetecting {
    public init() {}

    public func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> {
        switch physicalWidthInches(containingPoint: point) {
        case .success(let width):
            return .success(width < threshold ? .small : .wide)
        case .failure(let error):
            return .failure(error)
        }
    }

    public func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> {
        guard let screen = screen(containingPoint: point) else {
            return .failure(PsCoreError(
                category: .system,
                message: "No display found containing point (\(point.x), \(point.y))"
            ))
        }

        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return .failure(PsCoreError(
                category: .system,
                message: "Cannot determine display ID for screen containing point",
                detail: "NSScreenNumber not available in device description"
            ))
        }

        let physicalSize = CGDisplayScreenSize(screenNumber)
        let mmWidth = physicalSize.width

        guard mmWidth > 0 else {
            return .failure(PsCoreError(
                category: .system,
                message: "Cannot determine physical screen size",
                detail: "CGDisplayScreenSize returned 0mm width (broken EDID)"
            ))
        }

        return .success(mmWidth / 25.4)
    }

    public func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
        screen(containingPoint: point)?.visibleFrame
    }

    public func primaryScreenVisibleFrame() -> CGRect? {
        NSScreen.screens.first?.visibleFrame
    }

    // MARK: - Private

    private func screen(containingPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
