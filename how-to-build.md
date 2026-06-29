# How to Build & Deploy — new-api

> **项目**：new-api（QuantumNous/new-api）  
> **定位**：下一代 LLM 网关与 AI 资产管理系统，统一代理 40+ 上游 AI 提供商  
> **监控**：本项目强制集成 [Sentry](https://sentry.io/welcome/) 进行错误追踪与性能监控

---

## 目录

1. [技术栈概览](#1-技术栈概览)
2. [环境要求](#2-环境要求)
3. [Sentry 集成说明](#3-sentry-集成说明)
4. [本地开发环境搭建](#4-本地开发环境搭建)
5. [手动构建（不使用 Docker）](#5-手动构建不使用-docker)
6. [Docker 单机部署](#6-docker-单机部署)
7. [Docker Compose 完整部署](#7-docker-compose-完整部署)
8. [生产环境配置清单](#8-生产环境配置清单)
9. [数据库选型指南](#9-数据库选型指南)
10. [多节点集群部署](#10-多节点集群部署)
11. [环境变量参考表](#11-环境变量参考表)
12. [健康检查与监控](#12-健康检查与监控)
13. [常见问题排查](#13-常见问题排查)

---

## 1. 技术栈概览

| 层次 | 技术 |
|------|------|
| 后端语言 | Go 1.25+ |
| Web 框架 | Gin |
| ORM | GORM v2 |
| 数据库 | SQLite / MySQL ≥ 5.7.8 / PostgreSQL ≥ 9.6（三者同时支持） |
| 缓存 | Redis（go-redis v8） + 内存缓存 |
| 认证 | JWT、WebAuthn/Passkeys、OAuth（GitHub/Discord/OIDC 等） |
| 前端（默认） | React 19、TypeScript、Rsbuild、Base UI、Tailwind CSS v4 |
| 前端（经典） | React 18、Vite、Semi Design |
| 前端包管理 | Bun（优先）|
| 错误监控 | **Sentry**（`github.com/getsentry/sentry-go`） |
| 性能剖析 | Grafana Pyroscope（可选） |
| 容器基础镜像 | `debian:bookworm-slim` |

项目架构分层：`Router → Controller → Service → Model`

---

## 2. 环境要求

### 构建机器

| 工具 | 最低版本 | 说明 |
|------|----------|------|
| Go | 1.22+ | 生产 Dockerfile 使用 1.26.1 |
| Bun | 1.x | 前端构建，优先于 npm/yarn/pnpm |
| Docker | 20.10+ | 容器化部署 |
| Docker Compose | 2.x | 多服务编排 |
| Git | 任意 | 拉取代码 |

### 运行时依赖

| 服务 | 版本要求 | 用途 |
|------|----------|------|
| PostgreSQL | ≥ 9.6（推荐 15） | 主数据库（生产推荐） |
| MySQL | ≥ 5.7.8（推荐 8.x） | 主数据库（备选） |
| SQLite | 3.x | 主数据库（轻量单节点场景） |
| Redis | ≥ 6.x（推荐 7.x） | 缓存、分布式锁、多节点同步 |

---

## 3. Sentry 集成说明

> **本项目必须使用 Sentry 进行错误监控与性能追踪。**

### 3.1 Sentry 在代码中的位置

Sentry 在 `main.go` 中被初始化，**位于所有业务逻辑启动之前**：

```go
// main.go
err := sentry.Init(sentry.ClientOptions{
    Dsn:              "<YOUR_SENTRY_DSN>",       // 从 Sentry 控制台获取
    Release:          "new-api@" + common.Version,
    EnableTracing:    true,
    TracesSampleRate: 1.0,
    SendDefaultPII:   true,
})
defer sentry.Flush(2 * time.Second)
```

Sentry 中间件同时挂载到 Gin 路由器（必须在 Recovery 中间件之前）：

```go
server.Use(sentrygin.New(sentrygin.Options{
    Repanic: true,
}))
```

### 3.2 创建 Sentry 项目

1. 登录 [https://sentry.io/](https://sentry.io/)，新建 Organization 和 Project
2. 语言/平台选择 **Go**
3. 复制生成的 DSN（格式：`https://<key>@oXXXXXX.ingest.sentry.io/<project-id>`）

### 3.3 配置 Sentry DSN

**方式一：环境变量（推荐）**

```bash
export SENTRY_DSN="https://<key>@oXXXXXX.ingest.sentry.io/<project-id>"
```

然后在 `main.go` 中改为读取环境变量：

```go
sentry.Init(sentry.ClientOptions{
    Dsn:              os.Getenv("SENTRY_DSN"),
    Release:          "new-api@" + common.Version,
    Environment:      os.Getenv("SENTRY_ENVIRONMENT"), // 如 "production" / "staging"
    EnableTracing:    true,
    TracesSampleRate: 1.0,
    SendDefaultPII:   true,
})
```

**方式二：`.env` 文件**

项目启动时会自动加载 `.env` 文件（通过 `github.com/joho/godotenv`）：

```ini
# .env
SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=production
```

**方式三：Docker Compose 环境变量**

```yaml
environment:
  - SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
  - SENTRY_ENVIRONMENT=production
```

### 3.4 Sentry Release 与版本追踪

项目使用 `VERSION` 文件标记版本，构建时通过 ldflags 注入：

```bash
go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api
```

Sentry Release 字段自动为 `new-api@<VERSION>`，便于在 Sentry 控制台追踪每个版本的错误率。

### 3.5 建议的 Sentry 采样率配置

| 环境 | TracesSampleRate | 说明 |
|------|-----------------|------|
| 开发 | `1.0` | 全量追踪，方便调试 |
| 预发 | `0.5` | 采样 50% |
| 生产 | `0.1` | 按流量酌情调整，避免超出配额 |

---

## 4. 本地开发环境搭建

### 4.1 克隆代码

```bash
git clone https://github.com/QuantumNous/new-api.git
cd new-api
```

### 4.2 启动后端依赖服务（PostgreSQL + Redis）

```bash
docker compose -f docker-compose.dev.yml up -d
```

该命令会启动：
- `new-api-dev-pg`：PostgreSQL 15（端口仅内网可用）
- `new-api-dev-redis`：Redis 7

等待 PostgreSQL 健康检查通过（约 10 秒）。

### 4.3 创建 `.env` 文件

```ini
# .env（本地开发）
SQL_DSN=postgresql://root:123456@localhost:5432/new-api
REDIS_CONN_STRING=redis://localhost:6379
SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=development
GIN_MODE=debug
BATCH_UPDATE_ENABLED=true
ERROR_LOG_ENABLED=true
```

> 注意：`docker-compose.dev.yml` 中 PostgreSQL 端口未暴露给宿主机。如需本地直连，需在 `docker-compose.dev.yml` 的 `postgres` 服务中取消注释 `ports: - "5432:5432"`，或通过以下方式启动后端：

```bash
# 直接以 Docker 内网跑后端（推荐，省去端口映射）
docker compose -f docker-compose.dev.yml up -d
```

### 4.4 启动前端开发服务器

```bash
# 默认主题（React 19 + Rsbuild）
cd web/default
bun install
bun run dev
# 访问 http://localhost:3001，API 自动代理到 :3000
```

```bash
# 经典主题（React 18 + Vite）
cd web/classic
bun install
bun run dev
```

### 4.5 使用 Makefile 一键启动

```bash
# 启动后端 Docker 依赖 + 前端开发服务器
make dev

# 仅启动后端服务
make dev-api

# 重新构建并启动后端 Docker 容器
make dev-api-rebuild

# 重置本地初始化向导状态（清空 setup 记录）
make reset-setup
```

---

## 5. 手动构建（不使用 Docker）

### 5.1 构建前端

```bash
# 默认主题
cd web/default
bun install
DISABLE_ESLINT_PLUGIN=true VITE_REACT_APP_VERSION=$(cat ../../VERSION) bun run build
# 产物输出到 web/default/dist/

# 经典主题
cd web/classic
bun install
VITE_REACT_APP_VERSION=$(cat ../../VERSION) bun run build
# 产物输出到 web/classic/dist/
```

### 5.2 构建后端

```bash
cd <项目根目录>

# 设置构建参数
export CGO_ENABLED=0
export GOEXPERIMENT=greenteagc   # 启用 GreenTea GC（Go 实验性 GC 优化）

# 编译（将 VERSION 注入为 common.Version）
go build \
  -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" \
  -o new-api \
  .
```

### 5.3 运行

```bash
# 设置必要环境变量
export SQL_DSN="postgresql://user:password@host:5432/new-api"
export REDIS_CONN_STRING="redis://:password@host:6379"
export SESSION_SECRET="your-random-secret-here"
export SENTRY_DSN="https://<key>@oXXXXXX.ingest.sentry.io/<project-id>"
export SENTRY_ENVIRONMENT="production"

# 启动服务（默认监听 :3000）
./new-api --port 3000 --log-dir ./logs
```

---

## 6. Docker 单机部署

### 6.1 使用官方镜像

```bash
docker pull calciumion/new-api:latest

docker run -d \
  --name new-api \
  --restart always \
  -p 3000:3000 \
  -v $(pwd)/data:/data \
  -v $(pwd)/logs:/app/logs \
  -e SQL_DSN="postgresql://user:password@host:5432/new-api" \
  -e REDIS_CONN_STRING="redis://:password@host:6379" \
  -e SESSION_SECRET="your-random-secret-$(openssl rand -hex 16)" \
  -e SENTRY_DSN="https://<key>@oXXXXXX.ingest.sentry.io/<project-id>" \
  -e SENTRY_ENVIRONMENT="production" \
  -e BATCH_UPDATE_ENABLED=true \
  -e ERROR_LOG_ENABLED=true \
  -e TZ=Asia/Shanghai \
  calciumion/new-api:latest \
  --log-dir /app/logs
```

### 6.2 本地构建镜像

```bash
docker build \
  --platform linux/amd64 \
  -t new-api:local \
  .
```

跨平台构建（如 ARM64）：

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t new-api:local \
  --push .
```

---

## 7. Docker Compose 完整部署

### 7.1 获取配置文件

```bash
# 下载或复制 docker-compose.yml 到部署目录
cp docker-compose.yml /opt/new-api/
cd /opt/new-api/
```

### 7.2 修改生产配置

编辑 `docker-compose.yml`，**必须修改以下内容**：

```yaml
services:
  new-api:
    environment:
      # 数据库连接（PostgreSQL）
      - SQL_DSN=postgresql://root:<强密码>@postgres:5432/new-api
      # Redis 连接
      - REDIS_CONN_STRING=redis://:<强密码>@redis:6379
      # Session 密钥（多节点时必须一致）
      - SESSION_SECRET=<随机32位字符串>
      # Sentry 监控（必填）
      - SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
      - SENTRY_ENVIRONMENT=production
      # 时区
      - TZ=Asia/Shanghai
      # 节点名称（多节点时区分身份）
      - NODE_NAME=new-api-node-1
      # 推荐开启
      - BATCH_UPDATE_ENABLED=true
      - ERROR_LOG_ENABLED=true

  redis:
    command: ["redis-server", "--requirepass", "<强密码>"]

  postgres:
    environment:
      POSTGRES_PASSWORD: <强密码>
```

### 7.3 启动服务

```bash
# 首次启动
docker compose up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f new-api

# 停止服务
docker compose down

# 停止并清除数据（危险操作！）
docker compose down -v
```

### 7.4 升级版本

```bash
docker compose pull
docker compose up -d --force-recreate new-api
```

### 7.5 使用 MySQL 替代 PostgreSQL

修改 `docker-compose.yml`：

1. 注释掉 `postgres` 服务和 PostgreSQL 的 `SQL_DSN`
2. 取消注释 `mysql` 服务和 MySQL 的 `SQL_DSN`：
   ```yaml
   - SQL_DSN=root:<强密码>@tcp(mysql:3306)/new-api
   ```
3. 在 `depends_on` 中将 `postgres` 替换为 `mysql`
4. 取消注释 `volumes` 中的 `mysql_data`

---

## 8. 生产环境配置清单

部署前请逐项核查：

- [ ] **数据库密码**已从默认 `123456` 修改为强密码
- [ ] **Redis 密码**已修改
- [ ] **SESSION_SECRET** 已设置为随机字符串（多节点所有实例必须相同）
- [ ] **SENTRY_DSN** 已配置且 `SENTRY_ENVIRONMENT=production`
- [ ] **NODE_NAME** 已设置（多节点时每个节点唯一）
- [ ] 日志目录 `./logs` 挂载到持久化存储
- [ ] 数据目录 `./data` 挂载到持久化存储
- [ ] 防火墙仅开放 3000 端口，数据库与 Redis 端口不对外暴露
- [ ] 配置 Nginx/Caddy 反向代理并启用 HTTPS
- [ ] 配置定期数据库备份

---

## 9. 数据库选型指南

| 场景 | 推荐方案 | 配置示例 |
|------|----------|----------|
| 个人/轻量部署 | SQLite | 不设置 `SQL_DSN`，默认使用 `one-api.db` |
| 中小规模生产 | PostgreSQL 15 | `SQL_DSN=postgresql://user:pass@host:5432/new-api` |
| 已有 MySQL 环境 | MySQL 8.x | `SQL_DSN=root:pass@tcp(host:3306)/new-api` |

**SQLite 路径自定义：**

```bash
export SQLITE_PATH=/data/new-api.db
```

**注意**：所有数据库代码同时兼容三种数据库，迁移时需保证 SQL 语法通用性（详见 `AGENTS.md` Rule 2）。

---

## 10. 多节点集群部署

多节点部署时需要额外配置：

```yaml
environment:
  # 所有节点必须使用相同的 SESSION_SECRET
  - SESSION_SECRET=<全局统一随机字符串>
  # 标识当前节点身份（每个节点唯一）
  - NODE_NAME=new-api-node-2
  # 指定主节点（从节点设置为 slave）
  - NODE_TYPE=slave   # 主节点不设置或设为 master
  # 设置同步频率（秒）
  - SYNC_FREQUENCY=60
  # 共用同一个 Redis 实例
  - REDIS_CONN_STRING=redis://:<密码>@redis-cluster:6379
  # 共用同一个数据库
  - SQL_DSN=postgresql://user:pass@pg-primary:5432/new-api
```

**主节点（Master）**职责：
- 执行任务调度（Midjourney、异步任务等）
- `IsMasterNode = true`（默认，`NODE_TYPE` 不为 `slave`）

**从节点（Slave）**：
- 负责 API 转发，不执行任务调度
- 设置 `NODE_TYPE=slave`

---

## 11. 环境变量参考表

### 核心配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `SQL_DSN` | — | 数据库连接字符串（不设置则使用 SQLite） |
| `SQLITE_PATH` | `one-api.db` | SQLite 数据库文件路径 |
| `REDIS_CONN_STRING` | — | Redis 连接字符串 |
| `SESSION_SECRET` | 随机值 | Session 加密密钥，多节点时必须统一设置 |
| `CRYPTO_SECRET` | 同 `SESSION_SECRET` | 数据加密密钥 |
| `PORT` | `3000` | HTTP 监听端口（也可用 `--port` 命令行参数） |
| `TZ` | 系统时区 | 时区设置，推荐 `Asia/Shanghai` |

### Sentry 配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `SENTRY_DSN` | — | **必填**，Sentry DSN 地址 |
| `SENTRY_ENVIRONMENT` | — | 环境标识（如 `production`、`staging`） |

### 性能与缓存

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `BATCH_UPDATE_ENABLED` | `false` | 是否启用批量数据库更新 |
| `BATCH_UPDATE_INTERVAL` | `5` | 批量更新间隔（秒） |
| `SYNC_FREQUENCY` | `60` | 缓存同步频率（秒） |
| `MEMORY_CACHE_ENABLED` | `false` | 是否启用内存缓存（有 Redis 时自动开启） |
| `REDIS_POOL_SIZE` | `10` | Redis 连接池大小 |

### 流量控制

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `STREAMING_TIMEOUT` | `300` | 流式响应超时（秒） |
| `RELAY_TIMEOUT` | `0` | 中继请求超时（秒，0 为不限制） |
| `GLOBAL_API_RATE_LIMIT` | `180` | API 全局速率限制（次/周期） |
| `GLOBAL_API_RATE_LIMIT_DURATION` | `180` | API 速率限制周期（秒） |

### 节点与集群

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `NODE_NAME` | — | 节点名称，用于审计日志标识 |
| `NODE_TYPE` | `master` | 节点类型，设为 `slave` 关闭任务调度 |

### 功能开关

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `ERROR_LOG_ENABLED` | `false` | 是否记录错误日志 |
| `DEBUG` | `false` | 调试模式（同时影响 Gin 日志级别） |
| `GIN_MODE` | `release` | 设为 `debug` 开启 Gin 详细日志 |
| `ENABLE_PPROF` | `false` | 开启 pprof 性能分析（监听 :8005） |
| `FORCE_STREAM_OPTION` | `true` | 强制返回 usage 信息 |
| `USE_FRONTEND` | `true` | 设为 `false` 禁用前端，仅提供 API |
| `GENERATE_DEFAULT_TOKEN` | `false` | 是否为新用户生成初始令牌 |

### 分析埋点（可选）

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `GOOGLE_ANALYTICS_ID` | — | Google Analytics 测量 ID |
| `UMAMI_WEBSITE_ID` | — | Umami 网站 ID |
| `UMAMI_SCRIPT_URL` | Umami 官方 CDN | 自托管 Umami 时修改此地址 |

---

## 12. 健康检查与监控

### 内置健康检查接口

```bash
curl http://localhost:3000/api/status
# 响应示例：{"success": true, "message": "ok", ...}
```

Docker Compose 中已配置自动健康检查（每 30s 检测一次）。

### Sentry 监控验证

部署后可发送一个测试错误验证 Sentry 是否正常工作：

```bash
# 查看启动日志，确认 Sentry 初始化成功
docker compose logs new-api | grep -i sentry
# 期望输出：Sentry initialized successfully
```

### Pyroscope 持续性能剖析（可选）

如需启用 Grafana Pyroscope 持续性能分析：

```bash
export PYROSCOPE_SERVER_ADDRESS=http://pyroscope-server:4040
export PYROSCOPE_APP_NAME=new-api
```

代码中通过 `common.StartPyroScope()` 自动初始化。

---

## 13. 常见问题排查

### Q1：启动时报 `SESSION_SECRET` 错误

```
Please set SESSION_SECRET to a random string.
```

**原因**：`SESSION_SECRET` 被设置为默认值 `random_string`。  
**解决**：将其改为一个真正的随机字符串，如 `openssl rand -hex 32` 的输出。

---

### Q2：前端页面空白或 404

**原因**：前端构建产物未放置在正确位置。  
**解决**：
- Docker 部署：确认 Dockerfile 多阶段构建成功执行了前端 `bun run build`
- 手动部署：确认 `web/default/dist/` 和 `web/classic/dist/` 下存在 `index.html`
- 设置 `USE_FRONTEND=false` 可跳过前端，仅提供 API

---

### Q3：Sentry 初始化失败

```
Sentry initialization failed: ...
```

**原因**：DSN 格式错误或网络不通。  
**解决**：
1. 检查 `SENTRY_DSN` 是否正确（从 Sentry 控制台复制完整 DSN）
2. 确认部署机器能访问 `sentry.io` 或自托管 Sentry 地址
3. 初始化失败不影响主服务启动，但错误信息将不被上报

---

### Q4：数据库连接失败

**PostgreSQL**：
```
failed to initialize database: ...
```
检查 `SQL_DSN` 格式：`postgresql://user:password@host:5432/dbname`

**MySQL**：
```
SQL_DSN=root:password@tcp(host:3306)/dbname
```

**SQLite**（默认）：确认文件路径有写权限。

---

### Q5：Redis 连接失败

```
REDIS_CONN_STRING not set, Redis is not enabled
```
这是正常提示（未配置 Redis 时使用内存缓存）。  
如需启用 Redis，设置：
```bash
export REDIS_CONN_STRING=redis://:password@host:6379
```

---

### Q6：多节点 Session 失效

**原因**：各节点 `SESSION_SECRET` 不一致。  
**解决**：确保所有节点使用完全相同的 `SESSION_SECRET` 值。

---

## 附录：快速启动命令速查

```bash
# 开发环境一键启动
make dev

# 生产 Docker Compose 启动
docker compose up -d

# 查看实时日志
docker compose logs -f new-api

# 手动构建全流程
make build-all-frontends && go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api .

# 构建 Docker 镜像
docker build -t new-api:local .

# 健康检查
curl http://localhost:3000/api/status
```

---

*文档生成时间：2026-06-22 | 适用版本：new-api v1.0.0-rc.10+*
