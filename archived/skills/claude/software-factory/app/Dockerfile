FROM node:22-bookworm-slim AS frontend
WORKDIR /build
COPY app/frontend/package*.json ./
RUN npm ci --no-audit --no-fund
COPY app/frontend/ ./
RUN npm test && npm run build

FROM python:3.12-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /opt/factory
COPY app/backend/requirements.lock /tmp/requirements.lock
RUN pip install --no-cache-dir -r /tmp/requirements.lock
COPY . ./
COPY --from=frontend /build/dist ./app/frontend/dist/
USER 65532:65532
EXPOSE 4601
HEALTHCHECK --interval=3s --timeout=2s --start-period=10s --retries=10 CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:4601/api/identity', timeout=1)"]
CMD ["python", "-m", "uvicorn", "server:app", "--app-dir", "/opt/factory/app/backend", "--host", "0.0.0.0", "--port", "4601"]
