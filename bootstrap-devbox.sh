#!/usr/bin/env bash
#
# Author: aleks@crowdai.com
#
# Bootstraps a devbox with the latest Inca and Aztec things
# Assumes Inca is at ~/inca and Aztec is at ~/aztec_platform

set -o errexit
set -o nounset
set -o pipefail

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

if [[ "${EUID}" -eq 0 ]]; then
  echowarn 'Please run this script without sudo.'
  exit 1
fi

if ! ssh-add -l >/dev/null 2>&1; then
  echoerr "Could not open a connection to your ssh authentication agent!"
  echoerr "This means we can't update the git repos on this devbox."
  echo
  echowarn "Please re-ssh to this server using the ${GRN}-A${YLW} flag. This securely forwards your ssh keys."
  echowarn "If you've set up ${GRN}crowdai-ssh${YLW} correctly, this should already be the default."
  echo
  echowarn "###################################################"
  echowarn "DO NOT COPY YOU SSH KEYS ONTO THIS SERVER USING SCP"
  echowarn "###################################################"
  exit 1
fi

update_git_repo() {
  declare which_repo="$1"
  echomsg '#################################'
  echomsg "Updating ${which_repo} git repo"
  echomsg '#################################'
  git checkout dev
  if ! git pull origin dev; then
    echo
    echoerr "Could not update ${which_repo} git repo!"
    echo
    echowarn "Do you have your Github SSH key loaded added to your ssh agent keychain?"
    echowarn "Run ${GRN}ssh-add -l${YLW} to check if your Github key is loaded."
    echo
    exit 1
  fi
}

cd "${HOME}/inca"
update_git_repo "Inca"

cd "${HOME}/aztec_platform"
update_git_repo "Aztec"

cd "${HOME}/inca"
echomsg '#################################'
echomsg 'Bootstrapping CrowdAI tools and Inca'
echomsg '#################################'
./scripts/bootstrap-dev-server.sh

mkdir -p "${HOME}/.crowdai"
touch "${HOME}/.crowdai/devbox-bootstrapped-successfully"

echo
echogood 'Done boostrapping devbox!'
echowarn "##### Please source your shell .rc file or restart your shell!"
echo
echogood 'Happy coding! 🎉'
