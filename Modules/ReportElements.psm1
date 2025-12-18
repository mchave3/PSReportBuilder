#########################################################################
#
# PowerShell Report Builder - Report Elements Module
# Manages PSWriteHTML report elements
#
#########################################################################

# Class representing a report element
class ReportElement {
    [string]$Id
    [string]$Type
    [string]$Name
    [hashtable]$Properties
    [System.Collections.ArrayList]$Children
    [ReportElement]$Parent

    ReportElement([string]$type, [string]$name) {
        $this.Id = [guid]::NewGuid().ToString()
        $this.Type = $type
        $this.Name = $name
        $this.Properties = @{}
        $this.Children = [System.Collections.ArrayList]::new()
        $this.Parent = $null
    }

    [void] AddChild([ReportElement]$child) {
        $child.Parent = $this
        $this.Children.Add($child) | Out-Null
    }

    [void] RemoveChild([ReportElement]$child) {
        $child.Parent = $null
        $this.Children.Remove($child)
    }

    [void] MoveUp() {
        if ($null -eq $this.Parent) { return }
        $index = $this.Parent.Children.IndexOf($this)
        if ($index -gt 0) {
            $this.Parent.Children.RemoveAt($index)
            $this.Parent.Children.Insert($index - 1, $this)
        }
    }

    [void] MoveDown() {
        if ($null -eq $this.Parent) { return }
        $index = $this.Parent.Children.IndexOf($this)
        if ($index -lt ($this.Parent.Children.Count - 1)) {
            $this.Parent.Children.RemoveAt($index)
            $this.Parent.Children.Insert($index + 1, $this)
        }
    }
}

# Available element types
$Script:ElementTypes = @{
    'Tab'       = @{ DisplayName = 'Tab'; Icon = '📑'; CanContain = @('Section', 'Panel', 'Table', 'Chart', 'Text') }
    'Section'   = @{ DisplayName = 'Section'; Icon = '📦'; CanContain = @('Panel', 'Table', 'Chart', 'Text') }
    'Panel'     = @{ DisplayName = 'Panel'; Icon = '🗂️'; CanContain = @('Table', 'Chart', 'Text') }
    'Table'     = @{ DisplayName = 'Table'; Icon = '📊'; CanContain = @() }
    'Chart'     = @{ DisplayName = 'Chart'; Icon = '📈'; CanContain = @() }
    'Text'      = @{ DisplayName = 'Text'; Icon = '📝'; CanContain = @() }
}

# Function to create a new element
function New-ReportElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Tab', 'Section', 'Panel', 'Table', 'Chart', 'Text')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Name,

        [hashtable]$Properties = @{}
    )

    $element = [ReportElement]::new($Type, $Name)

    # Default properties based on type
    switch ($Type) {
        'Tab' {
            $element.Properties = @{
                TabName = $Name
                IconSolid = ''
            }
        }
        'Section' {
            $element.Properties = @{
                HeaderText = $Name
                CanCollapse = $false
                Invisible = $false
            }
        }
        'Panel' {
            $element.Properties = @{
                BackgroundColor = ''
            }
        }
        'Table' {
            $element.Properties = @{
                DataSourceId = ''
                HideFooter = $true
                DisablePaging = $false
                DisableSearch = $false
            }
        }
        'Chart' {
            $element.Properties = @{
                Title = $Name
                ChartType = 'Bar'  # Bar, Pie, Line, Donut
                DataSourceId = ''
            }
        }
        'Text' {
            $element.Properties = @{
                Text = ''
                Color = ''
                Alignment = 'left'
                FontSize = ''
            }
        }
    }

    # Merge with provided properties
    foreach ($key in $Properties.Keys) {
        $element.Properties[$key] = $Properties[$key]
    }

    return $element
}

# Function to get element types
function Get-ReportElementTypes {
    return $Script:ElementTypes
}

# Function to validate if an element can contain another
function Test-CanContainElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ReportElement]$Parent,

        [Parameter(Mandatory)]
        [string]$ChildType
    )

    $parentTypeInfo = $Script:ElementTypes[$Parent.Type]
    return $parentTypeInfo.CanContain -contains $ChildType
}

# Function to generate PSWriteHTML code for an element
function ConvertTo-PSWriteHTMLCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ReportElement]$Element,

        [int]$IndentLevel = 0
    )

    $indent = "    " * $IndentLevel
    $code = ""

    switch ($Element.Type) {
        'Tab' {
            $params = @()
            if ($Element.Properties.TabName) { $params += "-TabName '$($Element.Properties.TabName)'" }
            if ($Element.Properties.IconSolid) { $params += "-IconSolid $($Element.Properties.IconSolid)" }

            $code = "${indent}New-HTMLTab $($params -join ' ') {`n"
            foreach ($child in $Element.Children) {
                $code += ConvertTo-PSWriteHTMLCode -Element $child -IndentLevel ($IndentLevel + 1)
            }
            $code += "${indent}}`n"
        }
        'Section' {
            $params = @()
            if ($Element.Properties.HeaderText) { $params += "-HeaderText '$($Element.Properties.HeaderText)'" }
            if ($Element.Properties.CanCollapse) { $params += "-CanCollapse" }
            if ($Element.Properties.Invisible) { $params += "-Invisible" }

            $code = "${indent}New-HTMLSection $($params -join ' ') {`n"
            foreach ($child in $Element.Children) {
                $code += ConvertTo-PSWriteHTMLCode -Element $child -IndentLevel ($IndentLevel + 1)
            }
            $code += "${indent}}`n"
        }
        'Panel' {
            $params = @()
            if ($Element.Properties.BackgroundColor) { $params += "-BackgroundColor $($Element.Properties.BackgroundColor)" }

            $code = "${indent}New-HTMLPanel $($params -join ' ') {`n"
            foreach ($child in $Element.Children) {
                $code += ConvertTo-PSWriteHTMLCode -Element $child -IndentLevel ($IndentLevel + 1)
            }
            $code += "${indent}}`n"
        }
        'Table' {
            $params = @("-DataTable `$DataSource_$($Element.Properties.DataSourceId)")
            if ($Element.Properties.HideFooter) { $params += "-HideFooter" }
            if ($Element.Properties.DisablePaging) { $params += "-DisablePaging" }
            if ($Element.Properties.DisableSearch) { $params += "-DisableSearch" }

            $code = "${indent}New-HTMLTable $($params -join ' ')`n"
        }
        'Chart' {
            $code = "${indent}New-HTMLChart -Title '$($Element.Properties.Title)' {`n"
            $code += "${indent}    # Chart configuration for $($Element.Properties.ChartType)`n"
            $code += "${indent}}`n"
        }
        'Text' {
            $params = @("-Text '$($Element.Properties.Text)'")
            if ($Element.Properties.Color) { $params += "-Color $($Element.Properties.Color)" }
            if ($Element.Properties.Alignment) { $params += "-Alignment $($Element.Properties.Alignment)" }
            if ($Element.Properties.FontSize) { $params += "-FontSize $($Element.Properties.FontSize)" }

            $code = "${indent}New-HTMLText $($params -join ' ')`n"
        }
    }

    return $code
}

# Export functions
Export-ModuleMember -Function @(
    'New-ReportElement',
    'Get-ReportElementTypes',
    'Test-CanContainElement',
    'ConvertTo-PSWriteHTMLCode'
)
