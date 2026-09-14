#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
factory_python=""
for factory_candidate in python3 python; do
  if command -v "$factory_candidate" >/dev/null 2>&1 && "$factory_candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
    factory_python="$factory_candidate"
    break
  fi
done
if [[ -z "$factory_python" ]]; then
  printf '%s\n' 'Python 3.10 or newer is required.' >&2
  exit 1
fi
factory_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|-p)
      [[ $# -ge 2 ]] || { printf '%s\n' 'Missing project path.' >&2; exit 2; }
      factory_project="$2"
      if command -v cygpath >/dev/null 2>&1; then
        factory_project="$(cygpath -m "$factory_project")"
      elif command -v wslpath >/dev/null 2>&1 && [[ "$factory_project" =~ ^[A-Za-z]: ]]; then
        factory_project="$(wslpath -u "$factory_project")"
      fi
      factory_args+=(--project "$factory_project")
      shift 2
      ;;
    --model|-m|--skills|-s)
      [[ $# -ge 2 ]] || { printf '%s\n' 'Missing option value.' >&2; exit 2; }
      case "$1" in
        --model|-m) factory_args+=(--model "$2") ;;
        --skills|-s) factory_args+=(--skills "$2") ;;
      esac
      shift 2
      ;;
    *) factory_args+=("$1"); shift ;;
  esac
done
exec "$factory_python" "$script_dir/install-factory.py" "${factory_args[@]}"
