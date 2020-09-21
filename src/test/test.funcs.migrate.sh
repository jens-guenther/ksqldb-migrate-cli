#
# Tests for lib/ksqldb-migrate/funcs.migrate.sh

#### CONSTANTS ################################################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
KSQLDB_DIR_LIB=$DIR/../files/usr/local/lib/ksqldb-migrate

#### GLOBAL FUNCTIONS #########################################################

. $KSQLDB_DIR_LIB/funcs.migrate.sh
. $KSQLDB_DIR_LIB/funcs.yaml.sh


#### TESTS ####################################################################

#### test_migrate_setup

function test_migrate_setup__when_ksqldb_execute_fails_so_does_this(){

    ksqldb_mock_reset

    MOCK_RETURN_CODE=1

    if migrate_setup; then echo "when ksqldb_execute returns 1 migrate_setup must return 1, but was 0"; return 1; fi

    return 0
}

function test_migrate_setup__when_response_is_success_method_succeeds(){

    ksqldb_mock_reset

    MOCK_RETURN_STDOUT='[{"commandStatus":{"status":"SUCCESS","message":"MESSAGE"}}]'

    local STDOUT=
    STDOUT=$( { migrate_setup; } 2>&1 )
    local RC=$?

    if [ "$RC" == "1" ]; then echo "expected return value 0, but was '$RC'"; return 1; fi
    if [ ! -z "$STDOUT" ]; then echo "expected emtpy stdout/stderr, but was '$STDOUT'"; return 1; fi

    return 0
}

function test_migrate_setup__when_response_is_error_method_fails_with_error_message(){

    ksqldb_mock_reset

    MOCK_RETURN_STDOUT='[{"commandStatus":{"status":"ERROR","message":"ERRORMESSAGE"}}]'

    local STDOUT=
    STDOUT=$( { migrate_setup; } 2>&1 )
    local RC=$?

    if [ ! "$RC" == "1" ]; then echo "expected return value 1, but was '$RC'"; return 1; fi
    if ! echo "$STDOUT" | grep -q "ERRORMESSAGE"; then echo "expected 'ERRORMESSAGE' as part of stderr return, but was '$STDOUT'"; return 1; fi

    return 0
}

#### test_migrate_get_schema

function test_migrate_get_schema__returns_correct_schema() {
    local FILE="/foo/bar/schema/file.yaml"
    local EXPECTED="schema"
    local SCHEMA=$( migrate_get_schema $FILE )

    if [ ! "$SCHEMA" == "$EXPECTED" ]; then echo "schema must be '$EXPECTED', but was '$SCHEMA'"; return 1; fi 

}

#### test_migrate_get_name

function test_migrate_get_name__returns_correct_name() {
    local FILE="/foo/bar/schema/file.written.as.yml"
    local EXPECTED="file.written.as"
    local NAME=$( migrate_get_name $FILE )

    if [ ! "$NAME" == "$EXPECTED" ]; then echo "name must be '$EXPECTED', but was '$NAME'"; return 1; fi 

}

#### test_migrate_get_migration_id

function test_migrate_get_migration_id__returns_correct_migration_id() {

    local FILE="/schema/file.yaml"
    local EXPECTED="schema/file"
    local MIGRATION_ID=$( migrate_get_migration_id $FILE )

    if [ ! "$MIGRATION_ID" == "$EXPECTED" ]; then echo "migration id must be '$EXPECTED', but was '$MIGRATION_ID'"; return 1; fi 
}

#### test_migrate_get_hash

function test_migrate_calculate_file_hash__calculates_the_correct_hash() {   
    local FILE=/tmp/ksql.yml.$$
    trap "rm -f $FILE" EXIT

    cat > $FILE << EOM
ksql:
    CREATE STREAM foo AS
        SELECT * 
        FROM something_else;
streamsProperties:
    a: aVal
    b: bVal
EOM

    local EXPECTED_BASE="CREATESTREAMfooASSELECT*FROMsomething_else;a:aValb:bVal"
    local EXPECTED_HASH=$( echo "${EXPECTED_BASE}" | sha256sum )
    local HASH=$( migrate_calculate_file_hash "$FILE" )

    if [ ! "$EXPECTED_HASH" == "$HASH" ]; then echo "hash was expected as '$EXPECTED_HASH', but was '$HASH'"; return 1; fi

}

#### test_migrate_iterate_and_execute

TEST_MIAE_FOLDER=/tmp/$$

function test_miae_setup_ksql_test_files() {
    mkdir -p "${TEST_MIAE_FOLDER}"
    trap "rm -rf ${TEST_MIAE_FOLDER}" EXIT

    touch "${TEST_MIAE_FOLDER}/0001.ksql"
    touch "${TEST_MIAE_FOLDER}/0002.ksql"
    touch "${TEST_MIAE_FOLDER}/0003.ksql"
}

TEST_MIAE_CALLED_FILES=
TEST_MIAE_IGNORE=

function test_miae_mock_reset() {
    TEST_MIAE_CALLED_FILES=
    TEST_MIAE_IGNORE=
}

function test_miae_mock_set_ignore() {
    (( TEST_MIAE_IGNORE = $1 ))
}

function test_miae_mock_function() {
    if [ -z "${TEST_MIAE_CALLED_FILES}" ]; then
        TEST_MIAE_CALLED_FILES="$1"
    else
        TEST_MIAE_CALLED_FILES="${TEST_MIAE_CALLED_FILES}+$1"
    fi

    if [ ! -z "${TEST_MIAE_IGNORE}" ]; then
        (( TEST_MIAE_IGNORE -= 1 ))
        
        if [ $TEST_MIAE_IGNORE -eq 0 ]; then
            TEST_MIAE_IGNORE=
        fi

        return 255
    fi

    return 0
}

function test_miae_assert_num_files_executed() {
    local LC=$( echo "${TEST_MIAE_CALLED_FILES}" | perl -pe "s/\+/\n/g" | egrep "^.+$" | wc -l )

    if [ ! "$1" == "$LC" ]; then echo "number of files to be executed was expected to be '$1', but was '$LC'"; return 1; fi
}

function test_miae_assert_file_executed() {
    if ! echo "${TEST_MIAE_CALLED_FILES}" | grep -q "$1"; then echo "file '$1' was expected to be executed, but files were '${TEST_MIAE_CALLED_FILES}'"; return 1; fi
}

function test_miae_assert_first_file_executed() {
    if ! echo "${TEST_MIAE_CALLED_FILES}" | egrep -q "^[^+]*$1?(\+|$)"; then echo "file '$1' was expected to be executed first, but files were '${TEST_MIAE_CALLED_FILES}'"; return 1; fi
}

function test_migrate_iterate_and_execute_forward_all() {
    test_miae_setup_ksql_test_files
    test_miae_mock_reset

    migrate_iterate_and_execute "${TEST_MIAE_FOLDER}" "FORWARD" "test_miae_mock_function" > /dev/null

    test_miae_assert_num_files_executed 3
    test_miae_assert_file_executed "0001.ksql"
    test_miae_assert_file_executed "0002.ksql"
    test_miae_assert_file_executed "0003.ksql"
    test_miae_assert_first_file_executed "0001.ksql"

}

function test_migrate_iterate_and_execute_forward_one() {
    test_miae_setup_ksql_test_files
    test_miae_mock_reset

    migrate_iterate_and_execute "${TEST_MIAE_FOLDER}" "FORWARD" "test_miae_mock_function" 1 > /dev/null

    test_miae_assert_num_files_executed 1
    test_miae_assert_file_executed "0001.ksql"
    test_miae_assert_first_file_executed "0001.ksql"

}

function test_migrate_iterate_and_execute_forward_one_with_one_ignore() {
    test_miae_setup_ksql_test_files
    test_miae_mock_reset
    test_miae_mock_set_ignore 1

    migrate_iterate_and_execute "${TEST_MIAE_FOLDER}" "FORWARD" "test_miae_mock_function" 1 > /dev/null

    test_miae_assert_num_files_executed 2
    test_miae_assert_file_executed "0001.ksql"
    test_miae_assert_file_executed "0002.ksql"
    test_miae_assert_first_file_executed "0001.ksql"

}

function test_migrate_iterate_and_execute_backward_all() {
    test_miae_setup_ksql_test_files
    test_miae_mock_reset

    migrate_iterate_and_execute "${TEST_MIAE_FOLDER}" "BACKWARD" "test_miae_mock_function" > /dev/null

    test_miae_assert_num_files_executed 3
    test_miae_assert_file_executed "0001.ksql"
    test_miae_assert_file_executed "0002.ksql"
    test_miae_assert_file_executed "0003.ksql"
    test_miae_assert_first_file_executed "0003.ksql"

}

function test_migrate_iterate_and_execute_backward_one() {
    test_miae_setup_ksql_test_files
    test_miae_mock_reset

    migrate_iterate_and_execute "${TEST_MIAE_FOLDER}" "BACKWARD" "test_miae_mock_function" 1 > /dev/null

    test_miae_assert_num_files_executed 1
    test_miae_assert_file_executed "0003.ksql"
    test_miae_assert_first_file_executed "0003.ksql"

}

function test_migrate_iterate_and_execute_backward_one_with_one_ignore() {
    test_miae_setup_ksql_test_files
    test_miae_mock_reset
    test_miae_mock_set_ignore 1

    migrate_iterate_and_execute "${TEST_MIAE_FOLDER}" "BACKWARD" "test_miae_mock_function" 1 > /dev/null

    test_miae_assert_num_files_executed 2
    test_miae_assert_file_executed "0002.ksql"
    test_miae_assert_file_executed "0003.ksql"
    test_miae_assert_first_file_executed "0003.ksql"

}

#### MOCK FUNCTIONS ###########################################################

#### general mock vars
MOCK_RETURN_STDOUT="NOOP" # when NOOP then nothing will be send to stdout
MOCK_RETURN_STDERR="NOOP" # when NOOP then nothing will be send to stderr
MOCK_RETURN_CODE=0

function ksqldb_mock_reset() {
    MOCK_RETURN_STDOUT="NOOP"
    MOCK_RETURN_STDERR="NOOP"
    MOCK_RETURN_CODE="0"
}

function ksqldb_mock_function() {
    if [ ! "${MOCK_RETURN_STDOUT}" == "NOOP" ]; then
        echo "${MOCK_RETURN_STDOUT}"
    fi
    if [ ! "${MOCK_RETURN_STDERR}" == "NOOP" ]; then
        >&2 echo "${MOCK_RETURN_STDERR}"
    fi

    local RC=
    (( RC = ${MOCK_RETURN_CODE} ))

    return $RC
}

#####
# mock function.
function ksqldb_execute() {
    ksqldb_mock_function

    return $?
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
    test_migrate_setup__when_ksqldb_execute_fails_so_does_this \
    test_migrate_setup__when_response_is_success_method_succeeds \
    test_migrate_setup__when_response_is_error_method_fails_with_error_message \
    test_migrate_get_schema__returns_correct_schema \
    test_migrate_get_name__returns_correct_name \
    test_migrate_get_migration_id__returns_correct_migration_id \
    test_migrate_calculate_file_hash__calculates_the_correct_hash \
    test_migrate_iterate_and_execute_forward_all \
    test_migrate_iterate_and_execute_forward_one \
    test_migrate_iterate_and_execute_forward_one_with_one_ignore \
    test_migrate_iterate_and_execute_backward_all \
    test_migrate_iterate_and_execute_backward_one \
    test_migrate_iterate_and_execute_backward_one_with_one_ignore
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
