# Stage 1: Build Environment
FROM debian:12-slim AS builder
RUN apt-get update && apt-get install -y python3-venv python3-pip libpq-dev gcc
RUN python3 -m venv /opt/venv

# Activate virtual environment and install dependencies
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Distroless Runtime Environment
FROM gcr.io/distroless/python3-debian12
# Copy compiled virtual environment and source code
COPY --from=builder /opt/venv /opt/venv
COPY src/ /app/src/

# Set paths and execution environment
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/app/src"
WORKDIR /app

# Run as non-root user for security compliance
USER 65532
EXPOSE 8000

CMD ["/opt/venv/bin/uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]