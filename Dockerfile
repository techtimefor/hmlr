ckerfile
# --- STAGE 0: BASE ---
FROM ubuntu:noble AS base
ENV DEBIAN_FRONTEND=noninteractive

# 1. Enable s390x architecture
RUN dpkg --add-architecture s390x

# 2. Update sources.list to be ARCH-SPECIFIC
# This prevents the 404s by telling apt exactly where to find each arch
RUN sed -i 's/^deb http/deb [arch=amd64] http/' /etc/apt/sources.list && \
    echo "deb [arch=s390x] http://ports.ubuntu.com/ubuntu-ports noble main universe restricted multiverse" > /etc/apt/sources.list.d/s390x.list && \
    echo "deb [arch=s390x] http://ports.ubuntu.com/ubuntu-ports noble-updates main universe restricted multiverse" >> /etc/apt/sources.list.d/s390x.list && \
    echo "deb [arch=s390x] http://ports.ubuntu.com/ubuntu-ports noble-security main universe restricted multiverse" >> /etc/apt/sources.list.d/s390x.list

# 3. Standard update and tool install
RUN apt-get update && apt-get install -y \
    git build-essential cmake crossbuild-essential-s390x \
    debhelper devscripts pkg-config-s390x tar xz-utils

# --- STAGE 1: KATIE ---
FROM base AS build-katie
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/Katie.git
WORKDIR /build/Katie
RUN ln -sv package/debian . && \
    apt-get build-dep -y -a s390x . && \
    dpkg-buildpackage -uc -us -b -a s390x

# --- STAGE 2: KATANALIBS ---
FROM base AS build-libs
COPY --from=build-katie /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/kdelibs.git
WORKDIR /build/kdelibs
RUN ln -sv packaging/debian/katanalibs debian

# [INJECTION] Mapping the Hannah Montana color scheme
# Source: original_hml_data/desktoptheme/hannah_montana/colors
COPY original_hml_data/desktoptheme/hannah_montana/colors kdeui/colors/HannahMontana.colors

RUN apt-get build-dep -y -a s390x . && \
    dpkg-buildpackage -uc -us -b -a s390x

# --- STAGE 3: ARIYA-ICONS ---
FROM base AS build-icons
WORKDIR /build/katana/packaging/debian/ariya-icons
COPY icons.tar.xz /tmp/
# Strips 'hannah_montana' folder inside the tar to extract resolutions directly
RUN rm -rf icons/* && tar -xJvf /tmp/icons.tar.xz -C icons/ --strip-components=1
RUN dpkg-buildpackage -uc -us -b -a s390x

# --- STAGE 4: KATANA-WORKSPACE ---
FROM base AS build-workspace
COPY --from=build-libs /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build
RUN git clone --depth=1 https://github.com/fluxer/katana.git
WORKDIR /build/katana

# [INJECTION] Mapping themed folders
COPY original_hml_data/desktoptheme/hannah_montana/ plasma/desktop/shell/data/desktoptheme/hannah_montana/
COPY original_hml_data/ksplash/Themes/hannah_montana/ ksplash/ksplashqml/themes/hannah_montana/
COPY original_hml_data/wallpapers/ plasma/desktop/shell/data/wallpapers/

# Configure Plasma defaults
RUN sed -i 's/theme=default/theme=hannah_montana/g' plasma/desktop/shell/data/plasmarc && \
    sed -i 's/wallpaper=default/wallpaper=hannah_montana/g' plasma/desktop/shell/data/plasmarc

WORKDIR /build/katana/packaging/debian/katana-workspace
RUN apt-get build-dep -y -a s390x . && \
    dpkg-buildpackage -uc -us -b -a s390x

# --- EXPORT ---
FROM scratch AS export
COPY --from=build-workspace /build/katana/packaging/debian/*.deb /
