# Overlay Dockerfile for voice-agent — adds OTel auto-instrumentation.
# Build context: apps/voice-agent
FROM python:3.12-slim AS builder
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY requirements-cloud.txt .
RUN pip install --no-cache-dir -r requirements-cloud.txt \
    opentelemetry-distro \
    opentelemetry-exporter-otlp-proto-grpc \
    opentelemetry-instrumentation-fastapi \
    opentelemetry-instrumentation-httpx \
    && opentelemetry-bootstrap -a install

FROM python:3.12-slim AS runtime
# Non-root user (matches base image; uid 1000)
RUN useradd -m -u 1000 user && apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /home/user/app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --chown=user apps/voice-agent/app ./app
USER user
EXPOSE 7860
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    STT_BACKEND=groq \
    PORT=7860 \
    REMINDERS_DB=/tmp/reminders.sqlite \
    OTEL_SERVICE_NAME=voice-agent \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
    OTEL_EXPORTER_OTLP_INSECURE=true \
    OTEL_PYTHON_LOG_CORRELATION=true
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1
CMD ["sh", "-c", "opentelemetry-instrument uvicorn app.server:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
