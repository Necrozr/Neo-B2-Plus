# Step 1: Build stage
FROM golang:1.22-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git gcc musl-dev

WORKDIR /app

# Copy dependency files first for caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=1 GOOS=linux go build -o /neob2plus ./cmd/server/main.go

# Step 2: Runtime stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata

# Create non-root user for security
RUN adduser -D -g '' appuser
USER appuser

WORKDIR /home/appuser/

# Copy the binary from builder
COPY --from=builder /neob2plus .
# Copy static files if they exist (checkout UI)
COPY --from=builder /app/public ./public
# Copy default config (operator must override with their own)
COPY --from=builder /app/config.json.example ./config.json.example

# Expose the API port
EXPOSE 8080

# Run the binary
CMD ["./neob2plus"]
