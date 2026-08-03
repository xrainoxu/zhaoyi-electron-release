# macOS 一键自动安装说明

本文档说明非技术客户如何使用 `scripts/install-mac.sh` 脚本，在 macOS 上自动完成端口检查、下载应用、解除 quarantine 并安装到 `/Applications`，最后启动 `temp-electron`。Node.js 运行环境由应用在首次启动时自动下载到 `~/Library/Application Support/temp-electron/runtime/`。

> 面向对象：非技术客户、远程协助场景
> 适用系统：macOS（Apple Silicon 与 Intel）
> 默认分发仓库：`xrainoxu/zhaoyi-electron-release`（public）
> 源码仓库：`xrainoxu/electron-zhaoyi`（private）
> 脚本路径：`scripts/install-mac.sh`

---

## 1. 客户需要知道的事（最少信息）

客户只需要知道下面三步：

1. 打开「终端」（`Terminal`）。
2. 粘贴并执行一段命令（见下文）。
3. 等待脚本完成 + 应用自动启动。

**首次启动应用时，应用会自动下载 Node.js（约 30 秒），无需客户任何操作。**

---

## 2. 客户执行的一行命令

```bash
curl -fL https://raw.githubusercontent.com/xrainoxu/zhaoyi-electron-release/main/install/install-mac.sh | bash
```

或者手动保存脚本：

```bash
curl -fL https://raw.githubusercontent.com/xrainoxu/zhaoyi-electron-release/main/install/install-mac.sh -o install-mac.sh
bash install-mac.sh
```

> 安装脚本每次运行时都会从分发仓库自动发现最新版本，无需锁定分支/commit/tag。

### 下载源

- **通道 1（默认）**：`https://raw.githubusercontent.com/xrainoxu/zhaoyi-electron-release/main/latest.json`（静态清单，由 `publish.sh` 推送时自动维护，含 sha256）。
- **通道 2（兜底）**：`https://api.github.com/repos/xrainoxu/zhaoyi-electron-release/releases/latest`（GitHub Release API，无 sha256）。
- **自定义**：`INSTALL_BASE_URL=https://your-cdn bash <(curl -fsSL ...)` 覆盖下载源（CDN/内网镜像）。
- **锁版本**：`INSTALL_VERSION=v1.0.33 bash <(curl -fsSL ...)` 强制指定版本。

---

## 3. 脚本会做哪些事

1. **系统与架构识别**：`uname -s` 检查 macOS；`uname -m` 识别 `arm64` 或 `x64`。
2. **命令依赖检查**：`curl unzip xattr open pgrep ditto`，任意一个缺失立即报错。
3. **下载与安装应用**：从 GitHub Release 下载对应架构 zip → `unzip` → `xattr -cr` → `ditto` 到 `/Applications` → 启动。
4. **清理**：`trap cleanup EXIT` 清理临时目录。

**端口检查已下沉到应用内**：OpenClaw Gateway 默认监听 18789，应用启动时若被占用会自动降级到 18790-18799 共 10 个备选端口。脚本端不预判。

**Node.js 由应用自举**（不再由脚本负责），详见 §5。

---

## 4. 客户能看到的关键输出

成功路径：

```
正在检查 OpenClaw 所需端口……
端口检查通过。
正在获取 GitHub Release……
安装完成，正在启动 temp-electron v1.0.xx……
安装成功：/Applications/temp-electron.app
Node.js 运行环境将在应用首次启动时自动准备（约 30 秒）。
```

应用启动后，UI 依次展示：

1. `NodeBootstrapPage`（下载/校验/安装 Node）
2. `LoadingPage`（启动 OpenClaw Gateway）
3. 主应用界面

---

## 5. Node.js 由应用自举

**首次启动**应用时，会自动完成以下流程，无需客户手动安装：

1. 应用检查 `~/Library/Application Support/temp-electron/runtime/` 下是否已有兼容 Node（≥22.19.0）。
2. 没有时，从 `https://npmmirror.com/mirrors/node/` 下载最新 Node 22 官方 tarball。
3. SHA256 校验。
4. 解压到 `~/Library/Application Support/temp-electron/runtime/node-v22.x.x-darwin-{arch}/`。
5. 写入 manifest 后启动 OpenClaw Gateway。

**完全旁路系统 Node**：不修改 `.zshrc`、PATH、`/opt/homebrew/`、nvm 等任何已有 Node。

再次启动时直接命中本地缓存，秒级进入主界面。

---

## 6. 客户需要具备的环境

| 项 | 要求 | 是否由脚本/应用自动处理 |
|---|---|---|
| macOS | 11.0+（与 Electron 42 兼容） | 否 |
| Apple Silicon / Intel | 任一均可 | 是（脚本自动识别） |
| 网络（首次） | 可访问 `api.github.com` 与 `npmmirror.com` | 否 |
| Node.js ≥ 22.19.0 | 无需预装 | 是（应用首次启动自动下载） |
| `/Applications` 可写 | 必须 | 否（脚本会检查） |
| OpenClaw Gateway 端口（默认 18789 + 10 备选） | 至少 1 个空闲 | 是（应用内 `findAvailablePort()` 自动选择） |
| 管理员权限 | 不需要 | — |
| 客户 Apple ID | 不需要（`xattr -cr` 跳过 Gatekeeper） | — |

---

## 7. 常见问题与排查

### 7.1 Gateway 端口被全部占用

如果 18789 + 10 个备选端口都被占用，应用启动时 `findAvailablePort()` 会让 spawn 失败，渲染端展示 LoadingPage 错误页。

让客户在「活动监视器」或终端中找到占用进程并退出后重启 App。

### 7.2 Node Bootstrap 失败（应用内）

应用启动后展示 `NodeBootstrapPage`，failed 状态下有重试按钮：

- 点击重试：再次发起下载
- 连续失败 3 次：重试按钮禁用，提示"请检查网络或联系技术支持"

**网络受限**：

- 公司网络可能拦截 `npmmirror.com`，需要 IT 放行或在终端设置代理：
  ```bash
  export https_proxy=http://your-proxy:port
  open /Applications/temp-electron.app
  ```

### 7.3 找不到对应架构的 Release 资产

```
安装中止：Release v1.0.xx 没有对应架构资产：temp-electron-darwin-x64-1.0.xx.zip
```

发布端需要确保 `release.sh` / `publish.sh` 同时上传了 `arm64` 和 `x64` 两个资产。

### 7.4 GitHub Release API 不可达

```
安装中止：无法访问 GitHub Release
```

公司网络拦截 `api.github.com`，或在终端设置代理。

### 7.5 旧版 App 正在运行

```
安装中止：temp-electron 正在运行，请先退出旧版本后重新运行安装脚本。
```

退出旧版（Cmd + Q）后重新运行脚本。

### 7.6 macOS 仍提示「应用已损坏」

`xattr -cr` 已执行但仍提示损坏：确认是从 GitHub Release 下载的 `temp-electron.app`，再次执行 `xattr -cr /Applications/temp-electron.app`。如仍异常，正式发布需 Apple 签名 + notarization。

### 7.7 /Applications 不可写

```
安装中止：/Applications 目录不可写
```

客户账号不是管理员。让 IT 授予本地管理员权限。

---

## 7.8 查看 App 日志（远程排错）

远程协助客户时，需要看 App 主进程日志：

**macOS Console.app**：

1. 打开 `Console.app`（系统自带）
2. 左侧设备列表选中客户的 Mac
3. 搜索框输入 `temp-electron`
4. 过滤类别选「进程」
5. 可看到主进程、GPU 进程、Renderer 进程的 stdout/stderr

**日志关键字参考**：

| 关键字 | 含义 |
|---|---|
| `[OpenClaw]` | OpenClaw Gateway 启动日志 |
| `[OpenClaw] Using port 18789` | 实际使用端口 |
| `[OpenClaw] Gateway ready` | Gateway 启动成功 |
| `[NodeBootstrap]` | Node 自举流程日志 |
| `[NodeBootstrap] Latest v22: v22.x.x` | 已下载的 Node 版本 |
| `[NodeBootstrap] Downloading ...` | 下载进度 |
| `[OpenClaw] No compatible Node found` | 找不到 Node 22.19+ |
| `Bootstrap failed: ...` | Node 下载/解压失败 |
| `[BGCHECK_RUN_AGENT]` | 背调 Agent 调用日志 |
| `Network service crashed` | 浏览器底层网络异常 |

**直接查看日志文件**（开发者选项）：

```bash
# 主进程日志通过 macOS 系统日志系统，不写文件
# 渲染端日志可通过 Chrome DevTools 查看（开发模式）
```

---

## 8. 手动离线安装片段（备选）

```bash
ZIP=~/Downloads/temp-electron-darwin-arm64-1.0.xx.zip
unzip -q "$ZIP" -d /tmp/te
xattr -cr /tmp/te/temp-electron.app
rm -rf /Applications/temp-electron.app
ditto /tmp/te/temp-electron.app /Applications/temp-electron.app
open /Applications/temp-electron.app
```

应用首次启动仍会自动下载 Node。

---

## 9. 卸载

```bash
# 删除应用
rm -rf /Applications/temp-electron.app

# 删除用户数据（含 Node 运行时）
rm -rf ~/Library/Application\ Support/temp-electron
```

---

## 10. 内部测试 Checklist

- [ ] Apple Silicon：脚本选中 `arm64` 资产，应用下载 Node darwin-arm64。
- [ ] Intel Mac：脚本选中 `x64` 资产，应用下载 Node darwin-x64。
- [ ] 删除 `~/Library/Application Support/temp-electron/runtime/` 后启动应用：`NodeBootstrapPage` → `LoadingPage` → 主界面，约 30s。
- [ ] 再次启动应用：pull-on-mount 拿到 ready，直接 `LoadingPage` → 主界面，秒级。
- [ ] 断网测试：bootstrap failed → 重试按钮；连续 3 次后禁用。
- [ ] 重复执行安装脚本不会留下半成品。
- [ ] 测试 App 必须放在 `/Applications` 或 `~/Applications`，不要放在 `/tmp`（macOS TCC 会拒绝从 `/tmp` 启动未签名 App）。

---

## 11. 关键文件与代码索引

- 安装脚本：`scripts/install-mac.sh`
- Node 自举服务：`src/services/node-bootstrap.ts`
- Node 准备 UI：`src/components/NodeBootstrapPage.tsx`
- App 阶段控制：`src/App.tsx`（`AppPhase` 三段式）
- 双架构发布：`scripts/release.sh:7` `scripts/publish.sh:16`
- Node 扫描链：`src/services/openclaw.ts:findCompatibleNode()`（Method 0 优先 manifest）
- 端口常量：`src/services/openclaw.ts:13`

---

## 12. 后续增强（计划中）

- `INSTALL_RELEASE_BASE_URL` / `INSTALL_NODE_MIRROR` 环境变量支持内网镜像
- 检测到旧版本时软提示与 `osascript` 退出旧 App
- 支持 `~/Applications` 路径
- Apple Developer ID 签名 + notarization
- SHA256 校验发布 zip，Release notes 中附 checksum
- **测试包必须放在 macOS 信任路径（/Applications、~/Applications），不能放 /tmp，否则 TCC 拒绝启动**