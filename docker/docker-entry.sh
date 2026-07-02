#!/usr/bin/env bash
set -euo pipefail

is_github_hosted_runner() {
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && {
        [[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] ||
        [[ -n "${ImageOS:-}" ]] ||
        [[ -n "${ImageVersion:-}" ]]
    }
}

run_container_command() {
    if [[ "$#" -gt 0 ]]; then
        exec "$@"
    fi
    exit 0
}

if is_github_hosted_runner; then
    echo "GitHub-hosted runner detected; skipping self-hosted runner setup."
    run_container_command "$@"
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "GITHUB_TOKEN is not set" >&2
    exit 1
fi

mkdir -p /usr/local/actions-runner || { echo "Failed to create directory" >&2; exit 1; }

cd /usr/local/actions-runner || { echo "Failed to change directory" >&2; exit 1; }

curl -o actions-runner-linux-x64-2.335.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-linux-x64-2.335.1.tar.gz || { echo "Failed to download actions runner" >&2; exit 1; }

echo "4ef2f25285f0ae4477f1fe1e346db76d2f3ebf03824e2ddd1973a2819bf6c8cf  actions-runner-linux-x64-2.335.1.tar.gz" | shasum -a 256 -c || { echo "Failed to verify checksum" >&2; exit 1; }

tar xzf ./actions-runner-linux-x64-2.335.1.tar.gz || { echo "Failed to extract actions runner" >&2; exit 1; }

rm ./actions-runner-linux-x64-2.335.1.tar.gz || { echo "Failed to remove actions runner tar.gz" >&2; exit 1; }

REG_TOKEN=$(curl -X POST -H "Authorization: token ${GITHUB_TOKEN}" \
https://api.github.com/repos/akashskypatel/ffmpeg-kit-builders/actions/runners/registration-token | jq -r .token) || { echo "Failed to fetch registration token" >&2; exit 1; }

./config.sh --url https://github.com/akashskypatel/ffmpeg-kit-builders \
            --token "${REG_TOKEN}" \
            --name "gcp-worker-$(hostname)" \
            --unattended --replace --ephemeral || { echo "Failed to configure runner" >&2; exit 1; }

./svc.sh install || { echo "Failed to install GitHub Actions runner service" >&2; exit 1; }

./svc.sh start || { echo "Failed to start GitHub Actions runner service" >&2; exit 1; }
