[CmdletBinding()]
param (
    [Parameter(
        Mandatory = $true)]
    [ValidateNotNull()]
    [Hashtable]
    $NetworkRules,

    [Parameter(
        Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $ResourceGroup,

    [Parameter(
        Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $ResourceName,

    [Parameter(
        Mandatory = $true)]
    [Bool]
    $Shared
)