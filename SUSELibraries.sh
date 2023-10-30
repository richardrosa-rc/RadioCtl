#!/bin/bash
### Install libraries needed for RadioCtl for OpenSuse
sudo zypper -n install -l --force-resolution perl-autovivification
sudo zypper -n install -l --force-resolution perl-Device-SerialPort
sudo zypper -n install -l --force-resolution perl-Text-CSV
sudo zypper -n install -l --force-resolution perl-Text-CSV_XS
sudo zypper -n install -l --force-resolution perl-Gtk3
sudo zypper -n install -l --force-resolution typelib-1_0-Gtk-3_0
sudo zypper -n install -l --force-resolution typelib-1_0-GdkPixdata-2_0
