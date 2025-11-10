# HTTPS/TLS Configuration Guide for Applications

This guide shows how to configure HTTPS for your applications using Traefik and cert-manager.

## Prerequisites

- Traefik ingress controller deployed
- cert-manager with ClusterIssuers configured
- Wildcard certificate `lab-wildcard-tls` available (or create dedicated certificates)

## Quick Start - Using Wildcard Certificate

The simplest approach is to use the pre-created wildcard certificate:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.lab.dzarpelon.com
spec:
  entryPoints:
  - websecure  # HTTPS (port 443)
  routes:
  - match: Host(`myapp.lab.dzarpelon.com`)
    kind: Rule
    services:
    - name: my-app-service
      port: 80
  tls:
    secretName: lab-wildcard-tls  # Uses existing wildcard cert
```

## Copy Wildcard Certificate to Your Namespace

If your app is not in `traefik-system` or `longhorn-system`, you need to copy the certificate:

```bash
# Copy the wildcard certificate to your namespace
kubectl get secret lab-wildcard-tls -n traefik-system -o yaml | \
  sed 's/namespace: traefik-system/namespace: my-namespace/' | \
  kubectl apply -f -
```

Or create it automatically with a Certificate resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-wildcard-tls
  namespace: my-namespace
spec:
  secretName: lab-wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - "*.lab.dzarpelon.com"
  - "lab.dzarpelon.com"
```

## HTTP to HTTPS Redirect

Always redirect HTTP to HTTPS:

```yaml
---
# Middleware for redirect
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: default
spec:
  redirectScheme:
    scheme: https
    permanent: true

---
# HTTP route (redirects to HTTPS)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app-http
  namespace: default
spec:
  entryPoints:
  - web  # HTTP (port 80)
  routes:
  - match: Host(`myapp.lab.dzarpelon.com`)
    kind: Rule
    middlewares:
    - name: redirect-https
    services:
    - name: my-app-service
      port: 80

---
# HTTPS route
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app-https
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.lab.dzarpelon.com
spec:
  entryPoints:
  - websecure  # HTTPS (port 443)
  routes:
  - match: Host(`myapp.lab.dzarpelon.com`)
    kind: Rule
    services:
    - name: my-app-service
      port: 80
  tls:
    secretName: lab-wildcard-tls
```

## Dedicated Certificate (Not Wildcard)

For apps that need their own certificate:

```yaml
# Create the certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: default
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - myapp.lab.dzarpelon.com
  duration: 2160h  # 90 days
  renewBefore: 720h  # Renew 30 days before expiry

---
# Use the certificate
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.lab.dzarpelon.com
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`myapp.lab.dzarpelon.com`)
    kind: Rule
    services:
    - name: my-app-service
      port: 80
  tls:
    secretName: myapp-tls  # Uses dedicated certificate
```

## Standard Kubernetes Ingress (Alternative)

You can also use standard Kubernetes Ingress instead of Traefik IngressRoute:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.lab.dzarpelon.com
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - myapp.lab.dzarpelon.com
    secretName: lab-wildcard-tls
  rules:
  - host: myapp.lab.dzarpelon.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 80
```

## With Path-Based Routing

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app-paths
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.lab.dzarpelon.com
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`myapp.lab.dzarpelon.com`) && PathPrefix(`/api`)
    kind: Rule
    services:
    - name: api-service
      port: 8080
  - match: Host(`myapp.lab.dzarpelon.com`) && PathPrefix(`/web`)
    kind: Rule
    services:
    - name: web-service
      port: 80
  tls:
    secretName: lab-wildcard-tls
```

## With Middlewares (Auth, Headers, etc.)

```yaml
---
# Basic Authentication
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: default
spec:
  basicAuth:
    secret: auth-secret

---
# Add Security Headers
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: default
spec:
  headers:
    customResponseHeaders:
      X-Frame-Options: "SAMEORIGIN"
      X-Content-Type-Options: "nosniff"
      X-XSS-Protection: "1; mode=block"
    sslRedirect: true
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true

---
# Use middlewares
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app-secure
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: secure.lab.dzarpelon.com
spec:
  entryPoints:
  - websecure
  routes:
  - match: Host(`secure.lab.dzarpelon.com`)
    kind: Rule
    middlewares:
    - name: basic-auth
    - name: security-headers
    services:
    - name: my-app-service
      port: 80
  tls:
    secretName: lab-wildcard-tls
```

## Testing Your HTTPS Setup

```bash
# Check if DNS is registered
dig @192.168.100.101 -p 30053 myapp.lab.dzarpelon.com

# Test HTTP (should redirect to HTTPS)
curl -I http://myapp.lab.dzarpelon.com

# Test HTTPS
curl -I https://myapp.lab.dzarpelon.com

# Check certificate details
openssl s_client -connect myapp.lab.dzarpelon.com:443 -servername myapp.lab.dzarpelon.com < /dev/null 2>/dev/null | openssl x509 -noout -text

# Check certificate issuer
kubectl get certificate -A
kubectl describe certificate lab-wildcard-tls -n default
```

## Troubleshooting

### Certificate not working

```bash
# Check if certificate is ready
kubectl get certificate -n default
kubectl describe certificate myapp-cert -n default

# Check certificate secret
kubectl get secret myapp-tls -n default

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager -f

# Check for challenges
kubectl get challenge -A
```

### DNS not resolving

```bash
# Check External-DNS logs
kubectl logs -n dns-system deploy/external-dns

# Check etcd for records
kubectl exec -n dns-system etcd-0 -- etcdctl get --prefix /skydns/com/dzarpelon/lab
```

### Traefik not routing

```bash
# Check Traefik logs
kubectl logs -n traefik-system deploy/traefik -f

# Check IngressRoute status
kubectl get ingressroute -A
kubectl describe ingressroute my-app -n default
```

## Best Practices

1. **Use wildcard certificates** for most apps to avoid rate limits
2. **Always redirect HTTP to HTTPS** using middleware
3. **Use External-DNS annotations** for automatic DNS registration
4. **Add security headers** for production apps
5. **Monitor certificate expiry** (cert-manager handles renewal automatically)
6. **Use staging issuer** for testing to avoid Let's Encrypt rate limits

## Example: Complete Application with HTTPS

See `/main-infra/manifests/ingress/example-app-https.yaml` for complete examples including:
- Standard Kubernetes Ingress
- Traefik IngressRoute
- HTTP to HTTPS redirect
- Basic authentication
- Dedicated certificates
- Path-based routing
