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
        die "Can not open '$1' URL. No xdg-open or DISPLAY found"
    fi
}


##
# Call sudo when no root user yet.
##
function get-root
{
    uid="$( id -u )"
    if [ $uid -eq 0 ]
    then
        "$@"
    else
        sudo "$@"
    fi
}
