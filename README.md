# HashiStack Lab Environment

This repository contains automated infrastructure deployment for a complete Kubernetes cluster with production-ready add-ons, designed to serve as a foundation for HashiCorp stack deployment (Consul, Vault).

## 📋 Overview

This project provides a fully automated Kubernetes infrastructure with:

- **Base Kubernetes Cluster**: 4-node cluster (1 master + 3 workers) running on RHEL 10 ARM64
- **Container Networking**: Calico CNI for pod networking
- **Load Balancing**: MetalLB for bare-metal LoadBalancer services
- **Distributed Storage**: Longhorn for persistent volumes with replication
- **DNS Infrastructure**: Custom DNS stack (etcd + CoreDNS + External-DNS) for automatic service discovery
- **Ingress Controller**: Traefik with dashboard and TLS support
- **Security**: Basic authentication for all dashboards

## 🏗️ Repository Structure

```text
hashistack/
├── README.md                    # This file
└── main-infra/                  # Kubernetes infrastructure
    ├── ansible/                 # Ansible automation
    │   ├── inventory           # Cluster nodes definition
    │   ├── playbooks/          # Main orchestration playbooks
    │   │   └── k8s-cluster.yaml
    │   ├── group_vars/         # Configuration variables
    │   │   └── all/
    │   │       ├── secrets.yaml.example
    │   │       └── secrets.yaml (gitignored)
    │   └── roles/              # Ansible roles for each component
    │       ├── k8s_common/     # Base Kubernetes setup
    │       ├── k8s_master/     # Master node configuration
    │       ├── k8s_worker/     # Worker node configuration
    │       ├── k8s_addons/     # MetalLB deployment
    │       ├── k8s_longhorn/   # Longhorn storage
    │       ├── k8s_dns/        # DNS infrastructure
    │       ├── k8s_traefik/    # Traefik ingress
    │       └── k8s_destroy/    # Cleanup tasks
    └── manifests/              # Kubernetes manifests
        ├── dns/                # DNS stack manifests
        ├── ingress/            # Ingress resources
        └── metallb-*.yaml      # MetalLB configuration
```

## 🚀 Services Deployed

### 1. Kubernetes Cluster

- **Version**: v1.31.13
- **Platform**: RHEL 10 ARM64
- **Nodes**: 1 master + 3 workers
- **CNI**: Calico v3.26.1
- **CRI**: CRI-O

### 2. MetalLB Load Balancer

- **Version**: v0.14.9
- **Mode**: Layer 2
- **IP Pool**: 192.168.100.150-250
- **Purpose**: Provides LoadBalancer service type support in bare-metal environments

### 3. Longhorn Distributed Storage

- **Deployment**: Helm chart
- **Replication**: 2 replicas
- **Features**: Dynamic provisioning, snapshots, backups, web UI
- **Dashboard**: http://longhorn.lab.dzarpelon.com (authenticated)

### 4. DNS Infrastructure

- **etcd**: v3.5.15 (3-member cluster with persistent storage)
- **CoreDNS**: v1.11.1 (2 replicas, NodePort 30053)
- **External-DNS**: v0.14.2 (automatic DNS record management)
- **Domain**: \*.lab.dzarpelon.com
- **Purpose**: Automatic DNS resolution for services and ingresses

### 5. Traefik Ingress Controller

- **Version**: v3.5.x
- **Deployment**: Helm chart, 2 replicas
- **Features**: HTTP/HTTPS routing, dashboard, automatic service discovery
- **Dashboard**: http://traefik.lab.dzarpelon.com/dashboard/ (authenticated)

### 6. Dashboard Authentication

- **Method**: HTTP Basic Auth (htpasswd)
- **Protected Dashboards**: Traefik, Longhorn
- **Credentials**: Configured in `main-infra/ansible/group_vars/all/secrets.yaml`

## 📦 Prerequisites

### Controller Machine (where you run Ansible)

- Ansible 2.9+
- SSH access to all cluster nodes
- Python 3.x with pip
- kubectl (for verification)
- Private SSH key at `~/.ssh/dzarpelon`

### Cluster Nodes

- RHEL 10 or compatible Linux distribution
- SSH access with passwordless sudo
- Network connectivity between all nodes
- Static IP addresses

### Network Requirements

- Master node: 192.168.100.101
- Worker nodes: 192.168.100.102-104
- LoadBalancer pool: 192.168.100.150-250

## 🎯 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/dzarpelon/hashistack.git
cd hashistack/main-infra
```

### 2. Configure Credentials

```bash
cd ansible/group_vars/all
cp secrets.yaml.example secrets.yaml
# Edit secrets.yaml with your desired credentials
vim secrets.yaml
```

### 3. Configure Inventory

Edit `ansible/inventory` to match your node IPs:

```ini
[k8s_master]
k8s-master.lab.dzarpelon.com ansible_host=192.168.100.101

[k8s_workers]
k8s-1.lab.dzarpelon.com ansible_host=192.168.100.102
k8s-2.lab.dzarpelon.com ansible_host=192.168.100.103
k8s-3.lab.dzarpelon.com ansible_host=192.168.100.104
```

### 4. Deploy Complete Stack

```bash
cd main-infra
ansible-playbook ansible/playbooks/k8s-cluster.yaml
```

**Duration**: ~15-20 minutes for complete deployment

### 5. Configure DNS (Optional - for controller)

For macOS:

```bash
sudo mkdir -p /etc/resolver
echo "nameserver 192.168.100.101" | sudo tee /etc/resolver/lab.dzarpelon.com
echo "port 30053" | sudo tee -a /etc/resolver/lab.dzarpelon.com
```

For Linux, configure dnsmasq or NetworkManager accordingly.

## 🔍 Verification

```bash
# Check cluster status
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check LoadBalancer IP
kubectl get svc -n traefik-system traefik

# Test DNS resolution
dig @192.168.100.101 -p 30053 traefik.lab.dzarpelon.com

# Access dashboards (requires credentials from secrets.yaml)
# Traefik: http://traefik.lab.dzarpelon.com/dashboard/
# Longhorn: http://longhorn.lab.dzarpelon.com
```

## 🗑️ Cleanup

### Destroy Complete Environment

```bash
cd main-infra
ansible-playbook ansible/playbooks/k8s-cluster.yaml -e k8s_state=absent
```

This will:

- Drain and delete all nodes
- Stop kubelet and remove Kubernetes components
- Clean up network configurations
- Remove all persistent data

**⚠️ Warning**: This is destructive and will delete all data, including Longhorn volumes.

## 📚 Documentation

For detailed documentation on each component, architecture decisions, customization options, and troubleshooting:

- **Main Infrastructure**: [main-infra/README.md](main-infra/README.md)

## 🔧 Customization

### Change IP Pool

Edit `main-infra/manifests/metallb-ippool.yaml`:

```yaml
spec:
  addresses:
    - 192.168.100.150-192.168.100.250 # Modify this range
```

### Change DNS Domain

Update domain references in:

- CoreDNS Corefile configuration
- External-DNS annotations
- dnsmasq configuration in playbook

### Update Dashboard Credentials

Edit `main-infra/ansible/group_vars/all/secrets.yaml` and redeploy:

```bash
ansible-playbook ansible/playbooks/k8s-cluster.yaml \
  --limit k8s-master.lab.dzarpelon.com \
  --start-at-task="Deploy Traefik Ingress Controller"
```

## 🛠️ Common Operations

### Check Component Status

```bash
# MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspools -n metallb-system

# Longhorn
kubectl get pods -n longhorn-system
kubectl get storageclass

# DNS
kubectl get pods -n dns-system

# Traefik
kubectl get pods -n traefik-system
kubectl get ingress -A
```

### View Dashboard Credentials

```bash
cat main-infra/ansible/group_vars/all/secrets.yaml
```

### Test Authentication

```bash
# Should return 401 Unauthorized
curl -i http://traefik.lab.dzarpelon.com/dashboard/

# With credentials
curl -u admin:YOUR_PASSWORD http://traefik.lab.dzarpelon.com/dashboard/
```

## 🎓 Architecture Highlights

### Why These Components?

1. **MetalLB**: Essential for LoadBalancer services in bare-metal without cloud provider integration
2. **Longhorn**: Modern cloud-native storage, simpler than Rook/Ceph, excellent for small clusters
3. **Custom DNS Stack**: Enables GitOps-friendly automatic DNS without external DNS providers
4. **Traefik**: Cloud-native, lighter than NGINX, excellent Kubernetes integration
5. **Calico**: Proven CNI with good performance and NetworkPolicy support

### Deployment Order

The automation follows a specific order for dependencies:

1. **Common setup**: Base configuration on all nodes
2. **Python dependencies**: Required for Ansible Kubernetes modules
3. **Master initialization**: Including Calico CNI installation
4. **Worker join**: Serial to avoid race conditions
5. **MetalLB**: Load balancer before other services
6. **Longhorn**: Storage before DNS (etcd needs persistence)
7. **DNS**: Before ingress (benefits from automatic DNS)
8. **Traefik**: Last, with automatic DNS registration
9. **DNS client config**: Ensures all services are ready

## 🚧 Future Roadmap

The following enhancements are planned in priority order:

### Phase 1: Security (v1.1.0)

- [ ] **TLS/HTTPS with cert-manager**: Implement automated certificate management
  - Install cert-manager
  - Configure Let's Encrypt or self-signed CA for lab environment
  - Update Traefik IngressRoutes for HTTPS
  - Secure all dashboards (Traefik, Longhorn)

### Phase 2: Observability (v1.2.0)

- [ ] **Monitoring stack (Prometheus + Grafana)**: Establish baseline metrics and alerting
  - Deploy Prometheus Operator
  - Configure ServiceMonitors for all components
  - Create Grafana dashboards for Kubernetes, MetalLB, Longhorn, Traefik
  - Set up alerting rules

### Phase 3: HashiCorp Vault (v1.3.0)

- [ ] **HashiCorp Vault deployment**: Centralized secrets management
  - Deploy Vault with Integrated Storage (Raft) or leverage existing etcd cluster
  - Configure Vault HA with 3 instances
  - Enable Kubernetes authentication
  - Migrate dashboard credentials from `secrets.yaml` to Vault
  - Configure PKI engine for internal certificate management

### Phase 4: HashiCorp Consul (v1.4.0)

- [ ] **HashiCorp Consul deployment**: Service mesh and enhanced service discovery
  - Deploy Consul with service mesh enabled
  - Configure mTLS between pods using Consul Connect
  - Integrate with Vault for certificate management
  - Enhanced health checking and service discovery (complementing existing DNS)

### Phase 5: Centralized Logging (v1.5.0)

- [ ] **Logging stack (Loki or ELK)**: Complete observability with log aggregation
  - Deploy Loki or Elasticsearch stack
  - Configure log collection from all pods
  - Create log correlation dashboards
  - Integrate with Grafana for unified observability

### Phase 6: GitOps (v2.0.0)

- [ ] **GitOps with ArgoCD or Flux**: Declarative infrastructure management
  - Deploy ArgoCD or Flux
  - Migrate all manifests to Git-based deployment
  - Implement automated sync and drift detection
  - Establish proper RBAC and audit trails

### Architecture Notes

- **No Nomad**: Nomad is excluded as it's redundant with Kubernetes for orchestration
- **Vault Storage**: Using Integrated Storage (Raft) instead of deprecated Consul backend
- **Consul Role**: Service mesh and enhanced discovery, not as Vault storage
- **TLS Independence**: cert-manager provides TLS without requiring Vault first

## 🤝 Contributing

This is a personal lab environment, but suggestions and improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

This project is for educational and lab purposes.

## 🙋 Support

For issues or questions:

- Check the detailed documentation in [main-infra/README.md](main-infra/README.md)
- Review the troubleshooting section
- Check Ansible playbook output for errors

## 🏷️ Version

**Current Version**: v1.0.0.1 - Updated Roadmap

**Last Updated**: November 8, 2025

---

**Built with** ❤️ **for learning HashiCorp technologies**
