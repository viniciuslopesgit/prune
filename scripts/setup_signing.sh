#!/bin/zsh
# Creates a local (self-signed) certificate to sign Prune. Run it only once.
#
# Why: with ad hoc signing, each build has a new identity and macOS forgets its
# permissions (Full Disk Access, folders, Automation). With a fixed certificate, the
# app's identity stays the same between versions and the permissions are kept.
#
# Does not need an Apple Developer account and does not change the system's trust settings.
# To remove it: Keychain Access ▸ login ▸ delete "Prune Local Signing".
set -e

NAME="Prune Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
    echo "✓ The \"$NAME\" certificate already exists. Nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Uses the system's openssl (Homebrew's creates .p12 files that macOS does not import).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS" 2>/dev/null

# Imports into the login keychain, with access authorized for codesign.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "✓ Certificate \"$NAME\" created in the login keychain."

# Optional: avoids the "codesign wants to use the key…" window on the first build.
echo
echo "Optional: type your Mac login password so codesign can use the key"
echo "without asking (or press Enter to skip — then click \"Always Allow\" in the window)."
read -rs "LOGIN_PW?Password: "
echo
if [ -n "$LOGIN_PW" ]; then
    if security set-key-partition-list -S apple-tool:,apple: -s -k "$LOGIN_PW" -l "$NAME" -t private "$KEYCHAIN" >/dev/null 2>&1; then
        echo "✓ codesign can now use the key without asking."
    else
        echo "⚠️  Password not accepted — no problem, click \"Always Allow\" in the codesign window."
    fi
fi

echo
echo "Now rebuild:  ./scripts/build_app.sh   (or ./scripts/make_dmg.sh)"
echo "Then grant Full Disk Access one last time — it will be kept in the next versions."
