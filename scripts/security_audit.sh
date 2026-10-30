#!/bin/zsh
# Security audit of the built app (build/Prune.app): what the binary can do and where it loads code from.
# Run by scripts/check.sh --full and by the "Tests and security" pipeline.
#
#   ./scripts/security_audit.sh [path/to/Prune.app]
set -e
cd "$(dirname "$0")/.."
APP=${1:-build/Prune.app}
BIN=$APP/Contents/MacOS/Prune
FAILED=0
fail() { print -P "%F{red}  ✗ $1%f"; FAILED=1; }
ok() { print -P "%F{green}  ✓ $1%f"; }
[ -x "$BIN" ] || { print -P "%F{red}✗ No app at $APP (run scripts/build_app.sh).%f"; exit 1; }

# 1. Signature, and no entitlements: any entitlement (e.g. get-task-allow, disable-library-validation,
#    allow-dyld-environment-variables) widens what other code can do to the app, so each needs a review.
codesign --verify --deep --strict "$APP" 2>/dev/null && ok "valid signature" || fail "invalid signature"
ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | tr -d '\0' || true)
if print -r -- "$ENT" | grep -q "<key>"; then
    fail "the app has entitlements (review each one, then update this audit): $(print -r -- "$ENT" | grep -o '<key>[^<]*' | sed 's/<key>//' | tr '\n' ' ')"
else
    ok "no entitlements"
fi

for ARCH in $(lipo -archs "$BIN"); do
    # 2. Address randomization and stack protection.
    otool -hv -arch $ARCH "$BIN" | grep -q " PIE" && ok "$ARCH: PIE (address randomization)" || fail "$ARCH: not PIE"
    nm -arch $ARCH -u "$BIN" 2>/dev/null | grep -q "___stack_chk_fail" && ok "$ARCH: stack protector" || fail "$ARCH: no stack protector"
    # 3. Code only from the system: linked libraries in /System or /usr/lib, and no rpath that points
    #    anywhere else (a writable folder in the search path lets someone plant a library).
    OTHER=$(otool -L -arch $ARCH "$BIN" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/Library/|/usr/lib/)' || true)
    [ -z "$OTHER" ] && ok "$ARCH: only system libraries" || fail "$ARCH: links outside the system: $OTHER"
    RPATHS=$(otool -arch $ARCH -l "$BIN" | awk '$1 == "path" { print $2 }' | grep -vx '/usr/lib/swift' || true)
    [ -z "$RPATHS" ] && ok "$ARCH: no rpath outside /usr/lib/swift" || fail "$ARCH: rpath outside the system: $RPATHS"
done

# 4. Network: no App Transport Security exceptions, no cleartext http:// endpoints in the binary.
PLIST=$APP/Contents/Info.plist
if /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity" "$PLIST" >/dev/null 2>&1; then
    fail "Info.plist has App Transport Security exceptions"
else
    ok "no App Transport Security exceptions"
fi
HTTP=$(strings -a "$BIN" | grep -oE 'http://[A-Za-z0-9.-]+[A-Za-z0-9/._-]*' | grep -vE '^http://(www\.)?(apple\.com/DTDs|www\.andymatuschak\.org/xml-namespaces)' | sort -u || true)
[ -z "$HTTP" ] && ok "no cleartext http:// endpoints" || fail "cleartext http:// endpoints in the binary: $HTTP"

# 5. No key material or tokens in the binary or the bundle (the analytics key is an accepted exception, R8).
if strings -a "$BIN" | grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}'; then
    fail "the binary contains a private key or a token"
else
    ok "no private keys or tokens in the binary"
fi

# 6. Nothing in the bundle that other users could change.
WRITABLE=$(find "$APP" -perm -o+w ! -type l 2>/dev/null || true)
[ -z "$WRITABLE" ] && ok "no world-writable files in the bundle" || fail "world-writable: $WRITABLE"

[ $FAILED = 0 ] || { print -P "%F{red}✗ Security audit failed.%f"; exit 1; }
print -P "%F{green}✓ Security audit passed.%f"
