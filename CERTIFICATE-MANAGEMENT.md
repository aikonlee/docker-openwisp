# Certificate Management Guide

This document explains certificate handling in the OpenWISP Docker stack and how to manage them.

## Overview

OpenWISP uses SSL/TLS certificates for:

1. **NGINX (Web UI and API)**: Self-signed development certificates or Let's Encrypt production certificates
2. **Postfix (Mail Server)**: Self-signed mail certificates

## Certificate Locations

### Inside Containers

- **NGINX Dashboard**: `/etc/letsencrypt/live/{DASHBOARD_DOMAIN}/`
- **NGINX API**: `/etc/letsencrypt/live/{API_DOMAIN}/`
- **Postfix Mail**: `/etc/ssl/mail/openwisp.mail.*`

### Certificate Files

- `privkey.pem` - Private key (keep secure, mode 600)
- `fullchain.pem` - Full certificate chain (public, mode 644)
- `*.crt` - Certificate file
- `*.key` - Private key file

## Development Mode

In development mode, the system automatically generates self-signed certificates with:

- **Validity**: 3650 days (10 years) - increased from 365 days
- **Algorithm**: RSA 4096-bit
- **Subject**: CN=OpenWISP
- **SAN Extensions**: Includes wildcard and domain variants

### Auto-renewal

Certificates are checked for expiration each time containers start:

- If expired or expiring within 30 days, they are automatically regenerated
- No manual intervention required for local development

## Production Mode

In production mode, Let's Encrypt certificates are automatically renewed:

- Uses certbot in standalone mode
- Renewal scheduled weekly via crontab
- Requires ports 80/443 to be accessible

## Certificate Management Commands

### Check Certificate Status

```bash
# Check all certificates in running containers
./scripts/check-certificates.sh

# With specific domains
DASHBOARD_DOMAIN=myapp.example.com API_DOMAIN=api.example.com ./scripts/check-certificates.sh
```

### Renew/Regenerate Certificates

```bash
# Renew all certificates
./scripts/renew-certificates.sh all

# Renew only NGINX certificates
./scripts/renew-certificates.sh nginx

# Renew only Postfix certificate
./scripts/renew-certificates.sh postfix
```

### Makefile Targets

```bash
# Check certificate status
make cert-audit

# Renew certificates
make cert-renew
```

## Certificate Expiration Handling

### Automatic Handling

- Development certs are auto-regenerated if expired or expiring within 30 days
- No restart needed - just container re-initialization
- Happens automatically on first container start

### Manual Intervention

1. **If development certificates expire**:

   ```bash
   ./scripts/renew-certificates.sh all
   ```

2. **If production certificates expire**:
   - Verify certbot renewal is running: `docker logs <nginx-container>`
   - Manually renew if needed: `./scripts/renew-certificates.sh nginx`

3. **Check current status**:
   ```bash
   ./scripts/check-certificates.sh
   ```

## Best Practices

1. **Development**:
   - Use the automatic certificate generation
   - No need to manually manage certificates
   - Certificates valid for 10 years

2. **Staging**:
   - Use Let's Encrypt staging environment first to test
   - Then switch to production Let's Encrypt

3. **Production**:
   - Use Let's Encrypt for automatic renewal
   - Monitor certificate expiration via monitoring tools
   - Set up alerts for certificates expiring in 30 days
   - Weekly renewal checks ensure 7-day safety buffer

## Troubleshooting

### Certificate Validation Failed

```bash
# Validate a certificate
openssl x509 -in /etc/letsencrypt/live/domain/fullchain.pem -text -noout

# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/domain/fullchain.pem -enddate -noout
```

### NGINX SSL Errors

```bash
# Verify certificate and key match
openssl x509 -noout -modulus -in /etc/letsencrypt/live/domain/fullchain.pem | openssl md5
openssl rsa -noout -modulus -in /etc/letsencrypt/live/domain/privkey.pem | openssl md5

# If they don't match, regenerate:
./scripts/renew-certificates.sh nginx
```

### Postfix TLS Issues

```bash
# Check postfix certificate validity
docker exec <postfix-container> openssl x509 -in /etc/ssl/mail/openwisp.mail.crt -text -noout

# Regenerate if needed
./scripts/renew-certificates.sh postfix
```

## Advanced: Custom Certificates

To use custom certificates:

1. **Copy certificates to volumes**:

   ```bash
   docker cp mycert.crt <nginx-container>:/etc/letsencrypt/live/domain/fullchain.pem
   docker cp mykey.pem <nginx-container>:/etc/letsencrypt/live/domain/privkey.pem
   ```

2. **Set proper permissions**:

   ```bash
   docker exec <nginx-container> chmod 600 /etc/letsencrypt/live/domain/privkey.pem
   docker exec <nginx-container> chmod 644 /etc/letsencrypt/live/domain/fullchain.pem
   ```

3. **Reload NGINX**:
   ```bash
   docker exec <nginx-container> nginx -s reload
   ```

## Security Notes

- **Private Keys**: Always kept with 600 permissions (readable only by owner)
- **Public Certificates**: Kept with 644 permissions (world readable)
- **In Production**: Consider using a dedicated certificate management service
- **Monitoring**: Regularly audit certificate expiration dates
- **Renewal**: Maintain at least 30-day buffer before expiration

## Environment Variables

Configure certificate domains via environment variables:

```bash
export DASHBOARD_DOMAIN="dashboard.example.com"
export API_DOMAIN="api.example.com"
export CERT_ADMIN_EMAIL="admin@example.com"  # For Let's Encrypt
```

Then restart containers:

```bash
docker compose -f docker-compose.yml -f docker-compose.arm64.yml restart nginx
```
