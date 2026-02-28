# --- STAGE 0: NATIVE BASE ---
FROM ubuntu:noble AS base
ENV DEBIAN_FRONTEND=noninteractive

# Standard Ubuntu repositories for native build
RUN apt-get update && apt-get install -y \
    git build-essential cmake \
    debhelper devscripts pkg-config tar xz-utils

# --- STAGE 1: KATIE (Build Framework) ---
FROM base AS build-katie
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/Katie.git
WORKDIR /build/Katie
RUN ln -sv package/debian . && \
    apt-get build-dep -y . && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 2: KATANALIBS (Color Injection) ---
FROM base AS build-libs
COPY --from=build-katie /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/kdelibs.git
WORKDIR /build/kdelibs
RUN ln -sv packaging/debian/katanalibs debian

# [INJECTION] Injecting the Hannah Montana color palette
COPY original_hml_data/desktoptheme/hannah_montana/colors kdeui/colors/HannahMontana.colors

RUN apt-get build-dep -y . && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 3: ARIYA-ICONS (Icon Swap) ---
FROM base AS build-icons
WORKDIR /build/katana/packaging/debian/ariya-icons
COPY icons.tar.xz /tmp/
# Flatten 'hannah_montana' folder so resolutions (16x16, etc) land in the root
RUN rm -rf icons/* && tar -xJvf /tmp/icons.tar.xz -C icons/ --strip-components=1
RUN dpkg-buildpackage -uc -us -b

# --- STAGE 4: KATANA-WORKSPACE (The Purple Heart) ---
FROM base AS build-workspace
COPY --from=build-libs /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build
RUN git clone --depth=1 https://github.com/fluxer/katana.git
WORKDIR /build/katana

# [INJECTION] Mapping themed folders from your project
COPY original_hml_data/desktoptheme/hannah_montana/ plasma/desktop/shell/data/desktoptheme/hannah_montana/
COPY original_hml_data/ksplash/Themes/hannah_montana/ ksplash/ksplashqml/themes/hannah_montana/
COPY original_hml_data/wallpapers/ plasma/desktop/shell/data/wallpapers/

# Configure defaults directly in the Plasma source code
RUN sed -i 's/theme=default/theme=hannah_montana/g' plasma/desktop/shell/data/plasmarc && \
    sed -i 's/wallpaper=default/wallpaper=hannah_montana/g' plasma/desktop/shell/data/plasmarc

WORKDIR /build/katana/packaging/debian/katana-workspace
RUN apt-get build-dep -y . && \
    dpkg-buildpackage -uc -us -b

# --- FINAL STAGE: EXPORT ---
FROM scratch AS export
COPY --from=build-workspace /build/katana/packaging/debian/*.deb /
