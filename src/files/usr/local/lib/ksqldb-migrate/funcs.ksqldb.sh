####
# Invokes the ksqlDB /info endpoint and outputs the contents
#
# parameters:
# $KSQLDB_URL - the server url
function ksqldb_info(){
    REST_CONTENT=`curl -sX GET "$KSQLDB_URL/info"`

    if [ ! $? -eq 0 ]; then
        return 1
    fi

    echo $REST_CONTENT  \
    | jq '.'

    return 0
}

####
# Checks whether the ksqlDB server is available
#
# parameters:
# $KSQLDB_URL - the server url
function ksqldb_isAvailable(){
    REST_CONTENT=`curl -sX GET "$KSQLDB_URL/info"`

    if [ ! $? -eq 0 ]; then
        return 1
    fi

    return 0
}

####
# Invokes the ksqlDB /healthcheck endpoint and outputs the contents.
#
# see: https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-rest-api/info-endpoint/
#
# parameters:
# $KSQLDB_URL - the server url
function ksqldb_healthcheck(){
    REST_CONTENT=`curl -sX GET "$KSQLDB_URL/healthcheck"`

    if [ ! $? -eq 0 ]; then
        return 1
    fi

    echo $REST_CONTENT  \
    | jq '.'

    return 0
}

####
# Executes a statement at the ksqlDB server.
#
# see: https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-rest-api/ksql-endpoint/
#
# parameters:
# $1 - the statement(s) to execute
# $2 - optional json object of streams properties
# $3 - optional command sequence number
# $KSQLDB_URL - the server url
#
# returns:
# stdout - the result content as returned by the ksqlDB server
function ksqldb_execute(){

    # prepare data
    local DATA=$( echo "$1" | perl -pe "s/[\n\r]/ /g" | perl -pe "s/ $//g" )
    local STREAMS_PROPS="{}"
    local COMMAND_SEQUENCE_NUMBER=""

    if [ ! -z "$2" ]; then
        STREAMS_PROPS="$2"
    fi

    if [ ! -z "$3" ]; then
        COMMAND_SEQUENCE_NUMBER=", \"commandSequenceNumber\": $3"
    fi

    read -r -d '' DATA << EOM
{"ksql": "$DATA", "streamsProperties": ${STREAMS_PROPS}${COMMAND_SEQUENCE_NUMBER}}
EOM
    local CONTENT=
    # execute call
    CONTENT=$( ksqldb_post "/ksql" "$DATA" )

    if [ ! "$?" == "0" ]; then
        return 1
    fi

    # output the server response to stdout
    echo "$CONTENT"

    return 0;
}

####
# Executes a query at the ksqlDB server.
#
# see: https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-rest-api/query-endpoint/
#
# parameters:
# $1 - the statement(s) to execute
# $2 - optional json object of streams properties
# $KSQLDB_URL - the server url
#
# returns:
# stdout - the result content as returned by the ksqlDB server
function ksqldb_query(){

    # prepare data
    local DATA=$( echo "$1" | perl -pe "s/[\n\r]/ /g" | perl -pe "s/ $//g" )
    local STREAMS_PROPS="{}"

    if [ ! -z "$2" ]; then
        STREAMS_PROPS="$2"
    fi

    read -r -d '' DATA << EOM
{"ksql": "$DATA", "streamsProperties": ${STREAMS_PROPS}}
EOM
    
    local CONTENT=
    # execute call
    CONTENT=$( ksqldb_post "/query" "$DATA" )

    if [ ! "$?" == "0" ]; then
        return 1
    fi

    # output the server response to stdout
    echo "$CONTENT"

    return 0;
}


####
# Executes an insert to a stream at the ksqlDB server.
#
# see: https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-rest-api/query-endpoint/
#
# parameters:
# $1 - the stream to insert events to
# $2 - the json objects in the form '{ <col 1>: <value>, <col 2>: <value>, ... }', multiple objects separated by newline, the objects itself must not contain any newline
# $KSQLDB_URL - the server url
#
# returns:
# stdout - the result content as returned by the ksqlDB server
function ksqldb_stream_insert(){

    # prepare data
    local DATA=$( echo -e "{\"target\": \"$1\"}\n$2\n" )

    local CONTENT=
    # execute call
    CONTENT=$( ksqldb_post_http2 "/inserts-stream" "$DATA" )

    if [ ! "$?" == "0" ]; then
        return 1
    fi

    # output the server response to stdout
    echo "$CONTENT"

    return 0;
}

####
# Does a HTTP POST against the configured ksqlDB. 
#
# Return the content on stdout.
#
# parameters:
# $1 - the path to post to
# $2 - the data to post
function ksqldb_post() {
    local HEADER=/tmp/header.$$
    local CONTENT=/tmp/content.$$
    rm -f $HEADER $CONTENT
    trap "rm -f $HEADER $CONTENT" EXIT

    curl -sX "POST" "${KSQLDB_URL}$1" \
     -H "Accept: application/vnd.ksql.v1+json" \
     -d "$2" \
     -D $HEADER \
     -o $CONTENT

    local CURL_EC=$?
    if [ ! "$CURL_EC" == "0" ]; then
        >&2 echo "curl call was not sucessfull, exit code: $CURL_EC"
        return 1
    fi

    if ! grep -q "HTTP.*2.. OK" $HEADER; then
        >&2 echo "server didn't returned 2xx, response follows:"
        >&2 cat $HEADER
        >&2 cat $CONTENT
        >&2 echo
        return 1
    fi

    # output the content to stdout
    cat $CONTENT

    return 0;
}

####
# Does a HTTP2 POST against the configured ksqlDB. 
#
# Return the content on stdout.
#
# parameters:
# $1 - the path to post to
# $2 - the data to post
function ksqldb_post_http2() {
    local HEADER=/tmp/header.$$
    local CONTENT=/tmp/content.$$
    rm -f $HEADER $CONTENT
    trap "rm -f $HEADER $CONTENT" EXIT

    curl --http2 -sX "POST" "${KSQLDB_URL}$1" \
     -d "$2" \
     -D $HEADER \
     -o $CONTENT

    local CURL_EC=$?
    if [ ! "$CURL_EC" == "0" ]; then
        >&2 echo "curl call was not sucessfull, exit code: $CURL_EC"
        return 1
    fi

    if ! grep -q "HTTP/2 200" $HEADER; then
        >&2 echo "server didn't returned 2xx, response follows:"
        >&2 cat $HEADER
        >&2 cat $CONTENT
        >&2 echo
        return 1
    fi

    # output the content to stdout
    cat $CONTENT

    return 0;
}



