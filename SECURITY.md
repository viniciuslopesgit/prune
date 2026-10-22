# Segurança

O Prune apaga ficheiros e, em algumas tarefas, corre comandos como administrador. Um erro de segurança aqui pode custar dados. Obrigado por ajudar a encontrá-los.

## Versões suportadas

| Versão | Correções de segurança |
|---|---|
| Última estável ([Latest](https://github.com/viniciuslopesgit/prune/releases/latest)) | Sim |
| Última beta (pré-lançamento) | Sim |
| Anteriores | Não: atualize para a última estável |

## Como reportar

**Não abra uma issue pública** para uma vulnerabilidade.

Use **Security ▸ Report a vulnerability** no [repositório](https://github.com/viniciuslopesgit/prune/security). Se essa opção não aparecer, abra uma issue só com o título "Contacto de segurança", sem detalhes, e o maintainer responde com um canal privado.

Inclua, se puder:

- a versão do Prune e do macOS, e se é Apple silicon ou Intel;
- os passos para reproduzir, de preferência numa pasta de teste e não em dados reais;
- o impacto: o que pode ser apagado, lido ou executado, e com que privilégios.

## O que conta como vulnerabilidade

- Apagar, mover ou sobrescrever algo fora do que o utilizador escolheu: pastas protegidas, o destino de ligações simbólicas, outros volumes.
- Executar comandos como administrador com caminhos ou argumentos que alguém consiga controlar.
- Enviar dados para fora do Mac sem consentimento, ou enviar mais do que o [descrito no README](README.md#segurança-e-privacidade).
- Ler ou expor palavras-passe, cookies ou dados de navegação além do necessário para os limpar.

## Prazos

Prazos de um projeto com um maintainer, cumpridos tanto quanto possível:

| Passo | Prazo |
|---|---|
| Confirmar a receção | 3 dias |
| Avaliação inicial e gravidade | 7 dias |
| Correção de gravidade alta ou crítica | 30 dias |

A correção sai como patch, com `### Corrigido` no CHANGELOG, o que retira automaticamente as versões afetadas do caminho para estável. Em casos urgentes pode dispensar o período de espera de 24 h, com o motivo registado (ver [critérios de lançamento](docs/RELEASE_CRITERIA.md#5-governação)). Depois da correção publicada, o relatório é divulgado com crédito a quem o enviou, se assim o quiser.

## O que o Prune faz para limitar o risco

- Lista de pastas protegidas que nunca são apagadas, com os caminhos normalizados e as ligações da pasta-mãe resolvidas.
- Ficheiros pessoais e apps vão para o Lixo; só caches e registos são apagados diretamente.
- A palavra-passe de administrador só é pedida quando é precisa, e só para caminhos que passaram pela lista de proteção.
- Telemetria desligada até haver consentimento, sem nomes de ficheiros, pastas ou apps.
- Sem dependências de terceiros.

Os riscos conhecidos e ainda por resolver estão no [registo de riscos](https://github.com/viniciuslopesgit/prune/blob/dev/docs/RISK_REGISTER.md).
