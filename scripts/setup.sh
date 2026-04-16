#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Learning Platform Setup Wizard
# Supports:
# - macOS Terminal
# - Ubuntu on WSL
# - Linux
#
###############################################################################

#######################################
# Globals
#######################################
DOCTOR_ONLY="false"
AUTO_YES="false"

if [[ "${1:-}" == "--doctor" ]]; then
  DOCTOR_ONLY="true"
fi

if [[ "${1:-}" == "--yes" ]] || [[ "${2:-}" == "--yes" ]]; then
  AUTO_YES="true"
fi

#######################################
# Colors / formatting
#######################################
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  DIM="\033[2m"
  RED="\033[31m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  MAGENTA="\033[35m"
  CYAN="\033[36m"
  RESET="\033[0m"
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  RESET=""
fi

#######################################
# Paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="${HOME}/workspace/lms"
TARGET_INFRA_DIR="${ROOT_DIR}/learn-ops-infrastructure"
API_DIR="${ROOT_DIR}/learn-ops-api"
CLIENT_DIR="${ROOT_DIR}/learn-ops-client"
MONARCH_DIR="${ROOT_DIR}/service-monarch"

#######################################
# Repo URLs
# Adjust these if needed.
#######################################
API_REPO_URL="https://github.com/System-Explorer-Cohorts/learn-ops-api.git"
CLIENT_REPO_URL="https://github.com/System-Explorer-Cohorts/learn-ops-client.git"
INFRA_REPO_URL_DEFAULT="https://github.com/System-Explorer-Cohorts/learn-ops-infrastructure.git"
MONARCH_REPO_URL="https://github.com/System-Explorer-Cohorts/service-monarch.git"
NSS_ORG="System-Explorer-Cohorts"
GITHUB_API="https://api.github.com"

#######################################
# State
#######################################
OS_FAMILY=""
RUNNING_IN_WSL="false"

#######################################
# Utilities
#######################################
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

hr() {
  printf "%b\n" "${CYAN}================================================================${RESET}"
}

header() {
  echo
  hr
  printf "%b\n" "${BOLD}${CYAN}Learning Platform Setup Wizard${RESET}"
  printf "%b\n" "${DIM}Preparing a complete LMS workspace in ${ROOT_DIR}${RESET}"
  hr
  echo
}

step() {
  echo
  printf "%b\n" "${BOLD}${BLUE}▶ $1${RESET}"
}

substep() {
  printf "   %b\n" "${DIM}$1${RESET}"
}

ok() {
  printf "%b\n" "${GREEN}   ✔ $1${RESET}"
}

warn() {
  printf "%b\n" "${YELLOW}   ⚠ $1${RESET}"
}

err() {
  printf "%b\n" "${RED}   ✖ $1${RESET}"
}

die() {
  err "$1"
  exit 1
}

on_error() {
  local exit_code=$?
  echo
  err "Setup stopped because a command failed."
  warn "Exit code: ${exit_code}"
  warn "If you rerun setup, it will reuse anything already completed."
  exit "${exit_code}"
}
trap on_error ERR

section_done() {
  printf "%b\n" "${GREEN}${BOLD}✓ $1 complete${RESET}"
}

# Returns 0 (true) if version $1 >= $2 (semver-aware)
version_ge() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

#######################################
# Prompt helpers
#######################################
prompt_text() {
  local message="$1"
  printf "%b" "${BOLD}${message}${RESET} "
}

# Stores the result of masked_read — avoids bash local-variable shadowing.
_MASKED_INPUT=""

# Read a secret value, printing • for each character so users can confirm
# their paste landed and has the right length. Handles backspace and Enter.
# Result is stored in the global _MASKED_INPUT.
masked_read() {
  _MASKED_INPUT=""
  local char=""

  while IFS= read -r -s -n1 char; do
    if [[ -z "$char" ]]; then                                      # Enter
      break
    elif [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then       # Backspace
      if [[ -n "$_MASKED_INPUT" ]]; then
        _MASKED_INPUT="${_MASKED_INPUT%?}"
        printf "\b \b"
      fi
    elif [[ "$char" == $'\x1b' ]]; then                            # ESC sequence — skip rest of sequence
      local seq=""
      IFS= read -r -s -n1 -t 0.05 seq || true
      if [[ "$seq" == "[" ]]; then
        IFS= read -r -s -n1 -t 0.05 || true   # consume final byte
      fi
    else
      _MASKED_INPUT+="$char"
      printf "•"
    fi
  done
  printf "\n"
}

prompt_required() {
  local var_name="$1"
  local title="$2"
  local helper="$3"
  local secret="${4:-false}"
  local value=""

  echo
  printf "%b\n" "${BOLD}${MAGENTA}${title}${RESET}"
  printf "%b\n" "${DIM}${helper}${RESET}"

  while [[ -z "${value}" ]]; do
    if [[ "${secret}" == "true" ]]; then
      printf "%b" "$(prompt_text "→ Enter value:")"
      masked_read
      value="$_MASKED_INPUT"
    else
      read -r -p "$(prompt_text "→ Enter value:")" value
    fi

    if [[ -z "${value}" ]]; then
      warn "This value is required."
    fi
  done

  printf -v "${var_name}" '%s' "${value}"
}

prompt_with_default() {
  local var_name="$1"
  local title="$2"
  local helper="$3"
  local default_value="$4"
  local value=""

  echo
  printf "%b\n" "${BOLD}${MAGENTA}${title}${RESET}"
  printf "%b\n" "${DIM}${helper}${RESET}"

  read -r -p "$(prompt_text "→ Press Enter to use '${default_value}', or type a new value:")" value

  value="${value:-$default_value}"
  printf -v "${var_name}" '%s' "${value}"
}

confirm_yes_no() {
  local prompt="$1"

  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi

  local answer=""
  read -r -p "$(prompt_text "${prompt} [Y/n]")" answer
  answer="${answer:-Y}"
  [[ "${answer}" =~ ^[Yy]$ ]]
}

#######################################
# Detection
#######################################
detect_platform() {
  step "Detecting your environment"

  local uname_s
  uname_s="$(uname -s)"

  case "${uname_s}" in
    Darwin)
      OS_FAMILY="macOS"
      ;;
    Linux)
      OS_FAMILY="Linux"
      if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        RUNNING_IN_WSL="true"
        OS_FAMILY="WSL"
      fi
      ;;
    *)
      die "Unsupported platform: ${uname_s}. Use macOS Terminal or Ubuntu in WSL."
      ;;
  esac

  ok "Detected platform: ${OS_FAMILY}"

  if [[ "${OS_FAMILY}" == "WSL" ]]; then
    ok "Running inside WSL"
  fi

  if [[ "${OS_FAMILY}" == "Linux" ]]; then
    warn "Regular Linux detected. This script is optimized for macOS and Ubuntu on WSL, but Linux should work."
  fi

  section_done "Environment detection"
}

#######################################
# Command checks
#######################################
need_cmd() {
  local cmd="$1"
  local help_text="$2"

  if have_cmd "${cmd}"; then
    ok "Found ${cmd}"
  else
    die "'${cmd}' is not installed. ${help_text}"
  fi
}

check_make_usage_note() {
  if [[ "${OS_FAMILY}" == "WSL" ]]; then
    ok "Windows users should run this inside Ubuntu WSL, not PowerShell"
  fi
}

print_docker_install_instructions() {
  case "${OS_FAMILY}" in
    macOS)
      printf "   %b\n" "${BOLD}Install Docker Desktop:${RESET}"
      printf "     %s\n" "1. Go to: https://www.docker.com/products/docker-desktop/"
      printf "     %s\n" "2. Download and open the .dmg, drag Docker to Applications"
      printf "     %s\n" "3. Launch Docker from Applications"
      printf "     %s\n" "4. Wait for the whale icon to appear in the menu bar"
      ;;
    WSL)
      printf "   %b\n" "${BOLD}Install Docker Desktop on Windows (not inside WSL):${RESET}"
      printf "     %s\n" "1. Go to: https://www.docker.com/products/docker-desktop/"
      printf "     %s\n" "2. Run the Windows installer"
      printf "     %s\n" "3. After install: Settings → Resources → WSL Integration → enable your distro"
      printf "     %s\n" "4. Restart Docker Desktop"
      ;;
    *)
      printf "   %b\n" "${BOLD}Install Docker Engine:${RESET}"
      printf "     %s\n" "1. curl -fsSL https://get.docker.com | sh"
      printf "     %s\n" "   (or follow https://docs.docker.com/engine/install/)"
      printf "     %s\n" "2. sudo usermod -aG docker \$USER"
      printf "     %s\n" "3. newgrp docker          (or log out and back in)"
      printf "     %s\n" "4. sudo systemctl enable --now docker"
      ;;
  esac
}

check_docker_installed() {
  until have_cmd docker; do
    err "Docker is not installed."
    print_docker_install_instructions
    printf "   Press Enter once Docker is installed, or Ctrl+C to cancel...\n"
    read -r
  done
  ok "Found docker"
}

print_compose_install_instructions() {
  case "${OS_FAMILY}" in
    macOS|WSL)
      printf "   %b\n" "${BOLD}Docker Desktop includes Compose v2 — ensure it is up to date:${RESET}"
      printf "     %s\n" "1. Click the Docker icon → Check for Updates"
      printf "     %s\n" "2. Or download the latest from https://www.docker.com/products/docker-desktop/"
      printf "     %s\n" "3. Restart Docker Desktop after updating"
      ;;
    *)
      printf "   %b\n" "${BOLD}Install the Docker Compose plugin:${RESET}"
      printf "     %s\n" "Debian/Ubuntu:  sudo apt-get update && sudo apt-get install docker-compose-plugin"
      printf "     %s\n" "Other distros:  https://docs.docker.com/compose/install/linux/"
      ;;
  esac
}

check_compose_available() {
  until docker compose version >/dev/null 2>&1; do
    err "docker compose is unavailable."
    print_compose_install_instructions
    printf "   Press Enter once Compose is available, or Ctrl+C to cancel...\n"
    read -r
  done
  ok "Found docker compose"
}

check_prereqs() {
  step "Checking required tools"

  need_cmd git "Install Git, then rerun setup."
  check_docker_installed
  need_cmd python3 "Install Python 3, then rerun setup."
  need_cmd make "Install make, then rerun setup."

  check_compose_available

  check_make_usage_note
  section_done "Prerequisite checks"
}

#######################################
# Docker checks
#######################################
check_docker_running() {
  step "Checking Docker status"
  substep "Making sure the Docker daemon is reachable"

  until docker info >/dev/null 2>&1; do
    warn "Docker is not running. Please start Docker Desktop (or Docker Engine)."
    printf "   Press Enter once Docker is running, or Ctrl+C to cancel...\n"
    read -r
  done
  ok "Docker daemon is running"

  if [[ "${OS_FAMILY}" == "WSL" ]]; then
    warn "Make sure Docker Desktop has WSL integration enabled for your Ubuntu distro."
  fi

  check_docker_versions

  section_done "Docker status"
}

check_docker_versions() {
  local required_cli="28.1.1"
  local required_desktop="4.69.0"

  # --- Docker CLI version ---
  local cli_version
  cli_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)

  if [[ -z "${cli_version}" ]]; then
    die "Could not determine Docker CLI version. Please ensure Docker is running and up to date (requires ${required_cli})."
  fi

  while ! version_ge "${cli_version}" "${required_cli}"; do
    err "Docker CLI version ${cli_version} is too old. Requires ${required_cli} or newer."
    if [[ "${OS_FAMILY}" == "WSL" ]]; then
      printf "   To update on WSL:\n"
      printf "     1. Open Docker Desktop on Windows.\n"
      printf "     2. Click the Docker tray icon → Settings → Software Updates → Check for updates.\n"
      printf "     3. Or download the latest version from https://www.docker.com/products/docker-desktop/\n"
      printf "     4. After updating, restart Docker Desktop.\n"
    elif [[ "${OS_FAMILY}" == "macOS" ]]; then
      printf "   To update on macOS:\n"
      printf "     1. Click the Docker icon in the menu bar → Check for Updates.\n"
      printf "     2. Or download the latest version from https://www.docker.com/products/docker-desktop/\n"
      printf "     3. After updating, restart Docker Desktop.\n"
    else
      printf "   Please update Docker Engine to ${required_cli} or newer.\n"
    fi
    printf "   Press Enter once Docker has been updated and restarted, or Ctrl+C to cancel...\n"
    read -r
    cli_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)
  done
  ok "Docker CLI version ${cli_version} meets requirement (>= ${required_cli})"

  # --- Docker Desktop version (macOS only) ---
  if [[ "${OS_FAMILY}" == "macOS" ]]; then
    local desktop_version
    desktop_version=$(defaults read /Applications/Docker.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)

    while [[ -n "${desktop_version}" ]] && ! version_ge "${desktop_version}" "${required_desktop}"; do
      err "Docker Desktop version ${desktop_version} is too old. Requires ${required_desktop} or newer."
      printf "   To update on macOS:\n"
      printf "     1. Click the Docker icon in the menu bar → Check for Updates.\n"
      printf "     2. Or download the latest version from https://www.docker.com/products/docker-desktop/\n"
      printf "     3. After updating, restart Docker Desktop.\n"
      printf "   Press Enter once Docker Desktop has been updated and restarted, or Ctrl+C to cancel...\n"
      read -r
      desktop_version=$(defaults read /Applications/Docker.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)
    done

    if [[ -z "${desktop_version}" ]]; then
      warn "Could not read Docker Desktop version (is Docker Desktop installed at /Applications/Docker.app?)."
    else
      ok "Docker Desktop version ${desktop_version} meets requirement (>= ${required_desktop})"
    fi
  fi
}

#######################################
# Infra repo normalization
#######################################
get_current_infra_remote() {
  local remote=""
  if git -C "${CURRENT_INFRA_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote="$(git -C "${CURRENT_INFRA_DIR}" remote get-url origin 2>/dev/null || true)"
  fi
  echo "${remote:-${INFRA_REPO_URL_DEFAULT}}"
}

ensure_workspace_root() {
  step "Preparing workspace root"

  mkdir -p "${ROOT_DIR}"
  ok "Workspace directory ready: ${ROOT_DIR}"

  section_done "Workspace root"
}

normalize_infra_location_if_needed() {
  step "Ensuring the infrastructure repo is in the expected location"

  if [[ "${CURRENT_INFRA_DIR}" == "${TARGET_INFRA_DIR}" ]]; then
    ok "Infrastructure repo is already at ${TARGET_INFRA_DIR}"
    section_done "Infrastructure repo location"
    return
  fi

  echo
  hr
  err "Setup must be run from the expected workspace location."
  echo
  warn "You ran setup from:  ${CURRENT_INFRA_DIR}"
  warn "Expected location:   ${TARGET_INFRA_DIR}"
  echo
  substep "Please move the repo to the correct location and re-run setup:"
  echo
  printf "   %b\n" "${BOLD}mv ${CURRENT_INFRA_DIR} ${TARGET_INFRA_DIR}${RESET}"
  printf "   %b\n" "${BOLD}cd ${TARGET_INFRA_DIR}${RESET}"
  printf "   %b\n" "${BOLD}make setup${RESET}"
  echo
  hr
  echo
  exit 1
}

#######################################
# Clone helpers
#######################################
clone_if_missing() {
  local label="$1"
  local repo_url="$2"
  local target_dir="$3"

  if [[ -d "${target_dir}/.git" ]]; then
    ok "${label} already present"
  else
    substep "Cloning ${label} into ${target_dir}"
    git clone "${repo_url}" "${target_dir}"
    ok "Cloned ${label}"
  fi
}

verify_repo_dir() {
  local label="$1"
  local target_dir="$2"

  if [[ -d "${target_dir}/.git" ]]; then
    ok "${label} verified"
  else
    die "${label} was expected at ${target_dir}, but was not found."
  fi
}

clone_workspace_repos() {
  step "Cloning required repositories"

  substep "Your final workspace will look like:"
  printf "   %s\n" "${ROOT_DIR}"
  printf "   %s\n" "├── learn-ops-api"
  printf "   %s\n" "├── learn-ops-client"
  printf "   %s\n" "├── learn-ops-infrastructure"
  printf "   %s\n" "└── service-monarch"

  clone_if_missing "learn-ops-client" "${CLIENT_REPO_URL}" "${CLIENT_DIR}"
  clone_if_missing "learn-ops-api" "${API_REPO_URL}" "${API_DIR}"
  clone_if_missing "service-monarch" "${MONARCH_REPO_URL}" "${MONARCH_DIR}"

  verify_repo_dir "learn-ops-client" "${CLIENT_DIR}"
  verify_repo_dir "learn-ops-api" "${API_DIR}"
  verify_repo_dir "service-monarch" "${MONARCH_DIR}"
  verify_repo_dir "learn-ops-infrastructure" "${TARGET_INFRA_DIR}"

  section_done "Repository cloning"
}

#######################################
# Student fork helpers
#######################################

# Fork one NSS-Workshops repo to the student's account and echo the fork URL.
# Idempotent: GitHub returns the existing fork if it already exists.
ensure_fork_exists() {
  local repo_name="$1"

  substep "Forking ${NSS_ORG}/${repo_name} to ${GH_USERNAME}..."

  local http_code
  http_code="$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${GITHUB_API}/repos/${NSS_ORG}/${repo_name}/forks")"

  case "${http_code}" in
    200|202)
      : # success or async — will poll below
      ;;
    403)
      die "GitHub denied the fork request for ${repo_name}. Ensure your PAT has 'repo' scope."
      ;;
    *)
      die "Unexpected response (HTTP ${http_code}) when forking ${repo_name}."
      ;;
  esac

  # Poll until the fork is visible (handles GitHub's async 202 case)
  local attempts=0
  local max_attempts=6
  while [[ "${attempts}" -lt "${max_attempts}" ]]; do
    local check_code
    check_code="$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API}/repos/${GH_USERNAME}/${repo_name}")"

    if [[ "${check_code}" == "200" ]]; then
      ok "Fork ready: github.com/${GH_USERNAME}/${repo_name}"
      echo "https://github.com/${GH_USERNAME}/${repo_name}.git"
      return 0
    fi

    attempts=$(( attempts + 1 ))
    substep "Waiting for fork to become available... (${attempts}/${max_attempts})"
    sleep 5
  done

  die "Fork of ${repo_name} did not become available after ${max_attempts} attempts."
}

# Update git remotes so origin → student fork, upstream → NSS-Workshops.
# Idempotent: exits early if origin already points to the fork.
fixup_remotes() {
  local label="$1"
  local repo_dir="$2"
  local upstream_url="$3"
  local fork_url="$4"

  substep "Configuring remotes for ${label}"

  local current_origin
  current_origin="$(git -C "${repo_dir}" remote get-url origin 2>/dev/null || true)"

  if [[ "${current_origin}" == "${fork_url}" ]]; then
    ok "${label}: remotes already configured"
    # Ensure upstream exists even on re-run
    if ! git -C "${repo_dir}" remote get-url upstream >/dev/null 2>&1; then
      git -C "${repo_dir}" remote add upstream "${upstream_url}"
    fi
    return 0
  fi

  # Wire up upstream (rename existing origin, or set-url if upstream already present)
  if git -C "${repo_dir}" remote get-url upstream >/dev/null 2>&1; then
    git -C "${repo_dir}" remote set-url upstream "${upstream_url}"
  else
    git -C "${repo_dir}" remote rename origin upstream
  fi

  # Wire up origin → student fork
  if git -C "${repo_dir}" remote get-url origin >/dev/null 2>&1; then
    git -C "${repo_dir}" remote set-url origin "${fork_url}"
  else
    git -C "${repo_dir}" remote add origin "${fork_url}"
  fi

  ok "${label}: origin  → ${fork_url}"
  ok "${label}: upstream → ${upstream_url}"
}

setup_student_forks() {
  step "Setting up your personal forks"

  substep "Each course repo will be forked to your GitHub account."
  substep "You can push your work to 'origin' (your fork) and pull instructor"
  substep "updates from 'upstream' (the course repo) at any time."

  local -a repos=(
    "learn-ops-api|${API_REPO_URL}|${API_DIR}"
    "learn-ops-client|${CLIENT_REPO_URL}|${CLIENT_DIR}"
    "service-monarch|${MONARCH_REPO_URL}|${MONARCH_DIR}"
    "learn-ops-infrastructure|${INFRA_REPO_URL_DEFAULT}|${TARGET_INFRA_DIR}"
  )

  for entry in "${repos[@]}"; do
    local repo_name upstream_url repo_dir fork_url
    IFS='|' read -r repo_name upstream_url repo_dir <<< "${entry}"

    fork_url="$(ensure_fork_exists "${repo_name}")"
    fixup_remotes "${repo_name}" "${repo_dir}" "${upstream_url}" "${fork_url}"
  done

  section_done "Student forks"
}

#######################################
# Secret generation
#######################################
random_alnum() {
  python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(30)))
PY
}

#######################################
# Env file writers
#######################################
overwrite_prompt_if_exists() {
  local path="$1"

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  warn "File already exists: ${path}"
  if confirm_yes_no "Overwrite it?"; then
    return 0
  fi

  return 1
}

write_api_env() {
  local env_path="${API_DIR}/.env"
  local template_path="${API_DIR}/.env.template"

  [[ -f "${template_path}" ]] || die "Missing API template file: ${template_path}"

  if ! overwrite_prompt_if_exists "${env_path}"; then
    warn "Keeping existing API .env"
    return
  fi

  cp "${template_path}" "${env_path}"

  python3 - <<PY
from pathlib import Path

env_path = Path(r"${env_path}")
text = env_path.read_text()

replacements = {
    "LEARN_OPS_CLIENT_ID=": "LEARN_OPS_CLIENT_ID=${LEARN_OPS_CLIENT_ID}",
    "LEARN_OPS_SECRET_KEY=": "LEARN_OPS_SECRET_KEY=${LEARN_OPS_SECRET_KEY}",
    "LEARN_OPS_DJANGO_SECRET_KEY=": "LEARN_OPS_DJANGO_SECRET_KEY=${LEARN_OPS_DJANGO_SECRET_KEY}",
    "LEARN_OPS_SUPERUSER_NAME=": "LEARN_OPS_SUPERUSER_NAME=${LEARN_OPS_SUPERUSER_NAME}",
    "LEARN_OPS_SUPERUSER_PASSWORD=": "LEARN_OPS_SUPERUSER_PASSWORD=${LEARN_OPS_SUPERUSER_PASSWORD}",
    "SLACK_TOKEN=": "SLACK_TOKEN=${SLACK_TOKEN}",
    "GITHUB_TOKEN=": "GITHUB_TOKEN=${GITHUB_TOKEN}",
}

lines = text.splitlines()
updated = []
seen = set()

for line in lines:
    replaced = False
    for prefix, new_value in replacements.items():
        if line.startswith(prefix):
            updated.append(new_value)
            seen.add(prefix)
            replaced = True
            break
    if not replaced:
        updated.append(line)

for prefix, new_value in replacements.items():
    if prefix not in seen:
        updated.append(new_value)

env_path.write_text("\\n".join(updated) + "\\n")
PY

  ok "Created API .env"
}

write_monarch_env() {
  local env_path="${MONARCH_DIR}/.env"
  local template_path="${MONARCH_DIR}/.env.template"

  [[ -f "${template_path}" ]] || die "Missing Monarch template file: ${template_path}"

  if ! overwrite_prompt_if_exists "${env_path}"; then
    warn "Keeping existing Monarch .env"
    return
  fi

  cp "${template_path}" "${env_path}"

  python3 - <<PY
from pathlib import Path

env_path = Path(r"${env_path}")
text = env_path.read_text()

replacements = {
    "GH_PAT=": "GH_PAT=${GITHUB_TOKEN}",
    "SLACK_TOKEN=": "SLACK_TOKEN=${SLACK_TOKEN}",
    "SLACK_WEBHOOK_URL=": "SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}",
}

lines = text.splitlines()
updated = []
seen = set()

for line in lines:
    replaced = False
    for prefix, new_value in replacements.items():
        if line.startswith(prefix):
            updated.append(new_value)
            seen.add(prefix)
            replaced = True
            break
    if not replaced:
        updated.append(line)

for prefix, new_value in replacements.items():
    if prefix not in seen:
        updated.append(new_value)

env_path.write_text("\\n".join(updated) + "\\n")
PY

  ok "Created Monarch .env"
}

collect_user_identity() {
  step "Confirming your identity"

  local git_name git_fname git_lname git_email
  git_name="$(git config --global user.name 2>/dev/null || true)"
  git_fname="$(echo "${git_name}" | awk '{print $1}')"
  git_lname="$(echo "${git_name}" | awk '{print $2}')"
  git_email="$(git config --global user.email 2>/dev/null || true)"

  prompt_with_default USER_FIRST_NAME "First name" "Confirm or update your first name" "${git_fname}"
  prompt_with_default USER_LAST_NAME  "Last name"  "Confirm or update your last name"  "${git_lname}"
  prompt_with_default USER_EMAIL      "Email"      "Confirm or update your email"       "${git_email}"
  prompt_required     GH_USERNAME     "GitHub username" "Your GitHub handle (no @)" false

  section_done "Identity confirmed"
}

check_org_membership() {
  step "Checking GitHub org membership"

  local org="System-Explorer-Cohorts"
  local api_url="https://api.github.com/user/memberships/orgs/${org}"
  local http_code
  http_code="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${api_url}")"

  case "${http_code}" in
    200)
      local token_login
      token_login="$(curl -s \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/user" | grep -o '"login": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')"
      if [ "${token_login}" != "${GH_USERNAME}" ]; then
        warn "Token mismatch: the token belongs to '${token_login}', but you entered '${GH_USERNAME}' as your GitHub username."
        substep "Please re-run setup using a token generated from the '${GH_USERNAME}' account."
        exit 1
      fi
      ok "Confirmed: you are a member of github.com/organizations/${org}"
      ;;
    404)
      warn "Your GitHub account does not appear to be a member of the ${org} org."
      echo
      substep "Visit: https://github.com/organizations/${org}/invitation"
      substep "Request access or ask your instructor to invite you."
      echo
      while true; do
        if ! confirm_yes_no "Press Y once you have been added to the org and are ready to continue"; then
          die "Cannot continue without org membership."
        fi
        substep "Re-checking org membership..."
        local recheck_code
        recheck_code="$(curl -s -o /dev/null -w "%{http_code}" \
          -H "Authorization: Bearer ${GITHUB_TOKEN}" \
          -H "Accept: application/vnd.github+json" \
          "${api_url}")"
        if [ "${recheck_code}" = "200" ]; then
          ok "Confirmed: you are now a member of github.com/organizations/${org}"
          break
        else
          warn "Still not showing as a member (HTTP ${recheck_code}). GitHub can take a moment to update — try again."
          echo
        fi
      done
      ;;
    *)
      warn "Could not verify org membership automatically (GitHub API returned ${http_code})."
      substep "This can happen if your token is missing the read:org scope or requires SSO authorization."
      echo
      substep "Verify manually: https://github.com/orgs/${org}/people"
      echo
      confirm_yes_no "Are you a member of the ${org} org?"
      ;;
  esac

  section_done "Org membership"
}

prompt_github_pat() {
  echo
  printf "%b\n" "${BOLD}Follow these steps to create your Personal Access Token:${RESET}"
  echo
  printf "   %s\n" "1. Log into your GitHub account"
  printf "   %s\n" "2. Go to your Settings"
  printf "   %s\n" "3. Click Developer Settings (last item, left nav)"
  printf "   %s\n" "4. Click Personal access tokens > Tokens (classic)"
  printf "   %s\n" "5. Click Generate new token > Generate new token (classic)"
  printf "   %s\n" "6. In the Note field, enter: Learning Platform Token"
  printf "   %s\n" "7. Set expiration to 90 days"
  printf "   %s\n" "8. Select these permissions:"
  printf "      %s\n" "- admin:org"
  printf "      %s\n" "- admin:org_hook"
  printf "      %s\n" "- repo"
  printf "   %s\n" "9. Click Generate Token at the bottom — keep the window open!"
  echo

  prompt_required GITHUB_TOKEN "GitHub Personal Access Token" "Paste the token you just generated (starts with ghp_)" true
}

run_oauth_flow() {
  step "GitHub OAuth authorization"

  local auth_url="http://localhost:8000/auth/github/url?cohort=13&v=1"

  substep "This step links your GitHub account to the learning platform."
  substep "The local API will verify your identity through GitHub and create your account."
  echo
  printf "   %b\n" "${BOLD}What to do:${RESET}"
  printf "   %s\n" "  1. Open the link below in your browser"
  printf "   %s\n" "  2. GitHub will ask you to authorize the LearnOps app — click Authorize"
  printf "   %s\n" "  3. You will be redirected back to the local app — that means it worked"
  echo
  printf "   %b\n" "${BOLD}GitHub Authorization — LearnOps API${RESET}"
  printf "   %b\n" "${DIM}${auth_url}${RESET}"
  echo

  if confirm_yes_no "Open the authorization page in your browser?"; then
    open_in_browser "${auth_url}"
  fi

  echo
  printf "   %b\n" "${BOLD}What to expect:${RESET}"
  printf "   %s\n" "  Success: GitHub redirects you back to the local app (localhost:3000)"
  printf "   %s\n" "  Error page: the API may still be loading — wait 30s and try the link again"
  printf "   %s\n" "  'Invalid client' from GitHub: check that OAuth credentials are set in your .env"
  echo

  confirm_yes_no "Press Y once GitHub has redirected you back to the app"

  section_done "GitHub OAuth"
}

write_instructor_fixture() {
  step "Creating instructor fixture"

  local fixture_dir="${API_DIR}/LearningAPI/fixtures"
  local fixture_path="${fixture_dir}/currentuser.json"
  local today
  today="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"

  mkdir -p "${fixture_dir}"

  python3 - <<PY
import json, os

fixture_dir = "${fixture_dir}"
cu_path     = "${fixture_path}"
username    = "${GH_USERNAME}"
first_name  = "${USER_FIRST_NAME}"
last_name   = "${USER_LAST_NAME}"
email       = "${USER_EMAIL}"
today       = "${today}"

# Scan existing fixtures for this username and collect used PKs
used_pks   = set()
found_in   = None   # (filepath, data, index)

for fname in sorted(os.listdir(fixture_dir)):
    if fname == "currentuser.json":
        continue
    fpath = os.path.join(fixture_dir, fname)
    try:
        with open(fpath) as f:
            data = json.load(f)
        for i, entry in enumerate(data):
            if not isinstance(entry, dict) or entry.get("model") != "auth.user":
                continue
            used_pks.add(entry["pk"])
            if entry["fields"]["username"] == username:
                found_in = (fpath, data, i)
    except Exception:
        pass

if found_in:
    fpath, data, i = found_in
    entry   = data[i]
    changed = False
    if not entry["fields"].get("is_staff"):
        entry["fields"]["is_staff"] = True
        changed = True
    if 2 not in entry["fields"].get("groups", []):
        entry["fields"].setdefault("groups", []).append(2)
        changed = True
    if changed:
        with open(fpath, "w") as f:
            json.dump(data, f, indent=2)
        print(f"  Patched {os.path.basename(fpath)}: is_staff=True and groups includes 2 for {username}")
    else:
        print(f"  {username} already has is_staff=True and groups includes 2 in {os.path.basename(fpath)}")
    # Remove any stale currentuser.json so loaddata does not see a duplicate
    if os.path.exists(cu_path):
        os.remove(cu_path)
        print(f"  Removed stale currentuser.json")
else:
    new_pk = max(used_pks) + 1 if used_pks else 1
    record = [{
        "model": "auth.user",
        "pk": new_pk,
        "fields": {
            "password": "",
            "last_login": None,
            "is_superuser": False,
            "username": username,
            "first_name": first_name,
            "last_name": last_name,
            "email": email,
            "is_staff": True,
            "is_active": True,
            "date_joined": today,
            "groups": [2],
            "user_permissions": [],
        },
    }]
    with open(cu_path, "w") as f:
        json.dump(record, f, indent=4)
    print(f"  Wrote currentuser.json (pk={new_pk}) for {username}")
PY

  section_done "Instructor fixture"
}

collect_config() {
  step "Collecting required configuration"

  substep "A few values are required to wire up GitHub, Slack, and your local Django admin user."
  substep "Instructor-provided values are still needed here; setup cannot invent them for you."

  prompt_required \
    LEARN_OPS_CLIENT_ID \
    "Learn Ops Client ID" \
    "Your instructor should provide this value."

  prompt_required \
    LEARN_OPS_SECRET_KEY \
    "Learn Ops Secret Key" \
    "Your instructor should provide this value." \
    true

  prompt_required \
    SLACK_TOKEN \
    "Slack Token" \
    "Used by the API and Monarch service for Slack integration." \
    true

  prompt_required \
    SLACK_WEBHOOK_URL \
    "Slack Webhook URL" \
    "Used by Monarch to post migration status messages." \
    true

  prompt_github_pat

  LEARN_OPS_DJANGO_SECRET_KEY="$(random_alnum)"
  ok "Generated a fresh LEARN_OPS_DJANGO_SECRET_KEY"

  prompt_with_default \
    LEARN_OPS_SUPERUSER_NAME \
    "Local Django Admin Username" \
    "This is only for your local development environment." \
    "admin"

  prompt_with_default \
    LEARN_OPS_SUPERUSER_PASSWORD \
    "Local Django Admin Password" \
    "This is only for your local development environment." \
    "admin"

  section_done "Configuration collection"
}

write_client_env() {
  local env_path="${CLIENT_DIR}/.env"

  if [[ -f "${env_path}" ]]; then
    ok "Client .env already exists, skipping"
    return
  fi

  cat > "${env_path}" <<'EOF'
REACT_APP_API_URI=http://localhost:8000
REACT_APP_ENV="development"
CHOKIDAR_USEPOLLING=true
GENERATE_SOURCEMAP=false
EOF

  ok "Created client .env"
}

write_env_files() {
  step "Writing environment files"

  write_api_env
  write_monarch_env
  write_client_env

  section_done "Environment files"
}

#######################################
# Validation
#######################################
validate_layout() {
  step "Validating workspace structure"

  local expected=(
    "${ROOT_DIR}"
    "${API_DIR}"
    "${CLIENT_DIR}"
    "${TARGET_INFRA_DIR}"
    "${MONARCH_DIR}"
  )

  for path in "${expected[@]}"; do
    if [[ -e "${path}" ]]; then
      ok "Found ${path}"
    else
      die "Missing expected path: ${path}"
    fi
  done

  if [[ -f "${API_DIR}/.env" ]]; then
    ok "API environment file exists"
  else
    warn "API .env not found"
  fi

  if [[ -f "${MONARCH_DIR}/.env" ]]; then
    ok "Monarch environment file exists"
  else
    warn "Monarch .env not found"
  fi

  if [[ -f "${CLIENT_DIR}/.env" ]]; then
    ok "Client environment file exists"
  else
    warn "Client .env not found"
  fi

  section_done "Workspace validation"
}

#######################################
# Summary / next steps
#######################################
show_summary() {
  step "Setup summary"

  printf "%b\n" "${BOLD}Workspace ready:${RESET} ${ROOT_DIR}"
  echo
  printf "%b\n" "${BOLD}Repositories:${RESET}"
  printf "   • %s\n" "${CLIENT_DIR}"
  printf "   • %s\n" "${API_DIR}"
  printf "   • %s\n" "${TARGET_INFRA_DIR}"
  printf "   • %s\n" "${MONARCH_DIR}"
  echo
  printf "%b\n" "${BOLD}Useful commands:${RESET}"
  printf "   • %s\n" "make setup"
  printf "   • %s\n" "make doctor"
  printf "   • %s\n" "make up"
  printf "   • %s\n" "make logs"
  printf "   • %s\n" "make down"
  echo
  printf "%b\n" "${BOLD}Expected app URLs after startup:${RESET}"
  printf "   • %s\n" "Client: http://localhost:3000"
  printf "   • %s\n" "Admin:  http://localhost:8000/admin"
  echo
  warn "If any Docker services fail to start, rerun 'make up' after fixing the issue."
  section_done "Summary"
}

open_in_browser() {
  local url="$1"
  case "${OS_FAMILY}" in
    macOS) open "${url}" ;;
    WSL)   cmd.exe /c start "${url}" 2>/dev/null || true ;;
    *)     xdg-open "${url}" 2>/dev/null || true ;;
  esac
}

monitor_services() {
  step "Monitoring services"
  substep "The API loads fixtures on first start — this may take a few minutes."
  substep "Waiting for both services to respond before continuing..."
  echo

  local api_url="http://localhost:8000/admin"
  local client_url="http://localhost:3000/"
  local timeout=600
  local interval=5
  local elapsed=0
  local api_up="false"
  local client_up="false"
  local api_code="000"
  local client_code="000"

  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    api_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${api_url}" 2>/dev/null)" || true
    client_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${client_url}" 2>/dev/null)" || true

    if [[ "${api_code}" == "200" || "${api_code}" == "302" ]]; then api_up="true"; fi
    if [[ "${client_code}" == "200" ]]; then client_up="true"; fi

    if [[ "${api_up}" == "true" && "${client_up}" == "true" ]]; then
      break
    fi

    local api_label client_label
    if   [[ "${api_up}"    == "true" ]]; then api_label="ready"
    else                                      api_label="not ready, retrying..."
    fi
    if   [[ "${client_up}"   == "true" ]]; then client_label="ready"
    else                                        client_label="not ready, retrying..."
    fi

    substep "API: ${api_label}  |  Client: ${client_label}  (${elapsed}s elapsed)"
    sleep "${interval}"
    elapsed=$(( elapsed + interval ))
  done

  echo
  if [[ "${api_up}" == "true" ]]; then
    ok "API is up  →  http://localhost:8000/admin"
  else
    err "API did not respond after ${timeout}s"
    warn "Check logs: cd ${TARGET_INFRA_DIR} && docker compose logs api"
  fi

  if [[ "${client_up}" == "true" ]]; then
    ok "Client is up  →  http://localhost:3000"
  else
    err "Client did not respond after ${timeout}s"
    warn "Check logs: cd ${TARGET_INFRA_DIR} && docker compose logs client"
  fi

  section_done "Services"
}

maybe_start_services() {
  step "Optional: start the stack now"

  substep "The first startup can take a few minutes while Docker builds images."
  substep "This command uses the docker-compose.yml in learn-ops-infrastructure."

  if confirm_yes_no "Start services now?"; then
    if ! docker network inspect learningplatform >/dev/null 2>&1; then
      docker network create learningplatform
      ok "Created Docker network: learningplatform"
    else
      ok "Docker network 'learningplatform' already exists"
    fi

    (
      cd "${TARGET_INFRA_DIR}"
      docker compose up -d
    )
    ok "Docker services started"
    warn "If your compose file only includes client/api/database today, add Valkey and Monarch there for full-stack startup."

    monitor_services

    if confirm_yes_no "Open the app in your browser?"; then
      open_in_browser "http://localhost:3000"
      open_in_browser "http://localhost:8000/admin"
    fi
  else
    warn "Skipped starting services"
    echo
    printf "%b\n" "${BOLD}When you are ready to start the stack, run:${RESET}"
    printf "   %s\n" "cd ${TARGET_INFRA_DIR} && docker compose up -d"
    echo
    printf "%b\n" "${GREEN}${BOLD}Setup complete.${RESET}"
    printf "%b\n" "${DIM}Your Learning Platform workspace is ready to use.${RESET}"
    echo
    exit 0
  fi

  section_done "Startup option"
}

#######################################
# Docker cleanup
#######################################
cleanup_docker_resources() {
  step "Checking for existing LMS Docker resources"

  local containers=() raw_images=() raw_volumes=() images=() volumes=() networks=()
  local projects=("learn-ops-infrastructure" "service-monarch")

  # Containers — compose label is reliable for all managed containers
  for project in "${projects[@]}"; do
    while IFS= read -r name; do
      [[ -n "$name" ]] && containers+=("$name")
    done < <(docker ps -a --filter "label=com.docker.compose.project=${project}" \
               --format '{{.Names}}' 2>/dev/null || true)
  done

  # From each container: collect the image it used AND its volume mounts.
  # Pulled images (postgres, grafana, prometheus, etc.) have no compose label,
  # so we must look them up via the containers that used them.
  # Anonymous volumes likewise have no compose label.
  for container in "${containers[@]+"${containers[@]}"}"; do
    local img
    img="$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)"
    [[ -n "$img" ]] && raw_images+=("$img")

    while IFS= read -r vol; do
      [[ -n "$vol" ]] && raw_volumes+=("$vol")
    done < <(docker inspect --format \
      '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' \
      "$container" 2>/dev/null || true)
  done

  # Also catch locally built images via label filter (api, client, monarch)
  for project in "${projects[@]}"; do
    while IFS= read -r img; do
      [[ -n "$img" ]] && raw_images+=("$img")
    done < <(docker images --filter "label=com.docker.compose.project=${project}" \
               --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
  done

  # Deduplicate images and volumes (docker handles duplicates gracefully, but keep output clean)
  while IFS= read -r item; do
    [[ -n "$item" ]] && images+=("$item")
  done < <(printf '%s\n' "${raw_images[@]+"${raw_images[@]}"}" | sort -u)

  while IFS= read -r item; do
    [[ -n "$item" ]] && volumes+=("$item")
  done < <(printf '%s\n' "${raw_volumes[@]+"${raw_volumes[@]}"}" | sort -u)

  # Network is external (no compose label) — check by name
  if docker network inspect learningplatform >/dev/null 2>&1; then
    networks+=("learningplatform")
  fi

  if [[ ${#containers[@]} -eq 0 && ${#images[@]} -eq 0 && \
        ${#volumes[@]} -eq 0   && ${#networks[@]} -eq 0 ]]; then
    ok "No existing LMS Docker resources found"
    section_done "Docker cleanup check"
    return
  fi

  warn "Found existing LMS Docker resources:"
  [[ ${#containers[@]} -gt 0 ]] && { printf "   Containers:\n"; printf "     • %s\n" "${containers[@]}"; }
  [[ ${#images[@]} -gt 0 ]]    && { printf "   Images:\n";     printf "     • %s\n" "${images[@]}"; }
  [[ ${#volumes[@]} -gt 0 ]]   && { printf "   Volumes:\n";    printf "     • %s\n" "${volumes[@]}"; }
  [[ ${#networks[@]} -gt 0 ]]  && { printf "   Networks:\n";   printf "     • %s\n" "${networks[@]}"; }

  echo
  if ! confirm_yes_no "Delete all of the above before continuing?"; then
    warn "Skipping cleanup — existing resources may conflict with setup"
    section_done "Docker cleanup"
    return
  fi

  [[ ${#containers[@]} -gt 0 ]] && docker rm -f "${containers[@]}"
  [[ ${#images[@]} -gt 0 ]]    && docker rmi -f "${images[@]}"
  [[ ${#volumes[@]} -gt 0 ]]   && docker volume rm "${volumes[@]}"
  [[ ${#networks[@]} -gt 0 ]]  && docker network rm "${networks[@]}"

  ok "Removed all listed LMS Docker resources"
  section_done "Docker cleanup"
}

#######################################
# Doctor mode
#######################################
doctor_mode() {
  header
  detect_platform
  check_prereqs
  check_docker_running
  ensure_workspace_root

  step "Doctor summary"
  ok "Environment looks healthy for setup"
  echo
  printf "%b\n" "${BOLD}If you want to continue:${RESET}"
  printf "   %s\n" "cd ~/workspace/lms/learn-ops-infrastructure"
  printf "   %s\n" "make setup"
  echo
}

#######################################
# Main
#######################################
main() {
  if [[ "${DOCTOR_ONLY}" == "true" ]]; then
    doctor_mode
    exit 0
  fi

  header
  detect_platform
  check_prereqs
  check_docker_running
  cleanup_docker_resources
  ensure_workspace_root
  normalize_infra_location_if_needed "$@"
  clone_workspace_repos
  collect_user_identity
  collect_config
  check_org_membership
  setup_student_forks
  write_env_files
  write_instructor_fixture
  validate_layout
  show_summary
  maybe_start_services
  run_oauth_flow

  echo
  printf "%b\n" "${GREEN}${BOLD}All done.${RESET}"
  printf "%b\n" "${DIM}Your Learning Platform workspace is ready to use.${RESET}"
  echo
}

main "$@"
