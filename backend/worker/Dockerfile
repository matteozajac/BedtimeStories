FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system worker && useradd --system --gid worker --create-home worker
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY *.py ./
USER worker
ENV PYTHONUNBUFFERED=1 PORT=8080
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 1 --threads 1 --timeout 1800 --access-logfile /dev/null server:app"]
