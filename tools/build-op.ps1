param (
    [switch]$IncludeTests,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot -match 'tools$') { Split-Path $PSScriptRoot } else { $PSScriptRoot }
Set-Location $root

# Read info.toml for name and version (if exists)
$name = Split-Path $root -Leaf
$version = '0.0.0'
if (Test-Path 'info.toml') {
    $content = Get-Content 'info.toml' -Raw
    if ($content -match 'name\s*=\s*"([^"]+)"') { $name = $Matches[1] }
    if ($content -match 'version\s*=\s*"([^"]+)"') { $version = $Matches[1] }
}

$zipName = "$($name.ToLower() -replace '\s+', '-')-v$version.op"
Write-Host "Building $zipName..." -ForegroundColor Cyan

# Define patterns to exclude and directories to include
$excludePatterns = @('\.op$', '\.git', '\.stage', 'dist')
$includeDirs = @('assets', 'src', 'tools', '.github')
if ($IncludeTests) { $includeDirs += 'tests' }

# Calculate files to include
$files = Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $relPath = Resolve-Path $_.FullName -Relative
    $inAllowedDir = ($includeDirs | Where-Object { $relPath -like ".\$_*" })
    $isRootFile = ($_.DirectoryName -eq $root) # Include files in root (like info.toml) if they exist
    
    ($inAllowedDir -or $isRootFile) -and 
    -not ($excludePatterns | Where-Object { $relPath -match $_ })
}

if ($DryRun) {
    $files | ForEach-Object { Write-Host "Dry-run: Including $($_.FullName)" }
    return
}

# Create dist directory and zip file
$distDir = New-Item -ItemType Directory -Force -Path "dist"
$destPath = Join-Path $distDir $zipName

# Compress-Archive requires relative paths to avoid full directory structures inside the zip
$relativeFiles = $files | ForEach-Object { Resolve-Path $_.FullName -Relative }

if (Test-Path $destPath) { Remove-Item $destPath }
Compress-Archive -Path $relativeFiles -DestinationPath $destPath -CompressionLevel Optimal

Write-Host "Done! File created at: $destPath" -ForegroundColor Green