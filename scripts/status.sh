#!/bin/bash

# Script to check the status of Velero performance testing resources
# Shows current object counts and resource usage

set -e

echo "📊 Velero Performance Testing - Resource Status"
echo "============================================="
echo ""

# Check for simple test namespace
echo "🔍 Simple Test Status (velero-perf-test namespace):"
if kubectl get namespace velero-perf-test >/dev/null 2>&1; then
    echo "  ✅ Namespace: velero-perf-test (exists)"
    
    CM_COUNT=$(kubectl get configmaps -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l)
    SECRET_COUNT=$(kubectl get secrets -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l)
    SERVICE_COUNT=$(kubectl get services -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l)
    
    echo "  📈 Object counts:"
    echo "    ConfigMaps: $CM_COUNT"
    echo "    Secrets: $SECRET_COUNT"
    echo "    Services: $SERVICE_COUNT"
    echo "    Total: $((CM_COUNT + SECRET_COUNT + SERVICE_COUNT))"
else
    echo "  ❌ Namespace: velero-perf-test (not found)"
fi

echo ""

# Check for large-scale test namespaces
echo "🔍 Large-Scale Test Status (velero-test=performance namespaces):"
NAMESPACES=$(kubectl get namespaces -l velero-test=performance --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

if [ -z "$NAMESPACES" ]; then
    echo "  ❌ No large-scale test namespaces found"
else
    echo "  ✅ Found $(echo "$NAMESPACES" | wc -l) namespace(s):"
    
    TOTAL_CM=0
    TOTAL_SECRETS=0
    TOTAL_SERVICES=0
    
    for ns in $NAMESPACES; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            CM_COUNT=$(kubectl get configmaps -n "$ns" -l velero-test=performance --no-headers 2>/dev/null | wc -l)
            SECRET_COUNT=$(kubectl get secrets -n "$ns" -l velero-test=performance --no-headers 2>/dev/null | wc -l)
            SERVICE_COUNT=$(kubectl get services -n "$ns" -l velero-test=performance --no-headers 2>/dev/null | wc -l)
            
            TOTAL_CM=$((TOTAL_CM + CM_COUNT))
            TOTAL_SECRETS=$((TOTAL_SECRETS + SECRET_COUNT))
            TOTAL_SERVICES=$((TOTAL_SERVICES + SERVICE_COUNT))
            
            echo "    $ns: ${CM_COUNT} CM, ${SECRET_COUNT} secrets, ${SERVICE_COUNT} services"
        fi
    done
    
    echo ""
    echo "  📈 Large-scale totals:"
    echo "    ConfigMaps: $TOTAL_CM"
    echo "    Secrets: $TOTAL_SECRETS"
    echo "    Services: $TOTAL_SERVICES"
    echo "    Total: $((TOTAL_CM + TOTAL_SECRETS + TOTAL_SERVICES))"
fi

echo ""

# Overall summary
echo "📊 Overall Summary:"
ALL_CM=$(kubectl get configmaps --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
ALL_SECRETS=$(kubectl get secrets --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
ALL_SERVICES=$(kubectl get services --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)
ALL_NS=$(kubectl get namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l)

echo "  Total namespaces: $ALL_NS"
echo "  Total ConfigMaps: $ALL_CM"
echo "  Total Secrets: $ALL_SECRETS"
echo "  Total Services: $ALL_SERVICES"
echo "  Grand Total Objects: $((ALL_CM + ALL_SECRETS + ALL_SERVICES))"

echo ""

# Resource recommendations
TOTAL_OBJECTS=$((ALL_CM + ALL_SECRETS + ALL_SERVICES))
if [ "$TOTAL_OBJECTS" -eq 0 ]; then
    echo "💡 Recommendations:"
    echo "  No test resources found. Ready to run performance tests:"
    echo "    ./scripts/run-simple-test.sh      # Create 30k objects"
    echo "    ./scripts/run-large-scale-test.sh # Create 300k objects"
elif [ "$TOTAL_OBJECTS" -lt 50000 ]; then
    echo "💡 Recommendations:"
    echo "  Small-scale test detected. Consider:"
    echo "    ./scripts/run-large-scale-test.sh # Scale up to 300k objects"
    echo "    velero backup create test --include-namespaces velero-perf-test"
else
    echo "💡 Recommendations:"
    echo "  Large-scale test ready. Try Velero backup:"
    echo "    velero backup create perf-test --selector velero-test=performance"
fi

echo ""
echo "🧹 Cleanup options:"
echo "  ./scripts/cleanup-simple.sh      # Remove simple test only"
echo "  ./scripts/cleanup-large-scale.sh # Remove large-scale test only"
echo "  ./scripts/cleanup-all.sh         # Remove all test resources"