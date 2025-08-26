#!/bin/bash

# Script to clean up resources created by the simple test (30k objects)
# Removes the velero-perf-test namespace and all its contents

set -e

echo "🧹 Cleaning up simple test resources (30k objects)..."
echo "This will delete the 'velero-perf-test' namespace and all its contents."
echo ""

# Confirm deletion
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo "🔍 Checking for velero-perf-test namespace..."
if kubectl get namespace velero-perf-test >/dev/null 2>&1; then
    echo "📊 Current object counts in velero-perf-test namespace:"
    
    # Show current counts
    echo "  ConfigMaps: $(kubectl get configmaps -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l)"
    echo "  Secrets: $(kubectl get secrets -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l)"
    echo "  Services: $(kubectl get services -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "🗑️  Deleting velero-perf-test namespace..."
    kubectl delete namespace velero-perf-test
    
    echo "⏳ Waiting for namespace deletion to complete..."
    while kubectl get namespace velero-perf-test >/dev/null 2>&1; do
        echo "   Still deleting..."
        sleep 5
    done
    
    echo "✅ Simple test cleanup completed successfully!"
else
    echo "ℹ️  velero-perf-test namespace not found - nothing to clean up."
fi

echo ""
echo "🔍 Verifying cleanup..."
echo "Remaining namespaces with velero-test=performance label:"
kubectl get namespaces -l velero-test=performance --no-headers | wc -l