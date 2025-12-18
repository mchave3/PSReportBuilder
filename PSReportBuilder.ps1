#Requires -RunAsAdministrator
#Requires -Version 7.5

<#
.SYNOPSIS
    PowerShell Report Builder - Interactive HTML report generator

.DESCRIPTION
    WPF application for creating and editing HTML reports interactively.
    Based on the PSWriteHTML module for report generation.
    Supports multiple data sources: CSV, JSON, SQL Server, Microsoft Graph.

.PARAMETER Silent
    Runs the script without user interaction

.EXAMPLE
    .\PSReportBuilder.ps1
    Launches the Report Builder graphical interface

.NOTES
    Author: PSReportBuilder Team
    Version: 1.0.0
#>

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
$LogFilePath = Join-Path -Path $PSScriptRoot -ChildPath "Logs\PSReportBuilder_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFolder = Split-Path -Path $LogFilePath -Parent
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $LogFilePath -Append -IncludeInvocationHeader -Force | Out-Null
$Script:TranscriptStarted = $true

Write-Host "-------------------------------------------------------------------------------------------"
Write-Host " PowerShell Report Builder v1.0.0"
Write-Host " Interactive HTML report generator based on PSWriteHTML"
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
    @{ Name = "Microsoft.Graph.Authentication"; Required = $false }
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
        if ($module.Required -eq $false) {
            Write-Host "> Optional module $($module.Name) $versionInfo is not installed. Microsoft Graph features will be unavailable." -ForegroundColor Yellow
            continue
        }

        Write-Host "> Installing required module: $($module.Name) $versionInfo" -ForegroundColor Yellow
        try {
            if ($module.Version) {
                Install-Module -Name $module.Name -RequiredVersion $module.Version -Scope CurrentUser -Force -AllowClobber
            }
            else {
                Install-Module -Name $module.Name -Scope CurrentUser -Force -AllowClobber
            }
            Write-Host "> Module $($module.Name) $versionInfo installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "> Error installing module $($module.Name) : $_" -ForegroundColor Red
            if ($module.Required -ne $false) {
                AwaitForExit
            }
        }
    }
    else {
        Write-Host "> Module $($module.Name) $versionInfo is available." -ForegroundColor Green
    }

    # Import the module
    Write-Host "> Importing module $($module.Name) $versionInfo..." -ForegroundColor Cyan
    try {
        if ($module.Version) {
            Import-Module -Name $module.Name -RequiredVersion $module.Version -Force -ErrorAction SilentlyContinue
        }
        else {
            Import-Module -Name $module.Name -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        if ($module.Required -ne $false) {
            Write-Host "> Error importing module $($module.Name) : $_" -ForegroundColor Red
            AwaitForExit
        }
    }
}

# Import custom modules
Write-Host ""
Write-Host "> Loading PSReportBuilder modules..." -ForegroundColor Cyan

$modulesPath = Join-Path -Path $PSScriptRoot -ChildPath "Modules"
$modules = @(
    "ReportElements.psm1",
    "DataSources.psm1",
    "ReportGenerator.psm1"
)

foreach ($moduleName in $modules) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath $moduleName
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force
            Write-Host "  > Loaded: $moduleName" -ForegroundColor Green
        }
        catch {
            Write-Host "  > Error loading $moduleName : $_" -ForegroundColor Red
            AwaitForExit
        }
    }
    else {
        Write-Host "  > Module not found: $modulePath" -ForegroundColor Red
        AwaitForExit
    }
}

#endregion Bootstrap

#########################################################################
#
# Functions
#
#########################################################################
#region Functions

# Function to stop transcript if it was started
function Stop-PSReportBuilderTranscript {
    if (-not $Script:TranscriptStarted) {
        return
    }

    try {
        Stop-Transcript | Out-Null
        $Script:TranscriptStarted = $false
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

# Function to load XAML and create WPF window with Fluent theme
function New-WPFWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$XamlPath
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    if (-not (Test-Path $XamlPath)) {
        throw "XAML file not found: $XamlPath"
    }

    $xamlContent = Get-Content -Path $XamlPath -Raw

    # Remove x:Class attribute if present
    $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # Apply Fluent theme (requires PowerShell 7.5+ / .NET 9)
    # ThemeMode: System = follows Windows theme, Light, Dark, or None
    try {
        # Suppress experimental API warning WPF0001
        $window.ThemeMode = [System.Windows.ThemeMode]::System
    }
    catch {
        Write-Warning "Could not apply Fluent theme: $_"
    }

    return $window
}

# Function to find control by name in WPF window
function Get-WPFControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return $Window.FindName($Name)
}

# Function to update the report tree view
function Update-ReportTreeView {
    param(
        [System.Windows.Controls.TreeView]$TreeView,
        [object]$Report
    )

    $TreeView.Items.Clear()

    if ($null -eq $Report) {
        return
    }

    foreach ($element in $Report.Elements) {
        $item = New-TreeViewItem -Element $element
        $TreeView.Items.Add($item) | Out-Null
    }
}

# Function to create a TreeViewItem from a ReportElement
function New-TreeViewItem {
    param(
        [Parameter(Mandatory)]
        [object]$Element
    )

    $elementTypes = Get-ReportElementTypes
    $typeInfo = $elementTypes[$Element.Type]
    $icon = if ($typeInfo) { $typeInfo.Icon } else { "📄" }

    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = "$icon $($Element.Name)"
    $item.Tag = $Element

    foreach ($child in $Element.Children) {
        $childItem = New-TreeViewItem -Element $child
        $item.Items.Add($childItem) | Out-Null
    }

    return $item
}

# Function to update status bar
function Update-StatusBar {
    param(
        [System.Windows.Controls.TextBlock]$StatusText,
        [System.Windows.Controls.TextBlock]$StatusElements,
        [string]$Message,
        [object]$Report
    )

    if ($StatusText) {
        $StatusText.Text = $Message
    }

    if ($StatusElements -and $Report) {
        $count = 0
        foreach ($element in $Report.Elements) {
            $count += Get-ElementCount -Element $element
        }
        $StatusElements.Text = "Elements: $count"
    }
}

# Function to count elements recursively
function Get-ElementCount {
    param(
        [object]$Element
    )

    $count = 1
    foreach ($child in $Element.Children) {
        $count += Get-ElementCount -Element $child
    }
    return $count
}

# Function to update generated code
function Update-GeneratedCode {
    param(
        [System.Windows.Controls.TextBox]$CodeTextBox,
        [object]$Report
    )

    if ($null -eq $Report) {
        $CodeTextBox.Text = "# No report loaded"
        return
    }

    try {
        $code = Export-ReportCode -Report $Report
        $CodeTextBox.Text = $code
    }
    catch {
        $CodeTextBox.Text = "# Error generating code: $_"
    }
}

# Function to show data source dialog
function Show-DataSourceDialog {
    param(
        [System.Windows.Window]$Owner
    )

    $dialogPath = Join-Path -Path $PSScriptRoot -ChildPath "XAML\DataSourceDialog.xaml"
    $dialog = New-WPFWindow -XamlPath $dialogPath
    $dialog.Owner = $Owner

    # Get controls
    $txtName = Get-WPFControl -Window $dialog -Name "TxtDataSourceName"
    $cmbType = Get-WPFControl -Window $dialog -Name "CmbDataSourceType"
    $btnCancel = Get-WPFControl -Window $dialog -Name "BtnCancel"
    $btnSave = Get-WPFControl -Window $dialog -Name "BtnSaveDataSource"
    $btnTest = Get-WPFControl -Window $dialog -Name "BtnTestConnection"
    $btnBrowseCsv = Get-WPFControl -Window $dialog -Name "BtnBrowseCsv"
    $btnBrowseJson = Get-WPFControl -Window $dialog -Name "BtnBrowseJson"

    # Config panels
    $csvConfig = Get-WPFControl -Window $dialog -Name "CsvConfig"
    $jsonConfig = Get-WPFControl -Window $dialog -Name "JsonConfig"
    $sqlConfig = Get-WPFControl -Window $dialog -Name "SqlConfig"
    $graphConfig = Get-WPFControl -Window $dialog -Name "GraphConfig"
    $manualConfig = Get-WPFControl -Window $dialog -Name "ManualConfig"

    # Type change handler
    $cmbType.Add_SelectionChanged({
        $selectedItem = $cmbType.SelectedItem
        if ($null -eq $selectedItem) { return }

        $type = $selectedItem.Tag

        $csvConfig.Visibility = [System.Windows.Visibility]::Collapsed
        $jsonConfig.Visibility = [System.Windows.Visibility]::Collapsed
        $sqlConfig.Visibility = [System.Windows.Visibility]::Collapsed
        $graphConfig.Visibility = [System.Windows.Visibility]::Collapsed
        $manualConfig.Visibility = [System.Windows.Visibility]::Collapsed

        switch ($type) {
            "CSV" { $csvConfig.Visibility = [System.Windows.Visibility]::Visible }
            "JSON" { $jsonConfig.Visibility = [System.Windows.Visibility]::Visible }
            "SQL" { $sqlConfig.Visibility = [System.Windows.Visibility]::Visible }
            "Graph" { $graphConfig.Visibility = [System.Windows.Visibility]::Visible }
            "Manual" { $manualConfig.Visibility = [System.Windows.Visibility]::Visible }
        }
    })

    # Browse CSV
    $btnBrowseCsv.Add_Click({
        $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
        $openFileDialog.Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
        if ($openFileDialog.ShowDialog()) {
            $txtCsvPath = Get-WPFControl -Window $dialog -Name "TxtCsvPath"
            $txtCsvPath.Text = $openFileDialog.FileName
        }
    })

    # Browse JSON
    $btnBrowseJson.Add_Click({
        $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
        $openFileDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
        if ($openFileDialog.ShowDialog()) {
            $txtJsonPath = Get-WPFControl -Window $dialog -Name "TxtJsonPath"
            $txtJsonPath.Text = $openFileDialog.FileName
        }
    })

    # Cancel button
    $btnCancel.Add_Click({
        $dialog.DialogResult = $false
        $dialog.Close()
    })

    # Save button
    $btnSave.Add_Click({
        $name = $txtName.Text
        $type = $cmbType.SelectedItem.Tag

        $connectionInfo = @{}

        switch ($type) {
            "CSV" {
                $txtCsvPath = Get-WPFControl -Window $dialog -Name "TxtCsvPath"
                $cmbDelimiter = Get-WPFControl -Window $dialog -Name "CmbCsvDelimiter"
                $connectionInfo = @{
                    FilePath = $txtCsvPath.Text
                    Delimiter = $cmbDelimiter.SelectedItem.Tag
                }
            }
            "JSON" {
                $txtJsonPath = Get-WPFControl -Window $dialog -Name "TxtJsonPath"
                $connectionInfo = @{
                    FilePath = $txtJsonPath.Text
                }
            }
            "SQL" {
                $txtServer = Get-WPFControl -Window $dialog -Name "TxtSqlServer"
                $txtDatabase = Get-WPFControl -Window $dialog -Name "TxtSqlDatabase"
                $txtQuery = Get-WPFControl -Window $dialog -Name "TxtSqlQuery"
                $chkIntegrated = Get-WPFControl -Window $dialog -Name "ChkSqlIntegrated"
                $connectionInfo = @{
                    Server = $txtServer.Text
                    Database = $txtDatabase.Text
                    Query = $txtQuery.Text
                    IntegratedSecurity = $chkIntegrated.IsChecked
                }
            }
            "Graph" {
                $txtEndpoint = Get-WPFControl -Window $dialog -Name "TxtGraphEndpoint"
                $connectionInfo = @{
                    Endpoint = $txtEndpoint.Text
                }
            }
            "Manual" {
                $txtData = Get-WPFControl -Window $dialog -Name "TxtManualData"
                $connectionInfo = @{
                    Data = $txtData.Text
                }
            }
        }

        $dataSource = New-DataSource -Name $name -Type $type -ConnectionInfo $connectionInfo
        $dialog.Tag = $dataSource
        $dialog.DialogResult = $true
        $dialog.Close()
    })

    $result = $dialog.ShowDialog()

    if ($result) {
        return $dialog.Tag
    }
    return $null
}

#endregion Functions

#########################################################################
#
# Main Script - WPF Application
#
#########################################################################
#region Main Script

Write-Host ""
Write-Host "> Starting PowerShell Report Builder UI..." -ForegroundColor Green

try {
    # Load main window
    $mainWindowPath = Join-Path -Path $PSScriptRoot -ChildPath "XAML\MainWindow.xaml"
    $mainWindow = New-WPFWindow -XamlPath $mainWindowPath

    # Get main controls
    $treeView = Get-WPFControl -Window $mainWindow -Name "ReportTreeView"
    $statusText = Get-WPFControl -Window $mainWindow -Name "StatusText"
    $statusElements = Get-WPFControl -Window $mainWindow -Name "StatusElements"
    $txtReportTitle = Get-WPFControl -Window $mainWindow -Name "TxtReportTitle"
    $txtGeneratedCode = Get-WPFControl -Window $mainWindow -Name "TxtGeneratedCode"
    $dataSourcesList = Get-WPFControl -Window $mainWindow -Name "DataSourcesList"

    # Buttons
    $btnNew = Get-WPFControl -Window $mainWindow -Name "BtnNew"
    $btnOpen = Get-WPFControl -Window $mainWindow -Name "BtnOpen"
    $btnSave = Get-WPFControl -Window $mainWindow -Name "BtnSave"
    $btnPreview = Get-WPFControl -Window $mainWindow -Name "BtnPreview"
    $btnExportHtml = Get-WPFControl -Window $mainWindow -Name "BtnExportHtml"
    $btnAddDataSource = Get-WPFControl -Window $mainWindow -Name "BtnAddDataSource"
    $btnAddDataSourcePanel = Get-WPFControl -Window $mainWindow -Name "BtnAddDataSourcePanel"

    # Element buttons
    $btnAddTab = Get-WPFControl -Window $mainWindow -Name "BtnAddTab"
    $btnAddSection = Get-WPFControl -Window $mainWindow -Name "BtnAddSection"
    $btnAddPanel = Get-WPFControl -Window $mainWindow -Name "BtnAddPanel"
    $btnAddTable = Get-WPFControl -Window $mainWindow -Name "BtnAddTable"
    $btnAddChart = Get-WPFControl -Window $mainWindow -Name "BtnAddChart"
    $btnAddText = Get-WPFControl -Window $mainWindow -Name "BtnAddText"

    # Initialize with new report
    $Script:CurrentReport = New-Report -Title "New Report"
    Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Ready" -Report $Script:CurrentReport

    # New Report
    $btnNew.Add_Click({
        $Script:CurrentReport = New-Report -Title "New Report"
        $txtReportTitle.Text = $Script:CurrentReport.Title
        Update-ReportTreeView -TreeView $treeView -Report $Script:CurrentReport
        Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
        Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "New report created" -Report $Script:CurrentReport
        Clear-AllDataSources
    })

    # Save Report
    $btnSave.Add_Click({
        $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
        $saveFileDialog.Filter = "PSReportBuilder Files (*.psrb)|*.psrb"
        $saveFileDialog.DefaultExt = ".psrb"
        if ($saveFileDialog.ShowDialog()) {
            Save-ReportConfiguration -Report $Script:CurrentReport -Path $saveFileDialog.FileName
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Report saved: $($saveFileDialog.FileName)" -Report $Script:CurrentReport
        }
    })

    # Open Report
    $btnOpen.Add_Click({
        $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
        $openFileDialog.Filter = "PSReportBuilder Files (*.psrb)|*.psrb"
        if ($openFileDialog.ShowDialog()) {
            $Script:CurrentReport = Import-ReportConfiguration -Path $openFileDialog.FileName
            $txtReportTitle.Text = $Script:CurrentReport.Title
            Update-ReportTreeView -TreeView $treeView -Report $Script:CurrentReport
            Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Report loaded: $($openFileDialog.FileName)" -Report $Script:CurrentReport
        }
    })

    # Preview Report
    $btnPreview.Add_Click({
        try {
            $tempPath = Invoke-ReportGeneration -Report $Script:CurrentReport -ShowHTML
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Preview generated: $tempPath" -Report $Script:CurrentReport
        }
        catch {
            [System.Windows.MessageBox]::Show("Error during generation: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })

    # Export HTML
    $btnExportHtml.Add_Click({
        $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
        $saveFileDialog.Filter = "HTML Files (*.html)|*.html"
        $saveFileDialog.DefaultExt = ".html"
        if ($saveFileDialog.ShowDialog()) {
            try {
                Invoke-ReportGeneration -Report $Script:CurrentReport -OutputPath $saveFileDialog.FileName
                Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "HTML exported: $($saveFileDialog.FileName)" -Report $Script:CurrentReport
            }
            catch {
                [System.Windows.MessageBox]::Show("Error during export: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

    # Add Data Source
    $addDataSourceHandler = {
        $dataSource = Show-DataSourceDialog -Owner $mainWindow
        if ($null -ne $dataSource) {
            # Refresh data sources list
            $dataSources = Get-DataSources
            $dataSourcesList.Items.Clear()
            foreach ($ds in $dataSources) {
                $typeInfo = (Get-DataSourceTypes)[$ds.Type]
                $item = [PSCustomObject]@{
                    Name = $ds.Name
                    Icon = $typeInfo.Icon
                    Id = $ds.Id
                }
                $dataSourcesList.Items.Add($item) | Out-Null
            }
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Data source added: $($dataSource.Name)" -Report $Script:CurrentReport
        }
    }
    $btnAddDataSource.Add_Click($addDataSourceHandler)
    $btnAddDataSourcePanel.Add_Click($addDataSourceHandler)

    # Add Element functions
    function Add-ReportElement {
        param(
            [string]$Type,
            [string]$DefaultName
        )

        $element = New-ReportElement -Type $Type -Name $DefaultName

        # Get selected item in tree view
        $selectedItem = $treeView.SelectedItem

        if ($null -ne $selectedItem -and $null -ne $selectedItem.Tag) {
            $parentElement = $selectedItem.Tag

            # Check if parent can contain this element type
            if (Test-CanContainElement -Parent $parentElement -ChildType $Type) {
                $parentElement.AddChild($element)
            }
            else {
                # Add to root
                $Script:CurrentReport.AddElement($element)
            }
        }
        else {
            # Add to root
            $Script:CurrentReport.AddElement($element)
        }

        Update-ReportTreeView -TreeView $treeView -Report $Script:CurrentReport
        Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
        Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Element added: $DefaultName" -Report $Script:CurrentReport
    }

    $btnAddTab.Add_Click({ Add-ReportElement -Type "Tab" -DefaultName "New Tab" })
    $btnAddSection.Add_Click({ Add-ReportElement -Type "Section" -DefaultName "New Section" })
    $btnAddPanel.Add_Click({ Add-ReportElement -Type "Panel" -DefaultName "New Panel" })
    $btnAddTable.Add_Click({ Add-ReportElement -Type "Table" -DefaultName "New Table" })
    $btnAddChart.Add_Click({ Add-ReportElement -Type "Chart" -DefaultName "New Chart" })
    $btnAddText.Add_Click({ Add-ReportElement -Type "Text" -DefaultName "New Text" })

    # Report title change handler
    $txtReportTitle.Add_TextChanged({
        if ($null -ne $Script:CurrentReport) {
            $Script:CurrentReport.Title = $txtReportTitle.Text
            Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
        }
    })

    # Initialize code view
    Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport

    # Show main window
    Write-Host "> UI loaded successfully" -ForegroundColor Green
    Write-Host ""

    [void]$mainWindow.ShowDialog()
}
catch {
    Write-Host "> Error starting UI: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    AwaitForExit
}

Stop-PSReportBuilderTranscript
#endregion Main Script
