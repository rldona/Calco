# Calco user manual

The bilingual user guide (English at the root, Spanish under `es/`), built with [VitePress](https://vitepress.dev) and published to <https://rldona.github.io/Calco/> by `.github/workflows/manual.yml` on every push to `main` that touches this folder.

```bash
npm install
npm run dev       # live preview at http://localhost:5173/Calco/
npm run build     # static site in .vitepress/dist
```

## Screenshots

Images live in `public/`: full screens in `screens/<lang>/` and feature crops in `crops/<lang>/`. They come from the iPad Pro 11" simulator (2420×1668, landscape) with the demo project *Pip* (`swift scripts/make-pip.swift <folder>` writes `Pip.calco`; copy it into the app's Documents):

1. Take the screenshots into `raw/<lang>/<name>.png` (not committed), with the app set to that language in Preferences.
2. Run `swift scripts/crop.swift` to cut the status bar and the feature crops (boxes in the script) and save them as JPEG.

Each page in `guide/` has a twin with the same name in `es/guide/`; keep them in step.
