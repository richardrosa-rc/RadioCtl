#!/usr/bin/perl
##############################################################
#   Install RadioCtl                                         #
#  Run this script from the command line  
##############################################################
use strict;
my $Bold = "\e[1m";
my $Reset =  "\e[0m"; ## all attributes off
my $Eol = "$Reset\n";    ### reset color and add new line
my $errmsg = "$Bold\n Install was terminated before completion$Eol";

my $install_dir = '/usr/local/radioctl';
my $bin_dir = '/usr/local/bin';   ### Where symlinks will be placed
my @required = (
                "radioctl.png",
                "radioctl.desktop",
                "radioctl.conf",
                );
#### Libraries required for Debian distro
my @libs_debian = (
   'libgtk3-perl','libdevice-serialport-perl','libtext-csv-perl','libautovivification-perl'
   );
my @libs_suse = ( 
   'perl-Gtk3','perl-Device-SerialPort','perl-Text-CSV','perl-autovivification',
     'gdk-pixbuf-devel','perl-Text-CSV_XS','typelib-1_0-Gtk-3_0','typelib-1_0-GdkPixdata-2_0',
   );
my $distro = '';
my $rc = `grep -i suse /etc/os-release`;
### Not Suse
if ($?) {
   $distro = 'debian'; ### for now
}
else {$distro = 'suse';}
print "Distro found = $distro\n";


   
my $all_found = 1;    
foreach my $fs (@required) {
   if (-e $fs) {next;}
   else {
      print "$Bold Missing required install file $fs$Eol";
      $all_found = 0;
   }
}
if (!$all_found) {
   print "$Bold Please make the above files available before running this install again!";
   $Eol;
}

####################################################
#  Create a new directory for radioctl             #
####################################################
if (-d $install_dir) {
   print "$install_dir already exists. Will be updated\n";
}
else {
   my $cmd = "sudo mkdir -p $install_dir";
   print "Command=$cmd\n";
   system "$cmd";
}
if (!-d $install_dir) {
   print $Bold,"Cannot create $install_dir$Eol";
   exit 62;
}

system "sudo cp -auv *.pl $install_dir";
system "sudo chmod 755 $install_dir/*.pl";
### create symlinks for starting the program
system "sudo ln -s $install_dir/radioctl.pl $bin_dir";
### So the .PL is not needed 
system "sudo ln -s $install_dir/radioctl.pl $bin_dir/radioctl";

system "sudo ln -s $install_dir/radiowrite.pl $bin_dir";
system "sudo ln -s $install_dir/radiowrite.pl $bin_dir/radiowrite";


system "sudo cp -auv *.pm $install_dir";
system "sudo cp -auv *.odt $install_dir";
system "sudo cp radioctl.desktop /usr/share/applications";
if ($?) {
   ### This is NOT a show-stopper
   print "$Bold unable to copy radioctl.desktop\n";
   print "RadioCtl will not be available in the application menu!$Eol";  
}
else {
   system "sudo chown root:root /usr/share/applications/radioctl.desktop";
   system "sudo chmod 644  /usr/share/applications/radioctl.desktop";
}

system "sudo cp radioctl.png /usr/share/pixmaps";
if ($?) {
   ### Also not a big problem
   print "$Bold Could not copy radioctl.png\n";
   print " RadioCtl ICON will be missing$Eol";
}
else {
   system "sudo chown root:root /usr/share/pixmaps/radioctl.png";
   system "sudo chmod 644  /usr/share/pixmaps/radioctl.png";
}

### Finally the configuration file
if (-e ~/radioctl.conf/) {
   print "$Bold radioctl.conf already exists in your HOME directory.\n";
   print "  It will NOT be replaced$Eol";
}
else {
   system "cp radioctl.conf ~/";
}


################################################
#### now install the appropriate libraries     #
################################################
if ($distro =~ /debian/i) {
   system "sudo apt update";
   foreach my $lib (@libs_debian) {
      my $cmd = "sudo apt-get -y install $lib";
      print "$cmd\n";
      `$cmd`;
      if ($?) {print "$Bold could not install library $lib$Eol";}
   }
   `sudo apt install --fix-broken`;
}
else {
   foreach my $lib (@libs_suse) {
      my $cmd = "sudo zypper -n install -l --force-resolution $lib";
      print "$cmd\n";
      `$cmd`; 
      if ($?) {print "$Bold could not install library $lib$Eol";}
   }  
}

print "$Bold RadioCtl is now installed$Eol";

