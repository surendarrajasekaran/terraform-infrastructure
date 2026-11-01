"""Install the Argo controller and bootstrap its parent Application over a private API."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import ssl
import subprocess
import tempfile
import urllib.request

import yaml

ROOT = Path(__file__).resolve().parent


def run(command, *, data=None):
    result = subprocess.run(command, input=data, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(
            f"{command[0]} {command[1]} failed; inspect with your operator credentials"
        )
    return result.stdout


def bootstrap(args):
    outputs = json.loads(run(["terraform", f"-chdir={ROOT}", "output", "-json"]))
    for key, expected in [
        ("cloud", "aws"),
        ("name", args.name),
        ("environment", args.environment),
        ("region", args.region),
    ]:
        if outputs[key]["value"] != expected:
            raise ValueError("Terraform outputs do not match the requested target")
    if (
        json.loads(run(["aws", "sts", "get-caller-identity"]))["Account"]
        != args.account_id
    ):
        raise ValueError("Wrong AWS account")
    cluster = json.loads(
        run(
            [
                "aws",
                "eks",
                "describe-cluster",
                "--name",
                outputs["cluster_name"]["value"],
                "--region",
                args.region,
            ]
        )
    )["cluster"]
    kube = ["kubectl", "--context", args.context]
    config = json.loads(
        run(kube + ["config", "view", "--raw", "--minify", "-o", "json"])
    )
    if (
        config["clusters"][0]["cluster"].get("certificate-authority-data")
        != cluster["certificateAuthority"]["data"]
    ):
        raise ValueError("Kubeconfig CA does not match the selected EKS cluster")
    namespace = f"{args.name}-{args.environment}"
    manifests = args.gitops_dir / "argocd-manifests"
    controls = list(
        yaml.safe_load_all(
            (
                manifests / f"{args.name}-aws-{args.environment}" / "controls.yaml"
            ).read_text()
        )
    )
    if any(
        doc.get("metadata", {}).get("namespace") != namespace
        or doc.get("kind") not in ("ResourceQuota", "NetworkPolicy")
        for doc in controls
    ):
        raise ValueError("Namespace controls do not match this target")
    backend_policy = next(
        doc
        for doc in controls
        if doc["kind"] == "NetworkPolicy"
        and doc["metadata"]["name"] == f"{args.name}-backend"
    )
    database_cidrs = {
        rule["ipBlock"]["cidr"] for rule in backend_policy["spec"]["egress"][1]["to"]
    }
    if database_cidrs != set(outputs["database_egress_cidrs"]["value"]):
        raise ValueError(
            "GitOps database egress CIDRs differ from Terraform; update the controls before bootstrap"
        )
    for file in ("projects.yaml", "idea-board-controller.yaml"):
        if not (manifests / file).is_file():
            raise ValueError("GitOps projects and parent Application are required")
    lock = json.loads((ROOT / "argocd/chart-lock.json").read_text())
    with tempfile.TemporaryDirectory(prefix="argocd-bootstrap-") as directory:
        chart = Path(directory) / "argo-cd.tgz"
        if args.chart:
            chart.write_bytes(args.chart.read_bytes())
        else:
            with urllib.request.urlopen(lock["url"], timeout=60) as response:
                chart.write_bytes(response.read(20 * 1024 * 1024))
        if hashlib.sha256(chart.read_bytes()).hexdigest() != lock["sha256"]:
            raise ValueError("Argo chart checksum does not match the reviewed lock")
        if args.check:
            print(
                "Account, Terraform target, cluster CA, GitOps controls and Argo chart checksum verified; no changes made"
            )
            return
        with urllib.request.urlopen(
            "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem",
            timeout=30,
        ) as response:
            certificate = response.read(262144).decode("ascii")
        ssl.create_default_context().load_verify_locations(cadata=certificate)
        namespace_manifest = {
            "apiVersion": "v1",
            "kind": "Namespace",
            "metadata": {
                "name": namespace,
                "labels": {
                    "pod-security.kubernetes.io/enforce": "restricted",
                    "pod-security.kubernetes.io/enforce-version": "v1.33",
                    "pod-security.kubernetes.io/audit": "restricted",
                    "pod-security.kubernetes.io/warn": "restricted",
                },
            },
        }
        run(kube + ["apply", "-f", "-"], data=json.dumps(namespace_manifest))
        run(kube + ["apply", "-f", "-"], data=yaml.safe_dump_all(controls))
        for name, values in [
            (f"{args.name}-database-ca", {"ca.crt": certificate}),
            (
                f"{args.name}-database",
                {"DATABASE_URL": outputs["database_url"]["value"]},
            ),
            (
                f"{args.name}-migration",
                {
                    "DATABASE_URL": outputs["migration_database_url"]["value"],
                    "APP_DATABASE_USER": "ideas_app",
                    "APP_DATABASE_PASSWORD": outputs["application_password"]["value"],
                },
            ),
        ]:
            secret = {
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {"name": name, "namespace": namespace},
                "type": "Opaque",
                "data": {
                    key: base64.b64encode(value.encode()).decode()
                    for key, value in values.items()
                },
            }
            run(kube + ["apply", "-f", "-"], data=json.dumps(secret))
        run(
            [
                "helm",
                "upgrade",
                "--install",
                "argocd",
                str(chart),
                "--namespace",
                "argocd",
                "--create-namespace",
                "--kube-context",
                args.context,
                "--atomic",
                "--wait",
                "--timeout",
                "900s",
                "-f",
                str(ROOT / "argocd/test-values.yaml"),
            ]
        )
        for file in ("projects.yaml", "idea-board-controller.yaml"):
            run(kube + ["apply", "-f", str(manifests / file)])
        print(
            "Argo controller installed; the parent Application manages frontend and backend from Git"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--name", default="idea-board")
    parser.add_argument(
        "--environment", choices=["test", "staging", "production"], default="test"
    )
    parser.add_argument(
        "--gitops-dir", type=Path, default=ROOT.parents[3] / "infra-helm-charts"
    )
    parser.add_argument(
        "--chart",
        type=Path,
        help="Optional local chart archive; its checksum is still verified",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate prerequisites without changing the cluster",
    )
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9-]{2,20}", args.name):
        parser.error("Use a safe lowercase stack name")
    try:
        bootstrap(args)
    except (ValueError, RuntimeError, OSError, KeyError, StopIteration) as exc:
        parser.exit(
            1,
            f"Bootstrap failed: {str(exc) if isinstance(exc, (ValueError, RuntimeError)) else type(exc).__name__}; no credentials printed\n",
        )


if __name__ == "__main__":
    main()
