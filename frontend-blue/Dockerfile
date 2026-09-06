# ─────────────────────────────────────────────
# Stage 1: Build stage
# ─────────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files first for layer caching
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production

# ─────────────────────────────────────────────
# Stage 2: Production image (Blue)
# ─────────────────────────────────────────────
FROM node:18-alpine

# Label to identify this as the blue deployment
LABEL deployment.color="blue"

# Set NODE_ENV
ENV NODE_ENV=production

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application source
COPY server.js ./
COPY public/ ./public/

# Expose the frontend-blue port
EXPOSE 3100

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3100/health || exit 1

# Start the server
CMD ["node", "server.js"]
