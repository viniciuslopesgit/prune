# Changelog

Alterações relevantes de cada versão. Formato [Keep a Changelog](https://keepachangelog.com/pt-PT/1.1.0/), versões [SemVer](https://semver.org/lang/pt-PT/).

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

[1.2.5]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.5
[1.2.4]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.4
