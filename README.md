# HLS to S3 (Axis + CamStreamer → nginx-rtmp → S3)

This repo gives you a lean, reproducible setup to take an **RTMP push** from CamStreamer (on an Axis camera),
segment it to **HLS** using `nginx-rtmp`, and continuously mirror the segments and playlists to **Amazon S3**.
Tested on **Ubuntu 22.04 (arm64)** on **t4g.nano** in `us-west-2`.

## What you get

- **Docker Compose** for `nginx-rtmp` (no transcoding; just HLS segmentation)
- **Host-level systemd service** that runs `aws s3 sync` in a tight loop
- **Nginx config** tuned for 1080p with 6s segments and a ~2-minute local playlist window
- **S3 lifecycle** JSON to keep only the last 30 days of video

---

## Quick start (Ubuntu 22.04 on EC2)

### 0) Prereqs

- Launch EC2 in `us-west-2` (e.g., `t4g.nano`) with **IAM role** that has `s3:PutObject` to your bucket
- Open **TCP 1935** inbound from your camera’s egress IP; optionally open **TCP 80** from your IP for debugging
- Create an S3 bucket (example below): `winchester-dam-archive-usw2-001`
- (Recommended) Add a 30-day lifecycle rule (see `lifecycle.json` below)

### 1) Install Docker + Compose plugin

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
# log out/in or: newgrp docker
```
