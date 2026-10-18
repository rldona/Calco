# Releasing

Two GitHub Actions workflows build Calco:

| Workflow | When | What |
|---|---|---|
| `ci.yml` | Every push to `main` and every pull request | Generates the project with xcodegen, builds and runs the tests on an iPad simulator. |
| `release.yml` | A tag `vX.Y.Z` is pushed | Tests, archives the app signed for App Store Connect, uploads it to **TestFlight** and publishes a **GitHub release**. |

The manual has its own workflow, `manual.yml`, that publishes <https://rldona.github.io/Calco/>.

## Making a release

1. In `CHANGELOG.md`, move what's under **Unreleased** to a new section `## [X.Y.Z] - YYYY-MM-DD`, and update the links at the bottom.
2. Set `MARKETING_VERSION` in `project.yml` to `X.Y.Z` (the release overrides it from the tag anyway; this keeps local builds honest).
3. Commit, then tag and push:

   ```bash
   git tag v0.7.0
   git push origin v0.7.0
   ```

The release gets:

- **Notes**: the `CHANGELOG.md` section for that version. The workflow stops before building if there's none.
- `Calco-X.Y.Z.ipa`: the app signed for App Store Connect, the same build that goes to TestFlight.
- `Calco-X.Y.Z-dSYMs.zip`: debug symbols for crash reports.
- `calco-unity-X.Y.Z.zip`: the Unity importer package.

The build number is the workflow's run number, so every upload to TestFlight is unique. A tag with a suffix (`v1.0.0-beta.1`) makes a prerelease.

## One-time setup

### 1. The app in App Store Connect

In [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**: platform iOS, bundle ID `dev.plazoleta.calco`, any name and SKU. TestFlight uploads need this record.

### 2. An App Store Connect API key

**Users and Access** → **Integrations** → **App Store Connect API** → **+**. Give it the **Admin** role, so Xcode can create the provisioning profile. Download the `.p8` file (only possible once) and note the **Key ID** and the **Issuer ID** shown at the top of the page.

### 3. An Apple Distribution certificate

In Xcode → **Settings** → **Accounts** → your team → **Manage Certificates** → **+** → **Apple Distribution**. Then in **Keychain Access**, find *Apple Distribution: …*, right-click → **Export**, save it as `.p12` with a password.

### 4. The repository secrets

In GitHub → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Secret | Value |
|---|---|
| `DISTRIBUTION_CERTIFICATE_P12` | The `.p12` in base64: `base64 -i dist.p12 \| pbcopy` |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | The `.p12` password |
| `ASC_KEY_ID` | The API key's Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_PRIVATE_KEY` | The whole content of the `.p8` file, including the `BEGIN` / `END` lines |

Or from a terminal with the GitHub CLI:

```bash
base64 -i dist.p12 | gh secret set DISTRIBUTION_CERTIFICATE_P12
gh secret set DISTRIBUTION_CERTIFICATE_PASSWORD
gh secret set ASC_KEY_ID
gh secret set ASC_ISSUER_ID
gh secret set ASC_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
```

If any is missing, the release workflow says which ones and stops before building.

### 5. Install it on your iPad with TestFlight

1. In App Store Connect → the app → **TestFlight** → **Internal Testing** → **+**, create a group (for example *Team*) and add yourself.
2. Install **TestFlight** from the App Store on the iPad and sign in with the same Apple ID.
3. After a release, the build takes a few minutes to process; then it appears in TestFlight with **Install**. Later builds show up there as updates.

The app declares no non-exempt encryption (`ITSAppUsesNonExemptEncryption` in `project.yml`), so builds don't wait on the export compliance question.

## Helper scripts

- `scripts/ci/changelog-section.sh X.Y.Z` prints a version's changelog section (try it before tagging).
- `scripts/ci/pick-simulator.sh` picks an iPad simulator for the tests.
- `scripts/ci/ExportOptions.plist`: App Store Connect export with automatic signing.
