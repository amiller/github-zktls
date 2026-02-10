FROM python:3.11-slim
RUN pip install web3 dstack-sdk eth-account eth-keys eciespy
COPY app.py /app.py
EXPOSE 8080
CMD ["python", "-u", "/app.py"]
