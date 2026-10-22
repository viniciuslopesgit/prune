# Prune

Limpador e organizador para macOS, **gratuito e de código aberto** (GPL-3.0), escrito de raiz em SwiftUI.
Não contém código de terceiros nem de outros produtos comerciais.

## Descarregar

**[⬇ Descarregar a última versão](https://github.com/viniciuslopesgit/prune/releases/latest)**: ficheiro `Prune-<versão>.dmg`.

Requer macOS 14 (Sonoma) ou superior. Funciona em Macs com Apple silicon e Intel.

## Instalar

1. Abra o `Prune-<versão>.dmg` e arraste o **Prune** para a pasta **Aplicações**.
2. Abra o Prune a partir de Aplicações.
3. **Na primeira abertura, o macOS bloqueia a app.** O Prune é gratuito e não está registado na Apple (isso exige uma conta paga de programador), por isso o macOS mostra "Não foi possível verificar o Prune". Autorize uma vez:
   - clique em **OK**, abra *Definições do Sistema ▸ Privacidade e segurança*, desça até **Segurança** e clique em **Abrir mesmo assim**;
   - ou, no Terminal: `xattr -dr com.apple.quarantine /Applications/Prune.app`
4. Siga o assistente de **Acesso Total ao Disco**. Sem esta permissão, o macOS pergunta por cada pasta protegida que o Prune analisa.

As mesmas instruções vêm no ficheiro *Como abrir.txt*, dentro do DMG.

### Atualizar

Descarregue a versão nova e substitua o Prune na pasta Aplicações. Se o macOS voltar a pedir, autorize a abertura e o Acesso Total ao Disco como na primeira vez. As novidades de cada versão estão no [CHANGELOG](CHANGELOG.md).

## Funcionalidades

| Secção | Módulo | O que faz |
|---|---|---|
| — | **Análise Inteligente** | Limpeza + estado das proteções num clique |
| — | **Painel** | Disco, memória, CPU, rede, bateria (saúde e ciclos) e proteções do macOS: SIP, Gatekeeper, Firewall, FileVault, atualizações de segurança e XProtect, com atalho para ativar as que estiverem desligadas |
| Limpeza | **Lixo do Sistema** | Caches, registos, relatórios de falhas, temporários, lixo do Xcode, caches de npm/pip/Homebrew/Gradle…, ficheiros de iPhone, preferências danificadas, agentes quebrados, transferências incompletas |
| | **Anexos do Mail** | Anexos abertos e cópias locais de anexos |
| | **Lixo** | Esvazia o Lixo do disco de arranque e dos discos externos |
| Proteção | **Privacidade** | Histórico, cookies e cache de Safari, Chrome, Edge, Brave, Opera, Vivaldi, Arc, Firefox; itens recentes (palavras-passe e marcadores nunca são tocados) |
| Velocidade | **Otimização** | Itens de início de sessão, agentes de arranque (ativar/desativar/remover), grandes consumidores (CPU e memória por processo, só para consulta: o macOS gere a RAM sozinho) |
| | **Manutenção** | Espaço purgável, cache DNS, reindexar Spotlight, Launch Services, Quick Look, tipos de letra, acelerar o Mail, verificar disco, permissões, reiniciar Dock/Finder |
| Aplicações | **Desinstalador** | Remove apps com todos os ficheiros de suporte, repõe apps, encontra restos de apps já removidas |
| | **Atualizador** | Atualizações via Sparkle (site do programador) e Homebrew; atalho para a App Store |
| | **Extensões** | Extensões do Safari, partilha, Finder, widgets, Quick Look, Spotlight, painéis de preferências, plug-ins e extensões de Chrome/Edge/Brave/Firefox |
| Ficheiros | **Lente de Espaço** | Mapa visual (treemap) do disco com navegação |
| | **Grandes e Antigos** | Filtros por tamanho, data da última abertura e tipo |
| | **Duplicados** | Ficheiros idênticos (SHA-256) e fotografias semelhantes (Vision) |
| | **Destruidor** | Sobrescreve e apaga ficheiros sensíveis |
| — | **Barra de menus** | Monitor de CPU, memória, disco, rede, bateria e apps mais exigentes |

## Estatísticas de utilização (opcional)

O Prune pode enviar estatísticas anónimas para o Google Analytics 4 (Measurement Protocol), **só se o utilizador aceitar** (pergunta no primeiro arranque; muda-se em *Definições ▸ Geral ▸ Estatísticas*). Recusar apaga o identificador aleatório da instalação.

- Eventos: `app_open`, `module_view` (secção aberta), `scan_complete` e `clean_complete` (totais em MB e contagens).
- Nunca são enviados caminhos, nomes de ficheiros, pastas ou apps.
- As chaves não estão no repositório. Para as incluir num build, copie `analytics.env.example` para `analytics.env` (ignorado pelo git) e preencha o ID de medição e o segredo da API, ou exporte `GA_MEASUREMENT_ID` e `GA_API_SECRET`. Sem chaves, a opção nem aparece e nada é enviado.
- Quem compilar o código-fonte sem as suas chaves obtém uma app sem estatísticas. O segredo da API vai dentro do `Info.plist` da app distribuída e pode ser extraído; serve só para enviar eventos, não para ler dados.

## Segurança

- Nada é apagado sem confirmação. Os resultados de cada análise podem ser revistos item a item.
- Pastas críticas do sistema e do utilizador são bloqueadas (`Sources/Prune/Core/SafetyGuard.swift`), independentemente do que for selecionado.
- Por defeito, ficheiros pessoais e apps vão para o **Lixo**; caches e registos regeneráveis são apagados diretamente (configurável em Definições).
- **Lista de exclusões** nas Definições: o que lá estiver nunca é removido.
- As tarefas que exigem administrador pedem a palavra-passe através do diálogo do macOS.
- Nota sobre o Destruidor: em SSDs/APFS o sistema pode manter cópias de blocos antigos; a proteção total é o FileVault.

## Compilar a partir do código

Requer macOS 14 ou superior e as Command Line Tools do Xcode (`xcode-select --install`).

```bash
./scripts/build_app.sh
open build/Prune.app
```

Para o ter sempre à mão, arraste `build/Prune.app` para a pasta **Aplicações**.

### Atualizar a app instalada

```bash
./scripts/install.sh
```

Compila e atualiza `/Applications/Prune.app` **no lugar**. Evite substituir a app arrastando-a do DMG (o Finder manda a versão antiga para o Lixo e o macOS remove as permissões dela — tem de voltar a ativar o Acesso Total ao Disco).

### Criar o instalador (DMG)

```bash
./scripts/make_dmg.sh
```

Gera `build/Prune-<versão>.dmg`: uma janela com o Prune, um atalho para Aplicações e o ficheiro *Como abrir.txt*. A app é universal (Apple silicon + Intel). Não é preciso conta Apple Developer.

**Ao enviar para outros Macs:** como a app não é notarizada pela Apple (isso exige a conta paga), o macOS bloqueia a primeira abertura de cópias descarregadas da Internet. O utilizador autoriza uma vez em *Definições do Sistema ▸ Privacidade e segurança ▸ Abrir mesmo assim* (ou com `xattr -dr com.apple.quarantine /Applications/Prune.app`). As instruções vão dentro do DMG. No Mac onde a app foi compilada não há bloqueio.

### Permissões (evitar pedidos constantes)

1. **Assinatura estável (uma vez):** `./scripts/setup_signing.sh` cria um certificado local no porta-chaves. A partir daí, o `build_app.sh` assina com ele e o macOS reconhece a app como a mesma entre versões, mantendo as permissões. Sem isto (assinatura ad-hoc), cada compilação é uma "app nova" e o macOS volta a pedir tudo.
2. **Acesso Total ao Disco:** o assistente aparece ao abrir a app. Com esta permissão o macOS deixa de pedir autorização pasta a pasta (Documentos, Secretária, Transferências, dados de outras apps, Mail, Safari).
3. **Palavra-passe de administrador:** só é pedida em tarefas que precisam mesmo dela (limpar DNS, espaço purgável, apagar ficheiros do sistema…). O macOS pede-a em cada execução (não a memoriza).

## Ferramentas de desenvolvimento

```bash
# Executa todas as análises em modo só de leitura e mostra um resumo
build/Prune.app/Contents/MacOS/Prune --selftest

# Mede a memória de cada análise pesada (--twice repete para detetar fugas, --photos inclui fotos semelhantes)
build/Prune.app/Contents/MacOS/Prune --bench --twice

# Verifica o Acesso Total ao Disco com a identidade da app (lançada pelo macOS)
open -n /Applications/Prune.app --args --fdacheck /tmp/prune-fda.txt
```

## Estrutura do projeto

```
├── Package.swift            Pacote Swift (executável, macOS 14+)
├── Resources/
│   ├── Info.plist           Identificador, versão, permissões
│   └── Como abrir.txt       Instruções incluídas no DMG
├── scripts/
│   ├── build_app.sh         Compila e cria build/Prune.app (universal, assinada)
│   ├── install.sh           Compila e atualiza /Applications/Prune.app no lugar
│   ├── make_dmg.sh          Cria o instalador build/Prune-<versão>.dmg
│   ├── setup_signing.sh     Cria o certificado local de assinatura (uma vez)
│   ├── make_icon.swift      Desenha o ícone da app
│   └── make_dmg_background.swift  Desenha o fundo da janela do DMG
└── Sources/Prune/
    ├── App/                 Arranque, estado global, janela principal, lista de módulos
    ├── Core/                Infraestrutura: shell, ficheiros, permissões, definições, monitor do sistema
    │   └── Cleaning/        Modelo comum de limpeza (itens, categorias, remoção)
    ├── UI/                  Componentes partilhados: tema, estrutura dos ecrãs, controlos, gráficos
    ├── Features/            Uma pasta por funcionalidade (modelo + serviço + vista)
    │   ├── SmartScan/  Dashboard/  Cleanup/  Privacy/  Optimization/  Maintenance/
    │   ├── Uninstaller/  Updater/  Extensions/  SpaceLens/  LargeFiles/  Duplicates/  Shredder/
    │   └── Settings/  MenuBar/  Onboarding/
    └── Diagnostics/         Ferramentas --selftest, --bench e --fdacheck
```

Ficheiros gerados (ignorados pelo git): `build/` (app, DMG, ícone) e `.build/` (compilação do Swift; `swift package clean` liberta-a).

## Memória

- As análises percorrem o disco libertando memória à medida (autorelease pool por lote) e calculam hashes com um buffer fixo de 1 MB.
- A Lente de Espaço guarda só nomes (os caminhos são reconstruídos), agrega pastas pequenas e limita cada pasta a 50 filhos.
- Imagens são mostradas como miniaturas em cache (máx. 48 MB); os ícones também ficam em cache.
- Ao fechar a janela (a app continua na barra de menus) ou com pouca memória no sistema, os resultados pesados são libertados.

## Desenvolvimento e versões

- `main`: versão estável, igual à última Release. `dev`: trabalho em curso.
- Cada versão tem uma tag `vX.Y.Z` e uma [Release](https://github.com/viniciuslopesgit/prune/releases) com o DMG. A versão está em `Resources/Info.plist`.
- Versões: funcionalidade nova → `X.Y+1.0`; correção → `X.Y.Z+1`.

## Licença

Prune é software livre: pode redistribuí-lo e/ou modificá-lo nos termos da [GNU General Public License, versão 3](LICENSE).
