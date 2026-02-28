## Hannah Montana Linux Revived (hmlr)

A revived version of the ancient Hannah Montana Kubuntu based distro (wip)

## Downloads

Check releases for latest iso avaliable or you can manually build it following the building process.

## Building Process

Building Katana (hml customizations added)

```sh
docker build -t hmlr-v4-builder .
```

```sh
# Create a local directory for the files
mkdir -p ./finished_debs

# Create a temporary container instance (it won't run, just exist)
docker create --name hml-temp hmlr-v4-builder

# Copy ALL .deb files from the root of the container to your local folder
docker cp hml-temp:/. ./finished_debs/

# Clean up the temporary container
docker rm hml-temp
```

Building the ISO

> DO NOT RUN THE SCRIPT AS ROOT OR SUDO YOURSELF

1.
```sh
git clone https://github.com/techtimefor/hmlr.git
```
2.
```sh
cd hmlr.git
```
3.
```sh
chmod +x hmlr-builder.sh
```
4.
```sh
./hmlr-builder.sh
```

## Credits 

[Hannah Montana Linux](https://hannahmontana.sourceforge.net/)

[Ubuntu](https://ubuntu.com)

[Debian](https://debian.org)

