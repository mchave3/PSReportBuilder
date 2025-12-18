# Show error if current powershell environment does not have LanguageMode set to FullLanguage
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
   Write-Host "Error: PSReportBuilder is unable to run on your system. PowerShell execution is restricted by security policies" -ForegroundColor Red
   Write-Output ""
   Write-Output "Press enter to exit..."
   Read-Host | Out-Null
   Exit
}

Clear-Host
Write-Output "-------------------------------------------------------------------------------------------"
Write-Output " PSReportBuilder Script - Get"
Write-Output "-------------------------------------------------------------------------------------------"

Write-Output "> Downloading PSReportBuilder..."

# Download latest version of PSReportBuilder from GitHub as zip archive
try {
    $LatestReleaseUri = (Invoke-RestMethod https://api.github.com/repos/mchave3/PSReportBuilder/releases/latest).zipball_url
    $zipPath = Join-Path $env:TEMP "PSReportBuilder.zip"
    Invoke-RestMethod $LatestReleaseUri -OutFile $zipPath

    # Validate downloaded file exists and has valid size
    if (-not (Test-Path $zipPath)) {
        throw "Downloaded file not found"
    }

    $fileInfo = Get-Item $zipPath
    if ($fileInfo.Length -lt 1KB) {
        throw "Downloaded file is too small (possibly corrupted)"
    }

    Write-Output "> Downloaded successfully ($([math]::Round($fileInfo.Length/1MB, 2)) MB)"
}
catch {
    Write-Host "Error: Unable to fetch latest release from GitHub. Please check your internet connection and try again." -ForegroundColor Red
    if ($_.Exception.Message) {
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    Exit
}

# Remove old script folder if it exists, except for CustomAppsList and SavedSettings files
if (Test-Path "$env:TEMP/PSReportBuilder") {
    Write-Output ""
    Write-Output "> Cleaning up old PSReportBuilder folder..."
    Get-ChildItem -Path "$env:TEMP/PSReportBuilder" -Exclude CustomAppsList,SavedSettings,PSReportBuilder.log | Remove-Item -Recurse -Force
}

Write-Output ""
Write-Output "> Unpacking..."

# Unzip archive to PSReportBuilder folder
try {
    $extractRoot = Join-Path $env:TEMP "PSReportBuilder"
    Expand-Archive $zipPath $extractRoot -Force -ErrorAction Stop
}
catch {
    Write-Host "Error: Failed to extract archive" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    Exit
}

# Remove archive
Remove-Item $zipPath -ErrorAction SilentlyContinue

# Move files
try {
    $extractedFolder = Get-ChildItem -Path (Join-Path $extractRoot "mchave3-PSReportBuilder-*") -Directory -ErrorAction Stop

    if (-not $extractedFolder) {
        throw "Extracted folder not found. Archive structure may have changed."
    }

    # Copy the extracted repository contents into the root folder without flattening the tree
    Copy-Item -Path (Join-Path $extractedFolder.FullName "*") -Destination $extractRoot -Recurse -Force -ErrorAction Stop
    Remove-Item -Path $extractedFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "Error: Failed to move extracted files" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    Exit
}

# Forward arguments passed to Get.ps1 to PSReportBuilder.ps1
$forwardedArguments = @($args)

Write-Output ""
Write-Output "> Running PSReportBuilder..."

# Validate main script exists before running
$mainScriptPath = Join-Path $extractRoot "PSReportBuilder.ps1"
if (-not (Test-Path $mainScriptPath)) {
    Write-Host "Error: PSReportBuilder.ps1 not found in extracted files" -ForegroundColor Red
    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    Exit
}

# Security warning for privilege elevation
Write-Host "WARNING: " -ForegroundColor Yellow -NoNewline
Write-Host "This script will request administrator privileges to run PSReportBuilder."
Write-Output ""

# Run PSReportBuilder script with the provided arguments
try {
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $mainScriptPath
    ) + $forwardedArguments

    $PSReportBuilderProcess = Start-Process powershell.exe -PassThru -ArgumentList $argumentList -Verb RunAs -ErrorAction Stop

    # Wait for the process to finish before continuing
    if ($null -ne $PSReportBuilderProcess) {
        $PSReportBuilderProcess.WaitForExit()
    }
    else {
        Write-Host "Warning: Process object is null. User may have declined UAC prompt." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: Failed to start PSReportBuilder" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    Exit
}

# Remove all remaining script files, except for CustomAppsList and SavedSettings files
if (Test-Path "$env:TEMP/PSReportBuilder") {
    Write-Output ""
    Write-Output "> Cleaning up..."

    # Cleanup, remove PSReportBuilder directory
    Get-ChildItem -Path "$env:TEMP/PSReportBuilder" -Exclude CustomAppsList,SavedSettings,PSReportBuilder.log | Remove-Item -Recurse -Force
}

Write-Output ""
