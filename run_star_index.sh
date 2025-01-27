#!/bin/bash

set -o nounset
set -o errexit

# Check for correct number of arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <Species> <Path_to_JSON_file_with_parameters> <Output_folder>"
    exit 1
fi

# Assign arguments to variables
SPECIES="${1}"
PARAMS_JSON_FILE="${2}"
OUTPUT_FOLDER="${3}"

echo "Running ${SPECIES} ${PARAMS_JSON_FILE} ${OUTPUT_FOLDER}"

# Check system compatibility (currently Linux x64 only, but adaptable for future extensions)
_os="$(uname)"
_arch="$(uname -m)"

# Define the Cell Ranger binary command and the base URL for downloads
CELLRANGER_CMD="cellranger"
BASE_URL="https://cdn.platforma.bio/internal/pkgs/cellranger"
VERSION="9.0.0"

# Define a function to download and install Cell Ranger
download_and_install_cellranger() {
    local version="$1"
    local arch="$2"
    echo "Downloading and installing Cell Ranger version ${version} for ${arch}..."
    (
        mkdir -p "cellranger-${version}"
        cd "cellranger-${version}"
        wget -nv -O "cellranger-${version}-${arch}.tar.gz" \
            "${BASE_URL}/${version}/cellranger-${version}-${arch}.tar.gz"
        tar -xzf "cellranger-${version}-${arch}.tar.gz"
    )
    CELLRANGER_CMD="$(realpath "cellranger-${version}/bin/cellranger")"
}

# Check compatibility and download appropriate version based on architecture
case "${_arch}" in
    x86_64)
        if [ "${_os}" != "Linux" ]; then
            echo "This script can only be run on Linux x64 systems."
            exit 1
        fi
        download_and_install_cellranger "${VERSION}" "linux-x64"
        ;;
    aarch64)
        echo "Currently, there is no support for ARM architecture. Please check back later."
        exit 1
        # Uncomment and modify the following line when ARM support is available
        # download_and_install_cellranger "$VERSION" "linux-arm64"
        ;;
    *)
        echo "Unsupported architecture: ${_arch}"
        exit 1
        ;;
esac

# Placeholder for additional Cell Ranger commands
echo "Cell Ranger is set up at ${CELLRANGER_CMD}"
echo "Cell Ranger setup complete."

echo "Running Cell Ranger mkref for ${SPECIES} using parameters from ${PARAMS_JSON_FILE} and outputting to ${OUTPUT_FOLDER}"

# Read all necessary parameters from the JSON file using a single jq call
read -r ASSEMBLY_VERSION GENOME_URL GTF_URL LOCAL_GENOME_FILE LOCAL_GTF_FILE <<<$(jq -r --arg species "$SPECIES" '
  .[$species] | "\(.assembly_version) \(.genome_url) \(.gtf_url) \(.local_genome_file) \(.local_gtf_file)"
' "$PARAMS_JSON_FILE")

# Check if parameters were found and if either URLs or local files are available
if [[ -z "${ASSEMBLY_VERSION}" ]]; then
    echo "Error: Assembly version for species '$SPECIES' not found in $PARAMS_JSON_FILE."
    exit 1
fi

if [[ ("${GENOME_URL}" == "null" || "${GTF_URL}" == "null") && ("${LOCAL_GENOME_FILE}" == "null" || "${LOCAL_GTF_FILE}" == "null") ]]; then
    echo "Error: Neither genome/GTF URLs nor local files are set for species '$SPECIES'."
    exit 1
fi

# Calculate memory and threads
NUM_THREADS=$(nproc)
TOTAL_MEM_GB=$(awk '/MemTotal/ {print int($2 / 1024 / 1024)}' /proc/meminfo)
MEM_TO_USE_GB=$(awk "BEGIN {print int(${TOTAL_MEM_GB} * 0.8)}")

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_FOLDER}"
cd "${OUTPUT_FOLDER}"

# Determine whether to use local files or download from URLs
if [[ "${LOCAL_GENOME_FILE}" != "null" && "${LOCAL_GTF_FILE}" != "null" ]]; then
    echo "Using local files for $SPECIES"
    GENOME_FILENAME="${PARENT_SCRIPT_PATH}/${LOCAL_GENOME_FILE}"
    GTF_FILENAME="${PARENT_SCRIPT_PATH}/${LOCAL_GTF_FILE}"
elif [[ "${GENOME_URL}" != "null" && "${GTF_URL}" != "null" ]]; then
    echo "Downloading and processing files for ${SPECIES}"
    GENOME_FILENAME="genome.fa"
    GTF_FILENAME="${SPECIES}_${ASSEMBLY_VERSION}_annotations.gtf"

    # Download and decompress genome DNA fasta file
    wget -nv -O "${GENOME_FILENAME}.gz" "${GENOME_URL}"
    gunzip --force "${GENOME_FILENAME}.gz"

    # Download and decompress genome annotation GTF file
    wget -nv -O "${GTF_FILENAME}.gz" "${GTF_URL}"
    gunzip --force "${GTF_FILENAME}.gz"
else
    echo "Error: Incomplete file sources (either local or URL) for '$SPECIES'."
    exit 1
fi

echo "Generating reference with Cell Ranger... ${SPECIES}"
"${CELLRANGER_CMD}" mkref --genome="${SPECIES}"_"${ASSEMBLY_VERSION}" --fasta="${GENOME_FILENAME}" --genes="${GTF_FILENAME}" --memgb="${MEM_TO_USE_GB}" --nthreads="${NUM_THREADS}"

echo "Reference generation complete for ${SPECIES}."