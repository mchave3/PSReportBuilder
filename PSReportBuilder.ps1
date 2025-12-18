#Requires -RunAsAdministrator
#Requires -Version 5.1

param(
    [switch] $Silent
)

#########################################################################
#
# Bootstrap
#
#########################################################################
#region Bootstrap

Clear-Host

# Start transcript for logging
$LogFilePath = Join-Path -Path $PSScriptRoot -ChildPath "PSReportBuilder_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $LogFilePath -Append -IncludeInvocationHeader -Force | Out-Null

Write-Host "-------------------------------------------------------------------------------------------"
Write-Host " PSReportBuilder - Bootstrap"
Write-Host "-------------------------------------------------------------------------------------------"
Write-Host ""

# Show error if current powershell environment does not have LanguageMode set to FullLanguage
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-Host "> Error: PSReportBuilder is unable to run on your system. PowerShell execution is restricted by security policies" -ForegroundColor Red
    AwaitForExit
}

# Necessary Modules
$requiredModules = @(
    @{ Name = "PSWriteHTML"; Version = "1.40.0" }
    @{ Name = "Microsoft.Graph.Authentication"}
)

# Install necessary modules if not already installed
foreach ($module in $requiredModules) {
    # Check if module version is specified
    if ($module.Version) {
        $isInstalled = Get-Module -ListAvailable -Name $module.Name | Where-Object { $_.Version -eq $module.Version }
        $versionInfo = "(Version $($module.Version))"
    }
    else {
        $isInstalled = Get-Module -ListAvailable -Name $module.Name
        $versionInfo = ""
    }

    if (-not $isInstalled) {
        Write-Host "> Installing required module: $($module.Name) $versionInfo" -ForegroundColor Yellow
        try {
            if ($module.Version) {
                Install-Module -Name $module.Name -RequiredVersion $module.Version -Scope AllUsers -Force -AllowClobber
            }
            else {
                Install-Module -Name $module.Name -Scope AllUsers -Force -AllowClobber
            }
            Write-Host "> Module $($module.Name) $versionInfo installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "> Error installing module $($module.Name) : $_" -ForegroundColor Red
            AwaitForExit
        }
    }
    else {
        Write-Host "> Required module $($module.Name) $versionInfo is already installed." -ForegroundColor Green
    }

    # Import the module
    Write-Host "> Importing module $($module.Name) $versionInfo..." -ForegroundColor Cyan
    try {
        if ($module.Version) {
            Import-Module -Name $module.Name -RequiredVersion $module.Version -Force
        }
        else {
            Import-Module -Name $module.Name -Force
        }
    }
    catch {
        Write-Host "> Error importing module $($module.Name) : $_" -ForegroundColor Red
        AwaitForExit
    }
}
#endregion Bootstrap

#########################################################################
#
# Classes
#
#########################################################################
#region Classes


#endregion Classes

#########################################################################
#
# Functions
#
#########################################################################
#region Functions

# Function to stop transcript if it was started
function Stop-PSReportBuilderTranscript {
    if (-not $TranscriptStarted) {
        return
    }

    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}

# Function to await for user input before exiting the script
function AwaitForExit {
    # Suppress prompt if Silent parameter was passed
    if (-not $Silent) {
        Write-Output ""
        Write-Output "Press any key to exit..."
        $null = [System.Console]::ReadKey()
    }

    Stop-PSReportBuilderTranscript
    exit
}
#endregion Functions

#########################################################################
#
# Main Script
#
#########################################################################
#region Main Script
Write-Host "Starting PSReportBuilder Get script..." -ForegroundColor Green

Stop-PSReportBuilderTranscript
#endregion Main Script
