function Pause-Exit {
    param(
        [int] $ExitCode = 1
    )

    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    exit $ExitCode
}

$zipPath = Join-Path $env:TEMP "PSReportBuilder.zip"
$extractRoot = Join-Path $env:TEMP "PSReportBuilder"

# Show error if current powershell environment does not have LanguageMode set to FullLanguage
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-Host "Error: PSReportBuilder is unable to run on your system. PowerShell execution is restricted by security policies" -ForegroundColor Red
    Pause-Exit
}

try {
    Clear-Host
}
catch {
}
Write-Output "-------------------------------------------------------------------------------------------"
Write-Output " PSReportBuilder Script - Get"
Write-Output "-------------------------------------------------------------------------------------------"
Write-Output ""
Write-Output "> Downloading PSReportBuilder..."

# Download latest version of PSReportBuilder from GitHub as zip archive
try {
    $gitHubApiHeaders = @{
        "Accept"     = "application/vnd.github+json"
        "User-Agent" = "PSReportBuilder-Get.ps1"
    }

    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/mchave3/PSReportBuilder/releases/latest" -Headers $gitHubApiHeaders
    if (-not $latestRelease.zipball_url) {
        throw "GitHub API response did not include zipball_url"
    }

    if ($latestRelease.tag_name) {
        Write-Output ("> Latest release: {0}" -f $latestRelease.tag_name)
    }
    if ($latestRelease.html_url) {
        Write-Output ("> Release page: {0}" -f $latestRelease.html_url)
    }

    Invoke-RestMethod -Uri $latestRelease.zipball_url -OutFile $zipPath

    # Validate downloaded file exists and has valid size
    if (-not (Test-Path -LiteralPath $zipPath)) {
        throw "Downloaded file not found"
    }

    $fileInfo = Get-Item -LiteralPath $zipPath
    if ($fileInfo.Length -lt 1KB) {
        throw "Downloaded file is too small (possibly corrupted)"
    }

    Write-Output "> Downloaded successfully ($([math]::Round($fileInfo.Length / 1MB, 2)) MB)"

    $zipHash = Get-FileHash -Path $zipPath -Algorithm SHA256 -ErrorAction Stop
    Write-Output ("> Download SHA256: {0}" -f $zipHash.Hash)
}
catch {
    Write-Host "Error: Unable to fetch latest release from GitHub. Please check your internet connection and try again." -ForegroundColor Red
    if ($_.Exception.Message) {
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Exit
}

# Remove old script folder if it exists, except for CustomAppsList and SavedSettings files
if (Test-Path -LiteralPath $extractRoot) {
    Write-Output ""
    Write-Output "> Cleaning up old PSReportBuilder folder..."
    Get-ChildItem -Path $extractRoot -Exclude CustomAppsList, SavedSettings, PSReportBuilder.log | Remove-Item -Recurse -Force
}

Write-Output ""
Write-Output "> Unpacking..."

# Unzip archive to PSReportBuilder folder
try {
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force -ErrorAction Stop
}
catch {
    Write-Host "Error: Failed to extract archive" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Pause-Exit
}
finally {
    # Remove archive
    Remove-Item -LiteralPath $zipPath -ErrorAction SilentlyContinue
}

# Move files
try {
    $extractedFolder = Get-ChildItem -Path (Join-Path $extractRoot "mchave3-PSReportBuilder-*") -Directory -ErrorAction Stop
    if (-not $extractedFolder) {
        throw "Extracted folder not found. Archive structure may have changed."
    }

    # Copy the extracted repository contents into the root folder without flattening the tree
    Copy-Item -Path (Join-Path $extractedFolder.FullName "*") -Destination $extractRoot -Recurse -Force -ErrorAction Stop
    Remove-Item -LiteralPath $extractedFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "Error: Failed to move extracted files" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Pause-Exit
}

# Forward arguments passed to Get.ps1 to PSReportBuilder.ps1
$forwardedArguments = @($args)

Write-Output ""
Write-Output "> Running PSReportBuilder..."

# Validate main script exists before running
$mainScriptPath = Join-Path $extractRoot "PSReportBuilder.ps1"
if (-not (Test-Path -LiteralPath $mainScriptPath)) {
    Write-Host "Error: PSReportBuilder.ps1 not found in extracted files" -ForegroundColor Red
    Pause-Exit
}

# Security warning for privilege elevation
Write-Host "WARNING: " -ForegroundColor Yellow -NoNewline
Write-Host "This script will request administrator privileges to run PSReportBuilder."
Write-Output ""

try {
    $signature = Get-AuthenticodeSignature -FilePath $mainScriptPath -ErrorAction Stop
    Write-Output ("> Script signature: {0}" -f $signature.Status)

    if ($signature.Status -ne "Valid") {
        Write-Host "WARNING: " -ForegroundColor Yellow -NoNewline
        Write-Host "PSReportBuilder.ps1 is not Authenticode-signed with a valid signature. Only continue if you trust the source."
    }
}
catch {
    Write-Host "Warning: Unable to check Authenticode signature ($($_.Exception.Message))" -ForegroundColor Yellow
}

# Run PSReportBuilder script with the provided arguments
try {
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $mainScriptPath
    ) + $forwardedArguments

    $psReportBuilderProcess = Start-Process -FilePath "powershell.exe" -PassThru -ArgumentList $argumentList -Verb RunAs -ErrorAction Stop

    # Wait for the process to finish before continuing
    if ($null -ne $psReportBuilderProcess) {
        $psReportBuilderProcess.WaitForExit()
    }
    else {
        Write-Host "Warning: Process object is null. User may have declined UAC prompt." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: Failed to start PSReportBuilder" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Pause-Exit
}

# Remove all remaining script files, except for CustomAppsList and SavedSettings files
if (Test-Path -LiteralPath $extractRoot) {
    Write-Output ""
    Write-Output "> Cleaning up..."

    Get-ChildItem -Path $extractRoot -Exclude CustomAppsList, SavedSettings, PSReportBuilder.log | Remove-Item -Recurse -Force
}

Write-Output ""
