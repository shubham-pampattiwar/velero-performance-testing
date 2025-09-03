#!/bin/bash

# Script to run 150k resources sequentially using separate kube-burner configs
# Runs ConfigMaps, then Secrets, then Services jobs separately
# Note: Run this script from the repository root directory

set -e

# Change to repository root directory
cd "$(dirname "$0")/.."

echo "Starting sequential 150k resource creation using kube-burner"
echo "This will create 50k each of ConfigMaps, Secrets, and Services"
echo "Start time: $(date)"

# Check if kube-burner is available
if ! command -v kube-burner &> /dev/null; then
    echo "ERROR: kube-burner not found. Please install it first:"
    echo "https://github.com/kube-burner/kube-burner/releases"
    exit 1
fi

# Create namespaces first
echo "Creating namespaces for sequential test..."
for i in {0..9}; do
    NS_NAME="velero-perf-test-$i"
    echo "  Creating namespace: $NS_NAME"
    kubectl create namespace "$NS_NAME" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NS_NAME" velero-test=performance --overwrite
done

echo ""
echo "All namespaces created successfully!"
echo ""

# Job 1: ConfigMaps
echo "=== PHASE 1: Creating ConfigMaps ==="
echo "Start time: $(date)"
CONFIG_FILE="configs/kube-burner-configmaps-only.yaml"
LOG_FILE="kube-burner-configmaps-$(date +%Y%m%d-%H%M%S).log"
echo "Config file: $CONFIG_FILE"
echo "Log file: $LOG_FILE"

kube-burner init -c "$CONFIG_FILE" --log-level=info 2>&1 | tee "$LOG_FILE"

echo "ConfigMaps phase completed at: $(date)"
echo "ConfigMaps created:"
kubectl get configmaps --all-namespaces -l velero-test=performance,object-type=configmap --no-headers | wc -l
echo ""

# Job 2: Secrets
echo "=== PHASE 2: Creating Secrets ==="
echo "Start time: $(date)"
CONFIG_FILE="configs/kube-burner-secrets-only.yaml"
LOG_FILE="kube-burner-secrets-$(date +%Y%m%d-%H%M%S).log"
echo "Config file: $CONFIG_FILE"
echo "Log file: $LOG_FILE"

kube-burner init -c "$CONFIG_FILE" --log-level=info 2>&1 | tee "$LOG_FILE"

echo "Secrets phase completed at: $(date)"
echo "Secrets created:"
kubectl get secrets --all-namespaces -l velero-test=performance,object-type=secret --no-headers | wc -l
echo ""

# Job 3: Services
echo "=== PHASE 3: Creating Services ==="
echo "Start time: $(date)"
CONFIG_FILE="configs/kube-burner-services-only.yaml"
LOG_FILE="kube-burner-services-$(date +%Y%m%d-%H%M%S).log"
echo "Config file: $CONFIG_FILE"
echo "Log file: $LOG_FILE"

kube-burner init -c "$CONFIG_FILE" --log-level=info 2>&1 | tee "$LOG_FILE"

echo "Services phase completed at: $(date)"
echo "Services created:"
kubectl get services --all-namespaces -l velero-test=performance,object-type=service --no-headers | wc -l
echo ""

echo "=== FINAL RESULTS ==="
echo "Sequential resource creation completed at: $(date)"

# Final verification
echo "Verifying final resource counts..."

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
echo "Ready for Velero backup testing!"
echo "Expected: 150,000 total objects (50k ConfigMaps + 50k Secrets + 50k Services)"