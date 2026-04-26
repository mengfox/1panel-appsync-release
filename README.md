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

## 一、项目说明

`1panel-appsync` 用于从 GitHub / CNB 等 Git 仓库同步第三方 1Panel 应用商店到本地 1Panel 应用目录。

默认同步的应用商店仓库：

```text
GitHub:
https://github.com/mengfox/1panel-appstore.git

CNB:
https://cnb.cool/mengfox/1panel-appstore
```

默认同步到 1Panel 本地应用目录：

```bash
/opt/1panel/resource/apps/local
```

程序会自动检测 1Panel 安装路径，也支持通过参数指定自定义路径。

---

## 二、核心功能

```text
1. 支持 GitHub + CNB 双源同步
2. 支持自动测速选择最快源
3. 支持国内优先 CNB
4. 支持海外优先 GitHub
5. 支持自动识别 1Panel 本地应用目录
6. 支持 --local-dir 指定自定义目录
7. 支持同步前自动备份
8. 支持失败回滚
9. 支持应用包结构校验
10. 支持 Docker Compose 安全校验
11. 支持 daemon 内置定时同步
12. 支持 systemd 保活
13. 支持一键安装和更新
14. 支持 GitHub Release / CNB Release 分发
```

---

## 三、一键安装

### GitHub 安装

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash
```

### CNB 国内安装

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo env FORCE_CN=true bash
```

> 注意：CNB Raw 文件路径必须是 `/-/git/raw/main/`，不是 `/-/raw/main/`。

---

## 四、一键更新

### GitHub 更新

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash -s update
```

### CNB 国内更新

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo env FORCE_CN=true bash -s update
```

---

## 五、安装指定版本

例如安装 `v0.3.9`：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env CHANNEL=v0.3.9 bash
```

国内优先 CNB：

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo env FORCE_CN=true CHANNEL=v0.3.9 bash
```

---

## 六、手动安装

### AMD64

```bash
curl -fL -o 1panel-appsync https://github.com/mengfox/1panel-appsync-release/releases/latest/download/1panel-appsync-linux-amd64

chmod +x 1panel-appsync

sudo install -m 0755 1panel-appsync /usr/local/bin/1panel-appsync

1panel-appsync version
```

### ARM64

```bash
curl -fL -o 1panel-appsync https://github.com/mengfox/1panel-appsync-release/releases/latest/download/1panel-appsync-linux-arm64

chmod +x 1panel-appsync

sudo install -m 0755 1panel-appsync /usr/local/bin/1panel-appsync

1panel-appsync version
```

---

## 七、校验文件

下载 SHA256 校验文件：

```bash
curl -fL -o sha256.txt https://github.com/mengfox/1panel-appsync-release/releases/latest/download/sha256.txt
```

校验 AMD64：

```bash
sha256sum -c sha256.txt --ignore-missing
```

---

## 八、常用命令

### 查看版本

```bash
1panel-appsync version
```

### 一键诊断

```bash
1panel-appsync doctor
```

### 检测依赖

```bash
1panel-appsync deps
```

自动安装缺少依赖：

```bash
1panel-appsync deps --install
```

### 检测 1Panel 本地应用目录

```bash
1panel-appsync detect
```

### 检查配置和源

```bash
1panel-appsync check
```

### 测试 GitHub / CNB 源

```bash
1panel-appsync source
```

### 预览同步

```bash
1panel-appsync sync --dry-run
```

### 正式同步

```bash
1panel-appsync sync
```

### 查看同步状态

```bash
1panel-appsync status
```

### 回滚最近一次备份

```bash
1panel-appsync rollback
```

---

## 九、指定同步源

### 强制使用 CNB

```bash
1panel-appsync sync --source cnb
```

### 强制使用 GitHub

```bash
1panel-appsync sync --source github
```

### 国内模式

```bash
1panel-appsync sync --region cn
```

### 海外模式

```bash
1panel-appsync sync --region global
```

### 自动测速模式

```bash
1panel-appsync sync --region auto
```

---

## 十、指定 1Panel 本地应用路径

默认情况下，程序会自动检测 1Panel 本地应用目录。

如果你的 1Panel 安装路径是自定义的，可以手动指定：

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

为了安全，`--local-dir` 必须以以下路径结尾：

```text
resource/apps/local
apps/local
```

允许示例：

```text
/opt/1panel/resource/apps/local
/data/1panel/resource/apps/local
/www/server/1panel/resource/apps/local
```

不允许示例：

```text
/
/tmp/apps
/root/apps
/opt/1panel
```

---

## 十一、systemd 服务

安装脚本会自动创建 systemd 服务：

```bash
/etc/systemd/system/1panel-appsync.service
```

启动服务：

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

---

## 十二、systemd 下指定自定义路径

编辑环境文件：

```bash
sudo nano /etc/1panel-appsync/env
```

写入：

```bash
APPSYNC_DAEMON_ARGS="--local-dir /data/1panel/resource/apps/local"
```

重启服务：

```bash
sudo systemctl restart 1panel-appsync.service
```

---

## 十三、配置说明

从较新版本开始，`1panel-appsync` 已内置默认配置。

即使不存在：

```bash
/etc/1panel-appsync/config.yml
```

程序也可以直接运行：

```bash
1panel-appsync doctor
1panel-appsync source
1panel-appsync sync --dry-run
```

如果你需要自定义配置，可以创建：

```bash
sudo mkdir -p /etc/1panel-appsync
sudo nano /etc/1panel-appsync/config.yml
```

程序优先级：

```text
外部配置文件存在：优先使用 /etc/1panel-appsync/config.yml
外部配置文件不存在：自动使用程序内置默认配置
```

---

## 十四、备份与回滚

每次正式同步前，程序会自动备份当前本地应用目录。

备份目录：

```bash
/var/lib/1panel-appsync/backups/
```

查看备份：

```bash
ls -lah /var/lib/1panel-appsync/backups/
```

回滚最近一次备份：

```bash
1panel-appsync rollback
```

如果使用自定义路径：

```bash
1panel-appsync rollback --local-dir /data/1panel/resource/apps/local
```

---

## 十五、目录说明

默认安装位置：

```bash
/usr/local/bin/1panel-appsync
```

配置目录：

```bash
/etc/1panel-appsync/
```

数据目录：

```bash
/var/lib/1panel-appsync/
```

备份目录：

```bash
/var/lib/1panel-appsync/backups/
```

日志目录：

```bash
/var/log/1panel-appsync/
```

systemd 服务：

```bash
/etc/systemd/system/1panel-appsync.service
```

---

## 十六、卸载

使用安装脚本卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash -s uninstall
```

CNB 国内地址：

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo bash -s uninstall
```

卸载只会移除：

```text
1. /usr/local/bin/1panel-appsync
2. systemd 服务文件
```

默认保留配置、数据和备份：

```text
/etc/1panel-appsync/
/var/lib/1panel-appsync/
/var/log/1panel-appsync/
```

---

## 十七、故障排查

### 1. 先执行诊断

```bash
1panel-appsync doctor
```

### 2. 检查 CNB Raw 脚本地址

正确地址：

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | head
```

正常应该看到：

```bash
#!/usr/bin/env bash
```

如果看到：

```html
<!DOCTYPE html>
```

说明访问到了 HTML 页面，地址不正确或者仓库未同步成功。

### 3. 检查 Git 源

```bash
1panel-appsync source
```

### 4. 预览同步

```bash
1panel-appsync sync --dry-run
```

### 5. 查看服务日志

```bash
journalctl -u 1panel-appsync.service -f
```

---

## 十八、Release 文件

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

---

## 十九、License

Copyright © MengFox.

All rights reserved.
