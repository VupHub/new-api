# How to Use - new-api

> 适用范围：`e:\new-api-1.0.0-rc.10` 当前仓库
>
> 编写原则：
> 1. 以当前仓库实际存在的目录、脚本、配置入口和源码行为为准。
> 2. 当旧文档与代码不一致时，以源码现状为准，并在文档中显式标注差异。
> 3. 所有命令均按可复制、可复现的方式整理；生产和测试流程分别说明。

## 1. 项目定位

`new-api` 是一个 Go 实现的 AI API 网关与控制台系统，整体采用 `Router -> Controller -> Service -> Model` 分层，统一代理 40+ 上游模型服务，并提供：

- 多上游模型中继与格式转换
- 用户、令牌、配额、计费、支付管理
- 后台管理面板与多主题前端
- OAuth / OIDC / Passkey 等认证能力
- Redis 缓存、性能监控、日志与任务轮询

## 2. 标准化目录结构

下面是按职责归类后的标准目录视图，便于定位开发入口。

```text
new-api/
|-- .github/                  CI、Release、PR 规则
|-- bin/                      历史迁移 SQL 与辅助脚本
|-- common/                   通用基础设施：env、redis、json、日志、监控
|-- constant/                 常量定义
|-- controller/               HTTP 控制器
|-- docs/                     项目补充文档
|-- dto/                      请求/响应 DTO
|-- electron/                 Electron 桌面端封装
|-- i18n/                     后端国际化
|-- logger/                   日志初始化
|-- middleware/               Gin 中间件
|-- model/                    GORM 模型、迁移、OptionMap、数据库初始化
|-- oauth/                    OAuth 提供方实现
|-- pkg/                      内部包，如 billingexpr、cachex、ionet、perf_metrics
|-- relay/                    上游渠道适配与中继逻辑
|   |-- channel/              各模型/厂商适配器
|   |-- common/               中继共用逻辑
|   `-- helper/               定价、流式扫描、请求转换等
|-- router/                   API / Relay / Web 路由注册
|-- service/                  业务服务层
|-- setting/                  系统、模型、支付、性能、运营配置
|-- types/                    共享类型定义
|-- web/
|   |-- default/              默认前端：React 19 + Rsbuild + Tailwind
|   |   |-- src/              页面、组件、hooks、i18n、lib
|   |   |-- scripts/          i18n / 版权脚本
|   |   `-- package.json      默认前端脚本入口
|   `-- classic/              经典前端：React 18 + Vite + Semi
|       |-- src/              页面、helpers、i18n
|       `-- package.json      经典前端脚本入口
|-- .env.example              环境变量样例
|-- Dockerfile                生产镜像构建
|-- Dockerfile.dev            开发后端镜像构建
|-- docker-compose.yml        生产部署编排
|-- docker-compose.dev.yml    本地开发依赖编排
|-- go.mod                    Go 模块定义
|-- main.go                   服务启动入口
|-- makefile                  常用开发命令入口
|-- how-to-build.md           旧版构建说明
`-- VERSION                   版本号
```

### 2.1 关键子目录职责

| 目录 | 用途 | 是否高频修改 |
| --- | --- | --- |
| `main.go` | 服务启动、资源初始化、Gin 中间件、监控初始化 | 高 |
| `router/` | 新接口路由挂载位置 | 高 |
| `controller/` | HTTP 请求处理与参数校验 | 高 |
| `service/` | 核心业务逻辑 | 高 |
| `model/` | 数据结构、迁移、数据库兼容逻辑 | 高 |
| `relay/channel/` | 新上游模型适配入口 | 高 |
| `setting/` | 系统级默认配置与配置结构注册 | 高 |
| `web/default/src/` | 默认前端页面与组件 | 高 |
| `web/classic/src/` | 经典前端页面与组件 | 中 |
| `docs/` | 长文档与部署补充 | 中 |
| `.github/workflows/` | 发布流程、PR 校验逻辑 | 中 |

### 2.2 当前仓库与运行产物的路径差异

当前源码存在一处需要特别注意的路径差异：

- 前端源码目录实际位于 `web/default` 与 `web/classic`
- `main.go` 中的本地静态资源加载路径写的是 `./frontend/default` 与 `./frontend/classic`
- 因此，源码调试阶段不要依赖后端直接托管前端静态文件，应优先使用：
  - 默认前端：`cd web/default && bun run dev`
  - 经典前端：`cd web/classic && bun run dev`

如果你是做本地调试，请把前后端当成分离式开发；如果你是做正式打包，请以 `Dockerfile` / CI 中的构建流程为准。

## 3. 依赖安装步骤

### 3.1 基础依赖

| 组件 | 建议版本 | 最低要求 | 用途 |
| --- | --- | --- | --- |
| Go | `1.25.1+` | `1.22+` | 后端编译、测试 |
| Bun | `1.x` | `1.x` | 前端依赖安装与构建 |
| Docker Engine | `20.10+` | `19.03.6+` | 本地/生产容器部署 |
| Docker Compose | `2.x` | `2.x` | 多服务编排 |
| Git | 最新稳定版 | 任意 | 获取源码 |
| SQLite3 | 最新稳定版 | 3.x | 本地 SQLite 调试时使用 |

### 3.2 克隆源码

```bash
git clone https://github.com/QuantumNous/new-api.git
cd new-api
```

### 3.3 后端依赖安装

Go 依赖由 `go.mod` 管理，首次进入仓库后执行：

```bash
go mod download
```

### 3.4 默认前端依赖安装

```bash
cd web/default
bun install
cd ../..
```

### 3.5 经典前端依赖安装

```bash
cd web/classic
bun install
cd ../..
```

### 3.6 Electron 依赖安装

仅在需要桌面端封装时执行：

```bash
cd electron
npm install
cd ..
```

## 4. 代码修改规范

### 4.1 分支管理规范

当前仓库 CI 已显式保留以下分支语义：

- `alpha`：触发 alpha Docker 镜像发布
- `nightly`：触发 nightly Docker 镜像发布
- Git Tag：触发正式 Release 工作流

建议采用下列分支策略，避免与现有发布分支冲突：

| 分支类型 | 命名规范 | 基线 |
| --- | --- | --- |
| 功能开发 | `feat/<topic>` | 从远端默认分支切出 |
| 缺陷修复 | `fix/<topic>` | 从远端默认分支切出 |
| 文档整理 | `docs/<topic>` | 从远端默认分支切出 |
| 重构/杂项 | `chore/<topic>` | 从远端默认分支切出 |
| 预发布联调 | `release/<topic>` | 仅在团队约定后使用 |

禁止事项：

- 不要直接在 `alpha`、`nightly` 上做日常开发
- 不要将功能开发分支直接命名为 `release`、`alpha`、`nightly`
- 不要在未验证本地构建前直接打 Tag

### 4.2 提交信息规范

当前仓库没有根级别的 `husky` / `commitlint` / `pre-commit` 强制钩子，但 `web/default/cz.yaml` 已声明 Conventional Commits 风格配置，因此建议整个仓库统一使用：

```text
feat: 新增 xxx 能力
fix: 修复 xxx 问题
docs: 更新 how-to-use 文档
refactor: 重构 xxx 模块
chore: 调整构建脚本
test: 补充 xxx 测试
```

推荐要求：

- 每个提交只解决一类问题
- 提交信息要能独立说明意图
- 不要提交未整理的 AI 生成描述
- 涉及配置变更时，在提交说明中写明迁移影响

### 4.3 提交前校验

当前仓库的 PR CI 主要校验 PR 模板与人工说明质量，不会自动替你跑完整编译与测试。因此本地校验必须自己执行。

#### 后端最小校验

```bash
go test ./...
go build ./...
```

#### 默认前端最小校验

```bash
cd web/default
bun run typecheck
bun run lint
bun run build:check
bun run format:check
bun run copyright:check
bun run knip
cd ../..
```

#### 经典前端最小校验

```bash
cd web/classic
bun run lint
bun run eslint
bun run build
cd ../..
```

#### 涉及 i18n 时额外校验

默认前端：

```bash
cd web/default
bun run i18n:sync
cd ../..
```

经典前端：

```bash
cd web/classic
bun run i18n:extract
bun run i18n:status
bun run i18n:lint
cd ../..
```

### 4.4 PR 提交要求

提交 PR 时应满足 `.github/PULL_REQUEST_TEMPLATE.md` 的要求：

- 使用人工整理后的简洁摘要
- 说明改了什么、为什么这样改
- 勾选本地验证、安全合规、范围聚焦等检查项
- 附运行截图、关键日志或测试报告

## 5. 本地调试配置要求

### 5.1 调试模式基线

推荐本地使用如下基础配置：

```ini
GIN_MODE=debug
DEBUG=true
PORT=3000
SESSION_SECRET=<至少 32 位随机字符串>
CRYPTO_SECRET=<建议独立于 SESSION_SECRET 的随机字符串>
ERROR_LOG_ENABLED=true
```

要求说明：

- `SESSION_SECRET` 不能使用 `random_string`
- `CRYPTO_SECRET` 未显式设置时会回退到 `SESSION_SECRET`
- 本地前后端联调时，后端默认监听 `3000`

### 5.2 数据库与缓存调试要求

本地开发推荐优先使用 `docker-compose.dev.yml` 拉起 PostgreSQL + Redis：

```bash
docker compose -f docker-compose.dev.yml up -d
```

对应的本地直连配置通常为：

```ini
SQL_DSN=postgresql://root:123456@localhost:5432/new-api
REDIS_CONN_STRING=redis://localhost:6379
```

如果你不想额外安装 PostgreSQL，可直接使用 SQLite：

```ini
SQLITE_PATH=one-api.db
```

此时只要 `SQL_DSN` 留空，程序就会自动退回 SQLite。

### 5.3 前端本地代理要求

默认前端与经典前端开发服务器都默认反向代理到 `http://localhost:3000`：

- 默认前端：`web/default/rsbuild.config.ts`
- 经典前端：`web/classic/vite.config.js`

如果你的后端端口不是 `3000`，需要同步调整：

- 默认前端：设置 `VITE_REACT_APP_SERVER_URL`
- 经典前端：修改 `vite.config.js` 中的 `proxy.target`

### 5.4 建议的本地 `.env`

```ini
PORT=3000
GIN_MODE=debug
DEBUG=true
SESSION_SECRET=replace-with-random-string
CRYPTO_SECRET=replace-with-random-string
SQL_DSN=postgresql://root:123456@localhost:5432/new-api
REDIS_CONN_STRING=redis://localhost:6379
ERROR_LOG_ENABLED=true
BATCH_UPDATE_ENABLED=true
SYNC_FREQUENCY=60
```

### 5.5 可选调试能力

```ini
ENABLE_PPROF=true
PYROSCOPE_URL=http://localhost:4040
PYROSCOPE_APP_NAME=new-api
PYROSCOPE_MUTEX_RATE=5
PYROSCOPE_BLOCK_RATE=5
HOSTNAME=dev-node-1
```

## 6. 开发环境启动流程

### 6.1 推荐方式：后端依赖容器 + 本地前端

#### 步骤 1：启动后端依赖

```bash
docker compose -f docker-compose.dev.yml up -d
```

该编排会启动：

- `new-api-dev`：后端开发容器
- `new-api-dev-pg`：PostgreSQL 15
- `new-api-dev-redis`：Redis 7

#### 步骤 2：启动默认前端

```bash
cd web/default
bun install
bun run dev
```

默认访问地址：`http://localhost:3001`

#### 步骤 3：检查接口状态

```bash
curl http://localhost:3000/api/status
```

返回中应包含：

- `version`
- `start_time`
- `theme`
- `setup`

### 6.2 使用 Makefile 一键启动

```bash
make dev
```

可用的常用命令：

| 命令 | 用途 | 说明 |
| --- | --- | --- |
| `make dev` | 启动后端依赖容器 + 默认前端开发服务 | 最常用 |
| `make dev-api` | 仅启动开发后端容器栈 | 适合联调 API |
| `make dev-api-rebuild` | 重建并启动后端开发容器 | Go 代码改动后使用 |
| `make dev-web` | 启动默认前端开发服务 | 端口通常为 `3001` |
| `make dev-web-classic` | 启动经典前端开发服务 | Vite 模式 |
| `make reset-setup` | 重置初始化向导状态 | 清理 `setups` 和 root 用户记录 |

### 6.3 本地直跑后端

如果不使用开发容器，也可以直接在源码目录运行：

```bash
go run main.go
```

适用前提：

- 你已经自行准备好数据库与 Redis
- `.env` 已配置完成
- 若开启前端托管，不要依赖 `./frontend/*` 路径，建议配合本地前端 dev server 使用

## 7. 测试环境与生产环境构建流程

### 7.1 测试环境构建流程

适用于开发、预发、自测环境。

#### 方案 A：开发容器构建

```bash
docker compose -f docker-compose.dev.yml up -d --build new-api
```

适用场景：

- 需要快速验证 Go 代码改动
- 需要与 PostgreSQL、Redis 组合联调

#### 方案 B：源码手工构建

```bash
cd web/default
bun install
DISABLE_ESLINT_PLUGIN=true VITE_REACT_APP_VERSION=$(cat ../../VERSION) bun run build
cd ../classic
bun install
VITE_REACT_APP_VERSION=$(cat ../../VERSION) bun run build
cd ../..
go mod download
go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api .
```

产物说明：

- 默认前端产物：`web/default/dist/`
- 经典前端产物：`web/classic/dist/`
- 后端二进制：`./new-api`

### 7.2 生产环境构建流程

#### 步骤 1：准备生产配置

复制并修改 `docker-compose.yml` 中的以下默认值：

- PostgreSQL 密码
- Redis 密码
- `SESSION_SECRET`
- `SQL_DSN`
- `REDIS_CONN_STRING`
- 时区 `TZ`
- 节点标识 `NODE_NAME`

#### 步骤 2：构建生产镜像

```bash
docker build --platform linux/amd64 -t new-api:local .
```

多架构镜像：

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t new-api:local --push .
```

#### 步骤 3：通过 Compose 启动生产栈

```bash
docker compose up -d
```

#### 步骤 4：生产校验

```bash
docker compose ps
docker compose logs -f new-api
curl http://localhost:3000/api/status
```

### 7.3 正式 Release 流程

当前仓库正式发布由 Git Tag 触发 `.github/workflows/release.yml`：

- Linux：生成 `new-api-<version>` 与 `checksums-linux.txt`
- macOS：生成 `new-api-macos-<version>` 与 `checksums-macos.txt`
- Windows：生成 `new-api-<version>.exe` 与 `checksums-windows.txt`

注意事项：

- 只有 Tag 触发正式 Release
- `alpha` 与 `nightly` 只走镜像发布，不等价于正式版本

## 8. 核心功能配置说明

本项目的配置来源分为两层：

1. 环境变量：启动前加载，影响数据库、缓存、日志、监控、运行模式
2. 数据库 `options` / 结构化 setting：启动后载入，可通过后台管理或配置同步修改

### 8.1 核心环境变量总表

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `PORT` | 服务监听端口 | `1-65535` | `3000` |
| `GIN_MODE` | Gin 运行模式 | `debug` / `release` / 其他 Gin 合法值 | 非 `debug` 时按 `release` 处理 |
| `DEBUG` | 调试日志开关 | `true` / `false` | `false` |
| `USE_FRONTEND` | 是否启用前端静态资源托管 | `true` / `false` | `true` |
| `SESSION_SECRET` | Session 签名密钥 | 非空随机字符串，建议至少 32 位 | 程序内默认值存在，但生产必须显式覆盖 |
| `CRYPTO_SECRET` | 加密密钥 | 非空随机字符串 | 未设置时回退为 `SESSION_SECRET` |
| `SQL_DSN` | 主数据库连接串 | PostgreSQL URL / MySQL DSN / 以 `local` 开头时退回 SQLite | 留空则使用 SQLite |
| `LOG_SQL_DSN` | 日志数据库连接串 | 与 `SQL_DSN` 同格式 | 留空则复用主库 |
| `SQLITE_PATH` | SQLite 文件路径 | 合法文件路径 | 程序内默认路径 |
| `SQL_MAX_IDLE_CONNS` | 数据库最大空闲连接数 | 正整数 | `100` |
| `SQL_MAX_OPEN_CONNS` | 数据库最大打开连接数 | 正整数 | `1000` |
| `SQL_MAX_LIFETIME` | 数据库连接最长生命周期，单位秒 | 正整数 | `60` |
| `REDIS_CONN_STRING` | Redis 连接串 | `redis://` URL | 留空时禁用 Redis |
| `REDIS_POOL_SIZE` | Redis 连接池大小 | 正整数 | `10` |
| `MEMORY_CACHE_ENABLED` | 是否启用内存缓存 | `true` / `false` | `false` |
| `SYNC_FREQUENCY` | Option/缓存同步周期，单位秒 | 正整数 | `60` |
| `BATCH_UPDATE_ENABLED` | 是否启用批量更新 | `true` / `false` | `false` |
| `BATCH_UPDATE_INTERVAL` | 批量更新间隔，单位秒 | 正整数 | `5` |
| `CHANNEL_UPDATE_FREQUENCY` | 自动更新渠道频率 | 正整数，单位秒 | 未设置时不启动该任务 |
| `RELAY_TIMEOUT` | 全局请求超时，单位秒 | `0` 或正整数 | `0` |
| `STREAMING_TIMEOUT` | 流模式无响应超时，单位秒 | 正整数 | `300` |
| `MAX_FILE_DOWNLOAD_MB` | 文件下载大小上限 | 正整数，单位 MB | `64` |
| `STREAM_SCANNER_MAX_BUFFER_MB` | 流式扫描缓冲上限 | 正整数，单位 MB | `128` |
| `MAX_REQUEST_BODY_MB` | 请求体最大解压后大小 | 正整数，单位 MB | `128` |
| `FORCE_STREAM_OPTION` | 是否强制补全 `usage` 信息 | `true` / `false` | `true` |
| `UPDATE_TASK` | 是否启用任务更新轮询 | `true` / `false` | `true` |
| `ERROR_LOG_ENABLED` | 是否记录错误日志 | `true` / `false` | `false` |
| `NODE_TYPE` | 节点角色 | `master` / `slave` | 非 `slave` 均视为主节点 |
| `NODE_NAME` | 节点标识 | 非空字符串 | 空 |
| `FRONTEND_BASE_URL` | 非主节点前端重定向地址 | 合法 URL | 空 |
| `TRUSTED_REDIRECT_DOMAINS` | 支付跳转白名单域名 | 逗号分隔域名列表 | 空 |
| `ENABLE_PPROF` | 是否启用 pprof | `true` / `false` | `false` |
| `PYROSCOPE_URL` | Pyroscope 服务地址 | 合法 URL | 空 |
| `PYROSCOPE_APP_NAME` | Pyroscope 应用名 | 非空字符串 | `new-api` |
| `PYROSCOPE_MUTEX_RATE` | Mutex 采样率 | 非负整数 | `5` |
| `PYROSCOPE_BLOCK_RATE` | Block 采样率 | 非负整数 | `5` |
| `HOSTNAME` | 监控节点名 | 非空字符串 | `new-api` |
| `UMAMI_WEBSITE_ID` | Umami 网站 ID | UUID / 站点 ID | 空 |
| `UMAMI_SCRIPT_URL` | Umami 脚本地址 | 合法 URL | `https://analytics.umami.is/script.js` |
| `GOOGLE_ANALYTICS_ID` | Google Analytics 测量 ID | `G-` 开头字符串 | 空 |

### 8.2 数据库兼容要求

本项目强制兼容三种数据库：

- SQLite
- MySQL `>= 5.7.8`
- PostgreSQL `>= 9.6`

使用要求：

- 业务代码优先使用 GORM，不要优先写数据库方言 SQL
- 原始 SQL 涉及保留关键字 `group` / `key` 时，需复用 `model/main.go` 中的兼容列名
- 布尔值、聚合函数、DDL 语句必须考虑三库兼容

### 8.3 认证与第三方登录配置

下表中的配置大多会落库到 `options` 表，通常通过后台管理界面维护；未配置时均视为关闭或空值。

#### GitHub / LinuxDO / Telegram / WeChat / Turnstile

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `GitHubOAuthEnabled` | 是否启用 GitHub 登录 | `true` / `false` | `false` |
| `GitHubClientId` | GitHub OAuth Client ID | 非空字符串 | 空 |
| `GitHubClientSecret` | GitHub OAuth Secret | 非空字符串 | 空 |
| `LinuxDOOAuthEnabled` | 是否启用 LinuxDO 登录 | `true` / `false` | `false` |
| `LINUX_DO_TOKEN_ENDPOINT` | LinuxDO Token Endpoint | 合法 URL | `https://connect.linux.do/oauth2/token` |
| `LINUX_DO_USER_ENDPOINT` | LinuxDO 用户信息 Endpoint | 合法 URL | `https://connect.linux.do/api/user` |
| `TelegramOAuthEnabled` | 是否启用 Telegram 登录 | `true` / `false` | `false` |
| `TelegramBotToken` | Telegram 机器人 Token | 非空字符串 | 空 |
| `TelegramBotName` | Telegram 机器人名称 | 非空字符串 | 空 |
| `WeChatAuthEnabled` | 是否启用微信登录 | `true` / `false` | `false` |
| `WeChatServerAddress` | 微信服务端地址 | 合法 URL | 空 |
| `WeChatServerToken` | 微信 Token | 非空字符串 | 空 |
| `WeChatAccountQRCodeImageURL` | 微信二维码图地址 | 合法 URL | 空 |
| `TurnstileCheckEnabled` | 是否启用 Turnstile 验证 | `true` / `false` | `false` |
| `TurnstileSiteKey` | Turnstile Site Key | 非空字符串 | 空 |
| `TurnstileSecretKey` | Turnstile Secret Key | 非空字符串 | 空 |

#### OIDC

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `oidc.enabled` | 是否启用 OIDC | `true` / `false` | `false` |
| `oidc.client_id` | OIDC Client ID | 非空字符串 | 空 |
| `oidc.client_secret` | OIDC Client Secret | 非空字符串 | 空 |
| `oidc.well_known` | OIDC Well Known 地址 | 合法 URL | 空 |
| `oidc.authorization_endpoint` | 授权地址 | 合法 URL | 空 |
| `oidc.token_endpoint` | Token 地址 | 合法 URL | 空 |
| `oidc.user_info_endpoint` | 用户信息地址 | 合法 URL | 空 |

#### Passkey / WebAuthn

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `passkey.enabled` | 是否启用 Passkey | `true` / `false` | `false` |
| `passkey.rp_display_name` | RP 展示名称 | 非空字符串 | `common.SystemName` |
| `passkey.rp_id` | RP ID | 域名或主机名 | 空，若空则尝试从 `ServerAddress` 推导 |
| `passkey.origins` | 允许来源 | URL 或 URL 列表字符串 | 空，若空则回退 `ServerAddress` |
| `passkey.allow_insecure_origin` | 是否允许非 HTTPS | `true` / `false` | `false` |
| `passkey.user_verification` | 用户验证策略 | `required` / `preferred` / `discouraged` | `preferred` |
| `passkey.attachment_preference` | 认证器类型偏好 | `platform` / `cross-platform` / 空 | 空 |

### 8.4 支付与充值配置

#### Stripe

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `StripeApiSecret` | Stripe 服务端密钥 | 非空字符串 | 空 |
| `StripeWebhookSecret` | Stripe Webhook 密钥 | 非空字符串 | 空 |
| `StripePriceId` | Stripe 价格 ID | 非空字符串 | 空 |
| `StripeUnitPrice` | 前端展示单价 | 正数 | `8.0` |
| `StripeMinTopUp` | 最小充值金额 | 正整数 | `1` |
| `StripePromotionCodesEnabled` | 是否允许优惠码 | `true` / `false` | `false` |

#### Creem

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `CreemApiKey` | Creem API Key | 非空字符串 | 空 |
| `CreemProducts` | 商品清单 JSON | JSON 数组字符串 | `[]` |
| `CreemTestMode` | 是否启用测试模式 | `true` / `false` | `false` |
| `CreemWebhookSecret` | Webhook 签名密钥 | 非空字符串 | 空 |

#### Waffo

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `WaffoEnabled` | 是否启用 Waffo | `true` / `false` | `false` |
| `WaffoApiKey` | API Key | 非空字符串 | 空 |
| `WaffoPrivateKey` | 商户私钥 | 非空字符串 | 空 |
| `WaffoPublicCert` | 平台公钥证书 | PEM/证书文本 | 空 |
| `WaffoSandboxPublicCert` | 沙箱证书 | PEM/证书文本 | 空 |
| `WaffoSandboxApiKey` | 沙箱 API Key | 非空字符串 | 空 |
| `WaffoSandboxPrivateKey` | 沙箱私钥 | 非空字符串 | 空 |
| `WaffoSandbox` | 是否启用沙箱 | `true` / `false` | `false` |
| `WaffoMerchantId` | 商户号 | 非空字符串 | 空 |
| `WaffoNotifyUrl` | 异步回调地址 | 合法 URL | 空 |
| `WaffoReturnUrl` | 同步回跳地址 | 合法 URL | 空 |
| `WaffoSubscriptionReturnUrl` | 订阅回跳地址 | 合法 URL | 空 |
| `WaffoCurrency` | 币种代码 | 合法货币代码，如 `USD` / `CNY` | 空 |
| `WaffoUnitPrice` | 单价 | 正数 | `1.0` |
| `WaffoMinTopUp` | 最小充值金额 | 正整数 | `1` |
| `WaffoPayMethods` | 支付方式配置 | JSON 数组 | 默认使用内置方法列表 |

### 8.5 通用系统配置

#### 主题、文档、展示

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `theme.frontend` | 默认前端主题 | `classic` / 其他主题标识 | `classic` |
| `general_setting.docs_link` | 文档地址 | 合法 URL | `https://docs.newapi.pro` |
| `general_setting.ping_interval_enabled` | 是否向前端暴露心跳间隔 | `true` / `false` | `false` |
| `general_setting.ping_interval_seconds` | 心跳间隔秒数 | 正整数 | `60` |
| `general_setting.quota_display_type` | 额度展示类型 | `USD` / `CNY` / `TOKENS` / `CUSTOM` | `USD` |
| `general_setting.custom_currency_symbol` | 自定义货币符号 | 非空字符串 | `¤` |
| `general_setting.custom_currency_exchange_rate` | 自定义汇率 | 正数 | `1.0` |

#### 渠道自动测活

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `monitor_setting.auto_test_channel_enabled` | 是否自动测活渠道 | `true` / `false` | `false` |
| `monitor_setting.auto_test_channel_minutes` | 测活周期，单位分钟 | 正数 | `10` |
| `CHANNEL_TEST_FREQUENCY` | 通过环境变量强制打开自动测活 | 正整数 | 未设置 |

#### 性能与磁盘缓存

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `performance_setting.disk_cache_enabled` | 是否启用磁盘缓存 | `true` / `false` | `false` |
| `performance_setting.disk_cache_threshold_mb` | 触发磁盘缓存阈值 | 正整数，MB | `10` |
| `performance_setting.disk_cache_max_size_mb` | 最大缓存总量 | 正整数，MB | `1024` |
| `performance_setting.disk_cache_path` | 缓存目录 | 合法路径 | 空，表示系统临时目录 |
| `performance_setting.monitor_enabled` | 是否启用性能监控 | `true` / `false` | `true` |
| `performance_setting.monitor_cpu_threshold` | CPU 阈值 | `1-100` | `90` |
| `performance_setting.monitor_memory_threshold` | 内存阈值 | `1-100` | `90` |
| `performance_setting.monitor_disk_threshold` | 磁盘阈值 | `1-100` | `95` |

### 8.6 Sentry 与可观测性

当前仓库后端已接入 `sentry-go`，但实现存在以下现状：

- `main.go` 中已调用 `sentry.Init(...)`
- Gin 已挂载 `sentry-go/gin` 中间件
- 后端现已支持 `SENTRY_MODE=official|self-hosted|disabled` 三模式切换
- `.env.example`、`docker-compose.yml` 与 `docker-compose.dev.yml` 已提供 Sentry 参数样例
- 两套前端当前都没有安装 Sentry SDK

因此：

- 后端崩溃采集与部署态切换已具备基础能力
- 正式接入和参数规范请以 `how-to-use-sentry.md` 为准

## 9. 项目使用说明

### 9.1 首次初始化

服务启动后，先检查初始化状态：

```bash
curl http://localhost:3000/api/setup
curl http://localhost:3000/api/status
```

说明：

- `/api/setup`：返回系统是否已初始化
- `/api/status`：返回版本、主题、登录开关、展示配置等公开状态

如果你要重新跑初始化向导：

```bash
make reset-setup
```

### 9.2 日常开发

#### 后端开发

修改范围通常在：

- `router/`
- `controller/`
- `service/`
- `model/`
- `relay/`
- `setting/`

修改后执行：

```bash
go test ./...
go build ./...
```

#### 默认前端开发

```bash
cd web/default
bun run dev
```

适合：

- 新控制台页面
- 后台管理体验优化
- 新国际化接入

#### 经典前端开发

```bash
cd web/classic
bun run dev
```

适合：

- 存量页面维护
- 旧主题兼容修复

### 9.3 生产部署

最常见方式是使用 `docker-compose.yml`：

```bash
docker compose up -d
docker compose ps
docker compose logs -f new-api
```

推荐同时检查：

```bash
curl http://localhost:3000/api/status
```

## 10. 校验与验收清单

### 10.1 安装验收

- `go mod download` 成功
- `bun install` 在 `web/default`、`web/classic` 均成功
- `docker compose -f docker-compose.dev.yml up -d` 成功

### 10.2 本地调试验收

- `http://localhost:3001` 可打开默认前端
- `http://localhost:3000/api/status` 返回 `200`
- 后端日志无数据库连接失败、Redis ping 失败

### 10.3 构建验收

- `go build ./...` 成功
- 默认前端 `bun run build:check` 成功
- 经典前端 `bun run build` 成功
- 生产镜像 `docker build ...` 成功

### 10.4 发布验收

- Release Tag 能触发对应 GitHub Actions
- `alpha` / `nightly` 分支只用于镜像发布，不混入日常特性开发
- PR 描述符合模板，并附本地验证证据

## 11. 常见问题

### 11.1 为什么前端源码目录是 `web/*`，但后端里看到 `./frontend/*`？

这是当前仓库源码路径与运行产物路径之间的差异。调试阶段请使用前端 dev server，不要依赖后端直接托管源码目录。

### 11.2 为什么我只改了前端，还要做本地校验？

因为当前 PR CI 主要校验 PR 说明质量，不会自动替代前端编译、类型检查和格式校验。

### 11.3 为什么生产环境必须显式设置 `SESSION_SECRET`？

因为默认占位值 `random_string` 会在启动时直接触发 fatal，无法满足生产要求。

### 11.4 如何确认服务真的启动成功？

同时满足以下条件即可视为成功：

- 进程或容器健康
- `curl http://localhost:3000/api/status` 返回 `200`
- 日志中没有数据库、Redis、迁移失败信息
