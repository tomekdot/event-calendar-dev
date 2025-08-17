<#
  build-op.ps1
  - Packs the plugin into a .op (zip) and copies a versioned .op to the Plugins folder (if present) or parent.
  - Usage: .\build-op.ps1 [-IncludeTests] [-DryRun]
#>

param(
    [switch]$IncludeTests,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Log([string]$msg, [Switch]$IsError) {
    if ($IsError) { Write-Host ("[ERROR] " + $msg) -ForegroundColor Red }
    else { Write-Host ("[INFO]  " + $msg) }
}

# Resolve plugin root robustly
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) {
    Write-Log "Cannot determine script path." -IsError
    exit 1
}
$root = (Get-Item -LiteralPath $scriptPath).Directory.FullName
Write-Log "Plugin root: $root"

# Normalize root for substring operations
$rootNormalized = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

# Read name/version from info.toml; fall back to folder name / 0.0.0
$tomlPath = Join-Path $root 'info.toml'
$name = Split-Path $root -Leaf
$version = '0.0.0'
if (Test-Path $tomlPath) {
    try {
        $toml = Get-Content -LiteralPath $tomlPath -Raw
        $match = [regex]::Match($toml, 'name\s*=\s*"(?<n>.*?)"')
        if ($match.Success) { $name = $match.Groups['n'].Value }
        $match = [regex]::Match($toml, 'version\s*=\s*"(?<v>.*?)"')
        if ($match.Success) { $version = $match.Groups['v'].Value }
    } catch {
        Write-Log "Failed to read info.toml: $_" -IsError
    }
}

# Filenames
$safeName = $name.ToLower() -replace '\s+', '-'
$folderName = Split-Path $root -Leaf
$versionedOutput = "$safeName-v$version.op"
$simpleOutput = "$folderName.op"

# Items and folders to include
$includeExtensions = '.as','.md','.toml','.ps1','.json'
$explicitFiles = '.editorconfig','.gitattributes','.gitignore','LICENSE','README.md','CHANGELOG.md','info.toml','build-op.ps1'
$includeDirs = @('assets','tools','.github')
if ($IncludeTests) { $includeDirs += 'tests' }

# Build list of files that would be copied
$toCopy = New-Object System.Collections.Generic.List[string]

# Root files
Get-ChildItem -LiteralPath $root -File -Force | ForEach-Object {
    $ext = $_.Extension.ToLower()
    if ($ext -and ($includeExtensions -contains $ext)) { $toCopy.Add($_.FullName); return }
    if ($explicitFiles -contains $_.Name) { $toCopy.Add($_.FullName); return }
}

# Top-level .as (safe-guard)
Get-ChildItem -LiteralPath $root -Filter '*.as' -File -Force | ForEach-Object { $toCopy.Add($_.FullName) }

# Directories
foreach ($d in $includeDirs) {
    $src = Join-Path $root $d
    if (Test-Path $src) {
        Get-ChildItem -LiteralPath $src -Recurse -File -Force | ForEach-Object { $toCopy.Add($_.FullName) }
    }
}

# Deduplicate
$toCopy = $toCopy | Sort-Object -Unique

# Exclude any .op files and anything under .git or .stage
$toCopy = $toCopy | Where-Object {
    ($_ -notmatch '\.op$') -and ($_ -notmatch '([\\/]\.git([\\/]|$))') -and ($_ -notmatch '([\\/]\.stage([\\/]|$))')
}

if ($DryRun) {
    Write-Log "Dry run: files that would be included in the .op:"
    $count = ($toCopy | Measure-Object).Count
    Write-Log "Total files: $count"
    $toCopy | ForEach-Object { Write-Host " - $_" }
    Write-Log "Dry run complete. No archives were created."
    return
}

# Prepare staging folder
$stage = Join-Path $root '.stage'
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

# Copy files preserving relative paths (platform-safe)
foreach ($f in $toCopy) {
    try {
        $full = (Get-Item -LiteralPath $f).FullName
        if ($full.StartsWith($rootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($rootNormalized.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        } else {
            # fallback: use file name only
            $rel = Split-Path $full -Leaf
        }
        $dest = Join-Path $stage $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $full -Destination $dest -Force
    } catch {
        Write-Log "Failed to copy $f : $_" -IsError
    }
}

# Remove any accidental .git inside stage
$gitInStage = Join-Path $stage '.git'
if (Test-Path $gitInStage) { Remove-Item -LiteralPath $gitInStage -Recurse -Force }

# Create archives
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPathSimple = Join-Path $root $simpleOutput
if (Test-Path $zipPathSimple) { Remove-Item -LiteralPath $zipPathSimple -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPathSimple)
Write-Log "Created $zipPathSimple"

# Find nearest Plugins ancestor for versioned output (robust)
$cur = $rootNormalized
$pluginsAncestor = $null
while ($true) {
    $leaf = Split-Path $cur -Leaf
    if ($leaf -ieq 'Plugins') { $pluginsAncestor = $cur; break }
    $parent = Split-Path $cur -Parent
    if (-not $parent -or $parent -eq $cur) { break }
    $cur = $parent
}
if (-not $pluginsAncestor) { $pluginsAncestor = Split-Path $root -Parent }

# Ensure destination exists
if (-not (Test-Path $pluginsAncestor)) { New-Item -ItemType Directory -Path $pluginsAncestor -Force | Out-Null }

$zipPathVersioned = Join-Path $pluginsAncestor $versionedOutput
if (Test-Path $zipPathVersioned) { Remove-Item -LiteralPath $zipPathVersioned -Force }
Copy-Item -LiteralPath $zipPathSimple -Destination $zipPathVersioned -Force
Write-Log "Copied versioned archive to $zipPathVersioned"

# Cleanup
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Log "Build complete."