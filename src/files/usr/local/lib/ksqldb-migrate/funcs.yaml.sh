####
# Verifies whether a file has a correct YAML structure
#
# parameters:
# $1 - the file to verify
function yaml_verify(){
    yq v $1

    return $?
}

####
# Reads from a yaml file and returns that info on stdout.
#
# parameters:
# $1 - the file to read from
# $2 - the expression to return data for
# $3 - optional default value
function yaml_read(){
    local DEFAULT_VALUE=
    if [ ! -z "$3" ]; then
        DEFAULT_VALUE="--defaultValue $3"
    fi

    yq r $1 $DEFAULT_VALUE $2

    return $?
}

####
# Checks whether a yaml file has a key present
# 
# parameters:
# $1 - the file to verify
# $2 - the expression to return data for
function yaml_isKey() {
    if [ "$(yaml_read "$1" "$2" "_notset_")" == "_notset_" ]; then
        return 1
    fi

    return 0
} 