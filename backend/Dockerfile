FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir google-cloud-pubsub google-cloud-bigquery
COPY executor.py .
ENV PORT=8080
CMD ["python", "executor.py"]
