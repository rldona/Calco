# Contributing

Calco is tiny right now. The useful ways to help, in order:

1. **Opinions.** If you animate for games, open an issue about anything in the README that looks wrong or missing.
2. **Format feedback.** `docs/format.md` is the contract with engines. Poke holes in it.
3. **Code.** Once the Metal canvas PoC is merged, issues will be labeled `good first issue`.

## Ground rules

- Swift 5.10+, SwiftUI, Metal. No third-party UI frameworks.
- Keep the canvas engine (`Calco/Canvas`) independent of SwiftUI. It should be testable without a view.
- One feature per PR. Small PRs get reviewed; big ones rot.
- Spanish and English are both fine in issues and PRs. Code and docs are in English.
