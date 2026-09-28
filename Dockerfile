FROM python:3.13-slim
ARG GIT_SHA=unknown
ARG RUN_URL=unknown
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 GIT_SHA=${GIT_SHA} RUN_URL=${RUN_URL}
LABEL org.opencontainers.image.revision=${GIT_SHA} org.opencontainers.image.source=https://github.com/soodrajesh/gcp-keyless-cicd-supply-chain
WORKDIR /srv
COPY app/requirements.txt .
RUN pip install -r requirements.txt
COPY app/main.py .
RUN useradd -r -u 10001 app
USER 10001
CMD ["gunicorn", "--bind", ":8080", "--workers", "1", "--threads", "4", "main:app"]
