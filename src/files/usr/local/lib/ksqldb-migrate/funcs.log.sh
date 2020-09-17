KSQLDB_LOGC=KSQLDB-MIGRATE

####
# Outputs a log message to stdout. If the severity parameters isn't valid the
# message will be ignored.
#
# parameters:
# $1    severity DEBUG|INFO|WARN|ERROR
# $2    log message
# $KSQLDB_LOGC 	the log component
# $KSQLDB_LOGLEVEL	the log level (defaults to INFO)
function log(){
    DATE=`date '+%Y-%m-%dT%H:%M:%S%z'`
    POT_MSG=`echo "$DATE l=\"$1\", c=\"$KSQLDB_LOGC\", $2"`
    MSG=
    LEVEL=$KSQLDB_LOGLEVEL
    if [ -z "$LEVEL" ]; then
        LEVEL=INFO
    fi
    case "$1" in
        DEBUG)
            MSG=`[ "DEBUG" = "$LEVEL" ] && echo "$POT_MSG"`
        ;;
        INFO)
            MSG=`[ "INFO" = "$LEVEL" -o "DEBUG" = "$LEVEL" ] && echo "$POT_MSG"`
        ;;
        WARN)
            MSG=`[ "WARN" = "$LEVEL" -o "INFO" = "$LEVEL" -o "DEBUG" = "$LEVEL" ] && echo "$POT_MSG"`
        ;;
        ERROR)
            MSG=`[ "ERROR" = "$LEVEL" -o "WARN" = "$LEVEL" -o "INFO" = "$LEVEL" -o "DEBUG" = "$LEVEL" ] && echo "$POT_MSG"`
        ;;
        *) ;;
    esac

    if [ ! -z "$MSG" ]; then
        echo -e "$MSG" 1>&2
    fi
}

function logDebug(){
    log "DEBUG" "$1"
}
function logInfo(){
    log "INFO" "$1"
}
function logWarn(){
    log "WARN" "$1"
}
function logError(){
    log "ERROR" "$1"
}

