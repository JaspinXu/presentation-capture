# Linux 上传服务部署

本文说明如何将上传服务部署到一台通用 Linux 主机。iPhone 只访问 HTTPS API，不使用 SSH/SCP，也不会接触 Linux 账号密码。Docker 通过 bind mount 将最终文件直接写入管理员指定的宿主机目录：

```text
<UPLOAD_DATA_DIR>/<video-id>/final.mp4
<UPLOAD_DATA_DIR>/<video-id>/audio.wav
<UPLOAD_DATA_DIR>/<video-id>/presentation.<ppt|pptx|pdf>
```

每次录制使用独立的 `<video-id>` 目录。文件保存在宿主机，而不是容器临时层。

## 部署前提

请先由服务器管理员确认：

- 允许在目标主机运行 Docker 服务；
- 已分配具备足够容量、备份和保留策略的数据目录；
- 现有 443 端口的反向代理可以增加独立路由；
- 域名、TLS 证书、防火墙和公网访问策略已准备妥当。

不要覆盖服务器已有的 443 服务，也不要将 Linux 密码、OAuth secret、TLS 私钥或 `AUTH_SECRET` 提交到 Git。生产账号应使用 SSH Key，并按服务器政策限制密码登录。

## 准备数据目录

以下路径只是示例，请替换为管理员授权的目录：

```bash
sudo install -d -m 750 -o "$(id -u)" -g "$(id -g)" \
  /srv/presentation-capture/data
```

如果没有 `sudo` 权限，请让管理员创建目录并授予部署账号写权限。不要用 `chmod 777` 绕过权限问题。

## 配置生产变量

在仓库的 `server` 目录中复制模板：

```bash
cp .env.production.example .env.production
chmod 600 .env.production
```

编辑 `.env.production`，填写：

- `AUTH_SECRET`：至少 32 字节的随机值；
- `GOOGLE_CLIENT_IDS`：Google backend/web OAuth client ID；
- `UPLOAD_DATA_DIR`：宿主机绝对数据路径；
- `UPLOAD_UID` 和 `UPLOAD_GID`：部署账号的 `id -u` 与 `id -g` 输出。

Linux 登录和 App 登录是两套身份体系。App 使用 Google ID token 换取上传 API session token；上传服务不接受 Linux 用户名和密码。

## 启动服务

```bash
docker compose --env-file .env.production \
  -f docker-compose.production.yml up --build -d
docker compose --env-file .env.production \
  -f docker-compose.production.yml ps
curl --fail http://127.0.0.1:8080/health
```

Compose 默认只把端口绑定到 `127.0.0.1:8080`，不会直接暴露 8080。应由 Nginx 或 Caddy 提供公网 HTTPS。

## 配置反向代理

以下 Nginx 示例使用独立路径前缀，不会占用整台服务器的网站根路径：

```nginx
location /presentation-capture/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    client_max_body_size 20m;
    proxy_read_timeout 120s;
}
```

仓库中的 `server/nginx/presentation-capture-location.conf` 提供同样的可审查配置。管理员应将配置复制到 root 管理的 Nginx 目录，不要直接 include 普通用户可写目录。

App 的服务器 URL 必须使用证书覆盖的域名，不能直接使用公网 IP：

```text
https://capture.example.com/presentation-capture
```

## 验证

在服务器本机：

```bash
curl --fail http://127.0.0.1:8080/health
```

在外部网络：

```bash
curl --fail https://capture.example.com/presentation-capture/health
```

完成一次真机上传后检查：

```bash
find "$UPLOAD_DATA_DIR" -mindepth 2 -maxdepth 2 \
  -type f \( -name 'final.mp4' -o -name 'audio.wav' -o -name 'presentation.*' \) -ls
```

必须继续在真实 iPhone 上验证 WAV 可播放、音频时长与 MP4 一致、暂停/继续连续性，以及锁屏、断网和恢复上传。

## 没有 Docker 权限时

经管理员同意，可以使用 Node.js 22 和 `server/tool/start_user_service.sh` 在普通用户权限下监听 `127.0.0.1:8080`。环境变量应保存在权限为 `600` 的 `~/.config/presentation-capture/server.env` 中，并由 systemd user service 或受管的进程管理器启动。

这种方式仍需要管理员配置 HTTPS 反向代理。普通用户部署不应修改 `/etc/nginx`。
