# Deploy on EC2 (Amazon Linux 2023)

This project expects a tiny EC2 box with Docker and an instance role that can write to your S3 bucket.

## 0. Prep in AWS (one-time)

### Create/choose an S3 bucket for HLS:

Name example: `my-live-video`

If you’ll serve directly from S3, allow public reads (or prefer CloudFront + OAC).

### Create an IAM role for EC2 with this inline policy (scope to your bucket):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:GetBucketLocation"
      ],
      "Resource": ["arn:aws:s3:::MY_BUCKET", "arn:aws:s3:::MY_BUCKET/*"]
    }
  ]
}
```

Attach this role when you launch the instance (no static keys needed).

### Security Group (minimum):

- TCP 22 from your IP (SSH)
- TCP 1935 from your encoder’s IP(s) (RTMP)
- TCP 80 optional (for basic health page; you can also leave it closed)

## 1. Launch the instance

- **AMI:** Amazon Linux 2023
- **Size:** t3.small (or t3.micro for light tests)
- **Disk:** 20–30 GB gp3
- Attach the IAM role from step 0

## 2. Install Docker (+ Compose v2)

SSH in and run:

```sh
# System updates & Docker
sudo dnf -y update
sudo dnf -y install docker curl
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# re-login after this step to pick up the docker group

# Docker Compose v2 (CLI plugin)
VER="v2.29.2"
sudo mkdir -p /usr/libexec/docker/cli-plugins
sudo curl -SL "https://github.com/docker/compose/releases/download/${VER}/docker-compose-linux-x86_64" \
  -o /usr/libexec/docker/cli-plugins/docker-compose
sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose

# quick sanity check
docker --version
docker compose version
```

## 3. Clone and configure

Grab the code:

```sh
git clone https://github.com/<you>/rtmp-recorder.git
cd rtmp-recorder
```

Configure environment:

```sh
cp .env.example .env
```

Edit `.env` with your values:

```env
AWS_REGION=us-west-2
S3_BUCKET=MY_BUCKET
S3_PREFIX=hls
PUBLIC_ACL=true # or false if using CloudFront+OAC
SYNC_INTERVAL_SECONDS=1
HLS_FRAGMENT_SECONDS=2
HLS_PLAYLIST_SECONDS=30
```

(Optional) lock down port 80 exposure by SG; it's only for local health/index

## 4. Launch the stack

```sh
docker compose up -d
docker compose ps
docker compose logs -f --tail=200
```

You should see the rtmp and publisher containers running and healthy.

## 5. Ingest a test stream

From your encoder, push to:

```
rtmp://<EC2_PUBLIC_IP>/live/<STREAM_KEY>
```

Or from a laptop with FFmpeg:

```sh
ffmpeg -re -f lavfi -i "testsrc=size=1280x720:rate=30" \
  -f lavfi -i "sine=frequency=1000:sample_rate=48000" \
  -c:v libx264 -preset veryfast -b:v 3000k -g 60 -keyint_min 60 -sc_threshold 0 \
  -c:a aac -b:a 128k -ar 48000 -ac 2 \
  -f flv "rtmp://<EC2_PUBLIC_IP>/live/<STREAM_KEY>"
```

Verify HLS files appear:

```sh
docker exec -it rtmp ls -l /hls/<STREAM_KEY> | head
```

## 6. Playback URL

### Direct S3 (public objects):

```
https://MY_BUCKET.s3.amazonaws.com/hls/<STREAM_KEY>/index.m3u8
```

### Via CloudFront (recommended for production):

Point a distribution at the bucket (Origin Access Control), set low TTLs for `.m3u8` (0–5s) and moderate for `.ts` (5–30s), then:

```
https://YOUR_DISTRIBUTION/hls/<STREAM_KEY>/index.m3u8
```

### Simple web player snippet:

```html
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
<video id="v" controls autoplay muted playsinline></video>
<script>
  const src = "https://MY_BUCKET.s3.amazonaws.com/hls/STREAM_KEY/index.m3u8";
  const v = document.getElementById("v");
  if (v.canPlayType("application/vnd.apple.mpegurl")) v.src = src;
  else if (Hls.isSupported()) {
    const h = new Hls();
    h.loadSource(src);
    h.attachMedia(v);
  }
</script>
```

## 7. Tuning & housekeeping

- **Latency vs cost:** `nginx/nginx.conf` → `hls_fragment` (shorter = lower latency, more S3 PUTs).
- **Window length:** `hls_playlist_length` (e.g., 12–30s).
- **Cache behavior:** `.env` → `PLAYLIST_MAXAGE` and `SEGMENT_MAXAGE` (seconds).
- **Disk usage:** enabled `hls_cleanup on`; add an S3 Lifecycle rule to expire old `*.ts` if needed.

## 8. Troubleshooting

### Nothing in S3

- Confirm the EC2 instance role is attached and policy includes your bucket
- `docker compose logs -f publisher` for sync errors

### Encoder can’t connect

- SG must allow TCP 1935 from the encoder’s IP; verify instance’s public IP

### Playback stalls / slow updates

- Lower `PLAYLIST_MAXAGE` in `.env`
- If using CloudFront, set small TTLs for `.m3u8` (0–5s)

### CPU high

- The stack doesn’t transcode; CPU spikes usually mean your encoder settings are very high bitrate or many concurrent streams. Scale instance size if needed.

## 9. Start/stop/upgrade

### Start

```sh
docker compose up -d
```

### Stop

```sh
docker compose down
```

### Upgrade to latest images

```sh
docker compose pull
docker compose up -d --remove-orphans
```

## 10. Optional: user-data bootstrap (auto install on first boot)

Paste into EC2 User data (replace bucket/region):

```bash
#!/bin/bash
set -eux
dnf -y update
dnf -y install docker curl git
systemctl enable --now docker
VER="v2.29.2"
mkdir -p /usr/libexec/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/${VER}/docker-compose-linux-x86_64" \
  -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose

git clone https://github.com/<you>/rtmp-recorder.git /opt/rtmp-recorder
cd /opt/rtmp-recorder
cp .env.example .env
sed -i 's/^AWS_REGION=._/AWS_REGION=us-west-2/' .env
sed -i 's/^S3_BUCKET=._/S3_BUCKET=MY_BUCKET/' .env
docker compose up -d
```
