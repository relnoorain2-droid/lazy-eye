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
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $out = & git @Args 2>&1
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
$rulePrivateKey = 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
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

$contentHits = @()
foreach ($rule in $contentRules) {
    foreach ($file in $textFiles) {
        $hit = Select-String -Path $file.FullName -Pattern $rule.Pattern -Quiet -ErrorAction SilentlyContinue
        if ($hit) {
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

Invoke-Git add -A | Out-Null

$stagedRaw = Invoke-Git diff --cached --name-only
$staged = @()
if ($stagedRaw) {
    $staged = $stagedRaw -split "`r?`n" | Where-Object { $_ }
}

if ($staged.Count -eq 0) {
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

if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = Read-Host '  Commit message (Enter for a default)'
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = 'Amblyo: docs, scaffold, data layer, design system, CI'
    }
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
    Write-Host 'Next:' -ForegroundColor White
    Write-Host '  1. Confirm the repo is PRIVATE (Settings, then General)'
    Write-Host '  2. Continue docs/PHASE-4-SETUP.md from step 2'
    Write-Host '  3. CI runs automatically. The build job is EXPECTED to fail'
    Write-Host '     the first time. Send the errors over.'
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
