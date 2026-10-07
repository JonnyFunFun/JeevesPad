#!/bin/bash
# Deploy Jeeves to jailbroken iPad
# Usage: ./deploy.sh
#
# Configure your iPad's IP address below, or set IPAD_IP environment variable

IPAD_IP="${IPAD_IP:-YOUR_IPAD_IP}"
IPAD_PASS="${IPAD_PASS:-alpine}"

if [ "$IPAD_IP" = "YOUR_IPAD_IP" ]; then
    echo "Error: Please set your iPad's IP address"
    echo "Edit deploy.sh and replace YOUR_IPAD_IP, or run:"
    echo "  IPAD_IP=192.168.1.xxx ./deploy.sh"
    exit 1
fi
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no"

# Verify the SSH password before building; prompt if the default doesn't work.
# sshpass exits with 5 when the password is rejected.
check_login() {
    SSHPASS="$IPAD_PASS" sshpass -e ssh $SSH_OPTS -o ConnectTimeout=10 \
        root@$IPAD_IP "true" 2>/dev/null
}

echo "Checking SSH login to $IPAD_IP..."
check_login
status=$?
attempts=0
while [ $status -eq 5 ]; do
    if [ $attempts -ge 3 ]; then
        echo "Error: Too many failed password attempts"
        exit 1
    fi
    echo "SSH password was rejected."
    read -r -s -p "Enter root password for $IPAD_IP: " IPAD_PASS
    echo ""
    attempts=$((attempts + 1))
    check_login
    status=$?
done
if [ $status -ne 0 ]; then
    echo "Error: Could not connect to $IPAD_IP over SSH (sshpass exit code $status)"
    exit 1
fi
# Pass the password via the environment so it doesn't appear in the process list
export SSHPASS="$IPAD_PASS"

echo "Building Jeeves..."
./build_ipa.sh

echo ""
echo "Deploying to iPad at $IPAD_IP..."
echo ""

# Extract the app
rm -rf Payload
unzip -o Jeeves.ipa

# Kill the app if running
echo "Stopping Jeeves if running..."
sshpass -e ssh $SSH_OPTS root@$IPAD_IP "killall Jeeves 2>/dev/null || true"

# Remove the app's pre-rename install. Its settings are migrated (and then deleted)
# by Jeeves on first launch, so this only removes the old app bundle.
echo "Removing old HomeButler app if present..."
sshpass -e ssh $SSH_OPTS root@$IPAD_IP "if [ -d /Applications/HomeButler.app ]; then killall HomeButler 2>/dev/null; rm -rf /Applications/HomeButler.app && uicache && echo 'Removed HomeButler.app'; fi"

# Copy to iPad
echo "Copying app to iPad..."
sshpass -e scp $SSH_OPTS -r Payload/Jeeves.app root@$IPAD_IP:/Applications/

# Set permissions and refresh
echo "Setting permissions and refreshing UI cache..."
sshpass -e ssh $SSH_OPTS root@$IPAD_IP "chmod -R 755 /Applications/Jeeves.app && chown -R root:wheel /Applications/Jeeves.app && uicache -p /Applications/Jeeves.app"

# Launch the app
echo "Launching Jeeves..."
sshpass -e ssh $SSH_OPTS root@$IPAD_IP "open com.jeeves.Jeeves || uiopen /Applications/Jeeves.app"

# Cleanup
rm -rf Payload

echo ""
echo "Done! Jeeves updated and launched on iPad."
