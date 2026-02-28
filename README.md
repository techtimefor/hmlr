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
# Create a folder for the finished packages
mkdir -p ./finished_debs
```

```sh

# Run a temporary container to copy the files out
docker run --rm -v $(pwd)/finished_debs:/out hmlr-v4-builder bash -c "cp /*.deb /out/"
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

