#!/bin/bash

function stripColors {
  echo "${1}" | sed 's/\x1b\[[0-9;]*m//g'
}

function hasPrefix {
  case ${2} in
    "${1}"*)
      true
      ;;
    *)
      false
      ;;
  esac
}

function parseInputs {
  # Required inputs
  if [ "${INPUT_TF_ACTIONS_VERSION}" != "" ]; then
    tfVersion=${INPUT_TF_ACTIONS_VERSION}
  else
    echo "Input terraform_version cannot be empty"
    exit 1
  fi

  if [ "${INPUT_TG_ACTIONS_VERSION}" != "" ]; then
    tgVersion=${INPUT_TG_ACTIONS_VERSION}
  else
    echo "Input terragrunt_version cannot be empty"
    exit 1
  fi

  if [ "${INPUT_TF_ACTIONS_SUBCOMMAND}" != "" ]; then
    tfSubcommand=${INPUT_TF_ACTIONS_SUBCOMMAND}
  else
    echo "Input terraform_subcommand cannot be empty"
    exit 1
  fi

  # Optional inputs
  tfWorkingDir="."
  if [[ -n "${INPUT_TF_ACTIONS_WORKING_DIR}" ]]; then
    tfWorkingDir=${INPUT_TF_ACTIONS_WORKING_DIR}
  fi

  tfBinary="terragrunt"
  if [[ -n "${INPUT_TF_ACTIONS_BINARY}" ]]; then
    tfBinary=${INPUT_TF_ACTIONS_BINARY}
  fi

  tfComment=0
  if [ "${INPUT_TF_ACTIONS_COMMENT}" == "1" ] || [ "${INPUT_TF_ACTIONS_COMMENT}" == "true" ]; then
    tfComment=1
  fi

  tfCLICredentialsHostname=""
  if [ "${INPUT_TF_ACTIONS_CLI_CREDENTIALS_HOSTNAME}" != "" ]; then
    tfCLICredentialsHostname=${INPUT_TF_ACTIONS_CLI_CREDENTIALS_HOSTNAME}
  fi

  tfCLICredentialsToken=""
  if [ "${INPUT_TF_ACTIONS_CLI_CREDENTIALS_TOKEN}" != "" ]; then
    tfCLICredentialsToken=${INPUT_TF_ACTIONS_CLI_CREDENTIALS_TOKEN}
  fi

  tfFmtWrite=0
  if [ "${INPUT_TF_ACTIONS_FMT_WRITE}" == "1" ] || [ "${INPUT_TF_ACTIONS_FMT_WRITE}" == "true" ]; then
    tfFmtWrite=1
  fi

  tfWorkspace="default"
  if [ -n "${TF_WORKSPACE}" ]; then
    tfWorkspace="${TF_WORKSPACE}"
  fi
}

function configureCLICredentials {
  if [[ ! -f "${HOME}/.terraformrc" ]] && [[ "${tfCLICredentialsToken}" != "" ]]; then
    cat > ${HOME}/.terraformrc << EOF
credentials "${tfCLICredentialsHostname}" {
  token = "${tfCLICredentialsToken}"
}
EOF
  fi
}

function installTerraform {
  if [[ "${tfVersion}" == "latest" ]]; then
    echo "Checking the latest version of Terraform"
    tfVersion=$(curl -sL https://releases.hashicorp.com/terraform/index.json | jq -r '.versions[].version' | grep -v '[-].*' | sort -rV | head -n 1)

    if [[ -z "${tfVersion}" ]]; then
      echo "Failed to fetch the latest version"
      exit 1
    fi
  fi

  url="https://releases.hashicorp.com/terraform/${tfVersion}/terraform_${tfVersion}_linux_amd64.zip"

  echo "Downloading Terraform v${tfVersion}"
  status_code=$(curl -s -S -L -o /tmp/terraform_${tfVersion} --write-out "%{http_code}" ${url})
  if [ "${?}" -ne 0 ] || [ "${status_code}" -ne "200" ]; then
    echo "Failed to download Terraform v${tfVersion}"
    exit 1
  fi
  echo "Successfully downloaded Terraform v${tfVersion}"

  echo "Unzipping Terraform v${tfVersion}"
  unzip -d /usr/local/bin /tmp/terraform_${tfVersion} &> /dev/null
  if [ "${?}" -ne 0 ]; then
    echo "Failed to unzip Terraform v${tfVersion}"
    exit 1
  fi
  echo "Successfully unzipped Terraform v${tfVersion}"
}

function installTerragrunt {
  if [[ "${tgVersion}" == "latest" ]]; then
    echo "Checking the latest version of Terragrunt"
    latestURL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/gruntwork-io/terragrunt/releases/latest)
    tgVersion=${latestURL##*/}

    if [[ -z "${tgVersion}" ]]; then
      echo "Failed to fetch the latest version"
      exit 1
    fi
  fi

  url="https://github.com/gruntwork-io/terragrunt/releases/download/v${tgVersion}/terragrunt_linux_amd64"

  echo "Downloading Terragrunt v${tgVersion}"
  status_code=$(curl -s -S -L -o /tmp/terragrunt --write-out "%{http_code}" ${url})

  if [ "${?}" -ne 0 ] || [ "${status_code}" -ne "200" ]; then
    echo "Failed to download Terragrunt v${tgVersion}"
    exit 1
  fi
  echo "Successfully downloaded Terragrunt v${tgVersion}"

  echo "Moving Terragrunt v${tgVersion} to PATH"
  chmod +x /tmp/terragrunt
  mv /tmp/terragrunt /usr/local/bin/terragrunt 
  if [ "${?}" -ne 0 ]; then
    echo "Failed to move Terragrunt v${tgVersion}"
    exit 1
  fi
  echo "Successfully moved Terragrunt v${tgVersion}"
}

function loadCreds {
  echo "Loading creds"
  echo -n "$GOOGLE_CREDENTIALS_FILE" > /tmp/cred.json
  export GOOGLE_CREDENTIALS=$(cat /tmp/cred.json | tr -d '\n')
}

function loadSSH {
  if [ "$INPUT_SSH_KEY" != "" ]; then
    echo "Loading SSH key"
    ssh-agent -a $SSH_AUTH_SOCK > /dev/null
    ssh-add - <<< "INPUT_SSH_KEY"
    ssh-add -l

    echo "Adding GitHub.com keys"
    ssh-keyscan github.com >> ~/.ssh/known_hosts
  fi
}

function main {
  loadCreds

  # Source the other files to gain access to their functions
  scriptDir=$(dirname ${0})
  source ${scriptDir}/terragrunt_fmt.sh
  source ${scriptDir}/terragrunt_init.sh
  source ${scriptDir}/terragrunt_validate.sh
  source ${scriptDir}/terragrunt_plan.sh
  source ${scriptDir}/terragrunt_apply.sh
  source ${scriptDir}/terragrunt_output.sh
  source ${scriptDir}/terragrunt_import.sh
  source ${scriptDir}/terragrunt_taint.sh
  source ${scriptDir}/terragrunt_destroy.sh

  parseInputs
  configureCLICredentials
  installTerraform
  cd ${GITHUB_WORKSPACE}/${tfWorkingDir}

  case "${tfSubcommand}" in
    fmt)
      installTerragrunt
      terragruntFmt ${*}
      ;;
    init)
      installTerragrunt
      terragruntInit ${*}
      ;;
    validate)
      installTerragrunt
      terragruntValidate ${*}
      ;;
    plan)
      installTerragrunt
      terragruntPlan ${*}
      ;;
    apply)
      installTerragrunt
      terragruntApply ${*}
      ;;
    output)
      installTerragrunt
      terragruntOutput ${*}
      ;;
    import)
      installTerragrunt
      terragruntImport ${*}
      ;;
    taint)
      installTerragrunt
      terragruntTaint ${*}
      ;;
    destroy)
      installTerragrunt
      terragruntDestroy ${*}
      ;;
    *)
      echo "Error: Must provide a valid value for terragrunt_subcommand"
      exit 1
      ;;
  esac
}

main "${*}"
