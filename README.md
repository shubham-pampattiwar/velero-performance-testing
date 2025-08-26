# Velero Backup Performance Testing 🏎️💨

*Because waiting 6 hours for a backup is nobody's idea of fun!* 😅

A comprehensive (and surprisingly entertaining) toolkit for testing Velero backup performance with large numbers of Kubernetes objects. This repository provides scripts and configurations to reproduce performance issues and benchmark Velero across different versions — because sometimes you need to break things systematically to understand why they're already broken! 🤷‍♂️

## 🎯 Use Cases

- **Performance Regression Testing**: Catch Velero when it's having a "slow day" 🐌
- **Scale Testing**: See how many objects you can throw at Velero before it starts crying (30k-300k objects)
- **Bottleneck Analysis**: Find out why your backup went from "zoom zoom" to "zzz..." 😴
- **Environment Validation**: Make sure Velero performs consistently across clusters (or find out which cluster is the troublemaker)

## ⚡ Why This Approach?

This toolkit uses **[kube-burner](https://github.com/kube-burner/kube-burner)** - the Chuck Norris of Kubernetes performance testing tools! 💪 Unlike simple kubectl loops (which are about as efficient as using a spoon to dig a tunnel), kube-burner provides:

- **2-3 hours** vs 10+ hours for 300k objects *(because life's too short for inefficient scripts)*
- **Intelligent rate limiting** to prevent your API server from having an existential crisis 😰
- **Built-in monitoring** and progress tracking *(so you can watch the magic happen)*
- **Battle-tested** reliability at enterprise scale *(it's seen things... terrible, scalable things)*

*See the [detailed comparison](#-why-kube-burner) below for alternatives and why they make us sad. 😢*

## 🚀 Quick Start

### Prerequisites *(aka "The Boring But Important Stuff")*
- Kubernetes cluster (OpenShift/OCP supported) — *hopefully one that's not held together with duct tape* 🩹
- [kube-burner](https://github.com/kube-burner/kube-burner) installed — *your new best friend*
- kubectl configured for your cluster — *and hopefully pointing to the right one* 😅
- Sufficient cluster resources for object creation — *translation: don't run this on your laptop cluster with 2GB RAM*

### Simple Test (30k objects) — *"The Gentle Introduction"*
```bash
./scripts/run-simple-test.sh
```
*Perfect for when you want to dip your toes in the performance testing waters without flooding your cluster.*

### Large Scale Test (300k objects) — *"The Beast Mode"*
```bash
./scripts/run-large-scale-test.sh
```
*Warning: This is where things get spicy! 🌶️ Make sure your cluster has had its coffee first.*

**💡 Expected Behavior:** You'll see lots of throttling logs like:
```
Waited for 8.474643292s due to client-side throttling, not priority and fairness
```
**This is totally normal and good!** It means kube-burner is protecting your API server from overload. *(Don't panic, it's a feature, not a bug!)* ✨

## 🚀 Complete Performance Testing Workflow *(The Full Monty)*

### 1. Setup Velero — *"Getting the Band Together"*
```bash
./velero/install-velero.sh
```
*This script supports more cloud providers than a frequent flyer's credit card collection.*

### 2. Create Test Resources — *"Summoning the Object Army"*
```bash
./scripts/run-simple-test.sh      # 30k objects (the warm-up)
# OR
./scripts/run-large-scale-test.sh # 300k objects (the main event)
```
*Grab some coffee ☕, this might take a while. Or binge-watch a show. We don't judge.*

### 3. Run Backup Performance Test — *"The Moment of Truth"*
```bash
./velero/backup-performance-test.sh
```
*Where we find out if Velero is having a good day or needs a performance review.*

### 4. Analyze Performance — *"CSI: Kubernetes"*
```bash
./velero/analyze-performance.sh <backup-name>
```
*Time to put on your detective hat 🕵️ and figure out what happened.*

### 5. Test Restore Performance — *"The Plot Twist"*
```bash
./velero/restore-performance-test.sh <backup-name>
```
*Because sometimes the restore is faster than the backup, and that's just confusing.*

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

## 🔧 Configuration Details *(The Technical Stuff That Actually Matters)*

### Simple Test (30k objects) — *"Training Wheels Mode"*
- **Objects**: 10k ConfigMaps + 10k Secrets + 10k Services *(a nice, balanced breakfast of objects)*
- **Namespace**: Single namespace (`velero-perf-test`) *(keeping it simple, like Sunday morning)*
- **QPS/Burst**: 20/50 *(polite enough not to anger your API server)*
- **Duration**: ~5-10 minutes *(perfect for a coffee break)*

### Large Scale Test (300k objects) — *"Hold My Beer Mode"* 🍺
- **Objects**: 100k ConfigMaps + 100k Secrets + 100k Services *(aka "the object avalanche")*
- **Namespaces**: Multiple namespaces (`velero-perf-test-N`) *(spreading the chaos evenly)*
- **QPS/Burst**: 20/50 *(still being respectful, even at scale)*
- **Duration**: ~30-60 minutes *(enough time to question your life choices)*

All objects are labeled with `velero-test: "performance"` for easy backup targeting. *(Because finding needles in haystacks is so last century.)*

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

## 🎯 Expected Performance Characteristics *(What to Expect When You're Expecting... Objects)*

Based on performance testing, you should observe the following dramatic performance theater:

1. **Initial Fast Phase**: First ~5k objects process quickly *(Velero's enthusiastic "I got this!" phase)* 🚀
2. **Performance Degradation**: Slowdown to ~3 objects/sec in later phases *(aka "the reality check")* 🐌  
3. **Resource Usage**: Increased CPU (~3.5 cores) and memory (~4.5GB) usage *(your cluster working overtime)*
4. **Time Scaling**: 30k objects: ~5-10 min, 300k objects: ~30-60 min for creation *(patience is a virtue)*

*If you don't see this pattern, either you've discovered a miracle or something's broken. We're betting on the latter.* 🤞

## 🧹 Cleanup *(aka "Covering Your Tracks")*

### Quick Cleanup — *"The Magic Eraser"*
```bash
# Remove simple test (30k objects)
./scripts/cleanup-simple.sh

# Remove large-scale test (300k objects) 
./scripts/cleanup-large-scale.sh

# Remove ALL test resources (the nuclear option)
./scripts/cleanup-all.sh
```
*Because nobody likes a messy cluster. It's like leaving dirty dishes in the sink, but worse.* 🧽

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

### Kube-burner Advantages *(Why We're Head-Over-Heels for This Tool)*

- **🚀 Built for Scale**: Specifically designed for large-scale Kubernetes object creation *(unlike that script you wrote at 2 AM)*
- **⚡ Intelligent Concurrency**: Handles parallelism with automatic rate limiting and backoff *(smarter than your average bear)*
- **📊 Built-in Monitoring**: Progress tracking, performance metrics, and detailed logging *(it's like having a personal fitness tracker for your cluster)*
- **🛡️ Cluster-Safe**: Respects API server limits and implements proper backoff strategies *(won't accidentally DDoS your own cluster)*
- **🎯 Template System**: Easy object variation through YAML templates *(because copy-paste is so last decade)*
- **📈 Industry Standard**: Used by Kubernetes performance teams and backup tool vendors *(if it's good enough for the pros...)*
- **🔄 Error Resilience**: Automatic retries and graceful error handling *(bounces back like a rubber ball)*

### Alternative Approaches *(The Hall of Shame)*

**Simple kubectl (Not Recommended)** — *"The Scenic Route"*
```bash
# Would take 10+ hours with no concurrency
# Perfect if you enjoy watching paint dry
for i in {1..300000}; do
  kubectl create configmap "cm-$i" --from-literal=data="test"
done
```
*Pro tip: Don't do this unless you have 10+ hours to kill and a strong coffee supply.* ☕😴

**Parallel kubectl (Limited)** — *"Better, But Still Painful"*
```bash
# Better but lacks rate limiting and monitoring
# Like using a hammer when you need a precision tool
seq 1 300000 | xargs -P 10 -I {} kubectl create configmap "cm-{}" --from-literal=data="test"
```
*It'll work, but your API server might need therapy afterward.* 😵

**Custom Implementation** — *"The Masochist's Choice"*
Creating a custom solution would require implementing:
- Kubernetes client libraries and authentication *(reinventing the wheel)*
- Intelligent rate limiting and backoff *(good luck with that)*
- Comprehensive error handling and retries *(prepare for edge case hell)*
- Progress monitoring and logging *(because you love building dashboards, right?)*
- Template rendering system *(YAML templating from scratch, anyone?)*
- Resource cleanup capabilities *(don't forget to clean up after yourself)*

This represents hundreds of lines of complex code versus kube-burner's simple YAML configuration. *(Life's too short, use the right tool.)* 🛠️

### For Velero Testing Specifically *(The Perfect Match)*

- **Realistic Load Patterns**: Creates load similar to real applications *(not just random garbage)*
- **Backup Tool Compatible**: Generates standard Kubernetes objects *(Velero actually understands what we're creating)*
- **Performance Testing Standard**: Widely used for testing backup solutions *(the industry knows what's up)*
- **Proven at Scale**: Battle-tested in enterprise environments *(survived the corporate gauntlet)*

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
- **[Kube-burner Documentation](https://github.com/kube-burner/kube-burner)** - Object creation tool
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
- [Kube-burner GitHub Repository](https://github.com/kube-burner/kube-burner)
- [Kubernetes Performance Testing](https://kubernetes.io/docs/concepts/cluster-administration/system-logs/)

---

**Note**: This toolkit is designed for testing and development environments. Use caution when running large-scale tests in production clusters. *(We're not responsible if you accidentally stress-test your production environment into oblivion. You've been warned!)* ⚠️😅