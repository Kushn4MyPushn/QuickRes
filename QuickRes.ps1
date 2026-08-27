$ErrorActionPreference = "Stop"

$RepoOwner = "Kushn4MyPushn"
$RepoName  = "QuickRes"

$InstallDir = Join-Path $env:LOCALAPPDATA "QuickRes"
$ExePath = Join-Path $InstallDir "QuickRes.exe"
$VersionFile = Join-Path $InstallDir "version.txt"

$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "QuickRes.lnk"
$StartMenuShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "QuickRes.lnk"

function Get-LatestQuickResRelease {
    Write-Host ""
    Write-Host "Checking for the latest QuickRes release..."

    return Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest" `
        -Headers @{ "User-Agent" = "QuickRes-Installer" }
}

function Get-QuickResZip {
    param($Release)

    $Asset = $Release.assets |
        Where-Object { $_.name -match "(?i)^QuickRes.*\.zip$" } |
        Select-Object -First 1

    if (-not $Asset) {
        $Asset = $Release.assets |
            Where-Object { $_.name -match "(?i)\.zip$" } |
            Select-Object -First 1
    }

    if (-not $Asset) {
        throw "Could not find the QuickRes ZIP file in the latest GitHub release."
    }

    return $Asset
}

function Stop-QuickRes {
    Get-Process -Name "QuickRes" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function New-QuickResShortcut {
    param(
        [string]$ShortcutPath
    )

    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)

    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.Description = "QuickRes"
    $Shortcut.IconLocation = "$ExePath,0"

    $Shortcut.Save()
}

function Install-QuickRes {
    param($Release)

    $Asset = Get-QuickResZip -Release $Release

    $TempRoot = Join-Path $env:TEMP ("QuickRes-" + [Guid]::NewGuid().ToString())
    $ZipPath = Join-Path $TempRoot "QuickRes.zip"
    $ExtractPath = Join-Path $TempRoot "Extracted"

    try {
        New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

        Write-Host ""
        Write-Host "Downloading QuickRes $($Release.tag_name)..."

        Invoke-WebRequest `
            -Uri $Asset.browser_download_url `
            -OutFile $ZipPath `
            -UseBasicParsing

        # Verify GitHub's SHA-256 digest when available.
        if ($Asset.digest -and $Asset.digest -match "^sha256:(.+)$") {
            $ExpectedHash = $Matches[1].ToLower()
            $ActualHash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()

            if ($ActualHash -ne $ExpectedHash) {
                throw "Security check failed: downloaded ZIP hash does not match GitHub."
            }

            Write-Host "Download verified."
        }

        Write-Host "Extracting QuickRes..."

        Expand-Archive `
            -Path $ZipPath `
            -DestinationPath $ExtractPath `
            -Force

        $SourceExe = Get-ChildItem `
            -Path $ExtractPath `
            -Filter "QuickRes.exe" `
            -File `
            -Recurse |
            Select-Object -First 1

        if (-not $SourceExe) {
            throw "QuickRes.exe was not found inside the downloaded ZIP."
        }

        $SourceDir = $SourceExe.Directory.FullName

        Stop-QuickRes

        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

        # Replace the actual application runtime while avoiding unnecessary
        # deletion of other files that may contain user preferences.
        $InternalPath = Join-Path $InstallDir "_internal"

        if (Test-Path $InternalPath) {
            Remove-Item $InternalPath -Recurse -Force
        }

        if (Test-Path $ExePath) {
            Remove-Item $ExePath -Force
        }

        Get-ChildItem -Path $SourceDir | ForEach-Object {
            Copy-Item `
                -Path $_.FullName `
                -Destination $InstallDir `
                -Recurse `
                -Force
        }

        if (-not (Test-Path $ExePath)) {
            throw "Installation failed because QuickRes.exe was not copied correctly."
        }

        Set-Content `
            -Path $VersionFile `
            -Value $Release.tag_name `
            -Encoding ASCII

        Write-Host "Creating shortcuts..."

        New-QuickResShortcut -ShortcutPath $DesktopShortcut
        New-QuickResShortcut -ShortcutPath $StartMenuShortcut

        Write-Host ""
        Write-Host "QuickRes $($Release.tag_name) installed successfully."
        Write-Host "Installed to:"
        Write-Host $InstallDir
        Write-Host ""

        Start-Process $ExePath
    }
    finally {
        if (Test-Path $TempRoot) {
            Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Uninstall-QuickRes {
    Write-Host ""
    Write-Host "Uninstalling QuickRes..."

    Stop-QuickRes

    if (Test-Path $DesktopShortcut) {
        Remove-Item $DesktopShortcut -Force
    }

    if (Test-Path $StartMenuShortcut) {
        Remove-Item $StartMenuShortcut -Force
    }

    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
    }

    Write-Host ""
    Write-Host "QuickRes has been uninstalled."
    Write-Host ""
}

Clear-Host

Write-Host "======================================"
Write-Host "              QUICKRES"
Write-Host "======================================"
Write-Host ""

if (-not (Test-Path $ExePath)) {

    Write-Host "QuickRes is not installed."
    Write-Host ""

    $Release = Get-LatestQuickResRelease

    Write-Host "Latest version: $($Release.tag_name)"
    Write-Host ""

    Install-QuickRes -Release $Release

}
else {

    $InstalledVersion = "Unknown"

    if (Test-Path $VersionFile) {
        $InstalledVersion = (Get-Content $VersionFile -Raw).Trim()
    }

    $Release = $null
    $LatestVersion = "Unable to check"

    try {
        $Release = Get-LatestQuickResRelease
        $LatestVersion = $Release.tag_name
    }
    catch {
        Write-Host "Could not contact GitHub to check for updates."
    }

    Write-Host ""
    Write-Host "Installed version: $InstalledVersion"
    Write-Host "Latest version:    $LatestVersion"
    Write-Host ""
    Write-Host "[1] Update / Repair QuickRes"
    Write-Host "[2] Uninstall QuickRes"
    Write-Host "[3] Cancel"
    Write-Host ""

    $Choice = Read-Host "Choose 1, 2, or 3"

    switch ($Choice) {

        "1" {
            if (-not $Release) {
                throw "Cannot update because GitHub could not be reached."
            }

            Install-QuickRes -Release $Release
        }

        "2" {
            $Confirm = Read-Host "Type YES to uninstall QuickRes"

            if ($Confirm -eq "YES") {
                Uninstall-QuickRes
            }
            else {
                Write-Host "Uninstall cancelled."
            }
        }

        default {
            Write-Host "Cancelled."
        }
    }
}
