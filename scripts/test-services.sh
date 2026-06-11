#!/bin/bash

# =============================================================================
# Script de Teste dos Servicos SolidaryTech — Hackathon Fase 5
# =============================================================================
# Usage: ./scripts/test-services.sh [LOAD_BALANCER_IP]
#
# Se nenhum IP for informado, tenta obter automaticamente do kubectl.
# =============================================================================

set -euo pipefail

# Obter IP do Load Balancer
if [ -n "${1:-}" ]; then
  IP="$1"
else
  IP=$(kubectl get ingress togglemaster-ingress -n togglemaster \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -z "$IP" ]; then
    echo "ERRO: Nao foi possivel obter o IP do Load Balancer."
    echo "Usage: $0 <LOAD_BALANCER_IP>"
    exit 1
  fi
fi

URL="http://$IP"
PASS=0
FAIL=0

# Helper para contar resultados
check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "OK" ]; then
    echo "   [PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "   [FAIL] $desc — $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "=============================================="
echo "  SolidaryTech — Teste Completo de Servicos"
echo "  Cluster: Hackathon-oke"
echo "  Load Balancer: $IP"
echo "=============================================="

# -----------------------------------------------
# 1. Health Checks
# -----------------------------------------------
echo ""
echo "--- 1. Health Checks ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL/ngos/health" 2>/dev/null || echo "000")
[ "$STATUS" = "200" ] && check "NGO Service /health" "OK" || check "NGO Service /health" "HTTP $STATUS"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL/donations/health" 2>/dev/null || echo "000")
[ "$STATUS" = "200" ] && check "Donation Service /health" "OK" || check "Donation Service /health" "HTTP $STATUS"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL/volunteers/health" 2>/dev/null || echo "000")
[ "$STATUS" = "200" ] && check "Volunteer Service /health" "OK" || check "Volunteer Service /health" "HTTP $STATUS"

# -----------------------------------------------
# 2. NGO Service — CRUD
# -----------------------------------------------
echo ""
echo "--- 2. NGO Service (PostgreSQL) ---"

RESPONSE=$(curl -s -X POST "$URL/ngos/ngos" \
  -H "Content-Type: application/json" \
  -d '{"name":"ONG Teste Automatizado","description":"Teste script","contact_email":"auto@solidarytech.com"}' 2>/dev/null || echo "")
NGO_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null || echo "")
[ -n "$NGO_ID" ] && check "Criar ONG (id=$NGO_ID)" "OK" || check "Criar ONG" "Resposta: $RESPONSE"

RESPONSE=$(curl -s "$URL/ngos/ngos" 2>/dev/null || echo "")
COUNT=$(echo "$RESPONSE" | jq -r 'length // 0' 2>/dev/null || echo "0")
[ "$COUNT" -gt 0 ] 2>/dev/null && check "Listar ONGs (total=$COUNT)" "OK" || check "Listar ONGs" "Resposta vazia ou erro"

# -----------------------------------------------
# 3. Donation Service — CRUD + Queue
# -----------------------------------------------
echo ""
echo "--- 3. Donation Service (PostgreSQL + OCI Queue) ---"

RESPONSE=$(curl -s -X POST "$URL/donations/donations" \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":75.50,"donor_name":"Script Teste"}' 2>/dev/null || echo "")
DON_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null || echo "")
[ -n "$DON_ID" ] && check "Criar Doacao (id=$DON_ID)" "OK" || check "Criar Doacao" "Resposta: $RESPONSE"

RESPONSE=$(curl -s "$URL/donations/donations" 2>/dev/null || echo "")
COUNT=$(echo "$RESPONSE" | jq -r 'length // 0' 2>/dev/null || echo "0")
[ "$COUNT" -gt 0 ] 2>/dev/null && check "Listar Doacoes (total=$COUNT)" "OK" || check "Listar Doacoes" "Resposta vazia ou erro"

# -----------------------------------------------
# 4. Volunteer Service — CRUD (OCI NoSQL)
# -----------------------------------------------
echo ""
echo "--- 4. Volunteer Service (OCI NoSQL) ---"

RESPONSE=$(curl -s -X POST "$URL/volunteers/volunteers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Voluntario Script","email":"script@solidarytech.com","ngo_id":"1"}' 2>/dev/null || echo "")
VOL_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null || echo "")
[ -n "$VOL_ID" ] && check "Registrar Voluntario (id=$VOL_ID)" "OK" || check "Registrar Voluntario" "Resposta: $RESPONSE"

RESPONSE=$(curl -s "$URL/volunteers/volunteers/1" 2>/dev/null || echo "")
# volunteer-service retorna lista ou objeto
VOL_COUNT=$(echo "$RESPONSE" | jq -r 'if type == "array" then length else 1 end' 2>/dev/null || echo "0")
[ "$VOL_COUNT" -gt 0 ] 2>/dev/null && check "Listar Voluntarios ONG 1 (total=$VOL_COUNT)" "OK" || check "Listar Voluntarios ONG 1" "Resposta vazia ou erro"

# -----------------------------------------------
# 5. Monitoramento
# -----------------------------------------------
echo ""
echo "--- 5. Monitoramento ---"

GRAFANA_IP=$(kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
[ -n "$GRAFANA_IP" ] && check "Grafana acessivel (http://$GRAFANA_IP)" "OK" || check "Grafana" "IP nao encontrado"

ARGOCD_IP=$(kubectl get svc -n argocd argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
[ -n "$ARGOCD_IP" ] && check "ArgoCD acessivel (http://$ARGOCD_IP)" "OK" || check "ArgoCD" "IP nao encontrado"

PROM_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep Running | head -1 || echo "")
[ -n "$PROM_POD" ] && check "Prometheus Running" "OK" || check "Prometheus" "Pod nao encontrado ou nao Running"

LOKI_POD=$(kubectl get pods -n monitoring -l app=loki --no-headers 2>/dev/null | grep Running | head -1 || echo "")
[ -n "$LOKI_POD" ] && check "Loki Running" "OK" || check "Loki" "Pod nao encontrado ou nao Running"

# -----------------------------------------------
# Resultado Final
# -----------------------------------------------
echo ""
echo "=============================================="
echo "  RESULTADO: $PASS passed, $FAIL failed"
echo "=============================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
