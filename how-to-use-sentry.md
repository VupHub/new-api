# How to Use Sentry - new-api

> 目标：给 `new-api` 提供一份独立、可执行、可审计的 Sentry 接入说明。
>
> 本文同时覆盖两种场景：
> 1. 官方 Sentry SaaS 接入：满足“项目必须接入官方地址 `https://sentry.io/welcome/` 才能正常运行”的要求
> 2. 私有化 Sentry 自建：满足企业内网、数据留存或预发环境的自托管需要

## 1. 当前仓库现状

在开始接入前，必须先明确当前代码状态：

- 后端已引入 `github.com/getsentry/sentry-go`
- 后端已引入 `github.com/getsentry/sentry-go/gin`
- `main.go` 已在启动阶段初始化 Sentry，并在 Gin 中挂载中间件
- 后端现已支持通过 `SENTRY_MODE` 和 `SENTRY_DSN` 走环境变量配置
- `.env.example`、`docker-compose.yml`、`docker-compose.dev.yml` 已补充 Sentry 三模式样例
- `web/default` 与 `web/classic` 目前都没有前端 Sentry SDK 依赖

这意味着：

- 当前仓库已具备“后端三模式可切换”的基础异常采集能力
- 前端仍未接入 Sentry SDK
- 要满足完整可观测性要求，仍建议补充前端接入、标签治理和告警规则

## 2. 接入策略

### 2.1 官方地址要求与私有化部署的边界

由于项目明确要求必须接入官方地址 `https://sentry.io/welcome/` 对应的 Sentry 体系，建议采用如下策略：

| 场景 | 推荐方案 | 说明 |
| --- | --- | --- |
| 生产环境 | 官方 Sentry SaaS | 这是满足“必须接入官方地址”要求的主方案 |
| 测试 / 预发 / 内网验证 | 自建 Sentry Self-Hosted | 用于隔离验证、数据留存或离线调试 |
| 强监管或专网场景 | 混合模式 | 预发走私有化，生产仍接官方 SaaS |

如果你的组织要求“所有环境都必须完全内网化”，那么需要先和项目 owner 明确：这将与“官方地址强制接入”存在天然冲突。此时只能采用以下二选一：

- 修改项目接入要求，允许生产使用自建 Sentry
- 保持生产使用官方 Sentry，自建实例仅用于预发和数据回放

## 3. 私有化部署流程

以下流程基于 Sentry 官方 Self-Hosted 文档：

- 官方文档：[Self-Hosted Sentry](https://develop.sentry.dev/self-hosted/)
- 官方仓库：[getsentry/self-hosted](https://github.com/getsentry/self-hosted/releases/latest)

### 3.1 基础设施要求

根据官方 Self-Hosted 要求，建议至少准备如下资源：

| 项目 | 最低要求 | 建议值 | 说明 |
| --- | --- | --- | --- |
| OS | Debian / Ubuntu | Ubuntu 22.04+ / Debian 12 | 官方更偏好 Debian/Ubuntu 系 |
| Docker Engine | `19.03.6+` | 最新稳定版 | 官方最低要求 |
| Docker Compose | `2.32.2+` | 最新稳定版 | 官方最低要求 |
| CPU | `4 Core` | `8 Core` | ClickHouse / Kafka / Snuba 较重 |
| RAM | `16 GB + 16 GB swap` | `32 GB` | 官方建议 32 GB |
| 磁盘 | `20 GB` | `100 GB+ SSD` | 事件数据增长很快 |
| 网络 | 可访问 Docker Hub / GitHub | 生产建议固定出口 | 便于拉镜像和升级 |

附加建议：

- 专网或代理环境需预先配置 `http_proxy` / `https_proxy` / `no_proxy`
- 强隐私环境建议关闭 `SENTRY_BEACON`
- Air-gapped 场景建议单独准备镜像离线导入流程

### 3.2 宿主机准备

以 Ubuntu 为例：

```bash
sudo apt update
sudo apt install -y curl git ca-certificates
curl -fsSL https://get.docker.com | sh
docker version
docker compose version
```

建议额外准备：

- 专用数据盘挂载到 `/data/sentry`
- 系统 swap 至少 `16 GB`
- NTP 时间同步

### 3.3 拉取官方 Self-Hosted 仓库

```bash
VERSION=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/getsentry/self-hosted/releases/latest)
VERSION=${VERSION##*/}
git clone https://github.com/getsentry/self-hosted.git
cd self-hosted
git checkout ${VERSION}
```

### 3.4 执行安装脚本

```bash
./install.sh
```

说明：

- 该脚本会自动生成基础配置
- 会初始化 PostgreSQL、Kafka、ClickHouse、Redis、Snuba 等组件
- 安装阶段会询问是否允许上报 self-hosted 诊断数据

如果你在自动化环境执行，建议显式声明是否上报：

- 允许：`REPORT_SELF_HOSTED_ISSUES=true`
- 禁止：`REPORT_SELF_HOSTED_ISSUES=false`

### 3.5 启动服务

```bash
docker compose up --wait
```

官方默认绑定端口：

- Web UI：`9000`

浏览器访问：

```text
http://127.0.0.1:9000
```

### 3.6 私有化部署后的基础加固

生产环境至少补齐以下项：

| 项目 | 要求 |
| --- | --- |
| HTTPS | 必须通过 Nginx / Traefik / Caddy 反向代理并启用 TLS |
| 域名 | 建议独立域名，如 `sentry.example.com` |
| 备份 | 定期备份 PostgreSQL、ClickHouse、配置目录、上传文件 |
| 网络策略 | 只开放 `80/443` 给业务侧；管理端限制办公网 |
| 升级策略 | 通过 `git pull + docker compose pull + ./install.sh + docker compose up -d` 滚动升级 |
| 数据保留 | 根据磁盘容量调整 `SENTRY_RETENTION_DAYS` |

### 3.7 自建 Sentry 校验方法

至少完成以下校验：

#### 服务级校验

```bash
docker compose ps
docker compose logs --tail=200 web
docker compose logs --tail=200 worker
```

通过标准：

- 主要容器都为 `Up`
- Web 页面可登录
- 初始管理员能创建 Organization / Project

#### 功能级校验

1. 创建一个 `Go` 项目
2. 创建一个 `JavaScript` 项目
3. 复制 DSN
4. 用下面的最小脚本发送一个测试异常

Go 测试：

```go
package main

import (
  "log"
  "time"
  "github.com/getsentry/sentry-go"
)

func main() {
  err := sentry.Init(sentry.ClientOptions{
    Dsn: "https://<your-dsn>",
  })
  if err != nil {
    log.Fatal(err)
  }
  sentry.CaptureMessage("self-hosted sentry connectivity test")
  sentry.Flush(2 * time.Second)
}
```

通过标准：

- 事件能在对应项目中看到
- Issue 能看到时间、环境、Release、标签

## 4. 官方 Sentry SaaS 接入流程

### 4.1 创建组织与项目

访问官方入口：

- [Sentry Welcome](https://sentry.io/welcome/)

操作步骤：

1. 注册或登录 Sentry 账号
2. 创建 Organization
3. 创建项目：
   - 后端项目：平台选择 `Go`
   - 默认前端项目：平台选择 `React`
   - 经典前端项目：平台选择 `React`
4. 记录每个项目的 DSN、Project ID、Environment 命名规范、成员列表

### 4.2 环境规划

建议至少使用以下环境枚举：

| 环境 | 建议值 | 用途 |
| --- | --- | --- |
| 本地开发 | `development` | 个人调试 |
| 测试 / 预发 | `staging` | 联调与回归 |
| 生产 | `production` | 正式运行 |

### 4.3 项目命名建议

| 业务面 | 建议 Sentry Project 名 |
| --- | --- |
| 后端 API / Relay | `new-api-backend` |
| 默认前端 | `new-api-web-default` |
| 经典前端 | `new-api-web-classic` |

## 5. 项目端 Sentry SDK 接入步骤

### 5.1 后端接入要求

后端接入必须满足以下基线：

- 启动前初始化 Sentry
- `sentrygin` 中间件必须位于 Recovery 之前
- DSN、环境、Release、采样率必须从环境变量读取
- 退出前调用 `sentry.Flush`

### 5.2 后端必须改造的配置项

当前仓库后端现已支持并建议统一使用以下环境变量：

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `SENTRY_ENABLED` | 是否启用 Sentry | `true` / `false` | `true` |
| `SENTRY_DSN` | Sentry DSN | 官方 SaaS 或自建实例的 DSN | 空 |
| `SENTRY_ENVIRONMENT` | 运行环境 | `development` / `staging` / `production` | `production` |
| `SENTRY_RELEASE` | 发布版本 | `new-api@<version>` | 建议自动拼接 `common.Version` |
| `SENTRY_TRACES_SAMPLE_RATE` | 性能采样率 | `0.0-1.0` | `0.1` |
| `SENTRY_DEBUG` | SDK 调试日志 | `true` / `false` | `false` |
| `SENTRY_SEND_DEFAULT_PII` | 是否上报默认 PII | `true` / `false` | `false` |

兼容说明：

- 如果未显式设置 `SENTRY_MODE`，但设置了 `SENTRY_DSN`，后端会自动推断：
  - `sentry.io` DSN 视为 `official`
  - 其他 DSN 视为 `self-hosted`

推荐初始化形式如下：

```go
dsn := os.Getenv("SENTRY_DSN")
enabled := os.Getenv("SENTRY_ENABLED") != "false"
if enabled && dsn != "" {
  err := sentry.Init(sentry.ClientOptions{
    Dsn:              dsn,
    Release:          "new-api@" + common.Version,
    Environment:      common.GetEnvOrDefaultString("SENTRY_ENVIRONMENT", "production"),
    EnableTracing:    true,
    TracesSampleRate: 0.1,
    SendDefaultPII:   false,
    Debug:            common.GetEnvOrDefaultBool("SENTRY_DEBUG", false),
  })
  if err == nil {
    defer sentry.Flush(2 * time.Second)
  }
}
```

### 5.3 推荐的后端 Tag / Context

为了让告警能直接落到业务流程，建议至少写入以下标签：

| 标签 | 来源 | 说明 |
| --- | --- | --- |
| `node_name` | `NODE_NAME` | 多节点排障 |
| `node_type` | `NODE_TYPE` | 区分主从节点 |
| `request_id` | 请求中间件 | 串联日志与错误 |
| `user_id_hash` | 用户 ID 哈希值 | 不直接发送明文用户标识 |
| `channel_id` | 渠道 ID | 快速定位上游配置 |
| `provider` | 上游提供方 | 如 `openai` / `claude` / `gemini` |
| `model` | 请求模型名 | 快速聚合错误 |
| `payment_provider` | 支付回调链路 | Stripe / Creem / Waffo |
| `task_platform` | 异步任务平台 | 视频 / 图像 / 音乐任务 |

### 5.4 默认前端接入步骤

当前 `web/default` 尚未接入 Sentry，建议按以下步骤补齐：

#### 步骤 1：安装依赖

```bash
cd web/default
bun add @sentry/react
```

#### 步骤 2：在入口文件初始化

建议在 `src/main.tsx` 中注入：

```tsx
import * as Sentry from '@sentry/react'

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.VITE_SENTRY_ENVIRONMENT || 'production',
  release: import.meta.env.VITE_REACT_APP_VERSION,
  tracesSampleRate: 0.1,
})
```

#### 步骤 3：增加前端环境变量

| 参数 | 含义 | 取值范围 | 默认值 |
| --- | --- | --- | --- |
| `VITE_SENTRY_DSN` | 默认前端 DSN | 合法 DSN | 空 |
| `VITE_SENTRY_ENVIRONMENT` | 前端运行环境 | `development` / `staging` / `production` | `production` |

### 5.5 经典前端接入步骤

当前 `web/classic` 尚未接入 Sentry，建议按以下步骤补齐：

#### 步骤 1：安装依赖

```bash
cd web/classic
bun add @sentry/react
```

#### 步骤 2：在入口文件初始化

建议在 `src/index.jsx` 或主入口处添加：

```jsx
import * as Sentry from '@sentry/react'

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.VITE_SENTRY_ENVIRONMENT || 'production',
  tracesSampleRate: 0.1,
})
```

## 6. 错误上报规则配置

### 6.1 必须上报的错误

以下错误必须进入 Sentry：

| 错误类型 | 触发位置 | 上报要求 |
| --- | --- | --- |
| 启动初始化失败 | `InitResources()`、数据库初始化、Redis 初始化 | 作为 `fatal` / `error` |
| Gin panic | Recovery 前的中间件链 | 必须保留堆栈 |
| 上游 5xx / 解析失败 | Relay / provider adaptor | 记录 provider、model、channel |
| 支付回调验签失败 | Stripe / Creem / Waffo Webhook | 标记 `payment_provider` |
| OIDC / OAuth 回调异常 | 登录回调链路 | 标记 provider 与 redirect URI |
| 异步任务轮询失败 | 图像/视频/音乐任务 | 标记 task id、task platform |
| 数据库 / Redis 不可用 | 启动和运行期 | 标记 node name |
| 前端白屏 / 崩溃 | React render error | 标记 route、theme、browser |

### 6.2 不建议直接上报的错误

以下内容不应原样进入 Sentry，避免噪声或敏感信息外泄：

- 用户输错密码
- 普通表单校验失败
- 预期内的 `4xx` 请求错误
- 原始 Access Token
- 支付密钥、Webhook Secret、DSN
- 用户完整 Prompt / Completion 原文
- 邮箱、手机号、身份证等直接标识信息

建议做法：

- `4xx` 仅记录为 breadcrumb 或本地日志
- 用户标识仅传哈希值
- Prompt 只上传长度、模型、上游和摘要，不上传正文

### 6.3 采样率建议

| 环境 | `tracesSampleRate` | 说明 |
| --- | --- | --- |
| `development` | `1.0` | 本地全量排障 |
| `staging` | `0.3-0.5` | 联调阶段适度保留链路 |
| `production` | `0.05-0.1` | 避免高流量下成本失控 |

## 7. 告警规则配置

### 7.1 后端核心告警

建议至少配置以下告警：

| 规则 | 阈值建议 | 通知对象 |
| --- | --- | --- |
| `backend-panic` | `5 分钟 >= 1 次 panic` | On-call / 后端负责人 |
| `relay-5xx-rate` | `5 分钟 5xx 占比 > 3%` | On-call / 网关负责人 |
| `startup-failure` | 新版本启动失败立即告警 | 运维 / 发布负责人 |
| `db-redis-unavailable` | `10 分钟 >= 1 次` | 运维 |
| `payment-webhook-error` | 任意一次验签失败或处理失败 | 支付负责人 / 运维 |
| `task-timeout` | `15 分钟内超时任务数 > 阈值` | 任务业务负责人 |

### 7.2 前端核心告警

| 规则 | 阈值建议 | 通知对象 |
| --- | --- | --- |
| `frontend-crash` | `5 分钟 >= 1 次白屏级错误` | 前端负责人 |
| `login-flow-error` | 登录页/回调页异常激增 | 前端 + 认证负责人 |
| `setup-page-error` | 初始化向导异常 | 后端 + 前端 |

### 7.3 发布回归告警

必须开启以下维度：

- First seen after release
- Regressed issue after release
- 某 release 在 30 分钟内新增 issue 超过阈值

这样可以把 `VERSION`、Sentry Release 和实际部署关联起来。

## 8. 权限管理配置

建议在 Sentry 侧做最小权限分层。

### 8.1 组织角色建议

| 角色 | 适用人群 | 权限建议 |
| --- | --- | --- |
| Owner | 平台 owner / 安全负责人 | 仅限少数人 |
| Admin | 架构、运维负责人 | 可管理项目和告警 |
| Manager | 模块负责人 | 可看 issue、可处理规则 |
| Member | 开发者 | 可看 issue、可 comment、可 resolve |
| Read Only | 审计 / 客服 / 产品 | 仅查看 |

### 8.2 项目隔离建议

建议按项目分离：

- `new-api-backend`
- `new-api-web-default`
- `new-api-web-classic`

如果业务规模较大，可进一步按环境拆分：

- `new-api-backend-prod`
- `new-api-backend-staging`

### 8.3 凭据管理要求

- DSN 只放在环境变量，不写进代码仓库
- Auth Token 只放 CI Secret 或密码管理系统
- Webhook / 告警通知目标使用企业统一值班渠道

## 9. Sentry 与核心业务流程的联动要求

为了确保“接入后项目可正常运行”，Sentry 不能只是一个孤立的异常池，必须和核心业务链路联动。

### 9.1 启动与初始化链路

联动对象：

- `.env` 加载
- `InitResources()`
- `model.InitDB()`
- `model.InitLogDB()`
- `common.InitRedisClient()`
- `i18n.Init()`

要求：

- 初始化失败必须能在 Sentry 中看到
- 必须带 `node_name`、`release`、`environment`

### 9.2 用户与认证链路

联动对象：

- `/api/user/login`
- `/api/oauth/:provider`
- Passkey / OIDC / Telegram / WeChat 回调

要求：

- 第三方认证错误必须带 provider 标签
- 不能上传用户明文密码、完整 token

### 9.3 核心中继链路

联动对象：

- `/v1/*`
- Relay provider adaptor
- 上游请求转换、流式响应、计费结算

要求：

- 上游异常必须带 provider / model / channel
- 只记录必要上下文，不上传用户敏感正文

### 9.4 支付链路

联动对象：

- `/api/stripe/webhook`
- `/api/creem/webhook`
- `/api/waffo/webhook`
- `/api/waffo-pancake/webhook/:env`

要求：

- 验签失败必须立即告警
- 支付回调幂等处理失败要能定位到订单号和 provider

### 9.5 异步任务链路

联动对象：

- 图像、视频、音乐、MJ、Sora 等异步任务
- 轮询、退款、失败结算

要求：

- 必须带 task id、task platform、channel id
- 超时和重试异常应汇总告警，而不是单条噪声刷屏

## 10. 最小可执行配置样例

### 10.1 后端 `.env`

```ini
SENTRY_ENABLED=true
SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
SENTRY_ENVIRONMENT=production
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_DEBUG=false
SENTRY_SEND_DEFAULT_PII=false
```

### 10.2 Docker Compose 注入

```yaml
environment:
  - SENTRY_ENABLED=true
  - SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
  - SENTRY_ENVIRONMENT=production
  - SENTRY_TRACES_SAMPLE_RATE=0.1
  - SENTRY_DEBUG=false
  - SENTRY_SEND_DEFAULT_PII=false
```

### 10.3 前端 `.env`

默认前端 / 经典前端都可以采用：

```ini
VITE_SENTRY_DSN=https://<key>@oXXXXXX.ingest.sentry.io/<project-id>
VITE_SENTRY_ENVIRONMENT=production
```

## 11. 接入完成后的服务校验方法

### 11.1 启动校验

检查后端日志中是否出现 Sentry 初始化成功信息，或至少没有初始化失败信息。

### 11.2 事件校验

人为制造一个测试异常：

- 后端：调用 `sentry.CaptureMessage("backend sentry smoke test")`
- 前端：在浏览器控制台执行 `throw new Error('frontend sentry smoke test')`

通过标准：

- Sentry 控制台能看到事件
- 事件能看到 `environment`、`release`、`project`
- 事件具备请求上下文、标签和堆栈

### 11.3 业务链路校验

至少验证以下四类链路：

1. 登录
2. `/api/status`
3. 一次真实模型请求
4. 一次支付回调或模拟回调

### 11.4 告警校验

手工触发一条测试异常，确认：

- 通知能到达企业群、邮件或 PagerDuty
- 告警路由到正确值班组
- 同类错误可聚合，不产生告警风暴

## 12. 结论

要让 `new-api` 真正满足“必须接入官方 Sentry 才能正常运行”的要求，至少要同时完成以下事项：

1. 通过 `SENTRY_MODE=official|self-hosted|disabled` 明确运行模式
2. 在部署配置中显式注入 `SENTRY_DSN`、`SENTRY_ENVIRONMENT` 等参数
3. 建立官方 SaaS 或自建项目，并规范 `environment` / `release`
4. 为关键业务链路设置 Tag、告警和权限模型
5. 如有私有化诉求，将自建 Sentry 作为测试/预发或混合部署方案，而不是默认替代官方 SaaS
