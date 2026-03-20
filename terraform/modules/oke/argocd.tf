resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.1"

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  set {
    name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape"
    value = "flexible"
  }
}

resource "kubernetes_manifest" "argocd_apps" {
  for_each = toset([
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service"
  ])

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.key
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/ealvesjr90/fiap-demo-cicd-terraform-oci.git"
        targetRevision = "main"
        path           = "${each.key}/k8s"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "togglemaster"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}