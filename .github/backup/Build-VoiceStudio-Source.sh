#!/usr/bin/env bash
set -euo pipefail
UPSTREAM_REPO="debpalash/VoiceStudio"
UPSTREAM_URL="https://github.com/debpalash/VoiceStudio.git"
UPSTREAM_MAIN_SHA="d819ff54d93017bf4a5b34b605833162163c9e3c"
STABLE_TAG="v0.5.6"
STABLE_COMMIT="3915a62cb482bb43117aaebab57d22745bd1cc21"
BACKUP_DATE="20261019"
ROOT="${RUNNER_TEMP}/voicestudio-source-backup"
OUT="${GITHUB_WORKSPACE}/backup-output-source"
rm -rf "$ROOT" "$OUT"
mkdir -p "$ROOT" "$OUT"

git clone --mirror "$UPSTREAM_URL" "$ROOT/VoiceStudio.git"
git -C "$ROOT/VoiceStudio.git" lfs install --local
git -C "$ROOT/VoiceStudio.git" lfs fetch --all
OBSERVED_MAIN="$(git -C "$ROOT/VoiceStudio.git" rev-parse refs/heads/main)"
OBSERVED_STABLE="$(git -C "$ROOT/VoiceStudio.git" rev-parse "$STABLE_TAG^{}")"
test "$OBSERVED_MAIN" = "$UPSTREAM_MAIN_SHA"
test "$OBSERVED_STABLE" = "$STABLE_COMMIT"

GALLERY_PATH="omnivoice-gallery"
GALLERY_URL="$(git -C "$ROOT/VoiceStudio.git" show "$UPSTREAM_MAIN_SHA:.gitmodules" | git config -f /dev/stdin --get submodule.omnivoice-gallery.url)"
MAIN_GALLERY_SHA="$(git -C "$ROOT/VoiceStudio.git" ls-tree "$UPSTREAM_MAIN_SHA" "$GALLERY_PATH" | awk '{print $3}')"
STABLE_GALLERY_SHA="$(git -C "$ROOT/VoiceStudio.git" ls-tree "$STABLE_COMMIT" "$GALLERY_PATH" | awk '{print $3}')"
git clone --mirror "$GALLERY_URL" "$ROOT/omnivoice-gallery.git"
git -C "$ROOT/omnivoice-gallery.git" lfs install --local
git -C "$ROOT/omnivoice-gallery.git" lfs fetch --all || true
git -C "$ROOT/omnivoice-gallery.git" cat-file -e "$MAIN_GALLERY_SHA^{commit}"
git -C "$ROOT/omnivoice-gallery.git" cat-file -e "$STABLE_GALLERY_SHA^{commit}"

cat > "$ROOT/BACKUP_METADATA.json" <<JSON
{
  "schemaVersion": 1,
  "date": "2026-10-19",
  "upstream": "$UPSTREAM_REPO",
  "currentMain": {"versionDeclared": "0.5.7", "commit": "$UPSTREAM_MAIN_SHA"},
  "latestStable": {"tag": "$STABLE_TAG", "commit": "$STABLE_COMMIT", "published": "2026-09-23"},
  "submodule": {"path": "$GALLERY_PATH", "url": "$GALLERY_URL", "mainCommit": "$MAIN_GALLERY_SHA", "stableCommit": "$STABLE_GALLERY_SHA"},
  "gitLfsFetchedAll": true
}
JSON

mkdir -p "$ROOT/snapshots" "$ROOT/manifests"
git -C "$ROOT/VoiceStudio.git" archive --format=tar.gz --prefix="VoiceStudio-main-$UPSTREAM_MAIN_SHA/" "$UPSTREAM_MAIN_SHA" > "$ROOT/snapshots/VoiceStudio-main-$UPSTREAM_MAIN_SHA.tar.gz"
git -C "$ROOT/VoiceStudio.git" archive --format=tar.gz --prefix="VoiceStudio-v0.5.6/" "$STABLE_COMMIT" > "$ROOT/snapshots/VoiceStudio-v0.5.6.tar.gz"
git -C "$ROOT/omnivoice-gallery.git" archive --format=tar.gz --prefix="omnivoice-gallery-main-$MAIN_GALLERY_SHA/" "$MAIN_GALLERY_SHA" > "$ROOT/snapshots/omnivoice-gallery-main-$MAIN_GALLERY_SHA.tar.gz"

for spec in "package.json" "bun.lock" "pyproject.toml" "uv.lock" "backend/config/models.yaml" "backend/config/model_licenses.json" "docs/licensing/model-license-data.json" "scripts/install.ps1" "scripts/install.sh"; do
  safe="$(echo "$spec" | tr '/' '_')"
  git -C "$ROOT/VoiceStudio.git" show "$UPSTREAM_MAIN_SHA:$spec" > "$ROOT/manifests/$safe"
done

cat > "$ROOT/README-BACKUP.txt" <<'EOF'
VoiceStudio source preservation bundle.
Contains the complete upstream Git mirror, fetched LFS objects, complete omnivoice-gallery submodule mirror, pinned current main and stable v0.5.6 identities, source snapshots, and rebuild/model manifests.
The Git mirrors are authoritative. Model weights and external package registries are not contained in this source archive.
EOF

tar -C "$ROOT" -czf "$OUT/VoiceStudio-Source-Mirror-$BACKUP_DATE.tar.gz" VoiceStudio.git omnivoice-gallery.git BACKUP_METADATA.json README-BACKUP.txt manifests snapshots
sha256sum "$OUT/VoiceStudio-Source-Mirror-$BACKUP_DATE.tar.gz" > "$OUT/VoiceStudio-Source-Mirror-$BACKUP_DATE.tar.gz.sha256"
cp "$ROOT/BACKUP_METADATA.json" "$OUT/SOURCE_BACKUP_METADATA.json"
