import SwiftUI

/// Fixed top/bottom zones that scroll a parent `ScrollView` while dragging near the viewport edge.
struct DragAutoScrollOverlay<ID: Hashable>: View {
    let scrollIDs: [ID]
    @Binding var scrollPosition: ID?
    var edgeHeight: CGFloat = 56
    var scrollInterval: Duration = .milliseconds(220)
    /// Height at the top of the overlay that should pass taps through to views underneath (e.g. a pinned picker).
    var excludedTopHeight: CGFloat = 0

    @State private var activeEdge: Edge?
    @State private var scrollTask: Task<Void, Never>?

    private enum Edge {
        case top
        case bottom
    }

    var body: some View {
        VStack(spacing: 0) {
            if excludedTopHeight > 0 {
                Color.clear
                    .frame(height: excludedTopHeight)
                    .allowsHitTesting(false)
            }
            scrollEdge(.top)
            Spacer(minLength: 0)
                .allowsHitTesting(false)
            scrollEdge(.bottom)
        }
        .onDisappear {
            stopScrolling()
        }
    }

    @ViewBuilder
    private func scrollEdge(_ edge: Edge) -> some View {
        Color.clear
            .frame(height: edgeHeight)
            .frame(maxWidth: .infinity)
            .dropDestination(for: String.self) { _, _ in
                false
            } isTargeted: { isTargeted in
                if isTargeted {
                    startScrolling(edge)
                } else if activeEdge == edge {
                    stopScrolling()
                }
            }
    }

    private func startScrolling(_ edge: Edge) {
        guard activeEdge != edge else { return }
        activeEdge = edge
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            while !Task.isCancelled {
                scrollOneStep(edge)
                try? await Task.sleep(for: scrollInterval)
            }
        }
    }

    private func stopScrolling() {
        activeEdge = nil
        scrollTask?.cancel()
        scrollTask = nil
    }

    private func scrollOneStep(_ edge: Edge) {
        guard !scrollIDs.isEmpty else { return }

        guard let scrollPosition,
              let currentIndex = scrollIDs.firstIndex(of: scrollPosition) else {
            return
        }

        let nextIndex: Int?
        switch edge {
        case .top:
            nextIndex = currentIndex > 0 ? currentIndex - 1 : nil
        case .bottom:
            nextIndex = currentIndex < scrollIDs.count - 1 ? currentIndex + 1 : nil
        }

        guard let nextIndex, scrollIDs.indices.contains(nextIndex) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            self.scrollPosition = scrollIDs[nextIndex]
        }
    }
}

enum TripDayScrollAnchor: Hashable {
    case unscheduled
    case day(Int)
}

struct TripDayScrollAnchorsKey: PreferenceKey {
    static var defaultValue: [TripDayScrollAnchor] = []

    static func reduce(value: inout [TripDayScrollAnchor], nextValue: () -> [TripDayScrollAnchor]) {
        value.append(contentsOf: nextValue())
    }
}
