# New API (Deployment-Focused README)

[中文部署版](./README.md)

This README is focused on a reproducible deployment workflow based on the repository docs and recent changes:

- Ubuntu bare-metal backend (no Docker)
- BaoTa panel (Nginx reverse proxy)
- Aliyun ESA PAGES frontend (recommended: classic)
- Official Sentry (SaaS) or switchable Sentry modes

## Documentation Index

- Project how-to (structure/config/build): [how-to-use.md](./how-to-use.md)
- Sentry guide (official/self-hosted/disabled): [how-to-use-sentry.md](./how-to-use-sentry.md)
- Ubuntu bare-metal + official Sentry: [how-to-run-ubuntu-official-sentry.md](./how-to-run-ubuntu-official-sentry.md)
- Frontend standalone build: [how-to-build-frontend.md](./how-to-build-frontend.md)
- Windows build script (Ubuntu cross-build + Pages export): [build-windows.ps1](./build-windows.ps1)
- systemd example: [new-api.service](./new-api.service)
- Nginx example: [nginx.conf](./nginx.conf)

## Recommended Topology

Use two domains:

- `app.example.com` for Aliyun ESA PAGES frontend (static)
- `api.example.com` for backend API (BaoTa/Nginx reverse proxy to `127.0.0.1:3000`)

## 1. Backend on Ubuntu (bare-metal, no Docker)

### 1.1 Build the Linux binary

Option A: cross-build on Windows and upload to Ubuntu:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -BackendTargetOS ubuntu -SkipDefaultFrontend -SkipClassicFrontend
```

Artifacts:

- `dist/artifacts/backend/linux-amd64/`
  - `new-api-<version>`
  - `run-ubuntu.sh`
  - `README-ubuntu.md`

Option B: build directly on Ubuntu:

```bash
git clone https://github.com/VupHub/new-api.git
cd new-api
go mod download
go build -ldflags "-s -w -X github.com/QuantumNous/new-api/common.Version=v0.0.0-ubuntu" -o new-api .
```

### 1.2 Deploy to `/opt/new-api`

```bash
sudo mkdir -p /opt/new-api
sudo chown -R $USER:$USER /opt/new-api
```

Upload binaries into `/opt/new-api`, then:

```bash
cd /opt/new-api
chmod +x ./new-api-* ./run-ubuntu.sh 2>/dev/null || true
chmod +x ./new-api 2>/dev/null || true
```

### 1.3 Create `/opt/new-api/.env`

Example for PostgreSQL + Redis + Official Sentry:

```ini
PORT=3000
GIN_MODE=release
DEBUG=false
USE_FRONTEND=false

SESSION_SECRET=replace-with-a-random-32-char-string
CRYPTO_SECRET=replace-with-another-random-32-char-string

SQL_DSN=postgresql://newapi:strong-password@127.0.0.1:5432/new-api
REDIS_CONN_STRING=redis://127.0.0.1:6379/0

SENTRY_MODE=official
SENTRY_DSN=https://<public-key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=new-api@ubuntu-prod-1
SENTRY_ENABLE_TRACING=true
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_DEBUG=false
SENTRY_SEND_DEFAULT_PII=false
```

Notes:

- `SESSION_SECRET` must not be the placeholder `random_string`
- Official Sentry requires `SENTRY_MODE=official` and a `sentry.io` DSN

### 1.4 Start and health-check

```bash
set -a
source /opt/new-api/.env
set +a
cd /opt/new-api
./run-ubuntu.sh
```

```bash
curl http://127.0.0.1:3000/api/status
curl http://127.0.0.1:3000/api/setup
```

### 1.5 systemd service (recommended)

Create the service user:

```bash
sudo useradd --system --home /opt/new-api --shell /usr/sbin/nologin new-api
sudo chown -R new-api:new-api /opt/new-api
```

Install and start service:

```bash
sudo cp ./new-api.service /etc/systemd/system/new-api.service
sudo systemctl daemon-reload
sudo systemctl enable new-api
sudo systemctl restart new-api
sudo systemctl status new-api --no-pager
```

If you get `status=217/USER`, the `User=new-api` does not exist or permissions are wrong.

## 2. BaoTa Nginx reverse proxy (api.example.com)

Goal: proxy `https://api.example.com` to `http://127.0.0.1:3000`.

Verify:

```bash
curl https://api.example.com/api/status
```

## 3. Frontend on Aliyun ESA PAGES (recommended: classic)

### 3.1 Standalone build

See: [how-to-build-frontend.md](./how-to-build-frontend.md)

Recommended classic build for Aliyun ESA PAGES (inject backend URL):

```bash
cd web/classic
bun install
VITE_REACT_APP_SERVER_URL="https://api.example.com" bun run build
```

Artifact:

- `web/classic/dist/`

### 3.2 ESA PAGES build settings (root/output/static)

Aliyun ESA PAGES usually requires:

- Root Directory (frontend project folder)
- Output Directory (build output)
- Static Directory (published static folder, usually same as Output Directory)

Recommended settings for classic:

| Item | Value |
| --- | --- |
| Root Directory | `web/classic` |
| Install Command | `bun install` |
| Build Command | `VITE_REACT_APP_SERVER_URL=https://api.example.com bun run build` |
| Output Directory | `dist` |
| Static Directory | `dist` |

If you choose default:

| Item | Value |
| --- | --- |
| Root Directory | `web/default` |
| Install Command | `bun install` |
| Build Command | `bun run build` |
| Output Directory | `dist` |
| Static Directory | `dist` |

### 3.3 Deploy to ESA PAGES

After deployment, verify:

- `https://app.example.com/` loads assets correctly
- classic frontend can call `https://api.example.com` successfully

## 4. Initialize the system

When `GET /api/setup` returns `status=false` and `root_init=false`, you can initialize by calling:

```bash
curl -X POST 'https://api.example.com/api/setup' \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "admin",
    "password": "YourStrongPass123",
    "confirmPassword": "YourStrongPass123",
    "SelfUseModeEnabled": true,
    "DemoSiteEnabled": false
  }'
```

## 5. Backend paths you should proxy (gateway/same-domain mode)

- `/api`
- `/v1`
- `/v1beta`
- `/pg`
- `/mj`
- `/suno`
- `/kling/v1`
- `/jimeng`

## 6. ICP filing number (both frontends)

The ICP filing number is rendered on the footer and links to `https://beian.miit.gov.cn/`.

- default frontend: `DEFAULT_ICP_FILING_NUMBER` in [constants.ts](./web/default/src/lib/constants.ts)
- classic frontend: `DEFAULT_ICP_FILING_NUMBER` in [common.constant.js](./web/classic/src/constants/common.constant.js)

## License

This project is licensed under [GNU Affero General Public License v3.0 (AGPLv3)](./LICENSE), with additional terms under Section 7. Modified versions must preserve the required attribution and the visible link to the original project (e.g. <https://github.com/QuantumNous/new-api>).
