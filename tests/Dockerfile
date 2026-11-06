# Disposable Debian test environment; fake DSM paths are created only inside it.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends bash jq && rm -rf /var/lib/apt/lists/* \
    && touch /etc/synology-docker-test-image
WORKDIR /workspace
ENV DSM_MOCK_CONTAINER=1
CMD ["bash", "tests/run.sh"]
