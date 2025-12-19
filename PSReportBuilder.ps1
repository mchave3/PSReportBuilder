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
    Author: Mickaël CHAVE
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

# Function to expand/collapse TreeViewItem recursively
function Expand-TreeViewItem {
    param(
        [System.Windows.Controls.TreeViewItem]$Item,
        [bool]$Expand
    )

    $Item.IsExpanded = $Expand
    foreach ($child in $Item.Items) {
        if ($child -is [System.Windows.Controls.TreeViewItem]) {
            Expand-TreeViewItem -Item $child -Expand $Expand
        }
    }
}

# Function to move element up or down in report structure
function Move-ReportElement {
    param(
        [object]$Report,
        [object]$Element,
        [ValidateSet("Up", "Down")]
        [string]$Direction
    )

    # Find element in root or in parent's children
    $parent = Find-ElementParent -Report $Report -Element $Element

    if ($null -eq $parent) {
        # Element is at root level
        $list = $Report.Elements
    }
    else {
        $list = $parent.Children
    }

    $index = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i].Id -eq $Element.Id) {
            $index = $i
            break
        }
    }

    if ($index -eq -1) {
        return $false
    }

    $newIndex = if ($Direction -eq "Up") { $index - 1 } else { $index + 1 }

    if ($newIndex -lt 0 -or $newIndex -ge $list.Count) {
        return $false
    }

    # Swap elements
    $temp = $list[$index]
    $list[$index] = $list[$newIndex]
    $list[$newIndex] = $temp

    return $true
}

# Function to find parent of an element
function Find-ElementParent {
    param(
        [object]$Report,
        [object]$Element
    )

    foreach ($rootElement in $Report.Elements) {
        if ($rootElement.Id -eq $Element.Id) {
            return $null  # Element is at root
        }
        $parent = Find-ElementParentRecursive -Parent $rootElement -Element $Element
        if ($null -ne $parent) {
            return $parent
        }
    }
    return $null
}

function Find-ElementParentRecursive {
    param(
        [object]$Parent,
        [object]$Element
    )

    foreach ($child in $Parent.Children) {
        if ($child.Id -eq $Element.Id) {
            return $Parent
        }
        $found = Find-ElementParentRecursive -Parent $child -Element $Element
        if ($null -ne $found) {
            return $found
        }
    }
    return $null
}

# Function to remove element from report
function Remove-ReportElement {
    param(
        [object]$Report,
        [object]$Element
    )

    # Try to remove from root
    for ($i = 0; $i -lt $Report.Elements.Count; $i++) {
        if ($Report.Elements[$i].Id -eq $Element.Id) {
            $Report.Elements.RemoveAt($i)
            return $true
        }
    }

    # Try to remove from children recursively
    foreach ($rootElement in $Report.Elements) {
        if (Remove-ElementFromChildren -Parent $rootElement -Element $Element) {
            return $true
        }
    }
    return $false
}

function Remove-ElementFromChildren {
    param(
        [object]$Parent,
        [object]$Element
    )

    for ($i = 0; $i -lt $Parent.Children.Count; $i++) {
        if ($Parent.Children[$i].Id -eq $Element.Id) {
            $Parent.Children.RemoveAt($i)
            return $true
        }
        if (Remove-ElementFromChildren -Parent $Parent.Children[$i] -Element $Element) {
            return $true
        }
    }
    return $false
}

# Function to update properties panel
function Update-PropertiesPanel {
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [object]$Element
    )

    $Panel.Children.Clear()

    # Name property
    $nameLabel = New-Object System.Windows.Controls.Label
    $nameLabel.Content = "Name:"
    $Panel.Children.Add($nameLabel) | Out-Null

    $nameTextBox = New-Object System.Windows.Controls.TextBox
    $nameTextBox.Text = $Element.Name
    $nameTextBox.Padding = "5"
    $nameTextBox.Margin = "0,0,0,10"
    $nameTextBox.Tag = $Element
    $nameTextBox.Add_TextChanged({
        param($sender, $e)
        $sender.Tag.Name = $sender.Text
    })
    $Panel.Children.Add($nameTextBox) | Out-Null

    # Type (read-only)
    $typeLabel = New-Object System.Windows.Controls.Label
    $typeLabel.Content = "Type:"
    $Panel.Children.Add($typeLabel) | Out-Null

    $typeTextBox = New-Object System.Windows.Controls.TextBox
    $typeTextBox.Text = $Element.Type
    $typeTextBox.IsReadOnly = $true
    $typeTextBox.Padding = "5"
    $typeTextBox.Margin = "0,0,0,10"
    $typeTextBox.Background = [System.Windows.Media.Brushes]::LightGray
    $Panel.Children.Add($typeTextBox) | Out-Null

    # Add type-specific properties
    switch ($Element.Type) {
        "Table" {
            Add-TableProperties -Panel $Panel -Element $Element
        }
        "Chart" {
            Add-ChartProperties -Panel $Panel -Element $Element
        }
        "Text" {
            Add-TextProperties -Panel $Panel -Element $Element
        }
        "Section" {
            Add-SectionProperties -Panel $Panel -Element $Element
        }
    }
}

# Function to clear properties panel
function Clear-PropertiesPanel {
    param(
        [System.Windows.Controls.StackPanel]$Panel
    )

    $Panel.Children.Clear()

    $placeholder = New-Object System.Windows.Controls.TextBlock
    $placeholder.Text = "Select an element to view and edit its properties"
    $placeholder.Foreground = [System.Windows.Media.Brushes]::Gray
    $placeholder.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $Panel.Children.Add($placeholder) | Out-Null
}

# Function to add table-specific properties
function Add-TableProperties {
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [object]$Element
    )

    $dsLabel = New-Object System.Windows.Controls.Label
    $dsLabel.Content = "Data Source:"
    $Panel.Children.Add($dsLabel) | Out-Null

    $dsCombo = New-Object System.Windows.Controls.ComboBox
    $dsCombo.Padding = "5"
    $dsCombo.Margin = "0,0,0,10"

    $dataSources = Get-DataSources
    foreach ($ds in $dataSources) {
        $dsCombo.Items.Add($ds.Name) | Out-Null
    }
    if ($Element.Properties.DataSource) {
        $dsCombo.SelectedItem = $Element.Properties.DataSource
    }
    $dsCombo.Tag = $Element
    $dsCombo.Add_SelectionChanged({
        param($sender, $e)
        $sender.Tag.Properties.DataSource = $sender.SelectedItem
    })
    $Panel.Children.Add($dsCombo) | Out-Null
}

# Function to add chart-specific properties
function Add-ChartProperties {
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [object]$Element
    )

    $chartTypeLabel = New-Object System.Windows.Controls.Label
    $chartTypeLabel.Content = "Chart Type:"
    $Panel.Children.Add($chartTypeLabel) | Out-Null

    $chartTypeCombo = New-Object System.Windows.Controls.ComboBox
    $chartTypeCombo.Padding = "5"
    $chartTypeCombo.Margin = "0,0,0,10"
    @("Bar", "Line", "Pie", "Doughnut", "Area") | ForEach-Object { $chartTypeCombo.Items.Add($_) | Out-Null }
    if ($Element.Properties.ChartType) {
        $chartTypeCombo.SelectedItem = $Element.Properties.ChartType
    }
    $chartTypeCombo.Tag = $Element
    $chartTypeCombo.Add_SelectionChanged({
        param($sender, $e)
        $sender.Tag.Properties.ChartType = $sender.SelectedItem
    })
    $Panel.Children.Add($chartTypeCombo) | Out-Null
}

# Function to add text-specific properties
function Add-TextProperties {
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [object]$Element
    )

    $contentLabel = New-Object System.Windows.Controls.Label
    $contentLabel.Content = "Content:"
    $Panel.Children.Add($contentLabel) | Out-Null

    $contentTextBox = New-Object System.Windows.Controls.TextBox
    $contentTextBox.Text = $Element.Properties.Content
    $contentTextBox.AcceptsReturn = $true
    $contentTextBox.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $contentTextBox.Height = 100
    $contentTextBox.Padding = "5"
    $contentTextBox.Margin = "0,0,0,10"
    $contentTextBox.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $contentTextBox.Tag = $Element
    $contentTextBox.Add_TextChanged({
        param($sender, $e)
        $sender.Tag.Properties.Content = $sender.Text
    })
    $Panel.Children.Add($contentTextBox) | Out-Null
}

# Function to add section-specific properties
function Add-SectionProperties {
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [object]$Element
    )

    $collapsibleLabel = New-Object System.Windows.Controls.Label
    $collapsibleLabel.Content = "Collapsible:"
    $Panel.Children.Add($collapsibleLabel) | Out-Null

    $collapsibleCheck = New-Object System.Windows.Controls.CheckBox
    $collapsibleCheck.IsChecked = $Element.Properties.Collapsible
    $collapsibleCheck.Margin = "0,0,0,10"
    $collapsibleCheck.Tag = $Element
    $collapsibleCheck.Add_Checked({
        param($sender, $e)
        $sender.Tag.Properties.Collapsible = $true
    })
    $collapsibleCheck.Add_Unchecked({
        param($sender, $e)
        $sender.Tag.Properties.Collapsible = $false
    })
    $Panel.Children.Add($collapsibleCheck) | Out-Null
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

    # Structure management buttons
    $btnMoveUp = Get-WPFControl -Window $mainWindow -Name "BtnMoveUp"
    $btnMoveDown = Get-WPFControl -Window $mainWindow -Name "BtnMoveDown"
    $btnDeleteElement = Get-WPFControl -Window $mainWindow -Name "BtnDeleteElement"
    $btnExpandAll = Get-WPFControl -Window $mainWindow -Name "BtnExpandAll"
    $btnCollapseAll = Get-WPFControl -Window $mainWindow -Name "BtnCollapseAll"

    # Data source management buttons
    $btnEditDataSource = Get-WPFControl -Window $mainWindow -Name "BtnEditDataSource"
    $btnRemoveDataSource = Get-WPFControl -Window $mainWindow -Name "BtnRemoveDataSource"

    # Selected element label
    $txtSelectedElement = Get-WPFControl -Window $mainWindow -Name "TxtSelectedElement"
    $propertiesPanel = Get-WPFControl -Window $mainWindow -Name "PropertiesPanel"

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

    # TreeView selection changed - update properties panel
    $treeView.Add_SelectedItemChanged({
        $selectedItem = $treeView.SelectedItem
        if ($null -ne $selectedItem -and $null -ne $selectedItem.Tag) {
            $element = $selectedItem.Tag
            $elementTypes = Get-ReportElementTypes
            $typeInfo = $elementTypes[$element.Type]
            $icon = if ($typeInfo) { $typeInfo.Icon } else { "📄" }
            $txtSelectedElement.Text = "$icon $($element.Name) ($($element.Type))"

            # Update properties panel
            Update-PropertiesPanel -Panel $propertiesPanel -Element $element
        }
        else {
            $txtSelectedElement.Text = "No element selected"
            Clear-PropertiesPanel -Panel $propertiesPanel
        }
    })

    # Move Up button
    $btnMoveUp.Add_Click({
        $selectedItem = $treeView.SelectedItem
        if ($null -eq $selectedItem -or $null -eq $selectedItem.Tag) {
            return
        }

        $element = $selectedItem.Tag
        $moved = Move-ReportElement -Report $Script:CurrentReport -Element $element -Direction "Up"

        if ($moved) {
            Update-ReportTreeView -TreeView $treeView -Report $Script:CurrentReport
            Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Element moved up" -Report $Script:CurrentReport
        }
    })

    # Move Down button
    $btnMoveDown.Add_Click({
        $selectedItem = $treeView.SelectedItem
        if ($null -eq $selectedItem -or $null -eq $selectedItem.Tag) {
            return
        }

        $element = $selectedItem.Tag
        $moved = Move-ReportElement -Report $Script:CurrentReport -Element $element -Direction "Down"

        if ($moved) {
            Update-ReportTreeView -TreeView $treeView -Report $Script:CurrentReport
            Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Element moved down" -Report $Script:CurrentReport
        }
    })

    # Delete Element button
    $btnDeleteElement.Add_Click({
        $selectedItem = $treeView.SelectedItem
        if ($null -eq $selectedItem -or $null -eq $selectedItem.Tag) {
            return
        }

        $element = $selectedItem.Tag
        $result = [System.Windows.MessageBox]::Show(
            "Are you sure you want to delete '$($element.Name)'?",
            "Confirm Delete",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            Remove-ReportElement -Report $Script:CurrentReport -Element $element
            Update-ReportTreeView -TreeView $treeView -Report $Script:CurrentReport
            Update-GeneratedCode -CodeTextBox $txtGeneratedCode -Report $Script:CurrentReport
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Element deleted: $($element.Name)" -Report $Script:CurrentReport
            $txtSelectedElement.Text = "No element selected"
            Clear-PropertiesPanel -Panel $propertiesPanel
        }
    })

    # Expand All button
    $btnExpandAll.Add_Click({
        foreach ($item in $treeView.Items) {
            Expand-TreeViewItem -Item $item -Expand $true
        }
    })

    # Collapse All button
    $btnCollapseAll.Add_Click({
        foreach ($item in $treeView.Items) {
            Expand-TreeViewItem -Item $item -Expand $false
        }
    })

    # Edit Data Source button
    $btnEditDataSource.Add_Click({
        $selectedItem = $dataSourcesList.SelectedItem
        if ($null -eq $selectedItem) {
            [System.Windows.MessageBox]::Show("Please select a data source to edit.", "No Selection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        # TODO: Implement edit data source dialog
        [System.Windows.MessageBox]::Show("Edit data source functionality coming soon.", "Not Implemented", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Remove Data Source button
    $btnRemoveDataSource.Add_Click({
        $selectedItem = $dataSourcesList.SelectedItem
        if ($null -eq $selectedItem) {
            [System.Windows.MessageBox]::Show("Please select a data source to remove.", "No Selection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Are you sure you want to remove data source '$($selectedItem.Name)'?",
            "Confirm Remove",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            Remove-DataSource -Id $selectedItem.Id
            $dataSourcesList.Items.Remove($selectedItem)
            Update-StatusBar -StatusText $statusText -StatusElements $statusElements -Message "Data source removed: $($selectedItem.Name)" -Report $Script:CurrentReport
        }
    })

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
