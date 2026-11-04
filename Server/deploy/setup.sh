#!/bin/bash
# One-time setup of the dev server on Google Cloud (project benostudio-heistroyale, us-central1).
# Creates: the Cloud Build and Artifact Registry APIs, an image repository, a network of its own whose
# firewall opens only TCP 80 and 443, a static IP, the first image, and a free-tier e2-micro VM
# (Container-Optimized OS) that runs the server behind Caddy. Later updates: deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."

REGION=us-central1
ZONE=us-central1-a

gcloud services enable cloudbuild.googleapis.com artifactregistry.googleapis.com

gcloud artifacts repositories create heist --repository-format=docker --location=$REGION \
  --description="Heist Royale server images"
# Keep the two newest images; the free tier stores 0.5 GB.
policy=$(mktemp)
cat > "$policy" <<'JSON'
[
  {"name": "keep-two-newest", "action": {"type": "Keep"}, "mostRecentVersions": {"keepCount": 2}},
  {"name": "delete-older", "action": {"type": "Delete"}, "condition": {"tagState": "any", "olderThan": "1d"}}
]
JSON
gcloud artifacts repositories set-cleanup-policies heist --location=$REGION --policy="$policy" --no-dry-run
rm "$policy"

gcloud compute networks create heist-net --subnet-mode=custom
gcloud compute networks subnets create heist-$REGION --network=heist-net --region=$REGION --range=10.20.0.0/24
gcloud compute firewall-rules create heist-allow-web --network=heist-net --direction=INGRESS \
  --allow=tcp:80,tcp:443 --source-ranges=0.0.0.0/0 --target-tags=heist-server

gcloud compute addresses create heist-dev-ip --region=$REGION
ip=$(gcloud compute addresses describe heist-dev-ip --region=$REGION --format='value(address)')
host="${ip//./-}.sslip.io"

gcloud builds submit --config=Server/deploy/cloudbuild.yaml --ignore-file=Server/deploy/gcloudignore .

gcloud compute instances create heist-dev --zone=$ZONE --machine-type=e2-micro \
  --subnet=heist-$REGION --address=heist-dev-ip --tags=heist-server \
  --image-family=cos-stable --image-project=cos-cloud \
  --boot-disk-size=20GB --boot-disk-type=pd-standard \
  --metadata=heist-host=$host,google-logging-enabled=true \
  --metadata-from-file=user-data=Server/deploy/cloud-init.yaml,caddyfile=Server/deploy/Caddyfile

echo "Server: https://$host (health: https://$host/health, WebSocket: wss://$host/ws)"
