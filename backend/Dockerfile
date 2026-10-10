# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production PORT=8080 DB_PATH=/data/app.db
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/
RUN mkdir -p /data && chown node:node /data
VOLUME ["/data"]
EXPOSE 8080
ARG VERSION=dev
ENV APP_VERSION=${VERSION}
LABEL org.opencontainers.image.source="https://github.com/jeanyves-figiel/Gym-Workout" \
      org.opencontainers.image.version="${VERSION}"
HEALTHCHECK CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "--disable-warning=ExperimentalWarning", "src/server.ts"]
