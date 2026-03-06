#Requires -Version 5.0
<#
.SYNOPSIS
    Validates the health, connectivity, and certificate status of a Citrix Cloud Connector.

.DESCRIPTION
    This script performs comprehensive validation of a Citrix Cloud Connector after an update by:
    - Authenticating to Citrix Cloud API using service principal credentials
    - Initiating a health check on the specified Cloud Connector
    - Retrieving and reviewing health metrics and status
    - Verifying the certificate thumbprint used for secure communication
    - Confirming the certificate will not expire within 30 days

.PARAMETER CloudConnectorHostname
    The hostname of the Citrix Cloud Connector to validate.

.PARAMETER CertificateThumbprint
    The thumbprint of the certificate expected to be used by the Cloud Connector.

.PARAMETER CitrixCustomerId
    The Citrix Cloud customer ID for API authentication.

.PARAMETER CitrixApiKey
    The Citrix Cloud API key for service principal authentication.

.PARAMETER CitrixApiSecret
    The Citrix Cloud API secret for service principal authentication.

.PARAMETER WarningDays
    Number of days before certificate expiration to trigger a warning (default: 30).

.EXAMPLE
    .\Validate-CitrixCloudConnector.ps1 `
        -CloudConnectorHostname "cc-prod-01.example.com" `
        -CertificateThumbprint "ABC123DEF456" `
        -CitrixCustomerId "customer-id-123" `
        -CitrixApiKey "api-key-123" `
        -CitrixApiSecret "api-secret-abc"

.NOTES
    Requires internet connectivity to Citrix Cloud API endpoints.
    Service principal credentials must have appropriate permissions in Citrix Cloud.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$CloudConnectorHostname,

    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $true)]
    [string]$CitrixCustomerId,

    [Parameter(Mandatory = $true)]
    [string]$CitrixApiKey,

    [Parameter(Mandatory = $true)]
    [string]$CitrixApiSecret,

    [Parameter(Mandatory = $false)]
    [int]$WarningDays = 30,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$PSScriptRoot\CitrixConnectorValidation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

# ========================
# Configuration
# ========================
$CitrixApiBaseUri = "https://api.cloud.com"
$CitrixAuthUri = "https://trust.citrixworkspacesapi.net"
$MaxRetries = 3
$RetryDelaySeconds = 5

# ========================
# Logging Functions
# ========================
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error", "Success")]
        [string]$Level = "Information"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "Information" { Write-Host $logMessage -ForegroundColor Gray }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
    }

    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

# ========================
# Helper Functions
# ========================
function Invoke-CitrixApiRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [string]$Method = "Get",

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $false)]
        [object]$Body
    )

    $retryCount = 0
    $success = $false
    $response = $null

    while (-not $success -and $retryCount -lt $MaxRetries) {
        try {
            $params = @{
                Uri     = $Uri
                Method  = $Method
                Headers = $Headers
            }

            if ($Body) {
                $params['Body'] = $Body | ConvertTo-Json -Depth 10
                $params['ContentType'] = "application/json"
            }

            $response = Invoke-RestMethod @params -ErrorAction Stop
            $success = $true
            Write-Log "API request successful: $Uri" "Information"

        } catch {
            $retryCount++
            $errorMessage = $_.Exception.Message

            if ($retryCount -lt $MaxRetries) {
                Write-Log "API request failed (attempt $retryCount/$MaxRetries): $errorMessage. Retrying in $RetryDelaySeconds seconds..." "Warning"
                Start-Sleep -Seconds $RetryDelaySeconds
            } else {
                Write-Log "API request failed after $MaxRetries attempts: $errorMessage" "Error"
                throw $_
            }
        }
    }

    return $response
}

function Get-CitrixApiToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $true)]
        [string]$ApiSecret,

        [Parameter(Mandatory = $true)]
        [string]$CustomerId
    )

    Write-Log "Requesting API token from Citrix Cloud..." "Information"

    $authBody = @{
        ClientId     = $ApiKey
        ClientSecret = $ApiSecret
    } | ConvertTo-Json

    $authHeaders = @{
        "Content-Type"      = "application/json"
        "Accept"            = "application/json"
        "Citrix-CustomerId" = $CustomerId
    }

    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri "$CitrixAuthUri/root/tokens/clients" `
            -Method Post `
            -Body $authBody `
            -Headers $authHeaders `
            -ErrorAction Stop

        if (-not $tokenResponse.token) {
            throw "No token received from Citrix Cloud API"
        }

        Write-Log "API token obtained successfully" "Success"
        return $tokenResponse.token

    } catch {
        Write-Log "Failed to obtain API token: $($_.Exception.Message)" "Error"
        throw $_
    }
}

function Test-CloudConnectorHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$CustomerId
    )

    Write-Log "Initiating health check for Cloud Connector: $Hostname" "Information"

    $headers = @{
        "Authorization"     = "Bearer $Token"
        "Accept"           = "application/json"
        "Citrix-CustomerId" = $CustomerId
    }

    try {
        # Get the list of Cloud Connectors
        $connectorUri = "$CitrixApiBaseUri/cloudconnectors"
        $connectors = Invoke-CitrixApiRequest -Uri $connectorUri -Headers $headers

        if (-not $connectors -or -not $connectors.items) {
            throw "No connectors found in response"
        }

        # Find the connector matching the hostname
        $targetConnector = $connectors.items | Where-Object { $_.hostname -eq $Hostname }

        if (-not $targetConnector) {
            throw "Cloud Connector with hostname '$Hostname' not found"
        }

        Write-Log "Cloud Connector found: $($targetConnector.name) (ID: $($targetConnector.id))" "Information"

        # Initiate health check
        $healthCheckUri = "$CitrixApiBaseUri/cloudconnectors/$($targetConnector.id)/healthcheck"
        $healthCheck = Invoke-CitrixApiRequest -Uri $healthCheckUri -Method Post -Headers $headers

        Write-Log "Health check initiated, checking status..." "Information"

        # Wait a moment for health check to process
        Start-Sleep -Seconds 3

        # Retrieve health check results
        $healthStatusUri = "$CitrixApiBaseUri/cloudconnectors/$($targetConnector.id)"
        $healthStatus = Invoke-CitrixApiRequest -Uri $healthStatusUri -Headers $headers

        return @{
            ConnectorId        = $targetConnector.id
            ConnectorName      = $targetConnector.name
            Hostname           = $targetConnector.hostname
            HealthCheckStatus  = $healthStatus.status
            IsHealthy          = $healthStatus.status -eq "OK"
            LastHealthCheckTime = $healthStatus.lastContacted
            Details            = $healthStatus
        }

    } catch {
        Write-Log "Failed to test Cloud Connector health: $($_.Exception.Message)" "Error"
        throw $_
    }
}

function Get-CloudConnectorCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$CustomerId,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedThumbprint
    )

    Write-Log "Retrieving certificate information for Cloud Connector: $Hostname" "Information"

    $headers = @{
        "Authorization"     = "Bearer $Token"
        "Accept"           = "application/json"
        "Citrix-CustomerId" = $CustomerId
    }

    try {
        # Get connectors to find the target
        $connectorUri = "$CitrixApiBaseUri/cloudconnectors"
        $connectors = Invoke-CitrixApiRequest -Uri $connectorUri -Headers $headers

        $targetConnector = $connectors.items | Where-Object { $_.hostname -eq $Hostname }

        if (-not $targetConnector) {
            throw "Cloud Connector not found"
        }

        # Get certificate information from the connector details
        $certInfo = $targetConnector.certificate
        
        if (-not $certInfo) {
            throw "No certificate information available from API"
        }

        # Normalize thumbprint for comparison (remove spaces, convert to uppercase)
        $apiThumbprint = $certInfo.thumbprint -replace '\s', '' | ToUpper
        $expectedThumbprint = $ExpectedThumbprint -replace '\s', '' | ToUpper
        $thumbprintMatch = $apiThumbprint -eq $expectedThumbprint

        # Parse expiration date
        $expirationDate = [DateTime]::Parse($certInfo.expirationDate)
        $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

        $result = @{
            Subject              = $certInfo.subject
            Issuer               = $certInfo.issuer
            Thumbprint           = $apiThumbprint
            ThumbprintMatches    = $thumbprintMatch
            ExpirationDate       = $expirationDate
            DaysUntilExpiration  = $daysUntilExpiration
            IsExpired            = $expirationDate -lt (Get-Date)
            ExpiresWithin30Days  = $daysUntilExpiration -le 30 -and $daysUntilExpiration -gt 0
            Raw                  = $certInfo
        }

        if ($thumbprintMatch) {
            Write-Log "Certificate thumbprint verified successfully" "Success"
        } else {
            Write-Log "Certificate thumbprint mismatch! Expected: $ExpectedThumbprint, Got: $apiThumbprint" "Warning"
        }

        if ($result.IsExpired) {
            Write-Log "Certificate has EXPIRED on $($result.ExpirationDate)" "Error"
        } elseif ($result.ExpiresWithin30Days) {
            Write-Log "Certificate expires in $($result.DaysUntilExpiration) days ($($result.ExpirationDate))" "Warning"
        } else {
            Write-Log "Certificate is valid and expires in $($result.DaysUntilExpiration) days" "Success"
        }

        return $result

    } catch {
        Write-Log "Failed to retrieve certificate information: $($_.Exception.Message)" "Error"
        throw $_
    }
}

# ========================
# Main Validation Logic
# ========================
function Main {
    Write-Log "Starting Citrix Cloud Connector Validation" "Information"
    Write-Log "Cloud Connector Hostname: $CloudConnectorHostname" "Information"
    Write-Log "Log file: $LogPath" "Information"

    $validationResults = @{
        Success = $true
        Errors = @()
        Warnings = @()
        Details = @{}
    }

    try {
        # Step 1: Authenticate to Citrix Cloud
        Write-Log "Step 1: Authenticating to Citrix Cloud..." "Information"
        $token = Get-CitrixApiToken -ApiKey $CitrixApiKey -ApiSecret $CitrixApiSecret -CustomerId $CitrixCustomerId
        $validationResults.Details.Authentication = "Success"

        # Step 2: Test Cloud Connector Health
        Write-Log "Step 2: Testing Cloud Connector health..." "Information"
        $healthResults = Test-CloudConnectorHealth -Hostname $CloudConnectorHostname -Token $token -CustomerId $CitrixCustomerId
        $validationResults.Details.HealthCheck = $healthResults

        if (-not $healthResults.IsHealthy) {
            $message = "Cloud Connector is not healthy. Status: $($healthResults.HealthCheckStatus)"
            Write-Log $message "Error"
            $validationResults.Errors += $message
            $validationResults.Success = $false
        } else {
            Write-Log "Cloud Connector health check passed" "Success"
        }

        # Step 3: Verify Certificate
        Write-Log "Step 3: Verifying certificate..." "Information"
        $certResults = Get-CloudConnectorCertificate -Hostname $CloudConnectorHostname -Token $token -CustomerId $CitrixCustomerId -ExpectedThumbprint $CertificateThumbprint
        $validationResults.Details.Certificate = $certResults

        if (-not $certResults.ThumbprintMatches) {
            $message = "Certificate thumbprint does not match. Expected: $CertificateThumbprint, Got: $($certResults.Thumbprint)"
            Write-Log $message "Error"
            $validationResults.Errors += $message
            $validationResults.Success = $false
        } else {
            Write-Log "Certificate thumbprint verified" "Success"
        }

        if ($certResults.IsExpired) {
            $message = "Certificate has expired on $($certResults.ExpirationDate)"
            Write-Log $message "Error"
            $validationResults.Errors += $message
            $validationResults.Success = $false
        } elseif ($certResults.ExpiresWithin30Days) {
            $message = "Certificate expires in $($certResults.DaysUntilExpiration) days"
            Write-Log $message "Warning"
            $validationResults.Warnings += $message
        }

        # Summary
        Write-Log "======================================" "Information"
        Write-Log "Validation Summary" "Information"
        Write-Log "======================================" "Information"
        Write-Log "Overall Status: $(if ($validationResults.Success) { 'PASSED' } else { 'FAILED' })" -Level $(if ($validationResults.Success) { 'Success' } else { 'Error' })
        Write-Log "Health Status: $($healthResults.HealthCheckStatus)" -Level $(if ($healthResults.IsHealthy) { 'Success' } else { 'Error' })
        Write-Log "Certificate Thumbprint: $(if ($certResults.ThumbprintMatches) { 'VERIFIED' } else { 'MISMATCH' })" -Level $(if ($certResults.ThumbprintMatches) { 'Success' } else { 'Error' })
        Write-Log "Certificate Expiration: $($certResults.ExpirationDate) ($($certResults.DaysUntilExpiration) days)" -Level $(if ($certResults.IsExpired) { 'Error' } elseif ($certResults.ExpiresWithin30Days) { 'Warning' } else { 'Success' })

        if ($validationResults.Errors.Count -gt 0) {
            Write-Log "Errors found: $($validationResults.Errors.Count)" "Error"
            $validationResults.Errors | ForEach-Object { Write-Log "  - $_" "Error" }
        }

        if ($validationResults.Warnings.Count -gt 0) {
            Write-Log "Warnings found: $($validationResults.Warnings.Count)" "Warning"
            $validationResults.Warnings | ForEach-Object { Write-Log "  - $_" "Warning" }
        }

        Write-Log "======================================" "Information"

        return $validationResults

    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Validation failed with exception: $errorMessage" "Error"
        $validationResults.Success = $false
        $validationResults.Errors += $errorMessage
        return $validationResults
    }
}

# Run main validation
$results = Main

# Exit with appropriate code
if ($results.Success) {
    exit 0
} else {
    exit 1
}
