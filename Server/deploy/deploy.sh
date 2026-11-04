#!/bin/bash
# Ships the current Server/ and HeistCore/ to the dev VM: builds the image on Cloud Build (about 10 min),
# then stops and starts the VM so it pulls the new image (about 2 min offline; live matches are lost).
# Pass --config-only to skip the build and just push edited cloud-init.yaml or Caddyfile before the restart.
set -euo pipefail
cd "$(dirname "$0")/../.."

ZONE=us-central1-a

if [[ "${1:-}" != "--config-only" ]]; then
  gcloud builds submit --config=Server/deploy/cloudbuild.yaml --ignore-file=Server/deploy/gcloudignore .
fi
gcloud compute instances add-metadata heist-dev --zone=$ZONE \
  --metadata-from-file=user-data=Server/deploy/cloud-init.yaml,caddyfile=Server/deploy/Caddyfile
gcloud compute instances stop heist-dev --zone=$ZONE
gcloud compute instances start heist-dev --zone=$ZONE

ip=$(gcloud compute addresses describe heist-dev-ip --region=us-central1 --format='value(address)')
host="${ip//./-}.sslip.io"
echo "Waiting for https://$host/health"
for _ in $(seq 60); do
  if [[ "$(curl -sf "https://$host/health")" == ok ]]; then echo ok; exit 0; fi
  sleep 5
done
echo "No answer after 5 min; logs: gcloud logging read 'resource.type=gce_instance' --limit=50" >&2
exit 1
