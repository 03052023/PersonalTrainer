# Windows → iPhone + Apple Watch, sem Mac e sem custo

Atualizado em 2026-09-22 com fatos verificados (fontes no fim). Estado: código pronto para o primeiro run do CI; **nada foi instalado em aparelho ainda**.

## 1. Situação

- Você só tem Windows e nunca terá Mac. Os builds Apple rodam em runners macOS do GitHub Actions; a instalação no iPhone é feita por uma ferramenta de sideload no Windows com a sua conta Apple gratuita.
- Já está no repositório: o probe de validação (`Validation/DeviceProbe`, lê a última FC do Saúde), o app principal (projeto gerado por XcodeGen a partir de `project.yml`) e três workflows: **Core tests** (Linux, automático a cada push), **Device probe (manual)** e **App build (manual)** (macOS, só quando você dispara).
- Localmente, no Windows, só o motor (`Packages/TrainerCore`) compila e testa: `powershell -ExecutionPolicy Bypass -File Scripts/swift-test.ps1`.

## 2. Decisões

| Decisão | Motivo |
|---------|--------|
| Repositório **público** | Runners padrão do GitHub, inclusive macOS, são gratuitos e ilimitados em repositório público. Não há segredo no código: a assinatura acontece no seu Windows. Em repositório privado a franquia é 2.000 min/mês e o macOS consome ~10× mais rápido (≈ 200 min macOS/mês). Se preferir privado: não cadastre cartão e crie um budget de US$ 0 para Actions com "Stop usage when budget limit is reached". |
| Runner `macos-26` com Xcode 26.6 fixado | Imagem atual: macOS 26.6, Xcode 26.6 (Swift 6.3, SDK iOS/watchOS 26.5). O app compilado com SDK 26.5 roda no seu iOS 26.6.2. `macos-latest` muda de versão sem aviso; `-large/-xlarge` são sempre cobrados. |
| Testes Linux em `container: swift:6.3` | Mesmo Swift do Xcode 26.6; roda em `ubuntu-latest` em segundos. |
| App do Watch **opcional** | Ver §5. Enquanto o companion não instala, a FC vem do app Exercício nativo do relógio e o app do iPhone lê pelo HealthKit. |

## 3. Passo a passo (você)

1. Crie um repositório vazio no GitHub chamado `PersonalTrainer` (público; sem README, sem .gitignore).
2. Conecte e envie o código:

```bash
git -C C:/Users/leona/Developer/PersonalTrainer remote add origin https://github.com/<usuario>/PersonalTrainer.git
```

```bash
git -C C:/Users/leona/Developer/PersonalTrainer push -u origin main
```

   O Git Credential Manager abre o navegador para você autorizar. Nunca cole tokens ou senhas no chat.
3. Na aba **Actions** do repositório, confirme que **Core tests** ficou verde (dispara sozinho no push).
4. Ainda em Actions, abra **Device probe (manual)** → *Run workflow*. Baixe o artefato `DeviceProbe-for-resigning` (IPA + SHA256).
5. Depois rode **App build (manual)** e baixe `PersonalTrainer-for-resigning`. Se falhar, cole o trecho de erro do log no chat; a correção sai em um branch `fix/ci-*` e você roda de novo (cada rodada ≈ 15–30 min de runner).

## 4. Instalar no iPhone

**O problema central não é a Apple, é a ferramenta.** HealthKit está disponível para a conta gratuita em iOS e watchOS (tabela oficial de capabilities). Mas as ferramentas populares assinam o app só com os entitlements do perfil e **não pedem a capability HealthKit** ao criar o App ID; o entitlement `com.apple.developer.healthkit` desaparece e `HKHealthStore` falha em silêncio.

| Ferramenta (Windows 11, iOS 26) | HealthKit preservado | Instala app do Watch | Renovação 7 dias | Observações |
|---|---|---|---|---|
| AltServer/AltStore | **Não** (código do AltSign confirma) | Não (issue #229 aberta desde 2020) | automática com PC ligado | rejeita IPA com pasta `Watch/` |
| SideStore | **Não** | Não (fork Andris73 em andamento) | automática no aparelho | login no iPhone |
| iLoader (upstream, nab138) | **Não** | Não | manual (reinstalar) | open source, exige iTunes |
| Sideloadly | não verificado (código fechado) | não documentado | automática com PC ligado | — |
| **Impactor** (open source) | **Sim, pelo código** (pede capabilities lendo o entitlement) | Não | automática com PC ligado | só iPhone; não validado no seu aparelho |
| **iLoader fork Rzbck** (`feat/watch-companion-support-20260909`) | **Sim, pelo código** | **Sim, relato de 1 validação física** | manual | artefato de CI sem release, não assinado, expira 2026-12-09; PRs upstream sem resposta |

Ordem recomendada de teste (probe primeiro, app depois):

1. **Impactor** para iPhone-only: valida a rota HealthKit com a ferramenta de maior confiança pública. Se o probe mostrar uma amostra de FC com data, V3/V4 do iPhone estão provados.
2. **iLoader fork Rzbck** para iPhone + Watch. Antes de digitar credenciais, leia o diff da PR nab138/isideload#12 (ou compile o branch) — é um binário de CI de um fork com zero estrelas.
3. AltStore/SideStore/Sideloadly só para apps sem HealthKit; não servem para este projeto.

Pré-requisitos comuns: iTunes baixado **do site da Apple** (não da Microsoft Store); iPhone com Modo de Desenvolvedor ativado (aparece em Ajustes › Privacidade e Segurança após a primeira tentativa de instalação); os bundle IDs recebem sufixo `.TEAMID` na instalação, o que é esperado.

Depois de instalar, confirme: o probe abre, o botão "Autorizar e ler FC" mostra a folha de permissão do Saúde e, após um treino no relógio, exibe uma amostra com data. Se a folha não aparecer, o entitlement foi removido pela ferramenta.

## 5. Apple Watch: riscos concretos

- **Modo de Desenvolvedor no relógio.** A documentação da Apple e vários relatos indicam que o interruptor só aparece após pareamento com Xcode em um Mac. Sem ele o companion não roda. Só o teste no seu Series 7 responde isso.
- **Ferramenta única e frágil.** Todo o suporte a Watch pelo Windows vive em forks pessoais de setembro de 2026, sem aceite upstream, sem release e sem renovação automática. Uma atualização do iOS/watchOS pode quebrar tudo.
- **Renovação semanal manual.** Esquecer a reinstalação deixa iPhone e Watch sem o app até reinstalar.
- **Consequência de produto:** o app do Watch (M3) só começa depois de V3–V5 aprovados. Até lá, inicie "Musculação tradicional" no app Exercício do relógio durante o treino; o app do iPhone lê a FC e vincula esse treino do Saúde (SPEC RF-13/RF-14).

## 6. Limites da conta gratuita

Perfil válido por **7 dias**; **3 apps** sideloaded por aparelho (a própria loja, se houver, ocupa 1); **10 App IDs por 7 dias** (iPhone + Watch = 2 por app; o probe consome outros 2, desinstale-o depois); **3 dispositivos** por conta (iPhone + Watch = 2). Nunca mude os bundle IDs `com.personaltrainer.app` e `com.personaltrainer.app.watchkitapp`. Nada de Push, iCloud, Siri ou Sign in with Apple: indisponíveis para conta gratuita e fazem a assinatura falhar.

Antes de qualquer reinstalação ou de apagar o app para liberar vaga, exporte o backup JSON (M2). Os dados do Saúde permanecem mesmo sem o app.

## 7. Segurança

- Apple ID, senha e código 2FA só dentro da ferramenta de sideload, que fala direto com a Apple. Nunca em chats, issues, commits ou scripts. Senha de app específico não é aceita por essas ferramentas.
- Considere um Apple ID dedicado ao sideload.
- Binário de CI de fork sem release manipula suas credenciais: audite o diff ou compile você mesmo antes de usar.
- O repositório público não contém nem deve conter perfis, certificados ou chaves (`.gitignore` já bloqueia `*.mobileprovision`, `*.p12`, `*.p8`, `*.cer`, `*.key`).

## 8. Evidências

| Etapa | Prova | Estado |
|---|---|---|
| V0 | Estrutura, plists, entitlements conferidos por script | ✔ |
| V1 | Xcode compila iPhone e Watch no CI | aguarda primeiro run |
| V2 | IPA contém `Payload/…/Watch/…app` e os dois executáveis | aguarda primeiro run |
| V3 | Conta gratuita instala e abre os dois apps nos aparelhos | exige você |
| V4 | Os dois apps mostram amostra real de FC com data | exige você |
| V5 | Renovação após 7 dias mantém os dois apps abrindo | exige você |

## 9. Plano B

1. IPA sem a pasta `Watch/` (o workflow pode gerar uma variante) instalado pelo Impactor ou pelo fork Rzbck: app do iPhone completo, com HealthKit, FC vinda do app Exercício do relógio.
2. Acompanhar o fork Andris73/SideStore (`fix229`) para instalar o Watch a partir do próprio iPhone.
3. Apple Developer Program (US$ 99/ano) + TestFlight a partir do GitHub Actions: remove os limites de 7 dias, 3 apps e 10 App IDs e instala o Watch nativamente. É a única rota oficial sem Mac.

## 10. Fontes

- GitHub Actions: <https://github.com/actions/runner-images/blob/main/README.md>, <https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-Readme.md>, <https://docs.github.com/en/billing/concepts/product-billing/github-actions>, <https://docs.github.com/en/billing/how-tos/set-up-budgets>, <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>.
- Apple, conta gratuita: <https://developer.apple.com/help/account/reference/supported-capabilities-ios/>, <https://developer.apple.com/help/account/reference/supported-capabilities-watchos/>, <https://developer.apple.com/support/compare-memberships/>, <https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device>, <https://developer.apple.com/forums/thread/718634>.
- Ferramentas: <https://github.com/rileytestut/AltSign/blob/master/AltSign/Capabilities/ALTCapabilities.m>, <https://github.com/rileytestut/AltStore/issues/229>, <https://github.com/SideStore/SideSign/blob/main/Sources/Models/Feature.swift>, <https://github.com/claration/Impactor>, <https://github.com/nab138/iloader>, <https://github.com/nab138/isideload/pull/12>, <https://github.com/Rzbck/iloader-watch-companion>, <https://github.com/perezjuanj/OpenCircuit/issues/104>, <https://sideloadly.io/faq.html>.
- XcodeGen: <https://github.com/yonaskolb/XcodeGen>, <https://formulae.brew.sh/formula/xcodegen>.
