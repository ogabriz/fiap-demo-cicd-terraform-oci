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
  name            = "prometheus-stack"
  repository      = "https://prometheus-community.github.io/helm-charts"
  chart           = "kube-prometheus-stack"
  namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
  version         = "69.3.2"
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
  alerting:
    contactpoints.yaml:
      apiVersion: 1
      contactPoints:
        - orgId: 1
          name: Discord
          receivers:
            - uid: discord
              type: discord
              settings:
                url: "${var.discord_webhook_url}"
                use_discord_username: true
              disableResolveMessage: false
    policies.yaml:
      apiVersion: 1
      policies:
        - orgId: 1
          receiver: Discord
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 4h

alertmanager:
  enabled: true
  config:
    route:
      receiver: "discord"
      group_by:
        - namespace
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - receiver: "null"
          matchers:
            - alertname = "Watchdog"
    receivers:
      - name: "discord"
        discord_configs:
          - webhook_url: "${var.discord_webhook_url}"
            title: '{{ .GroupLabels.alertname }}'
            message: '{{ range .Alerts }}**{{ .Labels.severity }}**: {{ .Annotations.summary }}{{ end }}'
            send_resolved: true
      - name: "null"

additionalPrometheusRulesMap:
  togglemaster-alerts:
    groups:
      - name: togglemaster
        rules:
          - alert: PodCrashLooping
            expr: rate(kube_pod_container_status_restarts_total{namespace="togglemaster"}[5m]) > 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Pod {{ $labels.pod }} em CrashLoop no namespace togglemaster"
          - alert: HighErrorRate
            expr: sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m])) by (ingress) > 0.5
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "Alta taxa de erros 5xx no ingress {{ $labels.ingress }}"
          - alert: HighCPUUsage
            expr: sum(rate(container_cpu_usage_seconds_total{namespace="togglemaster"}[5m])) by (pod) > 0.8
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Pod {{ $labels.pod }} com uso de CPU acima de 80%"
          - alert: PodNotReady
            expr: kube_pod_status_ready{namespace="togglemaster", condition="true"} == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Pod {{ $labels.pod }} nao esta Ready ha 5 minutos"
EOF
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "helm_release" "loki_stack" {
  name            = "loki-stack"
  repository      = "https://grafana.github.io/helm-charts"
  chart           = "loki-stack"
  namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
  version         = "2.10.2"
  timeout         = 900
  force_update    = true
  cleanup_on_fail = true
  replace         = true
  wait            = false

  values = [<<EOF
loki:
  persistence:
    enabled: false
  isDefault: false
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

resource "helm_release" "otel_collector" {
  count      = var.newrelic_license_key != "" ? 1 : 0
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "0.73.1"
  timeout    = 600
  wait       = false

  values = [<<EOF
mode: deployment
config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"
  processors:
    batch:
      timeout: 10s
      send_batch_size: 1024
    memory_limiter:
      check_interval: 5s
      limit_mib: 256
  exporters:
    otlp/newrelic:
      endpoint: "https://otlp.nr-data.net:4317"
      headers:
        api-key: "${var.newrelic_license_key}"
    prometheus:
      endpoint: "0.0.0.0:8889"
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlp/newrelic]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlp/newrelic, prometheus]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlp/newrelic]
service:
  type: ClusterIP
  ports:
    otlp-grpc:
      port: 4317
      targetPort: 4317
      protocol: TCP
    otlp-http:
      port: 4318
      targetPort: 4318
      protocol: TCP
EOF
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "kubectl_manifest" "solidarytech_servicemonitor" {
  yaml_body = <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: solidarytech-services
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: solidarytech
  namespaceSelector:
    matchNames:
      - togglemaster
  endpoints:
    - port: http
      interval: 30s
      path: /health
EOF

  depends_on = [helm_release.prometheus_stack]
}

resource "helm_release" "redis_exporter" {
  name            = "redis-exporter"
  repository      = "https://prometheus-community.github.io/helm-charts"
  chart           = "prometheus-redis-exporter"
  namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
  version         = "6.1.1"
  timeout         = 600
  wait            = false
  force_update    = true
  cleanup_on_fail = true
  replace         = true

  values = [<<EOF
image:
  repository: oliver006/redis_exporter
  tag: v1.61.0
redisAddress: "redis://${var.redis_host}:6379"
serviceMonitor:
  enabled: true
  labels:
    release: prometheus-stack
EOF
  ]

  depends_on = [helm_release.prometheus_stack]
}
