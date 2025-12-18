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
    Invoke-RestMethod $LatestReleaseUri -OutFile "$env:TEMP/PSReportBuilder.zip"
}
catch {
    Write-Host "Error: Unable to fetch latest release from GitHub. Please check your internet connection and try again." -ForegroundColor Red
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
Expand-Archive "$env:TEMP/PSReportBuilder.zip" "$env:TEMP/PSReportBuilder"

# Remove archive
Remove-Item "$env:TEMP/PSReportBuilder.zip"
# Move files
Get-ChildItem -Path "$env:TEMP/PSReportBuilder/mchave3-PSReportBuilder-*" -Recurse | Move-Item -Destination "$env:TEMP/PSReportBuilder"

# Make list of arguments to pass on to the script
$arguments = $($PSBoundParameters.GetEnumerator() | ForEach-Object {
    if ($_.Value -eq $true) {
        "-$($_.Key)"
    }
    else {
         "-$($_.Key) ""$($_.Value)"""
    }
})

Write-Output ""
Write-Output "> Running PSReportBuilder..."

# Run PSReportBuilder script with the provided arguments
$PSReportBuilderProcess = Start-Process powershell.exe -PassThru -ArgumentList "-executionpolicy bypass -File $env:TEMP\PSReportBuilder\PSReportBuilder.ps1 $arguments" -Verb RunAs

# Wait for the process to finish before continuing
if ($null -ne $PSReportBuilderProcess) {
    $PSReportBuilderProcess.WaitForExit()
}

# Remove all remaining script files, except for CustomAppsList and SavedSettings files
if (Test-Path "$env:TEMP/PSReportBuilder") {
    Write-Output ""
    Write-Output "> Cleaning up..."

    # Cleanup, remove PSReportBuilder directory
    Get-ChildItem -Path "$env:TEMP/PSReportBuilder" -Exclude CustomAppsList,SavedSettings,PSReportBuilder.log | Remove-Item -Recurse -Force
}

Write-Output ""