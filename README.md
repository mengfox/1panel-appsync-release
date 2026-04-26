# 1Panel AppSync Release

这是 `1panel-appsync` 的公开发布仓库，只包含二进制文件、安装脚本和使用说明，不包含源码。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash
```

## 国内服务器优先 CNB

```bash
curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/raw/main/install-update.sh | sudo FORCE_CN=true bash
```

## 安装指定版本

```bash
curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo CHANNEL=v0.3.9 bash
```

## 常用命令

```bash
1panel-appsync doctor
1panel-appsync detect
1panel-appsync source
1panel-appsync sync --dry-run
1panel-appsync sync
1panel-appsync status
```

## 默认同步仓库

```text
GitHub: https://github.com/mengfox/1panel-appstore.git
CNB:    https://cnb.cool/mengfox/1panel-appstore
```
