import SwiftUI

// MARK: - ToastView
// Bottom banner shown after every change, with Undo when the change can be
// reverted. Rendered once by ContentView from OrbitStore.toast.

struct ToastView: View {
    @Environment(OrbitStore.self) private var store
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: OrbitSpacing.md) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? OrbitColors.warning : OrbitColors.success)
            Text(toast.text)
                .font(OrbitTypography.captionMedium)
                .lineLimit(2)
            Spacer(minLength: OrbitSpacing.sm)
            if toast.canUndo && store.canUndo {
                Button("Undo") { store.undo() }
                    .font(OrbitTypography.captionMedium)
                    .buttonStyle(.borderless)
            }
            Button { store.dismissToast() } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm + 2)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, OrbitSpacing.md)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .combine)
    }
}
