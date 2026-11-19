# delete-apk.ps1
#
# Removes an installed Win.apk app by its library name, optionally also deleting
# everything the app saved (Android data + shared storage), mirroring the
# launcher's Remove flow so installed_apps.json and shortcuts stay consistent.
#
# Usage:
#   .\scripts\delete-apk.ps1 "AiVerse"
#   .\scripts\delete-apk.ps1 -Name "AiVerse" -WithData
#   .\scripts\delete-apk.ps1 -Name "AiVerse" -WithData -DataDir "$env:LOCALAPPDATA\Win.apk"
#
# Requires: Windows PowerShell 5.1 or PowerShell 7+. Runs entirely in the user
# profile (%LOCALAPPDATA%\Win.apk); nothing is installed system-wide.

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Name,

    [switch] $WithData,

    [string] $DataDir = "$env:LOCALAPPDATA\Win.apk"
)

$ErrorActionPreference = 'Stop'

# Resolve (and validate) the Win.apk data dir.  Resolve-Path may return a
# PathInfo or a string depending on the host, so coerce to a plain string.
$resolvedDir = Resolve-Path $DataDir -ErrorAction SilentlyContinue
if (-not $resolvedDir) {
    Write-Error "Win.apk data dir not found: $DataDir`n  (set -DataDir if Win.apk stores its data elsewhere)"
    exit 1
}
$dataDir = "$resolvedDir"
$libraryDir = Join-Path $dataDir 'library'
$appsDir    = Join-Path $dataDir 'apps'
$androidDir = Join-Path $dataDir 'android'
$registry   = Join-Path $dataDir 'installed_apps.json'

if (-not (Test-Path $libraryDir)) {
    Write-Error "Win.apk library not found: $libraryDir"
    exit 1
}

# --- Find the app by library name -------------------------------------------
# The library holds "<name>.apk", "<name>.label", "<name>.package", ... so an
# app is identified by the stem of those files (or by .label content == name).
# Collect candidate app NAMES (stems), not individual files, so an app with
# several sidecars counts as one match.
$candidateNames = @()
foreach ($f in Get-ChildItem -Path $libraryDir -File -ErrorAction SilentlyContinue) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    if ($stem -eq $Name) { $candidateNames += $stem }
}
# Also accept a name that matches .label content even if the stem differs.
foreach ($f in Get-ChildItem -Path $libraryDir -Filter '*.label' -File -ErrorAction SilentlyContinue) {
    $label = try { [System.IO.File]::ReadAllText($f.FullName) } catch { '' }
    if ($label -eq $Name) { $candidateNames += [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
}
$candidateNames = @($candidateNames | Select-Object -Unique)

if ($candidateNames.Count -eq 0) {
    Write-Error "No installed Win.apk app named '$Name' found in $libraryDir"
    exit 1
}
if ($candidateNames.Count -gt 1) {
    Write-Error "Multiple library entries match '$Name':`n  $($candidateNames -join "`n  ")`n  Use a more specific name."
    exit 1
}
$appName = $candidateNames[0]

$labelFile   = Join-Path $libraryDir "$appName.label"
$packageFile = Join-Path $libraryDir "$appName.package"
$label = if (Test-Path $labelFile) { [System.IO.File]::ReadAllText($labelFile).Trim() } else { $appName }
$pkg   = if (Test-Path $packageFile) { (Get-Content -Path $packageFile -TotalCount 1).Trim() } else { $null }

Write-Host "Removing: $appName  (label: $label)" -ForegroundColor Cyan
if ($pkg) { Write-Host "Package:  $pkg" -ForegroundColor Cyan }
if ($WithData) { Write-Host "WithData: yes - Android data and shared-storage folders will be deleted" -ForegroundColor Yellow }

# --- Stop the app if it is running ------------------------------------------
# A running app is a winapk-runtime.exe whose command line references this app's
# library APK. Terminate it so its files can be removed.
$libApk = Join-Path $libraryDir "$appName.apk"
# Also match any split-bundle extension the app may have been installed as.
$apkCandidates = @('.apk', '.apkm', '.xapk', '.apks') | ForEach-Object { Join-Path $libraryDir ("$appName$_") } | Where-Object { Test-Path $_ }

$stopped = $false
foreach ($proc in Get-Process -Name 'winapk-runtime' -ErrorAction SilentlyContinue) {
    try {
        $cmd = $proc.Path
        $match = $apkCandidates | Where-Object { $cmd -like "*$_*" }
        if ($match) {
            if ($PSCmdlet.ShouldProcess("stop running process $($proc.Id) ($cmd)", "terminate")) {
                $proc | Stop-Process -Force
                $stopped = $true
                Write-Host "Stopped running app (pid $($proc.Id))."
            }
        }
    } catch {
        # Process may have exited already; ignore.
    }
}

# Give the runtime a moment to release file handles / its install mutex.
if ($stopped) {
    Start-Sleep -Milliseconds 700
}

# --- Collect everything to delete -------------------------------------------
$toRemove = New-Object System.Collections.Generic.List[string]

# Library sidecar files and the APK itself.
foreach ($ext in @('.apk', '.apkm', '.xapk', '.apks', '.label', '.package', '.ico', '.window', '.activity', '.orientation')) {
    $p = Join-Path $libraryDir ("$appName$ext")
    if (Test-Path $p) { $toRemove.Add($p) }
}
# Previous/fallback APKs left by a cut-off update (e.g. "<name>.previous.apk").
foreach ($p in Get-ChildItem -Path $libraryDir -Filter "$appName*" -File -ErrorAction SilentlyContinue) {
    if ($toRemove -notcontains $p.FullName) { $toRemove.Add($p.FullName) }
}
# The per-app folder under apps\.
$appDir = Join-Path $appsDir $appName
if (Test-Path $appDir) { $toRemove.Add($appDir) }
# The ".<name>.installed" marker the loader checks.
$installedMarker = Join-Path $androidDir "data\app\.$appName.installed"
if (Test-Path $installedMarker) { $toRemove.Add($installedMarker) }

# Shortcuts: Start menu "Win.apk Apps" and Desktop, matched by target pointing
# at this app's library APK (robust regardless of the exact safe-file name).
$shortcutFolders = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Win.apk Apps'),
    [Environment]::GetFolderPath('Desktop')
)
foreach ($folder in $shortcutFolders) {
    if (-not (Test-Path $folder)) { continue }
    foreach ($lnk in Get-ChildItem -Path $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue) {
        try {
            $sh = New-Object -ComObject WScript.Shell
            $target = $sh.CreateShortcut($lnk.FullName).TargetPath
            $sh = $null
            if ($target -and ($apkCandidates | Where-Object { $target -like "*$_*" })) {
                $toRemove.Add($lnk.FullName)
            }
        } catch {
            # Not a readable shortcut; skip.
        }
    }
}

# Android data / shared storage (only with -WithData).
if ($WithData -and $pkg) {
    $pkgW = $pkg
    foreach ($d in @(
        (Join-Path $androidDir "data\data\$pkgW"),
        (Join-Path $androidDir "sdcard\Android\data\$pkgW"),
        (Join-Path $androidDir "sdcard\Android\obb\$pkgW")
    )) {
        if (Test-Path $d) { $toRemove.Add($d) }
    }
    # Older runs may have stored data under "<package>_<version>" folders.
    $dataParent = Join-Path $androidDir "data\data"
    if (Test-Path $dataParent) {
        foreach ($d in Get-ChildItem -Path $dataParent -Filter "${pkgW}_*" -Directory -ErrorAction SilentlyContinue) {
            $toRemove.Add($d.FullName)
        }
    }
}

if ($toRemove.Count -eq 0) {
    Write-Host "Nothing to delete for '$appName'."
    exit 0
}

# De-duplicate the same file reached through different path spellings (e.g. short
# vs long 8.3 names) so we never report a failure for a file already deleted.
$unique = New-Object System.Collections.Generic.List[string]
$seen   = New-Object System.Collections.Generic.HashSet[string]
foreach ($p in $toRemove) {
    $fp = [System.IO.Path]::GetFullPath($p)
    if (-not $seen.Contains($fp)) {
        $seen.Add($fp) | Out-Null
        $unique.Add($p)
    }
}
$toRemove = $unique

Write-Host "`nWill remove:" -ForegroundColor DarkCyan
$toRemove | ForEach-Object { Write-Host "  $_" }

$action = "delete Win.apk app '$appName'"
if ($WithData) { $action += " and its data" }
if (-not $PSCmdlet.ShouldProcess($action, "remove")) {
    Write-Host "Cancelled."
    exit 0
}

# --- Perform deletion -------------------------------------------------------
$failed = @()
foreach ($p in $toRemove) {
    try {
        if ((Get-Item $p -ErrorAction SilentlyContinue).PSIsContainer) {
            Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
        } else {
            Remove-Item -Path $p -Force -ErrorAction Stop
        }
        Write-Host "  removed: $p" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED: $p`n        $($_.Exception.Message)" -ForegroundColor Red
        $failed += $p
    }
}

# --- Refresh installed_apps.json registry -----------------------------------
# Drop every registry row whose dirName (library name) matches this app.
if (Test-Path $registry) {
    try {
        $json = Get-Content -Path $registry -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $apps = @($json.apps)
        $kept = $apps | Where-Object { $_.dirName -ne $appName }
        $out = @{ schema = 2; apps = @($kept) } | ConvertTo-Json -Depth 10
        $tmp = "$registry.tmp"
        [System.IO.File]::WriteAllText($tmp, $out)
        Move-Item -Path $tmp -Destination $registry -Force
        Write-Host "  updated: $registry (removed app row)" -ForegroundColor Green
    } catch {
        Write-Host ("  WARNING: could not update " + $registry + ": " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

if ($failed.Count -gt 0) {
    Write-Host "`nSome items could not be removed (file in use? close the app and retry):" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "`nDone. App '$appName' removed.`n" -ForegroundColor Green
exit 0
