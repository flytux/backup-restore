#!/bin/sh

sudo -i

yum groupinstall "Development tools" -y

yum install ncurses-devel wget -y

wget https://sourceforge.net/projects/zsh/files/zsh/5.6.2/zsh-5.6.2.tar.xz/download

tar -xvJf download

cd zsh-5.6.2 && ./configure

make && make install

