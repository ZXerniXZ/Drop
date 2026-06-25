FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py config.py database.py auth.py ./
COPY models/ ./models/
COPY services/ ./services/

RUN mkdir -p storage

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-keep-alive", "600"]
