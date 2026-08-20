import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct FileShelfView: View {
    @ObservedObject var shelfManager = FileShelfManager.shared
    @State private var isTargeted: Bool = false
    @State private var hoveredCardId: UUID? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text("File Shelf Drop Zone")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    if !shelfManager.stagedFiles.isEmpty {
                        Text("\(shelfManager.stagedFiles.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.cyanAccent))
                            .foregroundColor(.black)
                    }
                }

                Spacer()

                if !shelfManager.stagedFiles.isEmpty {
                    Button(action: {
                        Theme.playHaptic(.levelChange)
                        shelfManager.clearAll()
                    }) {
                        Text("Clear All")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.todoistRed.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .pointerCursorOnHover()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if shelfManager.stagedFiles.isEmpty {
                dropZoneArea
            } else {
                stagedFilesList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            return handleDrop(providers: providers)
        }
        .onChange(of: isTargeted) { newValue in
            NotchPanelController.shared.trackingController?.updateDragTargeted(newValue)
            if newValue {
                Theme.playHaptic(.alignment)
            }
        }
    }

    private var dropZoneArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargeted ? Theme.cyanAccent : Color.white.opacity(Theme.surfaceActive),
                    style: StrokeStyle(lineWidth: isTargeted ? 2.0 : 1.5, dash: [5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Theme.cyanAccent.opacity(0.15) : Color.white.opacity(Theme.surfaceLow))
                )
                .shadow(color: isTargeted ? Theme.cyanAccent.opacity(0.35) : Color.clear, radius: 8, x: 0, y: 0)

            VStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundColor(isTargeted ? Theme.cyanAccent : Theme.textSecondary)

                Text(isTargeted ? "Drop Files to Stage" : "Drag files here to stage temporarily")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isTargeted ? Theme.cyanAccent : Theme.textPrimary)

                Text("Drag files back out to Finder, Slack, or email anytime")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .scaleEffect(isTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var stagedFilesList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(shelfManager.stagedFiles) { file in
                    stagedFileCard(file)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func stagedFileCard(_ file: StagedFile) -> some View {
        let isHovered = (hoveredCardId == file.id)

        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: file.fileIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .padding(8)
                    .background(Color.white.opacity(isHovered ? Theme.surfaceActive : Theme.surfaceLow))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isHovered ? Theme.cyanAccent.opacity(0.4) : Color.white.opacity(Theme.surfaceMid), lineWidth: 1)
                    )

                Button(action: {
                    Theme.playHaptic(.alignment)
                    shelfManager.removeFile(file)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .background(Circle().fill(Color.black))
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()
                .offset(x: 4, y: -4)
            }

            VStack(spacing: 2) {
                Text(file.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 68)

                Text(file.sizeFormatted)
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            hoveredCardId = hovering ? file.id : nil
        }
        .onDrag {
            Theme.playHaptic(.alignment)
            return NSItemProvider(object: file.url as NSURL)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { itemData, _ in
                guard let data = itemData as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    if let url = itemData as? URL {
                        Task { @MainActor in
                            Theme.playHaptic(.levelChange)
                            shelfManager.stageFiles(from: [url])
                        }
                    }
                    return
                }

                Task { @MainActor in
                    Theme.playHaptic(.levelChange)
                    shelfManager.stageFiles(from: [url])
                }
            }
            handled = true
        }
        return handled
    }
}
