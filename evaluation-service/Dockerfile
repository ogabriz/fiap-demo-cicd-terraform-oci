# ====== STAGE 1: BUILD ======
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Instalar git (necessário para go mod download)
RUN apk add --no-cache git

# Copiar arquivos de dependência
COPY go.mod ./
COPY go.sum* ./

# Download de dependências
RUN go mod download

# Copiar código-fonte
COPY *.go ./

# Build da aplicação
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o evaluation-service .

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
