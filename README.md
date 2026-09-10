# SBP 安装与发行

此仓库只分发 SBP 的安装入口、编译后的安装包和版本说明。源代码在独立的私有仓库维护。

在 Linux 服务器的交互式 Bash 终端执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/welenwho/sbp-release/main/install.sh)
```

选择最新稳定版或输入版本号。脚本下载并校验发布包后进入安装菜单：

- 新机器选择 Docker 或 Native，设置安装目录及面板地址（支持路径）。Docker 模式可选择 Caddy 或 Nginx。
- 已有 SBP 自动识别部署模式和安装目录，显示版本并确认升级。
- 安装器保留现有订阅、凭据、数据库和代理核心；升级期间核心继续服务，脚本错误触发回滚。
- 安装不检测、不导入、不卸载 vasma；该流程由管理员在面板中手动发起。
- QNAP 本入口仅下载、校验并保留安装包，需使用包内专用 Container Station Compose 模板，不能使用通用 Docker 安装器覆盖。

支持 Linux amd64 / arm64。需要 Bash、curl；缺少 unzip 或校验工具时会提示安装。脚本从官方 GitHub 分发地址下载，不要求 GitHub Token。GitHub 不可达时可手动下载 ZIP 后运行包内 `install.sh`。

工作目录默认 `/var/tmp`，不会直接向小容量 `/tmp` 解压；空间不足时提示选择目录。QNAP 应选择 `/share` 下持久数据卷。

## 手动下载

从 [Releases](https://github.com/welenwho/sbp-release/releases) 下载 ZIP 与同名 `.sha256` 文件，校验后解压执行 `install.sh`。每个版本附带维护文档，保留最近 20 个稳定版本。

## Docker 镜像

- `ghcr.io/welenwho/sbp:<版本>`
- `ghcr.io/welenwho/sbp-netctl:<版本>`
- `ghcr.io/welenwho/sbp-updater:<版本>`

核心使用 [singbox-v2ray-api](https://github.com/welenwho/singbox-v2ray-api) 的独立版本；升级平台不自动升级核心。
