#!/bin/bash
# Deploy Jeeves to jailbroken iPad
# Usage: ./deploy.sh
#
# Configure your iPad's IP address below, or set IPAD_IP environment variable.
# To deploy to several iPads at once, use deploy_fleet.sh.

cd "$(dirname "$0")" || exit 1
source ./deploy_common.sh

IPAD_IP="${IPAD_IP:-YOUR_IPAD_IP}"

if [ "$IPAD_IP" = "YOUR_IPAD_IP" ]; then
    echo "Error: Please set your iPad's IP address"
    echo "Edit deploy.sh and replace YOUR_IPAD_IP, or run:"
    echo "  IPAD_IP=192.168.1.xxx ./deploy.sh"
    exit 1
fi

# Verify the SSH password before building; prompt if the default doesn't work
echo "Checking SSH login to $IPAD_IP..."
jeeves_confirm_password "$IPAD_IP"
status=$?
if [ $status -eq 5 ]; then
    exit 1
elif [ $status -ne 0 ]; then
    echo "Error: Could not connect to $IPAD_IP over SSH (sshpass exit code $status)"
    exit 1
fi

echo "Building Jeeves..."
jeeves_build_payload || exit 1

echo ""
echo "Deploying to iPad at $IPAD_IP..."
echo ""
jeeves_install "$IPAD_IP"
result=$?

# Cleanup
rm -rf Payload

if [ $result -ne 0 ]; then
    echo "Error: Deploying to $IPAD_IP failed"
    exit 1
fi
echo ""
echo "Done! Jeeves updated and launched on iPad."
