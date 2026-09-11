#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/lambda
# Pure-Python boto3 dependency tree; target Linux for Lambda/CodeBuild consistency.
python3 -m pip install --disable-pip-version-check --requirement requirements.txt \
  --target .build/lambda --upgrade --only-binary=:all: --platform manylinux2014_x86_64 \
  --implementation cp --python-version 3.12
cp runtime/factory.py .build/lambda/factory.py
