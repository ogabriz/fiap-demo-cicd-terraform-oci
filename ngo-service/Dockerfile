FROM python:3.9-slim

WORKDIR /app

# Instalar dependências para OpenTelemetry e New Relic
RUN pip install --no-cache-dir \
    opentelemetry-distro \
    opentelemetry-exporter-otlp \
    newrelic

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Instrumentação automática do OpenTelemetry
RUN opentelemetry-bootstrap -a install

EXPOSE 8081

# Comando para rodar com auto-instrumentação OTel
CMD ["opentelemetry-instrument", "python", "app.py"]
