#!/usr/bin/env bash
#
# Author: aleks@crowdai.com
#
# Installs a set of common tools for development at CrowdAI.

set -o errexit
set -o nounset
set -o pipefail

UNAME=$(uname -s)
ARCH=$(uname -m)

BLUE=$(tput -Txterm setaf 4)
RED=$(tput -Txterm setaf 1)
YLW=$(tput -Txterm setaf 3)
GRN=$(tput -Txterm setaf 2)
CLR=$(tput -Txterm sgr0)
echomsg() { echo "${BLUE}$1${CLR}"; }
echogood() { echo "${GRN}$1${CLR}"; }
echowarn() { echo "${YLW}$1${CLR}"; }
echoerr() { echo "${RED}$1${CLR}" >&2; }

prompt_and_exit() {
  echo
  echowarn "##### Rerun this script once you've fixed the above error."
  exit 1
}

temppushd() { _tempdir=$(mktemp -d) && pushd "$_tempdir" >/dev/null; }
temppopd() { popd >/dev/null && rm -rf "$_tempdir"; }

join_array() { local IFS="$1"; shift; echo "$*"; }

installed() {
  local program=$1
  if ! hash "$program" 2>/dev/null; then
    echoerr "${YLW}$program${RED} not installed."
    return 1
  fi
}
semver_check() {
  local major=$1
  local minor=$2
  local patch=$3
  local min_major=$4
  local min_minor=$5
  local min_patch=$6
  if (( major < min_major )); then return 1; elif (( major > min_major )); then return 0; fi
  if (( minor < min_minor )); then return 1; elif (( minor > min_minor )); then return 0; fi
  if (( patch < min_patch )); then return 1; elif (( patch > min_patch )); then return 0; fi
  return 0
}
installed_version() {
  local program=$1
  if ! installed "$program"; then
    return 2
  fi

  local program_semver
  read -r -a program_semver <<< "$("$program" --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' \
      | awk '{split($1, a, "."); print a[1],a[2],a[3]}')"

  local min_semver=("$2" "$3" "$4")
  if ! semver_check "${program_semver[@]}" "${min_semver[@]}"; then
    echoerr "Expected ${YLW}$program${RED} version >= $(join_array '.' "${min_semver[@]}")"
    echoerr "Found $(join_array '.' "${program_semver[@]}")"
    return 1
  fi
}

if [[ $EUID -eq 0 ]]; then
  echomsg 'Please run this script without sudo.'
  exit 1
fi

if [[ $UNAME == Darwin ]] && ! installed realpath; then
  echomsg 'Installing coreutils for MacOS'
  brew install --upgrade coreutils

  echogood 'Installed coreutils'
fi

minimum_py3_version=(3 5 2)
if ! installed_version python3 "${minimum_py3_version[@]}"; then
  echomsg "Please update your Python installation."
  echomsg "We recommend using https://github.com/pyenv/pyenv"
  prompt_and_exit
fi

if ! python3 -m pip >/dev/null 2>&1; then
  echoerr "pip not installed for Python3!"
  echomsg "attempting to automatically install..."

  temppushd

  echomsg 'Need sudo password to install pip...'
  wget --quiet -O- https://bootstrap.pypa.io/get-pip.py | sudo -H python3 -
  python3 -m pip install --upgrade pip

  temppopd
fi

if ! installed aws; then
  echomsg 'Need sudo password to install awscli...'
  sudo -H python3 -m pip install --upgrade awscli
fi

if ! aws configure get aws_access_key_id >/dev/null 2>&1; then
  echoerr "Please configure your AWS credentials:"
  aws configure
  echogood 'AWS credentials configured.'
fi

if ! installed docker; then
  echomsg "Please follow instructions to install here: https://docs.docker.com/install"
  prompt_and_exit
fi

if ! installed_version docker-compose 1 21 1; then
  echomsg 'Attempting to automatically install...'

  echomsg 'Need sudo password to install docker-compose...'
  sudo -H python3 -m pip install --upgrade docker-compose
fi

if ! installed_version vault 0 9 3; then
  echomsg "Attempting to automatically install..."

  if [[ $UNAME == Darwin ]]; then
    brew install --upgrade vault

  elif [[ $UNAME == 'Linux' && $ARCH == 'x86_64' ]]; then
    temppushd

    if ! hash unzip; then
      if hash apt-get 2>/dev/null; then
        echomsg "Need sudo to install unzip through package manager..."
        sudo apt-get update
        sudo apt-get install unzip
      else
        echoerr "Couldn't find unzip program on \$PATH"
        echomsg "Please install ${YLW}unzip${BLUE} through your package manager, then rerun this script."
        prompt_and_exit
      fi
    fi

    wget --quiet -O vault.zip 'https://releases.hashicorp.com/vault/0.10.1/vault_0.10.1_linux_amd64.zip'
    unzip vault.zip
    echomsg 'Need sudo password to move vault binary into /usr/local/bin...'
    sudo chmod +x vault
    sudo mv vault /usr/local/bin/vault

    temppopd

  else
    echoerr "Unable to automatically install for $UNAME platform."
    echomsg "Please download latest binary from https://www.vaultproject.io/downloads.html, then move into \$PATH"
    prompt_and_exit
  fi

  echogood 'Installed Hashicorp Vault'
fi

if ! installed jq; then
  echomsg "Attempting to automatically install..."

  if [[ $UNAME == Darwin ]]; then
    brew install jq

  elif [[ $UNAME == 'Linux' ]] && hash apt-get 2>/dev/null; then  # Debian and Ubuntu
    echomsg "Need sudo to install jq through package manager..."
    sudo apt-get update
    sudo apt-get install jq

  elif [[ $UNAME == 'Linux' ]] && hash pacman 2>/dev/null; then  # Arch
    echomsg "Need sudo to install jq through package manager..."
    sudo pacman -Sy jq

  else
    echoerr "Unable to automatically install jq for $UNAME platform."
    echomsg "Please download latest from https://stedolan.github.io/jq/download/"
    prompt_and_exit
  fi

  echogood 'Installed jq'
fi

if ! installed consul-template; then
  echomsg 'Attempting to automatically install...'

  if [[ $UNAME == Darwin ]]; then
    brew install consul-template

  elif [[ $UNAME == 'Linux' && $ARCH == 'x86_64' ]]; then
    temppushd

    wget --quiet 'https://releases.hashicorp.com/consul-template/0.19.4/consul-template_0.19.4_linux_amd64.tgz'
    tar xf consul-template.*
    echomsg 'Need sudo password to move consul-template binary into /usr/local/bin...'
    sudo mv consul-template /usr/local/bin/consul-template

    temppopd

  else
    echoerr "Unable to automatically install for $UNAME platform."
    echomsg "Please download latest binary from https://releases.hashicorp.com/consul-template, then move into \$PATH"
    prompt_and_exit
  fi
fi

echo
echogood 'CrowdAI Tools Bootstrap complete! 🎉'
