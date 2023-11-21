set -xeEo pipefail

source CI/tests/common.sh

trap error ERR
trap finish EXIT


function functional_test_telemetry {
  # runs cpu hog and collect
  telemetry_id="funtest-`date +%s`"
  export scenario_type="arcaflow_scenarios"
  export scenario_file="CI/scenarios/arcaflow/cpu-hog/input.yaml"
  export post_config=""
  envsubst < CI/config/common_test_config.yaml > CI/config/telemetry.yaml
  yq -i '.telemetry.enabled=True' CI/config/arca_cpu_hog.yaml
  yq -i '.telemetry.username="'$telemetry_username'"' CI/config/telemetry.yaml
  yq -i '.telemetry.password="'$telemetry_password'"' CI/config/telemetry.yaml
  yq -i '.telemetry.backup_threads=1' CI/config/telemetry.yaml
  yq -i '.telemetry.run_tag="'$telemetry_id'"' CI/config/telemetry.yaml
  python3 -m coverage run -a run_kraken.py -c CI/config/telemetry.yaml
  test_folder="`aws s3 ls s3://$telemetry_bucket | awk '{ print $2 }' | grep $telemetry_id`"
  [ -z $test_folder ] && echo "[ERROR] telemetry folder not created" && exit 1
  readarray files < <(aws s3 ls s3://$telemetry_bucket/$test_folder | awk '{ print $4 }')
  [[ ${#files[@]} == 0 ]] && echo "[ERROR] no telemetry files uploaded " && exit 1
  echo -e "telemetry files successfully uploaded:\n  ${files[*]}"
  echo "Arcaflow Telemetry: Success"

}

functional_test_telemetry