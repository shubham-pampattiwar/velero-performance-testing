# Velero Backup Performance Testing

A comprehensive toolkit for testing Velero backup performance with large numbers of Kubernetes objects. This repository provides scripts and configurations to reproduce performance issues and benchmark Velero across different versions.

## 🎯 Use Cases

- **Performance Regression Testing**: Identify performance degradation between Velero versions
- **Scale Testing**: Test backup behavior with large object counts (30k-300k objects)
- **Bottleneck Analysis**: Reproduce scenarios where backup speed slows significantly after initial objects
- **Environment Validation**: Verify Velero performance in different cluster configurations

## 🚀 Quick Start

### Prerequisites
- Kubernetes cluster (OpenShift/OCP supported)
- [kube-burner](https://github.com/cloud-bulldozer/kube-burner) installed
- kubectl configured for your cluster
- Sufficient cluster resources for object creation

### Simple Test (30k objects)
```bash
cd scripts
./run-simple-test.sh
```

### Large Scale Test (300k objects)
```bash
cd scripts  
./run-large-scale-test.sh
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
│   └── create-objects-kubectl.sh   # Alternative kubectl approach
└── docs/                      # Documentation
    └── USAGE.md               # Detailed usage guide
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

## 📊 Verification Commands

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

```bash
# Simple test cleanup
kubectl delete namespace velero-perf-test

# Large scale test cleanup  
kubectl get namespaces -l velero-test=performance --no-headers | awk '{print $1}' | xargs kubectl delete namespace

# Alternative: Delete by label
kubectl delete namespaces -l velero-test=performance
```

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

- [Detailed Usage Guide](docs/USAGE.md)
- [Kube-burner Documentation](https://github.com/cloud-bulldozer/kube-burner)
- [Velero Documentation](https://velero.io/docs/)

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