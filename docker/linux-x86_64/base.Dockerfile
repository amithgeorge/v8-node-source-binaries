# Copyright (c) 2021 caoccao.com Sam Cao
# All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Usage: docker build -t sjtucaocao/javet:2.0.0 -f docker/linux-x86_64/base.Dockerfile .

FROM ubuntu:20.04
WORKDIR /

ARG JAVET_V8_VERSION
ARG JAVET_NODE_VERSION

RUN if [ -z "$JAVET_V8_VERSION" ]; then echo 'Build argument JAVET_V8_VERSION must be specified. Exiting.'; exit 1; fi
RUN if [ -z "$JAVET_NODE_VERSION" ]; then echo 'Build argument JAVET_NODE_VERSION must be specified. Exiting.'; exit 1; fi

# Update Ubuntu
ENV DEBIAN_FRONTEND=noninteractive
# files need to be cleaned/deleted in the same RUN layer that adds them, else there is no actual size reduction benefit
# the files remain in the image, just the layer marks the file as deleted and is not visible inside the OS
RUN apt-get update --yes \
	&& apt-get install --upgrade -qq --yes --no-install-recommends \
	build-essential cmake curl execstack git maven openjdk-8-jdk \
	patchelf python3 python python3-pip python3-distutils python3-testresources \
	software-properties-common sudo unzip wget zip \
	&& apt-get upgrade --yes \
	&& pip3 install --no-cache-dir coloredlogs \
	&& apt-get clean --yes

# Install CMake
RUN wget https://github.com/Kitware/CMake/releases/download/v3.21.4/cmake-3.21.4-linux-x86_64.sh \
	&& chmod 755 cmake-3.21.4-linux-x86_64.sh \
	&& mkdir -p /usr/lib/cmake \
	&& ./cmake-3.21.4-linux-x86_64.sh --skip-license --exclude-subdir --prefix=/usr/lib/cmake \
	&& ln -sf /usr/lib/cmake/bin/cmake /usr/bin/cmake \
	&& ln -sf /usr/lib/cmake/bin/cmake /bin/cmake \
	&& rm cmake-3.21.4-linux-x86_64.sh

# Prepare Javet Build Environment
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
ENV SDKMAN_HOME="/root/.sdkman"
ENV GRADLE_HOME="${SDKMAN_HOME}/candidates/gradle/current"
ENV PATH=$GRADLE_HOME/bin:$PATH

RUN rm /bin/sh && ln -s /bin/bash /bin/sh
# these two commands need to be on separate lines, else the symlink created above is not visible to the commands run below.
# if the two RUN commmands are merged, we get the error "source: not found"
RUN curl -s https://get.sdkman.io | bash \
	&& source ${SDKMAN_HOME}/bin/sdkman-init.sh \
	&& sdk install gradle 7.2 \
	&& rm -rf ${SDKMAN_HOME}/archives/* \
	&& rm -rf ${SDKMAN_HOME}/tmp/*

# Prepare V8
WORKDIR /google
ENV DEPOT_TOOLS_UPDATE=0
ENV PATH=/google/depot_tools:$PATH
# RUN git clone --depth=10 --branch=main https://chromium.googlesource.com/chromium/tools/depot_tools.git
# WORKDIR /google/depot_tools
# RUN git checkout remotes/origin/main

# WORKDIR /google
# RUN fetch --nohistory v8
# RUN mkdir v8 && cd v8 && \
# 	git init . && \
# 	git fetch https://chromium.googlesource.com/v8/v8.git +refs/tags/${JAVET_V8_VERSION}:v8_${JAVET_V8_VERSION} --depth 1 && \
# 	git checkout tags/${JAVET_V8_VERSION} && \
# 	cd ../ && \
# 	gclient root && \
# 	gclient config --spec 'solutions = [{"name": "v8","url": "https://chromium.googlesource.com/v8/v8.git","deps_file": "DEPS","managed": False,"custom_deps": {},},]' && \
# 	gclient sync --no-history && \
# 	gclient runhooks
# WORKDIR /google/v8
# RUN git checkout branch-heads/${JAVET_V8_BRANCH_HEAD}
# RUN sed -i 's/snapcraft/nosnapcraft/g' ./build/install-build-deps.sh
# RUN ./build/install-build-deps.sh
# RUN sed -i 's/nosnapcraft/snapcraft/g' ./build/install-build-deps.sh
# WORKDIR /google
# #RUN gclient sync
# RUN gclient sync --no-history
# RUN echo V8 preparation is completed.
COPY ./scripts/shell/fetch_v8_source .
RUN bash fetch_v8_source

# Build V8
WORKDIR /google/v8
COPY ./scripts/python/patch_v8_build.py .
# RUN python3 tools/dev/v8gen.py x64.release -- v8_monolithic=true v8_use_external_startup_data=false is_component_build=false v8_enable_i18n_support=false v8_enable_pointer_compression=false v8_static_library=true symbol_level=0 use_custom_libcxx=false v8_enable_sandbox=false
# RUN ninja -C out.gn/x64.release v8_monolith || python3 patch_v8_build.py -p ./
# RUN ninja -C out.gn/x64.release v8_monolith
# RUN rm patch_v8_build.py
# RUN echo V8 build is completed.
COPY ./scripts/shell/build_v8_source .
RUN bash ./build_v8_source

# Prepare Node.js v18
WORKDIR /
# RUN git clone --depth=1 --branch=v${JAVET_NODE_VERSION} https://github.com/nodejs/node.git
# WORKDIR /node
# RUN git checkout v${JAVET_NODE_VERSION}
# RUN echo Node.js preparation is completed.
COPY ./scripts/shell/fetch_node_source .
RUN bash ./fetch_node_source

# Build Node.js
WORKDIR /node
COPY ./scripts/python/patch_node_build.py .
# RUN python3 patch_node_build.py -p ./
# RUN ./configure --enable-static --without-intl
# RUN python3 patch_node_build.py -p ./
# RUN rm patch_node_build.py
# RUN make -j4
# RUN echo Node.js build is completed.
COPY ./scripts/shell/build_node_source .
RUN bash ./build_node_source

# # Shrink
# RUN rm -rf ${SDKMAN_HOME}/archives/*
# RUN rm -rf ${SDKMAN_HOME}/tmp/*
# RUN apt-get clean -y
# RUN rm -rf /var/lib/apt/lists/*
# WORKDIR /

# # Pre-cache Dependencies
# RUN mkdir Javet
# WORKDIR /Javet
# COPY . .
# RUN gradle dependencies
# WORKDIR /
# RUN rm -rf /Javet

# # Completed
# RUN echo Javet build base image is completed.