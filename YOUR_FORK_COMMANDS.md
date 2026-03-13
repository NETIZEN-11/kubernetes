# NETIZEN-11 Kubernetes Fork - MemoryQoS Fix Commands

## Step 1: Repository Setup

```bash
# Clone अपना fork
git clone https://github.com/NETIZEN-11/kubernetes.git
cd kubernetes

# Upstream remote add करें
git remote add upstream https://github.com/kubernetes/kubernetes.git

# Verify remotes
git remote -v
# Should show:
# origin    https://github.com/NETIZEN-11/kubernetes.git (fetch)
# origin    https://github.com/NETIZEN-11/kubernetes.git (push)
# upstream  https://github.com/kubernetes/kubernetes.git (fetch)
# upstream  https://github.com/kubernetes/kubernetes.git (push)
```

## Step 2: Sync with Upstream

```bash
# Fetch latest changes from upstream
git fetch upstream

# Switch to main branch
git checkout main

# Rebase with upstream main
git rebase upstream/main

# Push latest to your fork (optional but recommended)
git push origin main
```

## Step 3: Create MemoryQoS Fix Branch

```bash
# Create new branch for MemoryQoS fix
git checkout -b fix/memoryqos-besteffort-pods-137685

# Verify you're on the right branch
git branch
# Should show: * fix/memoryqos-besteffort-pods-137685
```

## Step 4: Apply MemoryQoS Changes

### File 1: pkg/kubelet/kuberuntime/kuberuntime_container_linux.go

**Line 164 पर change:**
```go
// FROM:
if memoryRequest != memoryLimit {

// TO:
if memoryRequest != memoryLimit || (memoryRequest == 0 && memoryLimit == 0) {
```

**Line 163 पर comment add:**
```go
// However, for BestEffort pods where both memoryRequest and memoryLimit are 0, we still need to set memory.high according to KEP.
```

### File 2: pkg/kubelet/kuberuntime/kuberuntime_container_linux_test.go

**TestGenerateContainerConfigWithMemoryQoSEnforced function में add करें:**

```go
// BestEffort pod with no memory requests or limits (add after pod2 definition)
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

// Add calculation after pod2MemoryHigh
// BestEffort pod: memory.high = floor[(memoryThrottlingFactor * node allocatable memory) / pageSize] * pageSize
pod3MemoryHigh := int64(math.Floor(
    float64(0)+
        (float64(memoryNodeAllocatable.Value())-float64(0))*float64(m.memoryThrottlingFactor))/float64(pageSize)) * pageSize

// Add config generation
l3, _ := m.generateLinuxContainerConfig(tCtx, &pod3.Spec.Containers[0], pod3, new(int64), "", nil, true)

// Add test case in tests slice
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

## Step 5: Test Your Changes

```bash
# Run specific test
go test -run TestGenerateContainerConfigWithMemoryQoSEnforced ./pkg/kubelet/kuberuntime/

# If test passes, run broader tests
go test ./pkg/kubelet/kuberuntime/

# Build check
make all
```

## Step 6: Commit and Push

```bash
# Add modified files
git add pkg/kubelet/kuberuntime/kuberuntime_container_linux.go
git add pkg/kubelet/kuberuntime/kuberuntime_container_linux_test.go

# Verify changes
git status
git diff --cached

# Commit
git commit -m "Fix MemoryQoS for BestEffort pods on cgroup v2

- Fix condition to set memory.high for BestEffort pods where both memory requests and limits are 0
- Add test case to verify memory.high is calculated using node allocatable memory  
- Ensure compliance with MemoryQoS KEP specification
- Fixes #137685

Signed-off-by: Your Name <your.email@example.com>"

# Push to your fork
git push origin fix/memoryqos-besteffort-pods-137685
```

## Step 7: Create Pull Request

1. Browser में जाएं: https://github.com/NETIZEN-11/kubernetes
2. "Compare & pull request" button click करें
3. PR details:
   - **Title:** `Fix MemoryQoS for BestEffort pods on cgroup v2`
   - **Base:** `kubernetes:main`
   - **Compare:** `NETIZEN-11:fix/memoryqos-besteffort-pods-137685`

## PR Template:

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
- This is the 3rd fix in the same fork repository

## Does this PR introduce a user-facing change?
```release-note
Fix MemoryQoS to properly set memory.high for BestEffort pods on cgroup v2 nodes, ensuring memory throttling works as specified in the MemoryQoS KEP.
```
```

## Quick Commands Summary:

```bash
git clone https://github.com/NETIZEN-11/kubernetes.git
cd kubernetes
git remote add upstream https://github.com/kubernetes/kubernetes.git
git fetch upstream
git checkout main
git rebase upstream/main
git checkout -b fix/memoryqos-besteffort-pods-137685
# Make changes...
git add .
git commit -m "Fix MemoryQoS for BestEffort pods on cgroup v2"
git push origin fix/memoryqos-besteffort-pods-137685
```

## Your Contribution History:
- ✅ Issue #1: [Already solved in this fork]
- ✅ Issue #2: [Already solved in this fork]  
- 🚀 Issue #3: MemoryQoS BestEffort pods (current)

यह commands follow करके आप easily PR create कर सकते हैं! 🎯
