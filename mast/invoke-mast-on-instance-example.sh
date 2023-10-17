set -e -o pipefail

export OUTPUT_FILE=$(mktemp)
trap "rm -f $OUTPUT_FILE" 0

input_cloud_spec_json=$(cat <<'__END_CLOUD_SPEC__'
${cloud_spec}
__END_CLOUD_SPEC__
)

docker_run mast validate_cloud_spec \
    --environment '${environment}' \
    --cloud-spec-json "$input_cloud_spec_json" \
    --output-file "$OUTPUT_FILE"

export cloud_spec_json=$(cat "$OUTPUT_FILE")


# Variables
# environment:${workflow.variables.environment}, cloud_spec:${context.meta.cloud_spec}
