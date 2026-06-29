# 前端独立编译指引（web/default + web/classic）

本文档提供两套前端的独立编译流程，均可在不构建后端的情况下完成生产构建。

## 前置环境

### 必备依赖

- Node.js
  - `web/default`：建议使用 [web/default/.node-version](file:///e:/new-api-1.0.0-rc.10/web/default/.node-version) 指定的版本（当前为 `24.10.0`）
  - `web/classic`：建议 `Node.js >= 18`（推荐 20+）
- 包管理器：`bun`
  - `web/default` 与 `web/classic` 均支持 `bun install` / `bun run ...`

### 校验命令

```bash
node -v
bun -v
```

## web/default（默认前端）

### 目录

- 代码目录：[web/default](file:///e:/new-api-1.0.0-rc.10/web/default)

### 初始化与依赖安装

```bash
cd web/default
bun install
```

### 生产环境编译

```bash
cd web/default
bun run build
```

### 产物

- `web/default/dist/`

## web/classic（经典前端）

### 目录

- 代码目录：[web/classic](file:///e:/new-api-1.0.0-rc.10/web/classic)

### 初始化与依赖安装

```bash
cd web/classic
bun install
```

### 生产环境编译

```bash
cd web/classic
bun run build
```

### 产物

- `web/classic/dist/`

## 可选：构建时指定后端地址（更适合 Pages）

`web/classic` 支持通过构建环境变量注入后端地址：

- `VITE_REACT_APP_SERVER_URL`

示例（以 `https://api.example.com` 为后端域名）：

```bash
cd web/classic
VITE_REACT_APP_SERVER_URL="https://api.example.com" bun run build
```

## 备案号配置

两套前端均已增加“备案号”配置项，直接修改配置文件即可更新。

- 默认前端配置项位置：[constants.ts](file:///e:/new-api-1.0.0-rc.10/web/default/src/lib/constants.ts)
  - `DEFAULT_ICP_FILING_NUMBER`
- 经典前端配置项位置：[common.constant.js](file:///e:/new-api-1.0.0-rc.10/web/classic/src/constants/common.constant.js)
  - `DEFAULT_ICP_FILING_NUMBER`

备案号将展示在页脚的 `© {year} {SystemName}. 版权所有` 右侧，并链接到工信部备案查询页面 `https://beian.miit.gov.cn/`。
