import SwiftUI
import ImageIO
import UniformTypeIdentifiers

extension View {
    /// Picks PNGs (or a folder of them) and opens the guide sequence sheet for them. `replacing`
    /// is a guide layer whose sequence they replace; nil adds a new guide.
    func guideSequenceImport(isPresented: Binding<Bool>, state: EditorState, replacing: String? = nil) -> some View {
        modifier(GuideSequenceImport(isPresented: isPresented, state: state, replacing: replacing))
    }
}

private struct GuideSequenceImport: ViewModifier {
    @Binding var isPresented: Bool
    let state: EditorState
    let replacing: String?
    @State private var files: GuideSequenceFiles?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.png, .folder], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                let picked = GuideSequenceFiles.read(urls)
                if picked.names.isEmpty {
                    state.lastError = String(localized: "There are no PNG images there.", bundle: AppLanguage.bundle)
                } else {
                    files = picked
                }
            }
            .sheet(item: $files) { files in
                GuideSequenceSheet(state: state, files: files, replacing: replacing)
            }
    }
}

/// The picked images, in natural order, read while the files were reachable.
struct GuideSequenceFiles: Identifiable {
    let id = UUID()
    var names: [String]
    var data: [Data?]

    /// PNGs among `urls`, and inside any folder among them.
    static func read(_ urls: [URL]) -> GuideSequenceFiles {
        var found: [String: Data?] = [:]
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                for file in inside where file.pathExtension.lowercased() == "png" {
                    found[file.lastPathComponent] = try? Data(contentsOf: file)
                }
            } else if url.pathExtension.lowercased() == "png" {
                found[url.lastPathComponent] = try? Data(contentsOf: url)
            }
        }
        let names = GuideSequence.naturalOrder(Array(found.keys))
        return GuideSequenceFiles(names: names, data: names.map { found[$0] ?? nil })
    }

    /// Image `i`, decoded with its orientation, or nil when it can't be read.
    func image(_ i: Int) -> CGImage? { data.indices.contains(i) ? Self.decode(data[i]) : nil }

    static func decode(_ data: Data?) -> CGImage? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

/// The guide sequence's options, with the images over the clip as they'll land: where they go,
/// how they fit, and how faint.
struct GuideSequenceSheet: View {
    @Bindable var state: EditorState
    let files: GuideSequenceFiles
    let replacing: String?
    @Environment(\.dismiss) private var dismiss
    @State private var options = GuideSequence.Options.load()
    @State private var target: String?
    @State private var previewIndex = 0
    @State private var first: CGImage?
    @State private var shown: CGImage?
    @State private var progress: Double?

    private var guides: [Layer] { state.layers.filter(\.guide) }

    private var plan: GuideSequence.Plan {
        GuideSequence.plan(count: files.names.count, step: options.step,
                           start: options.startAtPlayhead ? state.frameIndex : 0,
                           existing: state.frames.count, createMissing: options.createMissing)
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    preview
                    if plan.images.count > 1 {
                        Slider(value: Binding(get: { Double(previewIndex) },
                                              set: { previewIndex = Int($0.rounded()) }),
                               in: 0...Double(plan.images.count - 1), step: 1)
                    }
                    Text(previewCaption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 340)
                Form { formContent }
                    .frame(minWidth: 360)
            }
            .padding(.horizontal, 20)
            .navigationTitle(replacing == nil ? "Sequence as guide" : "Replace sequence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(progress != nil) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { run() }.disabled(plan.images.isEmpty || progress != nil)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(progress != nil)
        .onAppear {
            target = replacing.flatMap { id in guides.first { $0.id == id }?.id }
            first = files.image(0)
            shown = first
        }
        .onChange(of: previewIndex) { _, i in
            shown = plan.images.indices.contains(i) ? files.image(plan.images[i]) : first
        }
        .onChange(of: options.step) { _, _ in previewIndex = 0; shown = first }
    }

    @ViewBuilder
    private var formContent: some View {
        Section("Images") {
            Text(files.names.count == 1 ? "1 image" : "\(files.names.count) images, in this order:")
                .font(.subheadline)
            Text(files.names.prefix(6).joined(separator: ", ") + (files.names.count > 6 ? "…" : ""))
                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3)
        }
        Section("Layer") {
            Picker("Into", selection: $target) {
                Text("New guide layer").tag(String?.none)
                ForEach(guides) { Text($0.name).tag(Optional($0.id)) }
            }
        }
        Section("Frames") {
            CompactStepper(title: "Use one image in", value: $options.step, range: 1...12)
            CompactStepper(title: "New frames last", value: $options.hold, range: 1...24)
            Picker("Start at", selection: $options.startAtPlayhead) {
                Text("Frame 1").tag(false)
                Text("Frame \(state.frameIndex + 1) (playhead)").tag(true)
            }
            Toggle("Add the frames that are missing", isOn: $options.createMissing)
            Text(framesSummary).font(.caption).foregroundStyle(plan.leftOut > 0 ? Theme.accentText : .secondary)
        }
        Section("Fit") {
            Picker("Fit", selection: $options.fit) {
                Text("Whole").tag(GuideSequence.Fit.fit)
                Text("Cover").tag(GuideSequence.Fit.fill)
                Text("1:1").tag(GuideSequence.Fit.actual)
            }
            .pickerStyle(.segmented)
            CompactStepper(title: "Offset X", value: offsetBinding(\.offsetX), range: -4096...4096)
            CompactStepper(title: "Offset Y", value: offsetBinding(\.offsetY), range: -4096...4096)
        }
        Section("Look") {
            HStack {
                Text("Opacity")
                Slider(value: $options.opacity, in: 0.05...1)
                Text("\(Int((options.opacity * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            Picker("Tint", selection: $options.tint) {
                Text("None").tag(GuideSequence.Tint.none)
                Text("Red").tag(GuideSequence.Tint.red)
                Text("Blue").tag(GuideSequence.Tint.blue)
                Text("Green").tag(GuideSequence.Tint.green)
            }
            .pickerStyle(.segmented)
        }
        if let progress {
            Section { ProgressView(value: progress) { Text("Importing…") } }
        }
    }

    private func offsetBinding(_ key: WritableKeyPath<GuideSequence.Options, Double>) -> Binding<Int> {
        Binding(get: { Int(options[keyPath: key].rounded()) }, set: { options[keyPath: key] = Double($0) })
    }

    private var framesSummary: String {
        let p = plan
        if p.leftOut > 0 {
            return String(localized: "\(p.images.count) of \(p.images.count + p.leftOut) fit: the clip has no more frames.", bundle: AppLanguage.bundle)
        }
        if p.newFrames > 0 {
            return String(localized: "\(p.images.count) images, \(p.newFrames) new frames.", bundle: AppLanguage.bundle)
        }
        return String(localized: "\(p.images.count) images on the frames there are.", bundle: AppLanguage.bundle)
    }

    private var previewCaption: String {
        guard plan.images.indices.contains(previewIndex) else { return "" }
        let name = files.names[plan.images[previewIndex]]
        return String(localized: "Frame \(plan.frames[previewIndex] + 1): \(name)", bundle: AppLanguage.bundle)
    }

    private var canvas: CGSize { CGSize(width: state.renderer.canvasSize.x, height: state.renderer.canvasSize.y) }

    /// The frame the shown image goes to, as it is, with the image over it as it'll land.
    private var preview: some View {
        let frameIndex = plan.frames.indices.contains(previewIndex) ? plan.frames[previewIndex] : nil
        let under = frameIndex.flatMap { state.frames.indices.contains($0) ? state.frames[$0].id : nil }
            .flatMap { state.flattenedImage(clip: state.clip, frameID: $0) }
        let aspect = canvas.width / max(canvas.height, 1)
        return GeometryReader { geo in
            let k = geo.size.width / max(canvas.width, 1)
            ZStack(alignment: .topLeading) {
                Color.white
                if let under { Image(decorative: under, scale: 1).resizable() }
                if let shown, let firstSize = first.map({ CGSize(width: $0.width, height: $0.height) }) {
                    // The fit comes from the first image and applies to every one, like the import.
                    let r = GuideSequence.rect(for: firstSize, in: canvas, fit: options.fit,
                                               offset: CGPoint(x: options.offsetX, y: options.offsetY))
                    tinted(Image(decorative: shown, scale: 1).resizable())
                        .frame(width: r.width * k, height: r.height * k)
                        .offset(x: r.minX * k, y: r.minY * k)
                        .opacity(options.opacity)
                }
            }
            .clipped()
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline))
    }

    @ViewBuilder
    private func tinted(_ image: Image) -> some View {
        if let hex = options.tint.hex, let rgb = Layer(id: "", name: "", guide: true, tint: hex).guideTint {
            image.renderingMode(.template).foregroundStyle(Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)))
        } else {
            image
        }
    }

    /// Draws every image used at canvas size, off the main thread, then hands them to the editor.
    private func run() {
        options.save()
        let plan = plan, options = options, files = files, target = target
        let size = state.renderer.canvasSize, hard = state.project.pixelArt
        let rect = first.map { GuideSequence.rect(for: CGSize(width: $0.width, height: $0.height),
                                                  in: CGSize(width: size.x, height: size.y), fit: options.fit,
                                                  offset: CGPoint(x: options.offsetX, y: options.offsetY)) }
        progress = 0
        Task.detached(priority: .userInitiated) {
            var images: [[UInt8]?] = []
            for (n, i) in plan.images.enumerated() {
                let image = GuideSequenceFiles.decode(files.data[i])
                // Every image gets the first one's fit, whatever its own size.
                images.append(image.flatMap { img in
                    rect.map { GuideSequence.rasterize(img, into: $0, width: size.x, height: size.y, hard: hard) }
                })
                if plan.images.count > 30 {
                    let done = Double(n + 1) / Double(plan.images.count)
                    await MainActor.run { progress = done }
                }
            }
            let finished = images
            await MainActor.run {
                state.importGuideSequence(finished, plan: plan, hold: options.hold, replacing: target,
                                          opacity: options.opacity, tint: options.tint.hex)
                let broken = finished.filter { $0 == nil }.count
                if broken > 0 {
                    state.lastError = String(localized: "\(broken) of \(finished.count) images couldn't be read; their frames have no guide.",
                                             bundle: AppLanguage.bundle)
                }
                dismiss()
            }
        }
    }
}
