# Extend the existing vllm image with DeepGEMM for fp8 computing
FROM scitrera/dgx-spark-vllm:0.16.1-dev-3bbb2046-t5

# Install dependencies in one layer for better caching
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        build-essential \
        curl && \
    rm -rf /var/lib/apt/lists/*

# Clone and install DeepGEMM
RUN mkdir /tmp/deepgemm
WORKDIR /tmp/deepgemm
RUN git clone --recursive --depth 1 https://github.com/deepseek-ai/DeepGEMM .

# Install DeepGEMM using setup.py and uv pip in one layer
RUN python3 setup.py install

# Clean up build artifacts to reduce image size
RUN rm -rf /tmp/deepgemm/.git /tmp/deepgemm/build /tmp/deepgemm/*.egg-info

# Install the newest version of vLLM
RUN git clone --depth 1 https://github.com/vllm-project/vllm.git /tmp/vllm_moe_tune
WORKDIR /tmp/vllm_moe_tune
RUN python3 setup.py install

# Clean up build artifacts
RUN rm -rf /tmp/vllm_moe_tune/.git /tmp/vllm_moe_tune/build /tmp/vllm_moe_tune/*.egg-info

# Return to app directory
WORKDIR /app
