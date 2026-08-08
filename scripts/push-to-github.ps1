<#
.SYNOPSIS
    Safety-checks the working tree, then pushes Amblyo to GitHub.

.DESCRIPTION
    Steps:
      1. Check git
      2. Init the repo, set the per-repo commit identity, wire up the remote
      3. Scan for leaked secrets and refuse to continue if any are found
      4. Show what will be committed
      5. Commit and push

    Step 3 is why this exists rather than a plain list of commands. A .p8 key
    pushed to GitHub - even a private repo - must be revoked and regenerated,
    and if it is the App Store Connect key that means redoing signing setup.

    TWO RULES THIS FILE MUST KEEP:

    1. ASCII ONLY. Windows PowerShell 5.1 reads .ps1 files as Windows-1252,
       not UTF-8. Any em dash, curly quote or accented character becomes
       mojibake and can desynchronise the parser, producing syntax errors on
       unrelated lines. Do not paste smart punctuation into this file.

    2. $ErrorActionPreference stays "Continue". Under "Stop", PowerShell treats
       anything a native command writes to stderr as terminating - and git
       writes ordinary status messages to stderr. Exit codes are checked
       explicitly instead.

.EXAMPLE
    cd "E:\Lazy Eye"
    .\scripts\push-to-github.ps1

.EXAMPLE
    & "E:\Lazy Eye\scripts\push-to-github.ps1" -Message "Add exercise engine"
#>

[CmdletBinding()]
param(
    [string]$RepoUrl     = 'https://github.com/relnoorain2-droid/lazy-eye.git',
    [string]$Message     = '',
    [string]$Branch      = 'main',
    [string]$CommitEmail = 'relnoorain2@gmail.com',
    [string]$CommitName  = 'Noorulain Lari',
    [switch]$Force
)

# See rule 2 above. Do not change this to Stop.
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Write-Step { param($t) Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok   { param($t) Write-Host "  OK   $t" -ForegroundColor Green }
function Write-Warn { param($t) Write-Host "  WARN $t" -ForegroundColor Yellow }
function Write-Bad  { param($t) Write-Host "  STOP $t" -ForegroundColor Red }

# Runs git, captures stderr as text, returns trimmed stdout, sets $script:GitExit.
#
# THE PARAMETER IS NAMED $GitArgs, NOT $Args, AND THAT IS LOAD-BEARING.
#
# Two separate problems with $Args:
#   1. It is a PowerShell AUTOMATIC variable. Declaring a parameter with that
#      name shadows it and is asking for trouble.
#   2. PowerShell binds parameters by unique PREFIX. `Invoke-Git add -A` made
#      PowerShell read `-A` as the start of `-Args`, so it demanded a value for
#      it and the call failed with "Missing an argument for parameter 'Args'".
#
# That second one was not a loud failure. `git add -A` silently never ran, so
# nothing was staged, the script reported "nothing has changed", and the push
# happily re-pushed the PREVIOUS commit and said "Up to date". A whole session's
# work stayed on disk while the output looked like success.
#
# No git flag used here starts with "G", so with this name nothing binds by
# accident and everything reaches git as a plain argument.
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $out = & git @GitArgs 2>&1
    $script:GitExit = $LASTEXITCODE
    return ($out | Out-String).Trim()
}

Write-Host 'Amblyo to GitHub' -ForegroundColor White
Write-Host "Project root: $Root"

# ---------------------------------------------------------------------------
Write-Step '1. Git'

$gitVersion = Invoke-Git --version
if ($GitExit -ne 0) {
    Write-Bad 'Git is not installed, or not on your PATH.'
    Write-Host '  Install from https://git-scm.com/download/win, then reopen PowerShell.'
    exit 1
}
Write-Ok $gitVersion

# ---------------------------------------------------------------------------
Write-Step '2. Repository, identity and remote'

if (-not (Test-Path (Join-Path $Root '.git'))) {
    Invoke-Git init | Out-Null
    Invoke-Git branch -M $Branch | Out-Null
    Write-Ok "Initialised on branch '$Branch'"
} else {
    Write-Ok 'Repository already initialised'
    $current = Invoke-Git rev-parse --abbrev-ref HEAD
    if ($GitExit -eq 0 -and $current -and $current -ne $Branch -and $current -ne 'HEAD') {
        Write-Warn "On branch '$current' but pushing to '$Branch'"
    }
}

# Per-repository identity, so other projects keep their own settings.
# GitHub only links commits to your profile when the email is verified there.
Invoke-Git config user.name  $CommitName  | Out-Null
Invoke-Git config user.email $CommitEmail | Out-Null
Write-Ok "Commit identity for this repo: $CommitName <$CommitEmail>"

$globalEmail = Invoke-Git config --global user.email
if ($GitExit -eq 0 -and $globalEmail -and $globalEmail -ne $CommitEmail) {
    Write-Warn "Global git email is '$globalEmail'. Left alone; this repo overrides it."
}

# 'git remote' lists names and writes nothing to stderr when there are none.
# 'git remote get-url origin' DOES write to stderr, which broke an earlier version.
$remotes = Invoke-Git remote
$hasOrigin = ($remotes -split "`r?`n") -contains 'origin'

if (-not $hasOrigin) {
    Invoke-Git remote add origin $RepoUrl | Out-Null
    Write-Ok "Added remote 'origin' to $RepoUrl"
} else {
    $existing = Invoke-Git remote get-url origin
    if ($existing -ne $RepoUrl) {
        Invoke-Git remote set-url origin $RepoUrl | Out-Null
        Write-Warn "Remote was '$existing', updated to $RepoUrl"
    } else {
        Write-Ok "Remote 'origin' is $existing"
    }
}

# ---------------------------------------------------------------------------
Write-Step '3. Secret scan'

$forbiddenPatterns = @(
    '*.p8'
    '*.p12'
    '*.cer'
    '*.certSigningRequest'
    '*.mobileprovision'
    'AuthKey_*'
    '*.keystore'
    '*.jks'
    '.env'
    '.env.local'
)

$leaked = @()
foreach ($pattern in $forbiddenPatterns) {
    $found = Get-ChildItem -Path $Root -Filter $pattern -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\\.git\\' }
    if ($found) { $leaked += $found }
}

if ($leaked.Count -gt 0) {
    Write-Bad 'Signing material found in the project folder:'
    $leaked | ForEach-Object { Write-Host "       $($_.FullName)" -ForegroundColor Red }
    Write-Host ''
    Write-Host '  Move these OUTSIDE E:\Lazy Eye and put their contents in' -ForegroundColor Red
    Write-Host '  GitHub Secrets instead. See docs/PHASE-4-SETUP.md steps 3-4.' -ForegroundColor Red
    if (-not $Force) { exit 1 }
    Write-Warn 'Force given; continuing.'
} else {
    Write-Ok 'No key or certificate files present'
}

# Regex patterns are SINGLE quoted. In a double-quoted PowerShell string, $ and
# ` are special, and brace quantifiers next to them are easy to get wrong.
# DETECTS KEY MATERIAL, NOT THE WORDS "PRIVATE KEY".
#
# The previous rule matched the phrase anywhere, which blocked four files that
# contain no key at all: the grep guard in release.yml, the setup instructions
# telling you to copy the BEGIN and END lines, the membership test in
# apple_certs.py, and a progress-log entry describing those very three. A
# scanner that cries wolf gets bypassed with -Force, and then it protects
# nothing.
#
# A real PEM key is an envelope AROUND a long base64 body. Requiring at least
# two lines of 40+ base64 characters between the markers is what separates a key
# from a sentence about keys. Leading whitespace is allowed so a key pasted into
# an indented YAML block is still caught - that is a realistic way to leak one.
#
# Verified against 7 leak shapes (plain .p8, RSA, EC, OPENSSH, indented YAML,
# CRLF, inside a Swift string literal) and 6 false-positive shapes.
$rulePrivateKey = '-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----[\r\n]+(?:[ \t]*[A-Za-z0-9+/=]{40,}[ \t]*[\r\n]+){2,}[ \t]*-----END (?:[A-Z]+ )?PRIVATE KEY-----'
$ruleGitHubToken = 'gh[pousr]_[A-Za-z0-9]{16,}'
$rulePat = 'github_pat_[A-Za-z0-9_]{20,}'
$ruleAws = 'AKIA[0-9A-Z]{16}'

$contentRules = @(
    @{ Name = 'Private key block'; Pattern = $rulePrivateKey }
    @{ Name = 'GitHub token';      Pattern = $ruleGitHubToken }
    @{ Name = 'Fine-grained PAT';  Pattern = $rulePat }
    @{ Name = 'AWS access key';    Pattern = $ruleAws }
)

$textFiles = Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '\\\.git\\' -and
        $_.Extension -match '^\.(swift|md|yml|yaml|json|plist|py|rb|ps1|txt|xcprivacy|entitlements|storekit)$'
    }

# READS EACH FILE WHOLE, NOT LINE BY LINE.
#
# Select-String matches per line. The private-key rule spans several lines by
# design - that is the whole point of requiring a base64 body - so under
# Select-String it would silently never fire and the scan would report "clean"
# on a genuinely leaked key. Raw-mode reading is what makes the rule work.
$contentHits = @()
foreach ($file in $textFiles) {
    $text = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($text)) { continue }

    foreach ($rule in $contentRules) {
        if ([regex]::IsMatch($text, $rule.Pattern)) {
            $contentHits += ($rule.Name + ' in ' + $file.FullName)
        }
    }
}

if ($contentHits.Count -gt 0) {
    Write-Bad 'Possible credentials inside files:'
    $contentHits | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
    if (-not $Force) { exit 1 }
    Write-Warn 'Force given; continuing.'
} else {
    Write-Ok 'No credential patterns in tracked text files'
}

# ---------------------------------------------------------------------------
Write-Step '4. What will be committed'

$addOutput = Invoke-Git add -A
if ($GitExit -ne 0) {
    # Checked explicitly, because this is exactly where the script previously
    # lied. A failing `add` leaves nothing staged, which is indistinguishable
    # from "no changes" unless the exit code is read - and the script then
    # reported success while committing nothing.
    Write-Bad 'git add failed, so nothing was staged.'
    Write-Host "       $addOutput" -ForegroundColor Red
    exit 1
}

$stagedRaw = Invoke-Git diff --cached --name-only
$staged = @()
if ($stagedRaw) {
    $staged = $stagedRaw -split "`r?`n" | Where-Object { $_ }
}

if ($staged.Count -eq 0) {
    # Cross-check against the working tree before believing it. If git reports
    # dirty files but nothing is staged, `add` did not do its job and saying
    # "nothing has changed" would be wrong.
    $dirty = Invoke-Git status --porcelain
    if ($dirty) {
        Write-Bad 'There are uncommitted changes but nothing was staged.'
        Write-Host '       This means git add did not work. Nothing has been pushed.' -ForegroundColor Red
        Write-Host "       Working tree:" -ForegroundColor Red
        ($dirty -split "`r?`n" | Select-Object -First 10) | ForEach-Object {
            Write-Host "         $_" -ForegroundColor Red
        }
        exit 1
    }

    Write-Ok 'Nothing has changed since the last commit.'
    Write-Host "`n  Pushing anyway in case the last commit was never pushed." -ForegroundColor Cyan
    Invoke-Git push -u origin $Branch | Out-Host
    if ($GitExit -eq 0) { Write-Host "`nUp to date." -ForegroundColor Green }
    exit 0
}

Write-Host "  $($staged.Count) file(s):"
$staged | Select-Object -First 40 | ForEach-Object { Write-Host "    $_" }
if ($staged.Count -gt 40) {
    Write-Host "    ... and $($staged.Count - 40) more"
}

$dangerous = $staged | Where-Object {
    $_ -match '\.(p8|p12|cer|mobileprovision)$' -or $_ -match '\.xcodeproj'
}
if ($dangerous) {
    Write-Bad 'Staged but should be ignored:'
    $dangerous | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
    Write-Host "  Run 'git reset' and check .gitignore." -ForegroundColor Red
    exit 1
}
Write-Ok 'Nothing dangerous is staged'

# ---------------------------------------------------------------------------
Write-Step '5. Commit and push'

# NO PROMPT, AND NO STALE DEFAULT.
#
# This used to ask for a commit message and fall back to the Phase 1 text, which
# meant every commit either needed typing or was mislabelled. Neither is worth a
# human's attention: the message is derivable from what actually changed.
#
# Pass -Message to override when a commit deserves a real description.
if ([string]::IsNullOrWhiteSpace($Message)) {
    $changed = (Invoke-Git diff --cached --name-only) -split "`n" |
               Where-Object { $_ -and $_.Trim() -ne '' }

    $areas = @()
    if ($changed -match '^App/Core/Psychophysics/')   { $areas += 'adaptive engine' }
    if ($changed -match '^App/Core/Safety/')          { $areas += 'safety' }
    if ($changed -match '^App/Core/Stimuli/')         { $areas += 'stimuli' }
    if ($changed -match '^App/Core/Calibration/')     { $areas += 'calibration' }
    if ($changed -match '^App/Features/Exercises/')   { $areas += 'exercises' }
    if ($changed -match '^App/Features/Onboarding/')  { $areas += 'onboarding' }
    if ($changed -match '^App/Features/Train/')       { $areas += 'train' }
    if ($changed -match '^App/Purchases/')            { $areas += 'purchases' }
    if ($changed -match '^Tests/')                    { $areas += 'tests' }
    if ($changed -match '^\.github/')                 { $areas += 'ci' }
    if ($changed -match '^scripts/')                  { $areas += 'scripts' }
    if ($changed -match '^docs/')                     { $areas += 'docs' }
    if ($changed -match '\.xcassets/')                { $areas += 'assets' }

    $areas = $areas | Select-Object -Unique
    $count = @($changed).Count

    if ($areas.Count -gt 0) {
        $Message = 'Update ' + ($areas -join ', ') + " ($count files)"
    } else {
        $Message = "Update $count files"
    }
    Write-Host "  Message: $Message" -ForegroundColor DarkGray
}

Invoke-Git commit -m $Message | Out-Host
if ($GitExit -ne 0) {
    Write-Bad 'Commit failed. See the message above.'
    exit 1
}
Write-Ok 'Committed'

Write-Host "`n  Pushing to $RepoUrl" -ForegroundColor Cyan
Write-Host '  A browser window may open to authorise GitHub. That is expected.'

$pushOutput = Invoke-Git push -u origin $Branch
Write-Host $pushOutput

if ($GitExit -eq 0) {
    Write-Host "`nPushed successfully." -ForegroundColor Green
    Write-Host '  https://github.com/relnoorain2-droid/lazy-eye'
    Write-Host ''
    # This footer used to give Phase 4 setup instructions, which have been done
    # for weeks. Stale advice in a script you run every day is worse than none:
    # it either gets followed pointlessly or trains you to ignore the output.
    Write-Host 'CI is running now:' -ForegroundColor White
    Write-Host '  https://github.com/relnoorain2-droid/lazy-eye/actions'
    Write-Host ''
    Write-Host '  Lint takes about 10 seconds, build and test about 3 minutes.'
    Write-Host '  If it fails, send the lines containing "error:" and nothing else.'
    Write-Host ''
    Write-Host '  Note: the repo is PUBLIC, which is what makes Actions free.' -ForegroundColor DarkGray
    Write-Host '  Making it private again reinstates a 2,000 minute monthly cap,' -ForegroundColor DarkGray
    Write-Host '  billed at 10x for macOS - roughly four release builds.' -ForegroundColor DarkGray
} else {
    Write-Bad 'Push failed.'
    if ($pushOutput -match 'fetch first|rejected|non-fast-forward') {
        Write-Host "`n  The remote has commits you do not have, usually a README" -ForegroundColor Yellow
        Write-Host '  created with the repo. Run these two lines:' -ForegroundColor Yellow
        Write-Host "      git pull origin $Branch --allow-unrelated-histories" -ForegroundColor Yellow
        Write-Host "      git push -u origin $Branch" -ForegroundColor Yellow
    } elseif ($pushOutput -match 'Authentication|could not read|403') {
        Write-Host "`n  Authentication problem. Check you are signed in as" -ForegroundColor Yellow
        Write-Host '  relnoorain2-droid and that the repo exists.' -ForegroundColor Yellow
    }
    exit 1
}
