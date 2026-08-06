# 12 — BUILD & SHIP WITHOUT A MAC

You develop on Windows; GitHub Actions' macOS runners do the compiling, signing, and uploading.
This is a well-trodden path — the only genuinely hard part is code signing, and it's hard exactly once.

**Get this working in Phase 4, before the codebase is large.** Debugging signing against 300 files is
miserable; against a hello-world SwiftUI app it takes an afternoon.

---

## 1. THE THREE THINGS THAT MAKE THIS WORK

1. **XcodeGen** — the `.xcodeproj` is generated from `project.yml` on the runner. You never touch a
   binary project file, never hit a merge conflict in `.pbxproj`, and can add files by just creating
   them on disk.
2. **App Store Connect API key** — replaces Apple-ID password auth entirely. No 2FA prompts in CI.
3. **fastlane match** — stores your certificates and provisioning profiles, encrypted, in a private
   Git repo. The runner decrypts them at build time. You never need Keychain Access, so you never need
   a Mac.

---

## 2. ONE-TIME SETUP

### 2.1 App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API → **+**
Role **App Manager**. Download the `.p8` **once** (it is never downloadable again).
Record: **Key ID**, **Issuer ID**, and the `.p8` contents.

### 2.2 Private match repo

Create a **private** GitHub repo `amblyo-certificates`. Generate a fine-grained PAT with read/write
contents on it only. Choose a long random `MATCH_PASSWORD`.

### 2.3 Bootstrap the certificates — **run this on the runner, not your PC**

You cannot run `match` on Windows. Trigger it once via a manual workflow:

```yaml
# .github/workflows/bootstrap-signing.yml
name: Bootstrap Signing
on: workflow_dispatch
jobs:
  bootstrap:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.3', bundler-cache: true }
      - name: Create App Store Connect API key file
        run: |
          mkdir -p ~/private_keys
          echo "${{ secrets.ASC_KEY_P8 }}" > ~/private_keys/AuthKey_${{ secrets.ASC_KEY_ID }}.p8
      - name: Generate certs + profiles
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_AUTH }}
        run: bundle exec fastlane bootstrap
```

Run it **once from the GitHub UI**. It creates the distribution certificate and App Store profile and
commits them encrypted to the match repo. From then on every build just decrypts them.

### 2.4 GitHub secrets to create

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | Full `.p8` contents including BEGIN/END lines |
| `MATCH_PASSWORD` | Your match encryption passphrase |
| `MATCH_GIT_AUTH` | `base64("username:PAT")` |
| `TEAM_ID` | 10-char Apple Team ID |

---

## 3. FILES

### `project.yml` (XcodeGen)

```yaml
name: Amblyo
options:
  bundleIdPrefix: com.amblyo
  deploymentTarget: { iOS: "17.0" }
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    DEVELOPMENT_TEAM: QAT93YWVSF
    CODE_SIGN_STYLE: Manual
    ENABLE_USER_SCRIPT_SANDBOXING: YES
targets:
  Amblyo:
    type: application
    platform: iOS
    sources: [App]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.amblyo.app
        INFOPLIST_FILE: App/Info.plist
        TARGETED_DEVICE_FAMILY: "1,2"
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        PROVISIONING_PROFILE_SPECIFIER: match AppStore com.amblyo.app
        CODE_SIGN_IDENTITY: "Apple Distribution"
    entitlements:
      path: App/Amblyo.entitlements
      properties: {}
  AmblyoTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies: [{ target: Amblyo }]
  AmblyoUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies: [{ target: Amblyo }]
schemes:
  Amblyo:
    build: { targets: { Amblyo: all } }
    test: { targets: [AmblyoTests, AmblyoUITests], gatherCoverageData: true }
```

### `Gemfile`

```ruby
source "https://rubygems.org"
gem "fastlane"
gem "xcodeproj"
```

### `fastlane/Fastfile`

```ruby
default_platform(:ios)

APP_ID   = "com.amblyo.app"
SCHEME   = "Amblyo"

def asc_key
  app_store_connect_api_key(
    key_id:      ENV["ASC_KEY_ID"],
    issuer_id:   ENV["ASC_ISSUER_ID"],
    key_content: ENV["ASC_KEY_P8"],
    in_house:    false
  )
end

platform :ios do
  before_all { sh("xcodegen generate --spec ../project.yml") }

  desc "One-time: create certs and profiles"
  lane :bootstrap do
    match(type: "appstore", app_identifier: APP_ID, api_key: asc_key, readonly: false)
  end

  desc "Build and test — runs on every push"
  lane :ci do
    run_tests(
      scheme: SCHEME,
      devices: ["iPad Pro 13-inch (M4)", "iPhone 17 Pro"],
      code_coverage: true,
      result_bundle: true
    )
  end

  desc "Archive and upload to TestFlight"
  lane :beta do
    key = asc_key
    match(type: "appstore", app_identifier: APP_ID, api_key: key, readonly: true)
    increment_build_number(
      build_number: latest_testflight_build_number(api_key: key, app_identifier: APP_ID) + 1
    )
    build_app(
      scheme: SCHEME,
      export_method: "app-store",
      export_options: {
        provisioningProfiles: { APP_ID => "match AppStore #{APP_ID}" }
      }
    )
    upload_to_testflight(
      api_key: key,
      skip_waiting_for_build_processing: true,
      changelog: File.read("../CHANGELOG_LATEST.md") rescue "Internal build"
    )
  end

  desc "Push metadata + screenshots and submit for review"
  lane :release do
    key = asc_key
    upload_to_app_store(
      api_key: key,
      submit_for_review: true,
      automatic_release: false,
      force: true,                       # skip the HTML preview prompt
      precheck_include_in_app_purchases: true,
      submission_information: {
        add_id_info_uses_idfa: false,
        export_compliance_uses_encryption: false
      }
    )
  end
end
```

### `.github/workflows/ci.yml`

```yaml
name: CI
on:
  push:    { branches: [main, develop] }
  pull_request: { branches: [main] }
jobs:
  test:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: latest-stable }
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.3', bundler-cache: true }
      - run: brew install xcodegen
      - name: Claims lint
        run: python3 scripts/lint_claims.py     # fails the build on banned medical language
      - run: bundle exec fastlane ci
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: test-results, path: fastlane/test_output }
```

### `.github/workflows/release.yml`

```yaml
name: Release
on:
  push: { tags: ['v*'] }
  workflow_dispatch:
jobs:
  testflight:
    runs-on: macos-15
    timeout-minutes: 60
    env:
      ASC_KEY_ID:    ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      ASC_KEY_P8:    ${{ secrets.ASC_KEY_P8 }}
      MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
      MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_AUTH }}
      TEAM_ID: ${{ secrets.TEAM_ID }}
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: latest-stable }
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.3', bundler-cache: true }
      - run: brew install xcodegen
      - run: bundle exec fastlane beta
```

---

## 4. COST

- **Public repo → free, unlimited macOS minutes.**
- **Private repo → macOS carries a 10× multiplier.** The 2,000 free minutes/month become **200
  macOS minutes**. A full build+test cycle is roughly 10–15 minutes, so ~15 builds/month free.

**Recommendation:** keep the repo private and be disciplined — run the full pipeline on `main` and on
tags only, not on every branch push. Or budget ~$10–20/month for extra minutes. Do not make a health
app's repo public just to save minutes.

---

## 5. THE WINDOWS DEVELOPMENT LOOP (be realistic about this)

| You can do on Windows | You cannot do on Windows |
|---|---|
| Write all Swift, Markdown, YAML, Python | Run the iOS Simulator |
| Generate icons and screenshots | Use Xcode Previews |
| Edit `project.yml`, add files | Debug with breakpoints |
| Read CI logs and test results | Use Instruments |
| Manage App Store Connect in a browser | |

**Consequences you should plan for:**

- **Your feedback loop is ~10 minutes, not 2 seconds.** Write more unit tests than you normally would —
  `Core/Psychophysics` and `Core/Calibration` are pure logic and fully testable headlessly, which is
  exactly why `04` §7 puts the coverage targets there.
- **TestFlight is your simulator.** Ship to your own device early and often.
- **Use `swift-format` / `swiftlint` in CI** so style errors don't cost you a 10-minute round trip.
- **Consider a cloud Mac** (MacinCloud, ~$25/mo, or Scaleway Mac mini hourly) for the two or three
  moments where you genuinely need to see it run — first anaglyph calibration, and any layout bug you
  can't reproduce from a screenshot. This is optional but will save you hours during Phase 7.
- Xcode Cloud is an alternative to GitHub Actions and is configured entirely from App Store Connect in
  a browser — 25 free compute hours/month. Worth knowing about as a fallback if signing on Actions
  fights you.

---

## 6. TROUBLESHOOTING — THE FOUR FAILURES YOU WILL HIT

| Symptom | Cause | Fix |
|---|---|---|
| `No signing certificate "iOS Distribution" found` | `match` didn't run or ran read-only before bootstrap | Run `bootstrap-signing.yml` once from the Actions UI |
| `Provisioning profile doesn't match bundle identifier` | Bundle ID mismatch between `project.yml` and App Store Connect | They must be byte-identical, including case |
| `Product.products(for:)` returns `[]` | Paid Applications agreement unsigned, or products not "Ready to Submit" | App Store Connect → Agreements. This is the #1 StoreKit gotcha. |
| Build succeeds, TestFlight shows "Missing Compliance" | Export compliance not declared | Set `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` |
| `xcodegen: command not found` | Homebrew step missing/cached wrong | Pin `brew install xcodegen` before any fastlane lane |
