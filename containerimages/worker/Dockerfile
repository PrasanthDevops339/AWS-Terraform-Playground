# trivy:ignore:DS-0026 -- Ephemeral CodeBuild CLI worker; no service endpoint to health-check.
# Build this trusted automation image separately, scan it, then supply its ECR digest.
# BASE_IMAGE must be an approved standard AL2023 x86_64 image pinned by digest.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG PACKAGE_RELEASE
RUN test -n "$PACKAGE_RELEASE" && \
    dnf --releasever="$PACKAGE_RELEASE" install -y shadow-utils skopeo python3.12 python3.12-pip && \
    dnf clean all && rm -rf /var/cache/dnf
COPY requirements.txt /tmp/requirements.txt
RUN python3.12 -m pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt
# CodeBuild manages the process; the publisher never launches candidate containers.
ENTRYPOINT []
ENV PATH="/opt/containerimages/bin:${PATH}"
RUN mkdir -p /opt/containerimages/bin && ln -s /usr/bin/python3.12 /opt/containerimages/bin/python3
RUN groupadd --gid 10001 factory && useradd --uid 10001 --gid 10001 --create-home factory
# trivy:ignore:DS-0026 -- This is an ephemeral CodeBuild CLI worker, not a long-running service.
USER 10001:10001
