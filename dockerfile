# HOCS - Optical Computing Runtime Environment
# Base Image: Official Python on Linux
FROM python:3.9-slim-buster

# Metadata
LABEL maintainer="Muhammed Yusuf Cobanoglu"
LABEL version="2.4.0"
LABEL description="HOCS Driver & Simulation Container"

# System Dependencies (GCC for compiling C++ kernels)
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/*

# Work Directory
WORKDIR /app

# Install Python Dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy Source Code
COPY . .

# Compile C++ Physics Engine
RUN mkdir -p cpp_core/build && \
    cd cpp_core/build && \
    cmake .. && \
    make

# Expose API Port
EXPOSE 8000

# Health Check (Keep container alive)
HEALTHCHECK --interval=30s --timeout=10s \
  CMD curl -f http://localhost:8000/ || exit 1

# Default Command: Start API Server
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]

