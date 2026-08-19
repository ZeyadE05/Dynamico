import SwiftUI
import UniformTypeIdentifiers

public struct FileShelfView: View {
    @ObservedObject var shelfManager = FileShelfManager.shared
    @State private var isTargeted: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text("File Shelf Drop Zone")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))

                    if !shelfManager.stagedFiles.isEmpty {
                        Text("\(shelfManager.stagedFiles.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0, green: 210/255, blue: 255/255)))
                            .foregroundColor(.black)
                    }
                }

                Spacer()

                if !shelfManager.stagedFiles.isEmpty {
                    Button(action: {
                        shelfManager.clearAll()
                    }) {
                        Text("Clear All")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
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
    }

    private var dropZoneArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color(red: 0, green: 210/255, blue: 255/255) : Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? Color.blue.opacity(0.12) : Color.white.opacity(0.02)))

            VStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundColor(isTargeted ? Color(red: 0, green: 210/255, blue: 255/255) : Color.white.opacity(0.35))

                Text(isTargeted ? "Drop Files to Stage" : "Drag files here to stage temporarily")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isTargeted ? Color(red: 0, green: 210/255, blue: 255/255) : Color.white.opacity(0.6))

                Text("Drag files back out to Finder or Slack anytime")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.35))
            }
        }
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
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: file.fileIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

                Button(action: {
                    shelfManager.removeFile(file)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.4))
                        .background(Circle().fill(Color.black))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }

            VStack(spacing: 2) {
                Text(file.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: 68)

                Text(file.sizeFormatted)
                    .font(.system(size: 8))
                    .foregroundColor(Color.white.opacity(0.35))
            }
        }
        .onDrag {
            NSItemProvider(object: file.url as NSURL)
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
                            shelfManager.stageFiles(from: [url])
                        }
                    }
                    return
                }

                Task { @MainActor in
                    shelfManager.stageFiles(from: [url])
                }
            }
            handled = true
        }
        return handled
    }
}
