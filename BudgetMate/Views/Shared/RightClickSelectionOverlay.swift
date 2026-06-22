import SwiftUI

#if os(macOS)
import AppKit

/// Transparent overlay that selects an item on right-click or control-click without blocking the context menu.
struct RightClickSelectionOverlay: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickTrackingView {
        let view = RightClickTrackingView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: RightClickTrackingView, context: Context) {
        view.onRightClick = onRightClick
    }
}

final class RightClickTrackingView: NSView {
    var onRightClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shouldInterceptCurrentEvent else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
        super.rightMouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        }
        super.mouseDown(with: event)
    }

    private var shouldInterceptCurrentEvent: Bool {
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return true
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }
}
#endif

extension View {
    func onRightClickSelect(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay {
            RightClickSelectionOverlay(onRightClick: action)
        }
        #else
        self
        #endif
    }

    /// Single tap selects; double tap edits. On macOS, right/control-click selects before the context menu.
    func onActivitySelectionTap(
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) -> some View {
        onTapGesture(count: 2, perform: onEdit)
            .onTapGesture(count: 1, perform: onSelect)
            .onRightClickSelect(perform: onSelect)
    }
}
