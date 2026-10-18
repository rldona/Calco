import Metal

/// Holds one GPU texture per (clip, frame, layer). Lazily allocated.
/// The `Project` model is the source of truth for which keys should exist;
/// this is just the pixel storage behind it.
final class FrameStore {
    private let renderer: CanvasRenderer
    private var textures: [String: MTLTexture] = [:]

    init(renderer: CanvasRenderer) {
        self.renderer = renderer
    }

    private func key(_ clip: String, _ frame: String, _ layer: String) -> String {
        "\(clip)/\(frame)/\(layer)"
    }

    func texture(clip: String, frame: String, layer: String) -> MTLTexture? {
        let k = key(clip, frame, layer)
        if let t = textures[k] { return t }
        guard let t = renderer.makeLayerTexture() else { return nil }
        textures[k] = t
        return t
    }

    /// Existing texture only; nil means the layer is still blank and nothing needs compositing.
    func existingTexture(clip: String, frame: String, layer: String) -> MTLTexture? {
        textures[key(clip, frame, layer)]
    }

    func duplicate(clip: String, from source: String, to destination: String, layers: [String]) {
        for layer in layers {
            guard let src = existingTexture(clip: clip, frame: source, layer: layer),
                  let dst = texture(clip: clip, frame: destination, layer: layer) else { continue }
            renderer.copy(src, to: dst)
        }
    }

    func remove(clip: String, frame: String, layers: [String]) {
        for layer in layers {
            textures.removeValue(forKey: key(clip, frame, layer))
        }
    }

    func clear(clip: String, frame: String, layer: String) {
        if let t = existingTexture(clip: clip, frame: frame, layer: layer) {
            renderer.clear(t)
        }
    }
}
