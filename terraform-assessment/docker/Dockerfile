# # Use Prefect base image
# FROM prefecthq/prefect:2-latest

# # Set working directory inside container
# WORKDIR /opt/prefect

# # Copy flow code into container (same folder now)
# COPY my_flow.py .


# FROM prefecthq/prefect:2-latest
# WORKDIR /opt/prefect
# COPY my_flow.py .


# Base image Prefect v2
FROM prefecthq/prefect:2-latest

# Set working directory
WORKDIR /opt/prefect

# Copy your flow code into container
COPY my_flow.py .

# (optional) extra dependencies agar ho to
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt
