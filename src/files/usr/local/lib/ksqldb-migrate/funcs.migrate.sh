MIGRATION_STREAM="MIGRATION_STREAM"
MIGRATION_TABLE="MIGRATION_TABLE"
MIGRATION_SETUP_STATEMENT=
    read -r -d '' MIGRATION_SETUP_STATEMENT << EOM
CREATE STREAM ${MIGRATION_STREAM} (
    migration_id VARCHAR KEY,
    schema VARCHAR,
    name VARCHAR,
    hash VARCHAR
) WITH (
    KAFKA_TOPIC = '${MIGRATION_STREAM}',
    PARTITIONS = 1,
    VALUE_FORMAT = 'JSON'
);

CREATE TABLE ${MIGRATION_TABLE}
WITH (
    KAFKA_TOPIC = '${MIGRATION_TABLE}',
    PARTITIONS = 1,
    REPLICAS = 3,
    VALUE_FORMAT = 'JSON',
    TIMESTAMP='rollout_timestamp',
    TIMESTAMP_FORMAT='yyyy-MM-dd HH:mm:ss,SSSX'
) AS SELECT
    migration_id,
    LATEST_BY_OFFSET(schema) as schema,
    LATEST_BY_OFFSET(name) as name,
    LATEST_BY_OFFSET(hash) as hash,
    TIMESTAMPTOSTRING(LATEST_BY_OFFSET(ROWTIME), 'yyyy-MM-dd HH:mm:ss,SSSX', 'UTC') as rollout_timestamp
FROM ${MIGRATION_STREAM}
GROUP BY migration_id
EMIT CHANGES;
EOM

####
# Iterates alphabetically over all ksql YAML files, checks whether the
# migration needs to be applied, conditionally applies it, and registers the
# migration.
#
# parameters:
# $1 - the folder containing ksql YAML files
function migrate_apply_ksql_yaml_folder() {

    migrate_iterate_and_execute "$1" "FORWARD" "migrate_apply_ksql_yaml_file"
    return $RETVAL;
}

####
# Checks whether the migration needs to be applied, whether it was changed,
# conditionally applies it, and registers it.
#
# parameters:
# $1 - the migration file
function migrate_apply_ksql_yaml_file() {

    local FILE=$1

    # build migration id
    local ABSOLUTE_FILEPATH=$( readlink -f "$FILE" )
    local MIGRATION_ID=$( migrate_get_migration_id "${ABSOLUTE_FILEPATH}" )

    # calculate hash
    local FILE_HASH=$( migrate_calculate_file_hash "$FILE" )

    # load migration status
    local KSQLDB_HASH=
    KSQLDB_HASH=$( migrate_read_hash "$MIGRATION_ID" )

    if [ ! $? -eq 0 ]; then
        # potentially just rolled for the very first time so that we just created the migration table
        # in that case chances are that the table wasn't yet fully propagated througout the cluster
        >&2 echo "Failed to read hash from ksqlDB. Please try again, most probably an intermediate error. Aborting"
        return 1
    fi
    
    # conditionally verify hash
    # NOTE: see migrate_rollback_ksql_yaml_file for the explanation of "ROLLBACK"
    if [ ! -z "$KSQLDB_HASH" -a "$KSQLDB_HASH" != "ROLLBACK" ]; then
        # migration was already applied, check hash equality
        if [ ! "${FILE_HASH}" == "${KSQLDB_HASH}" ]; then
            >&2 echo "Hash mismatch for file '$1': file hash '${FILE_HASH}' vs. ksqldb hash '${KSQLDB_HASH}'. Was the file changed lately? Aborting."
            return 1
        fi

        >&2 echo "$FILE has been already applied before."

        # migration is fine.
        return 0
    fi

    # conditionally apply and register
    local MIGRATION_STATEMENT=$( yaml_read "$FILE" "ksql" )
    local MIGRATION_STREAMS_PROPS=$( yq r "$FILE" "streamsProperties" -j )
    
    if ! ksqldb_execute "${MIGRATION_STATEMENT}" "${MIGRATION_STREAMS_PROPS}"; then
        >&2 echo "Failed to apply '$FILE'. Aborting."
        return 1
    fi

    local MIGRATION_SCHEMA=$( migrate_get_schema "$FILE" )
    local MIGRATION_NAME=$( migrate_get_name "$FILE" )

    if ! migration_insert_migration_record "${MIGRATION_ID}" "${MIGRATION_SCHEMA}" "${MIGRATION_NAME}" "${FILE_HASH}"; then
        return 1;
    fi

    >&2 echo "$FILE was successfully applied."
}

####
# Reverse iterates alphabetically over all ksql YAML files, checks whether the
# migration needs to be rolled back, conditionally rolls it back, and deregisters the
# migration.
#
# parameters:
# $1 - the folder containing ksql YAML files
# $2 - the number of migrations to roll back
function migrate_rollback_ksql_yaml_folder() {

    migrate_iterate_and_execute "$1" "BACKWARD" "migrate_rollback_ksql_yaml_file" "$2"
    return $RETVAL;
}

####
# Checks whether the migration needs to be rolled back, whether it was changed,
# conditionally rolls it back it, and deregisters it.
#
# parameters:
# $1 - the migration file
function migrate_rollback_ksql_yaml_file() {

    local FILE=$1

    # build migration id
    local ABSOLUTE_FILEPATH=$( readlink -f "$FILE" )
    local MIGRATION_ID=$( migrate_get_migration_id "${ABSOLUTE_FILEPATH}" )

    # calculate hash
    local FILE_HASH=$( migrate_calculate_file_hash "$FILE" )

    # load migration status
    local KSQLDB_HASH=$( migrate_read_hash "$MIGRATION_ID" )
    
    # check if it was applied
    if [ -z "${KSQLDB_HASH}" -o "${KSQLDB_HASH}" == "ROLLBACK" ]; then
        # migration was not applied, nothing to do
        return -1
    fi 

    # migration was applied, check hash equality
    if [ ! "${FILE_HASH}" == "${KSQLDB_HASH}" ]; then
        >&2 echo "Hash mismatch for file '$1': file hash '${FILE_HASH}' vs. ksqldb hash '${KSQLDB_HASH}'. Was the file changed lately? Aborting."
        return 1
    fi

    # conditionally apply rollback
    local MIGRATION_STATEMENT=$( yq r "$FILE" "rollback.ksql" )
    local MIGRATION_STREAMS_PROPS=$( yq r "$FILE" "rollback.streamsProperties" -j )
    
    if [ ! -z "$ANSWER" -a ! "$ANSWER" = "y" -a ! "$ANSWER" = "Y" ]; then
        >&2 echo "Stopped rollback."
        exit 0
    fi

    if ! ksqldb_execute "${MIGRATION_STATEMENT}" "${MIGRATION_STREAMS_PROPS}"  > /dev/null ; then
        >&2 echo "Failed to apply '$FILE'. Aborting."
        return 1
    fi

    # deregister migration
    # PROBLEM: there seems to be no proper way sending tombstones through an
    # aggregation towards a materialized table (our MIGRATION_TABLE), i.e. we
    # aren't able to delete the row. 
    # SOLUTION: we set the hash to "ROLLBACK" and check for that value at 
    # migrate_apply_ksql_yaml_file

    local MIGRATION_SCHEMA=$( migrate_get_schema "$FILE" )
    local MIGRATION_NAME=$( migrate_get_name "$FILE" )

    if ! migration_insert_migration_record "${MIGRATION_ID}" "${MIGRATION_SCHEMA}" "${MIGRATION_NAME}" "ROLLBACK"  > /dev/null ; then
        return 1;
    fi

    >&2 echo "$FILE was successfully rolled back."
    return 0
}

####
# Inserts an migration record
#
# parameters:
# $1 - migration_id
# $2 - schema
# $3 - name
# $4 - hash
function migration_insert_migration_record(){
    local MIGRATION_ID="$1"
    local MIGRATION_SCHEMA="$2"
    local MIGRATION_NAME="$3"
    local MIGRATION_HASH="$4"

    local MIGRATION_STREAM_EVENT=
    read -r -d '' MIGRATION_STREAM_EVENT << EOM
{
    "migration_id": "${MIGRATION_ID}",
    "schema": "${MIGRATION_SCHEMA}",
    "name": "${MIGRATION_NAME}",
    "hash": "${MIGRATION_HASH}"
}
EOM
    MIGRATION_STREAM_EVENT=$( echo "${MIGRATION_STREAM_EVENT}" | perl -pe "s/[\n\r]//g" )

    local MIGRATION_STREAM_INSERT_STATEMENT=
    read -r -d '' MIGRATION_STREAM_INSERT_STATEMENT << EOM
INSERT INTO ${MIGRATION_STREAM} ( migration_id, schema, name, hash )
VALUES ( '${MIGRATION_ID}', '${MIGRATION_SCHEMA}', '${MIGRATION_NAME}', '${MIGRATION_HASH}' );
EOM

    # TODO: doesn't exists yet
    if ! ksqldb_stream_insert "${MIGRATION_STREAM}" "${MIGRATION_STREAM_EVENT}" > /dev/null ; then
        >&2 echo "UUUH-OHHH, couldn't create an migration history entry for the successful migration from '$FILE'."
        >&2 echo -e "Would be great if you could manually execute:\n${MIGRATION_STREAM_INSERT_STATEMENT}\n"
        return 1
    fi

}

####
# Reads the hash for the given migration id from ksqlDB migration table.
#
# parameters:
# $1 - migration id
#
# returns:
# stdout - the stored hash or "" if the migration id could not be found
function migrate_read_hash() {

    local MIGRATION_ID="$1"
    local QUERY=

    read -r -d '' QUERY << EOM
SELECT
    hash
FROM ${MIGRATION_TABLE}
WHERE 
    migration_id = '${MIGRATION_ID}';
EOM

    local KSQLDB_RESPONSE=
    KSQLDB_RESPONSE=$( ksqldb_query "$QUERY" )

    if [ ! $? -eq 0 ]; then
        return 1
    fi

    echo "${KSQLDB_RESPONSE}" | yq r - '**.row.columns.*' 
}

####
# Calculates the hash of the given ksql YAML file.
# The hash is a sha256 hash out of the ksql value and each of the parameter keys
# and values.
#
# parameters:
# $1 - the ksql YAML file
function migrate_calculate_file_hash() {
    # - calculate the hash of the concatenated
    #     - ksql parameter value 
    #     - each parameter key + value

    local BASE=$( yaml_read $1 "ksql" )
    BASE=$( echo "$BASE"; yaml_read $1 "streamsProperties" )
    BASE=$( echo "$BASE" | perl -pe "s/[\s]*//g" )
    
    echo "$BASE" | sha256sum
}

####
# Returns the migration id for the given absolute ksql YAML file path.
# The migration id is build from the schema name and the file name:
# migration id = <schema name>/<file name w/o extension>.
#
# The file name provided must be in an absolute form, not containing any
# relative parts. 
#
# see #migrate_get_schema
# see #migrate_get_name
#
# parameters:
# $1 - the absolute filepath 
function migrate_get_migration_id() {
    local SCHEMA=$( migrate_get_schema $1 )
    local NAME=$( migrate_get_name $1 )

    echo "$SCHEMA/$NAME"
}

####
# Returns the schema name of the given absolute ksql YAML file path.
# The schema name is the last path part of the filepath is located. 
#
# parameters:
# $1 - the absolute filepath
function migrate_get_schema() {
    echo $1 | perl -pe 's#^.*?/([^/]+?)/[^/]+$#\1#'
}

####
# Returns the name of the given absolute ksql YAML file path.
# The name is the filename without its extension. 
#
# parameters:
# $1 - the absolute filepath
function migrate_get_name() {
    echo $1 | perl -pe 's#^.*?/([^/]+?)\.[^/.]+$#\1#'
}

####
# Verifies all ksql YAML files
#
# parameters:
# $1 - the folder containing ksql YAML files
function migrate_verify_ksql_yaml_folder() {

    migrate_iterate_and_execute "$1" "FORWARD" "migrate_verify_ksql_yaml_file"
    return $RETVAL;
}

####
# Verifies a single ksql YAML for correctness.
#
# paramters:
# $1 - the file to verify
function migrate_verify_ksql_yaml_file() {
    
    local FILE="$1"

    # check YAML structure
    if ! yaml_verify $FILE; then
        >&2 echo "The file '$FILE' seems not to contain proper YAML. Aborting."
        return 1
    fi
    # check the ksql key exists
    if ! yaml_isKey $FILE "ksql"; then
        >&2 echo  "The file '$FILE' doesn't contain a 'ksql' key. Aborting."
        return 1
    fi
}

####
# Iterates alphabetically over all files found in the given directory and
# executes the given function for each file as argument. 
#
# The function must return 
#   0 - for every successful execution (migration counter will be decreased)
# < 0 - when there was nothing to do (migration counter won't be decreased)
# > 0 - when there was an error (immediate stop)
#
# parameters:
# $1 - the folder containing ksql YAML files
# $2 - direction of iteration "FORWARD|BACKWARD"
# $3 - the function to call, needs to have one required argument (a ksql YAML file) 
# $4 - optional - number of migrations to run: not set means all
function migrate_iterate_and_execute() {

    local KSQL_DIR="$1"
    local REVERSE=
    if [ "$2" == "BACKWARD" ]; then 
        REVERSE="-r"
    fi
    local FUNCTION="$3"
    local MIGRATION_NUM=
    if [ ! -z "$4" ]; then
        (( MIGRATION_NUM = $4 ))
    fi

    local RETVAL=
    (( RETVAL = 0 ))

    while read FILE; do

        # execute function
        $FUNCTION "$FILE"
        local EXEC_CODE=$?
        # every return code
        # - 255 means nothing to do
        # - greater than 0 means error
        # - equals 0 means successful executed

       if [ $EXEC_CODE -gt 0 -a ! $EXEC_CODE -eq 255 ]; then
            (( RETVAL = 1 ))
            break;
        fi

        if [ $EXEC_CODE -eq 0 -a ! -z "$MIGRATION_NUM" ]; then
            if [ $MIGRATION_NUM -eq 1 ]; then
                break
            fi

            (( MIGRATION_NUM -= 1 ))
        fi

    done < <(
        find $KSQL_DIR -maxdepth 1 -type f \
        | sort $REVERSE
    )

    return $RETVAL;
}

####
# Ensures the migration environment setup is correct.
#
# Assumes the ksqlDB server configured is available 
# (see funcs.ksqldb.sh#ksqldb_isAvailable)
#
# parameters:
function migrate_ensure_setup() {
 
    local CONTENT=
    # execute call
    CONTENT=$( ksqldb_execute "LIST TABLES;" )

    if [ ! "$?" == "0" ]; then
        return 1
    fi

    # check if the migration table exists
    if echo "$CONTENT" | grep -q "${MIGRATION_TABLE}"; then
        return 0
    fi

    # table doesn't exists so we need to set it up
    migrate_setup

    return $?
}

####
# Creates the migration table.
#
# parameters:
# $MIGRATION_SETUP_STATEMENT - the statement to create the migration table (see beginning of this file)
function migrate_setup() {

    local KSQLDB_RESPONSE=
    # execute call
    KSQLDB_RESPONSE=$( ksqldb_execute "${MIGRATION_SETUP_STATEMENT}" )

    if [ ! "$?" == "0" ]; then
        return 1
    fi

    local RESULT=$( echo ${KSQLDB_RESPONSE} | jq '. | last' )

    # check whether the execution was successful
    local CMDS=$( echo $RESULT | jq '.commandStatus.status' )
    local CMDM=$( echo $RESULT | jq '.commandStatus.message' )
    if ! echo $CMDS | grep -q "SUCCESS"; then
        >&2 echo "Error while setting up migration environment: $CMDS, $CMDM" 
        return 1
    fi
}