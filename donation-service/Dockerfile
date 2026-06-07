# Multi-stage build for Go
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod ./
# Se houver go.sum, descomente a linha abaixo
# COPY go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o main .

# Final stage
FROM alpine:latest
RUN apk --no-cache add ca-certificates curl

WORKDIR /root/
COPY --from=builder /app/main .

EXPOSE 8082
CMD ["./main"]
