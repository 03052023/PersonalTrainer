#!/usr/bin/env bash
# Build de dispositivo do app do iPhone, sem assinatura Apple, seguido de assinatura ad-hoc (preserva o
# entitlement HealthKit) e empacotamento em IPA para reassinatura local (ARCHITECTURE ADR 008). Mesmo
# padrão de Scripts/build-device-probe.sh. Uso no runner macOS: bash Scripts/build-app.sh
#
# Só o iPhone (SPEC §7.18 L6): o app do Watch fica fora do build até o M3, então o .app não pode ter
# Watch/. O IPA mantém o nome `PersonalTrainer-iphone-only-for-resigning.ipa`, que o guia de instalação cita.
# As mesmas checagens de manifesto, versão e criptografia rodam no passo "Check privacy manifest and
# Info.plist" do app-build.yml, sobre o app do simulador (CA11-2, CA11-6).
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
output="$root/build/app"
derived="$output/DerivedData"
project="PersonalTrainer.xcodeproj"
scheme="PersonalTrainer"
app_name="PersonalTrainer"
app_bundle_id="com.personaltrainer.app"
app_entitlements="PersonalTrainer/Support/PersonalTrainer.entitlements"
ipa_name="PersonalTrainer-iphone-only-for-resigning.ipa"
expected_version="1.0.0"
plist_buddy="/usr/libexec/PlistBuddy"

# `error:` no começo da linha: o passo "Report failures as annotations" do app-build.yml a vira anotação.
die() {
  echo "error: $*" >&2
  exit 1
}

mkdir -p "$output"
# Nome do IPA com o Watch, que não existe mais: não deixa um arquivo velho ao lado do novo.
rm -f "$output/PersonalTrainer-for-resigning.ipa"

if [ ! -d "$project" ]; then
  echo "==> $project ausente; gerando com XcodeGen"
  xcodegen generate --spec project.yml
fi
test -f "$app_entitlements"

echo "==> Xcode"
xcodebuild -version

echo "==> Build Release para generic/platform=iOS (sem assinatura)"
xcodebuild -project "$project" -scheme "$scheme" -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

app="$derived/Build/Products/Release-iphoneos/$app_name.app"
if [ ! -f "$app/$app_name" ]; then
  find "$app" -maxdepth 2 -type d || true
  die "Executável do iPhone não encontrado: $app/$app_name"
fi
# L6: sem o app do Watch no .app (o project.yml não tem a dependência até o M3).
if [ -e "$app/Watch" ]; then
  find "$app" -maxdepth 2 -type d || true
  die "O .app tem a pasta Watch/: o iPhone não pode embutir o app do relógio até o M3 (SPEC L6)"
fi

# --- Sanidade do Info.plist compilado (L1, L7, CA11-6 e exigências do instalador) -------------
# Chave ausente vira texto vazio, e o erro mostra o valor encontrado. Booleano sai como true/false.
plist_value() { "$plist_buddy" -c "Print :$2" "$1" 2>/dev/null || true; }
expect_plist() {
  local actual
  actual="$(plist_value "$1" "$2")"
  if [ "$actual" != "$3" ]; then
    die "Info.plist: $2 = '$actual' (esperado '$3') em $1"
  fi
}
echo "==> Verificando Info.plist"
expect_plist "$app/Info.plist" CFBundleIdentifier "$app_bundle_id"
expect_plist "$app/Info.plist" CFBundleShortVersionString "$expected_version"
expect_plist "$app/Info.plist" ITSAppUsesNonExemptEncryption false
if [ -z "$(plist_value "$app/Info.plist" NSHealthShareUsageDescription)" ]; then
  die "NSHealthShareUsageDescription vazio em $app/Info.plist"
fi
health_update="$(plist_value "$app/Info.plist" NSHealthUpdateUsageDescription)"
# O texto de gravação cita as sessões de força e as de aeróbico (RF-13; CA11-6).
case "$health_update" in
  *"força"*) ;;
  *) die "NSHealthUpdateUsageDescription não cita 'força': '$health_update'" ;;
esac
case "$health_update" in
  *"aeróbico"*) ;;
  *) die "NSHealthUpdateUsageDescription não cita 'aeróbico': '$health_update'" ;;
esac

# --- Manifesto de privacidade na raiz do .app (L1, CA11-2) -------------------------------------
# Um array vazio dá erro em `Print :Chave:0`; é assim que se confere que ele está vazio.
expect_empty_array() {
  "$plist_buddy" -c "Print :$2" "$1" >/dev/null 2>&1 || die "$2 ausente em $1 (esperado um array vazio)"
  if "$plist_buddy" -c "Print :$2:0" "$1" >/dev/null 2>&1; then
    die "$2 tem itens em $1 (esperado um array vazio)"
  fi
}
echo "==> Verificando o manifesto de privacidade"
manifest="$app/PrivacyInfo.xcprivacy"
if [ ! -f "$manifest" ]; then
  ls "$app" || true
  die "PrivacyInfo.xcprivacy não está na raiz de $app (fase Copy Bundle Resources do XcodeGen)"
fi
plutil -lint "$manifest" || die "plutil -lint rejeitou $manifest"
expect_plist "$manifest" NSPrivacyTracking false
expect_empty_array "$manifest" NSPrivacyTrackingDomains
expect_empty_array "$manifest" NSPrivacyCollectedDataTypes
# Motivo CA92.1 (dados só do próprio app) na categoria UserDefaults.
found_reason=false
i=0
while category="$(plist_value "$manifest" "NSPrivacyAccessedAPITypes:$i:NSPrivacyAccessedAPIType")"; [ -n "$category" ]; do
  if [ "$category" = "NSPrivacyAccessedAPICategoryUserDefaults" ]; then
    j=0
    while reason="$(plist_value "$manifest" "NSPrivacyAccessedAPITypes:$i:NSPrivacyAccessedAPITypeReasons:$j")"; [ -n "$reason" ]; do
      if [ "$reason" = "CA92.1" ]; then found_reason=true; fi
      j=$((j + 1))
    done
  fi
  i=$((i + 1))
done
if [ "$found_reason" != "true" ]; then
  die "O manifesto não declara NSPrivacyAccessedAPICategoryUserDefaults com o motivo CA92.1"
fi

# --- Assinatura ad-hoc, de dentro para fora (--deep é obsoleto para assinar) -----------------
# Não é uma assinatura Apple de provisionamento e não instala como está: serve para carregar o
# entitlement HealthKit até a reassinatura local com a conta do usuário.
sign_adhoc() {
  if [ -n "${2:-}" ]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$2" "$1"
  else
    codesign --force --sign - --timestamp=none "$1"
  fi
}
echo "==> Assinatura ad-hoc"
shopt -s nullglob
for item in "$app"/Frameworks/*; do sign_adhoc "$item"; done
sign_adhoc "$app" "$app_entitlements"
shopt -u nullglob
codesign --verify --deep --strict "$app"
echo "==> Entitlements do app iPhone"
codesign -d --entitlements - "$app"

# --- IPA (Payload/) ---------------------------------------------------------------------------
echo "==> Empacotando IPA"
stage="$(mktemp -d "$output/package.XXXXXX")"
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/$app_name.app"
rm -f "$output/$ipa_name"
ditto -c -k --keepParent "$stage/Payload" "$output/$ipa_name"
rm -rf "$stage"

echo "==> Verificando conteúdo do IPA"
entries="$(unzip -Z1 "$output/$ipa_name")"
for required in \
  "Payload/$app_name.app/Info.plist" \
  "Payload/$app_name.app/$app_name" \
  "Payload/$app_name.app/_CodeSignature/CodeResources" \
  "Payload/$app_name.app/PrivacyInfo.xcprivacy"; do
  if ! printf '%s\n' "$entries" | grep -qxF "$required"; then
    die "IPA sem $required"
  fi
done
if printf '%s\n' "$entries" | grep -q "^Payload/$app_name.app/Watch/"; then
  die "IPA com conteúdo em Payload/$app_name.app/Watch/ (SPEC L6)"
fi
if printf '%s\n' "$entries" | grep -q '\.mobileprovision$'; then
  die "IPA contém perfil de provisionamento; o artefato do CI não pode carregar credenciais Apple"
fi

(cd "$output" && shasum -a 256 "$ipa_name" > SHA256.txt)
git rev-parse HEAD > "$output/SOURCE_COMMIT.txt"
xcodebuild -version > "$output/XCODE_VERSION.txt"
echo "==> Pronto: $output/$ipa_name"
cat "$output/SHA256.txt"
