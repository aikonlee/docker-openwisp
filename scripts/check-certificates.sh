#!/bin/bash
# Certificate expiration check and audit script
# This script checks all certificates used in the OpenWISP docker-compose stack

set -euo pipefail

echo "=================================="
echo "OpenWISP Certificate Audit"
echo "=================================="
echo ""

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ISSUES_FOUND=0
CERTS_CHECKED=0

# Function to check certificate expiration
check_cert_expiry() {
	local cert_file="$1"
	local cert_name="$2"

	if [ ! -f "$cert_file" ]; then
		echo -e "${YELLOW}⚠ ${cert_name}: File not found${NC}"
		return 1
	fi

	CERTS_CHECKED=$((CERTS_CHECKED + 1))

	# Extract expiration date
	local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
	local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
	local current_epoch=$(date +%s)
	local diff=$((expiry_epoch - current_epoch))
	local days_left=$((diff / 86400))

	# Check if certificate is expired
	if [ $diff -lt 0 ]; then
		echo -e "${RED}✗ ${cert_name}: EXPIRED (expired $((-days_left)) days ago)${NC}"
		echo "  File: $cert_file"
		echo "  Expired: $expiry_date"
		ISSUES_FOUND=$((ISSUES_FOUND + 1))
		return 1
	fi

	# Check if certificate expires within 30 days
	if [ $diff -lt 2592000 ]; then
		echo -e "${YELLOW}⚠ ${cert_name}: Expiring soon ($days_left days left)${NC}"
		echo "  File: $cert_file"
		echo "  Expires: $expiry_date"
		ISSUES_FOUND=$((ISSUES_FOUND + 1))
		return 1
	fi

	# Certificate is valid
	echo -e "${GREEN}✓ ${cert_name}: Valid ($days_left days remaining)${NC}"
	echo "  File: $cert_file"
	echo "  Expires: $expiry_date"
	return 0
}

# Check environment variables for domain names
DASHBOARD_DOMAIN="${DASHBOARD_DOMAIN:-localhost}"
API_DOMAIN="${API_DOMAIN:-localhost}"

echo "Configuration:"
echo "  DASHBOARD_DOMAIN: $DASHBOARD_DOMAIN"
echo "  API_DOMAIN: $API_DOMAIN"
echo ""

echo "Checking running container certificates..."
echo ""

# Check certificates in running containers (if available)
if command -v docker &>/dev/null; then

	# Check nginx container certificates
	if docker ps --format '{{.Names}}' | grep -q nginx; then
		echo "=== NGINX Container Certificates ==="
		NGINX_CONTAINER=$(docker ps --format '{{.Names}}' | grep nginx | head -1)

		# Check dashboard certificate
		if docker exec "$NGINX_CONTAINER" test -f /etc/letsencrypt/live/${DASHBOARD_DOMAIN}/fullchain.pem 2>/dev/null; then
			TEMP_CERT=$(mktemp)
			docker cp "$NGINX_CONTAINER":/etc/letsencrypt/live/${DASHBOARD_DOMAIN}/fullchain.pem "$TEMP_CERT"
			check_cert_expiry "$TEMP_CERT" "NGINX - Dashboard Certificate (${DASHBOARD_DOMAIN})"
			rm -f "$TEMP_CERT"
			echo ""
		fi

		# Check API certificate
		if docker exec "$NGINX_CONTAINER" test -f /etc/letsencrypt/live/${API_DOMAIN}/fullchain.pem 2>/dev/null; then
			TEMP_CERT=$(mktemp)
			docker cp "$NGINX_CONTAINER":/etc/letsencrypt/live/${API_DOMAIN}/fullchain.pem "$TEMP_CERT"
			check_cert_expiry "$TEMP_CERT" "NGINX - API Certificate (${API_DOMAIN})"
			rm -f "$TEMP_CERT"
			echo ""
		fi
	fi

	# Check postfix container certificates
	if docker ps --format '{{.Names}}' | grep -q postfix; then
		echo "=== Postfix Container Certificates ==="
		POSTFIX_CONTAINER=$(docker ps --format '{{.Names}}' | grep postfix | head -1)

		if docker exec "$POSTFIX_CONTAINER" test -f /etc/ssl/mail/openwisp.mail.crt 2>/dev/null; then
			TEMP_CERT=$(mktemp)
			docker cp "$POSTFIX_CONTAINER":/etc/ssl/mail/openwisp.mail.crt "$TEMP_CERT"
			check_cert_expiry "$TEMP_CERT" "Postfix - Mail Certificate"
			rm -f "$TEMP_CERT"
			echo ""
		fi
	fi
fi

# Summary
echo "=================================="
echo "Summary:"
echo "  Certificates checked: $CERTS_CHECKED"
echo "  Issues found: $ISSUES_FOUND"
echo "=================================="
echo ""

if [ $ISSUES_FOUND -eq 0 ] && [ $CERTS_CHECKED -gt 0 ]; then
	echo -e "${GREEN}All certificates are valid!${NC}"
	exit 0
elif [ $CERTS_CHECKED -eq 0 ]; then
	echo -e "${YELLOW}No certificates found to check. Make sure containers are running.${NC}"
	exit 1
else
	echo -e "${RED}Certificate issues found. Consider regenerating expired certificates.${NC}"
	exit 1
fi
