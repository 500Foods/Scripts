# Kubernetes Node Information Script

A shell script that provides detailed information about nodes and pods in a Kubernetes cluster. The script creates tables showing pod information organized by node, including resource allocation, current usage, and network configuration.

## Requirements

- `kubectl` - Kubernetes command-line tool
- `jq` - Command-line JSON processor

## Usage

```bash
./nodeinfo.sh [--debug]
```

### Options

- `--debug`: Enable debug output for troubleshooting

## Output Format

The script creates a separate table for each node in the cluster. Each table includes the following columns:

| Column | Description |
|--------|-------------|
| POD | Name of the pod (shows pod count in totals row) |
| NAMESPACE | Kubernetes namespace where the pod is running |
| WORKLOAD | Workload label of the pod (if set) |
| WORKTYPE | Worktype label of the pod (if set) |
| CPU REQ | CPU resource request (in millicores) |
| CPU LIM | CPU resource limit (in millicores) |
| CPU USE | Current CPU usage (from kubectl top) |
| MEM REQ | Memory resource request |
| MEM LIM | Memory resource limit |
| MEM USE | Current memory usage (from kubectl top) |
| PORTS | Port allocations and protocols |

## Example Output

```
=== Node: worker-1 ===
┌──────────────┬───────────┬──────────┬──────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┐
│ POD          │ NAMESPACE │ WORKLOAD │ WORKTYPE │ CPU REQ │ CPU LIM │ CPU USE │ MEM REQ │ MEM LIM │ MEM USE │ PORTS   │
├──────────────┼───────────┼──────────┼──────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
│ nginx-pod    │ default   │ web      │ frontend │ 100m    │ 200m    │ 10m     │ 128Mi   │ 256Mi   │ 64Mi    │ 80/TCP  │
│ Total (1 pod)│           │          │          │ 100m    │ 200m    │ 10m     │ 128Mi   │ 256Mi   │ 64Mi    │         │
└──────────────┴───────────┴──────────┴──────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┘
```

## Notes

- Resource requests and limits are shown in their original format (e.g., millicores for CPU, Mi/Gi for memory)
- Current usage information requires the metrics-server to be installed in the cluster
- If a pod has multiple containers, their ports are combined in the PORTS column
- Missing values are shown as blank spaces
- Labels (workload, worktype) show as "Missing" if not set
- A totals row is included at the bottom of each node's table showing:
  * Total number of pods
  * Sum of all resource requests, limits, and current usage

## Version History

- 1.0.0: Initial release
  - Node-based pod information display
  - Resource allocation and usage tracking
  - Network port information
  - Support for debug mode