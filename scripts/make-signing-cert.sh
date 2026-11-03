#!/bin/bash
# One-time: creates a self-signed code-signing identity "Hangover Self-Signed" in your login keychain.
# Signing every release with the same identity lets macOS keep a user's folder permissions across updates.
# The private key stays in your keychain; nothing is written into the repo. macOS may ask for your password.
set -euo pipefail
NAME="Hangover Self-Signed"
if security find-identity -p codesigning ${HANGOVER_KEYCHAIN:+"$HANGOVER_KEYCHAIN"} 2>/dev/null | grep -q "$NAME"; then
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
# macOS can only read PKCS12 files protected with the older SHA1/3DES algorithms (OpenSSL 3 defaults to AES).
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security import "$TMP/id.p12" -k "${HANGOVER_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}" -P "$PASS" -T /usr/bin/codesign
echo "Created '$NAME'. Builds from scripts/build.sh will now be signed with it."
