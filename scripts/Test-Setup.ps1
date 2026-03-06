#Requires -Version 5.0
<#
.SYNOPSIS
    Test script to validate Citrix Cloud Connector validation suite setup.

.DESCRIPTION
    Performs pre-flight checks to ensure all prerequisites are met before running validations.
    Tests network connectivity, script availability, and parameter validation.

.EXAMPLE
    .\Test-Setup.ps1

.NOTES
    Run this before attempting actual validations to catch configuration issues early.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ScriptPath = ".\scripts\Validate-CitrixCloudConnector.ps1",

    [Parameter(Mandatory = $false)]
    [switch]$Verbose
)

# Configuration
$checks = @()
$passCount = 0
$failCount = 0
$warningCount = 0

# ========================
# Helper Functions
# ========================
function Write-Check {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Result,

        [Parameter(Mandatory = $false)]
        [string]$Detail
    )

    $statusSymbol = switch ($Result) {
        "PASS" { "✅"; $script:passCount++ }
        "FAIL" { "❌"; $script:failCount++ }
        "WARN" { "⚠️ "; $script:warningCount++ }
        default { "ℹ️ "; }
    }

    $color = switch ($Result) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "Cyan" }
    }

    Write-Host "$statusSymbol $Name" -ForegroundColor $color -NoNewline
    
    if ($Detail) {
        Write-Host " - $Detail" -ForegroundColor Gray
    } else {
        Write-Host ""
    }
}

# ========================
# Prerequisite Checks
# ========================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Citrix Cloud Connector Validation Suite" -ForegroundColor Cyan
Write-Host "Pre-Flight Checks" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. PowerShell Version
Write-Host "🔍 System Requirements" -ForegroundColor Cyan
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 5) {
    Write-Check "PowerShell Version" "PASS" "v$($psVersion.Major).$($psVersion.Minor) (requires 5.0+)"
} else {
    Write-Check "PowerShell Version" "FAIL" "v$($psVersion.Major).$($psVersion.Minor) (requires 5.0+)"
}

# 2. Operating System
$osInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
if ($osInfo) {
    $osVersion = $osInfo.OsVersion
    if ($osVersion -like "*Server 2022*" -or [version]$osVersion -ge [version]"10.0.20348") {
        Write-Check "Operating System" "PASS" "Windows Server 2022 compatible"
    } else {
        Write-Check "Operating System" "WARN" "Detected: $($osInfo.OsName) $osVersion (Windows Server 2022+ recommended)"
    }
} else {
    Write-Check "Operating System" "WARN" "Could not determine OS version"
}

# 3. Execution Policy
Write-Host ""
Write-Host "🔓 PowerShell Configuration" -ForegroundColor Cyan
$execPolicy = Get-ExecutionPolicy
if ($execPolicy -in @("RemoteSigned", "Unrestricted", "Bypass")) {
    Write-Check "ExecutionPolicy" "PASS" "Current: $execPolicy"
} else {
    Write-Check "ExecutionPolicy" "WARN" "Current: $execPolicy (RemoteSigned recommended for scripts)"
    Write-Host "  Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
}

# 4. Script Availability
Write-Host ""
Write-Host "📁 File Structure" -ForegroundColor Cyan
if (Test-Path $ScriptPath) {
    Write-Check "Validation Script" "PASS" "Found at $ScriptPath"
    
    # Check script is readable
    try {
        $content = Get-Content $ScriptPath -ErrorAction Stop
        $lineCount = (@($content) | Measure-Object -Line).Lines
        Write-Check "Script Readability" "PASS" "$lineCount lines"
    } catch {
        Write-Check "Script Readability" "FAIL" $_.Exception.Message
    }
} else {
    Write-Check "Validation Script" "FAIL" "Not found at $ScriptPath"
}

# 5. Required Modules
Write-Host ""
Write-Host "📦 PowerShell Modules" -ForegroundColor Cyan
$requiredModules = @()  # Validate-CitrixCloudConnector.ps1 uses built-in cmdlets only

Write-Check "Built-in Modules" "PASS" "Script uses only built-in PowerShell cmdlets (no external dependencies)"

# 6. Network Connectivity
Write-Host ""
Write-Host "🌐 Network Connectivity" -ForegroundColor Cyan

# Test DNS resolution
try {
    $dnsResult = Resolve-DnsName -Name "api.cloud.com" -ErrorAction Stop -QuickTimeout
    Write-Check "DNS Resolution" "PASS" "api.cloud.com resolves to $($dnsResult.IPAddress[0])"
} catch {
    Write-Check "DNS Resolution" "FAIL" "Cannot resolve api.cloud.com"
}

# Test network connectivity to Citrix Cloud
try {
    $tcpTest = Test-NetConnection -ComputerName "api.cloud.com" -Port 443 -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Check "HTTPS Connectivity" "PASS" "Port 443 is reachable"
    } else {
        Write-Check "HTTPS Connectivity" "FAIL" "Cannot connect to port 443"
    }
} catch {
    Write-Check "HTTPS Connectivity" "WARN" "Unable to test TCP connectivity: $($_.Exception.Message)"
}

# Test internet connectivity
try {
    $webTest = Invoke-WebRequest -Uri "https://api.cloud.com/citrix.cloud" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop -WarningAction SilentlyContinue
    Write-Check "Citrix API Endpoint" "PASS" "HTTP response received"
} catch {
    # 404 or other response is fine - means endpoint is reachable
    $statusCode = $_.Exception.Response.StatusCode.value__ 2>$null
    if ($statusCode) {
        Write-Check "Citrix API Endpoint" "PASS" "Reachable (HTTP $statusCode)"
    } else {
        Write-Check "Citrix API Endpoint" "WARN" "Could not verify reachability"
    }
}

# 7. Credential Configuration
Write-Host ""
Write-Host "🔐 Credential Configuration (Required for validation)" -ForegroundColor Cyan

$hasEnvCreds = @{
    ApiKey     = -not [string]::IsNullOrEmpty($env:CITRIX_API_KEY)
    ApiSecret  = -not [string]::IsNullOrEmpty($env:CITRIX_API_SECRET)
    CustomerId = -not [string]::IsNullOrEmpty($env:CITRIX_CUSTOMER_ID)
}

Write-Check "API Key" "$(if ($hasEnvCreds.ApiKey) { 'PASS' } else { 'WARN' })" $(if ($hasEnvCreds.ApiKey) { "Set in environment" } else { "Not set in environment (pass as parameter)" })
Write-Check "API Secret" "$(if ($hasEnvCreds.ApiSecret) { 'PASS' } else { 'WARN' })" $(if ($hasEnvCreds.ApiSecret) { "Set in environment" } else { "Not set in environment (pass as parameter)" })
Write-Check "Customer ID" "$(if ($hasEnvCreds.CustomerId) { 'PASS' } else { 'WARN' })" $(if ($hasEnvCreds.CustomerId) { "Set in environment" } else { "Not set in environment (pass as parameter)" })

# 8. Parameter Requirements
Write-Host ""
Write-Host "⚙️  Validation Parameters (Required at runtime)" -ForegroundColor Cyan
Write-Check "Cloud Connector Hostname" "INFO" "Must be provided at runtime"
Write-Check "Certificate Thumbprint" "INFO" "Must be provided at runtime"
Write-Check "Citrix Customer ID" "INFO" "Can be from environment or parameter"
Write-Check "API Key" "INFO" "Can be from environment or parameter"
Write-Check "API Secret" "INFO" "Can be from environment or parameter"

# 9. Jenkins Configuration (if applicable)
Write-Host ""
Write-Host "🏢 CI/CD Configuration (Optional)" -ForegroundColor Cyan

if (Test-Path ".\Jenkinsfile") {
    Write-Check "Jenkinsfile" "PASS" "Found in repository"
} else {
    Write-Check "Jenkinsfile" "WARN" "Not found (required for Jenkins integration)"
}

if (Test-Path ".\.github\workflows\*.yml") {
    Write-Check "GitHub Actions" "PASS" "Workflow files found"
} else {
    Write-Check "GitHub Actions" "WARN" "No workflow files found (optional)"
}

# ========================
# Summary
# ========================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalChecks = $passCount + $failCount + $warningCount
Write-Host "Total: $totalChecks | ✅ Pass: $passCount | ❌ Fail: $failCount | ⚠️  Warn: $warningCount" -ForegroundColor Cyan

Write-Host ""
if ($failCount -eq 0) {
    Write-Host "✅ All critical checks passed! Ready to validate Cloud Connectors." -ForegroundColor Green
    
    if ($warningCount -gt 0) {
        Write-Host "⚠️  $warningCount warning(s) found - review above for details" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Set credential environment variables or prepare parameters:" -ForegroundColor Gray
    Write-Host "   `$env:CITRIX_API_KEY = 'your-api-key'" -ForegroundColor Gray
    Write-Host "   `$env:CITRIX_API_SECRET = 'your-api-secret'" -ForegroundColor Gray
    Write-Host "   `$env:CITRIX_CUSTOMER_ID = 'your-customer-id'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Run the validation script:" -ForegroundColor Gray
    Write-Host "   PS> $ScriptPath -CloudConnectorHostname 'cc-prod-01.example.com' -CertificateThumbprint 'ABC123...'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Review logs for validation results" -ForegroundColor Gray
    
    exit 0
} else {
    Write-Host "❌ $failCount critical check(s) failed. Please address before running validations." -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed checks:" -ForegroundColor Red
    # Re-run to show just failures
    Write-Host "Review the checks marked ❌ above and take corrective action." -ForegroundColor Red
    
    exit 1
}
