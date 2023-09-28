set -e -o pipefail

export OUTPUT_FILE=$(mktemp)
trap "rm -f $OUTPUT_FILE" 0

input_service_spec_json=$(cat <<'__END_SERVICE_SPEC__'
${service_spec}
__END_SERVICE_SPEC__
)

docker_run mast validate_service_spec \
    --environment '${environment}' \
    --service-spec-json "$input_service_spec_json" \
    --output-file "$OUTPUT_FILE"

export service_spec_json=$(cat "$OUTPUT_FILE")


# Variables
# environment:${workflow.variables.environment}, service_spec:${context.meta.service_spec}
