# Etapa 1: instala dependencias de produccion en un entorno con build tools completo
FROM node:20-alpine AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Etapa 2: imagen final minimalista, solo con lo necesario para ejecutar
FROM node:20-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY package.json server.js ./

EXPOSE 5000
CMD ["node", "server.js"]
