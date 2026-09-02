# GPU1 上传服务部署

此部署保持现有 HTTPS 分片上传架构。iPhone 不使用 SSH/SCP，也不会接触 Linux 账号密码。上传服务运行在 Docker 中，但通过 bind mount 将最终文件直接写到 GPU1 宿主机：

```text
/data2/zhaobin/presentation-capture/<video-id>/final.mp4
/data2/zhaobin/presentation-capture/<video-id>/audio.wav
/data2/zhaobin/presentation-capture/<video-id>/presentation.<ppt|pptx|pdf>
```

每个录制使用独立的 `<video-id>` 目录，避免不同用户和任务的同名文件互相覆盖。容器内的 `/data` 对应宿主机的 `/data2/zhaobin/presentation-capture`，文件不保存在容器临时层。

## 部署前提

请先让 GPU1 管理员确认：

- 允许在 GPU1 运行此服务和 Docker；
- 现有 443 端口的反向代理可以增加该服务；
- `smc-gpu1.ddns.comp.nus.edu.sg` 可以作为 App API 域名；
- `/data2/zhaobin` 的容量、备份、保留和权限策略；
- 校外和移动网络访问符合 NUS/SoC 安全政策。

不要覆盖 GPU1 已有的 443 服务，也不要将 Linux 密码、OAuth client secret、TLS 私钥或 `AUTH_SECRET` 提交到 Git。截图或聊天中出现过的初始密码应视为已泄露并立即轮换。建议部署账号使用 SSH Key，并关闭公网密码登录。

## GPU1 上准备目录

登录 GPU1 后，在自己的授权目录中执行：

```bash
mkdir -p /data2/zhaobin/presentation-capture
chmod 750 /data2/zhaobin/presentation-capture
```

确认 Docker 容器使用的 UID/GID 对该目录具有写权限。不要通过 `chmod 777` 绕过权限问题。

## 配置生产变量

在 GPU1 的 shell 或受保护的部署环境中设置变量；不要把实际值加入仓库：

```bash
export AUTH_SECRET='<至少 32 字节的随机值>'
export GOOGLE_CLIENT_IDS='<Google backend/web OAuth client ID>'
export UPLOAD_UID="$(id -u)"
export UPLOAD_GID="$(id -g)"
```

Linux SSH 登录和 App 登录是两套身份体系。App 只使用 Google ID token 换取上传 API session token；上传服务不接受 Linux 用户名和密码。
Compose 使用 `UPLOAD_UID` 和 `UPLOAD_GID` 让容器以部署账号的宿主机身份写文件，避免生成 root 所有的上传文件。

## 启动上传服务

从仓库的 `server` 目录执行：

```bash
docker compose -f docker-compose.gpu1.yml up --build -d
docker compose -f docker-compose.gpu1.yml ps
curl --fail http://127.0.0.1:8080/health
```

Compose 只把应用端口绑定到 GPU1 的 `127.0.0.1:8080`，不会把 8080 直接暴露到公网。现有 Nginx/Caddy 应将 HTTPS 请求代理到该地址。

Nginx 路由示例（合并到管理员维护的现有 443 配置中，而不是覆盖整个配置）。使用独立路径前缀可以保留 GPU1 上现有的网站和接口：

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

App 的服务器 URL 应使用证书对应的 HTTPS 域名和上述路径前缀，不能使用公网 IP：

```text
https://smc-gpu1.ddns.comp.nus.edu.sg/presentation-capture
```

## 验证

在 GPU1 本机：

```bash
curl --fail http://127.0.0.1:8080/health
```

在关闭 VPN、未使用跳板机的外部网络：

```bash
curl --fail https://smc-gpu1.ddns.comp.nus.edu.sg/presentation-capture/health
```

完成一次真机上传后检查：

```bash
find /data2/zhaobin/presentation-capture -mindepth 2 -maxdepth 2 \
  -type f \( -name 'final.mp4' -o -name 'audio.wav' -o -name 'presentation.*' \) -ls
```

必须在真实 iPhone 上继续验证 WAV 可播放、音频时长与 MP4 一致、暂停/继续后的连续性，以及锁屏、断网和恢复上传。
