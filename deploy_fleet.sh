#!/bin/bash
# Deploy Jeeves to a fleet of jailbroken iPads.
#
# iPads are found by Bonjour (every running Jeeves advertises _jeeves._tcp) and/or
# taken from a hosts file, the IPADS environment variable or the command line.
# The app is built once, then installed on each iPad in turn. The root password is
# confirmed once (IPAD_PASS, default "alpine"; you're prompted if that's rejected)
# and the same password is used for every iPad.
#
# Usage: ./deploy_fleet.sh [options] [host ...]
#   -f FILE   Also deploy to the hosts in FILE (one per line; # starts a comment)
#   -n        Don't discover iPads with Bonjour (only use listed hosts)
#   -t SECS   How long to look for iPads with Bonjour (default 5)
#   -s        Skip the build and deploy the existing Jeeves.ipa
#   -y        Don't ask for confirmation before deploying
#   -h        Show this help
#
# Examples:
#   ./deploy_fleet.sh                      # every iPad running Jeeves on the network
#   ./deploy_fleet.sh -n -f ipads.txt      # just the iPads listed in ipads.txt
#   IPADS="10.0.0.20 10.0.0.21" ./deploy_fleet.sh -n

cd "$(dirname "$0")" || exit 1
source ./deploy_common.sh

SERVICE_TYPE="_jeeves._tcp"
DISCOVER=1
DISCOVERY_SECONDS=5
SKIP_BUILD=0
ASSUME_YES=0
HOSTS_FILE=""

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts "f:nt:syh" opt; do
    case "$opt" in
        f) HOSTS_FILE="$OPTARG" ;;
        n) DISCOVER=0 ;;
        t) DISCOVERY_SECONDS="$OPTARG" ;;
        s) SKIP_BUILD=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# --- Collect hosts -----------------------------------------------------------

HOSTS=()
add_host() {
    local host="$1" existing
    [ -z "$host" ] && return
    for existing in "${HOSTS[@]}"; do
        [ "$existing" = "$host" ] && return
    done
    HOSTS+=("$host")
}

# Runs a command for at most $1 seconds (macOS has no `timeout`)
run_for() {
    local seconds="$1"; shift
    "$@" &
    local pid=$!
    sleep "$seconds"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

discover_with_avahi() {
    # Parsable, resolved, terminate after the initial dump:
    # =;iface;IPv4;name;type;domain;hostname;address;port;txt
    local address
    while IFS=';' read -r event _ proto _ _ _ _ address _; do
        [ "$event" = "=" ] && [ "$proto" = "IPv4" ] && add_host "$address"
    done < <(timeout "$((DISCOVERY_SECONDS + 5))" avahi-browse -rpt "$SERVICE_TYPE" 2>/dev/null)
}

discover_with_dns_sd() {
    # Browse for instance names, then resolve each to its .local host name
    local browse names name resolve host
    browse=$(run_for "$DISCOVERY_SECONDS" dns-sd -B "$SERVICE_TYPE" local.)
    names=$(echo "$browse" | awk -v type="$SERVICE_TYPE." '$2 == "Add" { sub(".*" type "[ ]+", ""); print }')
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        resolve=$(run_for 2 dns-sd -L "$name" "$SERVICE_TYPE" local.)
        host=$(echo "$resolve" | sed -n 's/.*can be reached at \([^:]*\)\.:.*/\1/p' | head -1)
        add_host "$host"
    done <<< "$names"
}

if [ $DISCOVER -eq 1 ]; then
    echo "Looking for iPads running Jeeves (${DISCOVERY_SECONDS}s)..."
    if command -v avahi-browse >/dev/null 2>&1; then
        discover_with_avahi
    elif command -v dns-sd >/dev/null 2>&1; then
        discover_with_dns_sd
    else
        echo "Warning: Bonjour discovery needs avahi-browse (Linux: install avahi-utils) or dns-sd (macOS)." >&2
        echo "         Listing iPads with -f FILE, IPADS=\"...\" or as arguments still works." >&2
    fi
fi

if [ -n "$HOSTS_FILE" ]; then
    if [ ! -f "$HOSTS_FILE" ]; then
        echo "Error: Hosts file not found: $HOSTS_FILE" >&2
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(echo "$line" | tr -d '[:space:]')"
        add_host "$line"
    done < "$HOSTS_FILE"
fi
for host in $IPADS "$@"; do
    add_host "$host"
done

if [ ${#HOSTS[@]} -eq 0 ]; then
    echo "Error: No iPads found." >&2
    echo "Make sure Jeeves is running on them (it advertises itself while open), or list them:" >&2
    echo "  ./deploy_fleet.sh -f ipads.txt   or   ./deploy_fleet.sh 10.0.0.20 10.0.0.21" >&2
    exit 1
fi

echo ""
echo "Deploying to ${#HOSTS[@]} iPad(s):"
for host in "${HOSTS[@]}"; do
    echo "  - $host"
done
if [ $ASSUME_YES -eq 0 ]; then
    read -r -p "Continue? [Y/n] " answer
    case "$answer" in
        [nN]*) echo "Cancelled."; exit 0 ;;
    esac
fi

# --- Confirm the fleet password once ------------------------------------------
# Every iPad is assumed to use the same root password: it's confirmed (and prompted
# for if needed) on the first iPad that answers, then reused for all of them.

PASSWORD_CONFIRMED=0
for host in "${HOSTS[@]}"; do
    echo ""
    echo "Checking SSH login to $host..."
    jeeves_confirm_password "$host"
    status=$?
    if [ $status -eq 0 ]; then
        PASSWORD_CONFIRMED=1
        break
    elif [ $status -eq 5 ]; then
        exit 1
    fi
    echo "Couldn't reach $host (sshpass exit code $status); trying the next iPad."
done
if [ $PASSWORD_CONFIRMED -eq 0 ]; then
    echo "Error: None of the iPads could be reached over SSH." >&2
    exit 1
fi

# --- Build once ---------------------------------------------------------------

if [ $SKIP_BUILD -eq 1 ]; then
    if [ ! -f Jeeves.ipa ]; then
        echo "Error: -s given but Jeeves.ipa doesn't exist; run without -s to build it." >&2
        exit 1
    fi
    echo ""
    echo "Using existing Jeeves.ipa"
    rm -rf Payload
    unzip -q -o Jeeves.ipa || exit 1
else
    echo ""
    echo "Building Jeeves..."
    jeeves_build_payload || { echo "Error: Build failed" >&2; exit 1; }
fi

# --- Roll out -----------------------------------------------------------------

SUCCEEDED=()
FAILED=()
for host in "${HOSTS[@]}"; do
    echo ""
    echo "=== $host ==="
    jeeves_check_login "$host"
    status=$?
    if [ $status -eq 5 ]; then
        echo "Password rejected: this iPad doesn't use the fleet's root password. Skipping."
        FAILED+=("$host (password rejected)")
        continue
    elif [ $status -ne 0 ]; then
        echo "Couldn't connect (sshpass exit code $status). Skipping."
        FAILED+=("$host (unreachable)")
        continue
    fi
    if jeeves_install "$host"; then
        SUCCEEDED+=("$host")
    else
        FAILED+=("$host (install failed)")
    fi
done

rm -rf Payload

echo ""
echo "=== Summary ==="
echo "Updated ${#SUCCEEDED[@]} of ${#HOSTS[@]} iPad(s)."
for host in "${SUCCEEDED[@]}"; do echo "  OK      $host"; done
for host in "${FAILED[@]}"; do echo "  FAILED  $host"; done
[ ${#FAILED[@]} -eq 0 ]
