#!/usr/bin/env bash
#
# ios-safe-deploy.sh — deploy Memex to a physical iPhone WITHOUT ever risking
# on-device data.
#
# Why this exists
# ---------------
# On a free-provisioned personal build (bundle id com.example.memex), iOS gives
# the app NO storage that survives an uninstall, and iCloud entitlements are not
# granted (the NSUbiquitousContainers id in Info.plist belongs to the App Store
# bundle, not this one). So the ONLY safe way to deploy is:
#   1. Pull a full copy of the app data container OFF the device first.
#   2. Install WITHOUT uninstalling (incremental `flutter run`, never
#      `flutter install`, which prints "Uninstalling old version..." and wipes
#      the sandbox — this is exactly what destroyed the user's cards once).
#
# If the backup step fails, we ABORT and do not deploy.
#
# Usage:
#   scripts/ios-safe-deploy.sh [--release|--debug] [device-id]
#
# Defaults: --release, device YOUR_DEVICE_ID (your iPhone).

set -euo pipefail

MODE="--release"
DEVICE="YOUR_DEVICE_ID"
BUNDLE_ID="com.example.memex"
BACKUP_ROOT="${HOME}/memex-backups"

for arg in "$@"; do
  case "$arg" in
    --release) MODE="--release" ;;
    --debug)   MODE="--debug" ;;
    *)         DEVICE="$arg" ;;
  esac
done

STAMP="$(date +%Y-%m-%d_%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"

echo "==> [1/3] Backing up on-device app data BEFORE touching the install"
echo "    device:   ${DEVICE}"
echo "    bundle:   ${BUNDLE_ID}"
echo "    dest:     ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# Pull the whole app data container off the device (read-only copy).
if ! xcrun devicectl device copy from \
      --device "${DEVICE}" \
      --domain-type appDataContainer \
      --domain-identifier "${BUNDLE_ID}" \
      --source Documents \
      --destination "${BACKUP_DIR}" 2>"${BACKUP_DIR}/.copy.log"; then
  echo "!!  Backup pull FAILED — see ${BACKUP_DIR}/.copy.log"
  echo "!!  ABORTING deploy. Nothing on the device was changed."
  echo "!!  (Common cause: device locked/disconnected. Unlock, reconnect, retry.)"
  exit 1
fi

# Sanity check: refuse to proceed if the backup looks empty.
FILE_COUNT="$(find "${BACKUP_DIR}" -type f ! -name '.copy.log' | wc -l | tr -d ' ')"
echo "    backed up ${FILE_COUNT} file(s)"
if [ "${FILE_COUNT}" -eq 0 ]; then
  echo "!!  Backup is EMPTY — refusing to deploy over possibly-live data."
  echo "!!  If the app truly has no data yet, deploy manually with:"
  echo "!!    flutter run ${MODE} -d ${DEVICE}"
  exit 1
fi

echo "==> [2/3] Deploying WITHOUT uninstall (flutter run, incremental)"
echo "    NEVER use 'flutter install' here — it uninstalls and wipes data."
flutter run "${MODE}" -d "${DEVICE}"

echo "==> [3/3] Done. Safety backup kept at: ${BACKUP_DIR}"
