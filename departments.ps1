# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$c = $configuration | ConvertFrom-Json

$clientId = $c.clientId
$clientSecret = $c.clientSecret
$tenantId = $c.tenantId

$Script:BaseUrl = "https://api.youserve.nl"

function New-RaetSession { 
    [CmdletBinding()]
    param (
        [Alias("Param1")] 
        [parameter(Mandatory = $true)]  
        [string]      
        $ClientId,

        [Alias("Param2")] 
        [parameter(Mandatory = $true)]  
        [string]
        $ClientSecret,

        [Alias("Param3")] 
        [parameter(Mandatory = $false)]  
        [string]
        $TenantId
    )
   
    #Check if the current token is still valid
    if (Confirm-AccessTokenIsValid -eq $true) {       
        return
    }

    $url = "$Script:BaseUrl/authentication/token"
    $authorisationBody = @{
        'grant_type'    = "client_credentials"
        'client_id'     = $ClientId
        'client_secret' = $ClientSecret
    }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

        $result = Invoke-WebRequest -Uri $url -Method Post -Body $authorisationBody -ContentType 'application/x-www-form-urlencoded' -Headers @{'Cache-Control' = "no-cache" } -UseBasicParsing
        $accessToken = $result.Content | ConvertFrom-Json
        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($accessToken.expires_in)

        $Script:AuthenticationHeaders = @{
            'X-Client-Id'      = $ClientId
            'Authorization'    = "Bearer $($accessToken.access_token)"
            'X-Raet-Tenant-Id' = $TenantId
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        }
        elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
        }
        else {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
        }
        throw $errorMessage
    } 
}

function Confirm-AccessTokenIsValid {
    if ($null -ne $Script:expirationTimeAccessToken) {
        if ((Get-Date) -le $Script:expirationTimeAccessToken) {
            return $true
        }        
    }
    return $false    
}

function Invoke-RaetRestMethodList {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]
        $Url
    )
    try {
        [System.Collections.ArrayList]$ReturnValue = @()
        $counter = 0
        do {
            if ($counter -gt 0) {
                $SkipTakeUrl = $resultSubset.nextLink.Substring($resultSubset.nextLink.IndexOf("?"))
            }
            $counter++
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $accessTokenValid = Confirm-AccessTokenIsValid
            if ($accessTokenValid -ne $true) {
                New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
            }
            $result = Invoke-RestMethod -Uri $Url$SkipTakeUrl -Method GET -ContentType "application/json" -Headers $Script:AuthenticationHeaders -UseBasicParsing
            $resultSubset = $result
            $ReturnValue.AddRange($resultSubset.value)
        } until([string]::IsNullOrEmpty($resultSubset.nextLink))
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        }
        elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
        }
        else {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
        }
        throw $errorMessage
    }
    return $ReturnValue
}


Write-Information "Starting Department import"

# Query organizationunits
try {
    Write-Verbose "Querying organizationUnits"
    
    $organizationUnits = Invoke-RaetRestMethodList -Url "$Script:BaseUrl/iam/v1.0/organizationunits"

    # Filter for valid organizationunits
    $filterDateValidOrganizationUnits = Get-Date
    $organizationUnits = $organizationUnits | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidOrganizationUnits -and $_.validFrom -as [datetime] -le $filterDateValidOrganizationUnits }

    Write-Information "Successfully queried organizationunits. Result: $($organizationUnits.Count)"
}
catch {
    throw "Could not retrieve organizationunits. Error: $($_.Exception.Message)"
}

# Query persons
try {
    Write-Verbose "Querying persons"

    $persons = Invoke-RaetRestMethodList -Url "$Script:BaseUrl/iam/v1.0/persons"
    
    # Filter for valid persons
    $filterDateValidPersons = Get-Date
    $persons = $persons | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidPersons.AddDays(-90) -and $_.validFrom -as [datetime] -le $filterDateValidPersons.AddDays(90) }

    # Check if there still are duplicate persons
    $duplicatePersons = ($persons | Group-Object -Property personCode | Where-Object { $_.Count -gt 1 }).Name
    if ($duplicatePersons.Count -ge 1) {
        # Sort by validUntil and validFrom (Descending)
        $prop1 = @{Expression = { if (($_.validUntil -eq "") -or ($null -eq $_.validUntil) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validUntil -as [datetime] } }; Descending = $true }
        $prop2 = @{Expression = { if (($_.validFrom -eq "") -or ($null -eq $_.validFrom) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validFrom -as [datetime] } }; Descending = $false }

        $persons = $persons | Sort-Object -Property personCode, $prop1, $prop2 | Sort-Object -Property personCode -Unique
    }

    # Group by id
    $personsGrouped = $persons | Group-Object id -AsHashTable -AsString

    Write-Information "Successfully queried persons. Result: $($persons.Count)"
}
catch {
    throw "Could not retrieve persons. Error: $($_.Exception.Message)"
}

try {
    $organizationUnits | ForEach-Object {
        $managerId = $null
        if ($null -ne $_.manager) {
            $manager = $personsGrouped[$_.manager]
            if ($null -ne $manager.personCode) {
                $managerId = $manager.personCode
            } 
        }

        $department = [PSCustomObject]@{
            ExternalId        = $_.id
            ShortName         = $_.shortName
            DisplayName       = $_.fullName
            ManagerExternalId = $managerId
            ParentExternalId  = $_.parentOrgUnit
        }

        # Sanitize and export the json
        $department = $department | ConvertTo-Json -Depth 10
        $department = $department.Replace("._", "__")

        Write-Output $department
    }
    Write-Information "Department import completed"
}
catch {
    Write-Error "Error at line: $($_.InvocationInfo.PositionMessage)"
    throw "Error: $_"
}