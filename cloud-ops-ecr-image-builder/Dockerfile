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

#CMD ["opentelemetry-instrument", "python3", "config_aggregator.py"]
