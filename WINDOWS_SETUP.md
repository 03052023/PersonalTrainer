# Validação no Windows: iPhone + Apple Watch

Estado: código de teste preparado; não equivale a instalação, leitura real ou integração completa.

## Objetivo e aparelhos

Validar um caminho sem mensalidade nem assinatura Apple paga, mantendo o app nativo.
Desenvolvimento em `C:\Users\leona\Developer\PersonalTrainer`; originais preservados no OneDrive.
Aparelhos informados: iPhone 17 / iOS 26.6.2 e Apple Watch Series 7 GPS 41 mm / watchOS 26.5.
Nenhum número de série ou identificador de dispositivo é necessário no repositório.

## O que este teste faz

`Validation/DeviceProbe` contém um projeto isolado com app de iPhone e companion do Watch.
Em cada aparelho, o botão **Autorizar e ler FC** solicita somente leitura da frequência cardíaca.
O resultado é a última amostra das últimas 24 horas, com a data. Não é FC ao vivo.
Ausência de amostra não prova que o usuário recusou acesso: HealthKit não revela essa decisão.

O teste não grava treinos, não tem banco nem backend, não transmite dados de saúde e não implementa
WatchConnectivity. A FC é consultada independentemente em cada aparelho. Nenhuma regra P/S/D muda.

## Compilar sem Mac pessoal e sem cobranças

O Windows não compila os targets Apple. O workflow manual `Device probe (manual)` usa um runner
macOS padrão do GitHub, com Xcode. São máquinas Apple remotas; não há acesso interativo a um Mac.

Antes de executar, conferir **Settings → Billing and licensing → Budgets and alerts** da conta:
produto **Actions**, orçamento **US$ 0**, **Stop usage = Yes**. Em 2026-09-22 essa configuração
foi observada na conta do usuário. Não alterar para liberar gasto.
Conta gratuita privada usa a franquia incluída. Se ela acabar, aguardar renovação; não pagar.
O workflow não dispara em push, PR ou horário; tem timeout de 20 minutos, sem cache e artefato
retido por um dia. Não enviar credenciais Apple ao GitHub nem publicar o repositório por conveniência.

No GitHub: **Actions → Device probe (manual) → Run workflow**.
O artefato `DeviceProbe-for-resigning` inclui IPA, SHA-256, commit-fonte e versão do Xcode.
O IPA contém uma assinatura ad-hoc local para preservar o entitlement HealthKit; **não é uma
assinatura Apple de provisionamento e não instala diretamente**. Deve ser reassinado no Windows.

## Instalação: etapa experimental ainda não comprovada

O projeto comunitário [iloader-watch-companion](https://github.com/Rzbck/iloader-watch-companion)
relata instalação/abertura dos dois apps pelo Windows. A evidência não identifica conta gratuita,
os modelos/versões destes aparelhos nem leitura real de FC.

A evidência publicada de provisionamento HealthKit pertence ao par histórico:
- iLoader `70f37e9b4afc659ab44ec1944c034093f4cda416`.
- isideload `f7b9f3da570edd6824c29680545e710846d07df5`.

Não substituir esse par por qualquer release recente: a contribuição upstream exclui a parte
específica de HealthKit. Não há instalador estável comprovado para toda a combinação.
Antes de executar ferramentas comunitárias, revisar a origem, a dependência entre esses commits
e o processo de build. Instalação e login Apple são uma etapa separada, com participação do usuário.

O iLoader oficial exige iTunes no Windows. O usuário precisará conectar o iPhone, confiar no
computador e habilitar Modo de Desenvolvedor onde solicitado nos dois aparelhos.
Login Apple e 2FA ficam no fluxo local do instalador; nunca em chats, commits ou logs publicados.
Não remover apps existentes para liberar vagas automaticamente.

A conta Apple gratuita tem limites de apps/identificadores e perfis de sete dias. Renovar a
assinatura usando os mesmos identificadores e a mesma conta; validar também o companion.
Não considerar custo zero sustentável antes de testar essa renovação.

## Evidências necessárias

| Etapa | Prova exigida |
|---|---|
| V0 | Scripts verificam plists, referências, entitlement e estrutura do projeto |
| V1 | Xcode compila iPhone e Watch em CI |
| V2 | IPA contém `Payload/DeviceProbe.app/Watch/DeviceProbeWatch.app` e os dois executáveis |
| V3 | Conta gratuita provisiona, instala e abre os dois apps físicos |
| V4 | Os dois mostram uma amostra real e sua data após autorização |
| V5 | Renovação mantém os dois apps instalados e abrindo |

V1/V2 não demonstram V3/V4. V3/V4 não demonstram renovação nem integração completa.
Após V0–V5, uma tarefa separada valida FC ao vivo com `HKWorkoutSession`, WatchConnectivity,
gravação de um único treino e comportamento offline. Não tratar este probe como app de treino.

Para V4, usar o app Treino nativo do Watch para obter uma amostra recente e então consultar
novamente no probe. O HealthKit do iPhone pode demorar a receber amostras do relógio.
Não precisa compartilhar valores de saúde: basta informar se apareceu uma amostra com data recente.

## Verificação local

```powershell
cd C:\Users\leona\Developer\PersonalTrainer
python Validation/DeviceProbe/generate_project.py
python Scripts/check-device-probe.py
swift test --package-path Packages/TrainerCore
```

O gerador usa somente a biblioteca padrão de Python; não adiciona dependência de terceiros ao app.
O projeto gerado também fica versionado. Para compilar no runner, usar
`bash Scripts/build-device-probe.sh`. Os arquivos locais de build ficam ignorados pelo Git.

## Fontes e limites consultados em 2026-09-22

- [HealthKit disponível por modalidade de conta iOS](https://developer.apple.com/help/account/reference/supported-capabilities-ios/).
- [Capacidades watchOS](https://developer.apple.com/help/account/reference/supported-capabilities-watchos/).
- [Limites da conta Apple gratuita](https://developer.apple.com/help/account/basics/about-your-developer-account).
- [Franquia e cobrança do GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
- [Bloqueio de gastos do GitHub](https://docs.github.com/en/billing/how-tos/set-up-budgets).
- [Compatibilidade experimental](https://github.com/Rzbck/iloader-watch-companion/blob/main/docs/COMPATIBILITY.md).
- [Limitações da contribuição upstream](https://github.com/Rzbck/iloader-watch-companion/blob/main/HANDOFF.md).
- [iLoader oficial](https://iloader.app/).

## Resultado desta execução

Preencher somente com evidências observadas. Nenhum dispositivo foi validado apenas por um build.
