# Changelog

Alterações relevantes de cada versão. Formato [Keep a Changelog](https://keepachangelog.com/pt-PT/1.1.0/), versões [SemVer](https://semver.org/lang/pt-PT/).

## [1.2.9] - 2026-10-22

O ramo main passa a ter só o necessário para compilar a versão estável. A app não muda.

### Alterado
- O main deixa de ter os testes, os hooks e os scripts de publicação, que ficam só no ramo dev. Cada versão estável chega ao main como um único commit, depois de ser compilada e testada sem esses ficheiros.

### Corrigido
- Ficheiros de cache do Python deixaram de ser guardados no repositório.
- A publicação já não para com "a pasta mudou" quando um ficheiro é retirado do repositório.

## [1.2.8] - 2026-10-22

A versão estável passa a chegar ao main sozinha. A app não muda.

### Alterado
- Cada publicação verifica se há uma versão estável mais nova do que a do main e, se houver, testa-a de novo e leva-a para o main.

## [1.2.7] - 2026-10-22

O main passa a receber só versões estáveis, escolhidas e verificadas automaticamente. A app não muda.

### Adicionado
- Verificação automática da versão estável para o main: a mais recente publicada há pelo menos 24 horas, com o instalador, sem erros reportados e sem correções em versões posteriores. Antes de chegar ao main, é testada de novo numa cópia limpa.

## [1.2.6] - 2026-10-22

Cada versão passa agora por testes automáticos antes de ser publicada. A app não muda.

### Adicionado
- Testes automáticos às partes que apagam ou escolhem ficheiros: proteção de pastas, Destruidor, limpeza, duplicados, fotografias semelhantes e Lente de Espaço.
- Cada versão só é registada e publicada se passar nos testes, compilar sem avisos e o autoteste da app correr sem falhas.

## [1.2.5] - 2026-10-22

### Corrigido
- Destruidor: as ligações simbólicas dentro de uma pasta já não levam a sobrescrever o ficheiro original, fora da pasta.
- Destruidor: uma falha de escrita (disco cheio, ficheiro bloqueado) já não fecha a app.
- Proteção de pastas do sistema: passa a resolver ligações como /var e /tmp.
- Duplicados: fica sempre pelo menos uma cópia de cada ficheiro.
- Restos de apps: definições do sistema (impressão, iCloud) e do próprio Prune deixam de aparecer.
- Lente de Espaço: itens dentro de pastas também marcadas já não contam duas vezes.
- Limpeza: as categorias vazias saem da lista depois de limpar.

### Alterado
- Textos da app, README e instruções de instalação mais curtos e diretos, com plurais corretos.
- A secção "Velocidade" passa a chamar-se "Sistema".

## [1.2.4] - 2026-10-22

Primeira versão pública.

### Adicionado
- Licença GPL-3.0, este CHANGELOG e instruções de instalação no README.

## [1.2.3] - 2026-10-22

### Corrigido
- Assinatura, instalação e README voltaram a funcionar depois da mudança de nome; o projeto usa só o nome Prune.

## [1.2.2] - 2026-10-22

### Alterado
- Uma só folha em toda a app (a do ícone): ecrã de conclusão, consentimento e barra de menus.

## [1.2.1] - 2026-10-22

### Alterado
- Código reorganizado por funcionalidade; removido o que não era usado.

## [1.2.0] - 2026-10-22

### Removido
- Gestão de RAM: cartão "Velocidade" da Análise Inteligente e botões Sair/Forçar nos grandes consumidores. O macOS gere a memória sozinho; ficam as métricas.

## [1.1.1] - 2026-10-22

### Corrigido
- O assistente de Acesso Total ao Disco já não verifica a permissão sozinho a cada 1,5 s.

## [1.1.0] - 2026-10-22

### Alterado
- Novo nome, Prune, novo ícone (folha) e novo design marfim e tinta, com modo claro e escuro.

### Adicionado
- Estatísticas de utilização anónimas e opcionais, com pedido de consentimento no primeiro arranque.

## [1.0.0] - 2026-10-22

- Primeira versão: Análise Inteligente, Painel, limpeza, privacidade, otimização, manutenção, desinstalador, atualizador, extensões, Lente de Espaço, ficheiros grandes, duplicados e destruidor.

[1.2.9]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.9
[1.2.8]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.8
[1.2.7]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.7
[1.2.6]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.6
[1.2.5]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.5
[1.2.4]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.4
