# Velero Backup Performance Testing

A comprehensive toolkit for testing Velero backup performance with large numbers of Kubernetes objects. This repository provides scripts and configurations to reproduce performance issues and benchmark Velero across different versions.

## 🎯 Use Cases

- **Performance Regression Testing**: Identify performance degradation between Velero versions
- **Scale Testing**: Test backup behavior with large object counts (30k-300k objects)
- **Bottleneck Analysis**: Reproduce scenarios where backup speed slows significantly after initial objects
- **Environment Validation**: Verify Velero performance in different cluster configurations

## ⚡ Why This Approach?

This toolkit uses **[kube-burner](https://github.com/cloud-bulldozer/kube-burner)** - the industry standard for Kubernetes performance testing. Unlike simple kubectl loops or custom scripts, kube-burner provides:

- **2-3 hours** vs 10+ hours for 300k objects
- **Intelligent rate limiting** to prevent API server overwhelming
- **Built-in monitoring** and progress tracking
- **Battle-tested** reliability at enterprise scale

*See the [detailed comparison](#-why-kube-burner) below for alternatives and technical details.*

## 🚀 Quick Start

### Prerequisites
- Kubernetes cluster (OpenShift/OCP supported)
- [kube-burner](https://github.com/cloud-bulldozer/kube-burner) installed
- kubectl configured for your cluster
- Sufficient cluster resources for object creation

### Simple Test (30k objects)
```bash
./scripts/run-simple-test.sh
```

### Large Scale Test (300k objects)
```bash
./scripts/run-large-scale-test.sh
```

## 🚀 Complete Performance Testing Workflow

### 1. Setup Velero
```bash
./velero/install-velero.sh
```

### 2. Create Test Resources
```bash
./scripts/run-simple-test.sh      # 30k objects
# OR
./scripts/run-large-scale-test.sh # 300k objects
```

### 3. Run Backup Performance Test
```bash
./velero/backup-performance-test.sh
```

### 4. Analyze Performance
```bash
./velero/analyze-performance.sh <backup-name>
```

### 5. Test Restore Performance
```bash
./velero/restore-performance-test.sh <backup-name>
```

## 📁 Repository Structure

```
├── configs/                    # Kube-burner configuration files
│   ├── kube-burner-simple.yaml      # 30k objects config
│   └── kube-burner-large-scale.yaml # 300k objects config
├── templates/                  # Kubernetes object templates
│   ├── *-simple-template.yaml       # Single namespace templates
│   └── *-template.yaml             # Multi-namespace templates
├── scripts/                    # Execution scripts
│   ├── run-simple-test.sh          # 30k objects runner
│   ├── run-large-scale-test.sh     # 300k objects runner
│   ├── create-objects-kubectl.sh   # Alternative kubectl approach
│   ├── cleanup-simple.sh           # Clean up 30k objects
│   ├── cleanup-large-scale.sh      # Clean up 300k objects
│   ├── cleanup-all.sh              # Clean up all test resources
│   └── status.sh                   # Check current test status
├── velero/                     # Velero backup/restore scripts
│   ├── install-velero.sh           # Install Velero with multiple providers
│   ├── backup-performance-test.sh  # Run backup performance tests
│   ├── restore-performance-test.sh # Test restore performance
│   └── analyze-performance.sh      # Generate performance analysis
└── docs/                      # Documentation
    ├── USAGE.md                    # Detailed usage guide
    └── VELERO-SETUP.md             # Velero setup and testing guide
```

## 🔧 Configuration Details

### Simple Test (30k objects)
- **Objects**: 10k ConfigMaps + 10k Secrets + 10k Services
- **Namespace**: Single namespace (`velero-perf-test`)
- **QPS/Burst**: 20/50 (cluster-friendly)
- **Duration**: ~5-10 minutes

### Large Scale Test (300k objects)  
- **Objects**: 100k ConfigMaps + 100k Secrets + 100k Services
- **Namespaces**: Multiple namespaces (`velero-perf-test-N`)
- **QPS/Burst**: 20/50 (cluster-friendly)
- **Duration**: ~30-60 minutes

All objects are labeled with `velero-test: "performance"` for easy backup targeting.

## 📊 Status and Verification

### Quick Status Check
```bash
# Check current test status
./scripts/status.sh
```

### Manual Verification Commands
```bash
# Check object counts by type
kubectl get configmaps -n velero-perf-test -l velero-test=performance --no-headers | wc -l
kubectl get secrets -n velero-perf-test -l velero-test=performance --no-headers | wc -l  
kubectl get services -n velero-perf-test -l velero-test=performance --no-headers | wc -l

# Total object count
kubectl get all,configmaps,secrets -n velero-perf-test -l velero-test=performance --no-headers | wc -l

# Check across all namespaces (for large-scale test)
kubectl get all,configmaps,secrets --all-namespaces -l velero-test=performance --no-headers | wc -l
```

## 🎯 Expected Performance Characteristics

Based on performance testing, you should observe:

1. **Initial Fast Phase**: First ~5k objects process quickly
2. **Performance Degradation**: Slowdown to ~3 objects/sec in later phases  
3. **Resource Usage**: Increased CPU (~3.5 cores) and memory (~4.5GB) usage
4. **Time Scaling**: 30k objects: ~5-10 min, 300k objects: ~30-60 min for creation

## 🧹 Cleanup

### Quick Cleanup
```bash
# Remove simple test (30k objects)
./scripts/cleanup-simple.sh

# Remove large-scale test (300k objects) 
./scripts/cleanup-large-scale.sh

# Remove ALL test resources
./scripts/cleanup-all.sh
```

### Manual Cleanup
```bash
# Simple test cleanup
kubectl delete namespace velero-perf-test

# Large scale test cleanup
kubectl delete namespaces -l velero-test=performance
```

## 🔧 Why Kube-burner?

### The Challenge
Creating 300k Kubernetes objects efficiently is not trivial. Traditional approaches have significant limitations:

| Approach | Speed | Concurrency | Monitoring | Cluster Safety |
|----------|--------|-------------|------------|----------------|
| **Sequential kubectl** | 10+ hours | None | Manual | Poor |
| **Parallel kubectl** | 3-4 hours | Basic | Manual | Risk of overwhelming API |
| **Custom scripts** | Variable | Complex to implement | Custom code needed | Depends on implementation |
| **Kube-burner** | 2-3 hours | Smart rate limiting | Built-in | Respects API limits |

### Kube-burner Advantages

- **🚀 Built for Scale**: Specifically designed for large-scale Kubernetes object creation
- **⚡ Intelligent Concurrency**: Handles parallelism with automatic rate limiting and backoff
- **📊 Built-in Monitoring**: Progress tracking, performance metrics, and detailed logging
- **🛡️ Cluster-Safe**: Respects API server limits and implements proper backoff strategies
- **🎯 Template System**: Easy object variation through YAML templates
- **📈 Industry Standard**: Used by Kubernetes performance teams and backup tool vendors
- **🔄 Error Resilience**: Automatic retries and graceful error handling

### Alternative Approaches

**Simple kubectl (Not Recommended)**
```bash
# Would take 10+ hours with no concurrency
for i in {1..300000}; do
  kubectl create configmap "cm-$i" --from-literal=data="test"
done
```

**Parallel kubectl (Limited)**
```bash
# Better but lacks rate limiting and monitoring
seq 1 300000 | xargs -P 10 -I {} kubectl create configmap "cm-{}" --from-literal=data="test"
```

**Custom Implementation**
Creating a custom solution would require implementing:
- Kubernetes client libraries and authentication
- Intelligent rate limiting and backoff
- Comprehensive error handling and retries
- Progress monitoring and logging
- Template rendering system
- Resource cleanup capabilities

This represents hundreds of lines of complex code versus kube-burner's simple YAML configuration.

### For Velero Testing Specifically

- **Realistic Load Patterns**: Creates load similar to real applications
- **Backup Tool Compatible**: Generates standard Kubernetes objects
- **Performance Testing Standard**: Widely used for testing backup solutions
- **Proven at Scale**: Battle-tested in enterprise environments

## 🛠️ Customization

### Modify Object Counts
Edit the `replicas` values in the config files:
```yaml
objects:
  - objectTemplate: configmap-simple-template.yaml
    replicas: 5000  # Reduce for smaller tests
```

### Adjust Performance Settings
Modify QPS and burst limits:
```yaml
qps: 10      # Lower for resource-constrained clusters
burst: 25    # Lower for resource-constrained clusters
```

### Custom Object Templates
Create new templates in the `templates/` directory following the existing pattern.

## 📚 Documentation

- **[Velero Setup Guide](docs/VELERO-SETUP.md)** - Complete Velero installation and testing guide
- **[Detailed Usage Guide](docs/USAGE.md)** - Comprehensive usage instructions
- **[Kube-burner Documentation](https://github.com/cloud-bulldozer/kube-burner)** - Object creation tool
- **[Velero Documentation](https://velero.io/docs/)** - Official Velero documentation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with both simple and large-scale configurations
5. Submit a pull request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🔗 Related Resources

- [Velero GitHub Repository](https://github.com/vmware-tanzu/velero)
- [Kube-burner GitHub Repository](https://github.com/cloud-bulldozer/kube-burner)
- [Kubernetes Performance Testing](https://kubernetes.io/docs/concepts/cluster-administration/system-logs/)

---

**Note**: This toolkit is designed for testing and development environments. Use caution when running large-scale tests in production clusters.