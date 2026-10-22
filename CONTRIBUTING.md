# Contribuir

Obrigado pelo interesse. O Prune apaga ficheiros, por isso a prioridade é que nunca apague o que não deve. Antes de velocidade ou funcionalidades novas.

## Ramos

- **`dev`**: onde se trabalha. Os Pull Requests vão para aqui.
- **`main`**: só a versão estável, com o necessário para a compilar. Atualizado automaticamente; não aceita Pull Requests diretos.

## Preparar

Requer macOS 14 ou mais recente e as Command Line Tools do Xcode (`xcode-select --install`), ou o Xcode.

```bash
git clone -b dev https://github.com/viniciuslopesgit/prune.git
cd prune
./scripts/setup_hooks.sh   # verificação antes de cada commit e de cada push
./scripts/test.sh          # testes de unidade
./scripts/check.sh         # verificação rápida (a mesma do hook pre-commit)
```

## Regras para alterações

1. **Testes no mesmo Pull Request.** Funcionalidade nova ou alterada traz testes em `Tests/PruneTests`. Uma correção traz um teste que falhava antes dela. Um ficheiro novo em `Sources/` sem testes bloqueia o commit.
2. **Tudo o que apaga passa pelo `SafetyGuard.canDelete`.** Nunca chamar `FileManager.removeItem`, `trashItem` ou `rm` diretamente sobre caminhos que não passaram por lá.
3. **Testar operações destrutivas só em pastas descartáveis** (`TempDir` nos testes). Nunca no seu `~`, no Lixo verdadeiro ou em `/Applications`.
4. **Verificar o que não pode mudar**, além do que muda: o destino de uma ligação continua intacto, uma pasta protegida continua lá.
5. **Ações destrutivas ou com privilégios pedem confirmação** e mostram o que vai acontecer.
6. **Sem dependências novas** sem discutir primeiro numa issue (licença compatível com GPL-3.0, manutenção, necessidade real).
7. **Privacidade:** nada sai do Mac sem consentimento; a telemetria nunca inclui caminhos, nomes de ficheiros ou de apps.
8. **Código, textos, commits e CHANGELOG em português de Portugal.**

O CI corre `./scripts/check.sh --full` em macOS 14 e 15 em cada Pull Request para o `dev`, e tem de passar.

## Reportar erros

Abra uma issue com a versão do Prune e do macOS, Apple silicon ou Intel, os passos para reproduzir, e o que esperava. Erros que podem apagar dados recebem a etiqueta `bug` e bloqueiam a promoção da versão a estável.

Vulnerabilidades: **não** use issues públicas, veja [SECURITY.md](SECURITY.md).

## Publicação

O maintainer publica com `./scripts/ship.sh` (beta) e o `./scripts/stable.sh` promove para o `main` quando os [critérios de lançamento](https://github.com/viniciuslopesgit/prune/blob/dev/docs/RELEASE_CRITERIA.md) são cumpridos.
