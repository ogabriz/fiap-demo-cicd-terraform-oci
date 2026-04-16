terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "69.3.2"
  timeout         = 1200
  force_update    = true
  cleanup_on_fail = true
  replace         = true
  wait            = false

  values = [<<EOF
grafana:
  enabled: true
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
    datasources:
      enabled: true
      label: grafana_datasource
      labelValue: "1"
  additionalDataSources:
    - name: Prometheus
      uid: prometheus
      type: prometheus
      access: proxy
      url: http://prometheus-stack-kube-prom-prometheus.monitoring:9090
      version: 1
      isDefault: true
    - name: Loki
      uid: loki
      type: loki
      access: proxy
      url: http://loki-stack.monitoring:3100
      version: 1
      isDefault: false
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/oci-load-balancer-shape: flexible
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
EOF
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "helm_release" "loki_stack" {
  name       = "loki-stack"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "2.10.2"
  timeout         = 600
  force_update    = true
  cleanup_on_fail = true
  replace         = true

  values = [<<EOF
loki:
  persistence:
    enabled: true
    size: 10Gi
promtail:
  enabled: true
  config:
    clients:
      - url: http://loki-stack.monitoring:3100/loki/api/v1/push
EOF
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "kubernetes_config_map_v1" "grafana_dashboard_custom" {
  metadata {
    name      = "grafana-dashboard-custom"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "custom-dashboard.json" = file("${path.module}/dashboards/custom-dashboard.json")
  }

  depends_on = [helm_release.prometheus_stack]
}

resource "kubectl_manifest" "nginx_ingress_servicemonitor" {
  yaml_body = <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nginx-ingress-controller
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  namespaceSelector:
    any: true
  endpoints:
    - port: metrics
      interval: 30s
EOF

  depends_on = [helm_release.prometheus_stack]
}

resource "helm_release" "redis_exporter" {
  name       = "redis-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-redis-exporter"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "6.1.1"
  timeout    = 600
  wait       = false
  force_update    = true
  cleanup_on_fail = true
  replace         = true

  values = [<<EOF
image:
  repository: oliver006/redis_exporter
  tag: v1.63.0
redisAddress: "redis://${var.redis_host}:6379"
serviceMonitor:
  enabled: true
  labels:
    release: prometheus-stack
EOF
  ]

  depends_on = [helm_release.prometheus_stack]
}
