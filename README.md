# warp-masque-manager

使用 Cloudflare 官方 Linux 客户端，以 MASQUE Local Proxy 模式提供仅本机可访问的 SOCKS5 代理。

```bash
warp-masque install 40000
warp-masque status
warp-masque test 40000
warp-masque diagnose
warp-masque repair 40000
warp-masque uninstall
```

该后端不修改系统默认路由。Cloudflare 新版 Local Proxy 仅支持 MASQUE；如果 VPS 上游阻断 Happy Eyeballs/MASQUE，请改用独立的 `warp-wireguard-manager` 后端。

本项目供 `v2ray-manager` 调用，也可以独立使用。
