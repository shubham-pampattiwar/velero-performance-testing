#!/bin/bash

# Run 150k objects test for Velero performance testing
# Uses kube-burner to create objects and optionally monitors backup performance

set -e

KUBE_BURNER_CONFIG="configs/kube-burner-150k-objects.yaml"
MONITOR_BACKUP=false
BACKUP_NAME=""
CLEANUP_BEFORE=false

usage() {
    echo "Usage: $0 [-m BACKUP_NAME] [-c] [-h]"
    echo ""
    echo "Options:"
    echo "  -m BACKUP_NAME    Monitor backup performance after creating objects"
    echo "  -c                Cleanup existing test resources before running"
    echo "  -h                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Just create 150k objects"
    echo "  $0 -c                                 # Cleanup then create 150k objects"
    echo "  $0 -m perf-test-150k                  # Create objects and monitor backup"
    echo "  $0 -c -m perf-test-v1-16-2           # Full test with cleanup and monitoring"
    exit 1
}

while getopts "m:ch" opt; do
    case ${opt} in
        m)
            MONITOR_BACKUP=true
            BACKUP_NAME="$OPTARG"
            ;;
        c)
            CLEANUP_BEFORE=true
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if kube-burner is available
if ! command -v kube-burner &> /dev/null; then
    log_message "ERROR: kube-burner is required but not installed"
    log_message "Please install kube-burner: https://kube-burner.readthedocs.io/en/latest/installation/"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_message "ERROR: kubectl is required but not installed"
    exit 1
fi

# Cleanup if requested
if [ "$CLEANUP_BEFORE" = true ]; then
    log_message "Cleaning up existing test resources..."
    if [ -f "scripts/cleanup-all.sh" ]; then
        ./scripts/cleanup-all.sh
    else
        log_message "WARNING: cleanup-all.sh not found, attempting manual cleanup"
        kubectl delete namespaces -l velero-test=performance --ignore-not-found=true
    fi
    log_message "Cleanup completed"
fi

# Show current cluster status
log_message "Current cluster status:"
if [ -f "scripts/status.sh" ]; then
    ./scripts/status.sh
fi

# Create required namespaces for multi-namespace test
log_message "Creating namespaces for 150k objects test..."
BASE_NAMESPACE="velero-perf-test"
NUM_NAMESPACES=10

for i in $(seq 0 $((NUM_NAMESPACES - 1))); do
    NAMESPACE="${BASE_NAMESPACE}-${i}"
    log_message "Creating namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Add labels to the namespace
    kubectl label namespace "$NAMESPACE" \
        velero-test=performance \
        kube-burner-uuid=150k-test \
        --overwrite
done

log_message "Successfully created $NUM_NAMESPACES namespaces"

# Run kube-burner to create 150k objects
log_message "Starting kube-burner test to create 150k objects..."
log_message "Config: $KUBE_BURNER_CONFIG"

if [ ! -f "$KUBE_BURNER_CONFIG" ]; then
    log_message "ERROR: Configuration file not found: $KUBE_BURNER_CONFIG"
    exit 1
fi

kube-burner init -c "$KUBE_BURNER_CONFIG" --log-level=info

log_message "kube-burner test completed"

# Show final status
log_message "Final cluster status:"
if [ -f "scripts/status.sh" ]; then
    ./scripts/status.sh
fi

# Start backup monitoring if requested
if [ "$MONITOR_BACKUP" = true ]; then
    if [ -z "$BACKUP_NAME" ]; then
        log_message "ERROR: Backup name is required when monitoring is enabled"
        exit 1
    fi
    
    log_message "Starting backup monitoring for: $BACKUP_NAME"
    log_message "Note: You need to create the backup manually in another terminal:"
    log_message "  velero backup create $BACKUP_NAME --selector velero-test=performance"
    log_message ""
    log_message "Waiting for backup to be created..."
    
    # Wait for backup to exist
    while ! kubectl get backup "$BACKUP_NAME" -n velero &> /dev/null; do
        echo -n "."
        sleep 2
    done
    
    log_message ""
    log_message "Backup detected, starting monitoring..."
    ./scripts/monitor-backup-performance.sh -n "$BACKUP_NAME" -v
fi

log_message "Test completed successfully"