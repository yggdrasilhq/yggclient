#! /usr/bin/bash

install_location="${HOME}/.local/bin"

mkdir -p "$install_location"  && cd $install_location
rm kmonad

wget "https://git.example/yggdrasil/kmonad/releases/download/25de8837fd/kmonad"
chmod +x kmonad

echo
echo "kmonad is downloaded from git.example/yggdrasil/kmonad"
echo "It is downloaded in $install_location"
echo
echo "It is not required to be added in path as the systemd service"
echo "file will call the full path as $install_location/kmonad"