# Extend the existing vllm image with DeepGEMM for fp8 computing
FROM scitrera/dgx-spark-vllm:0.15.0-t5

# Install dependencies in one layer for better caching
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

# # Clone and install DeepGEMM
# WORKDIR /tmp/deepgemm
# RUN git clone --recursive --depth 1 https://github.com/deepseek-ai/DeepGEMM .

# # Install DeepGEMM using setup.py and uv pip in one layer
# RUN python setup.py install && \
#     uv pip install -e .

# # Clean up build artifacts to reduce image size
# RUN rm -rf /tmp/deepgemm/.git /tmp/deepgemm/build /tmp/deepgemm/*.egg-info

# Return to app directory
WORKDIR /app
