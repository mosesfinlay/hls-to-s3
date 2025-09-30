# hls-to-s3 (RTMP ingest → HLS → S3)

Tiny Dockerized pipeline:

- Send RTMP to `rtmp://EC2_PUBLIC_IP/live/STREAM_KEY`
- NGINX-RTMP writes HLS to `/hls/STREAM_KEY/`
- Sidecar syncs to `s3://$S3_BUCKET/$S3_PREFIX/STREAM_KEY/`
- Play: `https://$S3_BUCKET.s3.amazonaws.com/$S3_PREFIX/STREAM_KEY/index.m3u8` (or via CloudFront)

## 1) Prereqs

- EC2 with Docker + Docker Compose (`sudo yum/dnf install docker; sudo systemctl enable --now docker`)
- Security group: TCP 22 (SSH), 1935 (RTMP from your encoder IPs), 80 (optional)
- IAM role attached to instance with S3 access (Put/Get/List/Delete on your bucket)

Example inline policy (scope to your bucket):

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
      "Resource": ["arn:aws:s3:::YOUR_BUCKET", "arn:aws:s3:::YOUR_BUCKET/*"]
    }
  ]
}
```
