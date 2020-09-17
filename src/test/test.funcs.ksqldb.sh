#!/bin/bash
#
# Tests for lib/ksqldb-migrate/funcs.ksqldb.sh

#### CONSTANTS ################################################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
KSQLDB_DIR_LIB=$DIR/../files/usr/local/lib/ksqldb-migrate

#### GLOBAL FUNCTIONS #########################################################

. $KSQLDB_DIR_LIB/funcs.ksqldb.sh

#### GLOBAL VARIABLES #########################################################

KSQLDB_URL="http://127.0.0.1:1234"

#### TESTS ####################################################################

#### test_ksqldb_info

function test_ksqldb_info__sends_correct_headers() {
    server_start

    ( ksqldb_info ) &

    server_stop

    if ! assert_server_request_content "GET /info"; then return 1; fi

}

#### test_ksqldb_healthcheck

function test_ksqldb_healthcheck__sends_correct_headers() {
    server_start

    ( ksqldb_healthcheck ) &

    server_stop

    if ! assert_server_request_content "GET /healthcheck"; then return 1;fi

}

#### test_ksqldb_isAvailable

function test_ksqldb_isAvailable__server_not_started() {

    if ksqldb_isAvailable; then echo "expected return value 1, was 0"; return 1; fi

}

function test_ksqldb_isAvailable__server_started() {
    
    if ! execute_server_call "hello world" "ksqldb_isAvailable"; then echo "expected return value 0, was 1"; return 1; fi

}

#### test_ksqldb_post

function test_ksqldb_post__sends_correct_headers() {

    local URL_PATH="/path"
    
    server_start

    ( ksqldb_post "$URL_PATH" "STATEMENT" &> /dev/null ) &

    server_stop

    if ! assert_server_request_content "POST $URL_PATH"; then return 1; fi
    if ! assert_server_request_content "Accept: application/vnd.ksql.v1+json"; then return 1; fi

}

function test_ksqldb_post__sends_correct_content() {

    # please note we are expecting the linefeed being send
    local CONTENT=$'LINE1\nLINE2'

    server_start

    ( ksqldb_post "/" "$CONTENT" &> /dev/null ) &

    server_stop

    if ! assert_server_request_content "$CONTENT"; then return 1; fi

}

function test_ksqldb_post__handles_404() {
    
    execute_server_call $'HTTP/1.1 400 Not Found\r\n\r\nThis is content.' "ksqldb_post" "/" "S" &> /dev/null

    if [ ! $? -eq 1 ]; then echo "404s must be returned with return code 1, but was 0"; return 1; fi

}

#### test_ksqldb_execute

function test_ksqldb_execute__sends_correct_headers() {

    local URL_PATH="/ksql"
    
    server_start

    ( ksqldb_execute "$URL_PATH" "STATEMENT" &> /dev/null ) &

    server_stop

    if ! assert_server_request_content "POST $URL_PATH"; then return 1; fi
    if ! assert_server_request_content "Accept: application/vnd.ksql.v1+json"; then return 1; fi

}

function test_ksqldb_execute__sends_correct_content__without_streamsProperties() {

    # note that we are expecting '\r', '\n' to be replaced by ' '
    local STATEMENT=$'SELECT a,\r\nb\nFROM c;'
    local STMT_EXPECTED=$'SELECT a,  b FROM c;'

    server_start

    ( ksqldb_execute "$STATEMENT" &> /dev/null ) &

    server_stop

    read -r -d '' EXPECTED << EOM
{"ksql": "${STMT_EXPECTED}", "streamsProperties": {}}
EOM

    if ! assert_server_request_content "$EXPECTED"; then return 1; fi

}

function test_ksqldb_execute__sends_correct_content__with_streamsProperties_without_commandSequence() {

    server_start

    ( ksqldb_execute "S (P='V');" '{"p": "v"}' &> /dev/null ) &

    server_stop

    read -r -d '' EXPECTED << EOM
{"ksql": "S (P='V');", "streamsProperties": {"p": "v"}}
EOM

    if ! assert_server_request_content "$EXPECTED"; then return 1; fi

}

function test_ksqldb_execute__sends_correct_content__with_commandSequence() {

    server_start

    ( ksqldb_execute "S (P='V');" '{"p": "v"}' 123 &> /dev/null ) &

    server_stop

    read -r -d '' EXPECTED << EOM
{"ksql": "S (P='V');", "streamsProperties": {"p": "v"}, "commandSequenceNumber": 123}
EOM

    if ! assert_server_request_content "$EXPECTED"; then return 1; fi

}

function test_ksqldb_execute__returns_server_response() {
    
    local EXPECTED="STUFF RETURNED"
    local RESPONSE=`execute_server_call $'HTTP/1.1 200 OK\r\n\r\nSTUFF RETURNED' "ksqldb_execute" "S1; S2;"`

    if [ ! "$RESPONSE" == "$EXPECTED" ]; then echo "the content returned must be '$EXPECTED', but was '$RESPONSE'"; return 1; fi

}

function test_ksqldb_execute__handles_404() {
    
    execute_server_call $'HTTP/1.1 400 Not Found\r\n\r\nThis is content.' "ksqldb_execute" "S" &> /dev/null

    if [ ! $? -eq 1 ]; then echo "404s must be returned with return code 1, but was 0"; return 1; fi

}

#### test_ksqldb_query

function test_ksqldb_query__sends_correct_headers() {

    local URL_PATH="/query"
    
    server_start

    ( ksqldb_query "$URL_PATH" "STATEMENT" &> /dev/null ) &

    server_stop

    if ! assert_server_request_content "POST $URL_PATH"; then return 1; fi
    if ! assert_server_request_content "Accept: application/vnd.ksql.v1+json"; then return 1; fi

}

function test_ksqldb_query__sends_correct_content__without_streamsProperties() {

    # note that we are expecting '\r', '\n' to be replaced by ' '
    local STATEMENT=$'SELECT a,\r\nb\nFROM c;'
    local STMT_EXPECTED=$'SELECT a,  b FROM c;'

    server_start

    ( ksqldb_query "$STATEMENT" &> /dev/null ) &

    server_stop

    read -r -d '' EXPECTED << EOM
{"ksql": "${STMT_EXPECTED}", "streamsProperties": {}}
EOM

    if ! assert_server_request_content "$EXPECTED"; then return 1; fi

}

function test_ksqldb_query__sends_correct_content__with_streamsProperties() {

    server_start

    ( ksqldb_query "S (P='V');" '{"p": "v"}' &> /dev/null ) &

    server_stop

    read -r -d '' EXPECTED << EOM
{"ksql": "S (P='V');", "streamsProperties": {"p": "v"}}
EOM

    if ! assert_server_request_content "$EXPECTED"; then return 1; fi

}

function test_ksqldb_query__returns_server_response() {

    local EXPECTED="STUFF RETURNED"
    local RESPONSE=`execute_server_call $'HTTP/1.1 200 OK\r\n\r\nSTUFF RETURNED' "ksqldb_query" "S1; S2;"`

    if [ ! "$RESPONSE" == "$EXPECTED" ]; then echo "the content returned must be '$EXPECTED', but was '$RESPONSE'"; return 1; fi

}

function test_ksqldb_query__handles_404() {
    
    execute_server_call $'HTTP/1.1 400 Not Found\r\n\r\nThis is content.' "ksqldb_query" "S" &> /dev/null

    if [ ! $? -eq 1 ]; then echo "404s must be returned with return code 1, but was 0"; return 1; fi

}

#### test_ksqldb_stream_insert

function test_ksqldb_stream_insert__sends_correct_headers() {

    local URL_PATH="/inserts-stream"
    
    server_start

    ( ksqldb_stream_insert "stream" "objects" &> /dev/null ) &

    server_stop

    if ! assert_server_request_content "POST $URL_PATH"; then return 1; fi
    if ! assert_server_request_content "Accept: application/vnd.ksql.v1+json"; then return 1; fi

}

function test_ksqldb_stream_insert__sends_correct_content() {

    local STREAM="stream"
    local EVENTS='{"k1":"v1"}'

    local EXPECTED=$'{"target":"stream"}\n{"k1":"v1"}'

    server_start

    ( ksqldb_stream_insert "$STREAM" "$EVENTS" &> /dev/null ) &

    server_stop

    if ! assert_server_request_content "$EXPECTED"; then return 1; fi

}

function test_ksqldb_stream_insert__returns_server_response() {

    local EXPECTED="STUFF RETURNED"
    local RESPONSE=`execute_server_call $'HTTP/1.1 200 OK\r\n\r\nSTUFF RETURNED' "ksqldb_stream_insert" "stream" "objects"`

    if [ ! "$RESPONSE" == "$EXPECTED" ]; then echo "the content returned must be '$EXPECTED', but was '$RESPONSE'"; return 1; fi

}

function test_ksqldb_stream_insert__handles_404() {
    
    execute_server_call $'HTTP/1.1 400 Not Found\r\n\r\nThis is content.' "ksqldb_stream_insert" "stream" "objects" &> /dev/null

    if [ ! $? -eq 1 ]; then echo "404s must be returned with return code 1, but was 0"; return 1; fi

}


#### UTILITIES ################################################################

####
# Starts a mock server listening on 127.0.0.1:1234 which answers with the 
# string in $1 to the first request. Once started, the function named in $2
# will be executed with the given parameters. This function will return the
# return code of the named function. 
# The stdout of the named function is left untouched and can be fetched from
# stdout.
#
# parameters:
# $1    - server response
# $2    - function to call
# $3..n - string of function parameters separated by space
# $KSQLDB_URL - the server base url
function execute_server_call() {
    
    local RESPONSE=$1; shift
    local FUNCTION=$1; shift
    
    local OUTPUT=/tmp/$$
    trap "rm -f $OUTPUT" EXIT

    server_start
    
    ( $FUNCTION $@; echo -n $? > $OUTPUT ) & 
    
    server_respond "$RESPONSE"
    server_stop

    local RETVAL=
    (( RETVAL = `cat $OUTPUT` ))
    rm -f $OUTPUT

    return $RETVAL
}

#### MOCK SERVER ##############################################################

MOCK_SERVER_PORT=1234
MOCK_SERVER_PID=
MOCK_SERVER_REQUEST=/tmp/server.request.$$.txt
MOCK_SERVER_RESPONSE=/tmp/server.response.$$.txt

####
# starts a nc based server
#
function server_start() {
    # clean up older requests
    rm -f $MOCK_SERVER_REQUEST $MOCK_SERVER_RESPONSE

    touch $MOCK_SERVER_REQUEST $MOCK_SERVER_RESPONSE
    trap "rm -f $MOCK_SERVER_REQUEST $MOCK_SERVER_RESPONSE" EXIT

    tail -f $MOCK_SERVER_RESPONSE | nc -l $MOCK_SERVER_PORT > $MOCK_SERVER_REQUEST &
    MOCK_SERVER_PID=$! 

    sleep 1
}

####
# sends a response line
#
# parameters:
# $1 - the response line
function server_respond() {
    sleep 1

    echo "$1" > $MOCK_SERVER_RESPONSE
}

####
# stops the server and closes the connection
#
function server_stop() {
    sleep 1

    kill -s TERM $MOCK_SERVER_PID
    wait &> /dev/null
}

####
# Asserts that the current server has a request line as given.
#
# example:
# 
#   server_start
#
#   ( function_with_server_call ) &
#
#   server_stop
#   
#   if ! assert_server_request_content "GET /path HTTP/1.1"; then return 1; fi
#   if ! assert_server_request_content "Accept: */*"; then return 1; fi
#   
#
# parameters
# $1 - expected request header (line)
function assert_server_request_content() {
    if ! grep -q "$1" $MOCK_SERVER_REQUEST; then
        echo "server request expected to include '$1', but was"
        cat -v $MOCK_SERVER_REQUEST
        return 1
    fi

    return 0
}

#### TEST WRAPPER #############################################################

####
# Wrapper for test functions to log result.
#
# paramters:
# $1 - the function name
function test_function() {
    local OUTPUT=/tmp/test_function.$1.$$
    trap "rm -f $OUTPUT" EXIT

    $1 > $OUTPUT
    if [ ! $? -eq 0 ]; then
        local MSG=`cat $OUTPUT`
        echo "FAILED: $1 - $MSG"
        return 1
    fi

    echo "PASSED: $1"
    return 0
}


#### SCRIPT ###################################################################

# single test
if [ ! -z "$1" ]; then
    if ! test_function "$1"; then 
        exit 1
    fi
    exit 0
fi

# all tests
(( RETVAL = 0 ))

for TEST in \
    test_ksqldb_info__sends_correct_headers \
    test_ksqldb_healthcheck__sends_correct_headers \
    test_ksqldb_isAvailable__server_not_started \
    test_ksqldb_isAvailable__server_started \
    test_ksqldb_post__sends_correct_headers \
    test_ksqldb_post__sends_correct_content \
    test_ksqldb_post__handles_404 \
    test_ksqldb_execute__sends_correct_headers \
    test_ksqldb_execute__sends_correct_content__without_streamsProperties \
    test_ksqldb_execute__sends_correct_content__with_streamsProperties_without_commandSequence \
    test_ksqldb_execute__sends_correct_content__with_commandSequence \
    test_ksqldb_execute__returns_server_response \
    test_ksqldb_execute__handles_404 \
    test_ksqldb_query__sends_correct_headers \
    test_ksqldb_query__sends_correct_content__without_streamsProperties \
    test_ksqldb_query__sends_correct_content__with_streamsProperties \
    test_ksqldb_query__returns_server_response \
    test_ksqldb_query__handles_404 \
    test_ksqldb_stream_insert__sends_correct_headers \
    test_ksqldb_stream_insert__sends_correct_content \
    test_ksqldb_stream_insert__returns_server_response \
    test_ksqldb_stream_insert__handles_404
do
    if ! test_function "$TEST"; then 
        (( RETVAL += 1 ))
    fi
done

if [ $RETVAL -eq 0 ]; then
    echo "All Tests passed."
    exit 0
else
    echo "$RETVAL Tests FAILED."
    exit 1
fi
