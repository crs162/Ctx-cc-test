# GitHub Copilot Instructions - Citrix Cloud Connector Validation Suite

## Project Overview

This is a PowerShell-based validation suite for Citrix Cloud Connector health checks after system updates. The solution consists of:
- **PowerShell script** (`scripts/Validate-CitrixCloudConnector.ps1`): Core validation logic
- **Jenkins pipeline** (`Jenkinsfile`): Enterprise CI/CD integration for Windows Server 2022
- **GitHub Actions workflow** (`.github/workflows/validate-connector.yml`): Alternative CI/CD via GitHub
- **Documentation**: README, quick start guide, and configuration examples

## Architecture & Data Flows

### Authentication Flow
1. Script receives API Key and Secret as parameters
2. Sends POST request to `https://api.citrixcloud.com/citrixcloud/token` with Customer ID header
3. Receives Bearer token in response
4. All subsequent API calls use `Authorization: Bearer $token` header with Customer ID

### Validation Flow
1. **Health Check**: Get list of Cloud Connectors → Find by hostname → Check status property
2. **Certificate Verification**: Extract certificate object from connector details → Compare thumbprint (case-insensitive, whitespace-stripped)
3. **Expiration Check**: Parse `expirationDate` from certificate → Calculate days until expiration → Warn if ≤30 days

### Error Handling Pattern
- Retry logic: 3 attempts with 5-second delays for transient API failures
- Comprehensive logging with timestamps and severity levels
- Graceful degradation: Critical failures terminate; warnings don't block success

## Key Files & Their Responsibilities

### `scripts/Validate-CitrixCloudConnector.ps1`
**Core validation engine**
- **Parameters**: CloudConnectorHostname, CertificateThumbprint, CitrixCustomerId, CitrixApiKey, CitrixApiSecret, WarningDays (default 30)
- **Key functions**:
  - `Get-CitrixApiToken()`: Handles Citrix Cloud authentication
  - `Test-CloudConnectorHealth()`: Initiates health check and retrieves status
  - `Get-CloudConnectorCertificate()`: Verifies certificate thumbprint and expiration
  - `Invoke-CitrixApiRequest()`: Implements retry logic for API calls
- **Output**: Structured results object with Success flag, Errors, Warnings, Details
- **Exit codes**: 0 on success, 1 on failure (critical for Jenkins/GitHub Actions integration)

### `Jenkinsfile`
**Enterprise CI/CD orchestration**
- **Stages**: Preparation → Parameter Validation → Credential Retrieval → Execution → Log Archival
- **Credential handling**: Uses Jenkins Credentials Store (never inline) with `withCredentials` block
- **Agent requirement**: Label `windows-2022` required (cannot run on Linux)
- **Sensitive data**: Automatically sanitizes Bearer tokens from logs before archival
- **Post actions**: Success/failure notifications (email templates provided but commented out)

### `.github/workflows/validate-connector.yml`
**GitHub Actions alternative**
- **Trigger types**: Manual (workflow_dispatch) + scheduled (daily at 2 AM UTC)
- **Secrets required**: `CITRIX_API_KEY`, `CITRIX_API_SECRET`, `CITRIX_CUSTOMER_ID`
- **Optional secrets**: `DEFAULT_CLOUD_CONNECTOR_HOSTNAME`, `DEFAULT_CERTIFICATE_THUMBPRINT`, `SLACK_WEBHOOK_URL`
- **Environment variables passed**: Via `GITHUB_ENV` between steps to avoid exposing in logs

## Project-Specific Patterns & Conventions

### PowerShell Style
- **Logging**: All output goes through `Write-Log` function with levels: Information, Warning, Error, Success
- **Color coding**: Windows terminals use ForegroundColor for visual distinction
- **Hashtable usage**: Configuration and results passed as hashtables for flexibility
- **Error propagation**: `throw $_` for critical errors, allowing callers to handle

### API Integration
- **Base URI**: `https://api.citrixcloud.com` (hardcoded, no variables for security)
- **Authentication header**: `Citrix-CustomerId` required on ALL requests, not just auth
- **Response structure**: All responses expected as objects with properties (not arrays at root)
- **Certificate data structure**: Expected under `connector.certificate` with: `thumbprint`, `subject`, `issuer`, `expirationDate`

### Certificate Validation
- **Thumbprint comparison**: Must normalize (remove spaces, uppercase) before comparing
- **Expiration logic**: `expirationDate` is string, must parse to DateTime for calculations
- **Warning threshold**: 30 days by default, configurable via `-WarningDays` parameter

### Jenkins Specifics
- **Credential ID convention**: `citrix-cloud-api-credentials` (UsernamePassword type)
- **Windows path handling**: Use backslash `\` not forward slash `/` in paths
- **Artifact archival**: Logs archived to `artifacts/` directory for build retention
- **Email notifications**: Template provided in post block but disabled by default

## Common Development Tasks

### Adding a New Validation Check
1. Create a new function: `function Test-Something() { ... }`
2. Call from `Main()` function in sequence
3. Return hashtable with results
4. Update validation summary output to show new check
5. Example: Certificate chain validation, CRL status, TLS version support

### Enabling Email Notifications in Jenkins
1. Uncomment the `emailext()` call in post success/failure blocks
2. Set `to:` parameter with recipient email
3. Configure Jenkins Email Plugin at Manage Jenkins → Configure System
4. Define `env.NOTIFY_EMAIL` environment variable in job configuration

### Running Batch Validation
1. Use provided `CONFIGURATION_EXAMPLES.md` batch script template
2. Define array of connectors with hostname and thumbprint
3. Loop through each connector calling the main script
4. Aggregate results into summary report
5. Exit with failure code if any connector fails

### Extending for Additional Cloud Connectors
1. Cloud Connectors are identified uniquely by `hostname` property in API
2. To validate multiple: create wrapper with loop (see CONFIGURATION_EXAMPLES.md)
3. Each validation is independent; one failure doesn't block others
4. Results can be aggregated into monitoring systems via JSON output

## Critical Integration Points

### Citrix Cloud API Dependencies
- **Endpoint stability**: `api.citrixcloud.com` is the canonical endpoint (no failovers)
- **Token validity**: Tokens expire; implement refresh logic if validations exceed token TTL
- **Rate limiting**: API has rate limits; script implements backoff (5-second delays)
- **Network requirements**: TLS 1.2+, firewall must allow outbound to api.citrixcloud.com:443

### Jenkins Integration Requirements
- **Windows Agent**: Must be Windows Server 2022 (or compatible) with PowerShell 5.0+
- **Artifact archival**: Jenkins must have disk space for log archival (configure retention)
- **Credential storage**: Use Jenkins Credentials Plugin (never pass secrets via job parameters)
- **Build environment**: Ensure `WORKSPACE` variable is set (standard in declarative pipelines)

### GitHub Actions Integration Requirements
- **Runner**: Must use `windows-2022` runner (GitHub-hosted or self-hosted equivalent)
- **Secret management**: Store all credentials as GitHub Secrets
- **Artifact retention**: Configure desired retention in `upload-artifact` action (default 30 days)
- **Workflow dispatch**: Allows manual runs with input parameters via GitHub UI

## Testing & Validation Strategy

### Manual Testing
```powershell
# Test script directly with dummy credentials to verify error handling
./Validate-CitrixCloudConnector.ps1 -CloudConnectorHostname "test" -CertificateThumbprint "test" -CitrixCustomerId "test" -CitrixApiKey "invalid" -CitrixApiSecret "invalid"
# Should fail gracefully with "No token received" error
```

### Jenkins Testing
1. Create test job pointing to branch
2. Run with test credentials in non-prod environment
3. Verify logs are properly sanitized before archival
4. Test credential retrieval via `withCredentials` block

### Mock Responses
- Current implementation calls real Citrix Cloud API
- For testing, replace `Invoke-RestMethod` calls with mock responses in isolated test script

## Common Issues & Their Solutions

### "Certificate thumbprint does not match"
- **Cause**: Certificate renewed on Cloud Connector side
- **Fix**: Get new thumbprint from Cloud Connector and update parameter
- **Detection**: Script explicitly logs expected vs actual thumbprint

### API request timeouts
- **Cause**: Network connectivity issue or rate limiting
- **Fix**: Script has built-in retry logic (3 attempts); if still failing, check firewall
- **Monitor**: Check `LastContacted` time in health status for indicators

### PowerShell execution policy blocks script
- **Cause**: System execution policy too restrictive
- **Fix**: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- **Jenkins context**: Jenkins agent must have appropriate policy set

## Performance Characteristics

- **Execution time**: ~5-10 seconds under normal conditions (includes initial auth)
- **API calls**: ~3-4 REST calls (auth + connector list + health check + certificate)
- **Network**: Single TCP connection to api.citrixcloud.com
- **Memory**: <100MB PowerShell process
- **Timeout**: Script has 30-minute timeout in Jenkins (configurable)

## Security Considerations

- **Credential exposure**: Script never logs API keys or secrets (sanitizes Bearer tokens)
- **HTTPS only**: All API calls via HTTPS (enforced in URI)
- **Token scope**: Requests minimal scopes needed (read-only operations)
- **Audit trail**: All validation actions logged with timestamps for compliance
- **Sensitive output**: Certificate subject/issuer logged but not private key information

## Future Enhancement Opportunities

1. **Token refresh**: Implement OAuth token refresh for long-running batch operations
2. **JSON output**: Add `-OutputFormat Json` for monitoring system integration
3. **Webhook notifications**: Direct Slack/Teams notifications instead of via CI/CD
4. **Multi-tenant support**: Extend to validate connectors across multiple Citrix customers
5. **Certificate chain validation**: Verify intermediate/root certificate validity
6. **TLS version reporting**: Check TLS version used for secure communication
7. **Custom metrics**: Export validation results to CloudWatch/Prometheus

## References

- Citrix Cloud API docs: https://developer.cloud.citrix.com
- Cloud Connector administration: https://docs.citrix.com/cloud-connectors
- PowerShell error handling: https://docs.microsoft.com/powershell/scripting/lang-spec/chapter-14-error-handling
- Jenkins declarative pipelines: https://www.jenkins.io/doc/book/pipeline/syntax/
- GitHub Actions workflow syntax: https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions
