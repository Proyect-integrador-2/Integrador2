# MS Motos — imagen de producción para Integrador II.
#
# Una sola imagen: Express sirve la API (/api) y el build de Angular (server.js lo
# detecta en frontend/www). Tres etapas para que la imagen final no cargue el
# toolchain de Angular ni los compiladores que necesita bcrypt.

# ---------- 1. Build del frontend (Angular/Ionic) ----------
FROM node:22-bookworm-slim AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npx ng build --configuration production

# ---------- 2. Dependencias de producción del backend ----------
FROM node:22-bookworm-slim AS backend-deps
# bcrypt es un módulo nativo: si no hay binario precompilado para la plataforma,
# npm lo compila y necesita estas herramientas. Se quedan en esta etapa.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app/backend
COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

# ---------- 3. Imagen final ----------
FROM node:22-bookworm-slim
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app
COPY --from=backend-deps --chown=node:node /app/backend/node_modules ./backend/node_modules
COPY --chown=node:node backend/ ./backend/
COPY --from=frontend --chown=node:node /build/frontend/www ./frontend/www

# Sin root dentro del contenedor.
USER node
EXPOSE 3000

# Docker marca el contenedor "unhealthy" si /api/health deja de responder.
# Zabbix lee este estado con el plugin Docker del agent 2.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# cluster.js migra una vez (idempotente, sin DROP) y levanta WEB_CONCURRENCY workers.
CMD ["node", "backend/src/cluster.js"]
