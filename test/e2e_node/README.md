See [e2e-node-tests](https://git.k8s.io/community/contributors/devel/sig-node/e2e-node-tests.md)

## 🚀 Local Testing (Issue #137722)

Easy local node e2e testing without GCP setup:

```bash
# Run all tests
make test-e2e-node-local

# Run specific tests
make test-e2e-node-local FOCUS="Kubelet"

# Quick help
./test/e2e_node/local/run-local-e2e.sh --help
```

**Benefits:**
- ✅ No GCP required
- ✅ Docker-based containerd environment  
- ✅ One-command setup
- ✅ Fast local iteration

See [LOCAL_TESTING.md](./LOCAL_TESTING.md) for details.
