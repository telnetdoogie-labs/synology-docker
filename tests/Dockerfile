# Runs as root because the mocked tests write DSM paths under /usr and /var.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends bash jq && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
ENV DSM_MOCK_CONTAINER=1
CMD ["bash", "-c", "bash tests/run.sh && bash tests/workflows.sh"]
