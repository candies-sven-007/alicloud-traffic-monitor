# 配置说明

配置文件路径：`/etc/alicloud-traffic-monitor.conf`
权限应保持为 `600`（仅允许 root 读写）。

## 配置项详解

| 参数名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `INTERFACE` | `eth0` | 阿里云 ECS 默认公网绑定的物理网卡。 |
| `SINGBOX_SERVICE` | `sing-box` | 受保护的 OpenRC 服务名称。 |
| `INTERVAL` | `1` | 流量轮询与熔断守护频率（秒）。 |
| `TG_BOT_TOKEN` | - | Telegram Bot API 访问凭据。 |
| `TG_CHAT_ID` | - | 告警信息接收者的 Telegram Chat ID。 |

修改后重启服务生效：
```bash
rc-service alicloud-traffic-monitor restart
```
