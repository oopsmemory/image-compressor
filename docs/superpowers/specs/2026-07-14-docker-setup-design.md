# Docker Setup Design — Image Compressor

**Date:** 2026-07-14  
**Status:** Approved for implementation planning

## Goal

Add Docker support for the **web** app (React + Vite) so developers can run the image compressor locally in a container and publish a production container that serves the built static site with Node.

Tauri desktop/mobile builds are explicitly out of scope.

## Decisions

| Topic | Choice |
|--------|--------|
| Scope | Production + development |
| Compose layout | Base `docker-compose.yml` + `docker-compose.override.yml` for local dev |
| Production serving | Node via `vite preview` (not nginx) |
| Dockerfile structure | Single multi-stage file with named targets |

## Architecture

### Files to add / change

| File | Role |
|------|------|
| `Dockerfile` | Multi-stage image: `deps` → `development` → `build` → `production` |
| `docker-compose.yml` | Production service (`app`) using target `production` |
| `docker-compose.override.yml` | Local defaults: target `development`, bind mounts, Vite HMR |
| `.dockerignore` | Keep build context small (exclude `node_modules`, `dist`, `src-tauri`, `.git`, etc.) |
| `vite.config.ts` | Ensure `server` / `preview` bind to `0.0.0.0` (or `host: true`) for container networking |

### Runtime flows

```text
Local (default):
  docker compose up --build
  → merges docker-compose.yml + docker-compose.override.yml
  → development target
  → Vite on host http://localhost:5173

Production:
  docker compose -f docker-compose.yml up --build
  → override not applied
  → production target
  → vite preview on host http://localhost:8080 → container 4173
```

## Dockerfile stages

1. **deps** — `node:20-alpine`; copy `package.json` / `package-lock.json`; run `npm ci`.
2. **development** — From `deps`; working directory `/app`; default command:
   `npm run dev -- --host 0.0.0.0 --port 5173`.
3. **build** — From `deps`; copy application source; run `npm run build` → `dist/`.
4. **production** — From `deps` (or a slim Node stage with necessary files); copy `dist` and whatever is required to run `vite preview`; default command:
   `npm run preview -- --host 0.0.0.0 --port 4173`.

Expose ports `5173` (dev) and `4173` (preview) as appropriate per stage.

## Compose services

### `docker-compose.yml` (production)

- Service name: `app`
- `build.target`: `production`
- Ports: `8080:4173`
- `restart: unless-stopped`

### `docker-compose.override.yml` (local, auto-merged)

- Same service `app`
- `build.target`: `development`
- Ports: `5173:5173`
- Volumes:
  - `.:/app` (source bind mount)
  - named or anonymous volume for `/app/node_modules` so the host tree does not overwrite container dependencies
- Command aligned with development stage (Vite with host binding)

## Vite config adjustments

- Set `server.host` and `preview.host` so the app is reachable from outside the container.
- Prefer config-level host binding over relying only on CLI flags (CLI flags may still be set in Dockerfile/`command` for clarity).
- `server.open: true` is harmless but useless in Docker; leave as-is or disable — either is acceptable; do not block shipping on this.

## Out of scope

- Tauri / Android / iOS Docker builds
- TLS / reverse proxy
- Publishing images to a registry in CI
- Changing application compression logic

## Success criteria

1. `docker compose up --build` serves the app with hot reload on port 5173.
2. `docker compose -f docker-compose.yml up --build` serves the production build on port 8080.
3. Context excludes unnecessary Tauri and VCS paths via `.dockerignore`.
4. No secrets or unnecessary host files are copied into the image.

## Testing plan

1. Build and start with override; open `http://localhost:5173`; confirm UI loads and compression still works in-browser.
2. Start production-only compose; open `http://localhost:8080`; confirm static build loads.
3. Confirm a trivial source edit triggers Vite HMR in the dev container.

