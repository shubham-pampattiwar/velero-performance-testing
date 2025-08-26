#!/bin/bash

# Script to create ~300k Kubernetes resources for Velero performance testing
# This reproduces the scenario from issue #9169

set -e

NAMESPACE_PREFIX="perf-test"
TOTAL_NAMESPACES=100
RESOURCES_PER_NAMESPACE=3000

echo "Creating $TOTAL_NAMESPACES namespaces with $RESOURCES_PER_NAMESPACE resources each"
echo "Total resources: $((TOTAL_NAMESPACES * RESOURCES_PER_NAMESPACE))"

# Function to create resources in a namespace
create_namespace_resources() {
    local ns=$1
    local count=$2
    
    echo "Creating namespace: $ns"
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create ConfigMaps (lightweight objects)
    echo "Creating ConfigMaps in $ns..."
    for i in $(seq 1 $((count / 3))); do
        kubectl create configmap "config-$i" \
            --from-literal=key1="value$i" \
            --from-literal=key2="data$i" \
            --namespace="$ns" \
            --dry-run=client -o yaml | kubectl apply -f -
    done
    
    # Create Secrets
    echo "Creating Secrets in $ns..."
    for i in $(seq 1 $((count / 3))); do
        kubectl create secret generic "secret-$i" \
            --from-literal=username="user$i" \
            --from-literal=password="pass$i" \
            --namespace="$ns" \
            --dry-run=client -o yaml | kubectl apply -f -
    done
    
    # Create Services
    echo "Creating Services in $ns..."
    for i in $(seq 1 $((count / 3))); do
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: service-$i
  namespace: $ns
spec:
  selector:
    app: app-$i
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF
    done
    
    echo "Completed namespace $ns with $count resources"
}

# Create namespaces and resources in parallel batches
echo "Starting resource creation..."
for batch in $(seq 0 9); do
    start_ns=$((batch * 10 + 1))
    end_ns=$(((batch + 1) * 10))
    
    echo "Processing batch $((batch + 1))/10 (namespaces $start_ns-$end_ns)"
    
    for ns_num in $(seq $start_ns $end_ns); do
        ns_name="${NAMESPACE_PREFIX}-${ns_num}"
        create_namespace_resources "$ns_name" "$RESOURCES_PER_NAMESPACE" &
    done
    
    # Wait for this batch to complete before starting next
    wait
    echo "Batch $((batch + 1)) completed"
done

echo "All resources created successfully!"
echo "Total namespaces: $TOTAL_NAMESPACES"
echo "Total resources: $((TOTAL_NAMESPACES * RESOURCES_PER_NAMESPACE))"

# Verify resource count
echo "Verifying resource counts..."
kubectl get namespaces | grep "$NAMESPACE_PREFIX" | wc -l
kubectl get configmaps --all-namespaces | grep "$NAMESPACE_PREFIX" | wc -l
kubectl get secrets --all-namespaces | grep "$NAMESPACE_PREFIX" | wc -l
kubectl get services --all-namespaces | grep "$NAMESPACE_PREFIX" | wc -l