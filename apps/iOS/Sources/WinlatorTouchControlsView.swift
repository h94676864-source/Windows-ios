import SwiftUI

struct WinlatorTouchControlsView: View {
    @State private var stickOffset: CGSize = .zero
    @State private var pressedButton: String?

    let onAction: (String) -> Void

    private let buttons = ["A", "B", "X", "Y"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            VStack(spacing: 5) {
                Text("MOVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.65))
                ZStack {
                    Circle().fill(.black.opacity(0.42))
                    Circle().stroke(.white.opacity(0.32), lineWidth: 1)
                    Circle().fill(.white.opacity(0.18)).frame(width: 34, height: 34)
                        .offset(stickOffset)
                }
                .frame(width: 112, height: 112)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let limit: CGFloat = 35
                        let dx = value.translation.width
                        let dy = value.translation.height
                        let length = max(1, hypot(dx, dy))
                        let scale = min(1, limit / length)
                        stickOffset = CGSize(width: dx * scale, height: dy * scale)
                        onAction("stick:\(stickOffset.width.rounded()),\(stickOffset.height.rounded())")
                    }
                    .onEnded { _ in
                        stickOffset = .zero
                        onAction("stick:center")
                    })
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton("Y")
                    actionButton("B")
                }
                HStack(spacing: 8) {
                    actionButton("X")
                    actionButton("A")
                }
            }
            .padding(.bottom, 8)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func actionButton(_ title: String) -> some View {
        Button {
            pressedButton = title
            onAction("button:\(title)")
        } label: {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(pressedButton == title ? Color.cyan.opacity(0.75) : Color.white.opacity(0.18), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in pressedButton = nil })
    }
}

struct WinlatorOnScreenKeyboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var lastKey = "None"

    private let rows = [
        Array("1234567890"),
        Array("QWERTYUIOP"),
        Array("ASDFGHJKL"),
        Array("ZXCVBNM")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Type text for Windows session", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .padding(.horizontal)

                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 5) {
                        ForEach(rows[index], id: \.self) { character in
                            key(String(character))
                        }
                    }
                }

                HStack(spacing: 8) {
                    specialKey("Ctrl")
                    specialKey("Alt")
                    specialKey("Win")
                    specialKey("Shift")
                    specialKey("⌫")
                }
                HStack(spacing: 8) {
                    specialKey("Tab")
                    specialKey("Esc")
                    Button("Space") { text.append(" "); lastKey = "Space" }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    specialKey("↵")
                }

                Text("Last key: \(lastKey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Keyboard preview — input forwarding activates with the Windows runtime.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .navigationTitle("On-screen keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func key(_ value: String) -> some View {
        Button(value) {
            text.append(value.lowercased())
            lastKey = value
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .buttonStyle(.plain)
    }

    private func specialKey(_ value: String) -> some View {
        Button(value) { lastKey = value }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
    }
}
