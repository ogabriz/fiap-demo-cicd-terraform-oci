# ====== STAGE 1: BUILD ======
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Instalar git (necessário para go mod download)
RUN apk add --no-cache git

# Copiar arquivos de dependência e código-fonte
COPY go.mod ./
COPY go.sum* ./
COPY *.go ./

# Resolve dependências e gera o go.sum correto
RUN go mod tidy
RUN go mod download

# Build da aplicação
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o evaluation-service .

# ====== STAGE 2: RUNTIME ======
FROM alpine:3.18

WORKDIR /app

# Instalar ca-certificates para HTTPS e wget para health checks
RUN apk add --no-cache ca-certificates wget

# Copiar binário compilado do estágio anterior
COPY --from=builder /app/evaluation-service .

# Criar usuário não-root para segurança
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

USER appuser

EXPOSE 8004

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8004/health || exit 1

CMD ["./evaluation-service"]
