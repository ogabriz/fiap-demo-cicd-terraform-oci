FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN pip install --no-cache-dir \
    opentelemetry-distro \
    opentelemetry-exporter-otlp

COPY . .

RUN opentelemetry-bootstrap -a install

EXPOSE 8081

CMD ["opentelemetry-instrument", "python", "app.py"]
