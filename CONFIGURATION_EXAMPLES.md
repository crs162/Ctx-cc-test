# Citrix Cloud Connector Validation - Configuration Examples

## Example 1: Single Connector Validation (PowerShell)

```powershell
# Define your parameters
$params = @{
    CloudConnectorHostname  = "cc-prod-01.example.com"
    CertificateThumbprint   = "ABC123DEF456789ABCDEF"
    CitrixCustomerId        = "customer-12345"
    CitrixApiKey            = "your-api-key-here"
    CitrixApiSecret         = "your-api-secret-here"
    WarningDays             = 30
}

# Execute the validation script
& ".\scripts\Validate-CitrixCloudConnector.ps1" @params
```

## Example 2: Batch Validation Script (PowerShell)

Create a `validate-multiple.ps1` file for validating multiple connectors:

```powershell
# Configuration for multiple Cloud Connectors
$connectors = @(
    @{
        Hostname   = "cc-prod-01.example.com"
        Thumbprint = "ABC123DEF456789ABC"
        Environment = "Production"
    },
    @{
        Hostname   = "cc-prod-02.example.com"
        Thumbprint = "DEF456789ABCDEF456"
        Environment = "Production"
    },
    @{
        Hostname   = "cc-staging-01.example.com"
        Thumbprint = "789ABCDEF456789ABC"
        Environment = "Staging"
    }
)

# API Credentials (retrieve securely from environment variables or credential store)
$apiKey = $env:CITRIX_API_KEY
$apiSecret = $env:CITRIX_API_SECRET
$customerId = $env:CITRIX_CUSTOMER_ID

# Validation parameters
$warningDays = 30
$outputDir = ".\validation-results"

# Create output directory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Tracker for results
$results = @()

# Validate each connector
foreach ($connector in $connectors) {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Validating: $($connector.Hostname) ($($connector.Environment))" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor Cyan
    
    try {
        $logPath = Join-Path $outputDir "validation-$($connector.Environment)-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        
        & ".\scripts\Validate-CitrixCloudConnector.ps1" `
            -CloudConnectorHostname $connector.Hostname `
            -CertificateThumbprint $connector.Thumbprint `
            -CitrixCustomerId $customerId `
            -CitrixApiKey $apiKey `
            -CitrixApiSecret $apiSecret `
            -WarningDays $warningDays `
            -LogPath $logPath
        
        $exitCode = $LASTEXITCODE
        
        $results += @{
            Hostname = $connector.Hostname
            Environment = $connector.Environment
            Status = if ($exitCode -eq 0) { "SUCCESS" } else { "FAILED" }
            ExitCode = $exitCode
            LogFile = $logPath
            Timestamp = Get-Date
        }
        
    } catch {
        Write-Host "Exception during validation: $($_.Exception.Message)" -ForegroundColor Red
        $results += @{
            Hostname = $connector.Hostname
            Environment = $connector.Environment
            Status = "EXCEPTION"
            ExitCode = -1
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
    }
    
    Write-Host ""
}

# Display summary
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "VALIDATION SUMMARY" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
$exceptionCount = ($results | Where-Object { $_.Status -eq "EXCEPTION" }).Count

$results | ForEach-Object {
    $statusColor = switch ($_.Status) {
        "SUCCESS" { "Green" }
        "FAILED" { "Red" }
        "EXCEPTION" { "Red" }
        default { "Gray" }
    }
    
    Write-Host "$($_.Environment.PadRight(15)) $($_.Hostname.PadRight(35)) $($_.Status)" -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "Total: $($results.Count) | Success: $successCount | Failed: $failedCount | Exceptions: $exceptionCount" -ForegroundColor Cyan
Write-Host ""
Write-Host "Logs saved to: $outputDir" -ForegroundColor Cyan

# Exit with appropriate code
if ($failedCount -gt 0 -or $exceptionCount -gt 0) {
    exit 1
} else {
    exit 0
}
```

## Example 3: Jenkins Credentials Setup (Groovy)

Add this to your Jenkins Job DSL or manage manually:

```groovy
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.util.Secret

// Create Citrix Cloud API credentials
def createCitrixCredentials(String apiKey, String apiSecret, String credentialId, String description) {
    def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()
    def domain = Domain.global()
    
    def cred = new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        credentialId,
        description,
        apiKey,
        apiSecret
    )
    
    store.addCredentials(domain, cred)
    Jenkins.instance.save()
    println("Created credential: ${credentialId}")
}

// Usage
createCitrixCredentials(
    "your-citrix-api-key",
    "your-citrix-api-secret",
    "citrix-cloud-api-credentials",
    "Citrix Cloud API Credentials for Validation"
)
```

## Example 4: Jenkins Job Configuration (XML)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<org.jenkinsci.plugins.workflow.job.WorkflowJob>
    <description>Validates Citrix Cloud Connector Health and Certificate Status</description>
    <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
        <scm class="hudson.plugins.git.GitSCM">
            <configVersion>2</configVersion>
            <userRemoteConfigs>
                <hudson.plugins.git.UserRemoteConfig>
                    <url>https://github.com/your-org/citrix-connector-validation.git</url>
                    <credentialsId>github-credentials</credentialsId>
                </hudson.plugins.git.UserRemoteConfig>
            </userRemoteConfigs>
            <branches>
                <hudson.plugins.git.BranchSpec>
                    <name>*/main</name>
                </hudson.plugins.git.BranchSpec>
            </branches>
        </scm>
        <scriptPath>Jenkinsfile</scriptPath>
    </definition>
    <properties>
        <jenkins.branch.RateLimitBranchProperty_-JobPropertyImpl>
            <durationName>hour</durationName>
            <count>10</count>
        </jenkins.branch.RateLimitBranchProperty_-JobPropertyImpl>
    </properties>
    <triggers/>
    <disabled>false</disabled>
</org.jenkinsci.plugins.workflow.job.WorkflowJob>
```

## Example 5: Environment Variables Setup

Create a `.env.example` file (do NOT commit actual secrets):

```bash
# Citrix Cloud API Configuration
CITRIX_CUSTOMER_ID=your-customer-id
CITRIX_API_KEY=your-api-key-placeholder
CITRIX_API_SECRET=your-api-secret-placeholder

# Validation Configuration
VALIDATION_WARNING_DAYS=30
VALIDATION_LOG_DIR=./logs
VALIDATION_ARTIFACT_DIR=./artifacts

# Jenkins Configuration (if using environment variables)
JENKINS_BUILD_NUMBER=${BUILD_NUMBER}
JENKINS_BUILD_URL=${BUILD_URL}
JENKINS_WORKSPACE=${WORKSPACE}

# Notification Configuration (optional)
NOTIFY_EMAIL=admin@example.com
NOTIFY_SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## Example 6: Scheduled Jenkins Job

Add this to enable periodic validation (every Tuesday at 2 AM UTC):

```groovy
triggers {
    cron('0 2 * * 2')  // Every Tuesday at 2 AM UTC
}
```

Or for daily validation of critical connectors:

```groovy
triggers {
    cron('0 1 * * *')  // Every day at 1 AM UTC (adjust timezone as needed)
}
```

## Example 7: CloudWatch/Monitoring Integration

Save metrics after validation:

```powershell
# After validation completes
$results = Invoke-Expression "& '$scriptPath' $params"

# Parse results and send to CloudWatch
$metric = @{
    Namespace = "CitrixCloudConnector"
    MetricData = @(
        @{
            MetricName = "HealthCheckStatus"
            Value = if ($results.Success) { 1 } else { 0 }
            Unit = "Count"
            Timestamp = Get-Date
        },
        @{
            MetricName = "CertificateDaysToExpiration"
            Value = $results.Details.Certificate.DaysUntilExpiration
            Unit = "Count"
            Timestamp = Get-Date
        }
    )
}

# Send to CloudWatch (requires AWS SDK)
# Write-CloudWatchMetricData @metric
```

## Example 8: Slack Notification Integration

Add to Jenkinsfile `post` block:

```groovy
post {
    success {
        script {
            def slackMessage = """
            ✅ Citrix Cloud Connector Validation Successful
            
            Connector: ${params.CLOUD_CONNECTOR_HOSTNAME}
            Customer ID: ${params.CITRIX_CUSTOMER_ID}
            Build: <${env.BUILD_URL}|#${env.BUILD_NUMBER}>
            
            All health checks, certificate verification, and connectivity tests passed.
            """
            
            // Requires Slack plugin configured
            slackSend(
                color: 'good',
                message: slackMessage,
                channel: '#infrastructure-alerts'
            )
        }
    }
    failure {
        script {
            def slackMessage = """
            ❌ Citrix Cloud Connector Validation Failed
            
            Connector: ${params.CLOUD_CONNECTOR_HOSTNAME}
            Customer ID: ${params.CITRIX_CUSTOMER_ID}
            Build: <${env.BUILD_URL}|#${env.BUILD_NUMBER}>
            
            Please review the logs for details.
            """
            
            slackSend(
                color: 'danger',
                message: slackMessage,
                channel: '#infrastructure-alerts'
            )
        }
    }
}
```

## Additional Resources

- [Citrix Cloud API Reference](https://developer.cloud.citrix.com)
- [Jenkins Credentials Plugin](https://plugins.jenkins.io/credentials/)
- [PowerShell Error Handling](https://docs.microsoft.com/en-us/powershell/scripting/lang-spec/chapter-14-error-handling)
