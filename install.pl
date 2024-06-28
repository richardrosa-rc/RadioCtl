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


my @required = ("radioctl_ubuntu",
                "radioctl_tumbleweed",
                "radioctl_suse",
#               "radioctl_raspberrypi",
                "radiowrite_ubuntu",
                "radiowrite_tumbleweed",
                "radiowrite_suse",
#                "radiowrite_raspberrypi",
                "radioctl.png",
                "radioctl.desktop",
                "radioctl.conf",
                );
#### Libraries required for Debian distro
my @libs_debian = (
   'libgtk3-perl','libdevice-serialport-perl','libtext-csv-perl','libautovivification-perl'
   );
my @libs_suse = ( 
   'perl-Gtk3','perl-Device-SerialPort','perl-Text-CSV','perl-autovivification'
   );
my $distro = '';
my $rc = `grep -i suse /etc/osrelease`;
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
### need to determine the right binary to copy
my $source = '';
foreach my $binary ('raspberrypi','ubuntu','tumbleweed','suse',) {
   my $fn = "radioctl_$binary";
   if (!-e $fn) {
      print "$Bold Could not locate $fn in the current directory!\n";
      print $errmsg;
      exit 999;
   }
   
   ### Because the RaspberryPi is NOT  x64 arch
   ### Need a different way to detect
   if ($binary =~ /rasp/i) {
      ### Possibles:
      my $uname = `uname -a`;
      if ($uname =~ /raspberry/i) {
         $source = $binary;
         last;
      }
      next;
   
   }
   else {
      my $rc = `ldd $fn`;
      if ($rc =~ /not found/i) {next;}
      $source = $binary;
   }
   last;
}

if (!$source) {
   print "$Bold Could not find a compatible binary for this distribution\n";
   print "  Contact the authors for valid binaries or run from PERL source\n";
   print $errmsg;
   exit 999;
}

print "Determined compatible distro =>$source\n";


### copy the executables to the /usr/local/bin directory
foreach my $fn ('radioctl','radiowrite') {
   my $fs = $fn . '_' . $source;
   my $cmd = "sudo cp $fs /usr/local/bin/$fn";
   print "$cmd\n";
   system "sudo cp $fs /usr/local/bin/$fn";
   if ($?) {
       print "$Bold Unable to copy $fs!\n";
       print $errmsg;
       exit 999;
   }
   system "sudo chmod 755 /usr/local/bin/$fn";
}
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

