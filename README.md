# Citrix Cloud Connector Validation Suite

This solution provides automated validation of Citrix Cloud Connector health, connectivity, and certificate status after system updates or maintenance.

## Components

### 1. PowerShell Script: `Validate-CitrixCloudConnector.ps1`
A comprehensive validation script that checks:
- Cloud Connector health status via Citrix Cloud API
- Certificate thumbprint verification
- Certificate expiration status (warns if within 30 days of expiration)
- Connector connectivity and readiness to serve end users

### 2. Jenkins Pipeline: `Jenkinsfile`
A production-ready Jenkins pipeline that:
- Validates input parameters
- Securely manages API credentials
- Executes the validation script
- Captures and archives logs
- Provides detailed reporting

## Prerequisites

### For PowerShell Script Execution
- Windows Server 2022 (or compatible PowerShell 5.0+ environment)
- PowerShell 5.0 or later
- Network connectivity to `api.citrixcloud.com`
- Valid Citrix Cloud service principal credentials (API Key and Secret)

### For Jenkins Execution
- Jenkins instance (2.361+)
- Jenkins agent/node labeled `windows-2022` with PowerShell support
- Jenkins Credentials Plugin to store API credentials securely
- Network connectivity from Jenkins agent to Citrix Cloud API

## Setup Instructions

### Step 1: Prepare Citrix Cloud Credentials

1. Log into Citrix Cloud: https://citrix.cloud.com
2. Navigate to **Identity and Access Management** → **API Access**
3. Create a new API client (or use existing):
   - Note the **Customer ID**
   - Note the **API Key** and **API Secret**
4. Ensure the API client has permissions in **Identity and Access Management** to read Cloud Connector information

### Step 2: Configure Jenkins Credentials

1. Go to Jenkins Dashboard → **Manage Jenkins** → **Manage Credentials**
2. Select the appropriate store (e.g., **Global** credentials)
3. Click **Add Credentials**
4. Create a **Username with password** credential:
   - **Username**: Citrix API Key
   - **Password**: Citrix API Secret
   - **ID**: `citrix-cloud-api-credentials` (or custom ID)
   - **Description**: "Citrix Cloud API Credentials"

### Step 3: Configure Jenkins Windows Agent

1. Ensure your Jenkins agent is running on Windows Server 2022
2. Label the agent with `windows-2022` (or update the `agent` section in Jenkinsfile)
3. Verify PowerShell is available: `powershell -Command "Write-Host $PSVersionTable.PSVersion"`

### Step 4: Create Jenkins Job

**Option A: Declarative Pipeline Job**
1. Create a new **Pipeline** job in Jenkins
2. Under **Pipeline** section, select **Pipeline script from SCM**
3. Select Git and provide your repository URL
4. Set **Script Path** to `Jenkinsfile`
5. Save the job

**Option B: Multibranch Pipeline**
1. Create a new **Multibranch Pipeline** job
2. Configure branch sources to point to your repository
3. Jenkins will automatically discover the Jenkinsfile

## Usage

### Running from Windows PowerShell Directly

```powershell
.\scripts\Validate-CitrixCloudConnector.ps1 `
    -CloudConnectorHostname "cc-prod-01.example.com" `
    -CertificateThumbprint "ABC123DEF456789" `
    -CitrixCustomerId "customer-12345" `
    -CitrixApiKey "your-api-key" `
    -CitrixApiSecret "your-api-secret"
```

### Running via Jenkins Pipeline

1. Open your Jenkins job
2. Click **Build with Parameters**
3. Fill in the parameters:
   - **CLOUD_CONNECTOR_HOSTNAME**: e.g., `cc-prod-01.example.com`
   - **CERTIFICATE_THUMBPRINT**: e.g., `ABC123DEF456789`
   - **CITRIX_CUSTOMER_ID**: e.g., `customer-12345`
   - **CITRIX_API_CREDENTIALS**: Select your stored credentials
4. Click **Build**
5. Monitor the console output or navigate to the build page
6. Access logs via build artifacts

### Getting Certificate Thumbprint

To find the thumbprint of the certificate installed on your Cloud Connector:

```powershell
# On the Cloud Connector server
Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object { $_.Subject -like "*CN=your-connector*" } | Select-Object Thumbprint, Subject, NotAfter
```

Or from Citrix Cloud Console:
1. Go to **My Environment** → **Cloud Connectors**
2. Select your connector
3. View certificate details in the connector properties

## Output and Logging

### Log Files
- **PowerShell Execution**: Logs saved to `CitrixConnectorValidation-[timestamp].log`
- **Jenkins Execution**: Logs archived in the `artifacts` directory of each build

### Exit Codes
- **0**: Validation successful
- **1**: Validation failed (check logs for details)

### Log Contents
- Timestamp and severity level for each operation
- API request details and responses
- Health check status
- Certificate verification results
- Certificate expiration status
- Summary of all validation checks

## Monitoring and Alerts

### Jenkins Email Notifications

Uncomment the email notification sections in the Jenkinsfile to enable alerts:

```groovy
emailext(
    subject: "Citrix Cloud Connector Validation Status",
    body: "...",
    to: "${env.NOTIFY_EMAIL}",
    attachmentsPattern: 'artifacts/**/*.log'
)
```

Set the `NOTIFY_EMAIL` environment variable in your Jenkins job configuration.

### Integration with Monitoring Systems

The script returns structured information that can be:
- Parsed by monitoring tools (Splunk, ELK, etc.)
- Integrated with incident management systems
- Used in custom alerting workflows

## Troubleshooting

### Authentication Failures
- **Error**: "No token received from Citrix Cloud API"
- **Solution**: Verify API Key and Secret are correct, check Customer ID is correct

### Cloud Connector Not Found
- **Error**: "Cloud Connector with hostname '...' not found"
- **Solution**: Verify the exact hostname matches what's registered in Citrix Cloud, check network connectivity

### Certificate Thumbprint Mismatch
- **Likely Cause**: Certificate was renewed or replaced
- **Solution**: Update the CERTIFICATE_THUMBPRINT parameter with the new thumbprint

### API Request Timeouts
- Script will retry 3 times with 5-second delays
- If still failing: Check network connectivity to `api.citrixcloud.com`, verify firewall rules

### PowerShell Execution Policy
If execution is blocked:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Security Best Practices

1. **Credential Management**:
   - Store API credentials in Jenkins Credentials Store, never in code
   - Use service principals with minimal required permissions
   - Rotate API credentials periodically

2. **Logging**:
   - Logs are automatically sanitized to remove Bearer tokens
   - Archive logs with restricted access
   - Monitor log files for unauthorized access attempts

3. **Network**:
   - Ensure Cloud Connector servers can only connect to authorized Citrix endpoints
   - Use TLS 1.2+ for all API communications (handled automatically)
   - Restrict Jenkins agent network access appropriately

4. **Audit**:
   - Enable Jenkins audit logging
   - Review CloudTrail/audit logs for API credential usage
   - Monitor for unexpected validation failures

## Advanced Configuration

### Custom Retry Logic
Modify `MaxRetries` and `RetryDelaySeconds` in the script:
```powershell
$MaxRetries = 5           # Increase retry attempts
$RetryDelaySeconds = 10   # Increase delay between retries
```

### Custom Log Path
Specify a custom log location:
```powershell
-LogPath "C:\Logs\ConnectorValidation.log"
```

### Bulk Validation
Create a wrapper script to validate multiple connectors:
```powershell
$connectors = @(
    @{ Hostname = "cc-prod-01.example.com"; Thumbprint = "ABC123..." },
    @{ Hostname = "cc-prod-02.example.com"; Thumbprint = "DEF456..." }
)

foreach ($connector in $connectors) {
    .\Validate-CitrixCloudConnector.ps1 -CloudConnectorHostname $connector.Hostname `
                                         -CertificateThumbprint $connector.Thumbprint `
                                         # ... other parameters ...
}
```

## Support and Contributions

For issues, improvements, or questions:
1. Check the logs for detailed error messages
2. Verify all prerequisites are met
3. Review the troubleshooting section above
4. Contact your Citrix Cloud administrator or support team

## License

[Specify your license here]

## References

- [Citrix Cloud API Documentation](https://developer.cloud.citrix.com)
- [Citrix Cloud Connector Administration](https://docs.citrix.com/en-us/citrix-cloud/current-release/citrix-cloud-resource-locations/citrix-cloud-connectors.html)
- [PowerShell Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/cmdlet-overview)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
