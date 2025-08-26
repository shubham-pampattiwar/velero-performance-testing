# Detailed Usage Guide

This guide provides comprehensive instructions for using the Velero Performance Testing toolkit.

## Prerequisites Setup

### 1. Install kube-burner

**macOS:**
```bash
brew install kube-burner
```

**Linux:**
```bash
curl -L https://github.com/cloud-bulldozer/kube-burner/releases/latest/download/kube-burner-linux-x86_64.tar.gz | tar xz
sudo mv kube-burner /usr/local/bin/
```

**Verify installation:**
```bash
kube-burner version
```

### 2. Cluster Requirements

**Minimum Resources:**
- **Simple Test (30k objects)**: 2 CPU cores, 4GB RAM, 10GB storage
- **Large Scale Test (300k objects)**: 8 CPU cores, 16GB RAM, 50GB storage

**Recommended Resources:**
- **Simple Test**: 4 CPU cores, 8GB RAM
- **Large Scale Test**: 16 CPU cores, 32GB RAM

### 3. Permissions

Ensure your kubectl context has cluster-admin privileges:
```bash
kubectl auth can-i create namespaces
kubectl auth can-i create configmaps
kubectl auth can-i create secrets
kubectl auth can-i create services
```

## Running Tests

### Simple Test Workflow

1. **Navigate to scripts directory:**
   ```bash
   cd scripts
   ```

2. **Run the test:**
   ```bash
   ./run-simple-test.sh
   ```

3. **Monitor progress:**
   ```bash
   # In another terminal
   watch "kubectl get all,configmaps,secrets -n velero-perf-test -l velero-test=performance --no-headers | wc -l"
   ```

4. **Verify completion:**
   ```bash
   kubectl get configmaps -n velero-perf-test -l velero-test=performance --no-headers | wc -l
   # Should output: 10000
   
   kubectl get secrets -n velero-perf-test -l velero-test=performance --no-headers | wc -l  
   # Should output: 10000
   
   kubectl get services -n velero-perf-test -l velero-test=performance --no-headers | wc -l
   # Should output: 10000
   ```

### Large Scale Test Workflow

1. **Prepare cluster:**
   ```bash
   # Ensure sufficient resources
   kubectl top nodes
   kubectl describe nodes | grep -A 5 "Allocated resources"
   ```

2. **Run the test:**
   ```bash
   cd scripts
   ./run-large-scale-test.sh
   ```

3. **Monitor resource usage:**
   ```bash
   # Monitor node resources
   watch kubectl top nodes
   
   # Monitor object creation
   watch "kubectl get namespaces -l velero-test=performance --no-headers | wc -l"
   ```

4. **Track progress by namespace:**
   ```bash
   kubectl get namespaces -l velero-test=performance
   for ns in $(kubectl get namespaces -l velero-test=performance --no-headers | awk '{print $1}'); do
     echo "Namespace: $ns"
     kubectl get all,configmaps,secrets -n $ns -l velero-test=performance --no-headers | wc -l
   done
   ```

## Troubleshooting

### Common Issues

#### 1. Resource Limits
**Symptom:** Objects fail to create with "resource quota exceeded" or similar errors.

**Solution:**
```bash
# Check cluster resources
kubectl describe nodes
kubectl top nodes

# Reduce QPS/burst in config files
# Edit configs/kube-burner-simple.yaml:
qps: 10
burst: 20
```

#### 2. Permission Errors
**Symptom:** "forbidden" or "unauthorized" errors.

**Solution:**
```bash
# Check permissions
kubectl auth can-i "*" "*" --all-namespaces

# Use cluster-admin role if needed
kubectl create clusterrolebinding test-admin --clusterrole=cluster-admin --user=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.user}')
```

#### 3. Namespace Creation Failures
**Symptom:** Templates fail with "namespace not found" errors.

**Solution:**
```bash
# Manually create namespaces for large-scale test
for i in {0..9}; do
  kubectl create namespace velero-perf-test-$i
  kubectl label namespace velero-perf-test-$i velero-test=performance
done
```

#### 4. Slow Object Creation
**Symptom:** Object creation is extremely slow.

**Solution:**
```bash
# Check API server responsiveness
kubectl get --raw="/healthz"

# Reduce concurrency
# Edit config files to lower QPS:
qps: 5
burst: 10
```

### Cleanup Issues

#### Stuck Namespaces
**Symptom:** Namespaces remain in "Terminating" state.

**Solution:**
```bash
# Force cleanup (use with caution)
kubectl get namespaces -l velero-test=performance -o json | jq '.items[] | select(.status.phase=="Terminating") | .metadata.name' -r | xargs -I {} kubectl patch namespace {} -p '{"metadata":{"finalizers":[]}}' --type=merge
```

#### Resource Leaks
**Symptom:** Objects remain after namespace deletion.

**Solution:**
```bash
# Clean up by label across all namespaces
kubectl delete configmaps -l velero-test=performance --all-namespaces
kubectl delete secrets -l velero-test=performance --all-namespaces  
kubectl delete services -l velero-test=performance --all-namespaces
```

## Performance Analysis

### Measuring Creation Speed

```bash
# Start timing
start_time=$(date +%s)

# Run test
./run-simple-test.sh

# Calculate duration
end_time=$(date +%s)
duration=$((end_time - start_time))
echo "Creation took $duration seconds"

# Calculate rate
total_objects=30000
rate=$((total_objects / duration))
echo "Creation rate: $rate objects/second"
```

### Resource Monitoring

```bash
# Monitor during test execution
kubectl top nodes
kubectl top pods -n velero-perf-test

# Check API server metrics
kubectl get --raw="/metrics" | grep apiserver_request_duration_seconds

# Monitor etcd performance (if accessible)
kubectl get --raw="/metrics" | grep etcd_request_duration_seconds
```

## Advanced Configuration

### Custom Object Templates

Create new templates in `templates/` directory:

```yaml
# templates/custom-template.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-{{.Replica}}
  namespace: {{.Namespace}}
  labels:
    velero-test: "performance"
    custom-type: "example"
data:
  replica: "{{.Replica}}"
  custom-data: "your-custom-data-here"
```

Update config to use custom template:
```yaml
objects:
  - objectTemplate: custom-template.yaml
    replicas: 1000
```

### Multi-Cluster Testing

Run tests across multiple clusters:

```bash
# Cluster 1
kubectl config use-context cluster1
./run-simple-test.sh

# Cluster 2  
kubectl config use-context cluster2
./run-simple-test.sh

# Compare results
```

## Integration with Velero

### Creating Backups

After object creation, test Velero backup performance:

```bash
# Install Velero (example with AWS)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket my-backup-bucket \
  --secret-file ./credentials-velero

# Create backup
velero backup create perf-test-backup \
  --include-namespaces velero-perf-test \
  --wait

# Monitor backup progress
velero backup describe perf-test-backup
velero backup logs perf-test-backup
```

### Performance Metrics

```bash
# Check backup duration
velero backup get perf-test-backup -o json | jq '.status.phase, .status.startTimestamp, .status.completionTimestamp'

# Check backup size
velero backup describe perf-test-backup | grep "Backup Size"

# Monitor backup speed
velero backup logs perf-test-backup | grep -i "progress\|rate\|objects"
```

This guide should help you effectively use the performance testing toolkit. For additional support, please refer to the main README or open an issue in the repository.