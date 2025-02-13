#!/usr/bin/env bash

set -o errexit
set -o nounset

JSON_FILE="${1}"

jq -r 'keys[]' "${JSON_FILE}" | 
    while read -r species; do
         export PARENT_SCRIPT_PATH=$(dirname "$(realpath "$0")")
        ../run_star_index.sh "${species}" ./genomeFileUrls.json "./indexed_genome"
    done
