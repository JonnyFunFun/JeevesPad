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

# Installs the Cydia packages Jeeves's installation needs, if they're missing:
# uikittools (uicache: adds the app to the home screen) and com.conradkramer.open (open:
# starts Jeeves remotely). Keep in sync with DEPENDENCIES_SCRIPT in jeevespad/app/jeevespad_manager/ssh.py.
JEEVES_DEPENDENCIES_SCRIPT='missing=""
command -v uicache >/dev/null 2>&1 || missing="$missing uikittools"
command -v open >/dev/null 2>&1 || missing="$missing com.conradkramer.open"
if [ -z "$missing" ]; then echo "deps=ok"; exit 0; fi
command -v apt-get >/dev/null 2>&1 || { echo "deps=noapt$missing"; exit 3; }
echo "Installing$missing from Cydia..."
apt-get update >/dev/null 2>&1
apt-get install -y --force-yes $missing 2>&1 | tail -3
command -v uicache >/dev/null 2>&1 || { echo "deps=failed uikittools"; exit 4; }
command -v open >/dev/null 2>&1 || echo "deps=warn com.conradkramer.open"
exit 0'

# Makes sure the Cydia packages installing needs are on $1 (SSHPASS must be set)
jeeves_ensure_dependencies() {
    local host="$1" output status
    echo "Checking Cydia packages..."
    output=$(sshpass -e ssh $SSH_OPTS root@"$host" "$JEEVES_DEPENDENCIES_SCRIPT")
    status=$?
    echo "$output" | grep -v '^deps='
    case "$status" in
        0) ;;
        3) echo "Error: $host is missing Cydia packages (${output#*deps=noapt }) and has no apt-get to install them." >&2; return 1 ;;
        4) echo "Error: couldn't install UIKit Tools (uikittools) on $host. Install it from Cydia, then try again." >&2; return 1 ;;
        *) echo "Error: couldn't check Cydia packages on $host (exit code $status)." >&2; return 1 ;;
    esac
    if echo "$output" | grep -q '^deps=warn'; then
        echo "Warning: couldn't install Open (com.conradkramer.open), so Jeeves can't be started remotely. Start it from the home screen."
    fi
}

# Installs ./Payload/Jeeves.app on $1 and launches it (SSHPASS must be set)
jeeves_install() {
    local host="$1"

    jeeves_ensure_dependencies "$host" || return 1

    echo "Stopping Jeeves if running..."
    sshpass -e ssh $SSH_OPTS root@"$host" "killall Jeeves 2>/dev/null || true" || return 1

    # Remove the app's pre-rename install. Its settings are migrated (and then deleted)
    # by Jeeves on first launch, so this only removes the old app bundle.
    echo "Removing old HomeButler app if present..."
    sshpass -e ssh $SSH_OPTS root@"$host" "if [ -d /Applications/HomeButler.app ]; then killall HomeButler 2>/dev/null; rm -rf /Applications/HomeButler.app && uicache && echo 'Removed HomeButler.app'; fi" || return 1

    # scp won't create the app folder itself on a first install (the iPad's SFTP server
    # can't resolve a target that doesn't exist yet), so make sure it's there
    echo "Copying app to iPad..."
    sshpass -e ssh $SSH_OPTS root@"$host" "mkdir -p /Applications/Jeeves.app" || return 1
    sshpass -e scp $SSH_OPTS -r Payload/Jeeves.app root@"$host":/Applications/ || return 1

    echo "Setting permissions and refreshing UI cache..."
    sshpass -e ssh $SSH_OPTS root@"$host" "chmod -R 755 /Applications/Jeeves.app && chown -R root:wheel /Applications/Jeeves.app && uicache -p /Applications/Jeeves.app" || return 1

    echo "Launching Jeeves..."
    sshpass -e ssh $SSH_OPTS root@"$host" "open com.jeeves.Jeeves || uiopen /Applications/Jeeves.app"
}
