#!/bin/bash

set -e

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_DB:-mysecretpassword}"
POSTGRES_DB="${POSTGRES_DB:-$POSTGRES_USER}"

# Execute psql commands on the database container for performance reasons.
PSQL="docker exec -i $(docker-compose ps -q db) gosu ${POSTGRES_USER} psql -d ${POSTGRES_DB}"
# echo "psql command: ${PSQL}"

function usage() {
    echo -n \
         "Usage: $(basename "$0") [-h] [-f]

Populate database.

Options:
    -h  Show this help text
    -f  Force data reload
"
}

function drop() {
    tablename=${1}
    echo "Dropping ${tablename}"
    ${PSQL} -c "DROP TABLE ${tablename};"
}

function load() {
    file=${1}
    echo "Loading ${file}"
    extracted_file=${file/.gz/}
    gunzip "$file" -qkf
    ${PSQL} < "$extracted_file"
    rm "$extracted_file"
}

function table_exists() {
    table=${1}
    ${PSQL} -c "SELECT 1 FROM $table LIMIT 1" &>/dev/null
}

# Source: https://github.com/azavea/raster-foundry/blob/develop/scripts/setup#L17
function check_database() {
    echo "checking for database"
    # Check if database is set up to continue
    max=21 # 1 minute
    counter=1
    sleep 3  # wait briefly becuase it sometimes blinks out for a moment right after start-up
    while true; do
        if [[ ${counter} -gt 1 ]]; then
            echo "Checking if database is up yet (attempt ${counter})..."
        fi
        set +e
        ${PSQL} -c "SELECT 1" &>/dev/null
        status_check=$?
        if [ $status_check == 0 ]; then
            echo "database is up"
            return
        fi
        set -e
        if [[ ${counter} == "${max}" ]]; then
            echo "Could not connect to database after some time"
            exit 1
        fi
        sleep 3
        (( counter++ ))
    done
}

function check_postgis_install() {
    ${PSQL} -c "SELECT PostGIS_full_version();" &>/dev/null
    status_check=$?
    if [ $status_check == 0 ]; then
        echo "PostGIS is enabled"
        return
    fi
    echo "Enabling PostGIS"
    ${PSQL} -c "CREATE EXTENSION postgis;" &>/dev/null
}

while getopts ":hf" opt; do
    case $opt in
        h) usage; exit 0;;
        f) force_reload=true ;;
        \?) usage; exit 1;;
    esac
done
shift $(($OPTIND - 1))


check_database;
check_postgis_install;

tablename="${1:-pa_gardens}"

if table_exists "${tablename}"; then
    if [ "$force_reload" = true ]; then
        drop ${tablename}
        load "data/${tablename}.sql.gz"
    else
        echo "table ${tablename} exists"
    fi
else
    echo "Loading ${tablename}"
    load "data/${tablename}.sql.gz"
fi