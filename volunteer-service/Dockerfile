FROM python:3.9-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    opentelemetry-distro \
    opentelemetry-exporter-otlp \
    newrelic

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN opentelemetry-bootstrap -a install

EXPOSE 8083

CMD ["opentelemetry-instrument", "python", "app.py"]
