#!/usr/bin/perl
##############################################################
#   Install RadioCtl                                         #
#  Run this script from the 
##############################################################
use strict;
my $Bold = "\e[1m";
my $Reset =  "\e[0m"; ## all attributes off
my $Eol = "$Reset\n";    ### reset color and add new line
my $errmsg = "$Bold\n Install was terminated before completion$Eol";


my @required = ("radioctl_ubuntu",
                "radioctl_tumbleweed",
                "radioctl_suse",
                "radiowrite_ubuntu",
                "radiowrite_tumbleweed",
                "radiowrite_suse",
                "radioctl.png",
                "radioctl.desktop",
                "radioctl.conf",
                );
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
foreach my $binary ('ubuntu','tumbleweed','suse') {
   my $fn = "radioctl_$binary";
   if (!-e $fn) {
      print "$Bold Could not locate $fn in the current directory!\n";
      print $errmsg;
      exit 999;
   }
  
   my $rc = `ldd $fn`;
   if ($rc =~ /not found/i) {next;}
   $source = $binary;
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
   system "sudo cp $fs /usr/local/bin";
   if ($?) {
       print "$Bold Unable to copy $fs!\n";
       print $errmsg;
       exit 999;
   }
   system "sudo chmod 751 /usr/local/bin/$fs";
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
print "$Bold RadioCtl is now installed$Eol";

