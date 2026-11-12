# SPDX-License-Identifier: GPL-3.0-or-later
#
# Reproducible host for android/build.sh. Keep ANDROID_NDK_VERSION and
# ANDROID_COMPILE_SDK in sync with android/versions.env.
#
#   docker build -t sh-android-builder -f android/Dockerfile android
#   docker run --rm -v "$PWD":/work -w /work/silent-hill sh-android-builder \
#       sh android/build.sh all
#
# The Gradle image already provides Gradle 8.9 + JDK 17. Network access is
# needed on the first run: the SDK/NDK download, the git clones and Gradle's
# Android Gradle Plugin dependency are not cached in the image.

FROM gradle:8.9-jdk17

# The Gradle image drops to the unprivileged "gradle" user; installing the
# Android SDK under /opt needs root.
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake ninja-build git python3 curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_NDK_VERSION=27.2.12479018
ARG ANDROID_COMPILE_SDK=34
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}

RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" && \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
        -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools" && \
    mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest" && \
    rm /tmp/cmdline-tools.zip && \
    yes | sdkmanager --licenses >/dev/null && \
    sdkmanager --install \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;34.0.0" \
        "platform-tools" \
        "ndk;${ANDROID_NDK_VERSION}"

WORKDIR /work
