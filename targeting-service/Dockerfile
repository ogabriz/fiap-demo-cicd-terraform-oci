FROM python:3.11-slim

# Create a non-root user
RUN useradd -m -u 10001 appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy files with ownership assigned to the non-root user
COPY --chown=appuser:appuser . .

# Switch to the non-root user
USER appuser

EXPOSE 8003

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8003/health')" || exit 1

CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8003", "--workers", "1", "--timeout", "300", "app:app"]
