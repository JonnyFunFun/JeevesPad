#!/bin/bash
# Shared helpers for deploy.sh and deploy_fleet.sh (source this file; don't run it).
#
# Uses IPAD_PASS (default "alpine") as the root password; once confirmed it is
# exported as SSHPASS so `sshpass -e` keeps it out of the process list.

IPAD_PASS="${IPAD_PASS:-alpine}"
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Tries an SSH login to $1 with $IPAD_PASS. Returns sshpass's exit code:
# 0 = OK, 5 = password rejected, anything else = couldn't connect.
jeeves_check_login() {
    SSHPASS="$IPAD_PASS" sshpass -e ssh $SSH_OPTS root@"$1" "true" 2>/dev/null
}

# Confirms the password works on $1, prompting (up to 3 tries) if it's rejected.
# Returns 0 on success, 5 if the password couldn't be confirmed, or the connection
# error code if the host couldn't be reached.
jeeves_confirm_password() {
    local host="$1" status attempts=0
    jeeves_check_login "$host"
    status=$?
    while [ $status -eq 5 ]; do
        if [ $attempts -ge 3 ]; then
            echo "Error: Too many failed password attempts" >&2
            return 5
        fi
        echo "SSH password was rejected."
        read -r -s -p "Enter root password for $host: " IPAD_PASS
        echo ""
        attempts=$((attempts + 1))
        jeeves_check_login "$host"
        status=$?
    done
    if [ $status -eq 0 ]; then
        export SSHPASS="$IPAD_PASS"
    fi
    return $status
}

# Builds Jeeves.ipa and extracts it to ./Payload
jeeves_build_payload() {
    ./build_ipa.sh || return 1
    rm -rf Payload
    unzip -q -o Jeeves.ipa
}

# Installs ./Payload/Jeeves.app on $1 and launches it (SSHPASS must be set)
jeeves_install() {
    local host="$1"

    echo "Stopping Jeeves if running..."
    sshpass -e ssh $SSH_OPTS root@"$host" "killall Jeeves 2>/dev/null || true" || return 1

    # Remove the app's pre-rename install. Its settings are migrated (and then deleted)
    # by Jeeves on first launch, so this only removes the old app bundle.
    echo "Removing old HomeButler app if present..."
    sshpass -e ssh $SSH_OPTS root@"$host" "if [ -d /Applications/HomeButler.app ]; then killall HomeButler 2>/dev/null; rm -rf /Applications/HomeButler.app && uicache && echo 'Removed HomeButler.app'; fi" || return 1

    echo "Copying app to iPad..."
    sshpass -e scp $SSH_OPTS -r Payload/Jeeves.app root@"$host":/Applications/ || return 1

    echo "Setting permissions and refreshing UI cache..."
    sshpass -e ssh $SSH_OPTS root@"$host" "chmod -R 755 /Applications/Jeeves.app && chown -R root:wheel /Applications/Jeeves.app && uicache -p /Applications/Jeeves.app" || return 1

    echo "Launching Jeeves..."
    sshpass -e ssh $SSH_OPTS root@"$host" "open com.jeeves.Jeeves || uiopen /Applications/Jeeves.app"
}
