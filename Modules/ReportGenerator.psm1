#########################################################################
#
# PowerShell Report Builder - Report Generator Module
# Generates HTML reports with PSWriteHTML
#
#########################################################################

# Class representing a complete report
class Report {
    [string]$Id
    [string]$Title
    [string]$FilePath
    [System.Collections.ArrayList]$Elements
    [hashtable]$Settings

    Report([string]$title) {
        $this.Id = [guid]::NewGuid().ToString()
        $this.Title = $title
        $this.FilePath = ""
        $this.Elements = [System.Collections.ArrayList]::new()
        $this.Settings = @{
            Online = $true
            ShowHTML = $false
        }
    }

    [void] AddElement([object]$element) {
        $this.Elements.Add($element) | Out-Null
    }

    [void] RemoveElement([object]$element) {
        $this.Elements.Remove($element)
    }

    [void] Clear() {
        $this.Elements.Clear()
    }
}

# Current report being edited
$Script:CurrentReport = $null

# Function to create a new report
function New-Report {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$FilePath = ""
    )

    $Script:CurrentReport = [Report]::new($Title)
    $Script:CurrentReport.FilePath = $FilePath

    return $Script:CurrentReport
}

# Function to get the current report
function Get-CurrentReport {
    return $Script:CurrentReport
}

# Function to set the current report
function Set-CurrentReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Report]$Report
    )

    $Script:CurrentReport = $Report
}

# Function to generate PowerShell code for the report
function Export-ReportCode {
    [CmdletBinding()]
    param(
        [Report]$Report = $Script:CurrentReport
    )

    if ($null -eq $Report) {
        throw "Aucun rapport n'est actuellement chargé"
    }

    $code = @"
# PowerShell Report Builder - Generated Report
# Title: $($Report.Title)
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

# Import required module
Import-Module PSWriteHTML -Force

"@

    # Add data variables
    $dataSources = Get-DataSources
    foreach ($ds in $dataSources) {
        $code += "`n# Data Source: $($ds.Name)`n"
        $code += "`$DataSource_$($ds.Id) = @() # TODO: Load data from $($ds.Type)`n"
    }

    $code += @"

# Generate HTML Report
New-HTML -TitleText '$($Report.Title)' -Online:$($Report.Settings.Online) -FilePath '$($Report.FilePath)' {
"@

    # Generate code for each element
    foreach ($element in $Report.Elements) {
        $code += ConvertTo-PSWriteHTMLCode -Element $element -IndentLevel 1
    }

    $code += @"
}

"@

    if ($Report.Settings.ShowHTML) {
        $code += "# Open in browser`n"
    }

    return $code
}

# Function to generate and execute the report
function Invoke-ReportGeneration {
    [CmdletBinding()]
    param(
        [Report]$Report = $Script:CurrentReport,

        [switch]$ShowHTML,

        [string]$OutputPath
    )

    if ($null -eq $Report) {
        throw "No report is currently loaded"
    }

    # Determine output path
    $filePath = if ($OutputPath) { $OutputPath } elseif ($Report.FilePath) { $Report.FilePath } else {
        Join-Path -Path $env:TEMP -ChildPath "PSReportBuilder_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    }

    # Load data from sources
    $dataVariables = @{}
    $dataSources = Get-DataSources
    foreach ($ds in $dataSources) {
        if ($null -ne $ds.Data) {
            $dataVariables["DataSource_$($ds.Id)"] = $ds.Data
        }
    }

    # Build the scriptblock for New-HTML
    $htmlParams = @{
        TitleText = $Report.Title
        Online = $Report.Settings.Online
        FilePath = $filePath
    }

    # Generate the report with PSWriteHTML
    New-HTML @htmlParams {
        foreach ($element in $Report.Elements) {
            Invoke-ReportElement -Element $element -DataVariables $dataVariables
        }
    }

    if ($ShowHTML) {
        Start-Process $filePath
    }

    return $filePath
}

# Internal function to invoke a report element
function Invoke-ReportElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Element,

        [hashtable]$DataVariables = @{}
    )

    switch ($Element.Type) {
        'Tab' {
            $tabParams = @{}
            if ($Element.Properties.TabName) { $tabParams['TabName'] = $Element.Properties.TabName }
            if ($Element.Properties.IconSolid) { $tabParams['IconSolid'] = $Element.Properties.IconSolid }

            New-HTMLTab @tabParams {
                foreach ($child in $Element.Children) {
                    Invoke-ReportElement -Element $child -DataVariables $DataVariables
                }
            }
        }
        'Section' {
            $sectionParams = @{}
            if ($Element.Properties.HeaderText) { $sectionParams['HeaderText'] = $Element.Properties.HeaderText }
            if ($Element.Properties.CanCollapse) { $sectionParams['CanCollapse'] = $true }
            if ($Element.Properties.Invisible) { $sectionParams['Invisible'] = $true }

            New-HTMLSection @sectionParams {
                foreach ($child in $Element.Children) {
                    Invoke-ReportElement -Element $child -DataVariables $DataVariables
                }
            }
        }
        'Panel' {
            $panelParams = @{}
            if ($Element.Properties.BackgroundColor) { $panelParams['BackgroundColor'] = $Element.Properties.BackgroundColor }

            New-HTMLPanel @panelParams {
                foreach ($child in $Element.Children) {
                    Invoke-ReportElement -Element $child -DataVariables $DataVariables
                }
            }
        }
        'Table' {
            $tableParams = @{}
            if ($Element.Properties.HideFooter) { $tableParams['HideFooter'] = $true }
            if ($Element.Properties.DisablePaging) { $tableParams['DisablePaging'] = $true }
            if ($Element.Properties.DisableSearch) { $tableParams['DisableSearch'] = $true }

            $dataSourceId = $Element.Properties.DataSourceId
            $data = if ($DataVariables["DataSource_$dataSourceId"]) {
                $DataVariables["DataSource_$dataSourceId"]
            } else {
                @()
            }

            New-HTMLTable -DataTable $data @tableParams
        }
        'Chart' {
            $chartTitle = $Element.Properties.Title
            $chartType = $Element.Properties.ChartType

            $dataSourceId = $Element.Properties.DataSourceId
            $data = if ($DataVariables["DataSource_$dataSourceId"]) {
                $DataVariables["DataSource_$dataSourceId"]
            } else {
                @()
            }

            New-HTMLChart -Title $chartTitle {
                # TODO: Generate chart content based on type
                switch ($chartType) {
                    'Bar' {
                        New-ChartBar -Name 'Sample' -Value 1, 2, 3
                    }
                    'Pie' {
                        New-ChartPie -Name 'Sample' -Value 100
                    }
                    'Line' {
                        New-ChartLine -Name 'Sample' -Value 1, 2, 3
                    }
                    'Donut' {
                        New-ChartDonut -Name 'Sample' -Value 100
                    }
                }
            }
        }
        'Text' {
            $textParams = @{
                Text = $Element.Properties.Text
            }
            if ($Element.Properties.Color) { $textParams['Color'] = $Element.Properties.Color }
            if ($Element.Properties.Alignment) { $textParams['Alignment'] = $Element.Properties.Alignment }
            if ($Element.Properties.FontSize) { $textParams['FontSize'] = $Element.Properties.FontSize }

            New-HTMLText @textParams
        }
    }
}

# Function to save the report (configuration)
function Save-ReportConfiguration {
    [CmdletBinding()]
    param(
        [Report]$Report = $Script:CurrentReport,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($null -eq $Report) {
        throw "No report is currently loaded"
    }

    $config = @{
        Id = $Report.Id
        Title = $Report.Title
        FilePath = $Report.FilePath
        Settings = $Report.Settings
        Elements = @()
    }

    # Convert elements to serializable format
    foreach ($element in $Report.Elements) {
        $config.Elements += ConvertTo-SerializableElement -Element $element
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

# Function to load a report (configuration)
function Import-ReportConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Configuration file does not exist: $Path"
    }

    $config = Get-Content -Path $Path -Raw | ConvertFrom-Json

    $report = [Report]::new($config.Title)
    $report.Id = $config.Id
    $report.FilePath = $config.FilePath
    $report.Settings = @{}

    foreach ($prop in $config.Settings.PSObject.Properties) {
        $report.Settings[$prop.Name] = $prop.Value
    }

    # Rebuild elements
    foreach ($elementConfig in $config.Elements) {
        $element = ConvertFrom-SerializableElement -ElementConfig $elementConfig
        $report.Elements.Add($element) | Out-Null
    }

    $Script:CurrentReport = $report
    return $report
}

# Helper function to convert an element to serializable format
function ConvertTo-SerializableElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Element
    )

    $result = @{
        Id = $Element.Id
        Type = $Element.Type
        Name = $Element.Name
        Properties = $Element.Properties
        Children = @()
    }

    foreach ($child in $Element.Children) {
        $result.Children += ConvertTo-SerializableElement -Element $child
    }

    return $result
}

# Helper function to rebuild an element from configuration
function ConvertFrom-SerializableElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ElementConfig
    )

    $element = New-ReportElement -Type $ElementConfig.Type -Name $ElementConfig.Name
    $element.Id = $ElementConfig.Id

    foreach ($prop in $ElementConfig.Properties.PSObject.Properties) {
        $element.Properties[$prop.Name] = $prop.Value
    }

    foreach ($childConfig in $ElementConfig.Children) {
        $child = ConvertFrom-SerializableElement -ElementConfig $childConfig
        $element.AddChild($child)
    }

    return $element
}

# Export functions
Export-ModuleMember -Function @(
    'New-Report',
    'Get-CurrentReport',
    'Set-CurrentReport',
    'Export-ReportCode',
    'Invoke-ReportGeneration',
    'Save-ReportConfiguration',
    'Import-ReportConfiguration'
)
