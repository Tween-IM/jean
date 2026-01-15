# MAS Configuration Verification Script
# Run this on your MAS server to check configuration

#!/bin/bash

echo "=== MAS Configuration Check ==="
echo

# Check if MAS is running
echo "1. Checking MAS service status..."
systemctl status mas --no-pager -l || echo "MAS service not running"

echo
echo "2. Checking MAS configuration file..."
if [ -f /etc/mas/mas.yaml ]; then
    echo "✓ MAS config exists at /etc/mas/mas.yaml"
    grep -A 10 "clients:" /etc/mas/mas.yaml || echo "No clients section found"
else
    echo "✗ MAS config not found at /etc/mas/mas.yaml"
fi

echo
echo "3. Checking MAS logs..."
journalctl -u mas --no-pager -n 20 | grep -i error || echo "No recent errors in MAS logs"

echo
echo "4. Testing MAS endpoints..."
curl -s -k https://localhost:8080/.well-known/openid-configuration | head -5 || echo "MAS not responding on localhost:8080"

echo
echo "5. Checking database connectivity..."
# This would require database credentials

echo
echo "=== Next Steps ==="
echo "1. Ensure MAS config is deployed to /etc/mas/mas.yaml"
echo "2. Restart MAS: systemctl restart mas"
echo "3. Check logs: journalctl -u mas -f"
echo "4. Test client auth again"