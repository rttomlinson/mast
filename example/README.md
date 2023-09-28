SERVICE_SPEC_JSON=$(jq -Rsa . example/service_spec.json)
curl -XPOST "http://localhost:8888/2015-03-31/functions/function/invocations" -d "{\"environment\": \"prestaging\", \"step_name\": \"validate_service_spec\", \"service_spec_json\": $SERVICE_SPEC_JSON}"
