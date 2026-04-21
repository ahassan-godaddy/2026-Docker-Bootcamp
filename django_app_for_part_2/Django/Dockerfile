# syntax=docker/dockerfile:1
FROM python:3.13-slim-trixie AS builder

WORKDIR /build
COPY requirements.txt /build/
RUN pip install --upgrade pip && pip wheel --wheel-dir /wheels -r requirements.txt

FROM python:3.13-slim-trixie
ENV PYTHONUNBUFFERED=1
WORKDIR /code
COPY requirements.txt /code/
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && rm -rf /wheels
COPY . /code/
RUN useradd --system --uid 1001 --create-home app && chown -R app:app /code
USER app
ENTRYPOINT /bin/bash docker-entrypoint.sh