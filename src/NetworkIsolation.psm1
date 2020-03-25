function Set-Member {
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [String]
        $Name,

        [Parameter(Mandatory = $true)]
        $Value
    )
    
    if ($InputObject.$Name) {
        $InputObject.$Name = $Value
    }
    else {
        $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Get-MemberNames {
    param (
        [Parameter(
            ValueFromPipeline, 
            Mandatory = $true)]
        [ValidateNotNull()]
        $InputObject
    )
    
    if ($InputObject -is [Hashtable]) {
        return @($InputObject.Keys)
    }
    elseif ($InputObject -is [PSCustomObject]) {
        return $InputObject | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
    }
    else {
        throw ("Unexpected Object: " + $InputObject.GetType().FullName)
    }
}

function Get-MemberValues {
    param (
        [Parameter(
            ValueFromPipeline, 
            Mandatory = $true)]
        [ValidateNotNull()]
        $InputObject
    )

    if ($InputObject -is [Hashtable]) {
        return @($InputObject.Values)
    }
    elseif ($InputObject -is [PSCustomObject]) {
        return $InputObject | Get-Member -MemberType NoteProperty | ForEach-Object { $InputObject.($_.Name) }
    }
    else {
        throw ("Unexpected Object: " + $InputObject.GetType().FullName)
    }
}

function ConvertTo-Hashtable {
    param (
        [Parameter(
            ValueFromPipeline, 
            Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]
        $InputObject
    )
    
    $PropertyNames = $InputObject | Get-MemberNames
    $Hashtable = @{ }

    foreach ($PropertyName in $PropertyNames) {
        $Hashtable[$PropertyName] = $InputObject.$PropertyName
    }

    return $Hashtable
}

function Load-ProfileObject {
    param (
        [Parameter(
            ParameterSetName = "ProfileObject",
            Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]
        $ProfileObject,

        [Parameter(
            ParameterSetName = "ProfileObject")]
        [String]
        $WorkingDirectory = $PSScriptRoot,

        [Parameter(
            ParameterSetName = "ProfilePath",
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ProfilePath
    )

    if ($PSCmdlet.ParameterSetName -ieq 'ProfilePath') {
        $ProfilePath = [System.IO.Path]::Combine($PSScriptRoot, $ProfilePath)
        [String]$ProfilePath = Resolve-Path -Path $ProfilePath
        $WorkingDirectory = Split-Path -Path $ProfilePath -Parent
        $ProfileObject = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Json
    }

    $PropertyNames = $ProfileObject | Get-MemberNames

    if ($ProfileObject.'$ref') {
        $FinalProfilePath = [System.IO.Path]::Combine($WorkingDirectory, $ProfileObject.'$ref')
        [String]$FinalProfilePath = Resolve-Path -Path $FinalProfilePath
        $FinalProfileObject = Load-ProfileObject -ProfilePath $FinalProfilePath
    }
    else {
        $FinalProfileObject = New-Object -TypeName psobject
    }

    foreach ($PropertyName in $PropertyNames) {
        if ($PropertyName -ieq '$ref') {
            continue
        }

        $PropertyValue = $ProfileObject.$PropertyName

        if (($PropertyValue -is [Hashtable]) -or ($PropertyValue -is [PSCustomObject])) {
            $PropertyValue = Load-ProfileObject -ProfileObject $PropertyValue -WorkingDirectory $WorkingDirectory

            if ($FinalProfileObject.$PropertyName) {
                $FinalProperty = $FinalProfileObject.$PropertyName
                $SubPropertyNames = $PropertyValue | Get-MemberNames

                foreach ($SubPropertyName in $SubPropertyNames) {
                    $FinalProperty | Set-Member -Name $SubPropertyName -Value $PropertyValue.$SubPropertyName
                }

                continue
            }
        }

        $FinalProfileObject | Set-Member -Name $PropertyName -Value $PropertyValue
    }

    return $FinalProfileObject
}

function Get-NetworkIsolationProfile {
    param (
        [Parameter(
            ParameterSetName = "Profile",
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name,

        [Parameter(
            ParameterSetName = "ProfilePath",
            Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path
    )
    
    if ($PSCmdlet.ParameterSetName -eq "Profile") {
        $ProfilePath = [System.IO.Path]::Combine($PSScriptRoot, ".\Profiles\$Name.json")
    }
    elseif ($PSCmdlet.ParameterSetName -eq "ProfilePath") {
        $ProfilePath = [System.IO.Path]::Combine($PSScriptRoot, $Path)
    }
    else {
        throw ("Unknown Parameter Set Name: " + $PSCmdlet.ParameterSetName)
    }

    [String]$ProfilePath = Resolve-Path -Path $ProfilePath

    return Load-ProfileObject -ProfilePath $ProfilePath
}

function Deploy-NetworkIsolationProfile {
    [CmdletBinding(DefaultParameterSetName = "DeployProfile")]
    param (
        [Parameter(
            ParameterSetName = "DeployProfile", 
            Mandatory = $true)]
        [Parameter(
            ParameterSetName = "DeployToAzResource")]
        [String]
        $Profile,

        [Parameter(
            ParameterSetName = "DeployToAzResource",
            Mandatory = $true)]
        [String]
        $ResourceType,

        [Parameter(
            ParameterSetName = "DeployToAzResource",
            Mandatory = $true)]
        [String]
        $ResourceGroup,

        [Parameter(
            ParameterSetName = "DeployProfile")]
        [Parameter(
            ParameterSetName = "DeployToAzResource",
            Mandatory = $true)]
        [String]
        $ResourceName
    )

    $AzResources = $null
    
    if ($PSCmdlet.ParameterSetName -ieq "DeployProfile") {
        if ([String]::IsNullOrWhiteSpace($Profile)) {
            throw "-Profile must be provided."
        }

        Write-Host "Deploying Profile:$Profile ..."
    }
    elseif ($PSCmdlet.ParameterSetName -ieq "DeployToAzResource") {
        if ([String]::IsNullOrWhiteSpace($Profile)) {
            $Profile = "default"
        }

        if ([String]::IsNullOrWhiteSpace($ResourceType)) {
            throw "-ResourceType must be provided."
        }

        if ([String]::IsNullOrWhiteSpace($ResourceGroup)) {
            throw "-ResourceGroup must be provided."
        }

        if ([String]::IsNullOrWhiteSpace($ResourceName)) {
            throw "-ResourceName must be provided."
        }

        $AzResources = @(
            [PSCustomObject]@{
                type             = $ResourceType;
                "resource-group" = $ResourceGroup;
                "name"           = $ResourceName;   
            }
        )

        Write-Host "Deploying Profile:$Profile to Resource:$ResourceGroup\$ResourceName ..."
    }
    else {
        throw ("Not supported parameter set: " + $PSCmdlet.ParameterSetName)
    }

    Write-Host "Loading Profile:$Profile ..."
    $NIProfile = Get-NetworkIsolationProfile -Name $Profile
    Write-Host "Completed: Loaded Profile:$Profile."

    if (-not $AzResources) {
        if (-not $ResourceName) {
            $AzResources = @($NIProfile.resources | Get-MemberValues)
        }
        elseif ($NIProfile.resources.$ResourceName) {
            $AzResources = @($NIProfile.resources.$ResourceName)
        }
        else {
            throw "Resource with name:$ResourceName doesn't exist."
        }
    }

    $SubscriptionId = $NIProfile.'subscription'.'id'
    $SubscriptionEnv = $NIProfile.'subscription'.'environment'

    Write-Host "Connecting to Azure Subscription:$SubscriptionId of $SubscriptionEnv ..."

    Connect-AzAccount -Subscription $SubscriptionId -Environment $SubscriptionEnv -ErrorAction Stop

    Write-Host "Connected: Azure Subscription:$SubscriptionId of $SubscriptionEnv ."
    Write-Host 

    $NetworkRules = $NIProfile."network-rules" | ConvertTo-Hashtable

    foreach ($AzResource in $AzResources) {
        $AzResourceType = $AzResource.type;
        $AzResourceGroup = $AzResource."resource-group";
        $AzResourceName = $AzResource.name;
        $AzResourceShared = $false

        if ($AzResource.shared) {
            $AzResourceShared = $true
        }
        
        Write-Host "Deploying to Resource:$AzResourceGroup\$AzResourceName ..."

        . ".\Modules\ResourceTypes\$AzResourceType.ps1" `
            -NetworkRules $NetworkRules `
            -ResourceGroup $AzResourceGroup `
            -ResourceName $AzResourceName `
            -Shared $AzResourceShared

        Write-Host "Completed: Deployed to Resource:$AzResourceGroup\$AzResourceName ."
        Write-Host
    }

    Write-Host "Completed: Deployed Profile:$Profile ."
}

Export-ModuleMember -Function Get-NetworkIsolationProfile, Deploy-NetworkIsolationProfile