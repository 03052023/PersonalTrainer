#!/usr/bin/env bash
# Verifica as fronteiras do pacote TrainerCore (AGENTS.md R1–R3; TASKS.md T0.10; CA0-6).
# Uso: bash Scripts/check-boundaries.sh   → sai com 1 se alguma regra for violada.
set -euo pipefail
cd "$(dirname "$0")/.."

sources="Packages/TrainerCore/Sources"
engine="Packages/TrainerCore/Sources/TrainerCore/Engine"
failures=0

# check <regra> <descrição> <diretório> <opções e padrão do grep…>
# grep devolve 0 quando encontra algo (violação), 1 quando nada casa e ≥ 2 em erro.
check() {
  local rule="$1" description="$2" directory="$3"
  shift 3
  local matches status
  if matches="$(grep -rn --include='*.swift' "$@" "$directory")"; then
    status=0
  else
    status=$?
  fi
  case "$status" in
    0)
      printf '[FALHA] %s — %s\n%s\n\n' "$rule" "$description" "$matches"
      failures=$((failures + 1))
      ;;
    1)
      printf '[OK]    %s — %s\n' "$rule" "$description"
      ;;
    *)
      printf '[ERRO]  grep saiu com %s ao verificar %s\n' "$status" "$rule"
      exit 2
      ;;
  esac
}

if [ ! -d "$sources" ]; then
  echo "Diretório não encontrado: $sources"
  exit 2
fi

# R1: TrainerCore só importa Foundation.
check R1 "nenhum import de SwiftData/HealthKit/UIKit/SwiftUI/WatchConnectivity/WatchKit em $sources" \
  "$sources" -E 'import (SwiftData|HealthKit|UIKit|SwiftUI|WatchConnectivity|WatchKit)'

if [ -d "$engine" ]; then
  # R3: o motor não chama Date(); `now` é parâmetro. Padrão equivalente a \bDate\(\) que também
  # funciona no grep BSD do macOS (que não garante suporte a \b).
  check R3 "nenhuma chamada a Date() em $engine" \
    "$engine" -E '(^|[^A-Za-z0-9_])Date\(\)'
  # R2 / SPEC P12: nenhuma métrica de frequência cardíaca entra no motor.
  check R2 "nenhuma referência a frequência cardíaca em $engine" \
    "$engine" -iE 'heartRate|heart_rate|bpm'
else
  echo "[AVISO] $engine ainda não existe; R2 e R3 serão verificadas quando o motor entrar (T0.3/T0.4)."
fi

if [ "$failures" -gt 0 ]; then
  echo
  echo "check-boundaries: $failures violação(ões) de fronteira."
  exit 1
fi
echo "check-boundaries: OK."
