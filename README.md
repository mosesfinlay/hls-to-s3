# Deploy on EC2 (Amazon Linux 2023)

This project expects a tiny EC2 box with Docker and an instance role that can write to your S3 bucket.

## 0. Prep in AWS (one-time)

### Create/choose an S3 bucket for MP4 recordings:

Name example: `my-video-recordings`

If you'll serve directly from S3, allow public reads (or prefer CloudFront + OAC).

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
S3_PREFIX=recordings
PUBLIC_ACL=true # or false if using CloudFront+OAC
SYNC_INTERVAL_SECONDS=30
MP4_MAXAGE=86400
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

Verify MP4 recordings appear:

```sh
docker exec -it rtmp ls -l /recordings/ | head
```

## 6. Accessing Recordings

### Direct S3 (public objects):

```
https://MY_BUCKET.s3.amazonaws.com/recordings/<STREAM_KEY>.mp4
```

### Via CloudFront (recommended for production):

Point a distribution at the bucket (Origin Access Control), then:

```
https://YOUR_DISTRIBUTION/recordings/<STREAM_KEY>.mp4
```

### Simple web player snippet:

```html
<video id="v" controls width="800">
  <source
    src="https://MY_BUCKET.s3.amazonaws.com/recordings/STREAM_KEY.mp4"
    type="video/mp4"
  />
  Your browser does not support the video tag.
</video>
```

## 7. Tuning & housekeeping

- **Recording quality:** Adjust encoder settings for desired bitrate and resolution.
- **Sync frequency:** `.env` → `SYNC_INTERVAL_SECONDS` (how often to upload new recordings).
- **Cache behavior:** `.env` → `MP4_MAXAGE` (seconds).
- **Disk usage:** Add an S3 Lifecycle rule to expire old `*.mp4` files if needed.

## 8. Troubleshooting

### Nothing in S3

- Confirm the EC2 instance role is attached and policy includes your bucket
- `docker compose logs -f publisher` for sync errors

### Encoder can’t connect

- SG must allow TCP 1935 from the encoder’s IP; verify instance’s public IP

### Recordings not appearing

- Check `SYNC_INTERVAL_SECONDS` in `.env` - recordings sync periodically
- Verify the stream is actually being recorded: `docker exec -it rtmp ls -l /recordings/`

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

### Migrate to Newest Version (Safe Deployment)

When deploying a new version of the project code (not just Docker images):

#### Option 1: Zero-Downtime Migration (Recommended)

```sh
# 1. Backup current setup
cp -r rtmp-recorder rtmp-recorder-backup-$(date +%Y%m%d)

# 2. Pull latest code
cd rtmp-recorder
git fetch origin
git pull origin main

# 3. Check for new environment variables
diff .env.example .env || echo "Review .env for new variables"

# 4. Update containers with new configuration
docker compose pull
docker compose up -d --remove-orphans

# 5. Verify services are healthy
docker compose ps
docker compose logs -f --tail=50
```

#### Option 2: Clean Migration (Brief Downtime)

```sh
# 1. Stop services gracefully (completes current chunks)
docker compose down

# 2. Backup recordings and config
sudo cp -r /var/lib/docker/volumes/rtmp-recorder_recordings_data /backup/recordings-$(date +%Y%m%d)
cp .env .env.backup

# 3. Pull latest code
git pull origin main

# 4. Update environment if needed
# Compare .env.example with your .env and add any new variables

# 5. Start with latest version
docker compose pull
docker compose up -d

# 6. Verify migration
docker compose logs -f --tail=100
```

#### Migration Checklist

Before migrating, always:

- [ ] **Check release notes** for breaking changes
- [ ] **Backup recordings** (if using local storage)
- [ ] **Review .env.example** for new variables
- [ ] **Test in staging** if possible
- [ ] **Monitor logs** after deployment
- [ ] **Verify S3 uploads** are working
- [ ] **Test stream ingestion** with a short test stream

#### Rollback Plan

If something goes wrong:

```sh
# Quick rollback to previous version
docker compose down
git checkout HEAD~1  # or specific commit
docker compose up -d

# Or restore from backup
rm -rf rtmp-recorder
mv rtmp-recorder-backup-YYYYMMDD rtmp-recorder
cd rtmp-recorder
docker compose up -d
```

#### Environment Variable Changes

When migrating from older versions, check for these changes:

- **v1.0 → v2.0**: `RECORD_DURATION` → `CHUNK_DURATION_MINUTES`
- **New variables**: Always compare `.env.example` with your current `.env`

#### Monitoring After Migration

```sh
# Watch logs for errors
docker compose logs -f

# Check container health
docker compose ps

# Verify recordings are being created
docker exec rtmp ls -la /recordings/flv/

# Test S3 sync
docker compose logs publisher | grep -i error
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
sed -i 's/^S3_PREFIX=._/S3_PREFIX=recordings/' .env
docker compose up -d
```
