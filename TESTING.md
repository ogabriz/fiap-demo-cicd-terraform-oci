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

Os servicos usam imagens privadas do OCI Container Registry (`hackathon-repo`).
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
- **OCIR:** hackathon-repo (registro privado)
- **OCI Queue:** fila para donation-service
- **OCI NoSQL:** togglemaster_table para volunteer-service
- **Observability:** Prometheus + Grafana + Loki + AlertManager
- **ArgoCD:** GitOps para 3 servicos

---

## 5. Health Checks dos Servicos

```bash
export LB_IP=$(kubectl get ingress togglemaster-ingress -n togglemaster \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# NGO Service (Python/Flask — porta 8081)
curl -s http://$LB_IP/ngos/health | jq .

# Donation Service (Go — porta 8082)
curl -s http://$LB_IP/donations/health | jq .

# Volunteer Service (Python/Flask — porta 8083)
curl -s http://$LB_IP/volunteers/health | jq .
```

Resultado esperado: HTTP 200 com JSON indicando status `ok` ou `healthy`.

---

## 6. Testar NGO Service (PostgreSQL)

### 6.1 Criar uma ONG

```bash
curl -X POST http://$LB_IP/ngos/ngos \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ONG Teste SolidaryTech",
    "description": "Organizacao de teste para validacao",
    "contact_email": "teste@solidarytech.com"
  }' | jq .
```

### 6.2 Listar ONGs

```bash
curl -s http://$LB_IP/ngos/ngos | jq .
```

### 6.3 Validar diretamente no PostgreSQL

```bash
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster \
  -- psql -U togglemaster_user -d ngo_db -c "SELECT * FROM ngos;"
```

---

## 7. Testar Donation Service (PostgreSQL + OCI Queue)

### 7.1 Criar uma Doacao

```bash
curl -X POST http://$LB_IP/donations/donations \
  -H "Content-Type: application/json" \
  -d '{
    "ngo_id": 1,
    "amount": 150.00,
    "donor_name": "Doador Teste"
  }' | jq .
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

---

## 8. Testar Volunteer Service (OCI NoSQL)

### 8.1 Registrar um Voluntario

```bash
curl -X POST http://$LB_IP/volunteers/volunteers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Voluntario Teste",
    "email": "voluntario@solidarytech.com",
    "ngo_id": "1"
  }' | jq .
```

### 8.2 Listar Voluntarios por ONG

```bash
curl -s http://$LB_IP/volunteers/volunteers/1 | jq .
```

### 8.3 Validar no OCI NoSQL

```bash
# Consultar tabela NoSQL via OCI CLI
COMPARTMENT_ID="ocid1.compartment.oc1..aaaaaaaanehxovyxoaobjbxqhbgdcubarphs5xuptwok4gbcpepxov75obpq"

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

### 10.2 Dashboards Disponiveis

1. **Custom Dashboard (SolidaryTech)**
   - CPU Usage por namespace
   - Memory Usage por namespace
   - Network Traffic Rate (pods togglemaster)
   - Logs via Loki (namespace togglemaster)
   - Redis Memory e Commands/s
   - Pod Restarts

2. **Kubernetes / Compute Resources**
   - Dashboards padrao do kube-prometheus-stack

### 10.3 Alertas Configurados

| Alerta | Severidade | Condicao |
|--------|-----------|----------|
| PodCrashLooping | critical | Pod reiniciando continuamente por 5min |
| HighErrorRate | warning | Taxa de erros 5xx > 0.5/s por 2min |
| HighCPUUsage | warning | CPU > 80% por 5min |
| PodNotReady | critical | Pod nao Ready por 5min |

Alertas sao enviados para o **Discord** via webhook configurado no Alertmanager.

### 10.4 Validar Prometheus e AlertManager

```bash
# Port-forward do Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &

# Acessar http://localhost:9090/alerts
# Verificar se os alertas togglemaster estao listados

# Port-forward do AlertManager
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093 &

# Acessar http://localhost:9093
# Verificar receivers configurados (discord)
```

### 10.5 Testar Alerta (simular falha)

```bash
# Escalar donation-service para 0 replicas (simula PodNotReady)
kubectl scale deployment donation-service -n togglemaster --replicas=0

# Aguardar ~5 minutos e verificar:
# 1. Alerta PodNotReady no Grafana > Alerting
# 2. Notificacao no canal Discord

# Restaurar
kubectl scale deployment donation-service -n togglemaster --replicas=1
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

# Logs do volunteer-service com OCI NoSQL
{namespace="togglemaster", app="volunteer-service"} |= "NoSQL"

# Logs do postgres
{namespace="togglemaster", app="postgres"}
```

### 11.2 Verificar Promtail (agente de coleta)

```bash
# Verificar pods do promtail
kubectl get pods -n monitoring -l app=promtail

# Verificar logs do promtail
kubectl logs -n monitoring -l app=promtail --tail=20
```

---

## 12. Monitoramento — New Relic (APM)

### 12.1 Verificar Integracao

Os servicos enviam telemetria via OpenTelemetry (OTLP) para o New Relic.

```bash
# Verificar variaveis OTEL nos pods
kubectl get pods -n togglemaster -l app=ngo-service \
  -o jsonpath='{.items[0].spec.containers[0].env}' | jq .

# Verificar se o OTel Collector esta rodando (se newrelic_license_key foi configurada)
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector
```

### 12.2 Gerar Traces

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

### 12.3 Verificar no Console New Relic

1. Acesse [one.newrelic.com](https://one.newrelic.com)
2. Va em **APM & Services**
3. Procure os servicos: `ngo-service`, `donation-service`, `volunteer-service`
4. Verifique:
   - **Distributed Traces** — rastreamento das requests
   - **Errors** — erros capturados
   - **Metrics** — latencia, throughput
   - **Logs** — logs estruturados

---

## 13. Validar ArgoCD (GitOps)

O ArgoCD sincroniza automaticamente os manifests K8s do repositorio com o cluster.

```bash
# Obter IP do ArgoCD Server
ARGOCD_IP=$(kubectl get svc -n argocd argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "ArgoCD: http://$ARGOCD_IP"

# Credenciais padrao:
#   Usuario: admin
#   Senha:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### Aplicacoes no ArgoCD

| App | Source | Namespace |
|-----|--------|-----------|
| ngo-service | `ngo-service/k8s` | togglemaster |
| donation-service | `donation-service/k8s` | togglemaster |
| volunteer-service | `volunteer-service/k8s` | togglemaster |

Verifique que todas estao **Synced** e **Healthy** na UI do ArgoCD.

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
  -d '{"name":"Validacao Hackathon","description":"Teste completo","contact_email":"validacao@hackathon.com"}' | jq -r '.id // "ERRO"'

echo ""
echo "--- 4. CRUD: Criar Doacao ---"
curl -s -X POST http://$LB_IP/donations/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":100.00,"donor_name":"Validacao Hackathon"}' | jq -r '.id // "ERRO"'

echo ""
echo "--- 5. CRUD: Criar Voluntario ---"
curl -s -X POST http://$LB_IP/volunteers/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"Validacao Hackathon","email":"vol@hackathon.com","ngo_id":"1"}' | jq -r '.id // "ERRO"'

echo ""
echo "--- 6. Monitoring ---"
GRAFANA_IP=$(kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
ARGOCD_IP=$(kubectl get svc -n argocd argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
echo "   Grafana:   http://${GRAFANA_IP:-NAO_DISPONIVEL}"
echo "   ArgoCD:    http://${ARGOCD_IP:-NAO_DISPONIVEL}"
echo "   New Relic: https://one.newrelic.com"

echo ""
echo "--- 7. Kubernetes Resources ---"
echo "   Nodes:"
kubectl get nodes --no-headers | awk '{printf "      %-20s %s\n", $1, $2}'
echo "   Namespaces com pods:"
kubectl get pods --all-namespaces --no-headers 2>/dev/null | awk '{print $1}' | sort -u | awk '{print "      " $0}'

echo ""
echo "=== Validacao completa ==="
```

---

## Troubleshooting

### Pod em ImagePullBackOff

O Kubernetes nao consegue baixar a imagem do OCIR (registro privado `hackathon-repo`).

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
```

### Erro de conexao com PostgreSQL

```bash
# Verificar se o postgres esta acessivel
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- pg_isready

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

# Verificar logs
kubectl logs -n togglemaster -l app=volunteer-service --tail=100 | grep -i "nosql\|erro\|error"
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
