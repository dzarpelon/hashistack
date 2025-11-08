# Kubernetes Infrastructure with HashiStack

This project automates the deployment of a complete Kubernetes cluster with production-ready add-ons including storage, DNS, and ingress capabilities.

## Architecture Overview

### Base Infrastructure

- **Kubernetes**: v1.31.x cluster with 1 master and 3 worker nodes
- **Platform**: RHEL 10 ARM64
- **CNI**: Calico for pod networking
- **CRI**: CRI-O container runtime

### Add-ons Stack

#### 1. **MetalLB** - Bare Metal Load Balancer

- **Version**: v0.14.9
- **Mode**: Layer 2
- **Why**: Provides LoadBalancer service type support in bare-metal Kubernetes environments, assigning external IPs from a configured pool
- **IP Pool**: 192.168.100.150 - 192.168.100.250

#### 2. **Longhorn** - Distributed Block Storage

- **Deployment**: Helm chart
- **Replication**: 2 replicas for redundancy
- **Why**: Cloud-native distributed block storage for Kubernetes, provides persistent volumes with built-in backups, snapshots, and disaster recovery
- **Features**:
  - Dynamic volume provisioning
  - Cross-node replication
  - Snapshot and backup support
  - Web UI for management

#### 3. **DNS Infrastructure** - Custom DNS for Lab Domain

Components:

- **etcd**: v3.5.15 (3-member cluster with persistent storage via Longhorn)
- **CoreDNS**: v1.11.1 (2 replicas, NodePort 30053)
- **External-DNS**: v0.14.2 (automatic DNS record management)

**Why**: Provides automatic DNS resolution for services and ingresses in the lab domain (`*.lab.dzarpelon.com`), enabling access to services via friendly hostnames instead of IP addresses

**How it works**:

1. External-DNS watches Kubernetes services and ingresses
2. Automatically creates DNS records in etcd
3. CoreDNS serves DNS queries from etcd backend
4. All VMs configured to forward `*.lab.dzarpelon.com` queries to CoreDNS

#### 4. **Traefik** - Modern Ingress Controller

- **Version**: v3.5.x
- **Deployment**: Helm chart, 2 replicas
- **Why**: Cloud-native ingress controller with automatic service discovery, dashboard, and support for both Ingress resources and custom CRDs (IngressRoute)
- **Features**:
  - HTTP/HTTPS routing with automatic TLS
  - Built-in dashboard for monitoring
  - Support for multiple providers (Kubernetes Ingress + CRDs)
  - Access logs and metrics

### Pre-configured Services

The automation includes pre-configured Ingress resources for:

- **Traefik Dashboard**: `http://traefik.lab.dzarpelon.com/dashboard/`
- **Longhorn Dashboard**: `http://longhorn.lab.dzarpelon.com/`

## Prerequisites

1. **Controller Machine** (where you run Ansible):

   - Ansible installed
   - SSH access to all cluster nodes
   - Private key: `~/.ssh/dzarpelon`
   - DNS resolver configured for `*.lab.dzarpelon.com` (optional, for direct access)

2. **Cluster Nodes**:

   - RHEL 10 or compatible Linux distribution
   - SSH access with sudo privileges
   - Network connectivity between all nodes
   - Inventory configured in `ansible/inventory`

3. **DNS Configuration** (for controller):
   ```bash
   # macOS example
   sudo mkdir -p /etc/resolver
   echo "nameserver 192.168.100.101" | sudo tee /etc/resolver/lab.dzarpelon.com
   echo "port 30053" | sudo tee -a /etc/resolver/lab.dzarpelon.com
   ```

## Configuration

### Dashboard Authentication

The automation secures dashboard access with basic authentication. Before deployment, configure credentials:

1. **Copy the example secrets file**:

   ```bash
   cd main-infra/ansible/group_vars/all
   cp secrets.yaml.example secrets.yaml
   ```

2. **Edit credentials** in `secrets.yaml`:

   ```yaml
   dashboard_admin_user: admin
   dashboard_admin_password: YOUR_SECURE_PASSWORD
   ```

3. **The secrets.yaml file is gitignored** and will not be committed to version control

**Protected Dashboards**:

- Traefik Dashboard: `http://traefik.lab.dzarpelon.com/dashboard/`
- Longhorn Dashboard: `http://longhorn.lab.dzarpelon.com/`

Both use the same credentials configured in `secrets.yaml`.

## Deployment

### Deploy Complete Environment

From the `main-infra` directory:

```bash
cd main-infra
ansible-playbook ansible/playbooks/k8s-cluster.yaml
```

This will:

1. Configure all nodes with common Kubernetes components
2. Install Python dependencies for Ansible Kubernetes modules
3. Initialize the master node
4. Join worker nodes to the cluster
5. Deploy MetalLB load balancer
6. Install Longhorn distributed storage
7. Deploy DNS infrastructure (etcd + CoreDNS + External-DNS)
8. Install Traefik ingress controller
9. Configure DNS client forwarding on all VMs

**Duration**: Approximately 15-20 minutes for full deployment

### Deploy Specific Components

You can deploy individual components by limiting to the master node and starting at a specific task:

```bash
# Deploy only Longhorn
ansible-playbook ansible/playbooks/k8s-cluster.yaml \
  --limit k8s-master.lab.dzarpelon.com \
  --start-at-task="Deploy Longhorn storage system"

# Deploy only DNS infrastructure
ansible-playbook ansible/playbooks/k8s-cluster.yaml \
  --limit k8s-master.lab.dzarpelon.com \
  --start-at-task="Deploy DNS infrastructure"

# Deploy only Traefik
ansible-playbook ansible/playbooks/k8s-cluster.yaml \
  --limit k8s-master.lab.dzarpelon.com \
  --start-at-task="Deploy Traefik Ingress Controller"
```

## Verification

After deployment, verify each component:

```bash
# Check cluster status
kubectl get nodes

# Check MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspools -n metallb-system

# Check Longhorn
kubectl get pods -n longhorn-system
kubectl get storageclass

# Check DNS infrastructure
kubectl get pods -n dns-system
kubectl get svc -n dns-system

# Check Traefik
kubectl get pods -n traefik-system
kubectl get svc -n traefik-system
kubectl get ingress -A

# Test DNS resolution
dig @192.168.100.101 -p 30053 traefik.lab.dzarpelon.com
dig @192.168.100.101 -p 30053 longhorn.lab.dzarpelon.com
```

### Access Protected Dashboards

Both dashboards are protected with basic authentication. Use the credentials configured in `ansible/group_vars/all/secrets.yaml`.

```bash
# Test authentication (should return 401 Unauthorized)
curl -i http://traefik.lab.dzarpelon.com/dashboard/
curl -i http://longhorn.lab.dzarpelon.com/

# Access with credentials
curl -u admin:'YOUR_PASSWORD' http://traefik.lab.dzarpelon.com/dashboard/
curl -u admin:'YOUR_PASSWORD' http://longhorn.lab.dzarpelon.com/

# Or open in browser and enter credentials when prompted:
# - Traefik Dashboard: http://traefik.lab.dzarpelon.com/dashboard/
# - Longhorn Dashboard: http://longhorn.lab.dzarpelon.com/
```

**Verify authentication resources:**

```bash
# Check Traefik auth
kubectl get secret -n traefik-system traefik-dashboard-auth
kubectl get middleware -n traefik-system dashboard-auth

# Check Longhorn auth
kubectl get secret -n longhorn-system longhorn-dashboard-auth
kubectl get middleware -n longhorn-system longhorn-auth
```

## Destroying the Environment

### Complete Cluster Teardown

```bash
cd main-infra
ansible-playbook ansible/playbooks/k8s-cluster.yaml -e k8s_state=absent
```

This will:

1. Drain and delete all nodes from the cluster
2. Stop kubelet and remove Kubernetes components
3. Clean up network configurations
4. Remove all persistent data

**Warning**: This is destructive and will delete all data in the cluster, including Longhorn volumes.

### Remove Specific Components

To remove only add-ons while keeping the cluster:

```bash
# Remove Traefik
helm uninstall traefik -n traefik-system
kubectl delete namespace traefik-system

# Remove DNS infrastructure
kubectl delete -f manifests/dns/

# Remove Longhorn
helm uninstall longhorn -n longhorn-system
kubectl delete namespace longhorn-system

# Remove MetalLB
kubectl delete -f manifests/metallb-l2.yaml
kubectl delete -f manifests/metallb-ippool.yaml
```

## Customization

### Adjusting IP Pool

Edit `manifests/metallb-ippool.yaml` to change the LoadBalancer IP range:

```yaml
spec:
  addresses:
    - 192.168.100.150-192.168.100.250 # Modify this range
```

### Changing DNS Domain

1. Update External-DNS annotation pattern in manifests
2. Update CoreDNS Corefile zone in `manifests/dns/coredns.yaml`
3. Update dnsmasq configuration in playbook to match your domain

### Adjusting Replicas

- **Longhorn**: Edit `ansible/roles/k8s_longhorn/tasks/main.yaml` → `defaultClassReplicaCount`
- **Traefik**: Edit `ansible/roles/k8s_traefik/tasks/main.yaml` → `deployment.replicas`
- **CoreDNS**: Edit `manifests/dns/coredns.yaml` → `spec.replicas`

### Changing Dashboard Credentials

Edit `ansible/group_vars/all/secrets.yaml` and update:

```yaml
dashboard_admin_user: your_username
dashboard_admin_password: your_secure_password
```

Then redeploy authentication:

```bash
cd main-infra
ansible-playbook ansible/playbooks/k8s-cluster.yaml \
  --limit k8s-master.lab.dzarpelon.com \
  --start-at-task="Deploy Traefik Ingress Controller"
```

## Troubleshooting

### Pods not getting IPs

- Check Calico pods: `kubectl get pods -n kube-system -l k8s-app=calico-node`
- Verify IPv6 is disabled on nodes (RHEL 10 ARM64 workaround)

### LoadBalancer stuck in Pending

- Check MetalLB pods: `kubectl get pods -n metallb-system`
- Verify IPAddressPool: `kubectl get ipaddresspools -n metallb-system`

### DNS not resolving

- Check CoreDNS pods: `kubectl get pods -n dns-system`
- Test etcd: `kubectl exec -n dns-system etcd-0 -- etcdctl get /skydns --prefix --keys-only`
- Verify External-DNS logs: `kubectl logs -n dns-system -l app=external-dns`

### Traefik dashboard 404

- Access with trailing slash: `http://traefik.lab.dzarpelon.com/dashboard/`
- Or use Host header: `curl -H "Host: traefik.lab.dzarpelon.com" http://<TRAEFIK-IP>/dashboard/`

### Dashboard authentication not working

Verify secrets exist:

```bash
kubectl get secret -n traefik-system traefik-dashboard-auth
kubectl get secret -n longhorn-system longhorn-dashboard-auth
```

Check middleware resources:

```bash
kubectl get middleware -n traefik-system dashboard-auth
kubectl get middleware -n longhorn-system longhorn-auth
```

Verify htpasswd format in secret:

```bash
kubectl get secret -n traefik-system traefik-dashboard-auth -o jsonpath='{.data.users}' | base64 -d
```

## Architecture Decisions

### Why these components?

1. **MetalLB**: Essential for LoadBalancer services in bare-metal environments; alternatives (NodePort) don't provide stable external IPs

2. **Longhorn**: Modern, cloud-native storage built for Kubernetes; simpler than Rook/Ceph for small clusters; provides GUI and easy backup/restore

3. **Custom DNS Stack**: Allows automatic DNS for services without external DNS providers; etcd backend provides consistency; External-DNS enables GitOps-friendly DNS management

4. **Traefik**: Modern, cloud-native ingress with excellent Kubernetes integration; lighter than NGINX Ingress; supports both standard Ingress and custom CRDs; built-in dashboard

5. **Basic Auth for Dashboards**: Simple, secure authentication without additional infrastructure; credentials managed via Ansible variables; htpasswd format compatible with all web browsers

### Deployment Order

The order is critical for dependencies:

1. **Common setup first**: All nodes need base configuration
2. **Python deps early**: Required for Ansible Kubernetes modules
3. **Cluster init**: Master then workers
4. **MetalLB before storage**: LoadBalancer IPs needed for any exposed services
5. **Longhorn before DNS**: etcd needs persistent storage
6. **DNS before Traefik**: Ingress controller benefits from automatic DNS
7. **DNS client last**: Ensures all cluster services are ready before VMs try to use custom DNS

## Files Structure

```text
main-infra/
├── ansible.cfg                          # Ansible configuration
├── ansible/
│   ├── inventory                        # Cluster nodes inventory
│   ├── playbooks/
│   │   └── k8s-cluster.yaml            # Main orchestration playbook
│   └── roles/
│       ├── k8s_common/                  # Base Kubernetes setup
│       ├── k8s_master/                  # Master node initialization
│       ├── k8s_worker/                  # Worker node join
│       ├── k8s_addons/                  # MetalLB deployment
│       ├── k8s_longhorn/                # Longhorn storage
│       ├── k8s_dns/                     # DNS infrastructure
│       ├── k8s_traefik/                 # Traefik ingress
│       └── k8s_destroy/                 # Cleanup tasks
└── manifests/
    ├── dns/                             # DNS stack manifests
    │   ├── namespace.yaml
    │   ├── etcd.yaml
    │   ├── coredns.yaml
    │   └── external-dns.yaml
    ├── ingress/                         # Ingress resources
    │   └── longhorn-dashboard.yaml
    ├── metallb-ippool.yaml              # MetalLB IP pool
    └── metallb-l2.yaml                  # MetalLB L2 advertisement
```

## Next Steps

After successful deployment, you can:

1. Deploy applications using the Longhorn StorageClass for persistence
2. Create Ingress resources that automatically get DNS records
3. Use Traefik's IngressRoute CRD for advanced routing
4. Configure TLS certificates (manual or with cert-manager)
5. Set up monitoring (Prometheus + Grafana)
6. Deploy the HashiStack (Consul, Vault, Nomad)

## Support

For issues or questions:

- Check the troubleshooting section above
- Review Ansible playbook output for specific errors
- Examine pod logs: `kubectl logs -n <namespace> <pod-name>`
- Check events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
