#########################################################################
#
# PowerShell Report Builder - Data Sources Module
# Manages different data sources (CSV, SQL, Graph, etc.)
#
#########################################################################

# Class representing a data source
class DataSource {
    [string]$Id
    [string]$Name
    [string]$Type
    [hashtable]$ConnectionInfo
    [object]$Data
    [datetime]$LastRefresh

    DataSource([string]$name, [string]$type) {
        $this.Id = [guid]::NewGuid().ToString()
        $this.Name = $name
        $this.Type = $type
        $this.ConnectionInfo = @{}
        $this.Data = $null
        $this.LastRefresh = [datetime]::MinValue
    }
}

# Available data source types
$Script:DataSourceTypes = @{
    'CSV'       = @{ DisplayName = 'CSV File'; Icon = '📄'; RequiredFields = @('FilePath') }
    'JSON'      = @{ DisplayName = 'JSON File'; Icon = '📋'; RequiredFields = @('FilePath') }
    'SQL'       = @{ DisplayName = 'SQL Server Database'; Icon = '🗃️'; RequiredFields = @('Server', 'Database', 'Query') }
    'Graph'     = @{ DisplayName = 'Microsoft Graph'; Icon = '☁️'; RequiredFields = @('Endpoint') }
    'Manual'    = @{ DisplayName = 'Manual Entry'; Icon = '✏️'; RequiredFields = @() }
}

# Data sources collection
$Script:DataSources = [System.Collections.ArrayList]::new()

# Function to create a new data source
function New-DataSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('CSV', 'JSON', 'SQL', 'Graph', 'Manual')]
        [string]$Type,

        [hashtable]$ConnectionInfo = @{}
    )

    $dataSource = [DataSource]::new($Name, $Type)
    $dataSource.ConnectionInfo = $ConnectionInfo
    $Script:DataSources.Add($dataSource) | Out-Null

    return $dataSource
}

# Function to get all data sources
function Get-DataSources {
    return $Script:DataSources
}

# Function to get a data source by ID
function Get-DataSourceById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    return $Script:DataSources | Where-Object { $_.Id -eq $Id }
}

# Function to remove a data source
function Remove-DataSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $dataSource = Get-DataSourceById -Id $Id
    if ($dataSource) {
        $Script:DataSources.Remove($dataSource)
    }
}

# Function to get data source types
function Get-DataSourceTypes {
    return $Script:DataSourceTypes
}

# Function to load data from a source
function Import-DataSourceData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DataSource]$DataSource
    )

    try {
        switch ($DataSource.Type) {
            'CSV' {
                if ([string]::IsNullOrEmpty($DataSource.ConnectionInfo.FilePath)) {
                    throw "CSV file path is not specified"
                }
                if (-not (Test-Path $DataSource.ConnectionInfo.FilePath)) {
                    throw "CSV file does not exist: $($DataSource.ConnectionInfo.FilePath)"
                }

                $delimiter = if ($DataSource.ConnectionInfo.Delimiter) { $DataSource.ConnectionInfo.Delimiter } else { ',' }
                $DataSource.Data = Import-Csv -Path $DataSource.ConnectionInfo.FilePath -Delimiter $delimiter
            }
            'JSON' {
                if ([string]::IsNullOrEmpty($DataSource.ConnectionInfo.FilePath)) {
                    throw "JSON file path is not specified"
                }
                if (-not (Test-Path $DataSource.ConnectionInfo.FilePath)) {
                    throw "JSON file does not exist: $($DataSource.ConnectionInfo.FilePath)"
                }

                $DataSource.Data = Get-Content -Path $DataSource.ConnectionInfo.FilePath -Raw | ConvertFrom-Json
            }
            'SQL' {
                # Requires SqlServer module or System.Data.SqlClient
                $connectionString = "Server=$($DataSource.ConnectionInfo.Server);Database=$($DataSource.ConnectionInfo.Database);"

                if ($DataSource.ConnectionInfo.IntegratedSecurity) {
                    $connectionString += "Integrated Security=True;"
                } else {
                    $connectionString += "User Id=$($DataSource.ConnectionInfo.Username);Password=$($DataSource.ConnectionInfo.Password);"
                }

                $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                $command = New-Object System.Data.SqlClient.SqlCommand($DataSource.ConnectionInfo.Query, $connection)
                $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
                $dataSet = New-Object System.Data.DataSet

                $connection.Open()
                $adapter.Fill($dataSet) | Out-Null
                $connection.Close()

                $DataSource.Data = $dataSet.Tables[0]
            }
            'Graph' {
                # Uses Microsoft.Graph.Authentication
                $endpoint = $DataSource.ConnectionInfo.Endpoint

                # Check if connected to Graph
                try {
                    $context = Get-MgContext
                    if ($null -eq $context) {
                        throw "Not connected to Microsoft Graph. Use Connect-MgGraph first."
                    }
                } catch {
                    throw "Not connected to Microsoft Graph. Use Connect-MgGraph first."
                }

                $DataSource.Data = Invoke-MgGraphRequest -Method GET -Uri $endpoint
            }
            'Manual' {
                # Manual data is already in Data
                if ($null -eq $DataSource.Data) {
                    $DataSource.Data = @()
                }
            }
        }

        $DataSource.LastRefresh = Get-Date
        return $true
    }
    catch {
        Write-Error "Error loading data: $_"
        return $false
    }
}

# Function to refresh all data sources
function Update-AllDataSources {
    foreach ($dataSource in $Script:DataSources) {
        Import-DataSourceData -DataSource $dataSource
    }
}

# Function to clear all data sources
function Clear-AllDataSources {
    $Script:DataSources.Clear()
}

# Export functions
Export-ModuleMember -Function @(
    'New-DataSource',
    'Get-DataSources',
    'Get-DataSourceById',
    'Remove-DataSource',
    'Get-DataSourceTypes',
    'Import-DataSourceData',
    'Update-AllDataSources',
    'Clear-AllDataSources'
)
