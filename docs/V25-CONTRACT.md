# Contrato da 2.5, fase 2: loja, sem sideload, Sobre e avaliação

Versão 1 · 2026-10-05. Base: o commit do `main` que traz este arquivo, por cima do andaime `edc8201` (§3). Os worktrees `C:\Users\leona\Developer\pt-wt\w10-*` partem dele.

O dono aprovou lançar o Magister grátis na App Store do Brasil, com o nome "Magister: Treino com Ciência" (SPEC decisão 22; notas do dono, item 20). A fase 1 (T11.0 documentos, T11.1 CI menor) está no `main`. Esta fase faz, em paralelo, as tarefas T11.2 a T11.6 do TASKS (milestone M6), pelas regras L1 a L8 da SPEC §7.18, que são a fonte de verdade desta onda. A §7.18 já traz os detalhes que este contrato fixou (L2, L3, L4, L6, L8 "Desde a fase 2").

**Notas do dono que continuam valendo** (`docs/design/v23-owner-notes.md`, itens 1 a 20; os de número maior prevalecem):
- nenhuma mensagem, citação, elogio ou frase de efeito em lugar nenhum do app (itens 15 e 16). A página Privacidade e o aviso de saúde são informação, não mensagem de efeito;
- "Dados não coletados", mostrado com fatos, sem promessa absoluta (item 20, L1, L2);
- avisos, só o indispensável; avaliação "depois de 1 semana", "do jeito menos invasivo possível" (L3, L5);
- a base científica se diz "com base científica" ou "baseado em estudos publicados", nunca "validado cientificamente" (decisão 22);
- para o app, nunca "personal", "treinador" nem "coach" (L8).

**Fora deste contrato:**
- o bundle ID da loja (T11.10, decisão do dono): nenhum bundle ID muda;
- o envio à loja (`release.yml`, `ExportOptions.plist`, `build-release.sh`: T11.7) e as capturas (T11.8);
- a política, o suporte, os termos e a ficha da loja (T11.9), e a faixa etária (decisão pendente do dono);
- o plano pago e o uso de IA (decisão 13 em revisão);
- qualquer mudança em `Persistence/Schema/`, nos programas ou no catálogo do seed;
- o app do Watch (M3). Nenhum texto cita o Apple Watch como destino dos dados: o app do relógio não vai na loja.

## 0. Como testar sem compilador local

O Smart App Control bloqueia o Swift nesta máquina, e essa configuração não se mexe.

- Comece **todo** comando PowerShell com `Set-Location` para o **seu** worktree. Nunca edite `C:\Users\leona\Developer\PersonalTrainer` diretamente.
- Antes de cada push, releia inteiro cada arquivo que você alterou: tipos, imports, `@MainActor`/`Sendable`, inits, `switch` exaustivos, rótulos de argumento, fechamentos de chaves, `some View` com um só tipo de retorno.
- Configure o push antes: `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"`.
- CI: `git push origin HEAD:ci/v10-<key>`.
  - Todo push para `ci/**` que muda um arquivo fora da documentação roda o App build: compila e roda os testes no simulador, de 10 a 15 min.
  - O IPA (e o `Scripts/build-app.sh`) só roda em branch terminado em `-final`, em run manual ou quando a mensagem do commit da ponta contém `[ipa]`. **A `loja` precisa do `[ipa]` em toda rodada**, porque mexe no `build-app.sh`.
  - Se o commit toca `Packages/**` ou `PersonalTrainer/Resources/Seed/**`, roda também o Core tests. A coluna "Expected" do §2 diz quantos workflows esperar.
- Espere com `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\watch-ci.ps1 -Sha <sha completo> -Minutes 9 -Expected <N>` e repita a chamada até ele dizer que todos terminaram.
  - A API pública do GitHub aceita 60 pedidos por hora por IP, e os agentes desta onda dividem o mesmo IP. Se o script ficar mudo por muito tempo, é o limite: chame de novo, sem fazer outras consultas à API no meio.
- Corrija pelas anotações. No máximo 5 rodadas de CI por tarefa. No fim, com o CI verde, faça `git push origin v10/<key>`.
- Em `@Test(arguments:)`, declare os casos antes, como constantes com tipo explícito (armadilha do Swift 6.3 no Linux, HANDOFF §2).
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No PowerShell 5.1, passe a mensagem por arquivo (`git commit -F <arquivo>`), gravado em UTF-8 **sem BOM** (`[System.IO.File]::WriteAllText(<arquivo>, <texto>, (New-Object System.Text.UTF8Encoding($false)))`).
- O relatório traz: o que foi feito, os CAs cobertos, a lista **Verificado** e **Incerto** (AGENTS R11), o sha do último run verde e os achados fora do escopo.

## 1. Regras desta rodada

1. **Escopo exclusivo por arquivo** (§5). Arquivo novo só nas pastas da sua tarefa. Se precisar de um arquivo de outra tarefa, pare e reporte; não edite.
2. **Não edite** `SPEC.md`, `TASKS.md`, `AGENTS.md`, `DESIGN.md`, `ARCHITECTURE.md`, `README.md`, `WINDOWS_SETUP.md`, `docs/HANDOFF.md`, `docs/install/*`, `docs/design/*` nem este contrato. O arquiteto já os atualizou; o integrador marca o estado.
3. **`App/*` é do integrador** (`RootView.swift`, `AppEnvironment.swift`, `AppEnvironment+Factories.swift`, `PersonalTrainerApp.swift`). Ninguém mais toca. O que cada tarefa entrega para ser ligado está em "Entrega ao integrador".
4. **Congelado** (§4): as assinaturas listadas lá, os raw values persistidos e o formato do backup.
5. **Enum persistido nunca perde nem renomeia case** (AGENTS §4): `CoachRule.installExpiry` e `CoachAction.howToRenew` ficam; `OutsideActivityKind.spinning` fica com o raw value `spinning`.
6. **AGENTS:**
   - R1: `TrainerCore` só usa Foundation. R3: nenhum `Date()` no `TrainerCore`.
   - R4: views não escrevem no `ModelContext`. R5: `project.yml`, `.github/workflows/*`, `Scripts/build-*.sh` e `*.entitlements` só na `loja` ([PROJ]).
   - R7: regra nova ou alterada tem teste com o nome da regra (`@Test("L3 …")`, `@Test("L4 …")`, `testL2_…`, `testL3_…`, `testL4_…`, `testL5_…`). As regras já estão na SPEC §7.18.
   - R8: nada de `PersistentIdentifier` fora de `Persistence/`. R9: efeito externo com protocolo + Live + Fake.
   - R10: só o escopo; o resto vai em "Achados". R11: nada de `fatalError`, `try!` ou força-unwrap fora de testes; lista Verificado/Incerto.
   - §4: um tipo por arquivo, textos pt-BR fixos no código, `os.Logger`, sem `print`. §7: nenhuma permissão pedida no launch; **nenhum código de rede** (`URLSession`, sockets, `import Network`), nenhum SDK de terceiros (L1).
7. **Textos** só os do §6, ou novos no mesmo tom: pt-BR, curtos, factuais, sem promessa absoluta ("100% seguro", "aprovado pela Apple", "nada sai do iPhone", "em total conformidade com a LGPD"), sem "personal", "treinador" ou "coach" para o app, sem "!", sem "parabéns". Nenhuma linha com texto provisório ou "em breve": o que ainda não existe não aparece.
8. **Visual:** tokens do `Theme` e componentes do DesignSystem (`paperBackground()`, `inkCard()`, `PrimaryButtonStyle`), as listas como as de "Mais opções" (`Form`, `.listRowBackground(Theme.surface)`, `.scrollContentBackground(.hidden)`). Nada de hexadecimal solto, vermelho fora de erro, `figure.*`, `trophy`, `flame` (DESIGN §1, §8, §14).

## 2. Mapa das tarefas

| Chave | TASKS | Worktree | Branch | CI | Expected | Pesada |
|---|---|---|---|---|---|---|
| `loja` | T11.2 + T11.3 [PROJ] | `C:\Users\leona\Developer\pt-wt\w10-loja` | `v10/loja` | `ci/v10-loja` (com `[ipa]`) | 1 | não |
| `sideload` | T11.4 | `C:\Users\leona\Developer\pt-wt\w10-sideload` | `v10/sideload` | `ci/v10-sideload` | 2 | sim |
| `sobre` | T11.5 | `C:\Users\leona\Developer\pt-wt\w10-sobre` | `v10/sobre` | `ci/v10-sobre` | 1 | não |
| `avaliacao` | T11.6 | `C:\Users\leona\Developer\pt-wt\w10-avaliacao` | `v10/avaliacao` | `ci/v10-avaliacao` | 2 | sim |
| integrador | — | `C:\Users\leona\Developer\pt-wt\w10-integration` | `v10/integration` | `ci/v10-final` | 2 | — |

Nenhuma tarefa depende do código de outra para compilar: o que era compartilhado já está no andaime (§3) ou tem parâmetro com padrão (§4). No CI de cada tarefa, o app aparece "sem" a parte das outras (por exemplo, a `sobre` ainda vê a seção "Avisos" no Ajustes, e a `avaliacao` nunca pede de verdade, porque o `SessionFlowView` recebe o Fake até o integrador ligar o Live); o comportamento completo só existe na integração.

## 3. Andaime (no `main`, `edc8201`; App build verde no `ci/v10-scaffold`, run 37379293450)

O arquiteto tirou do código do integrador tudo o que dependia da C4, para a `sideload` apagar a C4 sem tocar no `App/*`:

| Arquivo | Mudança |
|---|---|
| `App/RootView.swift` | `CoachDestination` sem `.renewalHelp`; sem `coach.onRenewalHelpRequested`; sem a folha `RenewalHelpView`; comentários sem "Como renovar". |
| `App/AppEnvironment+Factories.swift` | `CoachService(…)` sem o argumento `expiry:` (app e preview). |
| `Services/Coach/CoachService.swift` | `expiry: ProvisioningExpiryReader = .unavailable` (o parâmetro ganhou padrão; a `sideload` o tira). |

Efeito no app do `main`: a C4 já não aparece (sem a data do perfil, a regra não fala), mas a seção "Avisos" do Ajustes e o código da C4 continuam até a `sideload`.

## 4. Assinaturas congeladas

| Símbolo | Dono | Quem usa |
|---|---|---|
| `CoachService.init(planner:programs:log:notifications:now:calendar:defaults:traits: = .empty, activities: = FakeOutsideActivityStore())`, sem `expiry:` | `sideload` | integrador (já chama assim desde o andaime), testes |
| `CoachInput.init(…)` sem `provisioningExpiry:`; os outros parâmetros, na mesma ordem e com os mesmos padrões | `sideload` | `sideload` |
| `SettingsView.init(backup:planner:coach:health:references:onDataChanged:now:defaults:)` e `SettingsView.init(model:coach:health:references:)`, iguais (o `coach` fica, mesmo sem uso visível) | `sideload` | integrador |
| `MoreOptionsView.init(model:references:)`, igual | `sobre` | `SettingsView` |
| `BackupServicing.suggestedFileName(now:) -> String`, assinatura igual; só o texto muda | `sobre` | `SettingsViewModel` |
| `OutsideActivityKind.spinning`: raw value `spinning`; `displayName` "Bicicleta indoor" | `sideload` | telas das atividades |
| `SessionFlowView.init(sessionID: UUID, environment: AppEnvironment, onClose: @escaping () -> Void, ratingPrompt: any RatingPromptStoring = FakeRatingPromptStore())` (parâmetro novo no fim, com padrão) | `avaliacao` | integrador |
| `protocol RatingPromptStoring: AnyObject` (§5.4), `final class LiveRatingPromptStore` com `init(defaults: UserDefaults = .standard, bundle: Bundle = .main)` e `final class FakeRatingPromptStore` com `init(isStoreInstall: Bool = false, currentVersion: String = "1.0.0", lastRequest: RatingPromptRecord? = nil)` | `avaliacao` | integrador |
| `RatingPromptPolicy`, `RatingPromptInput`, `RatingSessionEnding` (§5.4) | `avaliacao` | `avaliacao` |
| Nome do artefato do IPA `PersonalTrainer-for-resigning` e do arquivo `PersonalTrainer-iphone-only-for-resigning.ipa`; nome do workflow `App build (manual)` | `loja` | dono (guia da Amanda), `watch-ci` |

## 5. Tarefas

### 5.1 `loja` — manifesto de privacidade e `project.yml` da loja (T11.2 + T11.3 [PROJ])

**Escopo (exclusivo):** `project.yml`, `.github/workflows/app-build.yml`, `Scripts/build-app.sh` e o arquivo novo `PersonalTrainer/Resources/PrivacyInfo.xcprivacy`. Nada mais: nem `core-tests.yml`, nem `device-probe.yml`, nem os `.entitlements` (o HealthKit continua igual).

**Fazer:**
1. **`PrivacyInfo.xcprivacy`** (L1), plist XML com exatamente:
   - `NSPrivacyTracking` = `false`;
   - `NSPrivacyTrackingDomains` = array vazio;
   - `NSPrivacyCollectedDataTypes` = array vazio;
   - `NSPrivacyAccessedAPITypes` = um item: `NSPrivacyAccessedAPIType` = `NSPrivacyAccessedAPICategoryUserDefaults`, `NSPrivacyAccessedAPITypeReasons` = [`CA92.1`].

   O arquiteto conferiu em 2026-10-05: em `PersonalTrainer/`, `PersonalTrainerWatch/` e `Packages/TrainerCore/Sources` só aparece `UserDefaults`. Nenhuma API das outras categorias aparece: data de arquivo (`creationDate`, `modificationDate`, `attributesOfItem`, `resourceValues`), tempo desde o boot (`systemUptime`, `mach_absolute_time`), espaço em disco (`volumeAvailableCapacity…`, `systemFreeSize`) e teclados ativos (`activeInputModes`). Repita o grep antes de fechar (as outras tarefas desta onda não acrescentam nenhuma dessas APIs; o integrador confere de novo). Se achar outra, pare e reporte.
2. **`project.yml`:**
   - no target `PersonalTrainer`, sai a dependência `- target: PersonalTrainerWatch` e o comentário dela; no lugar, um comentário: o Watch fica fora do build do iPhone até o M3 (SPEC §7.18 L6). O target `PersonalTrainerWatch` continua no arquivo, sem mudança;
   - `MARKETING_VERSION: "1.0.0"` (L7). `CURRENT_PROJECT_VERSION` continua `"1"` (o número do build automático é da T11.7);
   - nas `info.properties` do iPhone: `ITSAppUsesNonExemptEncryption: false`;
   - `NSHealthShareUsageDescription` e `NSHealthUpdateUsageDescription` do iPhone: os textos do §6.3, exatos. Os do Watch ficam como estão;
   - nenhum bundle ID muda, nenhuma capability nova, nenhum `UIRequiredDeviceCapabilities`;
   - o `.xcprivacy` deve entrar sozinho na fase "Copy Bundle Resources", porque a pasta `PersonalTrainer` inteira é fonte e o XcodeGen manda para os recursos o que não é código. Se a checagem do passo 3 mostrar que ele não entrou, troque para entrada explícita: exclua o arquivo da fonte da pasta e acrescente `- path: PersonalTrainer/Resources/PrivacyInfo.xcprivacy` com `buildPhase: resources`.
3. **`app-build.yml`:**
   - comentário do topo: só o app do iPhone (L6);
   - no "Generate Xcode project", a checagem do Watch se inverte: falha (`::error::`) se o `project.pbxproj` tiver `Embed Watch Content`. As checagens `test -f` dos dois `Info.plist` gerados ficam;
   - passo novo, antes do XcodeGen e barato, **"Check L1: no network code"** (CA11-1): `grep -rnE 'URLSession|NWConnection|NSURLConnection|import Network' PersonalTrainer Packages --include='*.swift'` tem de voltar vazio, e o `project.yml` não pode ter pacote remoto (nenhuma linha `url:`, `from:`, `exactVersion:`, `branch:` ou `revision:` dentro de `packages:`);
   - passo novo, depois de "Keep test results for diagnosis" e só com os testes verdes, **"Check privacy manifest and Info.plist (L1, L6, L7)"** sobre o app do simulador (`build/app/DerivedData/Build/Products/Debug-iphonesimulator/PersonalTrainer.app`):
     - `PrivacyInfo.xcprivacy` na raiz do `.app`, `plutil -lint` ok, `NSPrivacyTracking` falso, os dois arrays vazios e `CA92.1` na categoria `UserDefaults`;
     - no `Info.plist`: `CFBundleShortVersionString` = `1.0.0` e `ITSAppUsesNonExemptEncryption` = `false`;
     - nenhuma pasta `Watch/` no `.app`.

     Use o `/usr/libexec/PlistBuddy`. Um array vazio dá erro em `Print :Chave:0`, e é assim que se confere. Cada falha sai como `::error title=…::`;
   - no "Keep package for local re-signing", sai a linha `build/app/PersonalTrainer-for-resigning.ipa` (com Watch); **o artefato continua `PersonalTrainer-for-resigning`**, com `PersonalTrainer-iphone-only-for-resigning.ipa`, `SHA256.txt`, `SOURCE_COMMIT.txt` e `XCODE_VERSION.txt`, `if-no-files-found: error` e `retention-days: 3`;
   - não mude o nome do workflow, os gatilhos, o `paths-ignore`, a política `PACKAGE_IPA`, o `concurrency` nem o runner.
4. **`Scripts/build-app.sh`:**
   - só o app do iPhone: saem as variáveis, as checagens, a assinatura e o IPA com o Watch. Ele falha se `$app/Watch` existir (L6);
   - checagens do `Info.plist` compilado:
     - `CFBundleIdentifier` = `com.personaltrainer.app`, como antes;
     - `CFBundleShortVersionString` = `1.0.0`;
     - `ITSAppUsesNonExemptEncryption` = `false`;
     - `NSHealthShareUsageDescription` não vazio, e `NSHealthUpdateUsageDescription` contendo "força" e "aeróbico" (CA11-6);
   - checagens do manifesto na raiz do `.app`: existe, `plutil -lint`, rastreamento falso, arrays vazios, `CA92.1`;
   - assinatura ad-hoc do app com `PersonalTrainer/Support/PersonalTrainer.entitlements`, como antes, e `codesign --verify --deep --strict`;
   - um IPA só, com o nome de sempre: `build/app/PersonalTrainer-iphone-only-for-resigning.ipa`. Conferências do zip:
     - tem `Payload/PersonalTrainer.app/Info.plist`, o executável, `_CodeSignature/CodeResources` e `Payload/PersonalTrainer.app/PrivacyInfo.xcprivacy`;
     - não tem nada em `Payload/PersonalTrainer.app/Watch/` nem `.mobileprovision`;
   - `SHA256.txt` (só desse IPA), `SOURCE_COMMIT.txt` e `XCODE_VERSION.txt`, como antes.
5. **CI:** a mensagem do commit da ponta de **cada** push para `ci/v10-loja` contém `[ipa]`. O run só está verde quando o passo "Build unsigned device IPA" rodou e o artefato saiu.

**Testes:** não há código Swift; os passos do CI são os testes (CA11-1, CA11-2, CA11-6).

**Entrega ao integrador:** nada a ligar. O `ci/v10-final` gera o IPA (termina em `-final`) e roda as checagens novas sobre o resultado da integração.

**Incerto (registre o que o CI confirmar):** a fase de recursos do `.xcprivacy` no XcodeGen; a saída do PlistBuddy para booleanos (`false`) e com acentos; se o `actool` ainda acrescenta os ícones ao `Info.plist` sem a dependência do Watch (deve, é do target do iPhone).

### 5.2 `sideload` — sem sideload no app (T11.4, L4) e "Bicicleta indoor" (L8)

**Escopo (exclusivo):**
- TrainerCore, em `Packages/TrainerCore/Sources/TrainerCore/`:
  - `Coach/CoachFeedBuilder.swift`, `Coach/CoachFeedBuilder+Rules.swift`, `Coach/CoachInput.swift`, `Coach/CoachRule.swift`, `Coach/CoachAction.swift` e `Coach/CoachMessage.swift`;
  - `Coach/ProvisioningProfileParser.swift` (**apagar**);
  - `Activities/OutsideActivityKind.swift` e `Activities/OutsideActivityRole.swift` (só os comentários com "spinning").
- Testes do TrainerCore, em `Packages/TrainerCore/Tests/TrainerCoreTests/`:
  - `CoachFeedTests.swift`, `CoachFixturesTests.swift`, `CoachRemindersTests.swift`, `CoachLogTests.swift` e `OutsideActivitiesTests.swift`;
  - `CoachProvisioningProfileParserTests.swift` (**apagar**);
  - novo `CoachInstallExpiryRemovedTests.swift`.
- Seed: `PersonalTrainer/Resources/Seed/references.v1.json`, só a palavra "spinning" no `summary` de `ainsworth-2011-compendium`, que vira "bicicleta indoor".
- App, em `PersonalTrainer/`:
  - `Services/Coach/CoachService.swift`, `CoachService+Actions.swift` e `CoachService+Input.swift`;
  - `Services/Coach/CoachService+Reminder.swift` (**apagar**) e o novo `Services/Coach/CoachService+LegacyReminder.swift`;
  - `Services/Coach/ProvisioningExpiryReader.swift` (**apagar**);
  - `Services/Notifications/NotificationScheduling.swift`, `LiveNotificationScheduler.swift` e `FakeNotificationScheduler.swift`;
  - `Features/Coach/RenewalHelpView.swift` (**apagar**), `Features/Coach/CoachHighlightSheet.swift` (só a preview), `Features/Coach/CoachPreviewData.swift` e `Features/Coach/CoachRule+Symbol.swift`;
  - `Features/Settings/SettingsView.swift`;
  - `PreviewSupport/HomePreviewSupport.swift` (só o `expiry:`).
- Testes do app, em `PersonalTrainerTests/Services/`: `CoachServiceTests.swift`, `CoachViewsTests.swift` e `SessionPlannerActivitiesTests.swift` (só o `expiry:`); `CoachExpiryReaderTests.swift` (**apagar**).

**Fazer:**
1. **TrainerCore (L4):**
   - `CoachInput` perde `provisioningExpiry` (propriedade, parâmetro e atribuição);
   - `CoachFeedBuilder` perde a chamada da C4 e `Priority.installExpiry`;
   - `CoachFeedBuilder+Rules` perde `expiryWarningDays` e `installExpiryMessage`;
   - apagar `ProvisioningProfileParser`;
   - `CoachRule.installExpiry` e `CoachAction.howToRenew` **ficam**, com o comentário "C4, removida na 2.5 (SPEC §7.18 L4): o case fica porque o raw value pode estar no log do diálogo; nunca é emitido nem oferecido". O `label` de `howToRenew` passa a ser `"Ok"`, para não sobrar o texto "Como renovar" no app;
   - os comentários de `CoachMessage`, `CoachFeedBuilder` e `CoachRule` deixam de citar a C4 como regra ativa (o exemplo de id `expiry:…`, "C4 and C1 come first" etc.).
2. **"Bicicleta indoor" (L8):**
   - `OutsideActivityKind.spinning.displayName` = `"Bicicleta indoor"`, com o raw value igual;
   - os comentários que dizem "spinning" passam a dizer "bicicleta indoor";
   - no `references.v1.json`, o resumo do compêndio diz "bicicleta indoor" no lugar de "spinning". Nenhuma outra mudança no arquivo.
3. **App (L4):**
   - `CoachService`:
     - perde o parâmetro `expiry:`, `provisioningExpiry`, `isExpiryReminderEnabled`, `setExpiryReminderEnabled(_:)`, `onRenewalHelpRequested`, `appliedReminder`, `ReminderState` e `expiryReminderHour`;
     - `FollowUp` perde `.renewalHelp`;
     - em `performEffect`, `.howToRenew` vai para o grupo "só o log" (`return nil`);
     - o comentário de uso para o integrador não cita mais a C4.
   - **Aviso antigo** (novo `CoachService+LegacyReminder.swift`):
     - as constantes `DefaultsKey.expiryReminderEnabled` (`"expiryReminderEnabled"`) e `expiryReminderIdentifier` (`"coach.expiryReminder"`) ficam, como legado;
     - no `refresh(…)`, no lugar do antigo `syncExpiryReminder`, `cancelLegacyExpiryReminderIfNeeded()`. Se `defaults.object(forKey: "expiryReminderEnabled") != nil`, ele apaga a chave e enfileira (`enqueue`, para os testes aguardarem `pendingWork?.value`) um `notifications.cancel(identifier: "coach.expiryReminder")`. Sem a chave, não faz nada. Assim cancela uma vez só, sem pedir permissão de notificação.
   - `NotificationScheduling`:
     - sai o requisito `scheduleReminder(at:identifier:title:body:)`, com o padrão da extensão, a implementação Live e a Fake;
     - o `FakeNotificationScheduler.ScheduledRequest` fica igual (o `title` opcional continua, sempre `nil`), porque outros testes leem esse formato;
     - os comentários deixam de citar a C4.
   - Apagar `ProvisioningExpiryReader.swift`, `CoachService+Reminder.swift` e `RenewalHelpView.swift`.
   - `CoachPreviewData`: sai a mensagem `expiry` (e de `all`). A preview do `CoachHighlightSheet` usa `.deload`. `CoachRule+Symbol` mantém o `case .installExpiry` (o `switch` precisa ser exaustivo), com o comentário "nunca exibida (L4)".
   - `SettingsView`:
     - sai a seção "Avisos" (`remindersSection`), o `isShowingRenewalHelp`, a folha da `RenewalHelpView` e o `expiryFooter`;
     - o comentário do topo deixa de citar "Avisos" e a validade;
     - o rodapé da seção Backup passa a ser o texto do §6.4;
     - as duas assinaturas de `init` ficam iguais (§4).
   - `HomePreviewSupport`, `SessionPlannerActivitiesTests`, `CoachViewsTests` e `CoachServiceTests` deixam de passar `expiry:`.
4. **Nenhum texto do app** (código e comentário) cita "Impactor" nem "Como renovar" depois da tarefa: `grep -rn "Impactor\|Como renovar\|RenewalHelp\|ProvisioningExpiry\|provisioningExpiry" PersonalTrainer Packages/TrainerCore/Sources --include=*.swift` volta vazio.

**Testes (R7):**
- **TrainerCore**, no novo `CoachInstallExpiryRemovedTests.swift` (`@Suite("L4 sem sideload no app")`):
  - `@Test("L4 o diálogo nunca gera a C4", arguments: …)`: com `CoachFixtures.fullInput()` e com o `CoachInput()` vazio, em vários `now` (constantes com tipo explícito), nenhuma mensagem tem `rule == .installExpiry` nem a ação `.howToRenew`;
  - `@Test("L4 nenhuma mensagem cita o Impactor nem a validade da instalação")`: título e motivo de todas as mensagens do `fullInput()`;
  - `@Test("L4 installExpiry e howToRenew continuam decodificáveis no log")`: um `CoachLog` gravado com esses raw values decodifica.
- **Ajustes nos testes do TrainerCore:**
  - `CoachFeedTests`: a lista dos destaques sem `.installExpiry`, e sem o `RuleCase` da C4;
  - `CoachFixturesTests`: `fullInput()` sem `provisioningExpiry`, com as contagens que dependiam dela ajustadas;
  - `CoachRemindersTests`: saem os testes da C4, e a suíte passa a "Coach — C5 a C8 lembretes";
  - `CoachLogTests`: os raw values continuam iguais; nos rótulos, `howToRenew` passa a `"Ok"`;
  - `OutsideActivitiesTests`: a linha de `.spinning` com o nome "Bicicleta indoor".
- **App:**
  - `testL4_legacyExpiryReminderIsCancelledOnce` (com a chave gravada: um `cancel("coach.expiryReminder")` e a chave apagada; no segundo `refresh`, nada);
  - `testL4_noLegacyKeyCancelsNothing`;
  - `testL4_howToRenewOnlyLogs` (responder `.howToRenew` a uma mensagem qualquer não navega nem pede permissão);
  - saem os testes da C4 e da `RenewalHelpView` (`CoachViewsTests`, `CoachServiceTests`) e o arquivo `CoachExpiryReaderTests.swift`.

**Entrega ao integrador:** nada a ligar (o andaime já tirou a C4 do `App/*`). O `CoachService.init` fica como no §4.

**Incerto:** se algum teste de outro arquivo usa `scheduleReminder` do Fake (o arquiteto não achou nenhum; se achar, pare e reporte); a ordem de `pendingWork` com o cancelamento enfileirado no primeiro `refresh`.

### 5.3 `sobre` — Sobre, Privacidade e textos do backup (T11.5, L2, L5)

**Escopo (exclusivo):**
- Em `PersonalTrainer/Features/Settings/`: `MoreOptionsView.swift`, `SettingsViewModel.swift` (só as duas mensagens do §6.4) e os novos `PrivacyView.swift`, `PrivacyText.swift` e `AppLinks.swift`.
- `PersonalTrainer/Features/Health/HealthProfileView.swift`: só o texto do §6.4.
- `PersonalTrainer/Services/Backup/BackupService.swift` (o nome do arquivo) e `BackupServicing.swift` (o comentário do nome).
- `PersonalTrainer/PreviewSupport/SettingsPreviewSupport.swift` (o nome do arquivo na preview).
- Testes: `PersonalTrainerTests/Services/BackupServiceTests.swift` (só o teste do nome), `PersonalTrainerTests/Features/SettingsViewModelTests.swift` (testes novos das mensagens) e o novo `PersonalTrainerTests/Features/PrivacyAboutTests.swift`.

**Fazer:**
1. **`AppLinks`** (enum, um lugar só para os endereços públicos, L2 e L3):
   - `static let privacyPolicyURL: URL? = nil`, `static let supportURL: URL? = nil` e `static let appStoreID: String? = nil` (o número que o App Store Connect dá ao app; T11.7 e T11.10);
   - `static func writeReviewURL(appStoreID: String?) -> URL?`, que monta `https://apps.apple.com/app/id<ID>?action=write-review` só quando o ID tem só dígitos e não é vazio; senão, `nil`;
   - `static var writeReviewURL: URL? { writeReviewURL(appStoreID: appStoreID) }`.

   Comentário: quando o dono tiver o site e o ID, só estas constantes mudam.
2. **`PrivacyText`** (enum com `static let`): todos os textos do §6.1 e §6.2, mais `static let all: [String]` com cada um deles, para os testes.
3. **`PrivacyView`**: a página "Privacidade" (L2), no mesmo visual de "Mais opções":
   - `Form` sem `NavigationStack` própria (a do `SettingsView` já existe), com `.navigationTitle("Privacidade")` e `.navigationBarTitleDisplayMode(.inline)`;
   - as seções e a ordem do §6.1;
   - os links da política e do suporte como `Link`, só quando a constante existe;
   - só leitura: nada grava, nada pede permissão.
4. **`MoreOptionsView`**, seção "Sobre", nesta ordem:
   - "Versão" (já existe);
   - `NavigationLink` "Privacidade" (símbolo `hand.raised`) para a `PrivacyView`;
   - `Link` "Avaliar o Magister" (símbolo `star`) para `AppLinks.writeReviewURL`, só quando ele não é `nil` (L3: item passivo; hoje não aparece);
   - no rodapé da seção, a linha fixa do aviso de saúde (L5, §6.2).

   As outras seções ficam como estão.
5. **Backup:**
   - `BackupService.suggestedFileName(now:)` devolve `Magister-backup-AAAA-MM-DD.json`, com o mesmo cálculo de data e fuso;
   - a importação já aceita qualquer `.json` (`fileImporter` com `[.json]`, nenhuma conferência de nome); confira e não mude;
   - as duas mensagens do `SettingsViewModel` e o texto do `HealthProfileView` passam aos do §6.4.

**Testes (R7):**
- `testL2_privacyTextsHaveNoAbsolutePromises`: nenhum texto de `PrivacyText.all`, em minúsculas, contém "100%", "100 %", "seguro", "garant", "nada sai", "aprovado pela apple", "lgpd", "validado", "impactor", "personal", "treinador", "coach" nem "icloud drive";
- `testL2_privacyTextsStateTheFacts`: os textos contêm "não coleta dados", "Acesso a Dados e Dispositivos", "Guarde-o num lugar só seu", "backup do iPhone no iCloud" e "app Saúde";
- `testL2_healthListsMatchPermissions`: o texto "Lê:" cita treinos, frequência cardíaca, VO2máx, variabilidade, repouso, sono, passos, data de nascimento e sexo; o texto "Grava:" cita força e aeróbico (os mesmos itens do §6.3);
- `testL3_writeReviewURLNeedsDigits`: `nil` → `nil`, `""` → `nil`, `"abc"` → `nil`, `"1234567890"` → `https://apps.apple.com/app/id1234567890?action=write-review`;
- `testL5_healthNoticeIsExact`;
- `testRF18_suggestedFileName_usesDayInConfiguredTimeZone`: passa a esperar `Magister-backup-2026-09-23.json` e `Magister-backup-2026-09-22.json`;
- em `SettingsViewModelTests`: `testL2_exportSuccessSuggestsAPlaceOfYourOwn` (a mensagem contém "Guarde-o num lugar só seu" e não contém "iCloud") e `testL2_importReadFailureHasNoICloud`.

**Entrega ao integrador:** nada a ligar (a "Mais opções" já é aberta pelo `SettingsView`).

**Incerto:** o `Link` dentro de `Form` com `Label` (aparência da linha); o símbolo `hand.raised` no iOS 18 (existe desde o iOS 14).

### 5.4 `avaliacao` — pedido de avaliação (T11.6, L3)

**Escopo (exclusivo):**
- TrainerCore: os novos `Packages/TrainerCore/Sources/TrainerCore/AppStore/RatingPromptPolicy.swift`, `RatingPromptInput.swift` e `RatingSessionEnding.swift` (pasta nova, já na ARCHITECTURE §17) e `Packages/TrainerCore/Tests/TrainerCoreTests/RatingPromptPolicyTests.swift`.
- App, os novos `PersonalTrainer/Services/RatingPrompt/RatingPromptStoring.swift`, `RatingPromptRecord.swift`, `LiveRatingPromptStore.swift`, `FakeRatingPromptStore.swift` e `RatingPromptGate.swift`.
- `PersonalTrainer/Services/HealthKit/HealthKitWorkoutRecorder.swift` e o novo `PersonalTrainer/Services/HealthKit/HealthRecordOutcome.swift`.
- `PersonalTrainer/Features/Session/SessionFlowView.swift` e `SessionSummaryView.swift`.
- Testes: o novo `PersonalTrainerTests/Services/RatingPromptTests.swift` e `PersonalTrainerTests/Services/HealthKitWorkoutRecorderTests.swift` (testes novos).

**TrainerCore (congelado):**
```swift
public enum RatingSessionEnding: String, Sendable, CaseIterable {
    case completed   // concluída nesta abertura da ficha, gravada, e o Saúde não falhou
    case abandoned   // "Sair sem registrar"
    case failed      // erro de gravação ou do Saúde
}

public struct RatingPromptInput: Sendable, Equatable {
    public var firstCompletedSessionStart: Date?
    public var completedSessionCount: Int        // inclui a sessão que acabou de terminar
    public var sessionEnding: RatingSessionEnding
    public var currentVersion: String            // CFBundleShortVersionString
    public var lastRequestVersion: String?
    public var lastRequestAt: Date?
    public var isStoreInstall: Bool
    public init(firstCompletedSessionStart: Date?, completedSessionCount: Int, sessionEnding: RatingSessionEnding,
                currentVersion: String, lastRequestVersion: String?, lastRequestAt: Date?, isStoreInstall: Bool)
}

public enum RatingPromptPolicy {
    public static let minimumDaysSinceFirstSession: Int = 7
    public static let minimumCompletedSessions: Int = 3
    public static let minimumDaysBetweenRequests: Int = 120
    public static let secondsPerDay: TimeInterval = 86_400
    public static func shouldRequest(_ input: RatingPromptInput, now: Date) -> Bool
    /// "Concluída" do L3: `status == .completed` e `workingSetCount > 0` (a mesma conta das Metas, W2).
    public static func countsAsCompleted(_ session: SessionSummary) -> Bool
    public static func firstCompletedSessionStart(in sessions: [SessionSummary]) -> Date?
    public static func completedSessionCount(in sessions: [SessionSummary]) -> Int
}
```
`shouldRequest` devolve `true` só quando valem todas:
- `isStoreInstall`;
- `sessionEnding == .completed`;
- `completedSessionCount >= 3`;
- `firstCompletedSessionStart` existe e `now.timeIntervalSince(first) >= 7 × 86 400`;
- `currentVersion`, sem espaços, não é vazio, e `lastRequestVersion != currentVersion`;
- `lastRequestAt == nil` ou `now.timeIntervalSince(last) >= 120 × 86 400`. Um `lastRequestAt` no futuro dá intervalo negativo e não pede.

Sem `Date()`, sem calendário, sem FC.

**App:**
```swift
/// SPEC §7.18 L3 (AGENTS R9). Live: UserDefaults + bundle; Fake: memória.
protocol RatingPromptStoring: AnyObject {
    func lastRequest() -> RatingPromptRecord?
    func recordRequest(_ record: RatingPromptRecord)
    var isStoreInstall: Bool { get }
    var currentVersion: String { get }
}
struct RatingPromptRecord: Equatable, Sendable { let version: String; let date: Date }
```
- **`LiveRatingPromptStore`** (`init(defaults: UserDefaults = .standard, bundle: Bundle = .main)`):
  - grava em `"ratingPromptLastVersion"` (String) e `"ratingPromptLastRequestAt"` (Double, `timeIntervalSince1970`). São as únicas chaves novas, já cobertas pelo `CA92.1` do manifesto;
  - `currentVersion` vem de `CFBundleShortVersionString` (vazio se faltar);
  - `isStoreInstall` é calculado uma vez no `init` por uma função pura `static func isStoreInstall(hasEmbeddedProfile: Bool, isSimulator: Bool) -> Bool` (`!hasEmbeddedProfile && !isSimulator`). O perfil é `bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil`, o mesmo arquivo que o leitor da C4 usava; o simulador sai de `#if targetEnvironment(simulator)`.
- **`FakeRatingPromptStore`** (§4): memória, com `private(set) var recorded: [RatingPromptRecord]`. A propriedade guardada do último pedido não pode se chamar `lastRequest`, porque conflita com o método `lastRequest()` do protocolo (use, por exemplo, `storedRequest`); o rótulo `lastRequest:` do `init` pode ficar.
- **`HealthKitWorkoutRecorder`** passa a guardar, por sessão, como terminou a ida ao Saúde. O enum `HealthRecordOutcome` tem `pending`, `notAttempted`, `saved` e `failed`, e `func healthOutcome(for sessionID: UUID) -> HealthRecordOutcome` responde assim:
  - `notAttempted`: o Saúde não está no aparelho ou não há permissão de gravar;
  - `saved`: gravou ou vinculou o treino;
  - `failed`: a gravação ou o `apply` do resumo deu erro;
  - `pending`: está gravando ou ainda não recebeu o `sessionFinished` (com o Saúde disponível).

  Nada mais muda no comportamento do gravador, e uma falha continua só no log (AGENTS §4).
- **`RatingPromptGate`** (`@MainActor`) junta o store, o `SessionPlanning` (`finishedSessionSummaries()`) e o gravador (opcional; `nil` vale `notAttempted`). Ele monta o `RatingPromptInput` da sessão que acabou de terminar e grava o pedido (`recordRequest` com `currentVersion` e `now`) quando pede. Uma falha de leitura do planejador vale "não pede", com log.
- **`SessionFlowView`** ganha o parâmetro do §4. O resumo só pode pedir quando veio do `onFinished` desta abertura (o caminho `showSummary()`) e a sessão está `completed`. Reabrir uma sessão já encerrada (`model.isFinished` ao abrir) nunca pede.
- **`SessionSummaryView`**:
  - recebe o necessário (o portão e se pode pedir; a assinatura é interna da tarefa) e usa `@Environment(\.requestReview)` (`import StoreKit`);
  - num `.task`, espera 2 s (`try await Task.sleep(for: .seconds(2))`). Se a tarefa for cancelada (a pessoa saiu), não pede;
  - se o Saúde está `pending`, espera de 0,5 em 0,5 s até 8 s a mais. Ainda `pending` ou `failed` vira `.failed`, e não pede;
  - se `RatingPromptPolicy.shouldRequest` deixa, chama `requestReview()` e grava o pedido;
  - nunca ao tocar num botão, nunca com texto próprio do app pedindo avaliação, sem incentivo e sem perguntar antes se a pessoa gostou (diretrizes 5.6.1 e 5.6.3).

**Testes (R7):**
- **TrainerCore**, `RatingPromptPolicyTests.swift`, tabela `@Test("L3 …", arguments: …)` com constantes de tipo explícito. Os casos:
  - pede com tudo cumprido;
  - 7 dias menos 1 s não pede, e 7 dias exatos pede;
  - 2 sessões não pede, e 3 pedem;
  - `abandoned` e `failed` não pedem;
  - sem primeira sessão não pede;
  - mesma versão não pede;
  - outra versão com 119 dias não pede, e com 120 pede;
  - nunca pediu pede;
  - fora da loja não pede;
  - versão vazia não pede;
  - último pedido no futuro não pede.

  Mais `@Test("L3 conta só sessões concluídas com série")` para `countsAsCompleted`, `firstCompletedSessionStart` e `completedSessionCount` (uma abandonada, uma concluída sem série, uma em andamento e duas concluídas).
- **App**, `RatingPromptTests.swift`:
  - `testL3_liveStoreRoundTrip` (suíte de `UserDefaults` própria, apagada no fim);
  - `testL3_storeInstallNeedsNoProfileAndDevice` (a função pura, nos 4 casos);
  - `testL3_gateAsksWhenAllConditionsHold`, `testL3_gateNeverAsksOutsideStore`, `testL3_gateNeverAsksAfterAbandon`, `testL3_gateRecordsVersionAndDate` e `testL3_gateSameVersionDoesNotAskAgain`, com o `FakeRatingPromptStore` e sessões criadas só pelo caminho oficial (planner e coordinator, R4).
- **App**, `HealthKitWorkoutRecorderTests.swift`: `testL3_outcomeSavedAfterRecording`, `testL3_outcomeFailedWhenSaveFails`, `testL3_outcomeNotAttemptedWithoutHealth` e `testL3_outcomePendingBeforeEvent`, com o `FakeHealthKitService`.

**Entrega ao integrador:** `LiveRatingPromptStore()`; o parâmetro `ratingPrompt:` do `SessionFlowView`.

**Incerto:** a heurística do perfil embutido (não é API documentada; o TestFlight não tem perfil, mas o iOS ignora o pedido ali); `RequestReviewAction` no Swift 6 (`@MainActor`, `callAsFunction`); `Task.sleep(for:)` lançando `CancellationError` quando a view some; o tempo da gravação no Saúde.

## 6. Guia de textos (TEXT_GUIDE)

Exatos. Uma mudança, só de pontuação ou para caber, e registrada em "Incerto".

### 6.1 Página "Privacidade" (L2; `PrivacyText`, na ordem)

Título: **Privacidade**

Sem cabeçalho:
- `intro`: "O Magister não coleta dados: não tem conta, anúncios, rastreamento nem ferramentas de análise. Quem fez o app não recebe nada do que você registra."

Seção **No iPhone**:
- `deviceData`: "Seus treinos, planos, atividades e ajustes ficam no iPhone."
- `deletingApp`: "Apagar o app apaga os dados dele no iPhone. Os treinos já gravados no app Saúde ficam lá até você apagá-los no Saúde."

Seção **App Saúde**:
- `health`: "O Magister lê e grava só se você permitir e usa esses dados apenas no aparelho. Para mudar, vá em Ajustes do iPhone › Saúde › Acesso a Dados e Dispositivos."
- `healthReads`: "Lê: treinos, frequência cardíaca, VO2máx, variabilidade da frequência cardíaca, frequência cardíaca em repouso, sono, passos, data de nascimento e sexo (os dois últimos são opcionais)."
- `healthWrites`: "Grava: cada sessão concluída, as de força como treino de força e as de aeróbico como treino aeróbico."

Seção **Backup**:
- `backup`: "O arquivo só é criado quando você pede e vai para onde você escolher. Ele traz seus treinos e alguns dados de saúde, como a frequência cardíaca média. Guarde-o num lugar só seu."
- `deviceBackup`: "Se o backup do iPhone no iCloud estiver ligado, a Apple inclui os dados do app nele, como faz com qualquer app."

Seção **Links**:
- `referenceLinks`: "Os links das referências abrem no navegador do iPhone."
- `policyLink` "Política de privacidade" e `supportLink` "Suporte" (rótulos dos `Link`, só com a URL).

### 6.2 Seção "Sobre" (L5, L3)

- `aboutPrivacy`: "Privacidade".
- `rateApp`: "Avaliar o Magister" (só com o ID do app).
- `healthNotice`, no rodapé: "O Magister não substitui a orientação de um médico ou de um profissional de educação física."

### 6.3 `Info.plist` do iPhone (`loja`)

- `NSHealthShareUsageDescription`: "O Magister lê do app Saúde seus treinos, frequência cardíaca, VO2máx, variabilidade da frequência cardíaca, frequência cardíaca em repouso, sono, passos e data de nascimento e sexo (opcionais) para mostrar o resumo de cada sessão, seus minutos de aeróbico e sua recuperação. Ele usa esses dados apenas no aparelho."
- `NSHealthUpdateUsageDescription`: "O Magister grava no app Saúde cada sessão concluída: as de força como treino de força e as de aeróbico como treino aeróbico."

### 6.4 Outros textos que mudam

| Onde | Antes | Depois | Dono |
|---|---|---|---|
| `SettingsView`, rodapé de Backup | "Os dados ficam só neste iPhone. Exporte um backup para o app Arquivos antes de reinstalar ou apagar o app. Importar substitui tudo o que está aqui." | "Seus treinos ficam no iPhone. Exporte um backup antes de reinstalar ou apagar o app e guarde-o num lugar só seu. Importar substitui tudo o que está aqui." | `sideload` |
| `SettingsViewModel`, backup salvo | "\(nome) foi salvo. Guarde-o fora do iPhone (iCloud Drive ou computador) antes de reinstalar o app." | "\(nome) foi salvo. Guarde-o num lugar só seu antes de reinstalar ou apagar o app." | `sobre` |
| `SettingsViewModel`, arquivo ilegível | "O arquivo escolhido não pôde ser lido. Verifique se ele terminou de baixar do iCloud Drive." | "O arquivo escolhido não pôde ser lido. Confira se ele terminou de baixar e tente de novo." | `sobre` |
| `HealthProfileView`, rodapé | "Estes dados ficam só neste aparelho, servem apenas ao painel de saúde e nunca mudam a carga da musculação." | "O Magister usa estes dados só no aparelho, no painel de saúde, e eles nunca mudam a carga da musculação." | `sobre` |
| `BackupService`, nome sugerido | `PersonalTrainer-backup-AAAA-MM-DD.json` | `Magister-backup-AAAA-MM-DD.json` | `sobre` |
| `OutsideActivityKind.spinning` | "Spinning ou bicicleta" | "Bicicleta indoor" | `sideload` |
| `references.v1.json`, resumo do compêndio | "…e spinning, futebol e circuito, no vigoroso." | "…e bicicleta indoor, futebol e circuito, no vigoroso." | `sideload` |
| `CoachAction.howToRenew.label` | "Como renovar" | "Ok" (nunca exibido) | `sideload` |

Saem do app: "Avisos", "Avisar na véspera de o app expirar", "Como renovar", "O app expira…", todo texto com "Impactor" e o rodapé da validade da instalação (`sideload`).

## 7. Integração (`v10/integration` → `ci/v10-final`)

1. Do worktree `C:\Users\leona\Developer\pt-wt\w10-integration` (branch `v10/integration`, no mesmo sha base), junte `v10/loja`, `v10/sideload`, `v10/sobre` e `v10/avaliacao`, nessa ordem, com `git merge --no-ff`. Os escopos são disjuntos: não se espera conflito de código. Se aparecer, resolva mantendo as duas mudanças e registre.
2. **Ligações** (só o integrador mexe no `App/*`):
   - `AppEnvironment.swift`: `let ratingPrompt: any RatingPromptStoring`, como último parâmetro do `init`, com padrão `FakeRatingPromptStore()`;
   - `AppEnvironment+Factories.swift`: o app passa `LiveRatingPromptStore()`; a preview fica com o Fake;
   - `RootView.swift`: `SessionFlowView(sessionID: presented.id, environment: environment, onClose: { … }, ratingPrompt: environment.ratingPrompt)`.
3. **Conferências** (todas com saída vazia, salvo a última):
   - CA11-1: `grep -rnE "URLSession|NWConnection|NSURLConnection|import Network" PersonalTrainer Packages --include=*.swift`;
   - CA11-3: `grep -rn "Impactor\|Como renovar\|RenewalHelp\|ProvisioningExpiry\|provisioningExpiry\|expiryReminderEnabled\b" PersonalTrainer Packages/TrainerCore/Sources --include=*.swift`. A exceção é o legado do `CoachService+LegacyReminder.swift`, que só pode citar a chave e o identificador antigos;
   - L8: `grep -rniE "\"[^\"]*(personal|treinador|coach|validad[oa] cientifica)[^\"]*\"" PersonalTrainer/Features PersonalTrainer/Services Packages/TrainerCore/Sources --include=*.swift`. Ignore chaves técnicas (`subsystem`, `category`, nomes de arquivo `PersonalTrainer…`, chaves `coach…` de `UserDefaults` e `Personalizado`), e só textos visíveis contam;
   - L2: nenhum texto visível sugere o iCloud Drive (`grep -rn "iCloud Drive" PersonalTrainer --include=*.swift`);
   - manifesto: o grep das APIs de motivo obrigatório do §5.1 ainda só acha `UserDefaults`.
4. **Testes cruzados:**
   - `testL3_previewEnvironmentNeverAsks`: `AppEnvironment.preview().ratingPrompt.isStoreInstall == false`;
   - os que as tarefas listaram em "Para o integrador".
5. **CI:** `git push origin HEAD:ci/v10-final` (o IPA sai sozinho no `-final`), `Expected` 2 (App build e Core tests). Confira no run que o artefato `PersonalTrainer-for-resigning` tem só o `PersonalTrainer-iphone-only-for-resigning.ipa` e que os passos L1 do §5.1 passaram.
6. **Estado:** depois do verde, o integrador marca T11.2–T11.6 e CA11-1 a CA11-6 no TASKS, com o run, e acrescenta ao HANDOFF §5f o run do IPA. A revisão estática adversarial e o corretor vêm depois, como nas versões anteriores; o merge no `main` é do corretor.

## 8. Critérios de aceitação desta fase

| CA | Como fecha | Tarefa |
|---|---|---|
| CA11-1 | Passo "Check L1: no network code" do App build, verde no `ci/v10-final`, e o grep do §7 | `loja`, integrador |
| CA11-2 | Checagens do manifesto no app do simulador (todo run) e no IPA (`build-app.sh`), verdes no `ci/v10-final` | `loja` |
| CA11-3 | Testes "L4 …" e `testL4_…` verdes, e o grep do §7 vazio | `sideload` |
| CA11-4 | Sobre com Versão, Privacidade e o aviso de saúde (L5), e os testes `testL2_…` e `testL5_…` verdes | `sobre` |
| CA11-5 | Testes "L3 …" e `testL3_…` verdes | `avaliacao` |
| CA11-6 | `build-app.sh` confere sem Watch, a versão 1.0.0, `ITSAppUsesNonExemptEncryption` falso e o texto de gravação com "força" e "aeróbico" | `loja` |

## 9. Incertezas conhecidas

- **XcodeGen e `.xcprivacy`:** o arquivo deve cair em "Copy Bundle Resources" por ser um arquivo que não é código. Só o CI confirma; o §5.1 traz a saída se não cair.
- **App Store Connect:** a validação da loja (ícones, `Info.plist`, manifesto, criptografia) só roda no envio, na T11.7. As checagens desta fase cobrem o que dá para ver sem enviar.
- **Watch parado:** sem a dependência, o target do Watch não compila em nenhum run até o M3. O código dele pode envelhecer; o M3 começa com um build dele.
- **"Instalado pela loja":** o app usa a falta do `embedded.mobileprovision` fora do simulador. É prática comum, mas não é API documentada. O `AppTransaction` (StoreKit 2) foi descartado: pode ir à rede da Apple e, em casos raros, pedir login, o contrário do "menos invasivo".
- **O iOS decide se a caixa de avaliação aparece** (no máximo 3 vezes por ano por app) e não conta ao app; a regra registra o pedido (L3).
- **Tempo do Saúde:** a gravação pode passar de 2 s; o app espera até 10 s no total e, sem resposta, não pede nesta sessão.
- **Limite da API do GitHub:** 60 pedidos por hora por IP, sem login. Com 4 agentes ao mesmo tempo, o `watch-ci` pode ficar mudo por um tempo (§0).

## 10. Decisões do arquiteto (onde o pedido não dizia, ou divergia)

1. **Rótulo do item de avaliação:** a SPEC (L3) e o TASKS dizem "Avaliar o Magister"; o pedido da fase dizia "Avaliar na App Store". Vale a SPEC, que é a fonte de verdade. Trocar é uma linha em `PrivacyText.rateApp`, se o dono preferir.
2. **"Os links das referências abrem no navegador do iPhone"**, e não "no Safari": a pessoa pode ter outro navegador padrão, e o `Link` abre no padrão. Fato mantido, palavra ajustada.
3. **"Seus treinos, planos, atividades e ajustes ficam no iPhone"**: o texto aprovado dizia "Seus treinos"; a L2 pede a lista do que fica no aparelho.
4. **Um andaime no `main`** (§3) em vez de deixar o `RootView` para a `sideload`: o pedido manda o `App/*` para o integrador, e sem o andaime o branch da `sideload` não compilaria sozinho.
5. **O item "Avaliar o Magister" fica com a `sobre`**, porque o `MoreOptionsView` é dela; a `avaliacao` não toca nesse arquivo.
6. **O rodapé do backup no Ajustes fica com a `sideload`**, dona do `SettingsView` (ela já tira a seção "Avisos" do mesmo arquivo).
7. **A palavra "spinning" também sai do resumo do compêndio** no `references.v1.json`: é a mesma marca de terceiros do `displayName`.
8. **`CoachAction.howToRenew.label` vira "Ok"**: o case fica (persistido), mas o texto "Como renovar" sai do app.
9. **(c) da L3 inclui o Saúde** com um estado por sessão no `HealthKitWorkoutRecorder`, porque a SPEC pede "sem erro de gravação nem do Saúde" e hoje o gravador só escreve no log. Sem permissão de gravar não é erro.
10. **Textos que diziam "ficam só neste iPhone/aparelho"** (Ajustes, perfil de saúde, permissão de leitura do Saúde) passam a dizer o fato sem absoluto, pela L1 ("nenhum texto diz 'nada sai do iPhone'").
