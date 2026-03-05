pipeline {
    agent {
        label 'windows-2022'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    parameters {
        string(
            name: 'CLOUD_CONNECTOR_HOSTNAME',
            defaultValue: '',
            description: 'The hostname of the Citrix Cloud Connector to validate',
            trim: true
        )
        string(
            name: 'CERTIFICATE_THUMBPRINT',
            defaultValue: '',
            description: 'The thumbprint of the certificate expected to be used by the Cloud Connector',
            trim: true
        )
        string(
            name: 'CITRIX_CUSTOMER_ID',
            defaultValue: '',
            description: 'The Citrix Cloud customer ID for API authentication',
            trim: true
        )
        credentials(
            name: 'CITRIX_API_CREDENTIALS',
            description: 'Citrix Cloud API credentials (username: API Key, password: API Secret)',
            credentialType: 'com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl',
            required: true
        )
    }

    environment {
        SCRIPT_PATH = "${WORKSPACE}\\scripts\\Validate-CitrixCloudConnector.ps1"
        ARTIFACT_DIR = "${WORKSPACE}\\artifacts"
        LOG_DIR = "${WORKSPACE}\\logs"
    }

    stages {
        stage('Preparation') {
            steps {
                script {
                    echo "=========================================="
                    echo "Citrix Cloud Connector Validation Pipeline"
                    echo "=========================================="
                    echo "Cloud Connector: ${params.CLOUD_CONNECTOR_HOSTNAME}"
                    echo "Certificate Thumbprint: ${params.CERTIFICATE_THUMBPRINT}"
                    echo "Customer ID: ${params.CITRIX_CUSTOMER_ID}"
                    echo "Build Number: ${env.BUILD_NUMBER}"
                    echo "Build URL: ${env.BUILD_URL}"
                    
                    // Create necessary directories
                    powershell """
                        \$artifactDir = "${env:ARTIFACT_DIR}"
                        \$logDir = "${env:LOG_DIR}"
                        
                        if (-not (Test-Path \$artifactDir)) {
                            New-Item -ItemType Directory -Path \$artifactDir -Force | Out-Null
                        }
                        
                        if (-not (Test-Path \$logDir)) {
                            New-Item -ItemType Directory -Path \$logDir -Force | Out-Null
                        }
                        
                        Write-Host "Directories created successfully"
                    """
                }
            }
        }

        stage('Validate Parameters') {
            steps {
                script {
                    powershell """
                        \$errors = @()
                        
                        if ([string]::IsNullOrWhiteSpace("${params:CLOUD_CONNECTOR_HOSTNAME}")) {
                            \$errors += "CLOUD_CONNECTOR_HOSTNAME parameter is required"
                        }
                        
                        if ([string]::IsNullOrWhiteSpace("${params:CERTIFICATE_THUMBPRINT}")) {
                            \$errors += "CERTIFICATE_THUMBPRINT parameter is required"
                        }
                        
                        if ([string]::IsNullOrWhiteSpace("${params:CITRIX_CUSTOMER_ID}")) {
                            \$errors += "CITRIX_CUSTOMER_ID parameter is required"
                        }
                        
                        if (\$errors.Count -gt 0) {
                            Write-Host "Parameter Validation Failed:" -ForegroundColor Red
                            \$errors | ForEach-Object { Write-Host "  - \$_" -ForegroundColor Red }
                            exit 1
                        }
                        
                        Write-Host "All required parameters provided" -ForegroundColor Green
                    """
                }
            }
        }

        stage('Retrieve Credentials') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: "${params.CITRIX_API_CREDENTIALS}",
                        usernameVariable: 'CITRIX_API_KEY',
                        passwordVariable: 'CITRIX_API_SECRET'
                    )]) {
                        env.CITRIX_API_KEY = CITRIX_API_KEY
                        env.CITRIX_API_SECRET = CITRIX_API_SECRET
                        echo "Credentials retrieved from Jenkins Credential Store"
                    }
                }
            }
        }

        stage('Execute Validation') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: "${params.CITRIX_API_CREDENTIALS}",
                        usernameVariable: 'CITRIX_API_KEY',
                        passwordVariable: 'CITRIX_API_SECRET'
                    )]) {
                        def exitCode = powershell(
                            script: """
                                \$scriptPath = "${env:SCRIPT_PATH}"
                                \$logDir = "${env:LOG_DIR}"
                                
                                if (-not (Test-Path \$scriptPath)) {
                                    Write-Host "ERROR: Script not found at \$scriptPath" -ForegroundColor Red
                                    exit 1
                                }
                                
                                Write-Host "Executing validation script..." -ForegroundColor Cyan
                                Write-Host ""
                                
                                \$startTime = Get-Date
                                
                                & "\$scriptPath" `
                                    -CloudConnectorHostname "${params:CLOUD_CONNECTOR_HOSTNAME}" `
                                    -CertificateThumbprint "${params:CERTIFICATE_THUMBPRINT}" `
                                    -CitrixCustomerId "${params:CITRIX_CUSTOMER_ID}" `
                                    -CitrixApiKey "\$env:CITRIX_API_KEY" `
                                    -CitrixApiSecret "\$env:CITRIX_API_SECRET" `
                                    -LogPath "\$logDir\\validation-${env:BUILD_NUMBER}.log"
                                
                                \$endTime = Get-Date
                                \$duration = \$endTime - \$startTime
                                
                                Write-Host ""
                                Write-Host "Validation execution completed in \$(\$duration.TotalSeconds) seconds" -ForegroundColor Cyan
                                
                                exit \$LASTEXITCODE
                            """,
                            returnStatus: true
                        )
                        
                        if (exitCode != 0) {
                            currentBuild.result = 'FAILURE'
                            error("Cloud Connector validation failed with exit code: ${exitCode}")
                        }
                    }   
                }
            }
        }

        stage('Archive Logs') {
            steps {
                script {
                    powershell """
                        \$logDir = "${env:LOG_DIR}"
                        \$artifactDir = "${env:ARTIFACT_DIR}"
                        
                        if (Test-Path \$logDir) {
                            \$logFiles = Get-ChildItem -Path \$logDir -Filter "*.log"
                            
                            if (\$logFiles.Count -gt 0) {
                                Write-Host "Archiving \$(\$logFiles.Count) log file(s)..."
                                Copy-Item -Path \$logDir\\* -Destination \$artifactDir -Force
                                Write-Host "Logs archived to artifacts directory"
                            }
                        }
                    """
                    
                    // Archive artifacts
                    archiveArtifacts(
                        artifacts: 'artifacts/**/*.log',
                        allowEmptyArchive: true,
                        onlyIfSuccessful: false
                    )
                }
            }
        }
    }

    post {
        always {
            script {
                echo "Pipeline execution completed"
                
                // Clean up sensitive data from logs
                powershell """
                    \$logDir = "${env:LOG_DIR}"
                    
                    if (Test-Path \$logDir) {
                        Get-ChildItem -Path \$logDir -Filter "*.log" | ForEach-Object {
                            \$content = Get-Content -Path \$_.FullName -Raw
                            # Remove sensitive patterns (basic sanitization)
                            \$content = \$content -replace 'Bearer\\s+[A-Za-z0-9\\-\\._~\\+\\/]+=*', 'Bearer [REDACTED]'
                            \$content = \$content -replace 'token[''"]?\\s*:\\s*[''"]([^''"]*)[''\"]', 'token: [REDACTED]'
                            Set-Content -Path \$_.FullName -Value \$content -NoNewline
                        }
                    }
                """
            }
        }

        success {
            script {
                echo "=========================================="
                echo "VALIDATION SUCCESSFUL"
                echo "=========================================="
                
                // Send success notification (configure according to your needs)
                // emailext(
                //     subject: "Citrix Cloud Connector Validation Successful - ${params.CLOUD_CONNECTOR_HOSTNAME}",
                //     body: "The Cloud Connector '${params.CLOUD_CONNECTOR_HOSTNAME}' has been validated successfully.\n\nBuild: ${env.BUILD_URL}",
                //     to: "${env.NOTIFY_EMAIL}"
                // )
            }
        }

        failure {
            script {
                echo "=========================================="
                echo "VALIDATION FAILED"
                echo "=========================================="
                echo "Cloud Connector: ${params.CLOUD_CONNECTOR_HOSTNAME}"
                echo "Build: ${env.BUILD_URL}"
                
                // Send failure notification (configure according to your needs)
                // emailext(
                //     subject: "FAILED: Citrix Cloud Connector Validation - ${params.CLOUD_CONNECTOR_HOSTNAME}",
                //     body: "The Cloud Connector validation for '${params.CLOUD_CONNECTOR_HOSTNAME}' has failed.\n\nBuild: ${env.BUILD_URL}\n\nPlease check the logs for details.",
                //     to: "${env.NOTIFY_EMAIL}",
                //     attachmentsPattern: 'logs/**/*.log'
                // )
            }
        }

        unstable {
            script {
                echo "Pipeline is unstable - check logs for warnings"
            }
        }
    }
}
