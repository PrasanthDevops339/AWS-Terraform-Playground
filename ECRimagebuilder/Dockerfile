FROM public.ecr.aws/amazonlinux/amazonlinux:latest

RUN yum install -y python3 && \
    yum clean all

WORKDIR /app

COPY app.py .

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 app.py || exit 1

CMD ["python3", "app.py"]
