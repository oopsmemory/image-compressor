# syntax=docker/dockerfile:1

FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM deps AS development
WORKDIR /app
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"]

FROM deps AS build
WORKDIR /app
COPY . .
RUN npm run build

FROM node:20-alpine AS production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY --from=build /app/dist ./dist
COPY vite.config.ts tsconfig.json tsconfig.app.json tsconfig.node.json index.html ./
EXPOSE 4173
CMD ["npm", "run", "preview", "--", "--host", "0.0.0.0", "--port", "4173"]
