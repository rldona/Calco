# Releasing

Two GitHub Actions workflows build Calco:

| Workflow | When | What |
|---|---|---|
| `ci.yml` | Every push to `main` and every pull request | Generates the project with xcodegen, builds and runs the tests on an iPad simulator. |
| `release.yml` | A tag `vX.Y.Z` is pushed | Tests, builds the app for iPad **without signing it** and publishes a **GitHub release**. |

The manual has its own workflow, `manual.yml`, that publishes <https://rldona.github.io/Calco/>.

Neither needs secrets or the paid Apple Developer Program.

## Making a release

1. In `CHANGELOG.md`, move what's under **Unreleased** to a new section `## [X.Y.Z] - YYYY-MM-DD`, and update the links at the bottom.
2. Set `MARKETING_VERSION` in `project.yml` to `X.Y.Z` (the release overrides it from the tag anyway; this keeps local builds honest).
3. Commit, then tag and push:

   ```bash
   git tag v0.8.0
   git push origin v0.8.0
   ```

The release gets:

- **Notes**: the `CHANGELOG.md` section for that version. The workflow stops before building if there's none.
- `Calco-X.Y.Z-unsigned.ipa`: the app, built in Release, not signed.
- `calco-unity-X.Y.Z.zip`: the Unity importer package.

The build number is the workflow's run number. A tag with a suffix (`v1.0.0-beta.1`) makes a prerelease.

## Installing on an iPad

iPadOS only runs signed apps, and without the Developer Program there's no TestFlight or App Store. Two ways with a free Apple ID:

- **Over USB** (what we do): `scripts/install-ipad.sh` builds the checked-out code and installs it on the plugged-in iPad; after tagging a release, run it to have that version on the iPad. Or build from Xcode as the [README](../README.md#building) says.
- **The release's `.ipa`**: a sideloading tool signs it with your Apple ID and installs it.

Either way a free account's signature lasts **7 days**: after that the app doesn't open until it's installed again. Projects stay on the iPad.

## Helper scripts

- `scripts/install-ipad.sh [UDID]` builds and installs the app on a connected iPad.
- `scripts/ci/changelog-section.sh X.Y.Z` prints a version's changelog section (try it before tagging).
- `scripts/ci/pick-simulator.sh` picks an iPad simulator for the tests.
