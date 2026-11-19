import json
import os
import re
import stat
import shutil
import subprocess
import time
from datetime import datetime, timedelta, timezone
from os import path as osp
from textwrap import dedent
from typing import Any, Dict, List, Optional, Set, Tuple

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
        "alarm_count": 7,
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
        # The seven alarms both engines have, and the lock table's
        "alarm_count": 8,
    },
}
LOG_GROUP_TIMEOUT = 600
# The alarm's period is 5 minutes; a period is evaluated a few minutes after it ends
ALARM_STATE_TIMEOUT = 900
ACTION_HISTORY_TIMEOUT = 300

# The module release test_upgrade_from_0_3_0 upgrades from: its topic is under alias/aws/sns
UPGRADE_FROM = "0.3.0"
UPGRADE_ROOT_DIR = "rds_postgres_upgrade"
UPGRADE_SERVICE_NAME = "test-rds-pgup"

LOCK_TABLE_NAMESPACE = "InfraHouse/RDS"
LOCK_TABLE_WIDGET = "PostgreSQL Lock Table Errors (per 5 minutes)"
CONNECTION_ATTEMPTS_WIDGET = "PostgreSQL Connection Attempts (per minute)"
UNIT_HIDDEN_WIDGETS = [
    "Free Storage (GiB)",
    "Free Storage Space (GiB)",
    "Freeable Memory (total: ",
]

# Lines in the shape of the ones LoopProof staging's database logged on 2026-11-18 (IH-169), from RDS's prefix
# %t:%r:%u@%d:[%p]:, with an address from RFC 5737's documentation range and a made-up user, database, process and
# statement. True marks the lines the lock table's filter must count.
LOCK_TABLE_LINES: List[Tuple[str, bool]] = [
    ("ERROR:  out of shared memory", True),
    ('HINT:  You might need to increase "max_locks_per_transaction".', False),
    ("STATEMENT:  SELECT pg_advisory_xact_lock(hashtext($1))", False),
    # A session that can't take a lock while it connects
    ("FATAL:  out of shared memory", True),
    # Shared memory itself exhausted, same SQLSTATE
    ("ERROR:  out of shared memory (1024 bytes requested)", True),
    # Statements that quote the error, as a STATEMENT line and as a slow query
    ("STATEMENT:  SELECT 'ERROR:  out of shared memory'", False),
    ("LOG:  duration: 1500.000 ms  statement: SELECT 'out of shared memory'", False),
    ("ERROR:  out of memory", False),
]


def _remove_readonly(func, path, _exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def _prepare_root(
    terraform_module_dir: str,
    aws_provider_version: str,
    aws_region: str,
    subnet_ids: List[str],
    test_role_arn: Optional[str],
) -> None:
    """
    Reset a test Terraform root and write its provider constraints and variables.

    :param terraform_module_dir: Path to the test Terraform root
    :param aws_provider_version: AWS provider version constraint, e.g. "~> 6.0"
    :param aws_region: AWS region for the provider
    :param subnet_ids: Private subnet IDs for the RDS instance
    :param test_role_arn: IAM role for the provider to assume, if any
    """
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
                subnet_ids = {json.dumps(subnet_ids)}
                """))
        if test_role_arn:
            fp.write(dedent(f"""
                    role_arn = "{test_role_arn}"
                    """))


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
        if _log_group(logs_client, log_group_name) is not None:
            return
        LOG.info("Waiting for log group %s", log_group_name)
        time.sleep(30)
    raise AssertionError(
        f"Log group {log_group_name} did not appear within {timeout} seconds"
    )


def _log_group(logs_client, log_group_name: str) -> Optional[Dict]:
    """
    Describe one CloudWatch log group.

    :param logs_client: boto3 CloudWatch Logs client
    :param log_group_name: Full log group name
    :return: The group's description from DescribeLogGroups, or None if it doesn't exist
    """
    groups = logs_client.describe_log_groups(logGroupNamePrefix=log_group_name)[
        "logGroups"
    ]
    return next((g for g in groups if g["logGroupName"] == log_group_name), None)


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


def _widget(dashboard_body: str, title_prefix: str) -> Dict:
    """
    Find the one widget whose title starts with a prefix.

    :param dashboard_body: Dashboard body JSON as returned by GetDashboard
    :param title_prefix: The title, or its start for titles with a computed end
    :return: The widget
    :raise AssertionError: If not exactly one widget matches
    """
    widgets = [
        w
        for w in json.loads(dashboard_body)["widgets"]
        if w["properties"]["title"].startswith(title_prefix)
    ]
    assert len(widgets) == 1, (title_prefix, _widget_titles(dashboard_body))
    return widgets[0]


def _widget_queries(widget: Dict) -> List[Dict]:
    """
    Turn a metric widget's metrics into GetMetricData queries, as the console does to draw it.

    :param widget: A metric widget from a dashboard body
    :return: MetricDataQueries for GetMetricData
    """
    period = widget["properties"]["period"]
    queries = []
    for row in widget["properties"]["metrics"]:
        options = row[-1] if isinstance(row[-1], dict) else {}
        query = {"Id": options["id"], "ReturnData": options.get("visible", True)}
        if "expression" in options:
            query["Expression"] = options["expression"]
            query["Period"] = period
        else:
            names = [x for x in row if isinstance(x, str)]
            query["MetricStat"] = {
                "Metric": {
                    "Namespace": names[0],
                    "MetricName": names[1],
                    "Dimensions": [
                        {"Name": names[i], "Value": names[i + 1]}
                        for i in range(2, len(names), 2)
                    ],
                },
                "Period": period,
                "Stat": widget["properties"]["stat"],
            }
        queries.append(query)
    return queries


def _assert_widget_data(cloudwatch_client, widget: Dict) -> None:
    """
    Fetch a widget's data the way the console draws it, and check CloudWatch accepts every query.

    :param cloudwatch_client: boto3 CloudWatch client
    :param widget: A metric widget from a dashboard body
    :raise AssertionError: If GetMetricData reports an error for any query
    """
    now = datetime.now(timezone.utc)
    response = cloudwatch_client.get_metric_data(
        MetricDataQueries=_widget_queries(widget),
        StartTime=now - timedelta(hours=1),
        EndTime=now,
    )
    LOG.info(
        "%s: %s",
        widget["properties"]["title"],
        [
            (r["Id"], r["StatusCode"], len(r["Values"]))
            for r in response["MetricDataResults"]
        ],
    )
    assert not response.get("Messages"), response["Messages"]
    for result in response["MetricDataResults"]:
        assert result["StatusCode"] in ("Complete", "PartialData"), result
        assert not result.get("Messages"), result


def _assert_no_overlap(dashboard_body: str) -> None:
    """
    Check that no two dashboard widgets cover the same grid cell.

    :param dashboard_body: Dashboard body JSON as returned by GetDashboard
    :raise AssertionError: If two widgets overlap
    """
    cells = {}
    for w in json.loads(dashboard_body)["widgets"]:
        for x in range(w["x"], w["x"] + w["width"]):
            for y in range(w["y"], w["y"] + w["height"]):
                title = w["properties"]["title"]
                assert (x, y) not in cells, (title, cells[(x, y)])
                cells[(x, y)] = title


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


def _available_pi_counters(pi_client, resource_id: str) -> Dict[str, str]:
    """
    Return the database counter metrics Performance Insights offers for an instance, with their units.

    :param pi_client: boto3 Performance Insights client
    :param resource_id: DbiResourceId of the RDS instance
    :return: Counter names and units, e.g. {"db.User.numbackends": "Connections", ...}
    """
    counters = {}
    kwargs = {"ServiceType": "RDS", "Identifier": resource_id, "MetricTypes": ["db"]}
    while True:
        response = pi_client.list_available_resource_metrics(**kwargs)
        counters.update({m["Metric"]: m.get("Unit") for m in response["Metrics"]})
        if not response.get("NextToken"):
            return counters
        kwargs["NextToken"] = response["NextToken"]


def _check_dashboard(
    cloudwatch_client, dashboard_body: str, engine: str, lock_table_metric: str
) -> None:
    """
    Check the widgets IH-169 added or fixed, and that the layout has no overlaps.

    :param cloudwatch_client: boto3 CloudWatch client
    :param dashboard_body: Dashboard body JSON as returned by GetDashboard
    :param engine: "mysql" or "postgres"
    :param lock_table_metric: The lock table metric's name, in LOCK_TABLE_NAMESPACE
    """
    _assert_no_overlap(dashboard_body)

    # Metric math keeps FreeStorageSpace's and FreeableMemory's unit, Bytes, after they're divided to GiB and MiB
    for title in UNIT_HIDDEN_WIDGETS:
        widget = _widget(dashboard_body, title)
        assert widget["properties"]["yAxis"]["left"]["showUnits"] is False, widget
        _assert_widget_data(cloudwatch_client, widget)

    if engine != "postgres":
        return

    # total_auth_attempts is a running total: the visible line is its rate per minute
    widget = _widget(dashboard_body, CONNECTION_ATTEMPTS_WIDGET)
    metrics = {row[0]["id"]: row[0] for row in widget["properties"]["metrics"]}
    assert metrics["e1"]["expression"] == "RATE(c1) * 60", metrics
    assert metrics["e1"].get("visible", True), metrics
    assert "'db.User.total_auth_attempts.avg'" in metrics["c1"]["expression"], metrics
    assert metrics["c1"]["visible"] is False, metrics
    _assert_widget_data(cloudwatch_client, widget)

    # The lock table's errors per 5 minutes, the alarm's metric
    widget = _widget(dashboard_body, LOCK_TABLE_WIDGET)
    properties = widget["properties"]
    assert properties["period"] == 300 and properties["stat"] == "Sum", properties
    assert [LOCK_TABLE_NAMESPACE, lock_table_metric] == properties["metrics"][1][:2]
    assert properties["metrics"][0][0]["expression"] == "FILL(m1, 0)", properties
    _assert_widget_data(cloudwatch_client, widget)


def _set_alarm_state_and_wait_for_action(
    cloudwatch_client, alarm_name: str, timeout: int = ACTION_HISTORY_TIMEOUT
) -> List[str]:
    """
    Put an alarm in ALARM, which runs its actions, and return what CloudWatch says it did.

    :param cloudwatch_client: boto3 CloudWatch client
    :param alarm_name: The alarm's name
    :param timeout: Seconds to wait for the action's history
    :return: The summaries of the alarm's action history since the state change
    :raise AssertionError: If no action is recorded within the timeout
    """
    started = datetime.now(timezone.utc)
    cloudwatch_client.set_alarm_state(
        AlarmName=alarm_name,
        StateValue="ALARM",
        StateReason="terraform-aws-rds tests: does the alarm's action reach its topic?",
    )
    return _wait_for_action(cloudwatch_client, alarm_name, started, timeout)


def _wait_for_action(
    cloudwatch_client, alarm_name: str, since: datetime, timeout: int
) -> List[str]:
    """
    Wait for an alarm's action history after a moment.

    :param cloudwatch_client: boto3 CloudWatch client
    :param alarm_name: The alarm's name
    :param since: Only history after this moment counts
    :param timeout: Seconds to wait
    :return: The summaries of the action history items
    :raise AssertionError: If no action is recorded within the timeout
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        items = cloudwatch_client.describe_alarm_history(
            AlarmName=alarm_name, HistoryItemType="Action", StartDate=since
        )["AlarmHistoryItems"]
        if items:
            return [i["HistorySummary"] for i in items]
        LOG.info("Waiting for %s's action", alarm_name)
        time.sleep(10)
    raise AssertionError(f"{alarm_name} ran no action within {timeout} seconds")


def _wait_for_alarm_state(
    cloudwatch_client, alarm_name: str, state: str, timeout: int = ALARM_STATE_TIMEOUT
) -> None:
    """
    Wait until an alarm reaches a state.

    :param cloudwatch_client: boto3 CloudWatch client
    :param alarm_name: The alarm's name
    :param state: "OK", "ALARM" or "INSUFFICIENT_DATA"
    :param timeout: Seconds to wait
    :raise AssertionError: If the alarm isn't in the state within the timeout
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        alarm = cloudwatch_client.describe_alarms(AlarmNames=[alarm_name])[
            "MetricAlarms"
        ][0]
        if alarm["StateValue"] == state:
            return
        LOG.info("%s is %s, waiting for %s", alarm_name, alarm["StateValue"], state)
        time.sleep(30)
    raise AssertionError(f"{alarm_name} wasn't {state} within {timeout} seconds")


def _log_line(message: str, when: datetime) -> str:
    """
    Format a PostgreSQL log line as RDS exports it, with placeholder session details.

    :param message: The line after the prefix, e.g. "ERROR:  out of shared memory"
    :param when: The line's time
    :return: The full line
    """
    return f"{when.strftime('%Y-%m-%d %H:%M:%S')} UTC:192.0.2.10(54321):app@appdb:[8124]:{message}"


def _check_lock_table_alarm(
    logs_client,
    cloudwatch_client,
    db_instance_id: str,
    alarm_name: str,
    topic_arn: str,
) -> None:
    """
    Check the lock table's filter and alarm on a PostgreSQL instance, then fire the alarm with a log line.

    :param logs_client: boto3 CloudWatch Logs client
    :param cloudwatch_client: boto3 CloudWatch client
    :param db_instance_id: The RDS instance identifier
    :param alarm_name: The lock table alarm's name
    :param topic_arn: The topic the alarm must notify, the high severity's
    """
    log_group_name = f"/aws/rds/instance/{db_instance_id}/postgresql"

    # One filter on the group RDS made
    filters = logs_client.describe_metric_filters(logGroupName=log_group_name)[
        "metricFilters"
    ]
    assert [f["filterName"] for f in filters] == [alarm_name], filters
    transformation = filters[0]["metricTransformations"][0]
    assert transformation["metricNamespace"] == LOCK_TABLE_NAMESPACE, transformation
    assert transformation["metricValue"] == "1", transformation
    assert "defaultValue" not in transformation, transformation

    # The filter counts the error line once, not the HINT or STATEMENT lines after it, nor anything else
    now = datetime.now(timezone.utc)
    matches = logs_client.test_metric_filter(
        filterPattern=filters[0]["filterPattern"],
        logEventMessages=[_log_line(m, now) for m, _ in LOCK_TABLE_LINES],
    )["matches"]
    assert sorted(m["eventNumber"] for m in matches) == [
        i for i, (_, counted) in enumerate(LOCK_TABLE_LINES, start=1) if counted
    ], matches

    # An alarm on the filter's metric: one error in 5 minutes, through the high severity's topic
    alarm = cloudwatch_client.describe_alarms(AlarmNames=[alarm_name])["MetricAlarms"][
        0
    ]
    LOG.info("Lock table alarm: %s", json.dumps(alarm, default=str, indent=4))
    assert alarm["Namespace"] == LOCK_TABLE_NAMESPACE
    assert alarm["MetricName"] == transformation["metricName"]
    assert alarm["Statistic"] == "Sum"
    assert alarm["Period"] == 300
    assert alarm["EvaluationPeriods"] == 1
    assert alarm["Threshold"] == 1.0
    assert alarm["ComparisonOperator"] == "GreaterThanOrEqualToThreshold"
    assert alarm["TreatMissingData"] == "notBreaching"
    assert alarm["AlarmActions"] == [topic_arn]
    assert alarm["OKActions"] == [topic_arn]
    assert log_group_name in alarm["AlarmDescription"]
    assert "pg_locks" in alarm["AlarmDescription"]

    # Fire it: the error's lines in the group, as PostgreSQL logs them. The test's database is in private subnets the
    # test can't reach, so it can't fill the lock table itself.
    stream = f"terraform-aws-rds-test-{int(time.time())}"
    logs_client.create_log_stream(logGroupName=log_group_name, logStreamName=stream)
    try:
        started = datetime.now(timezone.utc)
        logs_client.put_log_events(
            logGroupName=log_group_name,
            logStreamName=stream,
            logEvents=[
                {
                    "timestamp": int(started.timestamp() * 1000),
                    "message": _log_line(m, started),
                }
                for m, _ in LOCK_TABLE_LINES[:3]
            ],
        )
        _wait_for_alarm_state(cloudwatch_client, alarm_name, "ALARM")
        summaries = _wait_for_action(
            cloudwatch_client, alarm_name, started, ACTION_HISTORY_TIMEOUT
        )
        LOG.info("%s's actions: %s", alarm_name, summaries)
        assert f"Successfully executed action {topic_arn}" in summaries, summaries
    finally:
        logs_client.delete_log_stream(logGroupName=log_group_name, logStreamName=stream)


def _module_key_aliases(kms_client, service_name: str) -> List[str]:
    """
    List the aliases of the keys the module makes for its own topic.

    :param kms_client: boto3 KMS client
    :param service_name: The module's service_name
    :return: Alias names starting with alias/<service_name>-rds-alarms-
    """
    prefix = f"alias/{service_name}-rds-alarms-"
    aliases = []
    for page in kms_client.get_paginator("list_aliases").paginate():
        aliases.extend(
            a["AliasName"] for a in page["Aliases"] if a["AliasName"].startswith(prefix)
        )
    return aliases


def _as_list(value: Any) -> List:
    """
    Return a policy element as a list: IAM writes a single value as a string.

    :param value: A string or a list
    :return: A list
    """
    return value if isinstance(value, list) else [value]


def _check_alarms_key(kms_client, key_arn: str, alarm_arns: Set[str]) -> None:
    """
    Check that the topic's key lets CloudWatch use it for the module's alarms, and only those.

    :param kms_client: boto3 KMS client
    :param key_arn: The topic's KmsMasterKeyId
    :param alarm_arns: The ARNs of the module's alarms
    """
    key = kms_client.describe_key(KeyId=key_arn)["KeyMetadata"]
    assert key["KeyManager"] == "CUSTOMER", key
    assert kms_client.get_key_rotation_status(KeyId=key_arn)["KeyRotationEnabled"]

    policy = json.loads(
        kms_client.get_key_policy(KeyId=key_arn, PolicyName="default")["Policy"]
    )
    LOG.info("The topic's key policy: %s", json.dumps(policy, indent=4))
    statements = [
        s
        for s in policy["Statement"]
        if "cloudwatch.amazonaws.com" in _as_list(s["Principal"].get("Service", []))
    ]
    assert len(statements) == 1, policy
    statement = statements[0]
    assert statement["Effect"] == "Allow"
    assert sorted(_as_list(statement["Action"])) == [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
    ]
    assert set(_as_list(statement["Condition"]["ArnEquals"]["aws:SourceArn"])) == (
        alarm_arns
    )


def _terraform_plan(path: str) -> Tuple[Dict, str]:
    """
    Plan a test root after its module source changed.

    :param path: Path to the test Terraform root
    :return: The plan as JSON, and as text
    """
    for cmd in (
        ["terraform", "init", "-no-color"],
        [
            "terraform",
            "plan",
            "-var-file=terraform.tfvars",
            "-input=false",
            "-no-color",
            "-out=tfplan",
        ],
    ):
        subprocess.run(cmd, cwd=path, check=True)
    as_json = subprocess.run(
        ["terraform", "show", "-json", "tfplan"],
        cwd=path,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    as_text = subprocess.run(
        ["terraform", "show", "-no-color", "tfplan"],
        cwd=path,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(as_json), as_text


def _plan_block(plan_text: str, address: str) -> str:
    """
    Cut one resource's change out of a plan's text.

    :param plan_text: The output of terraform show for a plan
    :param address: A resource address, e.g. module.rds.aws_sns_topic.alarms[0]
    :return: The resource's block, from its "# <address>" line to its closing brace
    """
    match = re.search(
        rf"^\s*# {re.escape(address)} .*?^    }}$", plan_text, re.S | re.M
    )
    return match.group(0) if match else ""


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
    _prepare_root(
        terraform_module_dir,
        aws_provider_version,
        aws_region,
        service_network["subnet_private_ids"]["value"],
        test_role_arn,
    )

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
        kms_client = boto3_session.client("kms", region_name=aws_region)

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

        # Alarms, all on the caller's topic: with notifications, the module makes no topic and no key
        alarm_prefix = f"{expected['service_name']}-development-"
        alarms = cloudwatch_client.describe_alarms(AlarmNamePrefix=alarm_prefix)[
            "MetricAlarms"
        ]
        alarm_names = sorted(a["AlarmName"] for a in alarms)
        assert len(alarms) == expected["alarm_count"], alarm_names
        topic_arn = tf_output["alarm_topic_arn"]["value"]
        for alarm in alarms:
            assert alarm["AlarmActions"] == [topic_arn], alarm["AlarmName"]
        assert not _module_key_aliases(kms_client, expected["service_name"])

        lock_table_alarm = f"{alarm_prefix}out-of-shared-memory"
        if engine == "postgres":
            _check_lock_table_alarm(
                logs_client,
                cloudwatch_client,
                db_instance_id,
                lock_table_alarm,
                topic_arn,
            )
        else:
            assert lock_table_alarm not in alarm_names
            assert not logs_client.describe_metric_filters(
                metricName=lock_table_alarm, metricNamespace=LOCK_TABLE_NAMESPACE
            )["metricFilters"]

        # Dashboard has only this engine's widgets
        dashboard = cloudwatch_client.get_dashboard(
            DashboardName=tf_output["dashboard_name"]["value"]
        )
        titles = _widget_titles(dashboard["DashboardBody"])
        assert expected["connections_widget"] in titles
        assert not [t for t in titles if expected["foreign_marker"] in t], titles
        _check_dashboard(
            cloudwatch_client, dashboard["DashboardBody"], engine, lock_table_alarm
        )

        # Every Performance Insights counter on the dashboard exists for this engine and version
        pi_client = boto3_session.client("pi", region_name=aws_region)
        used_counters = _dashboard_pi_counters(dashboard["DashboardBody"])
        assert used_counters
        available = _available_pi_counters(pi_client, instance["DbiResourceId"])
        missing = used_counters - set(available)
        assert not missing, sorted(missing)
        # A counter whose unit isn't a rate may be a running total, which only climbs: IH-169 checked each by hand
        LOG.info(
            "Dashboard counters and their units: %s",
            json.dumps({c: available[c] for c in sorted(used_counters)}, indent=4),
        )


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_upgrade_from_0_3_0(
    service_network,
    keep_after: bool,
    test_role_arn: Optional[str],
    aws_region: str,
    aws_provider_version: str,
    boto3_session: boto3.Session,
) -> None:
    """
    Upgrade a PostgreSQL instance made with 0.3.0 and alarm_emails only, as aws-service-loopproof calls the module.

    The topic gets its key in place, so its email subscription stays; the lock table's filter goes on the log group
    RDS already made, whose retention stays; and an alarm that couldn't reach the topic before reaches it after.
    """
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, UPGRADE_ROOT_DIR)
    _prepare_root(
        terraform_module_dir,
        aws_provider_version,
        aws_region,
        service_network["subnet_private_ids"]["value"],
        test_role_arn,
    )
    override = osp.join(terraform_module_dir, "module_override.tf")
    with open(override, "w") as fp:
        fp.write(dedent(f"""
                # Written by test_upgrade_from_0_3_0: the release it upgrades from
                module "rds" {{
                  source  = "registry.infrahouse.com/infrahouse/rds/aws"
                  version = "{UPGRADE_FROM}"
                }}
                """))

    cloudwatch_client = boto3_session.client("cloudwatch", region_name=aws_region)
    logs_client = boto3_session.client("logs", region_name=aws_region)
    sns_client = boto3_session.client("sns", region_name=aws_region)
    kms_client = boto3_session.client("kms", region_name=aws_region)
    alarm_prefix = f"{UPGRADE_SERVICE_NAME}-development-"

    try:
        with terraform_apply(
            terraform_module_dir,
            destroy_after=not keep_after,
            json_output=True,
        ) as before:
            db_instance_id = before["db_instance_id"]["value"]
            cpu_alarm = cloudwatch_client.describe_alarms(
                AlarmNames=[f"{alarm_prefix}cpu-utilization"]
            )["MetricAlarms"][0]
            topic_arn = cpu_alarm["AlarmActions"][0]
            assert (
                sns_client.get_topic_attributes(TopicArn=topic_arn)["Attributes"][
                    "KmsMasterKeyId"
                ]
                == "alias/aws/sns"
            )
            subscriptions = sns_client.list_subscriptions_by_topic(TopicArn=topic_arn)[
                "Subscriptions"
            ]
            log_group_name = f"/aws/rds/instance/{db_instance_id}/postgresql"
            _wait_for_log_group(logs_client, log_group_name)
            retention = _log_group(logs_client, log_group_name).get("retentionInDays")

            # Logged, not asserted: what CloudWatch does with alias/aws/sns is AWS's, not the module's
            LOG.info(
                "%s %s's actions under alias/aws/sns: %s",
                UPGRADE_FROM,
                cpu_alarm["AlarmName"],
                _set_alarm_state_and_wait_for_action(
                    cloudwatch_client, cpu_alarm["AlarmName"]
                ),
            )

            # This branch's module, planned over the release's state
            os.remove(override)
            plan, plan_text = _terraform_plan(terraform_module_dir)
            actions = {
                rc["address"]: rc["change"]["actions"]
                for rc in plan["resource_changes"]
            }
            LOG.info("Planned actions: %s", json.dumps(actions, indent=4))
            topic = "module.rds.aws_sns_topic.alarms[0]"
            LOG.info("The topic's change:\n%s", _plan_block(plan_text, topic))
            assert actions[topic] == ["update"]
            assert actions["module.rds.aws_sns_topic_subscription.email[0]"] == [
                "no-op"
            ]
            assert actions["module.rds.aws_db_instance.this"] == ["no-op"]
            assert actions["module.rds.aws_kms_key.alarms[0]"] == ["create"]
            assert not [a for a, act in actions.items() if "delete" in act], actions

            with terraform_apply(
                terraform_module_dir,
                destroy_after=False,
                json_output=True,
            ) as after:
                assert after["db_instance_id"]["value"] == db_instance_id

                # The same topic and subscription, under the module's key
                assert (
                    sns_client.list_subscriptions_by_topic(TopicArn=topic_arn)[
                        "Subscriptions"
                    ]
                    == subscriptions
                )
                alarms = cloudwatch_client.describe_alarms(
                    AlarmNamePrefix=alarm_prefix
                )["MetricAlarms"]
                assert len(alarms) == ENGINES["postgres"]["alarm_count"], alarms
                for alarm in alarms:
                    assert alarm["AlarmActions"] == [topic_arn], alarm["AlarmName"]
                _check_alarms_key(
                    kms_client,
                    sns_client.get_topic_attributes(TopicArn=topic_arn)["Attributes"][
                        "KmsMasterKeyId"
                    ],
                    {a["AlarmArn"] for a in alarms},
                )

                # The filter on the group RDS made, with the group's retention as it was
                lock_table_alarm = f"{alarm_prefix}out-of-shared-memory"
                assert [
                    f["filterName"]
                    for f in logs_client.describe_metric_filters(
                        logGroupName=log_group_name
                    )["metricFilters"]
                ] == [lock_table_alarm]
                assert (
                    _log_group(logs_client, log_group_name).get("retentionInDays")
                    == retention
                )

                # CloudWatch can now publish to the topic
                summaries = _set_alarm_state_and_wait_for_action(
                    cloudwatch_client, lock_table_alarm
                )
                LOG.info(
                    "%s's actions under the module's key: %s",
                    lock_table_alarm,
                    summaries,
                )
                assert (
                    f"Successfully executed action {topic_arn}" in summaries
                ), summaries
    finally:
        if osp.isfile(override):
            os.remove(override)
