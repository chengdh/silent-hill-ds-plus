# SPDX-License-Identifier: GPL-3.0-or-later
#
# Reproducible host for android/build.sh. Keep ANDROID_NDK_VERSION and
# ANDROID_COMPILE_SDK in sync with android/versions.env.
#
#   docker build -t sh-android-builder -f android/Dockerfile android
#   docker run --rm -v "$PWD":/work -w /work/silent-hill sh-android-builder \
#       sh android/build.sh all
#
# The default base provides Gradle 8.9 + JDK 17 (AGP 8.6.1 requires JDK 17).
# Network access is needed on the first run: the SDK/NDK download, the git
# clones and Gradle's Android Gradle Plugin dependency are not cached in the
# image.
#
# Any image that already ships JDK 17 can be used instead -- handy when the
# local network cannot reach Docker Hub, or when an SDK/NDK is already baked
# into another image and does not have to be downloaded again:
#
#   docker build --build-arg BASE_IMAGE=my-android-image \
#       -t sh-android-builder -f android/Dockerfile android

ARG BASE_IMAGE=gradle:8.9-jdk17
FROM ${BASE_IMAGE}

# Some bases drop to an unprivileged user; apt and installing the SDK under
# /opt both need root.
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake ninja-build git python3 curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_NDK_VERSION=27.2.12479018
ARG ANDROID_COMPILE_SDK=34
ARG ANDROID_BUILD_TOOLS=34.0.0
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}

# Keep a cmdline-tools that the base image already provides: downloading it
# again would only risk overwriting a working sdkmanager.
RUN set -eu; \
    if [ ! -x "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]; then \
        mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"; \
        curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
            -o /tmp/cmdline-tools.zip; \
        unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools"; \
        mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest"; \
        rm /tmp/cmdline-tools.zip; \
    fi; \
    yes | sdkmanager --licenses >/dev/null 2>&1 || true; \
    sdkmanager --install \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "platform-tools" \
        "ndk;${ANDROID_NDK_VERSION}"

ENV ANDROID_NDK_HOME=${ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}
ENV ANDROID_NDK_ROOT=${ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}

WORKDIR /work
