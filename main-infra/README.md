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

#### 5. **cert-manager** - Automated Certificate Management

- **Version**: v1.15.3 (⚠️ Note: v1.19.x has CNI compatibility issues with Calico v3.26.1)
- **Deployment**: Helm chart
- **Why**: Automates X.509 certificate management in Kubernetes, integrates with Let's Encrypt for browser-trusted certificates
- **Features**:
  - Automated certificate issuance and renewal
  - DNS-01 challenge support (works with private IPs)
  - Wildcard certificate support
  - Integration with Cloudflare DNS
  - Let's Encrypt staging and production issuers

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

### Secrets Configuration

The automation requires configuration of sensitive credentials before deployment.

#### 1. Copy the Example Secrets File

```bash
cd main-infra/ansible/group_vars/all
cp secrets.yaml.example secrets.yaml
```

#### 2. Configure Dashboard Authentication

Edit `secrets.yaml` to set basic authentication credentials for dashboards:

```yaml
dashboard_admin_user: admin
dashboard_admin_password: YOUR_SECURE_PASSWORD
```

**Protected Dashboards**:

- Traefik Dashboard: `https://traefik.lab.dzarpelon.com/dashboard/`
- Longhorn Dashboard: `https://longhorn.lab.dzarpelon.com/`

#### 3. Configure cert-manager for TLS Certificates

##### Create Cloudflare API Token

1. Log in to Cloudflare Dashboard: https://dash.cloudflare.com/profile/api-tokens
2. Click **Create Token**
3. Use template: **Edit zone DNS**
4. Permissions: `Zone - DNS - Edit`
5. Zone Resources: `Include - Specific zone - dzarpelon.com`
6. Create token and copy it (shown only once!)

##### Update secrets.yaml

Add cert-manager configuration:

```yaml
# Email for Let's Encrypt certificate notifications
certmanager_email: "your-email@dzarpelon.com"

# Cloudflare API Token for DNS-01 ACME challenge
certmanager_cloudflare_api_token: "YOUR_CLOUDFLARE_API_TOKEN"
```

**Complete secrets.yaml example**:

```yaml
# Dashboard Authentication
dashboard_admin_user: admin
dashboard_admin_password: P@ssw0rd!

# cert-manager Configuration
certmanager_email: "admin@dzarpelon.com"
certmanager_cloudflare_api_token: "your-cloudflare-api-token-here"
```

**Note**: The `secrets.yaml` file is gitignored and will not be committed to version control.

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

# Check cert-manager
kubectl get pods -n cert-manager
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-staging
kubectl describe clusterissuer letsencrypt-prod

# Check wildcard certificate
kubectl get certificate -n traefik-system
kubectl describe certificate lab-wildcard-tls -n traefik-system

# Test DNS resolution
dig @192.168.100.101 -p 30053 traefik.lab.dzarpelon.com
dig @192.168.100.101 -p 30053 longhorn.lab.dzarpelon.com
```

### Verify TLS Certificates

```bash
# Check if certificate is ready
kubectl get certificate -n traefik-system lab-wildcard-tls

# View certificate details
kubectl describe certificate lab-wildcard-tls -n traefik-system

# Check the secret containing the certificate
kubectl get secret lab-wildcard-tls -n traefik-system

# Test HTTPS access (should work without warnings if using production issuer)
curl -v https://traefik.lab.dzarpelon.com/dashboard/
curl -v https://longhorn.lab.dzarpelon.com/

# Check certificate details
openssl s_client -connect traefik.lab.dzarpelon.com:443 -servername traefik.lab.dzarpelon.com < /dev/null 2>/dev/null | openssl x509 -noout -text
```

### Access Protected Dashboards

Both dashboards are protected with basic authentication and served over HTTPS. Use the credentials configured in `ansible/group_vars/all/secrets.yaml`.

```bash
# HTTP requests are automatically redirected to HTTPS
curl -I http://traefik.lab.dzarpelon.com/dashboard/
# Should return: HTTP/1.1 301 Moved Permanently

# HTTPS requires authentication (should return 401 Unauthorized)
curl -k -I https://traefik.lab.dzarpelon.com/dashboard/

# Access with credentials over HTTPS
curl -k -u admin:'YOUR_PASSWORD' https://traefik.lab.dzarpelon.com/dashboard/
curl -k -u admin:'YOUR_PASSWORD' https://longhorn.lab.dzarpelon.com/

# Or open in browser (credentials will be prompted):
# - Traefik Dashboard: https://traefik.lab.dzarpelon.com/dashboard/
# - Longhorn Dashboard: https://longhorn.lab.dzarpelon.com/
```

**Note**: Use `-k` flag with curl to skip certificate verification if using staging certificates. Production certificates from Let's Encrypt are trusted by default.

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

### Certificate not being issued

Check cert-manager pods:

```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager
kubectl logs -n cert-manager -l app=webhook
```

Check ClusterIssuer status:

```bash
kubectl describe clusterissuer letsencrypt-staging
kubectl describe clusterissuer letsencrypt-prod
```

Check Certificate status:

```bash
kubectl describe certificate lab-wildcard-tls -n traefik-system
kubectl get certificaterequest -n traefik-system
kubectl describe certificaterequest -n traefik-system
```

Check Challenge resources (DNS-01):

```bash
kubectl get challenge -A
kubectl describe challenge -A
```

Common issues:

- **Invalid Cloudflare API token**: Verify token has DNS edit permissions for dzarpelon.com
- **DNS propagation delay**: DNS-01 challenge can take 2-10 minutes
- **Rate limiting**: Let's Encrypt production has rate limits (50 certs/week per domain). Use staging for testing
- **Wrong email**: Check certmanager_email in secrets.yaml

### HTTPS not working / Certificate warnings

If using **staging certificates** (default):

- Staging certs are NOT trusted by browsers
- You'll see certificate warnings - this is expected
- Use `-k` flag with curl
- To switch to production: Set `k8s_certmanager_use_staging: false` in role defaults and redeploy

If using **production certificates**:

- Verify certificate is ready: `kubectl get certificate -n traefik-system`
- Check certificate issuer: Should show "letsencrypt-prod"
- Verify DNS resolution: Certificate must match the domain you're accessing
- Clear browser cache if seeing old certificate

Check certificate details:

```bash
# View certificate info
openssl s_client -connect traefik.lab.dzarpelon.com:443 -servername traefik.lab.dzarpelon.com < /dev/null 2>/dev/null | openssl x509 -noout -text | grep -A2 "Issuer"

# For staging: Issuer should be "(STAGING)"
# For production: Issuer should be "Let's Encrypt"
```

### Cloudflare DNS challenge failing

Check External-DNS logs:

```bash
kubectl logs -n cert-manager -l app=cert-manager | grep -i cloudflare
```

Verify Cloudflare secret:

```bash
kubectl get secret cloudflare-api-token -n cert-manager
```

Test Cloudflare API token manually:

```bash
# Replace with your token
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer YOUR_CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

Ensure token has permissions:

- Zone - DNS - Edit
- Include - Specific zone - dzarpelon.com

## Architecture Decisions

### Why these components?

1. **MetalLB**: Essential for LoadBalancer services in bare-metal environments; alternatives (NodePort) don't provide stable external IPs

2. **Longhorn**: Modern, cloud-native storage built for Kubernetes; simpler than Rook/Ceph for small clusters; provides GUI and easy backup/restore

3. **Custom DNS Stack**: Allows automatic DNS for services without external DNS providers; etcd backend provides consistency; External-DNS enables GitOps-friendly DNS management

4. **Traefik**: Modern, cloud-native ingress with excellent Kubernetes integration; lighter than NGINX Ingress; supports both standard Ingress and custom CRDs; built-in dashboard

5. **Basic Auth for Dashboards**: Simple, secure authentication without additional infrastructure; credentials managed via Ansible variables; htpasswd format compatible with all web browsers

6. **cert-manager + Let's Encrypt**: Automated certificate management with DNS-01 challenge; browser-trusted certificates via Let's Encrypt; supports wildcard certificates; automatic renewal before expiry

### Certificate Strategy

**Current (v1.1.0): Let's Encrypt + Cloudflare DNS-01**

- Public-facing dashboards use Let's Encrypt certificates
- DNS-01 challenge allows certificates for internal IPs (no public access needed)
- Wildcard certificate (`*.lab.dzarpelon.com`) covers all services
- Automatic renewal 30 days before expiry
- Browser-trusted certificates (no warnings with production issuer)

**Future (v1.3.0+): Hybrid with Vault PKI**

- Let's Encrypt: User-facing dashboards (90-day certificates)
- Vault PKI: Internal services and service mesh (short-lived certificates: hours to days)
- Best of both worlds: Public trust + fine-grained internal control

### Deployment Order

The order is critical for dependencies:

1. **Common setup first**: All nodes need base configuration
2. **Python deps early**: Required for Ansible Kubernetes modules
3. **Cluster init**: Master then workers
4. **MetalLB before storage**: LoadBalancer IPs needed for any exposed services
5. **Longhorn before DNS**: etcd needs persistent storage
6. **DNS before Traefik**: Ingress controller benefits from automatic DNS
7. **Traefik before cert-manager**: TLS certificates require ingress to be configured
8. **cert-manager after Traefik**: Updates existing IngressRoutes/Ingresses with TLS
9. **DNS client last**: Ensures all cluster services are ready before VMs try to use custom DNS

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
