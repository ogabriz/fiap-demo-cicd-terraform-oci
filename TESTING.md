# Guia Completo de Testes e Validacao — SolidaryTech na OCI

Este guia cobre **todos os testes** necessarios para validar a plataforma SolidaryTech
rodando na Oracle Cloud Infrastructure (OCI) com o cluster OKE **Hackathon-oke**.

---

## Pre-requisitos

- OCI CLI configurado (`~/.oci/config`)
- `kubectl` instalado e configurado
- `jq` instalado (para formatar JSON)
- Acesso ao compartment OCI do projeto

### 1. Configurar kubectl para o cluster Hackathon-oke

```bash
# Obter kubeconfig do cluster OKE
oci ce cluster create-kubeconfig \
  --cluster-id <OKE_CLUSTER_ID> \
  --file ~/.kube/config \
  --region sa-saopaulo-1 \
  --token-version 2.0.0

# Verificar conexao com o cluster
kubectl get nodes
kubectl get namespaces
```

> **Dica:** O `OKE_CLUSTER_ID` pode ser obtido via:
> ```bash
> cd terraform && terraform output oke_cluster_id
> ```

### 2. Obter o IP do Load Balancer (Ingress)

Todas as chamadas de API usam o IP do Ingress Controller:

```bash
export LB_IP=$(kubectl get ingress togglemaster-ingress -n togglemaster \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"
```

> Se o IP estiver vazio, o Ingress Controller pode nao estar pronto ainda.
> Verifique: `kubectl get svc -n ingress-nginx`

---

## 3. Deploy Inicial da Infraestrutura In-Cluster

PostgreSQL e Redis rodam como pods dentro do cluster OKE (nao em VMs externas).
O Terraform provisiona o cluster, VCN e recursos OCI; os manifests K8s sao aplicados manualmente ou via ArgoCD.

### 3.1 Criar Secret do OCIR (obrigatorio)

Os servicos usam imagens privadas do OCI Container Registry (`hackathon-repo/*`).
O Kubernetes precisa de um `docker-registry` secret para fazer pull:

```bash
# Substituir os valores:
#   TENANCY_NAMESPACE = namespace do tenancy (ex: grqkmwwimskh)
#   OCI_USERNAME      = usuario OCI (ex: oracleidentitycloudservice/seu@email.com)
#   AUTH_TOKEN         = Auth Token gerado em: OCI Console > Identity > Users > Auth Tokens

kubectl create namespace togglemaster --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ocir-secret \
  --docker-server=sa-saopaulo-1.ocir.io \
  --docker-username="TENANCY_NAMESPACE/OCI_USERNAME" \
  --docker-password="AUTH_TOKEN" \
  --docker-email=noreply@oci.com \
  -n togglemaster --dry-run=client -o yaml | kubectl apply -f -
```

### 3.2 Deploy PostgreSQL e Redis

> **Nota:** Ambos usam `emptyDir` (sem PVC). Dados persistem enquanto o pod existir.
> O CSI driver OCI Block Volume pode nao estar disponivel em clusters Free Tier.

```bash
# Limpar deployments antigos (se houver)
kubectl delete deployment postgres redis -n togglemaster --ignore-not-found
kubectl delete pvc postgres-pvc redis-pvc -n togglemaster --ignore-not-found

# Aplicar manifests
kubectl apply -f k8s-infra/postgres.yaml
kubectl apply -f k8s-infra/redis.yaml

# Aguardar pods ficarem prontos
kubectl rollout status deployment/postgres -n togglemaster --timeout=180s
kubectl rollout status deployment/redis -n togglemaster --timeout=180s
```

### 3.3 Inicializar bancos de dados

```bash
kubectl delete job db-init-ngo db-init-donation -n togglemaster --ignore-not-found
kubectl apply -f k8s-infra/db-init-job.yaml
kubectl wait --for=condition=complete job/db-init-ngo -n togglemaster --timeout=120s
kubectl wait --for=condition=complete job/db-init-donation -n togglemaster --timeout=120s
```

### 3.4 Deploy dos servicos

```bash
kubectl apply -f k8s-common/ingress.yaml
kubectl apply -f ngo-service/k8s/manifests.yaml
kubectl apply -f donation-service/k8s/manifests.yaml
kubectl apply -f volunteer-service/k8s/manifests.yaml
```

### 3.5 Verificar status

```bash
kubectl get pods -n togglemaster
# Resultado esperado: todos os pods em Running
# Os servicos ngo-service e donation-service tem initContainer que aguarda o postgres
# E normal ficarem em Init:0/1 por alguns segundos ate o postgres responder

# Se algum pod estiver em ImagePullBackOff → verifique o ocir-secret (secao 3.1)
# Se algum pod estiver em ImageInspectError → imagem precisa de nome qualificado
#   (ex: docker.io/library/postgres:15-alpine e NAO postgres:15-alpine)
```

---

## 4. Validar Infraestrutura Terraform

```bash
cd terraform

# Listar recursos provisionados
terraform state list

# Outputs importantes
terraform output oke_cluster_id
terraform output queue_id
terraform output queue_messages_endpoint
terraform output nosql_table_id
```

Recursos esperados:
- **VCN:** Hackathon-vcn (10.0.0.0/16)
- **Cluster OKE:** Hackathon-oke (versao K8s dinamica — ultima disponivel)
- **Node Pool:** Hackathon-nodepool (VM.Standard.A1.Flex, 2 OCPUs, 16 GB)
- **OCIR:** hackathon-repo/ngo-service, hackathon-repo/donation-service, hackathon-repo/volunteer-service (registros privados)
- **OCI Queue:** fila para donation-service
- **OCI NoSQL:** togglemaster_table para volunteer-service
- **Observability:** Prometheus + Grafana + Loki + AlertManager + Redis Exporter
- **ArgoCD:** GitOps para 3 servicos

---

## 5. Health Checks dos Servicos

```bash
export LB_IP=$(kubectl get ingress togglemaster-ingress -n togglemaster \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# NGO Service (Python/Flask — porta 8081)
curl -s http://$LB_IP/ngos/health | jq .
# Esperado: {"status": "ok", "service": "ngo-service"}

# Donation Service (Go — porta 8082)
curl -s http://$LB_IP/donations/health | jq .
# Esperado: {"status": "healthy", "service": "donation-service"}

# Volunteer Service (Python/Flask — porta 8083)
curl -s http://$LB_IP/volunteers/health | jq .
# Esperado: {"status": "ok", "service": "volunteer-service"}
```

---

## 6. Testar NGO Service (PostgreSQL)

O ngo-service gerencia ONGs usando PostgreSQL. Campos obrigatorios: `name`, `email`, `cause`, `city`.

### 6.1 Criar uma ONG

```bash
curl -X POST http://$LB_IP/ngos/ngos \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ONG Teste SolidaryTech",
    "email": "teste@solidarytech.com",
    "cause": "Educacao",
    "city": "Sao Paulo"
  }' | jq .
# Esperado: HTTP 201 com JSON contendo id, name, email, cause, city, created_at
```

### 6.2 Listar ONGs

```bash
curl -s http://$LB_IP/ngos/ngos | jq .
# Esperado: array com ONGs cadastradas (inclui dados seed: Anjos de Patas, Educa Mais)
```

### 6.3 Validar diretamente no PostgreSQL

```bash
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster \
  -- psql -U togglemaster_user -d ngo_db -c "SELECT * FROM ngos;"
```

---

## 7. Testar Donation Service (PostgreSQL + OCI Queue)

O donation-service gerencia doacoes. Campos obrigatorios: `ngo_id`, `amount`, `donor_name`.
Cada doacao e salva no PostgreSQL e publicada na OCI Queue (se configurada).

### 7.1 Criar uma Doacao

```bash
curl -X POST http://$LB_IP/donations/donations \
  -H "Content-Type: application/json" \
  -d '{
    "ngo_id": 1,
    "amount": 150.00,
    "donor_name": "Doador Teste"
  }' | jq .
# Esperado: HTTP 201 com JSON contendo id, ngo_id, amount, donor_name, status, created_at
```

### 7.2 Listar Doacoes

```bash
curl -s http://$LB_IP/donations/donations | jq .
```

### 7.3 Validar no PostgreSQL

```bash
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster \
  -- psql -U togglemaster_user -d donation_db -c "SELECT * FROM donations ORDER BY id DESC;"
```

### 7.4 Validar OCI Queue (mensagens enviadas)

```bash
# Obter queue_id do Terraform
QUEUE_ID=$(terraform -chdir=terraform output -raw queue_id)

# Listar mensagens na fila
oci queue messages get-messages \
  --queue-id "$QUEUE_ID" \
  --visibility-in-seconds 30 \
  --timeout-in-seconds 5 \
  --limit 10

# Verificar logs do donation-service para confirmar envio
kubectl logs -n togglemaster -l app=donation-service --tail=50 | grep -i "queue\|mensagem\|OCI"
```

> **Nota:** Se OCI_QUEUE_ID nao estiver configurado, o donation-service funciona normalmente
> sem enviar mensagens para a fila (modo degradado).

---

## 8. Testar Volunteer Service (OCI NoSQL)

O volunteer-service registra voluntarios no OCI NoSQL.
Campos obrigatorios: `name`, `email`, `ngo_id`.

> **Nota:** Se o OCI NoSQL nao estiver configurado (Instance Principal ou config file),
> o servico inicia em modo degradado: `/health` retorna OK, endpoints NoSQL retornam 503.

### 8.1 Registrar um Voluntario

```bash
curl -X POST http://$LB_IP/volunteers/volunteers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Voluntario Teste",
    "email": "voluntario@solidarytech.com",
    "ngo_id": "1"
  }' | jq .
# Esperado: HTTP 201 com JSON contendo id, name, email, ngo_id, registered_at
# Ou HTTP 503 se NoSQL nao estiver configurado
```

### 8.2 Listar Voluntarios por ONG

```bash
curl -s http://$LB_IP/volunteers/volunteers/1 | jq .
```

### 8.3 Validar no OCI NoSQL

```bash
# Consultar tabela NoSQL via OCI CLI
COMPARTMENT_ID=$(terraform -chdir=terraform output -raw compartment_id 2>/dev/null || echo "SEU_COMPARTMENT_ID")

oci nosql query execute \
  --compartment-id "$COMPARTMENT_ID" \
  --statement "SELECT * FROM togglemaster_table" \
  --output table

# Ou verificar logs do volunteer-service
kubectl logs -n togglemaster -l app=volunteer-service --tail=50
```

---

## 9. Teste de Carga (Stress Test)

### 9.1 Instalar hey (HTTP load generator)

```bash
# Linux AMD64
wget -q https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -O hey
chmod +x hey
```

### 9.2 Teste de carga no Donation Service (Hot Path)

```bash
# 100 requests, 10 concorrentes
./hey -n 100 -c 10 -m POST \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":50.00,"donor_name":"Load Test"}' \
  http://$LB_IP/donations/donations

# 500 requests, 20 concorrentes (stress)
./hey -n 500 -c 20 -m POST \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":25.00,"donor_name":"Stress Test"}' \
  http://$LB_IP/donations/donations
```

### 9.3 Teste de carga no NGO Service

```bash
./hey -n 200 -c 10 http://$LB_IP/ngos/ngos
```

---

## 10. Monitoramento — Grafana

### 10.1 Acessar Grafana

```bash
# Obter IP do Grafana (LoadBalancer)
GRAFANA_IP=$(kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Grafana: http://$GRAFANA_IP"

# Credenciais padrao:
#   Usuario: admin
#   Senha:
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

> A senha padrao do Helm chart kube-prometheus-stack e `prom-operator`.

### 10.2 Datasources Configurados

O Grafana tem 2 datasources:

| Datasource | Tipo | URL | Default |
|------------|------|-----|---------|
| Prometheus | prometheus | `http://prometheus-stack-kube-prom-prometheus.monitoring:9090` | Sim |
| Loki | loki | `http://loki-stack.monitoring:3100` | Nao |

Verifique em: **Grafana > Configuration > Data Sources**

Se houver datasource duplicado ou com erro, verifique os ConfigMaps:
```bash
kubectl get configmap -n monitoring -l grafana_datasource=1
```

### 10.3 Dashboards Disponiveis

1. **Custom Dashboard (SolidaryTech)** — criado via Terraform ConfigMap
   - CPU Usage por namespace
   - Memory Usage por namespace
   - Network Traffic Rate (pods togglemaster)
   - Logs via Loki (namespace togglemaster)
   - Redis Memory e Commands/s
   - Pod Restarts

2. **Kubernetes / Compute Resources** — dashboards padrao do kube-prometheus-stack
   - Cluster, Namespace, Workload, Pod views

Para acessar: **Grafana > Dashboards > Browse** ou pesquisar "SolidaryTech"

### 10.4 Alertas Configurados

| Alerta | Severidade | Condicao |
|--------|-----------|----------|
| PodCrashLooping | critical | Pod reiniciando continuamente por 5min |
| HighErrorRate | warning | Taxa de erros 5xx > 0.5/s por 2min |
| HighCPUUsage | warning | CPU > 80% por 5min |
| PodNotReady | critical | Pod nao Ready por 5min |

Alertas sao enviados para o **Discord** via webhook configurado no Alertmanager.

### 10.5 Validar Prometheus

```bash
# Verificar targets ativos no Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &
# Acessar http://localhost:9090/targets — todos devem estar UP

# Verificar alertas
# Acessar http://localhost:9090/alerts — deve listar os alertas togglemaster

# Matar port-forward
kill %1
```

### 10.6 Validar AlertManager

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093 &
# Acessar http://localhost:9093
# Menu > Status > verificar receivers (discord configurado)
kill %1
```

### 10.7 Testar Alerta (simular falha)

```bash
# Escalar donation-service para 0 replicas (simula PodNotReady)
kubectl scale deployment donation-service -n togglemaster --replicas=0

# Aguardar ~5 minutos e verificar:
# 1. Alerta PodNotReady no Grafana > Alerting > Alert Rules
# 2. Notificacao no canal Discord

# Restaurar
kubectl scale deployment donation-service -n togglemaster --replicas=1
```

### 10.8 Validar Redis Exporter

```bash
# Verificar se o redis-exporter esta rodando
kubectl get pods -n monitoring -l app=prometheus-redis-exporter

# No Grafana, usar PromQL:
#   redis_up
#   redis_memory_used_bytes
#   rate(redis_commands_processed_total[5m])
```

### 10.9 Validar ServiceMonitors

```bash
# Listar ServiceMonitors
kubectl get servicemonitor -n monitoring

# Esperado:
#   nginx-ingress-controller   — metricas do Ingress NGINX
#   solidarytech-services      — metricas /health dos servicos
#   prometheus-redis-exporter  — metricas do Redis
```

---

## 11. Monitoramento — Loki (Logs Centralizados)

### 11.1 Consultar Logs via Grafana

1. Acesse o Grafana (secao 10.1)
2. Menu lateral > **Explore**
3. Selecione o datasource **Loki**
4. Execute queries LogQL:

```logql
# Todos os logs do namespace togglemaster
{namespace="togglemaster"}

# Logs do donation-service
{namespace="togglemaster", app="donation-service"}

# Apenas erros
{namespace="togglemaster"} |= "error"

# Logs do ngo-service com PostgreSQL
{namespace="togglemaster", app="ngo-service"} |= "PostgreSQL"

# Logs do volunteer-service com OCI NoSQL
{namespace="togglemaster", app="volunteer-service"} |= "NoSQL"

# Logs do postgres
{namespace="togglemaster", app="postgres"}
```

### 11.2 Verificar Promtail (agente de coleta)

```bash
# Verificar pods do promtail (DaemonSet — 1 por node)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Verificar logs do promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20

# Verificar se promtail esta enviando para Loki
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=50 | grep -i "level=info"
```

### 11.3 Testar ingestion de logs

```bash
# Gerar logs nos servicos fazendo requests
for i in $(seq 1 5); do
  curl -s http://$LB_IP/ngos/health > /dev/null
  curl -s http://$LB_IP/donations/health > /dev/null
  curl -s http://$LB_IP/volunteers/health > /dev/null
done

# No Grafana Explore, consultar:
#   {namespace="togglemaster"} | json | line_format "{{.message}}"
# Os logs devem aparecer em 10-30 segundos
```

---

## 12. Monitoramento — New Relic (APM)

Os servicos enviam telemetria via OpenTelemetry (OTLP) para o New Relic.

> **Pre-requisito:** A secret `NEW_RELIC_LICENSE_KEY` deve estar configurada no GitHub
> (Settings > Secrets and variables > Actions). Sem ela, os servicos funcionam
> normalmente mas sem enviar telemetria (o OTel Collector nao sera instalado).

### 12.1 Verificar se o OTel Collector esta rodando

```bash
# O OTel Collector so e instalado se newrelic_license_key for configurada no Terraform
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Se nao existir, verificar se a variavel foi configurada:
# No terraform/envs/dev.tfvars, verificar newrelic_license_key
```

### 12.2 Verificar configuracao OTEL nos servicos

```bash
# Verificar variaveis OTEL do ngo-service
kubectl get pods -n togglemaster -l app=ngo-service \
  -o jsonpath='{.items[0].spec.containers[0].env}' | jq '.[] | select(.name | startswith("OTEL"))'

# Campos esperados:
#   OTEL_SERVICE_NAME: ngo-service
#   OTEL_EXPORTER_OTLP_ENDPOINT: https://otlp.nr-data.net
```

### 12.3 Gerar Traces

```bash
# Fazer requests para gerar traces distribuidos
for i in $(seq 1 10); do
  curl -s http://$LB_IP/ngos/ngos > /dev/null
  curl -s http://$LB_IP/donations/donations > /dev/null
  curl -s -X POST http://$LB_IP/volunteers/volunteers \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Trace Test $i\",\"email\":\"trace$i@test.com\",\"ngo_id\":\"1\"}" > /dev/null
done

echo "Aguarde 1-2 minutos e verifique no New Relic"
```

### 12.4 Verificar no Console New Relic

1. Acesse [one.newrelic.com](https://one.newrelic.com)
2. Va em **APM & Services**
3. Procure os servicos: `ngo-service`, `donation-service`, `volunteer-service`
4. Verifique:
   - **Summary** — visao geral de throughput, latencia, error rate
   - **Distributed Traces** — rastreamento das requests
   - **Errors** — erros capturados
   - **Metrics** — latencia, throughput, Apdex
   - **Logs** — logs estruturados (se configurado)

> **Nota:** Se a licenca New Relic nao estiver configurada, os logs dos servicos
> mostrarao `Failed to export logs to otlp.nr-data.net, error code: StatusCode.PERMISSION_DENIED`.
> Isso e esperado e nao afeta o funcionamento dos servicos.

---

## 13. Validar ArgoCD (GitOps)

O ArgoCD sincroniza automaticamente os manifests K8s do repositorio com o cluster.

### 13.1 Acessar ArgoCD

```bash
# Obter IP do ArgoCD Server (LoadBalancer)
ARGOCD_IP=$(kubectl get svc -n argocd argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "ArgoCD: http://$ARGOCD_IP"

# Se nao tiver External IP, usar port-forward:
kubectl port-forward -n argocd svc/argocd-server 8080:80 &
echo "ArgoCD: http://localhost:8080"

# Credenciais padrao:
#   Usuario: admin
#   Senha:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 13.2 Aplicacoes Configuradas

| App | Source Path | Namespace | Sync Policy |
|-----|------------|-----------|-------------|
| ngo-service | `ngo-service/k8s` | togglemaster | Automated (prune + selfHeal) |
| donation-service | `donation-service/k8s` | togglemaster | Automated (prune + selfHeal) |
| volunteer-service | `volunteer-service/k8s` | togglemaster | Automated (prune + selfHeal) |

Todas as apps apontam para o branch `main` do repositorio.

### 13.3 Verificar status via CLI

```bash
# Instalar argocd CLI (opcional)
kubectl -n argocd get applications

# Ou via kubectl
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status
```

### 13.4 Verificar na UI do ArgoCD

1. Acesse o ArgoCD (secao 13.1)
2. Na dashboard, verifique que todas as 3 aplicacoes mostram:
   - **Sync Status:** `Synced` (verde)
   - **Health Status:** `Healthy` (coracao verde)
3. Clique em cada app para ver a arvore de recursos (Deployment, Service, Secret)

### 13.5 Testar GitOps (sync automatico)

```bash
# Qualquer alteracao em ngo-service/k8s/, donation-service/k8s/ ou
# volunteer-service/k8s/ no branch main sera automaticamente aplicada
# pelo ArgoCD no cluster.

# Para forcar um sync manual:
kubectl -n argocd patch application ngo-service \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Ou na UI: clicar no botao "Sync" da aplicacao
```

### 13.6 Verificar Auto-Heal

```bash
# Deletar um pod manualmente — ArgoCD deve recriar
kubectl delete pod -n togglemaster -l app=ngo-service

# Verificar no ArgoCD UI ou via kubectl que o pod foi recriado
kubectl get pods -n togglemaster -l app=ngo-service -w
```

---

## 14. Validacao Completa (Script Automatizado)

Execute o script abaixo para validar todos os servicos de uma vez:

```bash
# Usando o script incluso no repositorio
chmod +x scripts/test-services.sh
./scripts/test-services.sh $LB_IP
```

Ou rode o checklist manual:

```bash
#!/bin/bash
echo "=== Checklist de Validacao SolidaryTech OCI ==="
echo ""

export LB_IP=$(kubectl get ingress togglemaster-ingress -n togglemaster \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"

echo ""
echo "--- 1. Pods ---"
kubectl get pods -n togglemaster --no-headers | awk '{printf "   %-40s %s\n", $1, $3}'

echo ""
echo "--- 2. Health Checks ---"
echo -n "   NGO Service:       "; curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/ngos/health; echo
echo -n "   Donation Service:  "; curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/donations/health; echo
echo -n "   Volunteer Service: "; curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/volunteers/health; echo

echo ""
echo "--- 3. CRUD: Criar ONG ---"
curl -s -X POST http://$LB_IP/ngos/ngos \
  -H "Content-Type: application/json" \
  -d '{"name":"Validacao Hackathon","email":"validacao@hackathon.com","cause":"Tecnologia","city":"Sao Paulo"}' | jq -r '.id // .error // "ERRO"'

echo ""
echo "--- 4. CRUD: Criar Doacao ---"
curl -s -X POST http://$LB_IP/donations/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":100.00,"donor_name":"Validacao Hackathon"}' | jq -r '.id // .error // "ERRO"'

echo ""
echo "--- 5. CRUD: Criar Voluntario ---"
curl -s -X POST http://$LB_IP/volunteers/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"Validacao Hackathon","email":"vol@hackathon.com","ngo_id":"1"}' | jq -r '.id // .error // "ERRO"'

echo ""
echo "--- 6. Monitoring ---"
GRAFANA_IP=$(kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
ARGOCD_IP=$(kubectl get svc -n argocd argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
echo "   Grafana:   http://${GRAFANA_IP:-NAO_DISPONIVEL}"
echo "   ArgoCD:    http://${ARGOCD_IP:-NAO_DISPONIVEL}"
echo "   New Relic: https://one.newrelic.com"

# Grafana senha
echo "   Grafana senha: $(kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo 'prom-operator')"

# ArgoCD senha
echo "   ArgoCD senha:  $(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo 'NAO_DISPONIVEL')"

echo ""
echo "--- 7. Kubernetes Resources ---"
echo "   Nodes:"
kubectl get nodes --no-headers | awk '{printf "      %-20s %s\n", $1, $2}'
echo "   Pods monitoring:"
kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{printf "      %-50s %s\n", $1, $3}'
echo "   Apps ArgoCD:"
kubectl get applications -n argocd --no-headers 2>/dev/null | awk '{printf "      %-25s Sync: %-10s Health: %s\n", $1, $2, $3}'

echo ""
echo "=== Validacao completa ==="
```

---

## Troubleshooting

### Pod em ImagePullBackOff

O Kubernetes nao consegue baixar a imagem do OCIR (registros privados `hackathon-repo/*`).

```bash
# Verificar o erro detalhado
kubectl describe pod <pod-name> -n togglemaster | grep -A10 Events

# Verificar se o secret ocir-secret existe
kubectl get secret ocir-secret -n togglemaster

# Recriar o secret se necessario (ver secao 3.1)
kubectl delete secret ocir-secret -n togglemaster --ignore-not-found
# ... e criar novamente com as credenciais corretas
```

### Pod em ImageInspectError

O OKE usa CRI-O que requer nomes de imagem totalmente qualificados.

```bash
# Se o erro contem "short name mode is enforcing":
# Garanta que os manifests usam nomes completos:
#   docker.io/library/postgres:15-alpine  (NAO: postgres:15-alpine)
#   docker.io/library/redis:7-alpine      (NAO: redis:7-alpine)
#   docker.io/library/busybox:1.36        (NAO: busybox:1.36)

# Deletar pod com erro e reaplicar
kubectl delete pod <pod-name> -n togglemaster
kubectl apply -f k8s-infra/postgres.yaml
```

### Pod em CrashLoopBackOff

```bash
# Ver logs do pod (inclusive do crash anterior)
kubectl logs -n togglemaster <pod-name> --previous

# Descrever pod para ver eventos
kubectl describe pod -n togglemaster <pod-name>

# Causas comuns:
# - PostgreSQL nao esta pronto (initContainer deveria esperar)
# - Variavel de ambiente incorreta (DATABASE_URL, OCI_QUEUE_ID, etc.)
# - Imagem com erro de build
# - Flask/Werkzeug incompatibilidade (verificar ImportError nos logs)
# - psycopg2 SCRAM auth (verificar "SCRAM authentication requires libpq version 10")
```

### Erro de conexao com PostgreSQL

```bash
# Verificar se o postgres esta acessivel
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- pg_isready

# Verificar se os databases existem
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster \
  -- psql -U togglemaster_user -d postgres -c "SELECT datname FROM pg_database;"

# Verificar DATABASE_URL do servico
kubectl get secret ngo-service-secret -n togglemaster \
  -o jsonpath='{.data.DATABASE_URL}' | base64 -d; echo

# Testar conexao manual
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster \
  -- psql -U togglemaster_user -d ngo_db -c "SELECT 1;"
```

### Erro de conexao com OCI Queue

```bash
# Verificar variaveis de ambiente do donation-service
kubectl exec -it $(kubectl get pods -n togglemaster -l app=donation-service \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- env | grep OCI

# Verificar logs
kubectl logs -n togglemaster -l app=donation-service --tail=100 | grep -i "queue\|erro\|error"

# Nota: O OCI_QUEUE_ID e OCI_QUEUE_ENDPOINT devem ser atualizados com os
# valores reais do Terraform output (secao 4)
```

### Erro de conexao com OCI NoSQL

```bash
# Verificar variaveis de ambiente do volunteer-service
kubectl exec -it $(kubectl get pods -n togglemaster -l app=volunteer-service \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- env | grep OCI

# Verificar logs — "modo degradado" e esperado se NoSQL nao estiver configurado
kubectl logs -n togglemaster -l app=volunteer-service --tail=100 | grep -i "nosql\|erro\|error\|degradado"
```

### Node com DiskPressure ou NotReady

```bash
# Verificar condicoes do node
kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') \
  | grep -A15 "Conditions:"

# Se DiskPressure = True:
# Reiniciar o node via OCI Console > Compute > Instances > Reboot
# Aguardar node voltar a Ready:
kubectl get nodes -w
```

### Grafana sem dados / datasource com erro

```bash
# Verificar ConfigMaps de datasource
kubectl get configmap -n monitoring -l grafana_datasource=1

# Verificar se Prometheus esta coletando metricas
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &
# Acessar http://localhost:9090/targets — verificar targets UP
kill %1

# Verificar se Loki esta recebendo logs
kubectl port-forward -n monitoring svc/loki-stack 3100:3100 &
curl -s http://localhost:3100/ready
# Esperado: "ready"
kill %1
```

### Terraform 409-NAMESPACE_CONFLICT (OCIR repos)

Se o `terraform apply` falhar com `409-NAMESPACE_CONFLICT, Repository already exists`:

```bash
# Os repos ja existem no OCI mas nao estao no Terraform state.
# Importar manualmente:
cd terraform
terraform init

# Listar repos existentes
oci artifacts container repository list \
  --compartment-id <COMPARTMENT_ID> --all \
  --query "data.items[].{name:\"display-name\",id:id}" --output table

# Importar cada repo
terraform import -var-file=envs/dev.tfvars \
  "module.ocir.oci_artifacts_container_repository.ngo_service" <REPO_OCID>
terraform import -var-file=envs/dev.tfvars \
  "module.ocir.oci_artifacts_container_repository.donation_service" <REPO_OCID>
terraform import -var-file=envs/dev.tfvars \
  "module.ocir.oci_artifacts_container_repository.volunteer_service" <REPO_OCID>

# Depois reexecutar
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

> **Nota:** O workflow `terraform-apply.yml` faz import automatico dos repos existentes.
> Execute via GitHub Actions (workflow_dispatch) para evitar esse problema.
