FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production
ENV PORT=3000

WORKDIR /app

# Copy dependency manifests first for better Docker layer caching
COPY package.json package-lock.json ./

# Install production dependencies using the lock file
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force

# Copy application
COPY server.js ./

# Create non-root user
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --shell /usr/sbin/nologin app

# Run application as non-root user
USER 10001:10001

EXPOSE 3000

# Container health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://127.0.0.1:3000/healthz', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

STOPSIGNAL SIGTERM

CMD ["node", "server.js"]
