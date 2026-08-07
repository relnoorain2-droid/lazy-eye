# PHASE 4 — CI SETUP CHECKLIST

Everything on your side, in order. Browser only — no Mac needed at any point.
Budget about **an hour**, most of it waiting.

**All the code is written.** These steps connect it to your Apple and GitHub
accounts.

---

## ⚠️ Why this matters more than it looks

**Not one line of this project has been through a Swift compiler yet.** About
5,000 lines of Swift exist and have never been built. That is normal for this
workflow — you have no Mac, so the first compile was always going to happen on
CI — but it means the first `fastlane ci` run will almost certainly fail with a
list of compile errors.

**That is expected, not a disaster.** Paste the errors to me and I'll fix them.
The important thing is doing it **now**, at 5,000 lines, rather than at 20,000
after the exercise engine lands. The cost of a first compile grows with the
codebase, and Phase 5 onwards is where the volume is.

---

## How a build actually reaches TestFlight

Worth reading once, so the six secrets stop looking like arbitrary hoops.

**You cannot upload to TestFlight without keys.** Apple requires two things that
cannot be skipped or substituted:

1. **The app must be signed** with a distribution certificate Apple issued to
   your account. An unsigned `.ipa` is rejected at upload.
2. **The upload must be authenticated** as you.

The six secrets are just those two facts, stored somewhere the runner can reach.

### What happens when you push a tag

```
  You:  git tag v1.0.0 && git push origin v1.0.0
    |
    v
  1. GitHub starts a fresh macOS virtual machine
     (empty - no Xcode project, no certificates, nothing of yours)
    |
    v
  2. Checks out your code
    |
    v
  3. xcodegen reads project.yml -> generates Amblyo.xcodeproj
     (this is why you never need to open Xcode)
    |
    v
  4. fastlane match clones your PRIVATE certificates repo,
     decrypts it with MATCH_PASSWORD,
     installs the certificate into the VM's temporary keychain
     ---> this is the "prove the app is really from you" half
    |
    v
  5. xcodebuild compiles Swift -> signs the binary with that certificate
    |
    v
  6. The signed .ipa is uploaded to App Store Connect,
     authenticated with your .p8 API key
     ---> this is the "prove YOU are uploading it" half
    |
    v
  7. Apple processes the build (5-15 minutes)
    |
    v
  8. It appears in TestFlight on your iPhone
    |
    v
  9. The VM is destroyed. Certificates and keys vanish with it.
```

Step 9 is why this is safe: nothing persists on the runner. Each build fetches
what it needs and takes it to the grave.

### Which secret does what

| Secret | Answers the question |
|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | "Who are you?" - authenticates the upload |
| `MATCH_GIT_URL`, `MATCH_GIT_AUTH` | "Where are your certificates kept?" |
| `MATCH_PASSWORD` | "Prove you can decrypt them" |

### Alternatives, and why they were rejected

| Approach | Verdict |
|---|---|
| **Xcode Cloud** - Apple manages signing entirely, no keys to handle | **Not possible for you.** Creating a workflow requires Xcode; App Store Connect only manages workflows that already exist. Nothing to run it from on Windows. |
| **fastlane `cert` + `sigh`** - creates certificates on the fly, only needs the API key | Tempting, but a fresh CI runner has no private key, so it creates a **new certificate every build**. Apple allows only 2-3 distribution certificates, and you would exhaust them in a week - invalidating builds already in TestFlight. |
| **Manual `.p12` export** - export once, store as a secret | Works, but exporting a `.p12` requires Keychain Access, which requires a Mac. |
| **fastlane `match`** | **Chosen.** One-time setup, then every build just decrypts. Never creates a second certificate. |

### It is less work than it sounds

Three of the six secrets come from one page in App Store Connect (about
3 minutes). Two come from creating an empty repo and a token (about 5 minutes).
One you invent yourself. Then you never touch any of it again.

---

## Step 1 — Create the GitHub repo

1. Create a **private** repo, e.g. `amblyo`.
   Keep it private. It is a health app; a public repo saves CI minutes but is not
   worth it.
2. Push everything in `E:\Lazy Eye` to it.

```bash
cd "E:\Lazy Eye"
git init
git add .
git commit -m "Amblyo: docs, scaffold, data layer, design system, CI"
git branch -M main
git remote add origin https://github.com/YOUR_USER/amblyo.git
git push -u origin main
```

`.gitignore` already excludes `*.xcodeproj`, signing material and build output.
**Check `git status` before your first commit** — if you see a `.p8`, a `.p12` or
a `.mobileprovision`, stop and remove it.

---

## Step 2 — Create the certificates repo

A **second, separate, private** repo — this one holds your encrypted signing
material.

1. Create private repo `amblyo-certificates`. Leave it empty.
2. **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**
   - Repository access: **Only select repositories** → `amblyo-certificates`
   - Permissions: **Contents → Read and write**
   - Expiry: 1 year
3. Copy the token. You cannot see it again.

Now build the auth string. Run this in PowerShell:

```powershell
$user = "YOUR_GITHUB_USERNAME"
$token = "github_pat_..."
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${user}:${token}"))
```

Keep that base64 string — it becomes `MATCH_GIT_AUTH`.

---

## Step 3 — App Store Connect API key

1. **App Store Connect → Users and Access → Integrations → App Store Connect API**
2. Click **＋**. Name it `CI`. Access: **App Manager**.
3. **Download the `.p8` file.** You get exactly one chance — Apple will not let
   you download it again.
4. Note the **Key ID** (10 characters) and the **Issuer ID** (a long UUID at the
   top of the page).

---

## Step 4 — GitHub secrets

In your `amblyo` repo: **Settings → Secrets and variables → Actions → New repository secret.**

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | The 10-character Key ID from step 3 |
| `ASC_ISSUER_ID` | The Issuer ID UUID from step 3 |
| `ASC_KEY_P8` | **The entire contents** of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines. Open it in Notepad and copy everything. |
| `MATCH_PASSWORD` | A long random passphrase you invent. **Save it in your password manager — without it your certificates are unrecoverable.** |
| `MATCH_GIT_URL` | `https://github.com/YOUR_USER/amblyo-certificates` |
| `MATCH_GIT_AUTH` | The base64 string from step 2 |

---

## Step 5 — Create the App Store Connect record

1. **App Store Connect → Apps → ＋ → New App**
2. Platform **iOS** · Name **Amblyo: Lazy Eye Training** · Primary language
   **English (U.S.)** · Bundle ID **com.amblyo.app** · SKU **amblyo-001**
3. Full access.

This does not publish anything. It creates the container TestFlight uploads into.

---

## Step 6 — Sign the Paid Applications agreement

**App Store Connect → Business.** Complete:

- Paid Applications agreement
- Bank details
- Tax forms

**Do this before Phase 10.** Until it is complete and active, `Product.products(for:)`
returns an empty array and your paywall shows nothing — with no error message
explaining why. It is the single most common "my StoreKit is broken" cause, and
it is not a code problem.

While you are there: **Business → Small Business Program → Apply.** 15% instead
of 30%. You said you'd do it last — just make sure "last" is before your first
revenue month, since it only applies from the month after approval.

---

## Step 7 — Bootstrap signing

1. GitHub → **Actions** tab → **Bootstrap Signing (run once)** → **Run workflow**
2. Type `BOOTSTRAP` in the confirmation field → **Run**
3. Wait ~5 minutes.

If it succeeds, your `amblyo-certificates` repo now contains encrypted certs and
profiles. **You should never run this workflow again.**

---

## Step 8 — Get CI green

The **CI** workflow runs automatically on push. Open the Actions tab and watch.

**Expect the `build` job to fail the first time.** Order of operations:

1. The `lint` job should pass immediately — it already passes locally.
2. The `build` job compiles for the first time. Copy the full error output and
   send it to me. I'll fix the errors and you push again.
3. Repeat until green. Typically two or three rounds.

Once `ci` is green, run **Release to TestFlight** manually, install on your
iPhone 14 Pro, and Phase 4 is done.

---

## What runs, and what it costs

| Workflow | Trigger | Runner | Rough cost |
|---|---|---|---|
| `ci.yml` — lint | push, PR | ubuntu | free |
| `ci.yml` — build & test | push, PR | macos-15 | ~10 min ⇒ **~100 min** of your quota |
| `bootstrap-signing.yml` | manual, once | macos-15 | ~50 min of quota |
| `release.yml` | tag `v*` | macos-15 | ~20 min ⇒ **~200 min** of quota |

**Private repos get 2,000 free minutes/month, but macOS bills at a 10× multiplier
— so you effectively have 200 macOS minutes.** That is roughly 15–20 CI runs a
month.

To stay inside it:

- Push to `develop` in batches rather than after every small edit
- The lint job runs on free Linux minutes and catches compliance errors without
  touching the macOS quota
- If you go over, it is about **$0.08/minute** — a heavy month is $10–20. Do not
  make the repo public to save this.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No signing certificate "iOS Distribution" found` | bootstrap not run, or run before secrets existed | Re-check secrets, run bootstrap once |
| `Could not find profile matching com.amblyo.app` | Bundle ID mismatch | Must be byte-identical everywhere, including case |
| `Authentication credentials are missing or invalid` | `ASC_KEY_P8` truncated | Paste the whole file including BEGIN/END lines |
| `fatal: Authentication failed` on the match repo | `MATCH_GIT_AUTH` wrong | Rebuild the base64 string; no trailing newline |
| `xcodegen: command not found` | brew step skipped | Already in both workflows — check the log ordering |
| Products array empty in Phase 10 | Paid Applications agreement | Step 6 |
| Build succeeds, TestFlight says "Missing Compliance" | Export compliance | Already set in `Info.plist` — should not happen |

---

## When you are done

Tell me and I'll tick Phase 4 in `13-BUILD-ROADMAP.md` and start Phase 3c
(onboarding) or Phase 5 (exercise engine), whichever you prefer.
