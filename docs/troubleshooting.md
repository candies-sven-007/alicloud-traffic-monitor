# 常见问题与故障排查

## 1. Telegram 告警无法收到
- 执行测试命令：
  ```bash
  alicloud-traffic-monitor test
  ```
- 检查 ECS 出方向 443 端口安全组是否放行。
- 确认 `/var/lib/alicloud-traffic-monitor/traffic.log` 中是否有 `Telegram API error` 报错记录。

## 2. 达到 200 GB 后 sing-box 是否会被意外重启？
不会。守护进程每次循环检测到存在 `/var/lib/alicloud-traffic-monitor/limit.lock` 标记时，如果 `sing-box` 处于 `started` 状态，将立即无缝拉停。

## 3. 服务器重启后流量计数会丢失吗？
不会。状态文件 `/var/lib/alicloud-traffic-monitor/state` 采用原子写入方式保存当前月份的出站累计值，并在网卡 `tx_bytes` 计数器归零时自适应累加。
