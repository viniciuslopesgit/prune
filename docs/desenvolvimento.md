# Testes e publicação

Nada é registado nem instalado sem passar nos testes.

```bash
./scripts/setup_hooks.sh               # uma vez: liga os hooks do git
./scripts/test.sh                      # testes de unidade (Tests/PruneTests)
./scripts/check.sh                     # verificação rápida
./scripts/check.sh --full              # verificação completa
./scripts/bump_version.sh patch        # versão nova (patch, minor ou major) e secção no CHANGELOG
./scripts/ship.sh "Mensagem do commit" # verificação completa → commit → push dev → Release
```

- **Verificação rápida** (antes de cada commit, pelo hook `pre-commit`): sintaxe dos scripts, nenhuma chave de `analytics.env` nas alterações, ficheiros novos em `Sources/` acompanhados de testes, compilação sem avisos, testes de unidade e cobertura mínima nos ficheiros que apagam ou escolhem ficheiros.
- **Verificação completa** (antes de cada push, pelo hook `pre-push`, e no `ship.sh`): tudo o anterior, secção da versão preenchida no CHANGELOG, app universal e assinada, e o autoteste da app compilada.
- `./scripts/stable.sh` diz qual a versão estável que deve estar no `main`: a Release mais recente com o DMG, sem issues abertas de `bug` que a mencionem, publicada há pelo menos 24 h e sem correções em versões posteriores. `--apply` verifica-a de novo numa cópia limpa e promove-a para o `main` por Pull Request; `--check X.Y.Z` só verifica.
- `ship.sh` publica a Release `vX.Y.Z` com o DMG e as notas tiradas do CHANGELOG e, no fim, promove a versão estável para o `main` (`stable.sh --apply`), se houver uma mais nova. Aceita `--install` (instala em /Applications), `--no-release` e `--no-promote`.

## O que vai para o main

O `main` tem só o necessário para compilar e distribuir a versão estável: sem testes, hooks nem scripts de publicação. A lista do que fica de fora está em [`.mainignore`](../.mainignore). Cada versão estável chega ao `main` como um único commit "Prune X.Y.Z (versão estável)", com o conteúdo da tag `vX.Y.Z` sem esses ficheiros, por Pull Request.

