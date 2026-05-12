#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   GCP_PROJECT       — your GCP project id
#   APNS_KEY_SECRET   — Secret Manager secret name that holds the APNs .p8
#   APNS_KEY_ID       — 10-char key id
#   APNS_TEAM_ID      — 10-char team id
#   APNS_BUNDLE_ID    — default com.sshido.app
#   APNS_PRODUCTION   — "true" for App Store/TestFlight, "false" otherwise
#   REGION            — default us-central1
#   SERVICE           — default sshido-relay
#
# Optional public-facing config:
#   PRIVACY_CONTACT   — email surfaced on /privacy and the landing footer
#                       (default privacy@sshido.com)
#   UPSTREAM_REPO_URL — URL /self-host redirects to (default: empty → /).
#                       Upstream sets this to the canonical repo tree URL;
#                       forks set their own or leave blank.
#
# One-time setup:
#   gcloud auth login
#   gcloud config set project "$GCP_PROJECT"
#   gcloud services enable run.googleapis.com firestore.googleapis.com secretmanager.googleapis.com artifactregistry.googleapis.com
#   gcloud firestore databases create --location="$REGION"
#   gcloud secrets create sshido-apns-key --data-file=~/AuthKey_XXXXXXXXXX.p8

: "${GCP_PROJECT:?set GCP_PROJECT}"
: "${APNS_KEY_SECRET:=sshido-apns-key}"
: "${APNS_KEY_ID:?set APNS_KEY_ID}"
: "${APNS_TEAM_ID:?set APNS_TEAM_ID}"
: "${APNS_BUNDLE_ID:=com.sshido.app}"
: "${APNS_PRODUCTION:=true}"
: "${REGION:=us-central1}"
: "${SERVICE:=sshido-relay}"
: "${PRIVACY_CONTACT:=privacy@sshido.com}"
: "${UPSTREAM_REPO_URL:=}"

IMAGE="$REGION-docker.pkg.dev/$GCP_PROJECT/sshido/$SERVICE:latest"

echo "▶ Building & pushing image $IMAGE..."
gcloud builds submit --tag "$IMAGE" .

echo "▶ Deploying to Cloud Run..."
gcloud run deploy "$SERVICE" \
  --image "$IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --concurrency 80 \
  --cpu 1 --memory 256Mi \
  --min-instances 0 --max-instances 3 \
  --set-env-vars "STORAGE=firestore,GOOGLE_CLOUD_PROJECT=$GCP_PROJECT,APNS_KEY_ID=$APNS_KEY_ID,APNS_TEAM_ID=$APNS_TEAM_ID,APNS_BUNDLE_ID=$APNS_BUNDLE_ID,APNS_PRODUCTION=$APNS_PRODUCTION,APNS_KEY_PATH=/secrets/apns.p8,PRIVACY_CONTACT=$PRIVACY_CONTACT,UPSTREAM_REPO_URL=$UPSTREAM_REPO_URL" \
  --set-secrets "/secrets/apns.p8=$APNS_KEY_SECRET:latest"

URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')
echo
echo "✅ Deployed: $URL"
echo
echo "Setting PUBLIC_URL to $URL and redeploying..."
gcloud run services update "$SERVICE" --region "$REGION" \
  --update-env-vars "PUBLIC_URL=$URL"
echo "Done. Health check: curl $URL/health"
