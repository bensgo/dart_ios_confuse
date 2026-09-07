#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$tool_root"

fvm dart format --output=none --set-exit-if-changed lib bin test
fvm dart analyze
fvm dart test

if [[ -z "${RELEASE_FIXTURE_ROOT:-}" ]]; then
  echo "Unit gate passed; RELEASE_FIXTURE_ROOT is unset, so the private Release fixture is skipped."
  exit 0
fi
if [[ -z "${RELEASE_TARGETS:-}" ]]; then
  echo "RELEASE_TARGETS is required when RELEASE_FIXTURE_ROOT is set." >&2
  exit 64
fi

for profile in product_alpha product_beta; do
  profile_path="config/${profile}_profile.yaml"
  if [[ ! -f "$RELEASE_FIXTURE_ROOT/$profile_path" ]]; then
    echo "Missing profile: $RELEASE_FIXTURE_ROOT/$profile_path" >&2
    exit 66
  fi
  fvm dart run bin/dart_prefix_renamer.dart \
    --transactional-build \
    --project="$RELEASE_FIXTURE_ROOT" \
    --target="$RELEASE_TARGETS" \
    --prefix="${profile#product_}" \
    --capabilities \
    --product-profile="$profile_path" \
    --artifact-dir=build/ios/archive \
    --artifact-dir=reports \
    -- fvm flutter build ipa --release --no-codesign
done
