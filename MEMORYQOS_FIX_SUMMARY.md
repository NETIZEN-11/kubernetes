# MemoryQoS BestEffort Pod Fix - Issue #137685

## Problem Summary
With MemoryQoS enabled on a cgroup v2 node, BestEffort pods do not get a finite `memory.high` value. Instead, `memory.high` remains unset and reads as max, which is inconsistent with the MemoryQoS KEP.

## Root Cause Analysis
The bug was located in `pkg/kubelet/kuberuntime/kuberuntime_container_linux.go` at line 163:

**Original Code:**
```go
if memoryRequest != memoryLimit {  // This condition fails for BestEffort pods
    // Calculate memory.high...
}
```

For BestEffort pods:
- `memoryRequest = 0`
- `memoryLimit = 0`
- Condition `0 != 0` evaluates to `false`
- Therefore, `memory.high` is never set

## Fix Implementation
**Modified Condition:**
```go
if memoryRequest != memoryLimit || (memoryRequest == 0 && memoryLimit == 0) {
    // Calculate memory.high...
}
```

This change ensures that:
1. Burstable pods (`memoryRequest != memoryLimit`) continue to work as before
2. BestEffort pods (`memoryRequest == 0 && memoryLimit == 0`) now get `memory.high` set according to KEP

## KEP Formula Implementation
The existing formula already correctly handles BestEffort pods:

```go
if memoryLimit != 0 {
    // Use container limit for Burstable pods
    memoryHigh = int64(math.Floor(
        float64(memoryRequest)+
            (float64(memoryLimit)-float64(memoryRequest))*float64(m.memoryThrottlingFactor))/float64(defaultPageSize)) * defaultPageSize
} else {
    // Use node allocatable memory for BestEffort pods (memoryLimit = 0)
    allocatable := m.getNodeAllocatable()
    allocatableMemory, ok := allocatable[v1.ResourceMemory]
    if ok && allocatableMemory.Value() > 0 {
        memoryHigh = int64(math.Floor(
            float64(memoryRequest)+
                (float64(allocatableMemory.Value())-float64(memoryRequest))*float64(m.memoryThrottlingFactor))/float64(defaultPageSize)) * defaultPageSize
    }
}
```

For BestEffort pods, this simplifies to:
```
memory.high = floor[(memoryThrottlingFactor * node allocatable memory) / pageSize] * pageSize
```

## Test Coverage Added
Added test case `BestEffortPodNoMemoryRequestOrLimit` in `TestGenerateContainerConfigWithMemoryQoSEnforced` to verify:
- `memory.min` is set to 0 (correct for BestEffort pods)
- `memory.high` is calculated using node allocatable memory
- Formula matches KEP specification

## Files Modified
1. **pkg/kubelet/kuberuntime/kuberuntime_container_linux.go**
   - Fixed condition at line 164 to handle BestEffort pods
   - Added comment explaining the change

2. **pkg/kubelet/kuberuntime/kuberuntime_container_linux_test.go**
   - Added test case for BestEffort pods
   - Verified memory.high calculation matches KEP formula

## Verification
The fix ensures that for the reproduction case:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-demo-besteffort
spec:
  containers:
  - name: app
    image: registry.k8s.io/pause:3.9
```

The container will now have:
- `memory.min = 0` (unchanged)
- `memory.high = floor[(0.9 * node_allocatable_memory) / pageSize] * pageSize` (newly set)

## Impact
- **Backward Compatible**: No changes to existing behavior for Burstable and Guaranteed pods
- **Minimal Change**: Single line condition modification
- **KEP Compliant**: Now follows MemoryQoS KEP specification for all pod QoS classes
- **Performance**: No performance impact, only affects pod creation logic

## Testing Recommendation
To verify the fix in a real environment:
1. Deploy a BestEffort pod on a cgroup v2 node with MemoryQoS enabled
2. Check the container's cgroup memory.high value
3. Verify it's set to a finite value calculated from node allocatable memory
4. Confirm it's not "max" (unlimited)
