#!/bin/bash

# Script to create 300k resources using kube-burner
# Note: Run this script from the repository root directory

set -e

# Change to repository root directory
cd "$(dirname "$0")/.."

CONFIG_FILE="configs/kube-burner-large-scale.yaml"
LOG_FILE="kube-burner-300k-$(date +%Y%m%d-%H%M%S).log"

echo "Starting 300k resource creation using kube-burner"
echo "Config file: $CONFIG_FILE"
echo "Log file: $LOG_FILE"
echo "Start time: $(date)"

# Check if kube-burner is available
if ! command -v kube-burner &> /dev/null; then
    echo "ERROR: kube-burner not found. Please install it first:"
    echo "https://github.com/cloud-bulldozer/kube-burner/releases"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file $CONFIG_FILE not found"
    exit 1
fi

# Create namespaces first
echo "Creating namespaces for large-scale test..."
for i in {0..9}; do
    NS_NAME="velero-perf-test-$i"
    echo "  Creating namespace: $NS_NAME"
    kubectl create namespace "$NS_NAME" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NS_NAME" velero-test=performance --overwrite
done

echo ""
echo "All namespaces created successfully!"
echo ""

# Run kube-burner
echo "Running kube-burner to create resources..."
kube-burner init -c "$CONFIG_FILE" --log-level=info 2>&1 | tee "$LOG_FILE"

echo ""
echo "Resource creation completed at: $(date)"
echo "Log saved to: $LOG_FILE"

echo ""
echo "Verifying resource counts..."

# Count resources by type
echo "ConfigMaps:"
kubectl get configmaps --all-namespaces -l velero-test=performance,object-type=configmap --no-headers | wc -l

echo "Secrets:"
kubectl get secrets --all-namespaces -l velero-test=performance,object-type=secret --no-headers | wc -l

echo "Services:"
kubectl get services --all-namespaces -l velero-test=performance,object-type=service --no-headers | wc -l

echo "Namespaces:"
kubectl get namespaces -l velero-test=performance --no-headers | wc -l

echo ""
echo "Total objects with velero-test=performance label:"
kubectl get all,configmaps,secrets --all-namespaces -l velero-test=performance --no-headers | wc -l

echo ""