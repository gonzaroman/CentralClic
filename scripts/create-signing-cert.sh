#!/bin/bash
# Creates a self-signed "CentralClic Local" code signing certificate in the login keychain.
# With it, every build of CentralClic keeps the same identity, so macOS doesn't forget the Accessibility permission.
# Keep a backup (Keychain Access → My Certificates → "CentralClic Local" → Export): releases signed with it let
# users keep the permission when they update.
# To delete it: Keychain Access → login → My Certificates → "CentralClic Local" → Delete.
set -euo pipefail
NAME="CentralClic Local"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "The \"${NAME}\" certificate already exists."
  exit 0
fi
# Uses the system openssl and classic PKCS12 encryption: the macOS keychain can't read the OpenSSL 3 format.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$TMP/id.p12" -passout pass:centralclic
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P centralclic -T /usr/bin/codesign
echo "✓ Created the \"${NAME}\" certificate. Run ./build.sh again."
