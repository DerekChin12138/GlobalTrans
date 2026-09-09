#!/bin/zsh
set -euo pipefail
# Creates (once) a local code-signing identity so Screen Recording TCC can stick
# across rebuilds. Ad-hoc signatures change cdhash every build; macOS 15+ then
# treats each rebuild as a new app and keeps asking.

CERT_NAME="GlobalTrans Local Signer"
EXISTING="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' "/$CERT_NAME/ {print \$2; exit}")"
if [[ -n "${EXISTING:-}" ]]; then
  printf '%s\n' "$EXISTING"
  exit 0
fi

APPLE="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application|Mac Developer/ {print $2; exit}')"
if [[ -n "${APPLE:-}" ]]; then
  printf '%s\n' "$APPLE"
  exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
KEY="$WORKDIR/gt.key"
CRT="$WORKDIR/gt.crt"
P12="$WORKDIR/gt.p12"

openssl genrsa -out "$KEY" 2048 >/dev/null 2>&1
openssl req -new -x509 -key "$KEY" -out "$CRT" -days 3650 \
  -subj "/CN=${CERT_NAME}/O=GlobalTrans" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "keyUsage=digitalSignature"
openssl pkcs12 -export -inkey "$KEY" -in "$CRT" -out "$P12" \
  -passout pass:globaltrans -name "$CERT_NAME"

security import "$P12" -k ~/Library/Keychains/login.keychain-db -P globaltrans \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" \
  ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true

CREATED="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' "/$CERT_NAME/ {print \$2; exit}")"
if [[ -z "${CREATED:-}" ]]; then
  echo "error: local signer was imported but is not trusted for code signing" >&2
  echo "add a free Apple ID in Xcode → Settings → Accounts, or trust '$CERT_NAME' in Keychain Access." >&2
  exit 1
fi
printf '%s\n' "$CREATED"
