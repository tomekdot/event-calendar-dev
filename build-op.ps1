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

function Write-Log($fmt, [Switch]$IsError) {
    if ($IsError) { Write-Host ("[ERROR] " + $fmt) -ForegroundColor Red }
    else { Write-Host ("[INFO]  " + $fmt) }
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Log "Plugin root: $root"

# Read name/version from info.toml; fall back to folder name / 0.0.0
$tomlPath = Join-Path $root 'info.toml'
$name = Split-Path $root -Leaf
$version = '0.0.0'
if (Test-Path $tomlPath) {
    try {
        $toml = Get-Content $tomlPath -Raw
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
$toCopy = @()

# Root files
Get-ChildItem -Path $root -File -Force | ForEach-Object {
    if ($_.Extension -and ($includeExtensions -contains $_.Extension.ToLower())) { $toCopy += $_.FullName; return }
    if ($explicitFiles -contains $_.Name) { $toCopy += $_.FullName; return }
}

# Top-level .as (safe-guard)
Get-ChildItem -Path $root -Filter '*.as' -File -Force | ForEach-Object { $toCopy += $_.FullName }

# Directories
foreach ($d in $includeDirs) {
    $src = Join-Path $root $d
    if (Test-Path $src) {
        # collect files under this dir
        Get-ChildItem -Path $src -Recurse -File -Force | ForEach-Object { $toCopy += $_.FullName }
    }
}

# Deduplicate
$toCopy = $toCopy | Sort-Object -Unique

# Exclude any .op files and anything under .git or .stage
$toCopy = $toCopy | Where-Object { $_ -notmatch '\.op$' -and ($_ -notmatch '\\.git\\' -and $_ -notmatch '\\.stage\\') }

if ($DryRun) {
    Write-Log "Dry run: files that would be included in the .op:"
    $toCopy | ForEach-Object { Write-Host " - $_" }
    Write-Log "Dry run complete. No archives were created."
    return
}

# Prepare staging folder
$stage = Join-Path $root '.stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

# Copy files preserving relative paths
foreach ($f in $toCopy) {
    try {
        $rel = Resolve-Path $f | ForEach-Object { $_.Path.Substring($root.Length).TrimStart('\\') }
        $dest = Join-Path $stage $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path $f -Destination $dest -Force
    } catch {
        Write-Log "Failed to copy $f : $_" -IsError
    }
}

# Remove any accidental .git inside stage
if (Test-Path (Join-Path $stage '.git')) { Remove-Item (Join-Path $stage '.git') -Recurse -Force }

# Create archives
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPathSimple = Join-Path $root $simpleOutput
if (Test-Path $zipPathSimple) { Remove-Item $zipPathSimple -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPathSimple)
Write-Log "Created $zipPathSimple"

# Find nearest Plugins ancestor for versioned output
$cur = $root
$pluginsAncestor = $null
while ($cur -and ($cur -ne (Split-Path $cur -Parent))) {
    if ((Split-Path $cur -Leaf) -ieq 'Plugins') { $pluginsAncestor = $cur; break }
    $cur = Split-Path $cur -Parent
}
if (-not $pluginsAncestor) { $pluginsAncestor = Split-Path $root -Parent }
$zipPathVersioned = Join-Path $pluginsAncestor $versionedOutput
if (Test-Path $zipPathVersioned) { Remove-Item $zipPathVersioned -Force }
Copy-Item $zipPathSimple -Destination $zipPathVersioned -Force
Write-Log "Copied versioned archive to $zipPathVersioned"

# Cleanup
Remove-Item $stage -Recurse -Force
Write-Log "Build complete."
