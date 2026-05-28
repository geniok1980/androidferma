FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip \
    && unzip -q /tmp/platform-tools.zip -d /opt \
    && rm /tmp/platform-tools.zip \
    && ln -s /opt/platform-tools/adb /usr/local/bin/adb

COPY pyproject.toml README.md alembic.ini ./
COPY gitd ./gitd
COPY run.py ./

RUN mkdir -p /app/data

RUN python -m pip install --upgrade pip \
    && pip install ".[llm,ocr]"

EXPOSE 5055

CMD ["python", "run.py"]
