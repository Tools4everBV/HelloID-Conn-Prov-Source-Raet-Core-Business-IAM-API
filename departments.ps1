$config = $configuration | ConvertFrom-Json 

$clientId = $config.connection.clientId
$clientSecret = $config.connection.clientSecret
$tenantId = $config.connection.tenantId

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

    $url = "https://api.raet.com/authentication/token"
    $authorisationBody = @{
        'grant_type'    = "client_credentials"
        'client_id'     = $ClientId
        'client_secret' = $ClientSecret
    } 
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
        $result = Invoke-WebRequest -Uri $url -Method Post -Body $authorisationBody -ContentType 'application/x-www-form-urlencoded' -Headers @{'Cache-Control' = "no-cache" } -Proxy:$Proxy -UseBasicParsing
        $accessToken = $result.Content | ConvertFrom-Json
        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($accessToken.expires_in)

        $Script:AuthenticationHeaders = @{
            'X-Client-Id'      = $ClientId;
            'Authorization'    = "Bearer $($accessToken.access_token)";
            'X-Raet-Tenant-Id' = $TenantId;
           
        }     
    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
        } else {
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

function Invoke-RaetWebRequestList {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]  
        [string]
        $Url
    )
    try {
        $accessTokenValid = Confirm-AccessTokenIsValid
        if ($accessTokenValid -ne $true) {
            New-RaetSession -ClientId $clientId -ClientSecret $clientSecret
        }

        [System.Collections.ArrayList]$ReturnValue = @()
        $counter = 0 
        do {
            if ($counter -gt 0) {
                $SkipTakeUrl = $resultSubset.nextLink.Substring($resultSubset.nextLink.IndexOf("?"))
            }    
            $counter++
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
            $result = Invoke-WebRequest -Uri $Url$SkipTakeUrl -Method GET -ContentType "application/json" -Headers $Script:AuthenticationHeaders -UseBasicParsing
            $resultSubset = (ConvertFrom-Json  $result.Content)
            $ReturnValue.AddRange($resultSubset.value)
        }until([string]::IsNullOrEmpty($resultSubset.nextLink))
    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
        } else {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'" 
        }  
        throw $errorMessage
    }
    return $ReturnValue
}

function Get-RaetOrganizationUnitsList { 
   
    $Script:BaseUrl = "https://api.raet.com/iam/v1.0"

    try {
        $organizationalUnits = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/organizationUnits"
        #$roleAssignments = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/roleAssignments"
        
        $managerActiveCompareDate = Get-Date
        #
        $persons = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/employees"
        $filterDate = (Get-Date).AddDays(-90).Date	
        $persons = $persons | Where-Object { $_.validUntil -as [datetime] -ge $filterDate }
        $persons = $persons | Where-Object { ($_.employments.dischargeDate -as [datetime] -ge $filterDate -or $_.employments.dischargeDate -eq "" -or $null -eq $_.employments.dischargeDate) } 
        $personsGrouped = $persons | Group-Object -AsHashTable -Property personcode -AsString
        $uniqueIdentities = $persons | Sort-Object personCode -Unique               

        $prop1 = @{Expression = { if (($_.validUntil -eq "") -or ($null -eq $_.validUntil) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validUntil -as [datetime] } }; Descending = $false } 
        $prop2 = @{Expression = { if (($_.validFrom -eq "") -or ($null -eq $_.validFrom) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validFrom -as [datetime] } }; Descending = $false } 
        
        $personList = [System.Collections.Generic.List[Object]]@()
        foreach ($id in  $uniqueIdentities) {
            $p = $personsGrouped[$id.personCode] | Sort-Object -Property personcode, $prop1, $prop2 | Select-Object -Last 1
            $personList.add($p)
        }
        $persons = $personList


        Write-Verbose -Verbose "Department import starting";
        $departments = @();
        foreach ($item in $organizationalUnits) {
            # $ouRoleAssignments = $roleAssignments | Select-Object * | Where-Object organizationUnit -eq $item.id
           
            $person = $persons | Select-Object * | Where-Object id -eq $item.manager
            $managerId = $null
            $ExternalIdOu = $item.id
            #$managerId = $person.personCode
            if ( $null -ne $person.personCode ) {
                $managerId = $person.personCode
            }   

            $organizationUnit = [PSCustomObject]@{
                ExternalId        = $ExternalIdOu
                ShortName         = $item.shortName
                DisplayName       = $item.fullName
                ManagerExternalId = $managerId
                ParentExternalId  = $item.parentOrgUnit
            }
            $departments += $organizationUnit;
        }
        Write-Verbose -Verbose "Department import completed";
        Write-Output $departments | ConvertTo-Json -Depth 10;
    } catch {
        throw "Could not Get-OrganizationUnitsList, message: $($_.Exception.Message)"   
    }
}

#call the Get-RaetOrganizationUnitsList function to get the data from the API
Get-RaetOrganizationUnitsList