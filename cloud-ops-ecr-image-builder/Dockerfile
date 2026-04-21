FROM python:3.12

# Install system dependencies for numpy/pandas
RUN apt-get update && apt-get install -y \
    build-essential \
    python3-dev \
    libpq-dev \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

ADD scripts/ /

RUN pip3 install --upgrade pip
RUN pip3 install --upgrade pip setuptools
RUN pip3 install -r /requirements.txt

RUN pip3 install opentelemetry-sdk
RUN pip3 install splunk-opentelemetry
RUN pip3 install opentelemetry-instrumentation
RUN pip3 install opentelemetry-instrumentation-logging

RUN opentelemetry-bootstrap

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &&\
    unzip -q ./awscliv2.zip &&\
    ./aws/install &&\
    rm -f ./awscliv2.zip &&\
    mkdir ~/.aws/ &&\
    touch ~/.aws/credentials

# Wrap every ECS task command with a 3-hour (10800s) timeout.
# Each task definition passes its own `command`; this ENTRYPOINT prepends the
# timeout automatically — no per-task changes needed.
# Exit code 124 = timeout fired; 137 = SIGKILL after grace period.
ENTRYPOINT ["timeout", "--kill-after=60s", "10800s"]

