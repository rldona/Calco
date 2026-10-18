import Metal
import CoreGraphics

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

    // MARK: - History

    /// The texture currently stored for a layer, without allocating one.
    func raw(_ k: LayerKey) -> MTLTexture? {
        textures[key(k.clip, k.frame, k.layer)]
    }

    /// Puts a texture back (or removes it with nil). Used by undo/redo to swap whole textures.
    func set(_ texture: MTLTexture?, for k: LayerKey) {
        textures[key(k.clip, k.frame, k.layer)] = texture
    }

    /// A fresh texture with the layer's current pixels; nil if the layer was never drawn on.
    func copy(of k: LayerKey) -> MTLTexture? {
        raw(k).flatMap(copy)
    }

    /// A fresh texture with the same pixels.
    func copy(_ src: MTLTexture) -> MTLTexture? {
        guard let dst = renderer.makeLayerTexture() else { return nil }
        renderer.copy(src, to: dst)
        return dst
    }

    // MARK: - Disk transfer

    /// Pixels of a layer for saving. Nil for a layer that was never drawn on (omitted from the package).
    func image(clip: String, frame: String, layer: String) -> CGImage? {
        existingTexture(clip: clip, frame: frame, layer: layer).flatMap(renderer.readback)
    }

    /// Fills a layer from a loaded PNG, allocating its texture.
    func load(_ image: CGImage, clip: String, frame: String, layer: String) {
        guard let t = texture(clip: clip, frame: frame, layer: layer) else { return }
        renderer.upload(image, into: t)
    }
}
