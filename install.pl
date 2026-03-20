#!/usr/bin/perl
##############################################################
#   Install RadioCtl                                         #
#  Run this script from the command line  
# UPDATED 03/01/26 - Added ARCH Linux support 
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

#############################################
#### Libraries required for each distro    ##
#############################################
my %libraries = (
   ### Debian based distros (Mint/Ubuntu)
   'debian' => [
       'libgtk3-perl',
       'libdevice-serialport-perl',
       'libtext-csv-perl',
       'libautovivification-perl'
       ],
       
   ### Suse + Tumbleweed    
   'suse' => [   
      'perl-Gtk3',
      'perl-Device-SerialPort',
      'perl-Text-CSV',
      'perl-autovivification',
      'gdk-pixbuf-devel',
      'perl-Text-CSV_XS',
      'typelib-1_0-Gtk-3_0',
      'typelib-1_0-GdkPixdata-2_0',
      ],
   ### Arch Linux
   'arch' => [
      'perl-autovivification',
      'perl-device-serialport',
      'perl-text-csv',
      'perl-gtk3',
      ],
   ### Additional distros here  
   );
   
### Determine the distro based on OS-RELEASE
my $distro = '(n/a)';
my @os_release = ();
if (open INFILE,"/etc/os-release") {
   @os_release = <INFILE>;
   close INFILE;
   foreach my $rec (@os_release) {
      if ($rec =~ /^name/i) {  ### Name record
         chomp $rec;
         if ($rec =~ /mint/i) {$distro = 'debian';}
         elsif ($rec =~ /arch/i) {$distro = 'arch';}
         elsif ($rec =~ /ubun/i) {$distro = 'debian';}
         elsif ($rec =~ /suse/i) {$distro = 'suse';}
         else {
            ($distro) = $rec =~ /\"(.*?)\"/;
         }
         last;
      }
   }
}
else {print $Bold,"Could not read /etc/os-release to determine distro!$Eol";}
            

   
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
my $cmd = '';
if ($libraries{$distro}) {
   print "Installing perl libraries for $distro type distribution..\n";
   if ($distro =~ /debian/i) {
      system "sudo apt update";  ### debian systems need this first
   }
   foreach my $lib (@{$libraries{$distro}}) {
      my $cmd = '';
      if ($distro =~ /debian/i) {$cmd = "sudo apt-get -y install $lib";}
      elsif ($distro =~ /suse/i) {$cmd =  "sudo zypper -n install -l --force-resolution $lib";}
      elsif ($distro =~ /arch/i) {$cmd = "sudo pacman -S $lib --noconfirm";}
      ### Should not happen, but just in case
      else {
         print $Bold,"Command needed for $distro$Eol";
         last;
      }
      print "$cmd\n";
      `$cmd`;
      if ($?) {print "$Bold could not install library $lib$Eol";}
   }
   
   ### For Debian, need this after all installation
   if ($distro =~ /debian/i) {
      `sudo apt install --fix-broken`;
   }
}
else {
   print $Bold,"No automatic installation available for PERL libraries for $distro\n";
   print " Libraries will need to be installed manually!$Eol";
}
        

print "$Bold RadioCtl is now installed$Eol";

