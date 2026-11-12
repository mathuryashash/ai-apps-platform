# Overlay Dockerfile for jobtracker — adds non-root user, OTel auto-instrumentation, healthcheck.
# Build context: apps/jobtracker
FROM python:3.10-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
# Install app deps + OpenTelemetry zero-code instrumentation
# The app imports cryptography, python-dotenv, numpy and rank-bm25 directly, but its unpinned
# requirements.txt does not list them; a fresh resolve dropped cryptography (pod crash).
RUN pip install --no-cache-dir -r requirements.txt \
    cryptography python-dotenv numpy rank-bm25 \
    opentelemetry-distro \
    opentelemetry-exporter-otlp-proto-grpc \
    opentelemetry-instrumentation-fastapi \
    opentelemetry-instrumentation-httpx \
    opentelemetry-instrumentation-sqlalchemy \
    opentelemetry-instrumentation-psycopg2 \
    && opentelemetry-bootstrap -a install

FROM python:3.10-slim AS runtime
# Non-root user (why: principle of least privilege; avoids container escape via root file writes)
RUN useradd -m -u 1000 appuser
WORKDIR /app
# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
# Need libpq at runtime
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/*
COPY --chown=appuser . .
USER appuser
EXPOSE 8000
# OTel env vars — overridden at deploy time via ConfigMap/Secret
ENV OTEL_SERVICE_NAME=jobtracker \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
    OTEL_EXPORTER_OTLP_INSECURE=true \
    OTEL_PYTHON_LOG_CORRELATION=true \
    PYTHONUNBUFFERED=1
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1
CMD ["opentelemetry-instrument", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
