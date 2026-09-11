#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-skills.sh [--model openai|claude] [--skills all|name1,collection:name2] [--project <directory>]

With no options, the script prompts for one model, one or more skills, and a
project root. Use collection:<name> to install a collection. Use 0 or all in
the selection menu to install every skill.

Install destinations:
  openai  -> <project>/.agents/skills
  claude  -> <project>/.claude/skills
EOF
}

model=""
skills_arg=""
project_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|-m)
      [[ $# -ge 2 ]] || { printf '%s\n' 'Missing value for --model.' >&2; exit 2; }
      model="${2,,}"
      shift 2
      ;;
    --skills|-s)
      [[ $# -ge 2 ]] || { printf '%s\n' 'Missing value for --skills.' >&2; exit 2; }
      skills_arg="$2"
      shift 2
      ;;
    --project|-p)
      [[ $# -ge 2 ]] || { printf '%s\n' 'Missing value for --project.' >&2; exit 2; }
      project_path="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

interactive=0
if [[ -z "$model" || -z "$skills_arg" || -z "$project_path" ]]; then
  interactive=1
fi

select_model() {
  while true; do
    printf '\nSelect a model:\n'
    printf '  1. openai\n'
    printf '  2. claude\n'
    read -r -p 'Model number: ' choice
    case "${choice//[[:space:]]/}" in
      1) model="openai"; return ;;
      2) model="claude"; return ;;
      *) printf '%s\n' 'Choose 1 or 2.' ;;
    esac
  done
}

if [[ -z "$model" ]]; then
  select_model
fi

case "$model" in
  openai|claude) ;;
  *)
    printf 'Unsupported model: %s\n' "$model" >&2
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd -- "$script_dir/.." && pwd -P)"
source_root="$repository_root/skills/$model"
collection_root="$repository_root/collections"

if [[ ! -d "$source_root" ]]; then
  printf 'Skill source directory does not exist: %s\n' "$source_root" >&2
  exit 1
fi

shopt -s nullglob
skill_directories=("$source_root"/*)
skill_names=()
for skill_directory in "${skill_directories[@]}"; do
  [[ -d "$skill_directory" ]] || continue
  if [[ ! -f "$skill_directory/SKILL.md" ]]; then
    printf 'Skill is missing SKILL.md: %s\n' "$skill_directory" >&2
    exit 1
  fi
  skill_names+=("$(basename -- "$skill_directory")")
done
if [[ ${#skill_names[@]} -eq 0 ]]; then
  printf 'No skills found in: %s\n' "$source_root" >&2
  exit 1
fi
mapfile -t skill_names < <(printf '%s\n' "${skill_names[@]}" | LC_ALL=C sort)

if [[ ! -d "$collection_root" ]]; then
  printf 'Collection directory does not exist: %s\n' "$collection_root" >&2
  exit 1
fi

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

unquote() {
  local value
  value="$(trim "$1")"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

collection_names=()
collection_descriptions=()
declare -A collection_members=()

for collection_directory in "$collection_root"/*; do
  [[ -d "$collection_directory" ]] || continue
  manifest_path="$collection_directory/collection.yaml"
  if [[ ! -f "$manifest_path" ]]; then
    printf 'Collection is missing collection.yaml: %s\n' "$collection_directory" >&2
    exit 1
  fi

  collection_name=""
  collection_description=""
  members=()
  in_skills=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == name:* ]]; then
      collection_name="$(unquote "${line#name:}")"
      in_skills=0
    elif [[ "$line" == description:* ]]; then
      collection_description="$(unquote "${line#description:}")"
      in_skills=0
    elif [[ "$line" =~ ^skills:[[:space:]]*$ ]]; then
      in_skills=1
    elif (( in_skills == 1 )) && [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-z0-9][a-z0-9-]*)[[:space:]]*$ ]]; then
      members+=("${BASH_REMATCH[1]}")
    elif (( in_skills == 1 )) && [[ "$line" =~ ^[^[:space:]] ]]; then
      in_skills=0
    fi
  done < "$manifest_path"

  directory_name="$(basename -- "$collection_directory")"
  if [[ -z "$collection_name" ]]; then
    printf 'Collection manifest is missing a name: %s\n' "$manifest_path" >&2
    exit 1
  fi
  if [[ "$collection_name" != "$directory_name" ]]; then
    printf "Collection name '%s' must match its directory '%s'.\n" "$collection_name" "$directory_name" >&2
    exit 1
  fi
  if [[ -z "$collection_description" ]]; then
    printf 'Collection manifest is missing a description: %s\n' "$manifest_path" >&2
    exit 1
  fi
  if [[ ${#members[@]} -eq 0 ]]; then
    printf 'Collection has no skills: %s\n' "$collection_name" >&2
    exit 1
  fi

  checked_members=()
  for member in "${members[@]}"; do
    found=0
    for skill_name in "${skill_names[@]}"; do
      [[ "$skill_name" == "$member" ]] && found=1
    done
    if (( found == 0 )); then
      printf "Collection '%s' references unknown %s skill: %s\n" "$collection_name" "$model" "$member" >&2
      exit 1
    fi
    for checked in "${checked_members[@]}"; do
      if [[ "$checked" == "$member" ]]; then
        printf 'Collection contains duplicate skills: %s\n' "$collection_name" >&2
        exit 1
      fi
    done
    checked_members+=("$member")
  done

  collection_names+=("$collection_name")
  collection_descriptions+=("$collection_description")
  collection_members["$collection_name"]="${members[*]}"
done

if [[ ${#collection_names[@]} -eq 0 ]]; then
  printf 'No collections found in: %s\n' "$collection_root" >&2
  exit 1
fi

for skill_name in "${skill_names[@]}"; do
  collected=0
  for collection_name in "${collection_names[@]}"; do
    for member in ${collection_members[$collection_name]}; do
      [[ "$member" == "$skill_name" ]] && collected=1
    done
  done
  if (( collected == 0 )); then
    printf 'Active skill missing from collections: %s\n' "$skill_name" >&2
    exit 1
  fi
done

select_skills() {
  printf '\nSelect skills or collections. Enter all or comma-separated numbers:\n'
  printf '  0. All\n'
  local index=1
  for skill_name in "${skill_names[@]}"; do
    printf '  %d. %s\n' "$index" "$skill_name"
    ((index += 1))
  done
  local collection_index=0
  for collection_name in "${collection_names[@]}"; do
    printf '  %d. collection:%s - %s\n' "$index" "$collection_name" "${collection_descriptions[$collection_index]}"
    ((index += 1))
    ((collection_index += 1))
  done
  read -r -p 'Selection: ' skills_arg
}

if [[ -z "$skills_arg" ]]; then
  select_skills
fi

selected_skills=()
add_selected_skill() {
  local candidate="$1"
  local existing
  for existing in "${selected_skills[@]}"; do
    [[ "$existing" == "$candidate" ]] && return
  done
  selected_skills+=("$candidate")
}

add_collection() {
  local requested_collection="$1"
  local collection_name member
  for collection_name in "${collection_names[@]}"; do
    if [[ "$collection_name" == "$requested_collection" ]]; then
      for member in ${collection_members[$collection_name]}; do
        add_selected_skill "$member"
      done
      return
    fi
  done
  printf 'Unknown collection: %s\n' "$requested_collection" >&2
  exit 1
}

IFS=',' read -r -a requested_skills <<< "$skills_arg"
select_all=0
for raw_skill in "${requested_skills[@]}"; do
  token="$(trim "${raw_skill,,}")"
  if [[ "$token" == all || "$token" == 0 ]]; then
    select_all=1
  fi
done

if (( select_all == 1 )); then
  selected_skills=("${skill_names[@]}")
else
  for raw_skill in "${requested_skills[@]}"; do
    token="$(trim "${raw_skill,,}")"
    [[ -n "$token" ]] || continue
    selected_name=""
    if [[ "$token" =~ ^[0-9]+$ ]]; then
      number=$((10#$token))
      maximum=$((${#skill_names[@]} + ${#collection_names[@]}))
      if (( number < 1 || number > maximum )); then
        printf 'Selection number is out of range: %s\n' "$token" >&2
        exit 1
      fi
      if (( number <= ${#skill_names[@]} )); then
        selected_name="${skill_names[$((number - 1))]}"
      else
        collection_number=$((number - ${#skill_names[@]} - 1))
        add_collection "${collection_names[$collection_number]}"
        continue
      fi
    elif [[ "$token" == collection:* ]]; then
      add_collection "$(trim "${token#collection:}")"
      continue
    else
      for skill_name in "${skill_names[@]}"; do
        if [[ "$skill_name" == "$token" ]]; then
          selected_name="$skill_name"
          break
        fi
      done
      if [[ -z "$selected_name" ]]; then
        printf 'Unknown skill: %s\n' "$token" >&2
        exit 1
      fi
    fi

    add_selected_skill "$selected_name"
  done
fi

if [[ ${#selected_skills[@]} -eq 0 ]]; then
  printf '%s\n' 'At least one skill must be selected.' >&2
  exit 1
fi

if [[ -z "$project_path" ]]; then
  read -r -p 'Project root: ' project_path
fi
if [[ -z "$project_path" ]]; then
  printf '%s\n' 'Project root is required.' >&2
  exit 1
fi

if [[ "$project_path" =~ ^[A-Za-z]:[\\/] ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    project_path="$(cygpath -u "$project_path")"
  elif command -v wslpath >/dev/null 2>&1; then
    project_path="$(wslpath -u "$project_path")"
  fi
fi

if [[ ! -d "$project_path" ]]; then
  printf 'Project directory does not exist: %s\n' "$project_path" >&2
  exit 1
fi

project_root="$(cd -- "$project_path" && pwd -P)"
if [[ "$model" == "openai" ]]; then
  destination_root="$project_root/.agents/skills"
else
  destination_root="$project_root/.claude/skills"
fi

printf '\nInstall summary:\n'
printf '  Model: %s\n' "$model"
printf '  Project: %s\n' "$project_root"
printf '  Skills: %s\n' "$(IFS=', '; printf '%s' "${selected_skills[*]}")"

if (( interactive == 1 )); then
  read -r -p 'Copy these skills? [Y/n] ' confirmation
  if [[ "$confirmation" =~ ^[Nn]([Oo])?$ ]]; then
    printf '%s\n' 'Cancelled.'
    exit 0
  fi
fi

mkdir -p "$destination_root"
for skill_name in "${selected_skills[@]}"; do
  source_directory="$source_root/$skill_name"
  target_directory="$destination_root/$skill_name"
  mkdir -p "$target_directory"
  cp -R "$source_directory"/. "$target_directory"/
  printf 'Installed %s -> %s\n' "$skill_name" "$target_directory"
done
