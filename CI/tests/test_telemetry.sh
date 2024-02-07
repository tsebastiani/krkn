set -xeEo pipefail

source CI/tests/common.sh

trap error ERR
trap finish EXIT


function functional_test_telemetry {
  export RUN_TAG="funtest-telemetry-`date +%s`-"
  #yq -i '.input_list[0].node_selector={"kubernetes.io/hostname":"kind-worker2"}' scenarios/arcaflow/cpu-hog/input.yaml
  yq -i '.telemetry.enabled=True' CI/config/common_test_config.yaml
  yq -i '.telemetry.full_prometheus_backup=True' CI/config/common_test_config.yaml
  yq -i '.telemetry.run_tag=env(RUN_TAG)' CI/config/common_test_config.yaml
  export scenario_type="arcaflow_scenarios"
  export scenario_file="scenarios/arcaflow/cpu-hog/input.yaml"
  export post_config=""
  envsubst < CI/config/common_test_config.yaml > CI/config/telemetry.yaml
  python3 -m coverage run -a run_kraken.py -c CI/config/telemetry.yaml
  echo "Arcaflow CPU Hog: Success"
}

functional_test_telemetry