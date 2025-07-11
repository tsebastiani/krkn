import logging
import time
from abc import ABC, abstractmethod
from krkn_lib.models.telemetry import ScenarioTelemetry
from krkn_lib.telemetry.ocp import KrknTelemetryOpenshift

from krkn import utils


class AbstractScenarioPlugin(ABC):
    @abstractmethod
    def run(
        self,
        run_uuid: str,
        scenario: str,
        krkn_config: dict[str, any],
        lib_telemetry: KrknTelemetryOpenshift,
        scenario_telemetry: ScenarioTelemetry,
    ) -> int:
        """
        This method serves as the entry point for a ScenarioPlugin. To make the plugin loadable,
        the AbstractScenarioPlugin class must be extended, and this method must be implemented.
        No exception must be propagated outside of this method.

        :param run_uuid: the uuid of the chaos run generated by krkn for every single run
        :param scenario: the config file of the scenario that is currently executed
        :param krkn_config: the full dictionary representation of the `config.yaml`
        :param lib_telemetry: it is a composite object of all the
        krkn-lib objects and methods needed by a krkn plugin to run.
        :param scenario_telemetry: the `ScenarioTelemetry` object of the scenario that is currently executed
        :return: 0 if the scenario suceeded 1 if failed
        """
        pass

    @abstractmethod
    def get_scenario_types(self) -> list[str]:
        """
        Indicates the scenario types specified in the `config.yaml`. For the plugin to be properly
        loaded, recognized and executed, it must be implemented and must return the matching `scenario_type` strings.
        One plugin can be mapped one or many different strings unique across the other plugins otherwise an exception
        will be thrown.


        :return: the corresponding scenario_type as a list of strings
        """
        pass

    def run_scenarios(
        self,
        run_uuid: str,
        scenarios_list: list[str],
        krkn_config: dict[str, any],
        telemetry: KrknTelemetryOpenshift,
    ) -> tuple[list[str], list[ScenarioTelemetry]]:

        scenario_telemetries: list[ScenarioTelemetry] = []
        failed_scenarios = []
        wait_duration = krkn_config["tunings"]["wait_duration"]
        events_backup = krkn_config["telemetry"]["events_backup"]
        for scenario_config in scenarios_list:
            if isinstance(scenario_config, list):
                logging.error(
                    "post scenarios have been deprecated, please "
                    "remove sub-lists from `scenarios` in config.yaml"
                )
                failed_scenarios.append(scenario_config)
                break

            scenario_telemetry = ScenarioTelemetry()
            scenario_telemetry.scenario = scenario_config
            scenario_telemetry.scenario_type = self.get_scenario_types()[0]
            scenario_telemetry.start_timestamp = time.time()
            parsed_scenario_config = telemetry.set_parameters_base64(
                scenario_telemetry, scenario_config
            )

            try:
                logging.info(
                    f"Running {self.__class__.__name__}: {self.get_scenario_types()} -> {scenario_config}"
                )
                return_value = self.run(
                    run_uuid,
                    scenario_config,
                    krkn_config,
                    telemetry,
                    scenario_telemetry,
                )
            except Exception as e:
                logging.error(
                    f"uncaught exception on scenario `run()` method: {e} "
                    f"please report an issue on https://github.com/krkn-chaos/krkn"
                )
                return_value = 1

            scenario_telemetry.exit_status = return_value
            scenario_telemetry.end_timestamp = time.time()
            utils.collect_and_put_ocp_logs(
                telemetry,
                parsed_scenario_config,
                telemetry.get_telemetry_request_id(),
                int(scenario_telemetry.start_timestamp),
                int(scenario_telemetry.end_timestamp),
            )

            if events_backup: 
                utils.populate_cluster_events(
                    krkn_config,
                    parsed_scenario_config,
                    telemetry.get_lib_kubernetes(),
                    int(scenario_telemetry.start_timestamp),
                    int(scenario_telemetry.end_timestamp),
                )

            if scenario_telemetry.exit_status != 0:
                failed_scenarios.append(scenario_config)
            scenario_telemetries.append(scenario_telemetry)
            logging.info(f"wating {wait_duration} before running the next scenario")
            time.sleep(wait_duration)
        return failed_scenarios, scenario_telemetries

    