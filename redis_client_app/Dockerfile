# syntax=docker/dockerfile:1
FROM python:3.13-slim-trixie AS builder

WORKDIR /build
COPY requirements.txt requirements.txt
RUN pip install --upgrade pip && pip wheel --wheel-dir /wheels -r requirements.txt

FROM python:3.13-slim-trixie

WORKDIR /app
COPY requirements.txt requirements.txt
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && rm -rf /wheels
COPY . .

RUN useradd --system --uid 1001 --create-home app && chown -R app:app /app
USER app

ENTRYPOINT [ "python3", "cache_client.py"]
