# 1Panel AppSync Release

`1panel-appsync` 是一个用于同步第三方 1Panel 应用商店的自动更新工具。

本仓库是 **1Panel AppSync 的公开发布仓库**，仅用于分发：

```text
1. Linux 二进制文件
2. 一键安装 / 更新脚本
3. Release 版本文件
4. 使用说明文档
```

本仓库 **不包含源码**。

---

## 一键安装

自动判断 GitHub / CNB 节点：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash
```

CNB 国内安装：

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo bash
```

> CNB Raw 文件路径必须是 `/-/git/raw/main/`，不是 `/-/raw/main/`。

安装完成后会默认：
- 写入 `systemd` 服务：`1panel-appsync.service`
- 先在前台立即执行一次 `1panel-appsync sync`
- 设置开机自启动
- 启动 `1panel-appsync daemon`
- 使用程序内置 `scheduler` 定时同步，之后每 10 分钟执行一次
- 不使用 `crontab`

如只想安装和启动 daemon，不想安装阶段等待首次同步：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env SYNC_AFTER_INSTALL=false bash
```

如你的 1Panel 本地应用目录不是默认路径：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env APPSYNC_DAEMON_ARGS="--local-dir /data/1panel/resource/apps/local" bash
```

---

## 一键更新

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash -s update
```

CNB：

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo bash -s update
```

---

## 安装指定版本

例如安装 `v0.5.0`：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env CHANNEL=v0.5.0 bash
```

指定版本默认从 GitHub Release 精确下载，避免 CNB Raw main 分支导致装错版本。

---

## 节点模式

默认自动测速：

```bash
REGION_MODE=auto
```

强制 CNB：

```bash
REGION_MODE=cn
```

强制 GitHub：

```bash
REGION_MODE=global
```

示例：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env REGION_MODE=cn bash
```

---

## 常用命令

```bash
1panel-appsync version
1panel-appsync doctor
1panel-appsync deps --install
1panel-appsync detect
1panel-appsync check
1panel-appsync source
1panel-appsync sync --dry-run
1panel-appsync sync
1panel-appsync status
1panel-appsync rollback
```

---

## 默认同步仓库

```text
GitHub: https://github.com/mengfox/1panel-appstore.git
CNB:    https://cnb.cool/mengfox/1panel-appstore
```

默认同步到：

```bash
/opt/1panel/resource/apps/local
```

---

## 自定义 1Panel 本地应用路径

```bash
1panel-appsync sync --local-dir /data/1panel/resource/apps/local
```

检测指定路径：

```bash
1panel-appsync detect --local-dir /data/1panel/resource/apps/local
```

daemon 模式指定路径：

```bash
1panel-appsync daemon --local-dir /data/1panel/resource/apps/local
```

`--local-dir` 必须以以下路径结尾：

```text
resource/apps/local
apps/local
```

---

## systemd 服务

一键安装脚本默认已经启用并启动服务，一般不需要手动执行。

手动启用并启动：

```bash
sudo systemctl enable --now 1panel-appsync.service
```

查看状态：

```bash
systemctl status 1panel-appsync.service
```

查看日志：

```bash
journalctl -u 1panel-appsync.service -f
```

重启服务：

```bash
sudo systemctl restart 1panel-appsync.service
```

安装时跳过自启动：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env START_SERVICE=false ENABLE_SERVICE=false bash
```

自定义 daemon 参数：

```bash
sudo nano /etc/1panel-appsync/env
sudo systemctl restart 1panel-appsync.service
```

示例：

```bash
APPSYNC_DAEMON_ARGS="--local-dir /data/1panel/resource/apps/local"
```

---

## 备份与回滚

备份目录：

```bash
/var/lib/1panel-appsync/backups/
```

回滚最近一次备份：

```bash
1panel-appsync rollback
```

---

## 卸载

GitHub：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash -s uninstall
```

CNB：

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo bash -s uninstall
```

---

## Release 文件

每个版本 Release 包含：

```text
1panel-appsync-linux-amd64
1panel-appsync-linux-arm64
sha256.txt
```

GitHub Release：

```text
https://github.com/mengfox/1panel-appsync-release/releases
```

CNB Release：

```text
https://cnb.cool/mengfox/1panel-appsync-release
```
