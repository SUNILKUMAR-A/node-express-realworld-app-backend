#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${MIGRATION_ARTIFACT_BUCKET:?Set MIGRATION_ARTIFACT_BUCKET to the private artifacts bucket name}"

if [[ ! -x "$repo_root/node_modules/.bin/prisma" ]]; then
  echo "Prisma CLI is missing; run npm ci and npx prisma generate first." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/artifact/src/prisma" "$work_dir/artifact/scripts"
cp "$repo_root/package.json" "$repo_root/package-lock.json" "$work_dir/artifact/"
cp -a "$repo_root/node_modules" "$work_dir/artifact/"
cp "$repo_root/src/prisma/schema.prisma" "$work_dir/artifact/src/prisma/"
cp -a "$repo_root/src/prisma/migrations" "$work_dir/artifact/src/prisma/"
cp "$repo_root/scripts/provision-app-db-user.js" "$work_dir/artifact/scripts/"
cp "$repo_root/infra/migration/buildspec-migrate.yml" "$work_dir/artifact/"

archive="$work_dir/migration-artifact.zip"
(
  cd "$work_dir/artifact"
  zip -qr "$archive" .
)

aws s3 cp "$archive" "s3://${MIGRATION_ARTIFACT_BUCKET}/migration/migration-artifact.zip"
echo "Uploaded migration source artifact to the configured private S3 bucket."
