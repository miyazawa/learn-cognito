FROM python:3.12-slim

# Do not write .pyc files; flush logs immediately so they show up in CloudWatch Logs
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies first so this layer is cached unless requirements.txt changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# main.py reads index.html at startup, so both files must be in the image
COPY main.py index.html ./

# Run as a non-root user
RUN useradd --create-home appuser
USER appuser

# Must match app_port in the Terraform variables
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
