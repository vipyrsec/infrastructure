#!/usr/bin/env python3

import argparse
import string
import base64
import logging
import subprocess
import tempfile
from pathlib import Path
from typing import Literal


LogLevel = Literal["debug", "info", "warn", "error"]

logging.basicConfig(format="[%(asctime)s] [%(levelname)-8s] %(message)s", level=logging.INFO)
log = logging.getLogger()

CSR_TEMPLATE = string.Template("""\
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest

metadata:
  name: $user

spec:
  request: $request
  signerName: kubernetes.io/kube-apiserver-client
  $expiration
  usages:
    - client auth
""")
CRB_TEMPLATE = string.Template("""\
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding

metadata:
  name: $user@$group
  labels:
    user: $user

roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $group

subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $user
""")


def run_command(command: str, input: str | None = None) -> str:
    """Run a command in a shell.

    Args:
        command: The command to run.
        input: The input for the command, if any.

    Returns:
        The output of the command.
    """
    log.debug("Running command %r", command)
    try:
        proc = subprocess.run(command, shell=True, capture_output=True, check=True, input=input, text=True)
        return proc.stdout
    except subprocess.CalledProcessError as cpe:
        log.exception("Failed to run command %r (%d): %s", cpe.cmd, cpe.returncode, cpe.stderr)
        raise


def generate_key() -> str:
    """Generate a private key.

    Returns:
        The private key.
    """
    return run_command("openssl genrsa 4096")


def create_csr(user: str, groups: list[str], key: str) -> str:
    """Create a certificate signing request (CSR).

    Args:
        user: The user for which to create the CSR.
        groups: The groups to which the user belongs.
        key: The private key of the user.

    Returns:
        The CSR.
    """
    return run_command(
        # We don't use the groups in the subject here, because we cannot revoke membership later
        # https://kubernetes.io/docs/concepts/security/hardening-guide/authentication-mechanisms/#x509-client-certificate-authentication
        f"openssl req -new -key /dev/stdin -subj /CN={user}",
        input=key,
    )


def approve_csr(csr: str, user: str, expiry_seconds: int = 31536000) -> str:
    """Approve the certificate signing request (CSR).

    Args:
        csr: The CSR to approve.
        user: The user associated to the CSR.
        expiry_seconds: The duration for which the approved certificate will be valid. Default: 31536000 (1 year).

    Returns:
        The approved certificate.
    """
    expiration = ""
    if expiry_seconds is not None:
        expiration = f"expirationSeconds: {expiry_seconds}"

    csr_manifest = CSR_TEMPLATE.substitute(user=user, request=csr, expiration=expiration)
    run_command("kubectl apply -f -", input=csr_manifest)
    run_command(f"kubectl certificate approve {user}")
    cert = run_command(f"kubectl get csr {user} -ojsonpath='{{.status.certificate}}'")
    run_command(f"kubectl delete csr {user}")
    return base64.b64decode(cert).decode()


def grant_permissions(user: str, group: str) -> None:
    """Grant permissions to the user.

    Args:
        user: The user to which to grant permissions.
        group: The group for which to grant the user permission.
    """
    crb_manifest = CRB_TEMPLATE.substitute(user=user, group=group)
    run_command("kubectl apply -f -", input=crb_manifest)


def generate_kube_config(user: str, key: str, cert: str) -> None:
    """Generate a kube config for the user.

    Args:
        user: The user for which to generate the kube config.
        key: The private key of the user.
        cert: The approved certificate of the user.

    Returns:
        The kube config.
    """
    config_path = Path(f"{user}.config")
    config = run_command("kubectl config view --flatten --minify")
    config_path.write_text(config)
    kubectl = f"kubectl --kubeconfig={config_path}"

    clusters = run_command(f"{kubectl} config get-clusters")
    cluster = clusters.splitlines()[-1]

    current_context = run_command(f"{kubectl} config current-context")
    run_command(f"{kubectl} config delete-context {current_context.strip('\n')}")

    users = run_command(f"{kubectl} config get-users")
    current_user = users.splitlines()[-1]
    run_command(f"{kubectl} config delete-user {current_user}")

    with (
        tempfile.NamedTemporaryFile("w", suffix=f"{user}.key") as key_file,
        tempfile.NamedTemporaryFile("w", suffix=f"{user}.crt") as cert_file,
    ):
        key_file.write(key)
        key_file.flush()
        cert_file.write(cert)
        cert_file.flush()

        run_command(
            f"{kubectl} config set-credentials {user}"
            f" --client-key={key_file.name}"
            f" --client-certificate={cert_file.name} --embed-certs"
        )

    context = f"{user}@{cluster}"
    run_command(f"{kubectl} config set-context {context} --cluster={cluster} --user={user}")
    run_command(f"{kubectl} config use-context {context}")

    return config_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Configure a user to access a Kubernetes cluster.",
        epilog="Make sure to set the `kubectl` context to the cluster to which you want to add the user!",
        allow_abbrev=False,
    )

    parser.add_argument("user", help="The user to create.")
    parser.add_argument(
        "-g",
        "--group",
        action="append",
        help="The group(s) to which to the user belongs.",
        choices=["vipyrsec", "vipyrsec-core-devs", "vipyrsec-admins"],
        required=True,
    )

    parser.add_argument(
        "--expiry-seconds",
        help=(
            "The duration for which the user config will be valid."
            " Minimum: 600 (10 minutes),"
            " Maximum: 31536000 (1 year),"
            " Default: 31536000 (1 year)"
        ),
        type=int,
        default=31536000,
    )

    misc_options = parser.add_argument_group("misc. options")
    misc_options.add_argument(
        "--log-level",
        help="Log verbosity. Default: info",
        choices=["debug", "info", "warn", "error"],
        default="info",
    )

    args = parser.parse_args()
    log.debug("Args: %s", args)

    user: str = args.user
    groups: list[str] = args.group

    expiry_seconds: int = args.expiry_seconds
    if not (600 <= expiry_seconds <= 31536000):
        msg = "expiry seconds must be between 600, and 31536000"
        raise ValueError(msg)

    log_level: LogLevel = args.log_level
    log.setLevel(log_level.upper())

    log.debug("Generating private key")
    key = generate_key()
    log.info("Generated private key")

    log.debug("Creating CSR for user %r with groups %r", user, groups)
    csr = create_csr(user, groups, key)
    log.info("Created CSR for user %r with groups %r", user, groups)

    log.debug("Approving CSR for user %r", user)
    encoded_csr = base64.b64encode(csr.encode()).decode().replace("\n", "")
    cert = approve_csr(encoded_csr, user, expiry_seconds)
    log.info("Approved CSR for user %r", user)

    for group in groups:
        log.debug("Granting permissions to user %r for group %r", user, group)
        grant_permissions(user, group)
        log.info("Granted permissions to user %r for group %r", user, group)

    log.debug("Generating kubeconfig for user %r", user)
    config_path = generate_kube_config(user, key, cert)
    log.debug("Generated kubeconfig for user %r", user)

    log.info(f"Config written to {config_path.resolve()}.")
