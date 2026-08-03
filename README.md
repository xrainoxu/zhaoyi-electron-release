# temp-electron Release Channel

本仓库托管 `temp-electron`（赵懿的外贸竞调分析 App）的对外安装脚本与 Release 分发包。

源码仓库保持 private；本仓库仅暴露：
- `install/install-mac.sh` —— 客户一键安装脚本
- `latest.json` —— 最新版本清单（含 sha256）

## 一行安装命令

```bash
curl -fsSL https://raw.githubusercontent.com/xrainoxu/zhaoyi-electron-release/main/install/install-mac.sh | bash
```

## 锁版本安装

```bash
INSTALL_VERSION=v1.0.33 bash -c "$(curl -fsSL https://raw.githubusercontent.com/xrainoxu/zhaoyi-electron-release/main/install/install-mac.sh)"
```

## 自定义下载源（CDN/镜像）

```bash
INSTALL_BASE_URL=https://your-cdn.example.com/releases bash <(curl -fsSL https://raw.githubusercontent.com/xrainoxu/zhaoyi-electron-release/main/install/install-mac.sh)
```

## 历史版本

见 [Releases](https://github.com/xrainoxu/zhaoyi-electron-release/releases)。

## 安全说明

- 本应用未做 Apple Developer ID 签名，下载后会触发 macOS Gatekeeper。安装脚本会自动执行 `xattr -cr` 解除 quarantine。
- **应用必须安装到 macOS 信任路径**：`/Applications` 或 `~/Applications`。**不要放在 `/tmp`** —— macOS TCC（透明同意控制）会拒绝从 `/tmp` 启动未签名 App，主进程代码无法执行。
- 正式发布建议补 Apple Developer ID 签名 + notarization。