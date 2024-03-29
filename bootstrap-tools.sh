#!/usr/bin/env bash
#
# Author: aleks@crowdai.com
#
# Installs a set of common tools for development at CrowdAI.

set -o errexit
set -o nounset
set -o pipefail

readonly minimum_git_version=(2 0 0)
readonly minimum_python_version=(3 6 6)
readonly minimum_docker_compose_version=(1 23 2)
readonly minimum_vault_version=(0 9 3)

readonly PYTHON="$(which python3)"
readonly PIP="${PYTHON} -m pip"

# --- BEGIN parse options
interactive=true
aws_configure=true
auto_configure_rc=false

while [[ $# -gt 0 ]]; do
  case ${1-x} in
    --non-interactive)
      interactive=false;
      aws_configure=false;
      auto_configure_rc=true ;;
    --skip-aws-configure)
      aws_configure=false ;;
    --auto-configure-rc)
      auto_configure_rc=true ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2 ;
      exit 1 ;;
  esac
  shift
done

# --- END parse options

UNAME="$(uname -s)"
ARCH="$(uname -m)"

SUDO="sudo -EH"
if [[ ${interactive} == false ]]; then
  SUDO="${SUDO} --non-interactive"
fi

BLUE="$(tput -Txterm setaf 4)"
RED="$(tput -Txterm setaf 1)"
YLW="$(tput -Txterm setaf 3)"
GRN="$(tput -Txterm setaf 2)"
CLR="$(tput -Txterm sgr0)"

echomsg() {
  echo "${BLUE}$1${CLR}"
}
echogood() {
  echo "${GRN}$1${CLR}"
}
echowarn() {
  echo "${YLW}$1${CLR}"
}
echoerr() {
  echo "${RED}$1${CLR}" >&2
}

prompt_and_exit() {
  echo
  echowarn "##### Rerun this script once you've fixed the above error."
  exit 1
}

temppushd() { _tempdir=$(mktemp -d) && pushd "$_tempdir" >/dev/null; }
temppopd() { popd >/dev/null && rm -rf "$_tempdir"; }

join_array() { local IFS="$1"; shift; echo "$*"; }

is_pip_installed() {
  local program="$1"
  if ! ${PIP} show "${program}" >/dev/null 2>&1; then
    echoerr "${YLW}${program}${RED} not installed."
    return 1
  fi
}
is_installed() {
  local program="$1"
  if ! hash "${program}" 2>/dev/null; then
    echoerr "${YLW}${program}${RED} not installed."
    return 1
  fi
}
semver_check() {
  local major="$1"
  local minor="$2"
  local patch="$3"
  local min_major="$4"
  local min_minor="$5"
  local min_patch="$6"
  if (( major < min_major )); then return 1; elif (( major > min_major )); then return 0; fi
  if (( minor < min_minor )); then return 1; elif (( minor > min_minor )); then return 0; fi
  if (( patch < min_patch )); then return 1; elif (( patch > min_patch )); then return 0; fi
  return 0
}
installed_version() {
  local program="$1"
  if ! is_installed "${program}"; then
    return 2
  fi

  local program_semver
  read -r -a program_semver <<< "$("${program}" --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' \
      | awk '{split($1, a, "."); print a[1],a[2],a[3]}')"

  local min_semver=("$2" "$3" "$4")
  if ! semver_check "${program_semver[@]}" "${min_semver[@]}"; then
    echoerr "Expected ${YLW}${program}${RED} version >= $(join_array '.' "${min_semver[@]}")"
    echoerr "Found $(join_array '.' "${program_semver[@]}")"
    return 1
  fi
}

if [[ ${EUID} -eq 0 ]]; then
  echowarn 'Please run this script without sudo.'
  exit 1
fi

mkdir -p ~/.crowdai
curl -fsSL https://raw.githubusercontent.com/crowd-ai/bootstrap/master/crowdai-env > ~/.crowdai/crowdai-env
chmod +x ~/.crowdai/crowdai-env
if [[ ! -e /usr/local/bin/crowdai-env ]]; then
  echomsg 'Need sudo password to install link crowdai-env binary...'
  ${SUDO} ln -s ~/.crowdai/crowdai-env /usr/local/bin/crowdai-env
fi

if [[ -z ${CROWDAI_ENV_INITIALIZED+x} ]]; then
  INIT_SCRIPT='if hash crowdai-env 2>/dev/null; then eval "$(crowdai-env)"; fi'

  if [[ "${auto_configure_rc}" != "true" ]]; then
    echomsg 'Please add the following snippet to your shell .rc file and then restart your shell:'
    echo "${INIT_SCRIPT}"
    prompt_and_exit
  fi

  if [[ "${SHELL}" == *bash ]]; then
    RCFILE=~/.bashrc
  elif [[ "${SHELL}" == *zsh ]]; then
    RCFILE=~/.zshrc
  else
    echomsg 'Please add the following snippet to your shell .rc file and then restart your shell:'
    echo "${INIT_SCRIPT}"
    prompt_and_exit
  fi

  echo "${INIT_SCRIPT}" >> "${RCFILE}"
  echomsg "The following to snippet has been automatically appended to ${RCFILE}"
  echo "${INIT_SCRIPT}"
  echo
  echowarn "Please restart your shell!"
  eval "$(crowdai-env)"
fi

if ! installed_version git "${minimum_git_version[@]}"; then
  echomsg "Please update your git installation."
  prompt_and_exit
fi

if [[ "${UNAME}" == "Darwin" ]] && ! is_installed realpath; then
  echomsg 'Installing coreutils for MacOS'
  brew install --upgrade coreutils

  echogood 'Installed coreutils'
fi

if ! installed_version ${PYTHON} "${minimum_python_version[@]}"; then
  echomsg "Please update your Python installation."
  echomsg "We recommend using https://github.com/pyenv/pyenv"
  prompt_and_exit
fi

if ! ${PIP} >/dev/null 2>&1; then
  echoerr "pip not installed for Python3!"
  echomsg "attempting to automatically install..."

  temppushd

  echomsg 'Need sudo password to install pip...'
  wget --quiet -O- https://bootstrap.pypa.io/get-pip.py | ${SUDO} ${PYTHON} -
  ${PIP} install --upgrade pip

  temppopd
fi

if ! is_pip_installed awscli; then
  echomsg 'Need sudo password to install awscli...'
  # shellcheck disable=SC2086
  ${SUDO} ${PIP} install --upgrade awscli
fi

if [[ "${aws_configure}" == "true" ]] && ! aws configure get aws_access_key_id >/dev/null 2>&1; then
  echoerr "Please configure your AWS credentials:"
  aws configure
  echogood 'AWS credentials configured.'
fi

if ! is_installed docker; then
  echomsg "Please follow instructions to install here: https://docs.docker.com/install"
  prompt_and_exit
fi

if ! is_pip_installed docker-compose || ! installed_version docker-compose "${minimum_docker_compose_version[@]}"; then
  echomsg 'Attempting to automatically install...'

  echomsg 'Need sudo password to install docker-compose...'
  # shellcheck disable=SC2086
  ${SUDO} ${PIP} install --upgrade docker-compose
fi

if ! installed_version vault "${minimum_vault_version[@]}"; then
  echomsg "Attempting to automatically install..."

  if [[ "${UNAME}" == "Darwin" ]]; then
    brew install vault

  elif [[ "${UNAME}" == 'Linux' ]] && hash pacman 2>/dev/null; then  # Arch
    echomsg "Need sudo to install vault through package manager..."
    ${SUDO} pacman -Sy vault

  elif [[ "${UNAME}" == 'Linux' && $ARCH == 'x86_64' ]]; then
    temppushd

    if ! hash unzip; then
      if hash apt-get 2>/dev/null; then
        echomsg "Need sudo to install unzip through package manager..."
        ${SUDO} apt-get update
        ${SUDO} apt-get install unzip
      else
        echoerr "Couldn't find unzip program on \$PATH"
        echomsg "Please install ${YLW}unzip${BLUE} through your package manager, then rerun this script."
        prompt_and_exit
      fi
    fi

    wget --quiet -O vault.zip 'https://releases.hashicorp.com/vault/0.10.1/vault_0.10.1_linux_amd64.zip'
    unzip vault.zip
    echomsg 'Need sudo password to move vault binary into /usr/local/bin...'
    ${SUDO} chmod +x vault
    ${SUDO} mv vault /usr/local/bin/vault

    temppopd

  else
    echoerr "Unable to automatically install for ${UNAME} platform."
    echomsg "Please download latest binary from https://www.vaultproject.io/downloads.html, then move into \$PATH"
    prompt_and_exit
  fi

  echogood 'Installed Hashicorp Vault'
fi
cat <<EOF > ~/.crowdai/vault.env
export VAULT_ADDR='https://vault-blue.crowdai.com'
EOF

if ! is_installed jq; then
  echomsg "Attempting to automatically install..."

  if [[ "${UNAME}" == "Darwin" ]]; then
    brew install jq

  elif [[ "${UNAME}" == 'Linux' ]] && hash apt-get 2>/dev/null; then  # Debian and Ubuntu
    echomsg "Need sudo to install jq through package manager..."
    ${SUDO} apt-get update
    ${SUDO} apt-get install jq

  elif [[ "${UNAME}" == 'Linux' ]] && hash pacman 2>/dev/null; then  # Arch
    echomsg "Need sudo to install jq through package manager..."
    ${SUDO} pacman -Sy jq

  else
    echoerr "Unable to automatically install jq for ${UNAME} platform."
    echomsg "Please download latest from https://stedolan.github.io/jq/download/"
    prompt_and_exit
  fi

  echogood 'Installed jq'
fi

if ! is_installed consul-template; then
  echomsg 'Attempting to automatically install...'

  if [[ "${UNAME}" == "Darwin" ]]; then
    brew install consul-template

  elif [[ "${UNAME}" == 'Linux' ]] && hash yay 2>/dev/null; then  # Arch
    yay -Syu consul-template

  elif [[ "${UNAME}" == 'Linux' && "${ARCH}" == 'x86_64' ]]; then
    temppushd

    wget --quiet -O consul-template.tgz 'https://releases.hashicorp.com/consul-template/0.19.4/consul-template_0.19.4_linux_amd64.tgz'
    tar xf consul-template.tgz
    echomsg 'Need sudo password to move consul-template binary into /usr/local/bin...'
    ${SUDO} mv consul-template /usr/local/bin/consul-template

    temppopd

  else
    echoerr "Unable to automatically install for ${UNAME} platform."
    echomsg "Please download latest binary from https://releases.hashicorp.com/consul-template, then move into \$PATH"
    prompt_and_exit
  fi
fi

echo
echogood 'CrowdAI Tools Bootstrap complete! 🎉'
