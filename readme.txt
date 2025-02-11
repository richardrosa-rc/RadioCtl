#### RadioCtl for Linux package

Control ICOM, Kenwood, and Uniden radios using the USB interface for these radios 
 and the Linux Operating System. 
 
This program allows you to:
  o Scan selected radio frequencies using any of the supported radios.
  o Record activity on those frequencies.
  o Search through ranges of frequencies for activity.
  o Update the memories in the radio.
  o Update SD cards for those radios that contain them.
  
 
This code has been developed and tested with the SUSE Linux distribution, but
 is also known to work with Ubuntu, Mint and Kali distros as well. 
 
For Ubuntu and Mint you MAY need to install additional libraries. 
 
Requirements: 
  o An installed or Live Linux distribution (SUSE, Ubuntu, Linux Mint, etc)
  o One of the supported radios:
  
    ICOM: R7000, IC-R30, IC-705, IC-7300, IC-8600 (untested)
    KENWOOD: TH-F6A
    UNIDEN:BCD325P2, SDS100, SDS200, BCD396T, BC895xlt
    AOR:AR-8000
  


NOTE:This is a BETA version. 
  There is a lot of Functionality left to be written,
  and a lot of bugs left to fix. 
  
  
  
  
Package contents:
   radioctl_{distro}  - The GUI program compiled for specific distributions.
   radiowrite_{distro}  - The command line program compiled for specific distributions. 
   radioctl.conf - Sample configuration file (to reside in your HOME directory)
   Conventional-Ulster_orange.csv - Sample RadioCtl format input file (Conventional Frequencies in the Hudson Valley of NY)
   NyComCo-EDACS.csv - Sample RadioCtl format input file (NYCOMCO EDACS system in the Hudson Valley of NY)
   Ham_Sample.csv - Sample Ham Radio and Shortwave frequencies.
   Radioctl-Operation.odt - Documentation for the program (in Open Document Format).
   Radioctl-DataFiles.odt - Documentation for the various file formats.
   install.pl - PERL script to install the program
   
Installation:
  Download from GIT via command:
      git clone https://github.com/richardrosa-rc/RadioCtl
  or download ZIP from web page
   
  If .zip, uncompress to the folder of your choice.
  Open terminal
  
  cd (location of download)
  perl install.pl 
  
 
To run (from terminal)
  radioctl.pl  (GUI)
    or
  radiowrite.pl (command line)   

  
Contact the authors at: richardrosa@yahoo.com for bug reports & suggestions.

ENJOY

Lydia & Richard Rosa
  
    
  
    
   
   

