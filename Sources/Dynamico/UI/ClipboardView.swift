import SwiftUI

public struct ClipboardView: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var copiedItemId: UUID? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Text("Clipboard History")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))

                    if !clipboardManager.items.isEmpty {
                        Text("\(clipboardManager.items.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                }

                Spacer()

                if !clipboardManager.items.isEmpty {
                    Button(action: {
                        clipboardManager.clearHistory()
                    }) {
                        Text("Clear")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if clipboardManager.items.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(Color.white.opacity(0.25))
                    Text("Clipboard is empty")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(clipboardManager.items) { item in
                            clipboardRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        Button(action: {
            clipboardManager.copyToClipboard(item)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                copiedItemId = item.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedItemId == item.id {
                    copiedItemId = nil
                }
            }
        }) {
            HStack(spacing: 10) {
                // Item Type Badge
                itemIcon(item)

                Text(item.displayTitle)
                    .font(item.type == .hexColor ? .system(size: 11, weight: .semibold, design: .monospaced) : .system(size: 11))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if copiedItemId == item.id {
                    Text("Copied")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func itemIcon(_ item: ClipboardItem) -> some View {
        switch item.type {
        case .hexColor:
            if let color = parseHexColor(item.content) {
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            } else {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.purple)
            }
        case .url:
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 0, green: 210/255, blue: 255/255))
        case .text:
            Image(systemName: "doc.text")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.4))
        case .image:
            if let nsImg = item.nsImage {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 1))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.orange)
            }
        case .rtf:
            Image(systemName: "text.alignleft")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.green)
        case .fileURL:
            Image(systemName: "doc.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.yellow)
        }
    }

    private func parseHexColor(_ hex: String) -> Color? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard cleanHex.count == 6 || cleanHex.count == 8 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}
