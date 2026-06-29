# Ubuntu 直接运行 + 官方 Sentry 逐步运行指导

> 适用目标：
> 1. 后端运行在 Ubuntu 裸机或云主机上
> 2. 不使用 Docker 运行 `new-api` 后端
> 3. Sentry 使用官方 SaaS，即 [Sentry Welcome](https://sentry.io/welcome/)
>
> 本文只覆盖后端直接运行方案。前端可单独使用反向代理、静态托管或 Pages。

## 1. 运行方式说明

当前仓库已经支持三种 Sentry 模式：

- `official`
- `self-hosted`
- `disabled`

如果你要使用官方 Sentry，必须满足以下条件：

- `SENTRY_MODE=official`
- `SENTRY_DSN` 必须是 `sentry.io` 域名对应的官方 DSN

如果 `SENTRY_MODE=official` 但 `SENTRY_DSN` 不是官方 DSN，程序会自动禁用 Sentry 初始化并输出错误日志。

## 2. 推荐部署拓扑

推荐在 Ubuntu 上采用以下结构：

- `new-api` 后端进程：直接运行二进制文件
- 数据库：PostgreSQL 或 MySQL，生产推荐 PostgreSQL
- 缓存：Redis，建议启用
- 监控：官方 Sentry SaaS
- 反向代理：Nginx 或 Caddy

如果你只是先验证能否启动，可以使用 SQLite 并暂时不启用 Redis。

## 3. 前置条件

### 3.1 Ubuntu 版本

推荐版本：

- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

### 3.2 最低资源建议

| 项目 | 最低建议 | 生产建议 |
| --- | --- | --- |
| CPU | 2 vCPU | 4 vCPU+ |
| 内存 | 2 GB | 8 GB+ |
| 磁盘 | 10 GB | 50 GB+ SSD |
| 网络 | 可访问数据库、Redis、`sentry.io` | 固定出口、低抖动 |

### 3.3 必备软件

Ubuntu 上至少需要：

```bash
sudo apt update
sudo apt install -y curl wget git ca-certificates tar
```

如果你打算在 Ubuntu 本机直接编译，还需要：

```bash
sudo apt install -y build-essential
```

## 4. 第一步：在官方 Sentry 创建项目

### 4.1 登录官方入口

打开：

- [https://sentry.io/welcome/](https://sentry.io/welcome/)

### 4.2 创建组织和项目

建议至少创建一个后端项目：

- 项目平台：`Go`
- 项目名称：`new-api-backend`

### 4.3 记录 DSN

创建完成后，在 Sentry 项目设置中记录 DSN，例如：

```text
https://<public-key>@oXXXXXX.ingest.sentry.io/<project-id>
```

后续会写入 Ubuntu 服务器上的 `.env` 文件。

### 4.4 建议环境命名

建议统一使用：

| 环境 | 建议值 |
| --- | --- |
| 本地 | `development` |
| 测试 / 预发 | `staging` |
| 生产 | `production` |

## 5. 第二步：准备后端程序

你可以二选一：

1. 在 Windows 上交叉编译 Ubuntu 二进制，再上传到 Ubuntu
2. 在 Ubuntu 机器上直接源码编译

### 5.1 方案 A：在 Windows 上构建 Ubuntu 二进制

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -BackendTargetOS ubuntu -SkipDefaultFrontend -SkipClassicFrontend
```

构建完成后，产物默认位于：

```text
dist/artifacts/backend/linux-amd64/
```

该目录通常包含：

- `new-api-<version>`
- `run-ubuntu.sh`
- `README-ubuntu.md`

如果你的 Ubuntu 是 ARM64 架构，例如部分云主机或 Oracle ARM 实例，改用：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -BackendTargetOS ubuntu -BackendTargetArch arm64 -SkipDefaultFrontend -SkipClassicFrontend
```

### 5.2 方案 B：在 Ubuntu 上直接编译

#### 步骤 1：安装 Go

请确保 Go 版本不低于 `1.22`，推荐使用更新稳定版。

安装后验证：

```bash
go version
```

#### 步骤 2：克隆源码

```bash
git clone https://github.com/QuantumNous/new-api.git
cd new-api
```

#### 步骤 3：下载依赖

```bash
go mod download
```

#### 步骤 4：编译

```bash
go build -ldflags "-s -w -X github.com/QuantumNous/new-api/common.Version=v0.0.0-manual" -o new-api .
```

如果你已经准备好版本号，也可以改成自己的版本标识，例如：

```bash
go build -ldflags "-s -w -X github.com/QuantumNous/new-api/common.Version=v1.0.0-ubuntu" -o new-api .
```

## 6. 第三步：把程序放到 Ubuntu

以下示例假设你的部署目录为 `/opt/new-api`。

### 6.1 创建目录

```bash
sudo mkdir -p /opt/new-api
sudo chown -R $USER:$USER /opt/new-api
cd /opt/new-api
```

### 6.2 上传文件

如果你是从 Windows 构建完成后上传，建议把整个 `linux-amd64` 目录内容上传到 `/opt/new-api/`。

上传后目录建议形如：

```text
/opt/new-api/
├── new-api-v0.0.0-dev
├── run-ubuntu.sh
└── README-ubuntu.md
```

如果你是在 Ubuntu 本机编译，则至少保证目录中有：

```text
/opt/new-api/
└── new-api
```

## 7. 第四步：准备运行账号

生产环境不建议直接使用 `root` 运行。

可以创建单独用户：

```bash
sudo useradd --system --home /opt/new-api --shell /usr/sbin/nologin new-api
sudo chown -R new-api:new-api /opt/new-api
```

如果你当前只是临时测试，可以先跳过这一步，后续再切换到 `systemd` 方案。

## 8. 第五步：准备 `.env` 文件

在 `/opt/new-api/.env` 创建运行配置。

### 8.1 最小可运行示例

这个示例适合先跑通：

```ini
PORT=3000
GIN_MODE=release
DEBUG=false
USE_FRONTEND=false

SESSION_SECRET=replace-with-a-random-32-char-string
CRYPTO_SECRET=replace-with-another-random-32-char-string

SQLITE_PATH=one-api.db

SENTRY_MODE=official
SENTRY_DSN=https://<public-key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=new-api@ubuntu-manual
SENTRY_ENABLE_TRACING=true
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_DEBUG=false
SENTRY_SEND_DEFAULT_PII=false
```

### 8.2 推荐生产示例

如果你已经准备好 PostgreSQL 和 Redis，建议使用：

```ini
PORT=3000
GIN_MODE=release
DEBUG=false
USE_FRONTEND=false

SESSION_SECRET=replace-with-a-random-32-char-string
CRYPTO_SECRET=replace-with-another-random-32-char-string

SQL_DSN=postgresql://newapi:strong-password@127.0.0.1:5432/new-api
REDIS_CONN_STRING=redis://127.0.0.1:6379/0

ERROR_LOG_ENABLED=true
BATCH_UPDATE_ENABLED=true
SYNC_FREQUENCY=60
NODE_NAME=ubuntu-prod-1

SENTRY_MODE=official
SENTRY_DSN=https://<public-key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=new-api@ubuntu-prod-1
SENTRY_ENABLE_TRACING=true
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_DEBUG=false
SENTRY_SEND_DEFAULT_PII=false
```

### 8.3 关键参数说明

| 参数 | 含义 | 取值范围 | 默认值 | 是否建议显式设置 |
| --- | --- | --- | --- | --- |
| `PORT` | 服务监听端口 | `1-65535` | `3000` | 是 |
| `GIN_MODE` | Gin 运行模式 | `debug` / `release` | 非 `debug` 时按 `release` | 是 |
| `DEBUG` | 调试日志开关 | `true` / `false` | `false` | 是 |
| `USE_FRONTEND` | 是否让后端托管前端静态文件 | `true` / `false` | `true` | 建议设为 `false` |
| `SESSION_SECRET` | Session 密钥 | 非空随机字符串 | 无安全默认值 | 必须 |
| `CRYPTO_SECRET` | 加密密钥 | 非空随机字符串 | 回退到 `SESSION_SECRET` | 必须 |
| `SQL_DSN` | 主数据库连接串 | PostgreSQL / MySQL DSN | 空 | 生产建议设置 |
| `SQLITE_PATH` | SQLite 文件路径 | 合法路径 | `one-api.db?...` | 最小方案使用 |
| `REDIS_CONN_STRING` | Redis 连接串 | `redis://...` | 空时禁用 Redis | 生产建议设置 |
| `SENTRY_MODE` | Sentry 模式 | `official` / `self-hosted` / `disabled` | 自动推断或禁用 | 官方 Sentry 时必须设为 `official` |
| `SENTRY_DSN` | 官方 Sentry DSN | `https://...sentry.io/...` | 空 | 必须 |
| `SENTRY_ENVIRONMENT` | 环境名 | `development` / `staging` / `production` | `production` 或按 `DEBUG` 推断 | 建议设置 |
| `SENTRY_RELEASE` | 发布版本标识 | 自定义字符串 | `new-api@<version>` | 建议设置 |
| `SENTRY_ENABLE_TRACING` | 是否启用 tracing | `true` / `false` | `true` | 建议设置 |
| `SENTRY_TRACES_SAMPLE_RATE` | tracing 采样率 | `0.0-1.0` | `0.1` | 建议设置 |
| `SENTRY_DEBUG` | SDK 调试日志 | `true` / `false` | 跟随 `DEBUG` | 建议生产设为 `false` |
| `SENTRY_SEND_DEFAULT_PII` | 是否发送默认 PII | `true` / `false` | `false` | 建议保持 `false` |

### 8.4 必须注意的事项

- `SESSION_SECRET` 不能设置为 `random_string`，否则程序会直接退出
- `SENTRY_MODE=official` 时，`SENTRY_DSN` 必须使用官方 `sentry.io` DSN
- 如果你不想让后端托管前端静态文件，建议显式设置 `USE_FRONTEND=false`
- 如果没有配置 `REDIS_CONN_STRING`，程序可以运行，只是 Redis 能力会关闭

## 9. 第六步：首次手工启动

### 9.1 给二进制执行权限

如果你使用的是从 Windows 上传的二进制：

```bash
cd /opt/new-api
chmod +x ./new-api-* ./run-ubuntu.sh 2>/dev/null || true
```

如果你的二进制名就是 `new-api`：

```bash
chmod +x ./new-api
```

### 9.2 加载环境变量并启动

如果目录里有 `.env`，可以使用：

```bash
set -a
source /opt/new-api/.env
set +a
cd /opt/new-api
./new-api
```

如果你上传的是构建脚本生成的文件，二进制名通常带版本号，例如：

```bash
set -a
source /opt/new-api/.env
set +a
cd /opt/new-api
./new-api-v0.0.0-dev
```

### 9.3 启动成功的标志

启动成功后，重点检查：

- 日志中没有数据库初始化失败
- 日志中没有 `Sentry initialization failed`
- 日志中出现 `Sentry initialized successfully`

## 10. 第七步：接口自检

服务启动后，先检查公开状态接口：

```bash
curl http://127.0.0.1:3000/api/status
```

如果返回 `200` 且有 JSON 内容，说明后端基础启动成功。

如果你想确认初始化状态：

```bash
curl http://127.0.0.1:3000/api/setup
```

## 11. 第八步：验证官方 Sentry 是否真正生效

### 11.1 启动日志校验

在应用日志中查找：

```text
Sentry initialized successfully
```

### 11.2 手工异常校验

最实用的方式是先让程序稳定运行，再人为制造一次可控错误或临时加入一条测试消息。

如果你已经有可控测试分支，可以临时在启动后加入：

```go
sentry.CaptureMessage("ubuntu official sentry smoke test")
```

然后重启服务并查看 Sentry 控制台。

### 11.3 控制台验收标准

在 Sentry 后端项目中应至少看到：

- 新事件已创建
- `environment=production`
- `release` 为你设置的 `SENTRY_RELEASE`
- 堆栈和请求上下文可见

## 12. 第九步：配置 systemd 开机自启

推荐把服务托管给 `systemd`。

### 12.1 创建服务文件

创建：

```bash
sudo tee /etc/systemd/system/new-api.service > /dev/null <<'EOF'
[Unit]
Description=new-api backend
After=network.target
Wants=network.target

[Service]
Type=simple
User=new-api
Group=new-api
WorkingDirectory=/opt/new-api
EnvironmentFile=/opt/new-api/.env
ExecStart=/opt/new-api/new-api-v0.0.0-dev
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
```

如果你的实际二进制名不是 `new-api-v0.0.0-dev`，请把 `ExecStart` 改成真实文件名。

### 12.2 重新加载并启动

```bash
sudo systemctl daemon-reload
sudo systemctl enable new-api
sudo systemctl start new-api
```

### 12.3 查看状态

```bash
sudo systemctl status new-api --no-pager
journalctl -u new-api -n 200 --no-pager
```

## 13. 第十步：反向代理和公网访问

如果要对外提供服务，建议使用 Nginx 或 Caddy 做反向代理，并启用 HTTPS。

最小 Nginx 示例：

```nginx
server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

如果前端是独立 Pages 或静态站点，请保证它能访问你的 Ubuntu 后端域名。

## 14. 常见问题排查

### 14.1 程序启动即退出，提示 `SESSION_SECRET`

原因：

- 你把 `SESSION_SECRET` 设成了占位值 `random_string`

处理：

- 换成至少 32 位随机字符串

### 14.2 日志提示 `Sentry official mode requires a sentry.io DSN`

原因：

- 你配置了 `SENTRY_MODE=official`
- 但 `SENTRY_DSN` 不是官方 `sentry.io` 域名

处理：

- 回到官方 Sentry 项目设置页，重新复制 DSN

### 14.3 `/api/status` 打不开

按顺序排查：

1. 检查进程是否存在
2. 检查 `PORT` 是否配置正确
3. 检查数据库是否可连
4. 查看 `journalctl -u new-api -n 200 --no-pager`

### 14.4 想先跑通，不想装 PostgreSQL 和 Redis

可以先使用：

- `SQLITE_PATH=one-api.db`
- 不设置 `REDIS_CONN_STRING`

这适合最小化验证，不建议长期作为正式生产方案。

## 15. 一套可直接复制的最小流程

### 15.1 Windows 构建

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -BackendTargetOS ubuntu -SkipDefaultFrontend -SkipClassicFrontend
```

### 15.2 Ubuntu 部署

```bash
sudo mkdir -p /opt/new-api
sudo chown -R $USER:$USER /opt/new-api
cd /opt/new-api
```

上传二进制后创建 `.env`：

```ini
PORT=3000
GIN_MODE=release
DEBUG=false
USE_FRONTEND=false
SESSION_SECRET=replace-with-a-random-32-char-string
CRYPTO_SECRET=replace-with-another-random-32-char-string
SQLITE_PATH=one-api.db
SENTRY_MODE=official
SENTRY_DSN=https://<public-key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=new-api@ubuntu-manual
SENTRY_ENABLE_TRACING=true
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_DEBUG=false
SENTRY_SEND_DEFAULT_PII=false
```

启动：

```bash
set -a
source /opt/new-api/.env
set +a
cd /opt/new-api
chmod +x ./new-api-* 2>/dev/null || true
./new-api-v0.0.0-dev
```

检查：

```bash
curl http://127.0.0.1:3000/api/status
```

## 16. 结论

如果你的目标是“Ubuntu 裸机直跑 + 官方 Sentry”，最关键的四件事是：

1. 准备可在 Ubuntu 运行的后端二进制
2. 正确设置 `.env`，尤其是 `SESSION_SECRET` 和 `SENTRY_MODE=official`
3. 保证 `SENTRY_DSN` 使用官方 `sentry.io` DSN
4. 启动后用 `/api/status` 和 Sentry 控制台同时验收

如果你后续还需要，我可以继续再补两份配套文件：

- `systemd` 服务模板文件
- `nginx` 反向代理配置示例文件
