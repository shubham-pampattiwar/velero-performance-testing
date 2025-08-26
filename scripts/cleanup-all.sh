#!/bin/bash

# Script to clean up ALL performance testing resources
# This removes everything created by both simple and large-scale tests

set -e

echo "🧹 Cleaning up ALL Velero performance testing resources..."
echo "This will delete:"
echo "  - velero-perf-test namespace (simple test)"
echo "  - All namespaces with velero-test=performance label (large-scale test)"
echo "  - Any orphaned resources with velero-test=performance label"
echo ""

# Show what will be deleted
echo "🔍 Scanning for performance test resources..."

# Check for simple test namespace
SIMPLE_NS_EXISTS=false
if kubectl get namespace velero-perf-test >/dev/null 2>&1; then
    SIMPLE_NS_EXISTS=true
    echo "📋 Found simple test namespace: velero-perf-test"
fi

# Check for large-scale test namespaces
LARGE_SCALE_NAMESPACES=$(kubectl get namespaces -l velero-test=performance --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
if [ -n "$LARGE_SCALE_NAMESPACES" ]; then
    echo "📋 Found large-scale test namespaces:"
    echo "$LARGE_SCALE_NAMESPACES" | sed 's/^/  - /'
fi

# Check for any orphaned resources
echo ""
echo "🔍 Checking for orphaned resources..."
ORPHANED_CM=$(kubectl get configmaps --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
ORPHANED_SECRETS=$(kubectl get secrets --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
ORPHANED_SERVICES=$(kubectl get services --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)

echo "📊 Total resources found:"
echo "  ConfigMaps: $ORPHANED_CM"
echo "  Secrets: $ORPHANED_SECRETS" 
echo "  Services: $ORPHANED_SERVICES"
echo "  Total: $((ORPHANED_CM + ORPHANED_SECRETS + ORPHANED_SERVICES))"

if [ "$ORPHANED_CM" -eq 0 ] && [ "$ORPHANED_SECRETS" -eq 0 ] && [ "$ORPHANED_SERVICES" -eq 0 ]; then
    echo "ℹ️  No performance test resources found - nothing to clean up!"
    exit 0
fi

echo ""
# Confirm deletion
read -p "Are you sure you want to delete all performance test resources? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo "🗑️  Starting comprehensive cleanup..."

# Method 1: Delete by namespace labels (most efficient)
echo "  Phase 1: Deleting namespaces with velero-test=performance label..."
kubectl delete namespaces -l velero-test=performance --ignore-not-found=true --timeout=300s &

# Method 2: Delete simple test namespace specifically
if [ "$SIMPLE_NS_EXISTS" = true ]; then
    echo "  Phase 2: Deleting velero-perf-test namespace..."
    kubectl delete namespace velero-perf-test --ignore-not-found=true --timeout=300s &
fi

# Wait for namespace deletions
wait

echo "⏳ Waiting for namespace deletions to complete..."
sleep 5

# Method 3: Clean up any remaining orphaned resources
echo "  Phase 3: Cleaning up any remaining orphaned resources..."

# Delete orphaned resources by label across all namespaces
kubectl delete configmaps -l velero-test=performance --all-namespaces --ignore-not-found=true &
kubectl delete secrets -l velero-test=performance --all-namespaces --ignore-not-found=true &
kubectl delete services -l velero-test=performance --all-namespaces --ignore-not-found=true &

# Wait for resource deletions
wait

echo ""
echo "✅ Comprehensive cleanup completed!"
echo ""
echo "🔍 Final verification..."
REMAINING_NS=$(kubectl get namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
REMAINING_CM=$(kubectl get configmaps --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
REMAINING_SECRETS=$(kubectl get secrets --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
REMAINING_SERVICES=$(kubectl get services --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)

echo "Remaining resources:"
echo "  Namespaces: $REMAINING_NS"
echo "  ConfigMaps: $REMAINING_CM"
echo "  Secrets: $REMAINING_SECRETS"
echo "  Services: $REMAINING_SERVICES"

TOTAL_REMAINING=$((REMAINING_NS + REMAINING_CM + REMAINING_SECRETS + REMAINING_SERVICES))
if [ "$TOTAL_REMAINING" -eq 0 ]; then
    echo ""
    echo "🎉 All Velero performance test resources successfully removed!"
    echo "Your cluster is now clean and ready for new tests."
else
    echo ""
    echo "⚠️  Some resources may still be terminating."
    echo "If resources persist, check for finalizers or re-run this script."
fi

echo ""
echo "💡 Ready to run new tests:"
echo "  ./scripts/run-simple-test.sh      # 30k objects"
echo "  ./scripts/run-large-scale-test.sh # 300k objects"