# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.x     | :white_check_mark: |
| 1.x     | :x:                |

The Foundation v2 is under active development. Security updates will be provided for the latest stable release.

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in The Foundation, please report it responsibly.

### How to Report

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, use one of these methods:

1. **GitHub Security Advisories** (preferred):
   - Navigate to the [Security tab](https://github.com/openclaw/openclaw/security)
   - Click "Report a vulnerability"
   - Fill out the advisory form with details

2. **Email**:
   - Send to: security@thefoundation.dev
   - Use PGP key if available (check repository for current key)
   - Include "SECURITY" in the subject line

### What to Include

When reporting a vulnerability, please provide:

- Description of the vulnerability
- Steps to reproduce
- Potential impact and attack scenarios
- Affected versions
- Suggested fix (if you have one)
- Your contact information for follow-up

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 5 business days
- **Status Updates**: Weekly until resolved
- **Resolution**: Depends on severity
  - Critical: 7 days
  - High: 14 days
  - Medium: 30 days
  - Low: 60 days

We will:
- Confirm receipt of your report
- Keep you informed of our progress
- Credit you in the security advisory (unless you prefer anonymity)
- Notify you when the vulnerability is fixed

## What Qualifies as a Security Issue

### In Scope

- Authentication and authorization bypasses
- SQL injection, command injection, code injection
- Cross-site scripting (XSS) in dashboard
- Exposure of sensitive data (API keys, credentials, PII)
- Privilege escalation within agent system
- Docker container escapes
- Insecure cryptographic practices
- Denial of service vulnerabilities
- Agent prompt injection leading to unauthorized actions
- Insecure defaults in configuration

### Out of Scope

- Social engineering attacks
- Physical attacks
- Denial of service via excessive resource consumption (rate limiting is user's responsibility)
- Vulnerabilities in third-party dependencies (unless we're using them insecurely)
- Issues requiring physical access to the host
- Self-XSS or issues requiring user to paste malicious content
- Outdated software versions (we track these separately)

## Security Best Practices

### For Contributors

1. **Never commit secrets**
   - All credentials go in `secrets/` directory (gitignored)
   - Use `.env.example` for configuration templates
   - Review diffs before committing

2. **Use parameterized queries**
   - No string concatenation in SQL
   - Use prepared statements or query builders

3. **Validate all input**
   - Sanitize user input
   - Validate agent outputs before execution
   - Escape data in templates

4. **Follow principle of least privilege**
   - Agents should only have permissions they need
   - Docker containers run as non-root
   - Database users have minimal required grants

5. **Keep dependencies updated**
   - Regularly update npm packages
   - Monitor security advisories
   - Use `npm audit` in CI/CD

### For Deployers

1. **Secrets Management**
   - Use Docker secrets in production
   - Consider 1Password Service Accounts or HashiCorp Vault
   - Rotate credentials regularly
   - Never store secrets in environment variables

2. **Network Security**
   - Use Cloudflare Tunnel or similar for external access
   - Enable Cloudflare Access for authentication
   - Configure firewall rules (UFW, iptables)
   - Limit PostgreSQL to internal network only

3. **Container Security**
   - Keep Docker and base images updated
   - Use read-only filesystems where possible
   - Drop unnecessary capabilities
   - Enable user namespaces

4. **Monitoring**
   - Review Grafana dashboards regularly
   - Set up Prometheus alerts for anomalies
   - Monitor log aggregation in Loki
   - Enable audit logging for agent actions

5. **Backup Security**
   - Encrypt backups with strong passphrase
   - Store backups in separate location
   - Test restore procedures regularly
   - Protect backup credentials

## Secrets Management Overview

The Foundation uses a layered approach to secrets management:

### Development

File-based secrets in `secrets/` directory:
```
secrets/
├── db_password.txt
├── anthropic_key.txt
├── openai_key.txt
├── slack_bot_token.txt
├── grafana_password.txt
└── backup_passphrase.txt
```

All files in `secrets/` are gitignored and should have `chmod 600` permissions.

### Production

Docker Swarm secrets (recommended):
```yaml
secrets:
  db_password:
    external: true
  anthropic_key:
    external: true
```

### Advanced

1. **1Password Service Accounts**:
   - Store secrets in 1Password vault
   - Use service account for programmatic access
   - Inject at runtime

2. **HashiCorp Vault**:
   - Store secrets in Vault
   - Use AppRole authentication
   - Dynamic secret generation

3. **Cloud Provider Secrets**:
   - AWS Secrets Manager
   - GCP Secret Manager
   - Azure Key Vault

## Security Headers

The dashboard and Seldon API should implement these security headers:

```
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Content-Security-Policy: default-src 'self'
Referrer-Policy: strict-origin-when-cross-origin
```

## Disclosure Policy

When a security issue is resolved:

1. We will publish a security advisory
2. Credit the reporter (unless they prefer anonymity)
3. Describe the vulnerability and impact
4. Provide upgrade instructions
5. List affected and fixed versions

We will coordinate disclosure timing with the reporter.

## Contact

For security-related questions that are not vulnerabilities:
- Open a GitHub Discussion
- Email: security@thefoundation.dev

For vulnerabilities, use the reporting process above.

## Acknowledgments

We appreciate security researchers who responsibly disclose vulnerabilities. Contributors will be acknowledged in our security advisories and project documentation.

Thank you for helping keep The Foundation secure.
