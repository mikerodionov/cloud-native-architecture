# Stage 1: Build Environment
FROM node:20-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY src/ ./src/

# Stage 2: Distroless Runtime Environment
FROM gcr.io/distroless/nodejs20-debian12
WORKDIR /app
# Copy strictly the application code and resolved dependencies
COPY --from=builder /app /app

# Run as non-root user for security compliance
USER 65532
EXPOSE 3000

CMD ["src/index.js"]