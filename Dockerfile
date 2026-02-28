# --- STAGE 0: NATIVE BASE ---
FROM ubuntu:noble AS base
ENV DEBIAN_FRONTEND=noninteractive

# Enable source repositories and install the "mk-build-deps" tool (devscripts)
RUN sed -i 's/Types: deb/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && apt-get install -y \
    git build-essential cmake \
    debhelper devscripts pkg-config tar xz-utils \
    equivs # Required for mk-build-deps

# --- STAGE 1: KATIE (Framework) ---
FROM base AS build-katie
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/Katie.git
WORKDIR /build/Katie
RUN ln -sv package/debian . && \
    mk-build-deps -i -t "apt-get -y --no-install-recommends" debian/control && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 2: KATANALIBS (Colors) ---
FROM base AS build-libs
COPY --from=build-katie /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build
RUN git clone --depth=1 https://bitbucket.org/smil3y/kdelibs.git
WORKDIR /build/kdelibs
RUN ln -sv packaging/debian/katanalibs debian
# [INJECTION]
COPY original_hml_data/desktoptheme/hannah_montana/colors kdeui/colors/HannahMontana.colors
RUN mk-build-deps -i -t "apt-get -y --no-install-recommends" debian/control && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 3: ARIYA-ICONS (Icons) ---
FROM base AS build-icons
WORKDIR /build/icons-build
RUN git clone --depth=1 https://github.com/fluxer/katana.git .
WORKDIR /build/icons-build/packaging/debian/ariya-icons
# [INJECTION]
COPY icons.tar.xz /tmp/
RUN rm -rf icons/* && tar -xJvf /tmp/icons.tar.xz -C icons/ --strip-components=1
RUN mk-build-deps -i -t "apt-get -y --no-install-recommends" debian/control && \
    dpkg-buildpackage -uc -us -b

# --- STAGE 4: KATANA-WORKSPACE (The Desktop) ---
FROM base AS build-workspace
COPY --from=build-libs /build/*.deb /tmp/deps/
RUN dpkg -i /tmp/deps/*.deb || apt-get install -f -y
WORKDIR /build/workspace-build
RUN git clone --depth=1 https://github.com/fluxer/katana.git .
# [INJECTION]
COPY original_hml_data/desktoptheme/hannah_montana/ plasma/desktop/shell/data/desktoptheme/hannah_montana/
COPY original_hml_data/ksplash/Themes/hannah_montana/ ksplash/ksplashqml/themes/hannah_montana/
COPY original_hml_data/wallpapers/ plasma/desktop/shell/data/wallpapers/
# Theming Defaults
RUN sed -i 's/theme=default/theme=hannah_montana/g' plasma/desktop/shell/data/plasmarc && \
    sed -i 's/wallpaper=default/wallpaper=hannah_montana/g' plasma/desktop/shell/data/plasmarc
WORKDIR /build/workspace-build/packaging/debian/katana-workspace
RUN mk-build-deps -i -t "apt-get -y --no-install-recommends" debian/control && \
    dpkg-buildpackage -uc -us -b

# --- FINAL STAGE: EXPORT ---
FROM scratch AS export
COPY --from=build-katie /build/*.deb /
COPY --from=build-libs /build/*.deb /
COPY --from=build-icons /build/icons-build/packaging/*.deb /
COPY --from=build-workspace /build/workspace-build/packaging/*.deb /
