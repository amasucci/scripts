

sudo adduser admin
sudo passwd admin
sudo usermod -aG wheel admin


ssh-copy-id admin@192.168.1.11

ssh-copy-id admin@192.168.1.12