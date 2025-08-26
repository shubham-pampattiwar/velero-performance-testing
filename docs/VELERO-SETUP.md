# Velero Setup and Performance Testing Guide

This guide provides comprehensive instructions for setting up Velero and running performance tests to reproduce backup performance issues.

## Prerequisites

### Velero CLI Installation

**macOS:**
```bash
brew install velero
```

**Linux:**
```bash
# Download latest release
VELERO_VERSION="v1.16.2"
wget https://github.com/vmware-tanzu/velero/releases/download/$VELERO_VERSION/velero-$VELERO_VERSION-linux-amd64.tar.gz
tar -xvf velero-$VELERO_VERSION-linux-amd64.tar.gz
sudo mv velero-$VELERO_VERSION-linux-amd64/velero /usr/local/bin/
```

**Verify Installation:**
```bash
velero version --client-only
```

## Velero Server Installation

### Automated Installation

Use our installation script for quick setup:

```bash
./velero/install-velero.sh
```

This script supports:
- AWS S3
- Google Cloud Storage
- Azure Blob Storage
- MinIO (for local testing)

### Manual Installation Examples

#### AWS S3
```bash
# Create S3 bucket and IAM user first
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.16.2 \
    --bucket my-velero-backups \
    --secret-file ./aws-credentials \
    --backup-location-config region=us-west-2 \
    --snapshot-location-config region=us-west-2
```

#### Google Cloud Storage
```bash
# Create GCS bucket and service account first
velero install \
    --provider gcp \
    --plugins velero/velero-plugin-for-gcp:v1.16.2 \
    --bucket my-velero-backups \
    --secret-file ./gcp-service-account.json
```

#### MinIO (Local Testing)
```bash
# Install MinIO in cluster first
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.16.2 \
    --bucket velero-backups \
    --secret-file ./minio-credentials \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.minio.svc.cluster.local:9000
```

## Performance Testing Workflow

### Step 1: Create Test Resources

**Small Scale Test (30k objects):**
```bash
./scripts/run-simple-test.sh
```

**Large Scale Test (300k objects):**
```bash
./scripts/run-large-scale-test.sh
```

### Step 2: Run Backup Performance Test

```bash
./velero/backup-performance-test.sh
```

This script will:
- Detect available test resources
- Allow selection of backup scope
- Monitor backup progress in real-time
- Calculate performance metrics
- Generate detailed logs

### Step 3: Analyze Performance

```bash
./velero/analyze-performance.sh <backup-name>
```

Generates comprehensive performance analysis including:
- Performance benchmarks
- Issue correlation
- Optimization recommendations
- Testing matrix

### Step 4: Test Restore Performance

```bash
./velero/restore-performance-test.sh <backup-name>
```

Options include:
- Full restore
- Namespace restore
- Selective restore with filters

## Expected Performance Characteristics

### Normal Performance (v1.11.1)
- **Rate**: 50+ objects/second
- **Duration**: ~30 minutes for 300k objects
- **Resource Usage**: ~1 CPU core, ~3GB memory

### Degraded Performance (v1.16.2 issue)
- **Initial Phase**: Fast processing (~5k objects)
- **Degraded Phase**: ~3 objects/second
- **Duration**: ~6 hours for 300k objects
- **Resource Usage**: ~3.5 CPU cores, ~4.5GB memory

### Performance Levels

| Level | Rate (obj/sec) | Status | Action |
|-------|----------------|--------|---------|
| 🚀 Excellent | > 50 | Normal operation | Continue monitoring |
| ⚡ Good | 21-50 | Acceptable | Minor optimization |
| ⚠️ Moderate | 6-20 | Below optimal | Investigation needed |
| 🐌 Slow | < 5 | **Issue reproduction** | Version/config analysis |

## Troubleshooting

### Common Issues

**1. Velero Server Not Starting**
```bash
# Check pod status
kubectl get pods -n velero

# Check logs
kubectl logs deployment/velero -n velero

# Verify backup location
velero backup-location get
```

**2. Backup Failures**
```bash
# Check backup status
velero backup describe <backup-name>

# View backup logs
velero backup logs <backup-name>

# Check storage connectivity
kubectl get backupstoragelocations -n velero
```

**3. Performance Issues**
```bash
# Monitor cluster resources
kubectl top nodes
kubectl top pods -n velero

# Check API server metrics
kubectl get --raw="/metrics" | grep apiserver_request_duration

# Review client-side throttling
# Look for "Waited for X due to client-side throttling" in logs
```

### Configuration Tuning

**Velero Resource Limits:**
```yaml
# Increase Velero pod resources
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 4000m
    memory: 8Gi
```

**Client QPS/Burst Settings:**
```bash
# Velero deployment environment variables
env:
- name: VELERO_CLIENT_QPS
  value: "30"
- name: VELERO_CLIENT_BURST
  value: "40"
```

**Backup Worker Configuration:**
```bash
# Adjust concurrent backup workers
velero server --backup-sync-period=60s --pod-volume-operation-timeout=240m
```

## Monitoring and Metrics

### Built-in Monitoring

```bash
# Backup status
velero backup get

# Resource usage
kubectl top pods -n velero

# API server load
kubectl get --raw="/metrics" | grep apiserver

# Storage throughput
# Monitor storage provider metrics
```

### Custom Dashboards

Monitor these key metrics:
- Backup duration trends
- Objects processed per second
- API server request latency
- Storage I/O throughput
- Velero pod resource usage

## Testing Matrix

### Recommended Test Scenarios

1. **Baseline Test**: 1k objects for functionality verification
2. **Small Scale**: 10k objects for basic performance
3. **Medium Scale**: 30k objects for moderate load
4. **Large Scale**: 300k objects for issue reproduction
5. **Concurrent Load**: 300k objects + cluster activity

### Version Comparison

Test the same workload across different Velero versions:

```bash
# Test with v1.11.1 (baseline)
# Test with v1.16.2 (reported issue)
# Test with latest version
```

## Security Considerations

### Backup Storage Access
- Use IAM roles/service accounts instead of static credentials
- Implement backup encryption at rest
- Restrict backup storage access

### Cluster Permissions
- Review Velero RBAC permissions
- Use namespace-scoped installations where possible
- Implement network policies for Velero pods

### Data Privacy
- Consider data residency requirements
- Implement backup retention policies
- Use encryption for sensitive workloads

## Integration with CI/CD

### Automated Performance Testing

```bash
# Example pipeline step
./scripts/run-simple-test.sh
./velero/backup-performance-test.sh
./velero/analyze-performance.sh backup-name
./scripts/cleanup-simple.sh
```

### Performance Regression Detection

Set up automated alerts when:
- Backup duration exceeds thresholds
- Object processing rate drops below baseline
- Error/warning counts increase

---

For additional support or questions, refer to:
- [Velero Documentation](https://velero.io/docs/)
- [Performance Testing Repository](../README.md)
- [Issue Troubleshooting](../docs/USAGE.md)