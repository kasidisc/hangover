#!/bin/bash
# One-time: creates a self-signed code-signing identity "Hangover Self-Signed" in your login keychain.
# Signing every release with the same identity lets macOS keep a user's folder permissions across updates.
# The private key stays in your keychain; nothing is written into the repo. macOS may ask for your password.
set -euo pipefail
NAME="Hangover Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "'$NAME' already exists in your keychain."; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS" 2>/dev/null
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Created '$NAME'. Builds from scripts/build.sh will now be signed with it."
