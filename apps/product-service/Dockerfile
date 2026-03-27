# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --production

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM node:20-alpine AS runner
WORKDIR /app

# Non-root user — principle of least privilege
RUN addgroup -g 1001 -S nestjs && adduser -S -u 1001 -G nestjs nestjs

COPY --from=builder --chown=nestjs:nestjs /app/dist        ./dist
COPY --from=builder --chown=nestjs:nestjs /app/node_modules ./node_modules
COPY --chown=nestjs:nestjs package.json ./

USER nestjs
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/products/health || exit 1

CMD ["node", "dist/main"]
