# warp-masque-manager

作者：**Martin&林知远**
使用 Cloudflare 官方 Linux 客户端，以 Local Proxy 模式提供仅本机可访问的 SOCKS5 代理。安装器优先使用 MASQUE；若默认 Happy Eyeballs 失败，会测试固定 IPv4 入口和备用端口，最后尝试官方客户端支持的 WireGuard 协议。

## 一键安装、验证与卸载

```bash
# 安装到 127.0.0.1:40000，并完成真实 WARP 流量验证
bash <(curl -fsSL https://raw.githubusercontent.com/0157Martin/warp-masque-manager/main/install.sh) install

# 验证版本、服务、监听和 Cloudflare trace（必须返回 warp=on）
warp-masque version
warp-masque status
warp-masque test 40000

# 彻底卸载官方客户端、注册、配置和管理命令
bash <(curl -fsSL https://raw.githubusercontent.com/0157Martin/warp-masque-manager/main/install.sh) uninstall
```

自定义本机 SOCKS5 端口：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0157Martin/warp-masque-manager/main/install.sh) install 41000
bash <(curl -fsSL https://raw.githubusercontent.com/0157Martin/warp-masque-manager/main/install.sh) verify 41000
```

```bash
warp-masque install 40000
warp-masque status
warp-masque test 40000
warp-masque stop
warp-masque start
warp-masque diagnose
warp-masque repair 40000
warp-masque uninstall
```

该后端不修改系统默认路由。所有候选入口都必须通过本机 SOCKS5 请求 Cloudflare trace 并返回 `warp=on`，否则安装失败且保留注册供后续修复。

本项目供 `v2ray-manager` 调用，也可以独立使用。对调用方提供统一的 `install/status/test/start/stop/diagnose/repair/uninstall/version` 接口。

安装脚本使用独立的 `APP_VERSION` 标识自身版本，避免与 Debian/Ubuntu `/etc/os-release` 中的 `VERSION` 变量冲突；CI 会实际加载系统版本文件验证该路径。
