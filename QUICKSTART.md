# Quick Start Guide - Citrix Cloud Connector Validation

Get up and running in 5 minutes!

## Prerequisites Check (1 min)

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion
# Should be 5.0 or higher

# Check network connectivity to Citrix Cloud
Test-NetConnection -ComputerName api.citrixcloud.com -Port 443
# Should return TcpTestSucceeded: True
```

## Get Your Credentials (2 min)

1. Go to https://citrix.cloud.com
2. Navigate to **Identity and Access Management** → **API Access**
3. Create or select an API client and copy:
   - **Customer ID**
   - **API Key**
   - **API Secret**

4. Get certificate thumbprint from Cloud Connector:
   ```powershell
   Get-ChildItem -Path "Cert:\LocalMachine\My" | 
   Where-Object { $_.Subject -like "*your-connector*" } | 
   Select-Object Thumbprint, Subject, NotAfter | Format-List
   ```

## Run Validation Locally (2 min)

```powershell
# Navigate to the scripts directory
cd .\scripts

# Run the validation
.\Validate-CitrixCloudConnector.ps1 `
    -CloudConnectorHostname "cc-prod-01.example.com" `
    -CertificateThumbprint "ABC123DEF456789" `
    -CitrixCustomerId "customer-12345" `
    -CitrixApiKey "your-api-key" `
    -CitrixApiSecret "your-api-secret"

# Check the exit code
Write-Host "Exit code: $LASTEXITCODE"
```

## Expected Output

**Success:**
```
[2024-01-15 10:30:45] [Information] Starting Citrix Cloud Connector Validation
[2024-01-15 10:30:46] [Success] API token obtained successfully
[2024-01-15 10:30:47] [Success] Cloud Connector health check passed
[2024-01-15 10:30:48] [Success] Certificate thumbprint verified successfully
==========================================
Overall Status: PASSED
Health Status: OK
Certificate Thumbprint: VERIFIED
Certificate Expiration: 2025-06-15 (452 days)
==========================================

Exit code: 0
```

**Failure:**
```
[2024-01-15 10:30:45] [Information] Starting Citrix Cloud Connector Validation
[2024-01-15 10:30:46] [Error] Failed to obtain API token: ...
Exit code: 1
```

## Setup Jenkins Pipeline (Optional - 5 min)

1. **Create Jenkins credentials:**
   - Jenkins → Manage Credentials → Global Credentials
   - Add Credentials (Username/Password)
   - Username: `your-api-key`
   - Password: `your-api-secret`
   - ID: `citrix-cloud-api-credentials`

2. **Create Pipeline job:**
   - New Job → Pipeline
   - Pipeline section: Select "Pipeline script from SCM"
   - SCM: Git
   - Repository URL: `https://github.com/your-repo/citrix-connector-validation`
   - Script Path: `Jenkinsfile`

3. **Run the job:**
   - Build with Parameters
   - Enter your Cloud Connector hostname, thumbprint, and Customer ID
   - Click Build

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `No token received from Citrix Cloud API` | Verify API Key, Secret, and Customer ID are correct |
| `Cloud Connector with hostname '...' not found` | Check exact hostname in Citrix Cloud console |
| `Certificate thumbprint does not match` | Get current thumbprint from Cloud Connector and update parameter |
| `PowerShell execution policy error` | Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `API request timeout` | Check network connectivity to `api.citrixcloud.com` |

## Next Steps

- **Review full README.md** for advanced configuration options
- **Check CONFIGURATION_EXAMPLES.md** for batch validation and monitoring integration
- **Enable email notifications** in Jenkinsfile for alerts
- **Schedule daily/weekly validations** using Jenkins cron triggers

## Getting Help

1. Check the log files for detailed error messages
2. Review the Troubleshooting section in README.md
3. Verify all prerequisites are installed and configured
4. Contact your Citrix Cloud administrator for API permission issues
