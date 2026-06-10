import SwiftUI

struct PendingUndo {
    let message: String
    let restore: () -> Void
}

struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
