#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Core-Business-Departments
#
# Version: 1.1.2
#####################################################
$c = $configuration | ConvertFrom-Json

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$clientId = $c.clientId
$clientSecret = $c.clientSecret
$tenantId = $c.tenantId

$Script:BaseUrl = "https://api.youserve.nl"

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

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
    $accessTokenValid = Confirm-AccessTokenIsValid
    if ($true -eq $accessTokenValid) {
        return
    }

    try {
        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

        $authorisationBody = @{
            'grant_type'    = "client_credentials"
            'client_id'     = $ClientId
            'client_secret' = $ClientSecret
        }        
        $splatAccessTokenParams = @{
            Uri             = "$($BaseUrl)/authentication/token"
            Headers         = @{'Cache-Control' = "no-cache" }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorisationBody
            UseBasicParsing = $true
        }

        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams
        if ($null -eq $result.access_token) {
            throw $result
        }

        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)

        $Script:AuthenticationHeaders = @{
            'X-Client-Id'      = $ClientId
            'Authorization'    = "Bearer $($result.access_token)"
            'X-Raet-Tenant-Id' = $TenantId
        }

        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"
    }
    catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObject = Resolve-HTTPError -Error $ex
    
            $verboseErrorMessage = $errorObject.ErrorMessage
    
            $auditErrorMessage = $errorObject.ErrorMessage
        }
    
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

        throw "Error creating Access Token at uri ''$($splatAccessTokenParams.Uri)'. Please check credentials. Error Message: $auditErrorMessage"
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
    
    # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

    [System.Collections.ArrayList]$ReturnValue = @()
    $counter = 0
    $triesCounter = 0
    do {
        try {
            $accessTokenValid = Confirm-AccessTokenIsValid
            if ($true -ne $accessTokenValid) {
                New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
            }

            $retry = $false

            if ($counter -gt 0 -and $null -ne $result.nextLink) {
                $SkipTakeUrl = $result.nextLink.Substring($result.nextLink.IndexOf("?"))
            }

            $counter++

            $splatGetDataParams = @{
                Uri             = "$Url$SkipTakeUrl"
                Headers         = $Script:AuthenticationHeaders
                Method          = 'GET'
                ContentType     = "application/json"
                UseBasicParsing = $true
            }
    
            Write-Verbose "Querying data from '$($splatGetDataParams.Uri)'"

            $result = Invoke-RestMethod @splatGetDataParams
            $ReturnValue.AddRange($result.value)

            # Wait for 0,6 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
            Start-Sleep -Milliseconds 600
        }
        catch {
            $ex = $PSItem
           
            if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObject = Resolve-HTTPError -Error $ex
        
                $verboseErrorMessage = $errorObject.ErrorMessage
        
                $auditErrorMessage = $errorObject.ErrorMessage
            }
        
            # If error message empty, fall back on $ex.Exception.Message
            if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
                $verboseErrorMessage = $ex.Exception.Message
            }
            if ([String]::IsNullOrEmpty($auditErrorMessage)) {
                $auditErrorMessage = $ex.Exception.Message
            }
    
            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

            $maxTries = 10
            if ( ($auditErrorMessage -Like "*Too Many Requests*" -or $auditErrorMessage -Like "*Connection timed out*") -and $triesCounter -lt $maxTries ) {
                $triesCounter++
                $retry = $true
                $delay = 600 # Wait for 0,6 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
                Write-Warning "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $auditErrorMessage. Trying again in '$delay' milliseconds for a maximum of '$maxTries' tries."
                Start-Sleep -Milliseconds $delay
            }
            else {
                $retry = $false
                throw "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $auditErrorMessage"
            }
        }
    }while (-NOT[string]::IsNullOrEmpty($result.nextLink) -or $retry -eq $true)

    Write-Verbose "Successfully queried data from '$($Url)'. Result count: $($ReturnValue.Count)"

    return $ReturnValue
}
#endregion functions

Write-Information "Starting Department import. Base URL: $BaseUrl"

# Query organizationunits
try {
    Write-Verbose "Querying organizationUnits"
    
    $organizationUnits = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/organizationunits"

    # Filter for valid organizationunits
    $filterDateValidOrganizationUnits = Get-Date
    $organizationUnits = $organizationUnits | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidOrganizationUnits -and $_.validFrom -as [datetime] -le $filterDateValidOrganizationUnits }

    Write-Information "Successfully queried organizationunits. Result: $($organizationUnits.Count)"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Error querying organizationunits. Error Message: $auditErrorMessage"
}

# Query persons
try {
    Write-Verbose "Querying persons"

    $persons = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/employees"
    
    # Filter for valid persons
    $filterDateValidPersons = Get-Date
    $persons = $persons | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidPersons.AddDays(-90) -and $_.validFrom -as [datetime] -le $filterDateValidPersons.AddDays(90) }

    # Check if there still are duplicate persons
    $duplicatePersons = ($persons | Group-Object -Property personCode -CaseSensitive | Where-Object { $_.Count -gt 1 }).Name
    if ($duplicatePersons.Count -ge 1) {
        # Sort by validUntil and validFrom (Descending)
        $prop1 = @{Expression = { if (($_.validUntil -eq "") -or ($null -eq $_.validUntil) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validUntil -as [datetime] } }; Descending = $true }
        $prop2 = @{Expression = { if (($_.validFrom -eq "") -or ($null -eq $_.validFrom) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validFrom -as [datetime] } }; Descending = $false }

        $persons = $persons | Sort-Object -Property personCode, $prop1, $prop2 -CaseSensitive | Sort-Object -Property personCode -CaseSensitive -Unique
    }

    # Make sure persons are unique
    $persons = $persons | Sort-Object id -Unique

    # Group by id
    $personsGrouped = $persons | Group-Object id -AsHashTable -AsString

    Write-Information "Successfully queried persons. Result: $($persons.Count)"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Error querying persons. Error Message: $auditErrorMessage"
}

try {
    Write-Verbose 'Enhancing and exporting department objects to HelloID'

    # Set counter to keep track of actual exported person objects
    $exportedDepartments = 0

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

        # Updated counter to keep track of actual exported department objects
        $exportedDepartments++
    }

    Write-Information "Succesfully enhanced and exported department objects to HelloID. Result count: $($exportedDepartments)"
    Write-Information "Department import completed"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Could not enhance and export department objects to HelloID. Error Message: $auditErrorMessage"
}
