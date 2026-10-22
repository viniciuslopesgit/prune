# Prune

App de macOS (SwiftUI, Swift Package, só Command Line Tools). Código, textos e commits em português de Portugal.

## Regra obrigatória do utilizador (em vigor até ordem em contrário)

Sempre que alterar código ou ficheiros do projeto, no fim e sem perguntar:

1. Subir a versão consoante a alteração: `./scripts/bump_version.sh patch` (correções, alterações internas), `minor` (funcionalidade nova) ou `major` (mudança incompatível).
2. Preencher a secção da versão no `CHANGELOG.md`: um parágrafo de resumo (vai para o topo da Release) e as listas `### Adicionado / Alterado / Corrigido / Removido`, escritas para quem usa a app.
3. `./scripts/ship.sh "Mensagem (X.Y.Z)"`: testes rigorosos → commit **só se passarem** → push para o **dev** → Release `vX.Y.Z` no GitHub com o DMG.

Se os testes falharem, corrigir e repetir até passarem; nunca registar código que falhe, nunca `--no-verify`. Nunca fazer push para o `main`: o `main` só recebe a versão estável, por `./scripts/stable.sh --apply` (o hook pre-push recusa o resto), e só quando o utilizador pedir. Instalar em `/Applications` (`--install`) só quando o utilizador pedir. O hook Stop em `.claude/settings.json` não deixa terminar com alterações por registar ou commits por enviar.

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
./scripts/bump_version.sh patch|minor|major     # versão nova + secção no CHANGELOG
./scripts/ship.sh "Mensagem (X.Y.Z)"            # testes → commit → push dev → Release
./scripts/stable.sh [--apply | --check X.Y.Z]   # versão estável para o main (regras em scripts/stable.py)
```

Versão estável = a Release mais recente com DMG, no histórico do dev, sem issues abertas de `bug` que a mencionem, publicada há ≥ 24 h (`STABLE_SOAK_HOURS`) e sem correções (`### Corrigido`) em versões publicadas depois. Testes das regras em `scripts/tests` (corridos pelo `check.sh`).
