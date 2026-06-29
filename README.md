# New API（中文部署版）

[English README](./README-en.md)

本 README 基于仓库现有部署文档与本次落地的改造点，给出一套可复现的“Ubuntu 裸机后端 + 宝塔 Nginx 反向代理 + 阿里云 ESA PAGES 前端 + 官方 Sentry”部署流程。

如果你只想快速跑起来，也可以用 Docker Compose（见下文“Docker 快速启动”）。

## 重要说明

- 本项目为 **New API**（QuantumNous 维护）的 LLM 网关与 AI 资产管理系统。
- 使用上游模型服务前，请确保你已合法获得相应服务、账号、Key 与权限，并遵守上游条款与本地法律法规。
- 如向公众提供生成式 AI 服务，请确保完成备案、许可、内容安全、日志留存、个人信息保护等合规义务。

## 文档导航

- 项目使用说明（目录结构/配置项/构建）：[how-to-use.md](./how-to-use.md)
- Sentry（官方/自建/禁用三模式）：[how-to-use-sentry.md](./how-to-use-sentry.md)
- Ubuntu 裸机运行 + 官方 Sentry： [how-to-run-ubuntu-official-sentry.md](./how-to-run-ubuntu-official-sentry.md)
- 前端独立编译： [how-to-build-frontend.md](./how-to-build-frontend.md)
- Windows 构建脚本（可交叉编译 Ubuntu 后端/导出 Pages 产物）：[build-windows.ps1](./build-windows.ps1)
- systemd 示例： [new-api.service](./new-api.service)
- Nginx 示例： [nginx.conf](./nginx.conf)

## 推荐部署拓扑（阿里云 ESA PAGES + 宝塔 + Ubuntu 裸机）

推荐使用双域名：

- `app.example.com`：托管在阿里云 ESA PAGES 的前端（推荐 classic 前端）
- `api.example.com`：指向 Ubuntu（宝塔/Nginx 反代到 `127.0.0.1:3000`）

这样前端与后端彻底解耦，运维最简单。

## 1. Ubuntu 裸机部署后端（不使用 Docker）

### 1.1 准备基础环境

推荐：

- Ubuntu 20.04 / 22.04 / 24.04
- PostgreSQL（生产推荐）
- Redis（推荐启用）

### 1.2 获取后端可执行文件

两种方式任选其一：

**方式 A：Windows 交叉编译 Ubuntu 后端（二进制上传到 Ubuntu）**

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -BackendTargetOS ubuntu -SkipDefaultFrontend -SkipClassicFrontend
```

产物默认在：

- `dist/artifacts/backend/linux-amd64/`

目录内会包含：

- `new-api-<version>`
- `run-ubuntu.sh`
- `README-ubuntu.md`

**方式 B：在 Ubuntu 本机编译**

```bash
git clone https://github.com/VupHub/new-api.git
cd new-api
go mod download
go build -ldflags "-s -w -X github.com/QuantumNous/new-api/common.Version=v0.0.0-ubuntu" -o new-api .
```

### 1.3 上传并落盘到 Ubuntu

以 `/opt/new-api` 为例：

```bash
sudo mkdir -p /opt/new-api
sudo chown -R $USER:$USER /opt/new-api
```

把二进制与脚本上传到 `/opt/new-api/`，并赋权：

```bash
cd /opt/new-api
chmod +x ./new-api-* ./run-ubuntu.sh 2>/dev/null || true
chmod +x ./new-api 2>/dev/null || true
```

### 1.4 配置 `.env`（示例：PostgreSQL + Redis + 官方 Sentry）

创建 `/opt/new-api/.env`：

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

说明：

- `SESSION_SECRET` 不能是占位值 `random_string`，否则程序会直接退出
- 使用官方 Sentry 时必须：`SENTRY_MODE=official` 且 `SENTRY_DSN` 为 `sentry.io` 官方 DSN

### 1.5 手工启动验证

```bash
set -a
source /opt/new-api/.env
set +a
cd /opt/new-api
./run-ubuntu.sh
```

自检：

```bash
curl http://127.0.0.1:3000/api/status
curl http://127.0.0.1:3000/api/setup
```

### 1.6 配置 systemd（推荐）

1) 创建运行用户：

```bash
sudo useradd --system --home /opt/new-api --shell /usr/sbin/nologin new-api
sudo chown -R new-api:new-api /opt/new-api
```

2) 安装 service：

```bash
sudo cp /opt/new-api/new-api.service /etc/systemd/system/new-api.service 2>/dev/null || true
sudo cp ./new-api.service /etc/systemd/system/new-api.service
sudo systemctl daemon-reload
sudo systemctl enable new-api
sudo systemctl restart new-api
sudo systemctl status new-api --no-pager
```

如果你看到 `status=217/USER`，说明 `User=new-api` 不存在或目录权限不正确。

## 2. 宝塔面板 Nginx 反向代理（api.example.com）

目标：把公网域名 `https://api.example.com` 反代到 `http://127.0.0.1:3000`。

关键点：

- 站点类型选“纯静态”
- 开启 SSL + 强制 HTTPS
- 反向代理目标使用 `127.0.0.1:3000`（不要用公网 IP）

反代后建议验证：

```bash
curl https://api.example.com/api/status
```

## 3. 部署前端到阿里云 ESA PAGES（推荐 classic）

### 3.1 前端独立编译

参考完整文档：[how-to-build-frontend.md](./how-to-build-frontend.md)

推荐 classic 前端用于阿里云 ESA PAGES（支持设置后端地址）：

```bash
cd web/classic
bun install
VITE_REACT_APP_SERVER_URL="https://api.example.com" bun run build
```

产物：

- `web/classic/dist/`

### 3.2 ESA PAGES 构建配置（根目录/输出目录/静态目录）

阿里云 ESA PAGES 通常需要配置以下 3 项（名称可能因控制台版本略有差异）：

- 根目录（Root Directory）：前端项目所在目录
- 构建输出目录（Output Directory）：构建产物输出目录
- 静态文件目录（Static Directory）：对外发布的静态文件目录（通常同 Output Directory）

推荐配置（classic 前端）：

| 配置项 | 值 |
| --- | --- |
| 根目录 | `web/classic` |
| 依赖安装命令 | `bun install` |
| 构建命令 | `VITE_REACT_APP_SERVER_URL=https://api.example.com bun run build` |
| 输出目录 | `dist` |
| 静态文件目录 | `dist` |

如果你选择 default 前端（更偏同源模式）：

| 配置项 | 值 |
| --- | --- |
| 根目录 | `web/default` |
| 依赖安装命令 | `bun install` |
| 构建命令 | `bun run build` |
| 输出目录 | `dist` |
| 静态文件目录 | `dist` |

### 3.3 上传到 ESA PAGES

将构建产物部署到 ESA PAGES 后，建议验证：

- `https://app.example.com/` 能正常加载静态资源
- 能登录/访问控制台页面
- 前端能正确请求 `https://api.example.com`（classic 前端）

说明：

- ESA PAGES 在线构建模式下，不需要你手工上传 `dist`，由 ESA 在构建后自动发布
- 如果你希望离线打包再上传，可使用脚本导出 Pages 产物（见 [build-windows.ps1](./build-windows.ps1) 的 `-ExportFrontendForPages`），产物目录为 `dist/artifacts/pages/classic` 或 `dist/artifacts/pages/default`

## 4. 初始化系统（无需 ESA PAGES 先上线）

当 `/api/setup` 返回：

```json
{"data":{"status":false,"root_init":false},"success":true}
```

说明系统尚未初始化，可以直接调用初始化接口创建管理员：

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

## 5. 需要回源到后端的路径（同域/网关场景）

如果你未来做“同域名网关”，这些路径应转发到后端：

- `/api`
- `/v1`
- `/v1beta`
- `/pg`
- `/mj`
- `/suno`
- `/kling/v1`
- `/jimeng`

## 6. 备案号配置（两套前端）

备案号展示在页脚 `© {year} {SystemName}. 版权所有` 右侧，并链接到 `https://beian.miit.gov.cn/`。

- 默认前端：修改 [constants.ts](./web/default/src/lib/constants.ts) 的 `DEFAULT_ICP_FILING_NUMBER`
- 经典前端：修改 [common.constant.js](./web/classic/src/constants/common.constant.js) 的 `DEFAULT_ICP_FILING_NUMBER`

## 7. Docker 快速启动（可选）

如果你暂时不需要 Pages/宝塔/裸机部署，快速启动可用：

```bash
git clone https://github.com/VupHub/new-api.git
cd new-api
docker compose up -d
```

## License

本项目使用 [GNU Affero General Public License v3.0 (AGPLv3)](./LICENSE)。

AGPLv3 Section 7 存在附加条款：修改后的版本必须保留 UI 中的作者归属声明与原项目链接（例如保留 <https://github.com/QuantumNous/new-api> 的可见链接）。
