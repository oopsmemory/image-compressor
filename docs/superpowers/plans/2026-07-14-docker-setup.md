# Docker Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a multi-stage Dockerfile plus Compose (base + override) so the web image compressor runs in Docker for both local Vite development and Node `vite preview` production.

**Architecture:** One `Dockerfile` with named stages (`deps` → `development` → `build` → `production`). `docker-compose.yml` runs production on host port 8080. `docker-compose.override.yml` switches to development with bind mounts and Vite on port 5173. Vite binds to `0.0.0.0` for container access. Tauri stays out of the image via `.dockerignore`.

**Tech Stack:** Node 20 Alpine, npm, Vite 6, Docker Compose v2

**Spec:** `docs/superpowers/specs/2026-07-14-docker-setup-design.md`

---

## File structure

| File | Responsibility |
|------|----------------|
| `.dockerignore` | Exclude `node_modules`, `dist`, `src-tauri`, `.git`, docs noise from build context |
| `Dockerfile` | Multi-stage image with `deps`, `development`, `build`, `production` targets |
| `docker-compose.yml` | Production `app` service (target `production`, `8080:4173`) |
| `docker-compose.override.yml` | Local override: target `development`, mounts, `5173:5173` |
| `vite.config.ts` | Set `server.host` / `preview.host` for container networking |

---

### Task 1: Add `.dockerignore`

**Files:**
- Create: `.dockerignore`

- [ ] **Step 1: Create `.dockerignore`**

```dockerignore
node_modules
dist
.git
.github
src-tauri
*.md
!README.md
docs
.vscode
.idea
coverage
.env
.env.*
*.log
.DS_Store
```

- [ ] **Step 2: Verify file exists at repo root**

Run: `test -f .dockerignore && wc -l .dockerignore`

Expected: exit 0, line count around 15

- [ ] **Step 3: Commit**

```bash
git add .dockerignore
git commit -m "$(cat <<'EOF'
Add .dockerignore for lean web container builds.

EOF
)"
```

---

### Task 2: Bind Vite to all interfaces

**Files:**
- Modify: `vite.config.ts`

- [ ] **Step 1: Update `vite.config.ts` server and preview host settings**

Replace the existing `server` block and add `preview` so containers are reachable from the host:

```typescript
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { defineConfig } from "vite";
// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    host: true,
    open: true,
  },
  preview: {
    host: true,
    port: 4173,
  },
  build: {
    target: "esnext",
    minify: "esbuild",
    sourcemap: false,
    rollupOptions: {
      treeshake: true,
    },
  },
});
```

- [ ] **Step 2: Confirm TypeScript still typechecks the config**

Run: `npx tsc -p tsconfig.node.json --noEmit`

Expected: exit 0, no errors

- [ ] **Step 3: Commit**

```bash
git add vite.config.ts
git commit -m "$(cat <<'EOF'
Bind Vite server and preview to all interfaces for Docker.

EOF
)"
```

---

### Task 3: Add multi-stage `Dockerfile`

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Create `Dockerfile` with named stages**

Write this exact file. Do not set `NODE_ENV=production` before `npm ci` in the production stage — Vite is a devDependency and must remain installed for `vite preview`.

```dockerfile
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
```

If Step 3 fails because a Vite plugin needs files under `src/` or `public/`, copy the minimum extra paths into the production stage and re-verify (do not copy `src-tauri`).

- [ ] **Step 2: Validate Dockerfile syntax**

Run: `docker build --target production -t image-compressor:prod .`

Expected: build succeeds; last lines show exporting layers / naming to `image-compressor:prod`

- [ ] **Step 3: Smoke-test production image**

Run:

```bash
docker run --rm -d --name image-compressor-prod-test -p 8080:4173 image-compressor:prod
sleep 2
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
docker stop image-compressor-prod-test
```

Expected: HTTP status `200`

If curl fails, check container logs with `docker logs image-compressor-prod-test` before stopping, fix the Dockerfile production stage, and retry.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "$(cat <<'EOF'
Add multi-stage Dockerfile for Vite dev and preview production.

EOF
)"
```

---

### Task 4: Add Compose base and override

**Files:**
- Create: `docker-compose.yml`
- Create: `docker-compose.override.yml`

- [ ] **Step 1: Create production `docker-compose.yml`**

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    ports:
      - "8080:4173"
    restart: unless-stopped
```

- [ ] **Step 2: Create local `docker-compose.override.yml`**

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: development
    ports:
      - "5173:5173"
    volumes:
      - .:/app
      - app_node_modules:/app/node_modules
    command: ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"]

volumes:
  app_node_modules:
```

Note: Compose may merge `ports` as a union, so local `docker compose up` might expose both `5173` and `8080`. Spec success only requires `5173` for local. Leave as-is unless a port conflict blocks verification.

- [ ] **Step 3: Verify merged and production-only configs**

Run:

```bash
docker compose config --services
docker compose -f docker-compose.yml config
```

Expected:
- First command prints `app`
- Second shows `target: production` and `8080:4173` without development volumes

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml docker-compose.override.yml
git commit -m "$(cat <<'EOF'
Add Compose production base and local development override.

EOF
)"
```

---

### Task 5: End-to-end verification

**Files:**
- None (verification only)

- [ ] **Step 1: Start production-only stack**

Run:

```bash
docker compose -f docker-compose.yml up --build -d
sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
docker compose -f docker-compose.yml down
```

Expected: HTTP `200`, then stack stops cleanly

- [ ] **Step 2: Start local (override) stack**

Run:

```bash
docker compose up --build -d
sleep 5
curl -s -o /dev/null -w "%{http_code}" http://localhost:5173/
docker compose down
```

Expected: HTTP `200`

- [ ] **Step 3: Confirm no further commits needed**

If verification required Dockerfile or Compose fixes, commit those fixes with a clear message (e.g. `Fix production preview dependencies in Dockerfile.`). Otherwise stop.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Multi-stage Dockerfile with named targets | Task 3 |
| `docker-compose.yml` production service | Task 4 |
| `docker-compose.override.yml` for local | Task 4 |
| `.dockerignore` excluding Tauri/VCS | Task 1 |
| Vite host binding | Task 2 |
| Prod on 8080 / preview 4173 | Tasks 3–5 |
| Dev on 5173 with node_modules volume | Tasks 4–5 |
| Tauri out of scope | Task 1 (ignored) |

---

## Self-review notes

- No TBD/placeholder steps remaining; production stage explicitly uses `npm ci` without forcing `NODE_ENV=production` before install so Vite remains available for `preview`.
- Compose ports merge quirk is called out; success criteria do not require stripping 8080 from local merge.
- Commits are frequent and scoped per task.
