resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.1"

  values = [<<EOF
server:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/oci-load-balancer-shape: flexible
  extraArgs:
    - --insecure
EOF
  ]
}

resource "kubectl_manifest" "argocd_apps" {
  for_each = toset([
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service"
  ])

  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${each.key}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ealvesjr90/fiap-demo-cicd-terraform-oci.git
    targetRevision: main
    path: ${each.key}/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: togglemaster
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

  depends_on = [helm_release.argocd]
}