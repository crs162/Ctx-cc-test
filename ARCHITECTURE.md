# Architecture & System Design

## System Overview

The Citrix Cloud Connector Validation Suite is a distributed validation system designed to ensure Cloud Connector health and security posture after system updates, with support for both Jenkins and GitHub Actions CI/CD platforms.

```
┌─────────────────────────────────────────────────────────────┐
│                    Validation Request                        │
│  (Jenkins Job / GitHub Actions / Manual PowerShell)         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
            ┌────────────────────┐
            │   Input Parameter  │
            │   Validation       │
            └────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │ Validate-CitrixCloud       │
        │ Connector.ps1 (Main Script)│
        └─┬──────────────────────┬───┘
          │                      │
          ▼                      ▼
    ┌──────────────┐    ┌──────────────────┐
    │ Citrix Cloud │    │ Local File System │
    │ API Calls    │    │ (Logs, Artifacts) │
    └──────────────┘    └──────────────────┘
          │
          ├─► Get-CitrixApiToken()
          │
          ├─► Test-CloudConnectorHealth()
          │   ├─ Get Cloud Connector List
          │   ├─ Find Target by Hostname
          │   └─ Initiate & Check Health
          │
          └─► Get-CloudConnectorCertificate()
              ├─ Extract Certificate Data
              ├─ Verify Thumbprint
              └─ Check Expiration
```

## Component Architecture

### 1. PowerShell Validation Engine
**Location**: `scripts/Validate-CitrixCloudConnector.ps1`

**Responsibilities**:
- Authenticate to Citrix Cloud API
- Query Cloud Connector status
- Verify certificate properties
- Report validation results
- Generate structured logs

**Key Design Decisions**:
- Single script, no external dependencies (built-in cmdlets only)
- Hashtable-based return values for flexibility
- Comprehensive retry logic for transient failures
- Separate concerns via distinct functions
- Exit code 0/1 for CI/CD integration

**Dependencies**:
- PowerShell 5.0+ (built-in cmdlets)
- Network connectivity to api.citrixcloud.com:443
- Valid Citrix Cloud credentials

### 2. CI/CD Orchestration Layer

#### Jenkins Pipeline (`Jenkinsfile`)
**Platform**: Enterprise Jenkins instances, Windows Server 2022 agents

**Architecture**:
```
Pipeline Stages:
  1. Preparation
     └─ Verify environment, create directories
  2. Validate Parameters
     └─ Check all required inputs provided
  3. Retrieve Credentials
     └─ Load API credentials from Jenkins Secret Store
  4. Execute Validation
     └─ Call PowerShell script with parameters
  5. Archive Logs
     └─ Collect logs, sanitize sensitive data, archive
```

**Key Features**:
- Declarative syntax (jenkinsfile)
- Jenkins Credentials Store integration
- Automatic credential sanitization
- Build artifact archival
- Post-action notifications (email/chat)

**Security**:
- Credentials never appear in logs
- Bearer tokens redacted before archival
- Read-only API operations
- Audit trail via Jenkins logs

#### GitHub Actions Workflow (`.github/workflows/validate-connector.yml`)
**Platform**: GitHub Actions, windows-2022 runners

**Architecture**:
```
Workflow Triggers:
  - Manual dispatch (workflow_dispatch)
  - Scheduled (cron: daily at 2 AM UTC)
  - Commitments (push to main - optional)

Steps:
  1. Checkout Code
  2. Setup PowerShell Environment
  3. Prepare Directories
  4. Validate Parameters
  5. Execute Validation Script
  6. Upload Logs as Artifacts
  7. Post Validation Summary
  8. Notify Slack (optional)
```

**Key Features**:
- Multiple trigger types
- GitHub Secrets integration
- Automatic log archival
- Slack notifications
- Run summary reporting

### 3. API Communication Layer

**Citrix Cloud API Integration Pattern**:

```
Authentication:
  POST /citrixcloud/token
  ├─ Body: {client_id, client_secret}
  ├─ Header: Citrix-CustomerId
  └─ Response: {token}

Cloud Connector Operations (Bearer Token + Customer ID):
  GET /cloudconnectors
  ├─ List all Cloud Connectors
  └─ Response: {items: [{hostname, id, name, certificate, ...}]}
  
  POST /cloudconnectors/{id}/healthcheck
  ├─ Initiate health check
  └─ Response: {}
  
  GET /cloudconnectors/{id}
  ├─ Get connector details
  └─ Response: {status, lastContacted, certificate: {thumbprint, expirationDate, ...}}
```

**Retry & Error Handling**:
```
For each API call:
  ├─ Attempt 1: Immediate
  ├─ Attempt 2: Wait 5s, retry
  ├─ Attempt 3: Wait 5s, retry
  └─ Fail: Throw exception, log error
```

## Data Flow Diagram

```
┌──────────────┐
│  User Input  │ (hostname, thumbprint, credentials)
└──────┬───────┘
       │
       ▼
┌─────────────────────────────┐
│  Validate-CitrixCloud       │
│  Connector.ps1              │
│  ├─ Main()                  │
│  │  ├─ Get-CitrixApiToken  │
│  │  │  └─► Citrix Cloud API
│  │  │      /citrixcloud/token
│  │  │
│  │  ├─ Test-CloudConnector │
│  │  │  Health()            │
│  │  │  └─► Citrix Cloud API
│  │  │      /cloudconnectors
│  │  │      /healthcheck
│  │  │
│  │  └─ Get-CloudConnector  │
│  │     Certificate()        │
│  │     └─► Citrix Cloud API
│  │         /cloudconnectors/{id}
│  │
│  └─ Return Results
│     {Success, Errors, Warnings,
│      Details{Health, Certificate}}
└──────┬──────────────────────┘
       │
       ├─► Log File (local)
       │
       └─► Exit Code (0/1)
           └─► CI/CD System
               ├─ Success: Notify
               └─ Failure: Alert
```

## Validation State Machine

```
START
  │
  ├─► INPUT_VALIDATION
  │   └─ Parameters valid? → FAILED (exit 1)
  │   └─ Parameters valid? → AUTHENTICATION
  │
  ├─► AUTHENTICATION
  │   └─ Get API token? → FAILED (exit 1)
  │   └─ Get API token? ✓ → HEALTH_CHECK
  │
  ├─► HEALTH_CHECK
  │   └─ Find connector? → FAILED (exit 1)
  │   └─ Find connector? ✓ → Check status
  │   └─ Status = OK? → CERTIFICATE_VERIFY
  │   └─ Status ≠ OK? → FAILED (exit 1)
  │
  ├─► CERTIFICATE_VERIFY
  │   └─ Get certificate? → FAILED (exit 1)
  │   └─ Thumbprint match? → EXPIRATION_CHECK
  │   └─ Thumbprint ≠ match? → FAILED + WARNING
  │
  ├─► EXPIRATION_CHECK
  │   └─ Expired? → FAILED (exit 1)
  │   └─ Expired < 30 days? → SUCCESS + WARNING
  │   └─ Expired > 30 days? → SUCCESS
  │
  └─► RETURN_RESULTS
      └─ Exit 0 or 1
```

## Security Architecture

### Authentication & Authorization
- **Service Principal**: API Key + Secret pair
- **Token-based**: Citrix Cloud issues time-limited bearer token
- **Scope**: Read-only operations (no modifications)
- **Headers**: Citrix-CustomerId required on all requests

### Credential Protection
```
Jenkins:
  ├─ Credentials Store (encrypted at rest)
  ├─ withCredentials block (environment variables)
  └─ Automatic sanitization before log archival

GitHub Actions:
  ├─ GitHub Secrets (encrypted)
  ├─ GITHUB_ENV (environment isolation between steps)
  └─ No credential exposure in workflow logs
```

### Network Security
- HTTPS only (enforced in URLs)
- TLS 1.2+ (automatic via modern PowerShell)
- Certificate validation enabled (default behavior)
- Firewall rules limit to api.citrixcloud.com:443

### Audit Trail
- Timestamped logs for all operations
- Validation results stored as artifacts
- No sensitive data in logs (sanitized)
- Build/run history preserved in CI/CD

## Resilience & Reliability

### Error Recovery
```
Network Failures:
  ├─ Transient: Automatic retry (3 attempts, 5s intervals)
  ├─ Persistent: Fail with error message, exit code 1
  └─ Timeout: Fallback to next attempt

Invalid Credentials:
  ├─ API Key: Immediate failure (no retry)
  ├─ API Secret: Immediate failure (no retry)
  └─ Customer ID: Immediate failure (no retry)

Data Validation:
  ├─ Missing field: Fail with descriptive error
  ├─ Invalid format: Fail with expected vs actual
  └─ Type mismatch: Fail with conversion attempt log
```

### Monitoring & Alerting
```
Success Notification:
  ├─ Email (configured in Jenkins)
  ├─ Slack (GitHub Actions optional)
  └─ CI/CD history tracking

Failure Notification:
  ├─ Email with log attachment
  ├─ Slack with details
  ├─ Dashboard alerts
  └─ Build failure status
```

## Scaling Considerations

### Single Connector Validation
- ~5-10 seconds per connector
- ~3-4 API calls
- Suitable for: manual runs, single connector tests

### Batch Validation (Multiple Connectors)
- Use wrapper script in CONFIGURATION_EXAMPLES.md
- Sequential validation loop
- Results aggregation
- ~1-2 minutes for 10 connectors

### High-Volume Monitoring
- Scheduled daily validations via GitHub Actions
- Metrics export to CloudWatch/Prometheus
- Alert thresholds per environment
- Historical trend analysis

## Extension Points

### Custom Validations
1. Add new function in PowerShell script
2. Call from Main() function
3. Return hashtable with results
4. Update summary output

### Alternative CI/CD
1. Copy PowerShell logic to your platform
2. Manage credentials per platform's pattern
3. Adjust log/artifact handling
4. Update notification mechanisms

### Monitoring Integration
1. Parse JSON output (future enhancement)
2. Send metrics to monitoring system
3. Create dashboards and alerts
4. Integrate with incident management

## Performance Optimization

### API Caching
- Not implemented (fresh status on each run)
- Consider caching for high-frequency checks

### Parallel Validation
- Not implemented (sequential batch validation)
- Could parallelize multiple connector checks

### Token Reuse
- Single token per batch (not implemented)
- Would reduce auth calls in multi-connector runs

## Development & Testing

### Test Environments
```
Local Testing:
  ├─ Run script directly with test credentials
  ├─ Mock API endpoints for offline testing
  └─ Validate error handling

Jenkins Testing:
  ├─ Test job in non-prod environment
  ├─ Verify credential retrieval
  └─ Test log sanitization

GitHub Actions Testing:
  ├─ Workflow triggered manually
  ├─ Verify secrets injection
  └─ Validate artifact upload
```

## References

- **Citrix Cloud API**: https://developer.cloud.citrix.com
- **Cloud Connector Docs**: https://docs.citrix.com/cloud-connectors
- **Jenkins Pipelines**: https://www.jenkins.io/doc/book/pipeline/
- **GitHub Actions**: https://docs.github.com/actions
- **PowerShell**: https://docs.microsoft.com/powershell
