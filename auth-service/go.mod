module github.com/ealvesjr90/fiap-demo-cicd-terraform-oci/auth-service

go 1.23

require (
	github.com/joho/godotenv v1.5.1
	github.com/lib/pq v1.10.9
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.42.0
	go.opentelemetry.io/otel v1.16.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.16.0
	go.opentelemetry.io/otel/sdk v1.16.0
	go.opentelemetry.io/otel/trace v1.16.0
)
