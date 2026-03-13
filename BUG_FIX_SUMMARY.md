# Kubernetes Pod Init Container Restart Bug - Fix Summary

## 🐛 Bug Description
**Pod POD-A stuck in "Init" state after kubelet restart during pod restart**

### Scenario
1. Pod POD-A is running with 2 init containers + 1 regular container
2. Minion reboots → all containers exit
3. Kubelet starts and begins restarting pod
4. If kubelet restarts DURING pod restart, residual containers from old sandbox are not properly cleaned
5. On next kubelet startup, old exited containers confuse the state machine
6. Pod permanently stuck in "Init" state

---

## 🔍 Root Causes & Issues Found

### Issue #1: purgeInitContainers() doesn't filter by sandbox ID
**File**: `pkg/kubelet/kuberuntime/kuberuntime_container.go` (Line 1007)

**Problem**:
- Removes ALL init containers matching a name, regardless of which sandbox they belong to
- When kubelet restarts mid-sync, OLD containers from previous sandbox might still exist
- If removal fails, error is logged but function continues (doesn't stop SyncPod)
- This can leave residual old containers that confuse later sync cycles

**Original Code**:
```go
func (m *kubeGenericRuntimeManager) purgeInitContainers(...) {
    for name := range initContainerNames {
        for _, status := range podStatus.ContainerStatuses {
            if status.Name != name { continue }
            if err := m.removeContainer(...) {
                utilruntime.HandleError(...) // Error logged, but function continues!
                continue
            }
        }
    }
}
```

### Issue #2: SyncPod ignores purgeInitContainers() failures
**File**: `pkg/kubelet/kuberuntime/kuberuntime_manager.go` (Line 1472)

**Problem**:
- purgeInitContainers had no return value (void function)
- Even if critical cleanup failed, SyncPod proceeded to create new sandbox
- This causes the pod to start with unclean state
- Later, new containers can't properly initialize in mixed state

**Original Code**:
```go
if podContainerChanges.CreateSandbox {
    m.purgeInitContainers(ctx, pod, podStatus)  // No error checking!
}
```

### Issue #3: computeInitContainerActions() confuses old containers with new ones
**File**: `pkg/kubelet/kuberuntime/kuberuntime_container.go` (Line 1087)

**Problem**:
- The code comment even acknowledges the bug: *"kubelet cannot differentiate container statuses of previous podSandbox from current one"*
- When checking if init is complete, it looks at ANY regular container's state
- If an old exited regular container from previous sandbox is found, thinks init is done
- Even though new init containers are still running/failed

**Original Code**:
```go
podHasInitialized := false
for _, container := range pod.Spec.Containers {
    status := podStatus.FindContainerStatusByName(container.Name)
    if status == nil { continue }
    switch status.State {
    case kubecontainer.ContainerStateRunning:
        podHasInitialized = true  // Could be container from OLD sandbox!
    }
}
```

---

## ✅ Fixes Implemented

### Fix #1: Filter purgeInitContainers by active sandbox ID
**File**: `pkg/kubelet/kuberuntime/kuberuntime_container.go`

**Changes**:
1. Changed function signature to return `error` instead of `void`
2. Gets list of active sandbox IDs from `podStatus.SandboxStatuses`
3. Only removes init containers that do NOT belong to active sandboxes
4. Properly tracks and returns errors

**New Code**:
```go
func (m *kubeGenericRuntimeManager) purgeInitContainers(...) error {
    // Get IDs of active sandboxes to avoid removing containers from new sandboxes
    activeSandboxIDs := sets.New[string]()
    for _, sb := range podStatus.SandboxStatuses {
        if sb.State == runtimeapi.PodSandboxState_SANDBOX_READY {
            activeSandboxIDs.Insert(sb.Id)
        }
    }
    
    var lastErr error
    for name := range initContainerNames {
        for _, status := range podStatus.ContainerStatuses {
            if status.Name != name { continue }
            
            // CRITICAL: Skip containers from active sandboxes
            if activeSandboxIDs.Has(status.PodSandboxID) {
                logger.V(4).Info("Skipping init container removal - belongs to active sandbox", ...)
                continue
            }
            
            if err := m.removeContainer(...) {
                logger.Error(err, "failed to remove pod init container", ...)
                lastErr = err
            }
        }
    }
    return lastErr
}
```

### Fix #2: Honor purgeInitContainers() errors in SyncPod
**File**: `pkg/kubelet/kuberuntime/kuberuntime_manager.go`

**Changes**:
1. Changed to check the error returned by purgeInitContainers
2. If cleanup fails, abort the sync to prevent mixed state
3. Log error and record failure in sync result
4. RetryManager will attempt cleanup again in next sync cycle

**New Code**:
```go
if podContainerChanges.CreateSandbox {
    if err := m.purgeInitContainers(ctx, pod, podStatus); err != nil {
        logger.Error(err, "Failed to purge init containers, aborting pod sync", ...)
        killResult := kubecontainer.NewSyncResult(...)
        killResult.Fail(kubecontainer.ErrKillPodSandbox, fmt.Sprintf("failed to purge init containers: %v", err))
        result.AddSyncResult(killResult)
        return  // CRITICAL: Stop here, don't proceed
    }
}
```

### Fix #3: Filter by active sandbox in computeInitContainerActions
**File**: `pkg/kubelet/kuberuntime/kuberuntime_container.go`

**Changes**:
1. Extract active sandbox ID from `podStatus.SandboxStatuses[0].Id`
2. When checking container states for init completion, filter by active sandbox
3. Only consider containers that belong to current active sandbox
4. Log when skipping containers from different sandboxes (debug visibility)

**New Code**:
```go
podHasInitialized := false

// Get the active sandbox ID (the most recent one)
var activeSandboxID string
if len(podStatus.SandboxStatuses) > 0 {
    activeSandboxID = podStatus.SandboxStatuses[0].Id
}

for _, container := range pod.Spec.Containers {
    status := podStatus.FindContainerStatusByName(container.Name)
    if status == nil { continue }
    
    // CRITICAL: Only consider containers from the active sandbox
    if activeSandboxID != "" && status.PodSandboxID != activeSandboxID {
        logger.V(5).Info("Skipping container from different sandbox during init check", ...)
        continue
    }
    
    switch status.State {
    case kubecontainer.ContainerStateRunning:
        podHasInitialized = true
    }
}
```

---

## 📊 Impact Analysis

### What This Fixes
✅ **Residual container cleanup**: Old containers from dead sandboxes are properly identified and purged  
✅ **Clear error propagation**: Cleanup failures are visible and stop bad state from propagating  
✅ **Correct init completion detection**: Uses only containers from current active sandbox  
✅ **Kubelet restart resilience**: Pod can recover even if kubelet crashes mid-restart

### Scenarios Now Handled
1. **Kubelet crash during pod restart** → Automatic recovery on next start
2. **Container runtime issues** → Errors reported, not silently ignored
3. **Stale container detection** → Properly identifies old vs new containers
4. **Sandbox switching** → Works correctly with multiple sandbox creations

### Code Locations Modified
- `pkg/kubelet/kuberuntime/kuberuntime_container.go` - 2 changes
  - purgeInitContainers() function (Lines 1004-1050)
  - computeInitContainerActions() function (Lines 1090-1130)
- `pkg/kubelet/kuberuntime/kuberuntime_manager.go` - 1 change  
  - SyncPod() function (Lines 1472-1483)

---

## 🧪 Testing Recommendations

### Unit Tests to Add
```go
// Test 1: purgeInitContainers filters by active sandbox
func TestPurgeInitContainersFiltersActiveSandbox(t *testing.T) {
    // Create 2 containers with same name but different sandbox IDs
    // Ensure only non-active one is removed
}

// Test 2: purgeInitContainers returns error on failure
func TestPurgeInitContainersReturnsError(t *testing.T) {
    // Mock removeContainer to fail
    // Verify error is returned
}

// Test 3: computeInitContainerActions uses active sandbox only
func TestComputeInitContainerActionsUsesActiveSandbox(t *testing.T) {
    // Create pod with old exited container + new running init
    // Verify it doesn't think pod is initialized
}
```

### E2E Tests
```bash
# Reproduce the bug scenario:
1. Start pod with 2 init containers
2. Kill kubelet while pod is initializing
3. Restart kubelet
4. Verify pod eventually reaches Running state (not stuck in Init)
```

### Manual Testing
```bash
# Monitor logs during pod restart across kubelet restart:
kubectl logs -f kubelet.log | grep -i "init\|sandbox\|purge"

# Verify pod transitions correctly:
kubectl get pod <pod-name> -w
kubectl describe pod <pod-name>  # Check events
```

---

## 📝 Changelog Entry

```
Fix pod stuck in Init state when kubelet restarts during pod restart (#XXXXX)

When kubelet restarts mid-pod-restart, residual containers from old sandboxes
were not properly distinguished from current ones, causing:
- Failed init container cleanup to be ignored
- Old exited containers to signal init completion
- Pods permanently stuck in Init state

Changes:
- purgeInitContainers now filters by active sandbox ID before removal
- SyncPod aborts if init container cleanup fails
- computeInitContainerActions uses only active sandbox containers for state checks

Fixes: #XXXXX
Kind: bugfix
Release-note: Fixed pod initialization failures when kubelet restarts during pod restart
```

---

## 🔗 Related Code References

- **Container Status**: `pkg/kubelet/container/runtime.go` - Line 359 (PodSandboxID field)
- **PodStatus Structure**: `pkg/kubelet/container/runtime.go` - Line 341 (SandboxStatuses field)  
- **getPodContainerStatuses**: `pkg/kubelet/kuberuntime/kuberuntime_container.go` - Line 664
- **Active container tracking**: Checks `c.PodSandboxID == activePodSandboxID` before including

---

**Status**: ✅ All fixes implemented and ready for testing
