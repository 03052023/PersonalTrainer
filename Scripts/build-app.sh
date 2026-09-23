#!/usr/bin/env bash
# Build de dispositivo do app iPhone com o companion watchOS embutido, sem assinatura Apple,
# seguido de assinatura ad-hoc (preserva os entitlements HealthKit dos dois bundles) e
# empacotamento em IPA para reassinatura local (ARCHITECTURE ADR 008). Mesmo padrão de
# Scripts/build-device-probe.sh. Uso no runner macOS: bash Scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
output="$root/build/app"
derived="$output/DerivedData"
project="PersonalTrainer.xcodeproj"
scheme="PersonalTrainer"
app_name="PersonalTrainer"
watch_name="PersonalTrainerWatch"
app_bundle_id="com.personaltrainer.app"
watch_bundle_id="com.personaltrainer.app.watchkitapp"
app_entitlements="PersonalTrainer/Support/PersonalTrainer.entitlements"
watch_entitlements="PersonalTrainerWatch/Support/PersonalTrainerWatch.entitlements"
ipa_name="PersonalTrainer-for-resigning.ipa"
plist_buddy="/usr/libexec/PlistBuddy"

mkdir -p "$output"

if [ ! -d "$project" ]; then
  echo "==> $project ausente; gerando com XcodeGen"
  xcodegen generate --spec project.yml
fi
test -f "$app_entitlements"
test -f "$watch_entitlements"

echo "==> Xcode"
xcodebuild -version

echo "==> Build Release para generic/platform=iOS (sem assinatura)"
xcodebuild -project "$project" -scheme "$scheme" -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

app="$derived/Build/Products/Release-iphoneos/$app_name.app"
watch="$app/Watch/$watch_name.app"
if [ ! -f "$app/$app_name" ]; then
  echo "Executável do iPhone não encontrado: $app/$app_name"
  exit 1
fi
if [ ! -f "$watch/$watch_name" ]; then
  echo "Watch app não embutido em Watch/: $watch"
  find "$app" -maxdepth 2 -type d
  exit 1
fi

# --- Sanidade dos Info.plist compilados (CA0-4 e exigências do instalador) -------------------
plist_value() { "$plist_buddy" -c "Print :$2" "$1"; }
expect_plist() {
  local actual
  actual="$(plist_value "$1" "$2")"
  if [ "$actual" != "$3" ]; then
    echo "Info.plist: $2 = '$actual' (esperado '$3') em $1"
    exit 1
  fi
}
echo "==> Verificando Info.plist"
expect_plist "$app/Info.plist" CFBundleIdentifier "$app_bundle_id"
expect_plist "$watch/Info.plist" CFBundleIdentifier "$watch_bundle_id"
expect_plist "$watch/Info.plist" WKApplication true
expect_plist "$watch/Info.plist" WKCompanionAppBundleIdentifier "$app_bundle_id"
expect_plist "$watch/Info.plist" WKRunsIndependentlyOfCompanionApp false
if ! plist_value "$watch/Info.plist" WKBackgroundModes | grep -q 'workout-processing'; then
  echo "WKBackgroundModes do watch app não contém workout-processing"
  exit 1
fi
for plist in "$app/Info.plist" "$watch/Info.plist"; do
  for key in NSHealthShareUsageDescription NSHealthUpdateUsageDescription; do
    if [ -z "$(plist_value "$plist" "$key")" ]; then
      echo "$key vazio em $plist"
      exit 1
    fi
  done
done
# Um NSExtension residual faz o instalador exigir o watch app em PlugIns/ em vez de Watch/.
if "$plist_buddy" -c 'Print :NSExtension' "$watch/Info.plist" >/dev/null 2>&1; then
  echo "NSExtension presente no Info.plist do watch app"
  exit 1
fi

# --- Assinatura ad-hoc, de dentro para fora (--deep é obsoleto para assinar) -----------------
# Não é uma assinatura Apple de provisionamento e não instala como está: serve para carregar os
# entitlements HealthKit até a reassinatura local com a conta do usuário.
sign_adhoc() {
  if [ -n "${2:-}" ]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$2" "$1"
  else
    codesign --force --sign - --timestamp=none "$1"
  fi
}
echo "==> Assinatura ad-hoc"
shopt -s nullglob
for item in "$watch"/Frameworks/*; do sign_adhoc "$item"; done
sign_adhoc "$watch" "$watch_entitlements"
for item in "$app"/Frameworks/*; do sign_adhoc "$item"; done
sign_adhoc "$app" "$app_entitlements"
shopt -u nullglob
codesign --verify --deep --strict "$app"
echo "==> Entitlements do watch app"
codesign -d --entitlements - "$watch"
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
  "Payload/$app_name.app/Watch/$watch_name.app/Info.plist" \
  "Payload/$app_name.app/Watch/$watch_name.app/$watch_name" \
  "Payload/$app_name.app/Watch/$watch_name.app/_CodeSignature/CodeResources"; do
  if ! printf '%s\n' "$entries" | grep -qxF "$required"; then
    echo "IPA sem $required"
    exit 1
  fi
done
if printf '%s\n' "$entries" | grep -q '\.mobileprovision$'; then
  echo "IPA contém perfil de provisionamento; o artefato do CI não pode carregar credenciais Apple"
  exit 1
fi

# --- Variante só iPhone (sem Watch/) ----------------------------------------------------------
# Ferramentas de sideload sem suporte a companion (ex.: Impactor, AltStore) rejeitam ou tratam mal
# um IPA com Watch/ (WINDOWS_SETUP.md §4, plano B). Mesmo app, sem o relógio, reassinado ad-hoc
# com os mesmos entitlements HealthKit para a reassinatura local.
iphone_ipa="PersonalTrainer-iphone-only-for-resigning.ipa"
echo "==> Empacotando variante só iPhone"
stage="$(mktemp -d "$output/package.XXXXXX")"
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/$app_name.app"
rm -rf "$stage/Payload/$app_name.app/Watch"
sign_adhoc "$stage/Payload/$app_name.app" "$app_entitlements"
codesign --verify --deep --strict "$stage/Payload/$app_name.app"
rm -f "$output/$iphone_ipa"
ditto -c -k --keepParent "$stage/Payload" "$output/$iphone_ipa"
rm -rf "$stage"
iphone_entries="$(unzip -Z1 "$output/$iphone_ipa")"
if printf '%s\n' "$iphone_entries" | grep -q "^Payload/$app_name.app/Watch/"; then
  echo "Variante só iPhone ainda contém Watch/"
  exit 1
fi
if ! printf '%s\n' "$iphone_entries" | grep -qxF "Payload/$app_name.app/$app_name"; then
  echo "Variante só iPhone sem o executável do app"
  exit 1
fi

(cd "$output" && shasum -a 256 "$ipa_name" "$iphone_ipa" > SHA256.txt)
git rev-parse HEAD > "$output/SOURCE_COMMIT.txt"
xcodebuild -version > "$output/XCODE_VERSION.txt"
echo "==> Pronto: $output/$ipa_name e $output/$iphone_ipa"
cat "$output/SHA256.txt"
