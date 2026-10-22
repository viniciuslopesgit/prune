#!/bin/zsh
# Cria um certificado local (auto-assinado) para assinar o Prune. Corre-se uma única vez.
#
# Porquê: com assinatura ad-hoc, cada compilação tem uma identidade nova e o macOS esquece
# as permissões (Acesso Total ao Disco, pastas, Automação). Com um certificado fixo, a
# identidade da app mantém-se entre versões e as permissões ficam.
#
# Não precisa de conta Apple Developer e não altera definições de confiança do sistema.
# Para remover: Acesso a Porta-chaves ▸ início de sessão ▸ apagar "Prune Local Signing".
set -e

NAME="Prune Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
    echo "✓ O certificado \"$NAME\" já existe. Nada a fazer."
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

# Usa o openssl do sistema (o do Homebrew gera .p12 que o macOS não importa).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS" 2>/dev/null

# Importa para o porta-chaves de início de sessão, com acesso autorizado ao codesign.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "✓ Certificado \"$NAME\" criado no porta-chaves de início de sessão."

# Opcional: evita a janela "codesign quer usar a chave…" na primeira compilação.
echo
echo "Opcional: escreva a palavra-passe da sua sessão do Mac para o codesign usar a chave"
echo "sem perguntar (ou prima Enter para saltar — nesse caso clique \"Permitir sempre\" na janela)."
read -rs "LOGIN_PW?Palavra-passe: "
echo
if [ -n "$LOGIN_PW" ]; then
    if security set-key-partition-list -S apple-tool:,apple: -s -k "$LOGIN_PW" -l "$NAME" -t private "$KEYCHAIN" >/dev/null 2>&1; then
        echo "✓ O codesign já pode usar a chave sem perguntar."
    else
        echo "⚠️  Palavra-passe não aceite — não faz mal, clique \"Permitir sempre\" na janela do codesign."
    fi
fi

echo
echo "Agora recompile:  ./scripts/build_app.sh   (ou ./scripts/make_dmg.sh)"
echo "Depois conceda o Acesso Total ao Disco uma última vez — vai manter-se nas próximas versões."
