#!/bin/bash

##
# This script install development local tools to make easier the getting
# started process for everyone.
#
# Usage:
#   ./utils/install-local-tools.sh
#
# For debuging something wrong in the script:
#   VERBOSE=5 ./utils/install-local-tools.sh
##


OPERATOR_SDK_VERSION="v0.18.1"
OPENSHIFT_CLIENT_ARCHIVE_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.4/openshift-client-linux.tar.gz"

VERBOSE_ERROR=1
VERBOSE_WARNING=2
VERBOSE_INFO=3
VERBOSE_TRACE=4
VERBOSE_DEBUG=5
VERBOSE_DEFAULT=$VERBOSE_WARNING
VERBOSE=${VERBOSE:-$VERBOSE_DEFAULT}


##
# Just print something out to the stderr
##
function yield
{
    echo "$*" >&2
} # yield


##
# Primitive to print out debug messages in stderr.
# $@ The message to print out.
##
function debug-msg
{
    # shellcheck disable=SC2086
    [ $VERBOSE -ge $VERBOSE_DEBUG ] && yield "DEBUG:$*"
} # debug-msg


##
# Primitive to print out trace messages in stderr.
# $@ The message to print out.
##
function trace-msg
{
    # shellcheck disable=SC2086
    [ $VERBOSE -ge $VERBOSE_TRACE ] && yield "TRACE:$*"
} # trace-msg


##
# Primitive to print out informative messages in stderr.
# $@ The message to print out.
##
function info-msg
{
    # shellcheck disable=SC2086
    [ $VERBOSE -ge $VERBOSE_INFO ] && yield "INFO:$*"
} # info-msg


##
# Primitive to print out warning messages in stderr.
# $@ The message to print out.
##
function warning-msg
{
    # shellcheck disable=SC2086
    [ $VERBOSE -ge $VERBOSE_WARNING ] && yield "WARNING:$*"
} # warning-msg


##
# Primitive to print out error messages in stderr.
# $@ The message to print out.
##
function error-msg
{
    # shellcheck disable=SC2086
    [ $VERBOSE -ge $VERBOSE_ERROR ] && yield "ERROR:$*"
} # error-msg


##
# Terminate the script execution with the last return
# code or 127 if no error code in the last operation.
# $@ Message to be printed as error into the standard
# error output.
##
function die
{
    local ERR=$?
    [ $ERR -eq 0 ] && ERR=127
    error-msg "$@"
    exit $ERR
} # die


##
# Try the operation and if it fails, finish the script
# execution.
##
function try
{
    "$@" || die "Trying '$*'"
} # try


##
# Confirmation message
##
function confirm
{
    local ans
    ans=""
    while [ "$ans" != "y" ] && [ "$ans" != "Y" ] && [ "$ans" != "n" ] && [ "$ans" != "N" ]
    do
        [ "$ans" != "" ] && echo -e "\nERROR:Please response 'y' or 'n'"
        echo -n "$* "
        read -r -n1 ans; printf "\n"
    done
    if [ "$ans" == "y" ] || [ "$ans" == "Y" ]
    then
        return 0
    else
        return 1
    fi
} # confirm


##
# Print command to be executed when VERBOSE_TRACE is set.
##
function verbose
{
    # shellcheck disable=SC2086
    [ $VERBOSE -ge $VERBOSE_TRACE ] && yield "$*"
    "$@"
} # verbose


##
# Open the URL spicified
# @param $1 The URL to be opened.
##
function open-url
{
    if command -v xdg-open 1>/dev/null && [ "$DISPLAY" != "" ]
    then
        xdg-open "$1"
    else
        echo "Can not find xdg-open or no DISPLAY found."
        echo "Please go to '$1'"
        die "Can not open URL: '$1'"
    fi
}


# Install packages
echo ">> Installing packages"
verbose sudo dnf install -y golang gcc ansible gettext \
                            less openssh-clients which \
                            podman buildah curl

# Install OpenShift Client
command -v oc 2>/dev/null 1>/dev/null || {
    echo ">> Installing Openshift Client"
    verbose curl -o "/tmp/openshift-client.tar.gz" --silent -L "$OPENSHIFT_CLIENT_ARCHIVE_URL" \
    && verbose sudo tar xzf "/tmp/openshift-client.tar.gz" -C /usr/local/bin/ \
    && oc completion bash | sudo tee /usr/share/bash-completion/completions/oc 1>/dev/null \
    && rm -f "/tmp/openshift-client.tar.gz"
} || die "When installing OpenShift client"


# Install operator-sdk
command -v operator-sdk 2>/dev/null 1>/dev/null || {
    echo ">> Installing Operator-SDK ${OPERATOR_SDK_VERSION}"
    ( verbose curl -L --silent -o "operator-sdk" "https://github.com/operator-framework/operator-sdk/releases/download/${OPERATOR_SDK_VERSION}/operator-sdk-${OPERATOR_SDK_VERSION}-$( uname -m )-linux-gnu" \
        && verbose chmod a+x operator-sdk \
        && verbose sudo mv operator-sdk /usr/local/bin/operator-sdk \
        && operator-sdk completion bash \
            | sudo tee /usr/share/bash-completion/completions/operator-sdk 1>/dev/null 
    ) || die "When installing operator-sdk"
}


# Install Visual Studio Code (optional)
command -v code 2>/dev/null 1>/dev/null || {
    echo "Visual Studio Code is an IDE which could provide a complete solution for"
    echo "working with the different technologies used with operator-sdk"
    confirm "Do you want to install Visual Studio Code?" && {
        echo ">> Installing repository for 'code' package"
        sudo rpm --import "https://packages.microsoft.com/keys/microsoft.asc"
        cat <<EOF | sudo tee /etc/yum.repos.d/vscode.repo 1>/dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
        dnf check-update
        echo ">> Installing Visual Studio Code"
        sudo dnf install -y code
        echo "Recommended plug-ins"
        echo "  - Go"
        echo "  - Ansible"
        echo "  - YAML"
        echo "  - OpenShift Extension Pack"
        echo "  - Knative"
    }
    command -v code 2>/dev/null 1>/dev/null \
    && echo ">> Visual Studio Code is installed" \
    && confirm "Do you want to open Visual Studio Code now?" \
    && code .
}


# Install CodeReady Containers
! command -v crc 2>/dev/null 1>/dev/null \
&& confirm "Do you want to install CodeReady Container?" && {
    echo ">> Installing CodeReadyContainer"
    [ ! -e pull-secret ] && [ ! -e "$( xdg-user-dir DOWNLOAD )/pull-secret" ] && {
        echo "ERROR:File '$PWD/pull-secret' does not exist"
        echo ">> Please download 'pull-secret' file in your Download file"
        echo "Opening browser for getting it at: https://cloud.redhat.com/openshift/install/crc/installer-provisioned"
        open-url "https://cloud.redhat.com/openshift/install/crc/installer-provisioned"
        echo "INFO: Rerun 'install-local-tools.sh' when the file has been downloaded"
        exit 1
    }
    if [ ! -e pull-secret ] && [ -e "$( xdg-user-dir DOWNLOAD )/pull-secret" ]
    then
        mv "$( xdg-user-dir DOWNLOAD )/pull-secret" "$PWD/pull-secret"
    fi
    [ ! -e pull-secret ] && die "Can not find 'pull-secret' file"

    [ ! -e crc-linux-amd64.tar.xz ] && [ ! -e "$( xdg-user-dir DOWNLOAD )/crc-linux-amd64.tar.xz" ] && {
        echo "ERROR:File '${PWD}/crc-linux-amd64.tar.xz' does not exist"
        echo "Opening browser for getting it at: https://cloud.redhat.com/openshift/install/crc/installer-provisioned"
        echo "Please download the linux version and copy it to '${PWD}' directory."
        open-url "https://cloud.redhat.com/openshift/install/crc/installer-provisioned"
        echo "INFO: Rerun 'install-local-tools' when the file has been downloaded"
        exit 1
    }
    [ -e crc-linux-amd64.tar.xz ] || mv "$( xdg-user-dir DOWNLOAD )/crc-linux-amd64.tar.xz" "crc-linux-amd64.tar.xz"

    # Extracting crc binary
    [ ! -e crc-linux ] || rm -rf crc-linux
    mkdir crc-linux
    try tar xf crc-linux-amd64.tar.xz -C ./crc-linux --strip-components 1 \
    && ( [ -e "${HOME}/.local/bin" ] || mkdir -p "${HOME}/.local/bin" ) \
    && cp -f crc-linux/crc "${HOME}/.local/bin/crc" \
    && rm -rf crc-linux

    echo ">> Deploying VM with OpenShift"
    verbose crc setup
    verbose crc start --cpus 6 --memory 16384 --pull-secret-file "${PWD}/pull-secret"

    cat <<EOF
>> Local CodeReadyContainer cluster
To create the local cluster run 'crc start --pull-secret-file $PWD/pull-secret' 
EOF
    crc console --credentials
}

