# Kubernetes Domain Management Audit Script

A shell script that audits Ingress controllers and Certificate Manager configurations in a Kubernetes cluster. The script identifies mismatches between ingress domains and SSL certificates, helping ensure all domains are properly secured and all certificates are being used.

## Requirements

- `kubectl` - Kubernetes command-line tool
- `doctl` - DigitalOcean command-line tool
- `jq` - Command-line JSON processor

## Usage

```bash
./dommgmt.sh [--debug]
```

### Options

- `--debug`: Enable detailed debug output for troubleshooting

### Environment Variables

The script supports the following environment variables to customize behavior:

- `INGRESS_CLASS`: Specifies the ingress class to filter on (default: "nginx")
- `CERT_MANAGER_NAMESPACE`: Namespace where cert-manager is installed (default: "cert-manager")
- `INGRESS_NAMESPACE`: Namespace where the ingress controller is installed (default: "ingress-nginx")

## Output Format

The script produces several tables and status reports:

### Ingress Controller Domains

A table showing all domains configured in ingress resources with the following columns:

| Column | Description |
|--------|-------------|
| DOMAIN | The hostname configured in the ingress rule |
| NAMESPACE | Kubernetes namespace of the ingress resource |
| WORKLOAD | Workload label of the ingress (if set) |
| WORKTYPE | Worktype label of the ingress (if set) |
| INGRESS | Name of the ingress resource |
| SERVICE:PORT | Backend service and port that traffic is routed to |
| PATH | URL path configured in the ingress rule |
| TLS | Whether TLS is configured for this domain (YES/NO) |

### Certificate Manager Status

A table showing all certificates managed by cert-manager with the following columns:

| Column | Description |
|--------|-------------|
| DOMAIN | Domain name covered by the certificate |
| NAMESPACE | Kubernetes namespace of the certificate |
| WORKLOAD | Workload label of the certificate (if set) |
| WORKTYPE | Worktype label of the certificate (if set) |
| CERTIFICATE | Name of the certificate resource |
| STATUS | Current status of the certificate (Ready/NotReady) |
| RENEWAL | Certificate expiration date |

### Domain Mismatches

A report highlighting:
- Domains in ingress resources that lack corresponding certificates
- Certificates that aren't used by any ingress resource

### System Health Check

Status report for:
- Cert-manager pods (with status and node location)
- Ingress controller pods (with status and node location)

## Example Output

```
=== DOKS Ingress and Certificate Manager Audit (v1.0.19) ===
Ingress Class: nginx
Cert-Manager Namespace: cert-manager
Ingress Namespace: ingress-nginx

=== Ingress Controller Domains ===
┌────────────────────┬───────────┬──────────┬──────────┬───────────┬─────────────┬─────┬─────┐
│ DOMAIN             │ NAMESPACE │ WORKLOAD │ WORKTYPE │ INGRESS   │ SERVICE:PORT │ PATH │ TLS │
├────────────────────┼───────────┼──────────┼──────────┼───────────┼─────────────┼─────┼─────┤
│ api.example.com    │ default   │ api      │ backend  │ api       │ api:80       │ /   │ YES │
│ www.example.com    │ default   │ web      │ frontend │ web       │ web:80       │ /   │ YES │
└────────────────────┴───────────┴──────────┴──────────┴───────────┴─────────────┴─────┴─────┘

=== Certificate Manager Status ===
┌────────────────────┬───────────┬──────────┬──────────┬────────────────┬────────┬─────────────────┐
│ DOMAIN             │ NAMESPACE │ WORKLOAD │ WORKTYPE │ CERTIFICATE    │ STATUS │ RENEWAL         │
├────────────────────┼───────────┼──────────┼──────────┼────────────────┼────────┼─────────────────┤
│ api.example.com    │ default   │ api      │ backend  │ api-cert       │ Ready  │ 2023-12-31      │
│ www.example.com    │ default   │ web      │ frontend │ web-cert       │ Ready  │ 2023-12-31      │
│ test.example.com   │ default   │ test     │ test     │ test-cert      │ Ready  │ 2023-12-31      │
└────────────────────┴───────────┴──────────┴──────────┴────────────────┴────────┴─────────────────┘

=== Domain Mismatches ===
✓ All ingress domains have corresponding certificates!

⚠ Certificates not used by ingress (review if unneeded):
  • test.example.com

=== System Health Check ===
Cert-Manager Pods:
cert-manager-5d5976f644-xh7j9   1/1     Running   0    5d    10.244.0.45   worker-1   <none>
cert-manager-cainjector-76cdbdf7c4-s8q9v   1/1     Running   0    5d    10.244.1.23   worker-2   <none>
cert-manager-webhook-7f68d87c8c-bpgq5   1/1     Running   0    5d    10.244.0.46   worker-1   <none>

Ingress Controller Pods:
ingress-nginx-controller-546d56d5f9-78xvp   1/1     Running   0    5d    10.244.1.24   worker-2   <none>
```

## Notes

- The script is specifically designed for DOKS (DigitalOcean Kubernetes Service) but works with any Kubernetes cluster using nginx ingress and cert-manager
- Missing workload or worktype labels are shown as "Missing"
- Color coding is used in the terminal output (green for success, red for errors, yellow for warnings)
- The script checks for exact domain matches between ingress and certificates (subdomains are treated as separate domains)
- The script creates temporary files during execution and cleans them up upon completion
- Error logs are saved to /tmp/ for debugging purposes

## Version History

- 1.0.19: Current version
  - Enhanced error handling
  - Added support for workload and worktype labels
  - Improved table rendering with box-drawing characters