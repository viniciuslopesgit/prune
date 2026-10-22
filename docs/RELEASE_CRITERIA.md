# Critérios de lançamento e estabilidade

Uma versão do Prune só é **estável** quando há evidência verificável disso. Compilar, passar nos testes ou funcionar no Mac de quem a fez não chega: o Prune apaga ficheiros, e um erro pode custar dados a quem o usa.

Este documento define os estados de uma versão, o que é preciso para passar de um ao seguinte, como se mede e quem decide. As regras automáticas estão em [`scripts/stable.py`](../scripts/stable.py) (com testes em `scripts/tests`) e a verificação em [`scripts/check.sh`](../scripts/check.sh). Os riscos conhecidos estão no [registo de riscos](RISK_REGISTER.md).

## 1. Quatro coisas diferentes

| Afirmação | O que prova | O que **não** prova |
|---|---|---|
| Os testes passam | O comportamento testado está como esperado nas máquinas onde correram | Que não há erros; o que não está testado (ex.: as regras de cada análise) |
| Funcionalmente correto | Cada funcionalidade faz o que promete, incluindo casos-limite e erros | Que funciona noutros macOS, com outras permissões ou a longo prazo |
| Operacionalmente fiável | Funciona em várias máquinas e versões, recupera de falhas, sem fugas de memória | Que é seguro para quem não sabe o que está a apagar |
| Seguro para o público | Nada é apagado sem consentimento, nada crítico pode ser apagado, falhas não deixam o sistema em mau estado | Ausência total de defeitos |

## 2. Estados de uma versão

| Estado | Onde está | Como se chega lá | Quem decide |
|---|---|---|---|
| **Alfa** | Commits no `dev` sem tag; builds locais | Verificação rápida no pre-commit | Quem faz o commit |
| **Beta** | Release no GitHub marcada como pré-lançamento, com DMG e `SHA256SUMS` | `scripts/ship.sh`: verificação completa local → commit → push `dev` → tag `vX.Y.Z` | Automático |
| **Candidata (RC)** | A beta que o `stable.sh` aponta como candidata | Todos os critérios automáticos da secção 4 cumpridos | Automático |
| **Estável** | Commit "Prune X.Y.Z (versão estável)" no `main`; Release marcada como **Latest** | `scripts/stable.sh --apply`: nova verificação completa numa cópia limpa da tag, compilação e autoteste do conteúdo do `main`, Pull Request com merge | Automático para patch e minor; **aprovação humana** para major |

O link "Descarregar a última versão" do README aponta para a **Latest**, que é sempre a última estável. As betas só aparecem a quem as procura.

### Tipos de versão (SemVer)

| Tipo | Quando | Exige |
|---|---|---|
| Patch `X.Y.Z+1` | Correções e alterações internas, sem funcionalidade nova | Critérios automáticos |
| Minor `X.Y+1.0` | Funcionalidade nova compatível | Critérios automáticos + testes da funcionalidade nova no mesmo commit |
| Major `X+1.0.0` | Mudança incompatível (definições, comportamento por omissão ao apagar, requisitos do sistema) | Critérios automáticos + `STABLE_APPROVE=X.Y.Z` + decisão registada no Pull Request |

## 3. Portões de qualidade

**B** = bloqueia, **A** = só aviso. Coluna "Evidência": o que fica guardado para justificar a decisão.

### 3.1 A cada commit (`check.sh`, hook pre-commit)

| # | Verificação | Tipo | Evidência |
|---|---|---|---|
| Q1 | Sintaxe e permissão de execução de todos os scripts e hooks | B | Saída do check |
| Q2 | Testes dos scripts de publicação (`scripts/tests`) | B | Saída do check |
| Q3 | Nenhuma chave de `analytics.env` nas alterações; nenhum ficheiro ignorado registado | B | Saída do check |
| Q4 | Ficheiro novo em `Sources/` exige testes novos ou alterados | B | Saída do check |
| Q5 | Compilação sem avisos (`-warnings-as-errors`) | B | `.build/check-build-debug.log` |
| Q6 | Testes de unidade, 100% a passar, em série | B | `.build/check-tests.log` |
| Q7 | Cobertura mínima de linhas nos ficheiros que apagam ou escolhem o que se apaga (`MIN_COVERAGE`) | B | Relatório `llvm-cov` |

### 3.2 Antes de cada beta (`check.sh --full`, `ship.sh`, hook pre-push)

| # | Verificação | Tipo | Evidência |
|---|---|---|---|
| R1 | Tudo da secção 3.1 | B | — |
| R2 | Versão `X.Y.Z` no `Info.plist`, com secção preenchida no CHANGELOG | B | CHANGELOG |
| R3 | App universal (arm64 + x86_64), assinada, versão certa | B | `lipo`, `codesign --verify` |
| R4 | Autoteste da app compilada: todas as análises correm só em leitura e 6 verificações dão o resultado esperado | B | `.build/check-selftest.log` |
| R5 | O que é testado é exatamente o que é enviado (comparação de árvores git) | B | `.build/check-passed` |
| R6 | DMG e `SHA256SUMS` anexados à Release | B | Release no GitHub |

### 3.3 Antes de estável (`stable.py`, `stable.sh`)

| # | Critério | Tipo | Porquê este limite |
|---|---|---|---|
| S1 | Release publicada, com DMG e `SHA256SUMS` | B | Quem descarrega tem de poder verificar o ficheiro |
| S2 | Tag no histórico do `dev`, com `.mainignore` | B | O `main` só compila a partir da 1.2.9 |
| S3 | **CI verde no commit da tag** em macOS 14 e 15 | B | É a única evidência de compatibilidade fora da máquina de quem publica |
| S4 | Nenhuma issue aberta com a etiqueta `bug` que mencione a versão | B | Para uma app que apaga ficheiros, um erro reportado e não resolvido bloqueia. Quem quiser um erro menor sem bloquear não lhe dá a etiqueta `bug` e explica porquê na issue |
| S5 | Nenhuma versão publicada depois traz `### Corrigido` | B | Se houve correção, a versão anterior tinha um defeito conhecido |
| S6 | Publicada há pelo menos 24 h (`STABLE_SOAK_HOURS`) | B | É um tempo de espera, **não prova de fiabilidade**: com poucos utilizadores, 24 h sem queixas não quer dizer nada. Serve para o maintainer usar a beta e para o CI correr |
| S7 | Major só com `STABLE_APPROVE=X.Y.Z` | B | Mudanças incompatíveis precisam de decisão humana |
| S8 | Nova verificação completa numa cópia limpa da tag | B | Exclui caches e alterações locais |
| S9 | O conteúdo do `main` (sem ficheiros de desenvolvimento) compila, fica assinado e passa o autoteste | B | O `main` tem de ser compilável por quem o clona |

### 3.4 O que ainda não é medido

Estes indicadores não são verificados hoje. Cada um tem entrada no [registo de riscos](RISK_REGISTER.md).

| Indicador | Estado | Proposta |
|---|---|---|
| Regras de cada análise (o que é lixo) | **Sem testes** | Testes com pastas temporárias que imitam `~/Library` (risco R1) |
| Execução em Intel | Só compilado | Teste manual em Intel em cada major (A) |
| Memória e tempo de cada análise | `--bench` existe, sem limites | Aviso se o pico de memória de uma análise subir mais de 50% face à versão anterior (A) |
| Taxa de falhas | Não medida (não há relatórios de falhas, por privacidade) | Só as issues; um relatório de falhas opcional seria uma decisão de privacidade à parte |
| Testes de instalação, atualização e desinstalação | Manuais | Lista de verificação na secção 6 |

## 4. Segurança das operações que apagam

Estas regras valem para todo o código que remove, move, sobrescreve ou corre como administrador.

1. **Pré-visualização primeiro.** Cada análise mostra a lista do que vai ser removido antes de remover. Nada é apagado sem uma ação explícita do utilizador.
2. **Confirmação.** Remoções de ficheiros do utilizador, apps, itens de arranque e tarefas com privilégios pedem confirmação, com o número de itens e o tamanho.
3. **Lista de proteção.** Tudo passa pelo `SafetyGuard.canDelete`: as pastas do sistema e as pastas pessoais nunca podem ser apagadas, os caminhos são normalizados e a pasta-mãe é resolvida (`/var`, `/tmp`, `/etc`).
4. **Ligações simbólicas.** Apagar uma ligação nunca toca no destino; o Destruidor nunca sobrescreve através de uma ligação.
5. **Reversível por omissão.** Ficheiros pessoais e apps vão para o Lixo. Só caches e registos são apagados diretamente.
6. **Privilégio mínimo.** Pede a palavra-passe de administrador só quando a operação falha sem ela, uma vez por lote, e só para caminhos que passaram o `SafetyGuard`.
7. **Testes só em pastas descartáveis.** Os testes usam `TempDir` e nunca tocam em `~`, no Lixo verdadeiro ou em `/Applications`. Nenhuma operação destrutiva se testa diretamente no Mac de quem desenvolve.
8. **Uma limpeza que corre bem não prova que é segura.** Os testes verificam também o que **não** pode mudar: o ficheiro de destino de uma ligação continua igual; os dados destruídos desaparecem mesmo, através de uma ligação física; as pastas protegidas continuam lá.

## 5. Governação

| Situação | Quem ou o quê | Registo |
|---|---|---|
| Beta | `ship.sh`, depois de a verificação completa passar | Commit, tag, Release |
| Estável patch/minor | `stable.sh --apply` (corre no fim de cada `ship.sh` e todos os dias às 23:30) | Pull Request para o `main`, com a tabela de critérios e a evidência |
| Estável major | Maintainer, com `STABLE_APPROVE=X.Y.Z ./scripts/stable.sh --apply` | O mesmo Pull Request, com a justificação da aprovação |
| Exceção a um critério (ex.: correção de segurança urgente sem as 24 h) | Maintainer: `STABLE_SOAK_HOURS=0 ./scripts/stable.sh --apply` | Motivo escrito no Pull Request e uma linha no CHANGELOG |
| Risco aceite | Maintainer | Entrada no [registo de riscos](RISK_REGISTER.md), com data e motivo |

**Nunca há exceção** para Q5–Q7, R3–R5, S3, S8 ou S9. São estas verificações que impedem que uma versão que apaga mal chegue a alguém.

### Regressões e retirada de uma versão

1. Abrir uma issue com a etiqueta `bug` a mencionar `vX.Y.Z`. A versão deixa logo de poder ser promovida (S4).
2. Se a versão já é estável e o erro pode causar perda de dados: editar a Release para pré-lançamento com a nota "⚠️ Retirada: ver #N" e, no `main`, fazer `git revert` do commit da versão por Pull Request. Como o `main` tem um commit por versão, isso repõe a estável anterior.
3. Publicar a correção (`### Corrigido`). As versões anteriores ficam automaticamente rejeitadas (S5) e a correção segue o caminho normal.

### Vulnerabilidades

Ver [SECURITY.md](../SECURITY.md).

## 6. Lista de verificação manual (cada minor e major)

Num Mac ou numa conta de teste que não seja a principal:

- [ ] Instalação limpa a partir do DMG; `shasum -a 256 -c SHA256SUMS` confirma o DMG.
- [ ] Atualização por cima da versão anterior: as definições mantêm-se e o Acesso Total ao Disco continua concedido.
- [ ] Sem Acesso Total ao Disco: as análises não falham e explicam o que falta.
- [ ] Cancelar o pedido de palavra-passe de administrador: nada é apagado e a interface explica porquê.
- [ ] Desinstalar o Prune com o próprio Desinstalador de outra app e pelo Finder: não ficam agentes nem processos.
- [ ] Em Intel (só em cada major): abrir, correr a Análise Inteligente e uma limpeza de caches.

## 7. Critérios da primeira versão "GA certificada"

A numeração do Prune já passou o 1.0.0 (há tags `v1.x` publicadas, que não se reutilizam). Por isso, a primeira versão que cumprir **todos** estes critérios deve sair como **2.0.0**, com aprovação explícita. Até lá, "estável" quer dizer: cumpre os critérios automáticos e não tem defeitos conhecidos.

| # | Critério | Obrigatório para 2.0.0 | Como se verifica |
|---|---|---|---|
| G1 | Todos os portões automáticos (secção 3) cumpridos | Sim | Pull Request de promoção |
| G2 | Regras de cada análise com testes e cobertura ≥ 80% nos scanners (R1) | Sim | `MIN_COVERAGE` inclui os scanners |
| G3 | Remoção como administrador sem corrida entre verificar e apagar (R2) | Sim | Teste que troca a pasta-mãe por uma ligação |
| G4 | Confirmação em todas as ações destrutivas e com privilégios (R4) | Sim | Revisão das views; lista na secção 4 |
| G5 | Distribuição sem pedir para desativar a quarentena: Developer ID e notarização, **ou** risco aceite registado com alternativa documentada (ex.: compilar a partir do código) (R3) | Sim | `spctl -a -vv` aceita a app, ou entrada no registo de riscos |
| G6 | Proteção do ramo `main` no GitHub: só por Pull Request, sem force-push (R10) | Sim | Definições do repositório |
| G7 | Relatório privado de vulnerabilidades ligado no GitHub | Sim | Definições do repositório |
| G8 | Lista manual da secção 6 feita e anexada ao Pull Request | Sim | Pull Request |
| G9 | Programa-piloto: a beta usada por pelo menos 5 pessoas, em pelo menos 2 versões do macOS, durante 7 dias, sem erros `bug` abertos | Sim | Issue de piloto com as respostas |
| G10 | Limites de memória por análise (secção 3.4) | Não (aviso) | `--bench` |
| G11 | Registo local do que foi apagado | Não, mas recomendado | — |
