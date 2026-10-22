# Prune

App de macOS (SwiftUI, Swift Package, só Command Line Tools). Código, textos e commits em português de Portugal.

## Regra obrigatória do utilizador (em vigor até ordem em contrário)

1. **Sempre** correr os testes rigorosos (`./scripts/check.sh --full`, através do `ship.sh`) e **só** fazer commit se passarem.
2. **Sempre** que alterar código ou ficheiros do projeto, fazer commit automaticamente no fim, sem perguntar: `./scripts/ship.sh "Mensagem" --no-install`.

Se os testes falharem, corrigir e repetir até passarem; nunca registar código que falhe, nunca `--no-verify`. Instalar em `/Applications` (sem `--no-install`), criar DMG ou fazer push só quando o utilizador pedir. O hook Stop em `.claude/settings.json` não deixa terminar com alterações por registar.

## Testes obrigatórios

Nenhuma alteração é registada nem instalada sem passar no portão de qualidade (`scripts/check.sh`).

- **Funcionalidade nova ou alterada → testes em `Tests/PruneTests`**, no mesmo commit. Um ficheiro novo em `Sources/` sem testes novos ou alterados bloqueia o commit. `ALLOW_NO_TESTS=1` só para código puramente de interface (views).
- Testar a lógica, não a interface: o que decide o que se apaga, analisa ou calcula. Se a lógica estiver presa a uma view ou a pastas reais do utilizador, extrair para uma função que receba os caminhos/dados.
- Os testes só tocam em pastas temporárias (`TempDir`). Nunca no Lixo verdadeiro, em `~` ou em `/Applications`.
- Para cada correção de bug, um teste que falhava antes da correção.
- Os mínimos de cobertura em `scripts/check.sh` (`MIN_COVERAGE`) só sobem. Ficheiros novos que apagam ou escolhem ficheiros entram na lista.
- Nunca usar `git commit --no-verify` nem `git push --no-verify`.

## Comandos

```bash
./scripts/test.sh                        # testes de unidade (--filter ShredderTests para um grupo)
./scripts/check.sh                       # verificação rápida (o hook pre-commit corre esta)
./scripts/check.sh --full                # + versão/CHANGELOG, app universal assinada e autoteste
./scripts/ship.sh "Mensagem" [--dmg] [--push]   # verificação completa → commit → instalar
```

Depois de concluir uma funcionalidade: atualizar o CHANGELOG (e a versão em `Resources/Info.plist`, se for uma versão nova) e correr `./scripts/ship.sh "…"`. Se falhar, corrigir a causa e repetir; nunca contornar o portão. `--push` só quando o utilizador pedir.
