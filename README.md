# Prune

Limpe, organize e proteja o seu Mac. Gratuito e de código aberto.

**[Descarregar a última versão](https://github.com/viniciuslopesgit/prune/releases/latest)** · macOS 14 ou mais recente · Apple silicon e Intel

## Instalar

1. Abra o `Prune-<versão>.dmg` e arraste o Prune para **Aplicações**.
2. Na primeira abertura, o macOS bloqueia a app, porque o Prune não está registado na Apple. Autorize uma vez em *Definições do Sistema ▸ Privacidade e segurança ▸ Abrir mesmo assim*, ou no Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Prune.app
   ```
3. Siga o assistente para dar **Acesso Total ao Disco**.

Para atualizar, descarregue a versão nova e substitua a app em Aplicações. Novidades no [CHANGELOG](CHANGELOG.md).

## Funcionalidades

- **Análise Inteligente:** lixo para limpar e estado das proteções do macOS, num clique.
- **Painel:** disco, memória, CPU, rede, bateria e proteções do macOS (SIP, Gatekeeper, Firewall, FileVault, XProtect).
- **Limpeza:** caches, registos, temporários, Xcode e gestores de pacotes, ficheiros de iPhone, anexos do Mail e Lixo.
- **Privacidade:** histórico, cookies e caches de Safari, Chrome, Edge, Brave, Opera, Vivaldi, Arc e Firefox. Palavras-passe e marcadores ficam intactos.
- **Sistema:** itens de arranque, processos e tarefas de manutenção (DNS, Spotlight, Launch Services, disco).
- **Aplicações:** desinstalação completa, restos de apps removidas, atualizações (Sparkle e Homebrew) e extensões.
- **Ficheiros:** mapa do disco, ficheiros grandes e antigos, duplicados, fotografias semelhantes e destruição segura.
- **Barra de menus:** CPU, memória, disco, rede e bateria em tempo real.

## Segurança e privacidade

- Nada é apagado sem confirmação. Pode rever cada item antes de limpar.
- Pastas do sistema e pastas pessoais estão protegidas, independentemente do que selecionar.
- Ficheiros pessoais e apps vão para o Lixo. Caches e registos são apagados diretamente. Pode mudar isto nas Definições.
- As estatísticas de utilização são anónimas e só são enviadas com o seu consentimento. Nunca incluem nomes de ficheiros, pastas ou apps.

## Desenvolvimento

Requer macOS 14 ou mais recente e as Command Line Tools do Xcode (`xcode-select --install`).

```bash
./scripts/setup_signing.sh   # uma vez: certificado local, para o macOS manter as permissões
./scripts/build_app.sh       # cria build/Prune.app (universal)
./scripts/install.sh         # compila e atualiza /Applications/Prune.app
./scripts/make_dmg.sh        # cria build/Prune-<versão>.dmg
```

Estatísticas: crie `analytics.env` (ignorado pelo git) com `GA_MEASUREMENT_ID` e `GA_API_SECRET`. Sem este ficheiro, a app não envia nada.

Diagnóstico:

```bash
build/Prune.app/Contents/MacOS/Prune --selftest      # todas as análises, só em leitura
build/Prune.app/Contents/MacOS/Prune --bench --twice # memória de cada análise
```

Estrutura de `Sources/Prune`: `App` (arranque e janela), `Core` (ficheiros, permissões, definições, limpeza), `UI` (tema e componentes), `Features` (uma pasta por funcionalidade) e `Diagnostics`.

### Versões

`main` é a versão estável e `dev` o trabalho em curso. Cada versão tem uma tag `vX.Y.Z` e uma [Release](https://github.com/viniciuslopesgit/prune/releases) com o DMG.

## Licença

[GPL-3.0](LICENSE)
