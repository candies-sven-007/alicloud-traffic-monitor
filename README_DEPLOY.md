# VPS 一键部署指南

**当前时间：** 2026-09-04 20:52:14 (UTC+8)

## 📦 可用文件

| 文件 | 用途 | 大小 |
|-----|-----|------|
| `alicloud-traffic-monitor-v2.0.0.zip` | 完整项目包 | 33KB |
| `deploy-vps.sh` | VPS一键部署脚本 | ~3KB |

---

## 🚀 部署方式选择

### 选项 1：使用一键部署脚本（推荐）

**步骤 1：在VPS上下载部署脚本**

```bash
# 下载脚本
curl -fsSL "https://你的github仓库/deploy-vps.sh" -o /tmp/deploy.sh

# 或者（如果已有脚本在本地）
# 上传脚本到VPS: scp deploy-vps.sh root@your-vps:/tmp/
```

**步骤 2：执行部署**

```bash
sudo sh /tmp/deploy.sh
```

**步骤 3：等待完成**

脚本会自动：
- ✅ 安装依赖
- ✅ 下载项目
- ✅ 解压并安装
- ✅ 生成配置文件
- ✅ 启动服务

---

### 选项 2：手动分步部署

**步骤 1：在VPS上下载压缩包**

```bash
# 方式A：使用GitHub raw链接
curl -fsSL "https://你的github仓库/alicloud-traffic-monitor-v2.0.0.zip" -o app.zip

# 方式B：如果有其他源
wget "https://你的服务器/alicloud-traffic-monitor-v2.0.0.zip" -O app.zip
```

**步骤 2：解压**

```bash
unzip app.zip
cd alicloud-traffic-monitor-v2
```

**步骤 3：安装**

```bash
sudo chmod +x install.sh
sudo ./install.sh install
```

**步骤 4：配置（可选）**

```bash
# 编辑配置文件
sudo vi /etc/alicloud-traffic-monitor.conf

# 测试Telegram（如果配置了）
alicloud-traffic-monitor test
```

---

## 📝 上传到 GitHub 的步骤

### 1. 创建 GitHub 仓库

```bash
# 本地创建仓库
git init alicloud-traffic-monitor-v2
cd alicloud-traffic-monitor-v2

# 配置git
git config user.name "Your Name"
git config user.email "your@email.com"

# 添加所有文件
git add .
git commit -m "Initial commit - v2.0.0"

# 添加远程仓库
git remote add origin https://github.com/YOUR_USERNAME/alicloud-traffic-monitor.git

# 推送到GitHub
git branch -M main
git push -u origin main
```

### 2. 获取 Raw 链接

**压缩包的 Raw 链接：**
```
https://github.com/YOUR_USERNAME/alicloud-traffic-monitor/archive/refs/heads/main.zip
```

**部署脚本的 Raw 链接：**
```
https://raw.githubusercontent.com/YOUR_USERNAME/alicloud-traffic-monitor/main/deploy-vps.sh
```

### 3. 在 VPS 上使用 Raw 链接

```bash
# 直接执行脚本（最简单）
sudo sh <(curl -fsSL "https://raw.githubusercontent.com/YOUR_USERNAME/alicloud-traffic-monitor/main/deploy-vps.sh")

# 或者先下载再执行
curl -fsSL "https://raw.githubusercontent.com/YOUR_USERNAME/alicloud-traffic-monitor/main/deploy-vps.sh" -o deploy.sh
sudo sh deploy.sh
```

---

## 🔗 常用 GitHub Raw 链接格式

### 从分支获取

```
https://raw.githubusercontent.com/USERNAME/REPO/BRANCH/FILE_PATH
```

**示例：**
```
# 获取 main 分支的 deploy-vps.sh
https://raw.githubusercontent.com/candies/alicloud-traffic-monitor/main/deploy-vps.sh

# 获取 main 分支的项目压缩包
https://github.com/candies/alicloud-traffic-monitor/archive/refs/heads/main.zip
```

### 从标签获取

```
https://raw.githubusercontent.com/USERNAME/REPO/v2.0.0/FILE_PATH
```

---

## ✅ VPS 部署后的验证

部署完成后，在 VPS 上运行：

```bash
# 1. 查看状态
alicloud-traffic-monitor status

# 2. 检查服务
rc-service alicloud-traffic-monitor status

# 3. 查看日志
tail -20 /var/lib/alicloud-traffic-monitor/traffic.log

# 4. 运行诊断
alicloud-traffic-monitor diagnose

# 5. 测试通知（如果配置）
alicloud-traffic-monitor test
```

---

## 🐛 常见问题

### Q：下载时提示 "Connection refused"？

**A：** 检查网络和防火墙
```bash
# 测试连接
curl -I https://github.com

# 如果无法连接，尝试使用代理
curl -x PROXY_IP:PORT "https://..."
```

### Q：解压失败？

**A：** 确保安装了 unzip
```bash
apk add --no-cache unzip
```

### Q：安装脚本权限不足？

**A：** 使用 sudo 运行
```bash
sudo sh deploy-vps.sh
```

### Q：如何自定义 GitHub 仓库地址？

**A：** 修改脚本中的 `GITHUB_RAW_URL` 变量，或者传递参数

```bash
# 使用默认地址（candies仓库）
sudo sh deploy-vps.sh

# 使用自定义地址
sudo sh deploy-vps.sh "https://你的github仓库/archive/refs/heads/main.zip"
```

---

## 📋 完整的一行部署命令

### 最简洁的方式（推荐）

```bash
sudo sh <(curl -fsSL "https://raw.githubusercontent.com/candies/alicloud-traffic-monitor/main/deploy-vps.sh")
```

### 带自定义仓库地址

```bash
sudo sh <(curl -fsSL "https://raw.githubusercontent.com/YOUR_USERNAME/alicloud-traffic-monitor/main/deploy-vps.sh") "https://github.com/YOUR_USERNAME/alicloud-traffic-monitor/archive/refs/heads/main.zip"
```

---

## 🔄 后续更新

### 更新已安装的版本

```bash
cd /opt/alicloud-traffic-monitor
sudo ./install.sh update
```

### 从 GitHub 直接更新

```bash
cd /opt/alicloud-traffic-monitor

# 拉取最新代码
git pull origin main

# 重新安装
sudo ./install.sh install
```

---

## 📖 部署后查看文档

文档位置：
```
/opt/alicloud-traffic-monitor/docs/
```

查看文档：
```bash
# 查看安装指南
cat /opt/alicloud-traffic-monitor/docs/INSTALL.md

# 查看配置指南
cat /opt/alicloud-traffic-monitor/docs/configuration.md

# 查看故障排查
cat /opt/alicloud-traffic-monitor/docs/troubleshooting.md
```

---

## 🎯 总结

| 方式 | 命令 | 适用场景 |
|-----|------|--------|
| 最快 | `sudo sh <(curl ... deploy-vps.sh)` | 生产环境一键部署 |
| 标准 | `sudo ./install.sh install` | 已下载项目 |
| 自定义 | `deploy-vps.sh + URL参数` | 自有GitHub仓库 |

---

**现在你可以轻松地在任何 VPS 上一键部署这个应用了！** 🎉

