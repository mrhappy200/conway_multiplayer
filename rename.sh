#! /usr/bin/env nix
#! nix shell nixpkgs#busybox --command bash

while true; do
read -r -p "please name your project: " name

if [ -z "$name" ]
then
      echo "please give an input"
      break
else
      find . -type f -exec sed -i "s/\%\#project-name\%\#/$name/g" {} \;
      exit
fi
done
