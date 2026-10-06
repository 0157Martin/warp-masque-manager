# warp-masque-manager

使用 Cloudflare 官方 Linux 客户端，以 Local Proxy 模式提供仅本机可访问的 SOCKS5 代理。安装器优先使用 MASQUE；若默认 Happy Eyeballs 失败，会测试固定 IPv4 入口和备用端口，最后尝试官方客户端支持的 WireGuard 协议。

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
