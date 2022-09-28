#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Core-Business-Persons
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
$excludePersonsWithoutContractsInHelloID = $c.excludePersonsWithoutContractsInHelloID

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

            $maxTries = 3
            if ($auditErrorMessage -Like "*`"errorCode`": `"Too Many Requests`"*" -and $triesCounter -lt $maxTries) {
                $triesCounter++
                $retry = $true
                $delay = 100
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

Write-Information "Starting person import. Base URL: $BaseUrl"

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

# Query employments
try {
    Write-Verbose "Querying employments"

    $employments = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/employments"

    # Filter for valid employments
    $filterDateValidEmployments = Get-Date
    $employments = $employments | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidEmployments -and $_.validFrom -as [datetime] -le $filterDateValidEmployments.AddDays(90) }

    # Check if there still are duplicate persons
    $duplicateEmployments = ($employments | Group-Object -Property id | Where-Object { $_.Count -gt 1 }).Name
    if ($duplicateEmployments.Count -ge 1) {
        # Sort by  validFrom and validUntil(Ascending)
        $prop1 = @{Expression = { if (($_.validFrom -eq "") -or ($null -eq $_.validFrom) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validFrom -as [datetime] } }; Descending = $false }
        $prop2 = @{Expression = { if (($_.validUntil -eq "") -or ($null -eq $_.validUntil) ) { (Get-Date -Year 2199 -Month 12 -Day 31) -as [datetime] } else { $_.validUntil -as [datetime] } }; Descending = $true }

        $employments = $employments | Sort-Object -Property id, $prop1, $prop2 | Sort-Object -Property id -Unique
    }

    # Group by personCode
    $employmentsGrouped = $employments | Group-Object personCode -CaseSensitive -AsHashTable -AsString

    Write-Information "Successfully queried employments. Result: $($employments.Count)"
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

    throw "Error querying employments. Error Message: $auditErrorMessage"
}

# Query companies
try {
    Write-Verbose "Querying companies"
    
    $companies = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/companies"

    # Filter for valid companies
    $filterDateValidCompanies = Get-Date
    $companies = $companies | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidCompanies -and $_.validFrom -as [datetime] -le $filterDateValidCompanies }

    # Group by ShortName
    $companiesGrouped = $companies | Group-Object shortName -AsHashTable -AsString

    Write-Information "Successfully queried companies. Result: $($companies.Count)"
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

    throw "Error querying companies. Error Message: $auditErrorMessage"
}

# Query organizationunits
try {
    Write-Verbose "Querying organizationUnits"
    
    $organizationUnits = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/organizationunits"

    # Filter for valid organizationunits
    $filterDateValidOrganizationUnits = Get-Date
    $organizationUnits = $organizationUnits | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidOrganizationUnits -and $_.validFrom -as [datetime] -le $filterDateValidOrganizationUnits }

    # Group by id
    $organizationUnitsGrouped = $organizationUnits | Group-Object id -AsHashTable -AsString

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

# Query costCenters
try {
    Write-Verbose "Querying costCenters"
    
    $costCenters = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/valueList/costCenter"

    # Filter for valid costCenters
    $filterDateValidCostCenters = Get-Date
    $costCenters = $costCenters | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidCostCenters -and $_.validFrom -as [datetime] -le $filterDateValidCostCenters }

    # Group by ShortName
    $costCentersGrouped = $costCenters | Group-Object shortName -AsHashTable -AsString

    Write-Information "Successfully queried costCenters. Result: $($costCenters.Count)"
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

    throw "Error querying costCenters. Error Message: $auditErrorMessage"
}

# Query classifications
try {
    Write-Verbose "Querying classifications"
    
    $classifications = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/valueList/classification"

    # Filter for valid classifications
    $filterDateValidClassifications = Get-Date
    $classifications = $classifications | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidClassifications -and $_.validFrom -as [datetime] -le $filterDateValidClassifications }

    # Group by ShortName
    $classificationsGrouped = $classifications | Group-Object shortName -AsHashTable -AsString

    Write-Information "Successfully queried classifications. Result: $($classifications.Count)"
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

    throw "Error querying classifications. Error Message: $auditErrorMessage"
}

# Query jobProfiles
try {
    Write-Verbose "Querying jobProfiles"
    
    $jobProfiles = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/iam/v1.0/jobProfiles"

    # Filter for valid classifications
    $filterDateValidJobProfiles = Get-Date
    $jobProfiles = $jobProfiles | Where-Object { $_.validUntil -as [datetime] -ge $filterDateValidJobProfiles -and $_.validFrom -as [datetime] -le $filterDateValidJobProfiles.AddDays(90) }

    # Group by id
    $jobProfilesGrouped = $jobProfiles | Group-Object id -AsHashTable -AsString

    Write-Information "Successfully queried jobProfiles. Result: $($jobProfiles.Count)"
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

    throw "Error querying jobProfiles. Error Message: $auditErrorMessage"
}

try {
    Write-Verbose 'Enhancing and exporting person objects to HelloID'

    # Set counter to keep track of actual exported person objects
    $exportedPersons = 0

    # Enhance the persons model
    $persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force

    $persons | ForEach-Object {
        # Set required fields for HelloID
        $_.ExternalId = $_.personCode
        $_.DisplayName = "$($_.knownAs) $($_.lastNameAtBirth) ($($_.ExternalId))" 

        # Transform emailAddresses and add to the person
        if ($null -ne $_.emailAddresses) {
            foreach ($emailAddress in $_.emailAddresses) {
                if (![string]::IsNullOrEmpty($emailAddress)) {
                    # Add a property for each type of EmailAddress
                    $_ | Add-Member -MemberType NoteProperty -Name "$($emailAddress.type)EmailAddress" -Value $emailAddress -Force
                }
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove customFieldGroup, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('emailAddresses')
        }

        # Transform phoneNumbers and add to the person
        if ($null -ne $_.phoneNumbers) {
            foreach ($phoneNumber in $_.phoneNumbers) {
                if (![string]::IsNullOrEmpty($phoneNumber)) {
                    # Add a property for each type of PhoneNumber
                    $_ | Add-Member -MemberType NoteProperty -Name "$($phoneNumber.type)PhoneNumber" -Value $phoneNumber -Force
                }
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove phoneNumbers, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('phoneNumbers')
        }

        # Transform addresses and add to the person
        if ($null -ne $_.addresses) {
            foreach ($address in $_.addresses) {
                if (![string]::IsNullOrEmpty($address)) {
                    # Add a property for each type of address
                    $_ | Add-Member -MemberType NoteProperty -Name "$($address.type)Address" -Value $address -Force
                }
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove addresses, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('addresses')
        }
        
        # Transform extensions and add to the person
        if ($null -ne $_.extensions) {
            foreach ($extension in $_.extensions) {
                # Add a property for each extension
                $_ | Add-Member -Name $extension.key -MemberType NoteProperty -Value $extension.value -Force
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove extensions, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('extensions')
        }

        # Enhance person with employment
        # Get employments for person, linking key is company personCode
        $personEmployments = $employmentsGrouped[$_.personCode]
        # Create contracts object
        $contractsList = [System.Collections.ArrayList]::new()
        if ($null -ne $personEmployments) {
            foreach ($employment in $personEmployments) {
                # Set required fields for HelloID
                $employmentExternalId = "$($employment.id)"
                $employment | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $employmentExternalId -Force

                # Enhance employment with company for for extra information, such as: fullName
                # Get company for employment, linking key is company ShortName
                if ($employment.company.count -gt 0) {
                    $company = $companiesGrouped[($employment.company)]
                    if ($null -ne $company) {
                        # In the case multiple companies are found with the same ID, we always select the first one in the array
                        $employment | Add-Member -MemberType NoteProperty -Name "company" -Value $company[0] -Force
                    }
                }

                # Enhance employment with organizationUnit for for extra information, such as: fullName
                # Get organizationUnit for employment, linking key is organizationUnit id
                if ($employment.organizationUnit.count -gt 0) {
                    $organizationUnit = $organizationUnitsGrouped[($employment.organizationUnit)]
                    if ($null -ne $organizationUnit) {
                        # In the case multiple organizationUnits are found with the same ID, we always select the first one in the array
                        $employment | Add-Member -MemberType NoteProperty -Name "organizationUnit" -Value $organizationUnit[0] -Force
                    }
                }
                
                # Enhance employment with costCenter for for extra information, such as: fullName
                # Get costCenter for employment, linking key is costCenter ShortName
                if ($employment.costCenter.count -gt 0) {
                    $costCenter = $costCentersGrouped[($employment.costCenter)]
                    if ($null -ne $costCenter) {
                        # In the case multiple costCenters are found with the same ID, we always select the first one in the array
                        $employment | Add-Member -MemberType NoteProperty -Name "costCenter" -Value $costCenter[0] -Force
                    }
                }

                # Enhance employment with jobProfile for for extra information, such as: fullName
                # Get jobProfile for employment, linking key is jobProfile id
                if ($employment.jobProfile.count -gt 0) {
                    $jobProfile = $jobProfilesGrouped["$($employment.jobProfile)"]
                    if ($null -ne $jobProfile) {
                        # In the case multiple jobProfiles are found with the same ID, we always select the first one in the array
                        $employment | Add-Member -MemberType NoteProperty -Name "jobProfile" -Value $jobProfile[0] -Force
                    }
                }

                # Enhance employment with classification for for extra information, such as: fullName
                # Get classification for employment, linking key is classification ShortName
                if ($employment.classification.count -gt 0) {
                    $classification = $classificationsGrouped[$employment.classification]
                    if ($null -ne $classification) {
                        # In the case multiple classification are found with the same ID, we always select the first one in the array
                        $employment | Add-Member -MemberType NoteProperty -Name "classification" -Value $classification[0] -Force
                    }
                }

                # Create Contract object(s) based on employments
                # Create custom employment object to include prefix of properties
                $employmentObject = [PSCustomObject]@{}
                $employment.psobject.properties | ForEach-Object {
                    $employmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                }

                [Void]$contractsList.Add($employmentObject)
            }

            # Remove unneccesary fields from object (to avoid unneccesary large objects)
            # Remove employments, since the data is transformed into a seperate object: contracts
            $_.PSObject.Properties.Remove('employments')
        }
        else {
            ### Be very careful when logging in a loop, only use this when the amount is below 100
            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
            # Write-Warning "No employments found for person: $($_.ExternalId)"
        }

        # Add Contracts to person
        if ($contractsList.Count -ge 1) {
            $_.Contracts = $contractsList
        }
        elseif ($true -eq $excludePersonsWithoutContractsInHelloID) {
            ### Be very careful when logging in a loop, only use this when the amount is below 100
            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
            # Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Person has no contract data"
            return
        }           
    
        # Sanitize and export the json
        $person = $_ | ConvertTo-Json -Depth 10
        $person = $person.Replace("._", "__")

        Write-Output $person

        # Updated counter to keep track of actual exported person objects
        $exportedPersons++
    }

    Write-Information "Succesfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Person import completed"
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

    throw "Could not enhance and export person objects to HelloID. Error Message: $auditErrorMessage"
}