FROM mcr.microsoft.com/playwright/python:v1.57.0-jammy

RUN pip install awslambdaric
WORKDIR /var/task
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .

ENTRYPOINT [ "/usr/bin/python", "-m", "awslambdaric" ]
CMD [ "app.handler" ]