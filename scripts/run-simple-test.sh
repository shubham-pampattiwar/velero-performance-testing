#!/bin/bash

# Script to create 30k resources using simplified kube-burner config

set -e

CONFIG_FILE="../configs/kube-burner-simple.yaml"
LOG_FILE="kube-burner-simple-$(date +%Y%m%d-%H%M%S).log"

echo "Starting 30k resource creation using simplified kube-burner config"
echo "Config file: $CONFIG_FILE"
echo "Log file: $LOG_FILE"
echo "Start time: $(date)"

# Create namespace first
echo "Creating namespace: velero-perf-test"
kubectl create namespace velero-perf-test --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace velero-perf-test velero-test=performance --overwrite

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
kubectl get configmaps -n velero-perf-test -l velero-test=performance --no-headers | wc -l

echo "Secrets:"
kubectl get secrets -n velero-perf-test -l velero-test=performance --no-headers | wc -l

echo "Services:"
kubectl get services -n velero-perf-test -l velero-test=performance --no-headers | wc -l

echo ""
echo "Total objects in velero-perf-test namespace:"
kubectl get all,configmaps,secrets -n velero-perf-test -l velero-test=performance --no-headers | wc -l

echo ""
echo "Ready for Velero backup testing!"
echo "Next steps:"
echo "1. Install/configure Velero v1.16.2" 
echo "2. Create backup of 'velero-perf-test' namespace"
echo "3. Monitor backup performance and compare with issue expectations"