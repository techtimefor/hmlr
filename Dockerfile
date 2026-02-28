# --- STAGE 0: NATIVE BASE ---
FROM ubuntu:noble AS base
ENV DEBIAN_FRONTEND=noninteractive

# Install core build tools
RUN apt-get update && apt-get install -y \
    git build-essential cmake \
    debhelper devscripts pkg-config tar xz-utils

# --- STAGE 1: KATIE (The Engine) ---
FROM base AS build-katie
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/Katie.git
WORKDIR /build/Katie
RUN ln -sv package/debian . && \
    apt-get build-dep -y debian/control && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 2: KATANALIBS (Color Scheme Injection) ---
FROM base AS build-libs
COPY --from=build-katie /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/kdelibs.git
WORKDIR /build/kdelibs
RUN ln -sv packaging/debian/katanalibs debian

# [INJECTION] Injecting the Hannah Montana colors
COPY original_hml_data/desktoptheme/hannah_montana/colors kdeui/colors/HannahMontana.colors

RUN apt-get build-dep -y debian/control && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 3: ARIYA-ICONS (Icon Swap) ---
FROM base AS build-icons
WORKDIR /build/icons-build
RUN git clone --depth=1 https://github.com/fluxer/katana.git .
WORKDIR /build/icons-build/packaging/debian/ariya-icons

# [INJECTION] Replacing Ariya with Hannah icons
COPY icons.tar.xz /tmp/
RUN rm -rf icons/* && tar -xJvf /tmp/icons.tar.xz -C icons/ --strip-components=1

RUN apt-get build-dep -y debian/control && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 4: KATANA-WORKSPACE (Theme & Wallpaper Injection) ---
FROM base AS build-workspace
COPY --from=build-libs /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build/workspace-build
RUN git clone --depth=1 https://github.com/fluxer/katana.git .

# [INJECTION] Mapping themed folders from your project directory
COPY original_hml_data/desktoptheme/hannah_montana/ plasma/desktop/shell/data/desktoptheme/hannah_montana/
COPY original_hml_data/ksplash/Themes/hannah_montana/ ksplash/ksplashqml/themes/hannah_montana/
COPY original_hml_data/wallpapers/ plasma/desktop/shell/data/wallpapers/

# Hard-code Plasma defaults for the Hannah Montana experience
RUN sed -i 's/theme=default/theme=hannah_montana/g' plasma/desktop/shell/data/plasmarc && \
    sed -i 's/wallpaper=default/wallpaper=hannah_montana/g' plasma/desktop/shell/data/plasmarc

WORKDIR /build/workspace-build/packaging/debian/katana-workspace
RUN apt-get build-dep -y debian/control && \
    dpkg-buildpackage -uc -us -b

# --- FINAL STAGE: EXPORT ---
FROM scratch AS export
# Collect all .deb files from all stages for extraction
COPY --from=build-katie /build/*.deb /
COPY --from=build-libs /build/*.deb /
COPY --from=build-icons /build/icons-build/packaging/*.deb /
COPY --from=build-workspace /build/workspace-build/packaging/*.deb /
