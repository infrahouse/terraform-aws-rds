import json
import os
import re
import stat
import shutil
import time
from os import path as osp
from textwrap import dedent
from typing import Dict, List, Optional, Set

import boto3
import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import LOG, TERRAFORM_ROOT_DIR

# Expected per-engine properties. Each engine has its own Terraform root (and state)
# so that --keep-after keeps both deployments instead of one replacing the other.
ENGINES = {
    "mysql": {
        "root_dir": "rds",
        "service_name": "test-rds",
        "version_prefix": "8.4.",
        "family": "mysql8.4",
        "port": 3306,
        "logs_exports": ["error", "slowquery"],
        "connections_widget": "MySQL Connections",
        "foreign_marker": "PostgreSQL",
    },
    "postgres": {
        "root_dir": "rds_postgres",
        "service_name": "test-rds-pg",
        "version_prefix": "18.",
        "family": "postgres18",
        "port": 5432,
        "logs_exports": ["postgresql", "upgrade"],
        "connections_widget": "PostgreSQL Connections",
        "foreign_marker": "MySQL",
    },
}
ALARM_COUNT = 7
LOG_GROUP_TIMEOUT = 600


def _remove_readonly(func, path, _exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def _wait_for_log_group(
    logs_client, log_group_name: str, timeout: int = LOG_GROUP_TIMEOUT
) -> None:
    """
    Wait until RDS creates the CloudWatch log group for an exported log.

    :param logs_client: boto3 CloudWatch Logs client
    :param log_group_name: Full log group name, e.g. /aws/rds/instance/<id>/postgresql
    :param timeout: Seconds to wait before failing
    :raise AssertionError: If the log group doesn't appear within the timeout
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        groups = logs_client.describe_log_groups(logGroupNamePrefix=log_group_name)[
            "logGroups"
        ]
        if any(g["logGroupName"] == log_group_name for g in groups):
            return
        LOG.info("Waiting for log group %s", log_group_name)
        time.sleep(30)
    raise AssertionError(
        f"Log group {log_group_name} did not appear within {timeout} seconds"
    )


def _db_parameters(rds_client, parameter_group_name: str) -> Dict[str, Dict]:
    """
    Return all parameters of a DB parameter group, keyed by name.

    :param rds_client: boto3 RDS client
    :param parameter_group_name: DB parameter group name
    :return: Mapping of parameter name to its description from DescribeDBParameters
    """
    params = {}
    paginator = rds_client.get_paginator("describe_db_parameters")
    for page in paginator.paginate(DBParameterGroupName=parameter_group_name):
        for param in page["Parameters"]:
            params[param["ParameterName"]] = param
    return params


def _widget_titles(dashboard_body: str) -> List[str]:
    """
    Extract widget titles from a CloudWatch dashboard body.

    :param dashboard_body: Dashboard body JSON as returned by GetDashboard
    :return: List of widget titles
    """
    return [w["properties"]["title"] for w in json.loads(dashboard_body)["widgets"]]


def _dashboard_pi_counters(dashboard_body: str) -> Set[str]:
    """
    Extract Performance Insights counter names used in DB_PERF_INSIGHTS() expressions.

    :param dashboard_body: Dashboard body JSON as returned by GetDashboard
    :return: Counter names, e.g. {"db.User.numbackends", ...}
    """
    return set(
        re.findall(
            r"DB_PERF_INSIGHTS\('RDS', '[^']+', '([^']+)\.avg'\)", dashboard_body
        )
    )


def _available_pi_counters(pi_client, resource_id: str) -> Set[str]:
    """
    Return the database counter metrics Performance Insights offers for an instance.

    :param pi_client: boto3 Performance Insights client
    :param resource_id: DbiResourceId of the RDS instance
    :return: Counter names, e.g. {"db.User.numbackends", ...}
    """
    counters = set()
    kwargs = {"ServiceType": "RDS", "Identifier": resource_id, "MetricTypes": ["db"]}
    while True:
        response = pi_client.list_available_resource_metrics(**kwargs)
        counters.update(m["Metric"] for m in response["Metrics"])
        if not response.get("NextToken"):
            return counters
        kwargs["NextToken"] = response["NextToken"]


@pytest.mark.parametrize("engine", list(ENGINES))
@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_rds(
    service_network,
    keep_after: bool,
    test_role_arn: Optional[str],
    aws_region: str,
    aws_provider_version: str,
    engine: str,
    boto3_session: boto3.Session,
) -> None:
    expected = ENGINES[engine]
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, expected["root_dir"])

    terraform_dir = osp.join(terraform_module_dir, ".terraform")
    if osp.isdir(terraform_dir):
        shutil.rmtree(
            terraform_dir,
            onerror=lambda func, path, _: _remove_readonly(func, path, None),
        )
    lock_file = osp.join(terraform_module_dir, ".terraform.lock.hcl")
    if osp.isfile(lock_file):
        os.remove(lock_file)

    with open(osp.join(terraform_module_dir, "terraform.tf"), "w") as fp:
        fp.write(dedent(f"""
                terraform {{
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                    random = {{
                      source  = "hashicorp/random"
                      version = "~> 3.0"
                    }}
                  }}
                }}
                """))

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(dedent(f"""
                region     = "{aws_region}"
                subnet_ids = {json.dumps(service_network["subnet_private_ids"]["value"])}
                """))
        if test_role_arn:
            fp.write(dedent(f"""
                    role_arn = "{test_role_arn}"
                    """))

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info("Terraform outputs: %s", json.dumps(tf_output, indent=4))

        assert "db_instance_id" in tf_output
        assert "db_instance_endpoint" in tf_output
        assert "master_secret_arn" in tf_output
        assert "security_group_id" in tf_output
        assert "dashboard_name" in tf_output

        assert tf_output["db_instance_id"]["value"] is not None
        assert tf_output["master_secret_arn"]["value"] is not None
        assert tf_output["security_group_id"]["value"].startswith("sg-")

        db_instance_id = tf_output["db_instance_id"]["value"]
        rds_client = boto3_session.client("rds", region_name=aws_region)
        cloudwatch_client = boto3_session.client("cloudwatch", region_name=aws_region)
        logs_client = boto3_session.client("logs", region_name=aws_region)

        # Engine, version, port
        instance = rds_client.describe_db_instances(
            DBInstanceIdentifier=db_instance_id
        )["DBInstances"][0]
        assert instance["Engine"] == engine
        assert instance["EngineVersion"].startswith(
            expected["version_prefix"]
        ), instance["EngineVersion"]
        assert instance["Endpoint"]["Port"] == expected["port"]
        assert tf_output["db_instance_port"]["value"] == expected["port"]

        # Parameter group family
        parameter_group_name = tf_output["parameter_group_name"]["value"]
        parameter_group = rds_client.describe_db_parameter_groups(
            DBParameterGroupName=parameter_group_name
        )["DBParameterGroups"][0]
        assert parameter_group["DBParameterGroupFamily"] == expected["family"]

        if engine == "postgres":
            params = _db_parameters(rds_client, parameter_group_name)
            # Set by the module from long_query_time = 1 (seconds)
            assert params["log_min_duration_statement"]["ParameterValue"] == "1000"
            assert params["log_min_duration_statement"]["Source"] == "user"
            # Not set by the module because they are RDS defaults for postgres18
            assert params["rds.force_ssl"]["ParameterValue"] == "1"
            assert (
                "pg_stat_statements"
                in params["shared_preload_libraries"]["ParameterValue"]
            )

        # Logs are exported to CloudWatch
        assert sorted(instance["EnabledCloudwatchLogsExports"]) == sorted(
            expected["logs_exports"]
        )
        _wait_for_log_group(
            logs_client,
            f"/aws/rds/instance/{db_instance_id}/{expected['logs_exports'][0]}",
        )

        # Alarms
        alarms = cloudwatch_client.describe_alarms(
            AlarmNamePrefix=f"{expected['service_name']}-development-"
        )["MetricAlarms"]
        assert len(alarms) == ALARM_COUNT, [a["AlarmName"] for a in alarms]

        # Dashboard has only this engine's widgets
        dashboard = cloudwatch_client.get_dashboard(
            DashboardName=tf_output["dashboard_name"]["value"]
        )
        titles = _widget_titles(dashboard["DashboardBody"])
        assert expected["connections_widget"] in titles
        assert not [t for t in titles if expected["foreign_marker"] in t], titles

        # Every Performance Insights counter on the dashboard exists for this engine and version
        pi_client = boto3_session.client("pi", region_name=aws_region)
        used_counters = _dashboard_pi_counters(dashboard["DashboardBody"])
        assert used_counters
        missing = used_counters - _available_pi_counters(
            pi_client, instance["DbiResourceId"]
        )
        assert not missing, sorted(missing)
