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

## 添加受管节点

在中心面板的“节点 → 添加节点”填写节点名称、公网主机名/IP，复制生成的一键命令到新 Linux 主机的 Bash 终端执行。无需事先下载 SBP 安装包；脚本会下载与中心一致的公开版本、校验、调用 Docker 节点安装器并等待注册成功。一次性 Token 不会放到下载 URL 或节点 `.env`。

目标机需要 Bash、curl，以及 root 或 sudo 权限。缺少 Docker/Compose 时由节点安装器安装。已有面板请使用接管流程；QNAP 继续使用专用运行结构。中心对应版本的安装包与镜像必须已公开发布。

## 手动下载

从 [Releases](https://github.com/welenwho/sbp-release/releases) 下载 ZIP 与同名 `.sha256` 文件，校验后解压执行 `install.sh`。每个版本附带维护文档，保留最近 20 个稳定版本。

## Docker 镜像

- `ghcr.io/welenwho/sbp:<版本>`
- `ghcr.io/welenwho/sbp-netctl:<版本>`
- `ghcr.io/welenwho/sbp-updater:<版本>`

核心使用 [singbox-v2ray-api](https://github.com/welenwho/singbox-v2ray-api) 的独立版本；升级平台不自动升级核心。
