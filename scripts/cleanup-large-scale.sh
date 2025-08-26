#!/bin/bash

# Script to clean up resources created by the large-scale test (300k objects)
# Removes all namespaces with velero-test=performance label

set -e

echo "🧹 Cleaning up large-scale test resources (300k objects)..."
echo "This will delete ALL namespaces with label 'velero-test=performance'."
echo ""

# Check what will be deleted
echo "🔍 Finding namespaces to delete..."
NAMESPACES=$(kubectl get namespaces -l velero-test=performance --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

if [ -z "$NAMESPACES" ]; then
    echo "ℹ️  No namespaces found with velero-test=performance label."
    echo "✅ Nothing to clean up!"
    exit 0
fi

echo "📋 Namespaces that will be deleted:"
echo "$NAMESPACES" | sed 's/^/  - /'
echo ""

# Count objects across all namespaces
echo "📊 Current object counts across all performance test namespaces:"
TOTAL_CONFIGMAPS=0
TOTAL_SECRETS=0
TOTAL_SERVICES=0

for ns in $NAMESPACES; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        CM_COUNT=$(kubectl get configmaps -n "$ns" -l velero-test=performance --no-headers 2>/dev/null | wc -l)
        SECRET_COUNT=$(kubectl get secrets -n "$ns" -l velero-test=performance --no-headers 2>/dev/null | wc -l)
        SERVICE_COUNT=$(kubectl get services -n "$ns" -l velero-test=performance --no-headers 2>/dev/null | wc -l)
        
        TOTAL_CONFIGMAPS=$((TOTAL_CONFIGMAPS + CM_COUNT))
        TOTAL_SECRETS=$((TOTAL_SECRETS + SECRET_COUNT))
        TOTAL_SERVICES=$((TOTAL_SERVICES + SERVICE_COUNT))
        
        echo "  $ns: ${CM_COUNT} ConfigMaps, ${SECRET_COUNT} Secrets, ${SERVICE_COUNT} Services"
    fi
done

echo ""
echo "📈 Total objects to be deleted:"
echo "  ConfigMaps: $TOTAL_CONFIGMAPS"
echo "  Secrets: $TOTAL_SECRETS"
echo "  Services: $TOTAL_SERVICES"
echo "  Total: $((TOTAL_CONFIGMAPS + TOTAL_SECRETS + TOTAL_SERVICES))"
echo ""

# Confirm deletion
read -p "Are you sure you want to delete all these resources? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo "🗑️  Starting namespace deletion..."

# Delete namespaces in parallel for faster cleanup
for ns in $NAMESPACES; do
    echo "  Deleting $ns..."
    kubectl delete namespace "$ns" --ignore-not-found=true &
done

echo "⏳ Waiting for all namespaces to be deleted..."

# Wait for all deletions to complete
for ns in $NAMESPACES; do
    while kubectl get namespace "$ns" >/dev/null 2>&1; do
        sleep 2
    done
    echo "  ✓ $ns deleted"
done

echo ""
echo "✅ Large-scale test cleanup completed successfully!"
echo ""
echo "🔍 Verifying cleanup..."
REMAINING=$(kubectl get namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
echo "Remaining namespaces with velero-test=performance label: $REMAINING"

if [ "$REMAINING" -eq 0 ]; then
    echo "🎉 All performance test resources successfully removed!"
else
    echo "⚠️  Some namespaces may still be terminating. Run this script again if needed."
fi