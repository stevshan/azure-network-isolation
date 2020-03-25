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

$ResourceType = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

Write-Host "$ResourceType`:"

foreach ($NetworkRuleName in $NetworkRules.Keys) {
    Write-Host "Applying NetworkRule:$NetworkRuleName ..."

    $NetworkRule = $NetworkRules[$NetworkRuleName]
    $NetworkRuleType = $NetworkRule.type

    if ($NetworkRuleType -ieq 'AppPorts') {
        $RGName = $NetworkRule."resource-group"
        $RName = $NetworkRule."name"

        $VNet = Get-AzVirtualNetwork -ResourceGroupName $RGName -Name $RName     

        foreach ($Subnet in $VNet.Subnets) {
            $VNetRules += @($Subnet.Id)
        }
    } 
    elseif ($NetworkRuleType -ieq 'IPRanges') {
        $IPRangeRules += @($NetworkRule."ip-ranges")
    }
    else {
        Write-Host "Skipped: Not Supported NetworkRule:$NetworkRuleName ($NetworkRuleType)."
        continue
    }

    Write-Host "Completed: Applied NetworkRule:$NetworkRuleName."
    Write-Host
}

Write-Host "Applying Network Rules to $ResourceType`:$ResourceGroup\$ResourceName ..."
Update-AzKeyVaultNetworkRuleSet -VaultName $ResourceName -ResourceGroupName $ResourceGroup -IpAddressRange $IPRangeRules -VirtualNetworkResourceId $VNetRules -DefaultAction Deny -PassThru
Write-Host "Completed: Applied Network Rules to $ResourceType`:$ResourceGroup\$ResourceName ."
Write-Host