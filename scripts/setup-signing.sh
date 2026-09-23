#!/bin/zsh
set -euo pipefail
umask 077
signing_dir="$HOME/Library/Application Support/MacBar/Signing"
if [[ -f "$signing_dir/identity.sha1" ]]; then
  print 'Existing identity preserved. No new key created.'
  exit 0
fi
mkdir -p "$signing_dir"
signing_tmp=$(mktemp -d)
trap 'rm -rf "$signing_tmp"' EXIT
openssl req -new -newkey rsa:3072 -x509 -sha256 -days 3650 -noenc \
  -subj '/CN=MacBar Local Code Signing/O=MacBar Local Development/' \
  -addext 'basicConstraints=critical,CA:FALSE' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=critical,codeSigning' \
  -keyout "$signing_tmp/key.pem" -out "$signing_tmp/certificate.pem" 2>"$signing_tmp/generation.log"
signing_password=$(openssl rand -hex 24)
/usr/bin/openssl pkcs12 -export -inkey "$signing_tmp/key.pem" \
  -in "$signing_tmp/certificate.pem" -name 'MacBar Local Code Signing' \
  -passout "pass:$signing_password" -out "$signing_tmp/identity.p12"
security import "$signing_tmp/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -f pkcs12 -P "$signing_password" -x -T /usr/bin/codesign
openssl x509 -in "$signing_tmp/certificate.pem" -outform DER -out "$signing_dir/certificate.der"
openssl x509 -in "$signing_tmp/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' > "$signing_dir/identity.sha1"
print 'MacBar certificate created; private key imported into the login keychain.'
