# MemoryQoS Fix - Pull Request Creation Guide

## Step 1: Fork और Clone Kubernetes Repository

```bash
# GitHub से Kubernetes repository fork करें (अगर पहले से नहीं किया है)
# https://github.com/kubernetes/kubernetes/fork

# Fork किया हुआ repository clone करें
git clone https://github.com/YOUR_USERNAME/kubernetes.git
cd kubernetes

# Upstream remote add करें
git remote add upstream https://github.com/kubernetes/kubernetes.git
```

## Step 2: New Branch Create करें

```bash
# Latest main branch sync करें
git fetch upstream
git checkout main
git rebase upstream/main

# New branch create करें अपने fix के लिए
git checkout -b fix/memoryqos-besteffort-pods-137685
```

## Step 3: Changes Apply करें

### Option A: Manual Changes (Recommended)

**File 1: `pkg/kubelet/kuberuntime/kuberuntime_container_linux.go`**

Line 164 पर यह change करें:
```go
// OLD CODE:
if memoryRequest != memoryLimit {

// NEW CODE:
if memoryRequest != memoryLimit || (memoryRequest == 0 && memoryLimit == 0) {
```

Comment add करें line 163 पर:
```go
// However, for BestEffort pods where both memoryRequest and memoryLimit are 0, we still need to set memory.high according to KEP.
```

**File 2: `pkg/kubelet/kuberuntime/kuberuntime_container_linux_test.go`**

`TestGenerateContainerConfigWithMemoryQoSEnforced` function में यह test case add करें:

```go
// BestEffort pod with no memory requests or limits
pod3 := &v1.Pod{
    ObjectMeta: metav1.ObjectMeta{
        UID:       "12345678",
        Name:      "bar",
        Namespace: "new",
    },
    Spec: v1.PodSpec{
        Containers: []v1.Container{
            {
                Name:            "foo",
                Image:           "busybox",
                ImagePullPolicy: v1.PullIfNotPresent,
                Command:         []string{"testCommand"},
                WorkingDir:      "testWorkingDir",
                Resources: v1.ResourceRequirements{
                    // No memory requests or limits - BestEffort pod
                },
            },
        },
    },
}

// BestEffort pod: memory.high = floor[(memoryThrottlingFactor * node allocatable memory) / pageSize] * pageSize
pod3MemoryHigh := int64(math.Floor(
    float64(0)+
        (float64(memoryNodeAllocatable.Value())-float64(0))*float64(m.memoryThrottlingFactor))/float64(pageSize)) * pageSize

l3, _ := m.generateLinuxContainerConfig(tCtx, &pod3.Spec.Containers[0], pod3, new(int64), "", nil, true)

// Test case add करें tests slice में:
{
    name: "BestEffortPodNoMemoryRequestOrLimit",
    pod:  pod3,
    expected: &expectedResult{
        l3,
        0, // memory.min should be 0 for BestEffort pods
        int64(pod3MemoryHigh),
    },
},
```

### Option B: Files Copy करके

मेरे द्वारा modified files को copy करें:
```bash
# मेरे modified files को copy करें
cp /path/to/my/modified/kuberuntime_container_linux.go pkg/kubelet/kuberuntime/
cp /path/to/my/modified/kuberuntime_container_linux_test.go pkg/kubelet/kuberuntime/
```

## Step 4: Test Run करें

```bash
# Dependencies install करें
make all

# Specific test run करें
go test -run TestGenerateContainerConfigWithMemoryQoSEnforced ./pkg/kubelet/kuberuntime/

# Full test suite run करें (optional)
make test
```

## Step 5: Commit और Push करें

```bash
# Changes add करें
git add pkg/kubelet/kuberuntime/kuberuntime_container_linux.go
git add pkg/kubelet/kuberuntime/kuberuntime_container_linux_test.go

# Commit करें
git commit -m "Fix MemoryQoS for BestEffort pods on cgroup v2

- Fix condition to set memory.high for BestEffort pods where both memory requests and limits are 0
- Add test case to verify memory.high is calculated using node allocatable memory
- Ensure compliance with MemoryQoS KEP specification
- Fixes #137685"

# Push करें अपने fork में
git push origin fix/memoryqos-besteffort-pods-137685
```

## Step 6: Pull Request Create करें

1. GitHub पर जाएं: https://github.com/YOUR_USERNAME/kubernetes
2. "Compare & pull request" button पर click करें
3. PR details fill करें:

**Title:** `Fix MemoryQoS for BestEffort pods on cgroup v2`

**Body:**
```markdown
## What type of PR is this?
/kind bug

## What this PR does / why we need it
Fixes MemoryQoS issue where BestEffort pods do not get a finite memory.high value on cgroup v2 nodes. Currently memory.high remains unset and reads as max, which is inconsistent with the MemoryQoS KEP.

## Which issue(s) this PR fixes
Fixes #137685

## Special notes for your reviewer
- The fix ensures BestEffort pods get memory.high calculated using node allocatable memory according to KEP formula
- Backward compatible - no changes to existing Burstable/Guaranteed pod behavior
- Added comprehensive test coverage for BestEffort pods

## Does this PR introduce a user-facing change?
```release-note
Fix MemoryQoS to properly set memory.high for BestEffort pods on cgroup v2 nodes, ensuring memory throttling works as specified in the MemoryQoS KEP.
```
```

## Step 7: PR Review और Merge

1. Kubernetes maintainers से review request करें
2. CI/CD tests pass होने तक wait करें
3. Review comments address करें
4. Approvals मिलने के बाद merge होगा

## Additional Resources

- [Kubernetes Contributing Guide](https://github.com/kubernetes/community/blob/master/contributors/guide/first-contribution.md)
- [MemoryQoS KEP](https://git.k8s.io/enhancements/keps/sig-node/2570-memory-qos)
- [Issue #137685](https://github.com/kubernetes/kubernetes/issues/137685)

## Quick Commands Summary

```bash
# Setup
git clone https://github.com/YOUR_USERNAME/kubernetes.git
cd kubernetes
git remote add upstream https://github.com/kubernetes/kubernetes.git

# Branch
git checkout -b fix/memoryqos-besteffort-pods-137685

# Make changes (manually or copy files)

# Test
go test -run TestGenerateContainerConfigWithMemoryQoSEnforced ./pkg/kubelet/kuberuntime/

# Commit
git add .
git commit -m "Fix MemoryQoS for BestEffort pods on cgroup v2"
git push origin fix/memoryqos-besteffort-pods-137685

# Create PR on GitHub
```

यह guide follow करके आप easily pull request create कर सकते हैं!
