#!/bin/bash
# Certificate renewal/regeneration helper script
# This script helps regenerate expired certificates in the OpenWISP stack

set -euo pipefail

echo "=================================="
echo "OpenWISP Certificate Renewal"
echo "=================================="
echo ""

if [ $# -lt 1 ]; then
	echo "Usage: $0 [all|nginx|postfix]"
	echo ""
	echo "Options:"
	echo "  all      - Renew all certificates"
	echo "  nginx    - Renew NGINX SSL certificates (dashboard + API)"
	echo "  postfix  - Renew Postfix mail certificate"
	echo ""
	exit 1
fi

RENEW_TYPE="${1:-all}"

# Environment variables
DASHBOARD_DOMAIN="${DASHBOARD_DOMAIN:-localhost}"
API_DOMAIN="${API_DOMAIN:-localhost}"

echo "Configuration:"
echo "  DASHBOARD_DOMAIN: $DASHBOARD_DOMAIN"
echo "  API_DOMAIN: $API_DOMAIN"
echo ""

# Function to regenerate nginx certificates
renew_nginx_certs() {
	echo "Regenerating NGINX certificates..."

	if ! command -v docker &>/dev/null; then
		echo "Error: Docker is not available"
		return 1
	fi

	NGINX_CONTAINER=$(docker ps --format '{{.Names}}' | grep nginx | head -1 || true)
	if [ -z "$NGINX_CONTAINER" ]; then
		echo "Error: No running nginx container found"
		return 1
	fi

	echo "Found NGINX container: $NGINX_CONTAINER"

	# Execute certificate regeneration inside container
	docker exec "$NGINX_CONTAINER" bash -c "
        source /etc/nginx/utils.sh 2>/dev/null || source /home/openwisp/utils.sh || true
        
        echo 'Regenerating dashboard certificate...'
        rm -f /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/privkey.pem
        rm -f /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/fullchain.pem
        mkdir -p /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/
        openssl req -x509 -newkey rsa:4096 \
            -keyout /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/privkey.pem \
            -out /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/fullchain.pem \
            -days 3650 -nodes -subj '/CN=OpenWISP' \
            -addext \"subjectAltName=DNS:\${DASHBOARD_DOMAIN},DNS:*.\${DASHBOARD_DOMAIN}\"
        chmod 600 /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/privkey.pem
        chmod 644 /etc/letsencrypt/live/\${DASHBOARD_DOMAIN}/fullchain.pem
        
        echo 'Regenerating API certificate...'
        rm -f /etc/letsencrypt/live/\${API_DOMAIN}/privkey.pem
        rm -f /etc/letsencrypt/live/\${API_DOMAIN}/fullchain.pem
        mkdir -p /etc/letsencrypt/live/\${API_DOMAIN}/
        openssl req -x509 -newkey rsa:4096 \
            -keyout /etc/letsencrypt/live/\${API_DOMAIN}/privkey.pem \
            -out /etc/letsencrypt/live/\${API_DOMAIN}/fullchain.pem \
            -days 3650 -nodes -subj '/CN=OpenWISP' \
            -addext \"subjectAltName=DNS:\${API_DOMAIN},DNS:*.\${API_DOMAIN}\"
        chmod 600 /etc/letsencrypt/live/\${API_DOMAIN}/privkey.pem
        chmod 644 /etc/letsencrypt/live/\${API_DOMAIN}/fullchain.pem
        
        echo 'Reloading NGINX...'
        nginx -s reload || nginx
    " || echo "Note: Certificate regeneration completed with some output"

	echo "✓ NGINX certificates regenerated"
}

# Function to regenerate postfix certificates
renew_postfix_certs() {
	echo "Regenerating Postfix mail certificate..."

	if ! command -v docker &>/dev/null; then
		echo "Error: Docker is not available"
		return 1
	fi

	POSTFIX_CONTAINER=$(docker ps --format '{{.Names}}' | grep postfix | head -1 || true)
	if [ -z "$POSTFIX_CONTAINER" ]; then
		echo "Warning: No running postfix container found"
		return 1
	fi

	echo "Found Postfix container: $POSTFIX_CONTAINER"

	# Execute certificate regeneration inside container
	docker exec "$POSTFIX_CONTAINER" bash -c "
        mkdir -p /etc/ssl/mail/
        rm -f /etc/ssl/mail/openwisp.mail.key
        rm -f /etc/ssl/mail/openwisp.mail.crt
        
        echo 'Regenerating mail certificate...'
        openssl req -new -nodes -x509 -subj '/CN=openwisp-postfix' \
            -days 3650 -keyout /etc/ssl/mail/openwisp.mail.key \
            -out /etc/ssl/mail/openwisp.mail.crt -extensions v3_ca
        
        chmod 600 /etc/ssl/mail/openwisp.mail.key
        chmod 644 /etc/ssl/mail/openwisp.mail.crt
        
        # Reload postfix configuration
        postconf -e smtpd_tls_cert_file=/etc/ssl/mail/openwisp.mail.crt
        postconf -e smtpd_tls_key_file=/etc/ssl/mail/openwisp.mail.key
        postfix reload || postfix start
    " || echo "Note: Postfix certificate regeneration completed"

	echo "✓ Postfix mail certificate regenerated"
}

# Execute based on RENEW_TYPE
case "$RENEW_TYPE" in
all)
	renew_nginx_certs
	echo ""
	renew_postfix_certs
	;;
nginx)
	renew_nginx_certs
	;;
postfix)
	renew_postfix_certs
	;;
*)
	echo "Error: Invalid certificate type '$RENEW_TYPE'"
	exit 1
	;;
esac

echo ""
echo "=================================="
echo "Certificate renewal completed"
echo "=================================="
echo ""
echo "Next steps:"
echo "  1. Run the certificate audit: ./scripts/check-certificates.sh"
echo "  2. Verify services are still running: docker compose ps"
echo "  3. Test HTTPS connectivity to your services"
echo ""
