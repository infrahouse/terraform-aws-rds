import json
import os
import stat
import shutil
from os import path as osp
from textwrap import dedent
from typing import Optional

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import LOG, TERRAFORM_ROOT_DIR


def _remove_readonly(func, path, _exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_rds(
    service_network,
    keep_after: bool,
    test_role_arn: Optional[str],
    aws_region: str,
    aws_provider_version: str,
) -> None:
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "rds")

    terraform_dir = osp.join(terraform_module_dir, ".terraform")
    if osp.isdir(terraform_dir):
        shutil.rmtree(terraform_dir, onexc=_remove_readonly)
    lock_file = osp.join(terraform_module_dir, ".terraform.lock.hcl")
    if osp.isfile(lock_file):
        os.remove(lock_file)

    with open(osp.join(terraform_module_dir, "terraform.tf"), "w") as fp:
        fp.write(
            dedent(
                f"""
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
                """
            )
        )

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region     = "{aws_region}"
                subnet_ids = {json.dumps(service_network["subnet_private_ids"]["value"])}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{test_role_arn}"
                    """
                )
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
