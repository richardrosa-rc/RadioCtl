#!/usr/bin/perl -w
use strict;
my $author = 'Lydia And Richard';
my $office_prog = 'libreoffice --view';
use constant TRUE  => 1;
use constant FALSE => 0;
use autovivification;
no  autovivification;
use Scalar::Util qw(looks_like_number);
my $doit = TRUE;
use Device::SerialPort qw ( :PARAM :STAT 0.07 );
use Text::ParseWords;
use Text::CSV;
use File::Basename;
use Scalar::Util qw(looks_like_number);
use threads;
use threads::shared;
use Thread::Queue;
use Config;
$Config{useithreads} or die "Perl Thread Support missing!";
use Data::Dumper;
use Encode;
use Time::HiRes qw( utime usleep ualarm gettimeofday tv_interval );
use FindBin qw($RealBin);
use lib "$RealBin";
my $callpath = "$RealBin/";
print STDERR "callpath = $callpath\n";
use radioctl;
use scanner;
use uniden;
use icom;
use kenwood;
use aor8000;
use bearcat;
print "$Bold$Green RadioCtl$White Command Line Process$Red Rev=$White$Rev$Eol";
my %opt_dply = (
'dir' => "         $Bold$Cyan--dir$Yellow dir$Reset     Directory for output.        $Eol",
'baud' => "      $Bold$Cyan--baud$Yellow nnnnn$Reset     Baud rate Override for Selected Radio. $Eol",
'append' => "          $Bold$Cyan--append$Reset     Append data to existing file(s) instead of overwrite $Eol",
'dqkey' => "          $Bold$Cyan--dqkey$Reset      Assign department quickkeys (if missing)         $Eol",
'fspec' => "   $Bold$Cyan-f|--fspec$Yellow file$Reset     Full filespec (including path and ext) for output file.$Eol",
'gqkey' => "          $Bold$Cyan--gqkey$Reset      Assign group quickkeys (if missing)              $Eol",
'keyfmt' => "       $Bold$Cyan-k|--keyfmt$Reset     Store records as KEYWORD=VALUE fields            $Eol",
'nohdr' => "          $Bold$Cyan--nohdr$Reset      Don't generate header records.                   $Eol",
'noglobals' => "          $Bold$Cyan--noglobals$Reset  Don't include global data $Eol",
'nosearch' => "          $Bold$Cyan--nosearch$Reset   Don't include search data $Eol",
'notoneout' => "          $Bold$Cyan--notoneout$Reset  Don't include toneout data $Eol",
'nosys' => "          $Bold$Cyan--nosys$Reset      Don't include system data $Eol",
'notrunk' => "        $Bold$Cyan --notrunk$Reset     Don't included trunked systems.     $Eol" ,
'owrite' => "       $Bold$Cyan-o|--owrite$Reset     Overwrite any existing file(s) without prompt       $Eol",
'port' => "$Bold$Cyan--port$Yellow /dev/{name}$Reset     Port Override for Selected radio. $Eol",
'posfmt' => "       $Bold$Cyan-p|--posfmt$Reset     Store records as positional fields               $Eol",
'renum' => "        $Bold$Cyan--renum$Bold$Green x$Reset      Renumber the channels (non-dynamic radios only)$Eol" .
"                       $Bold$Green x$Reset is optional starting number (Defaults to$Yellow 0$Reset). $Eol",
'sort' => "       $Bold$Cyan-s|--sort$Reset       Sort FREQ records by frequency                 $Eol",
'sqkey' => "          $Bold$Cyan--sqkey$Reset      Assign system quickkey (if missing)    $Eol" ,
'tqkey' => "          $Bold$Cyan--tqkey$Reset      Assign site quickkey (if missing)    $Eol" ,
'hz' => "       $Bold$Cyan-h|--hz$Reset         Store frequencies in Hz (default is MHz)     \n" ,
);
my $help =
"    $Bold$Green RadioCtl$White Non-GUI write and read routines. v$Red$Rev             $Eol" .
"$Eol" .
"  Function: Read/Write various radios and data files. $Eol" .
"$Eol" .
"  syntax: $Bold radiowrite.pl $Green command $Yellow input(s) $Cyan {options}$Eol" .
"     An$Bold$Yellow input$Reset is a$Yellow filespec$Reset or a$Magenta radio name.$Eol" .
"     For$Yellow filespecs$Reset, most commands (unless otherwise indicated) allow for multiple inputs.$Eol" .
"    $Yellow Filenames$Reset with imbedded blanks need to be enclosed with quotes.      $Eol" .
"     RadioCtl data files must have$Bold *RadioCtl$Reset as the first record.        $Eol" .
"     Unless the file resides in the current directory, the full path of  each file is required.$Eol" .
"     Output files are usually placed in the default directory.             $Eol" .
"     This default is specified in the configuration file key$Bold tempdir$Eol" .
"        and can be overridden using the $Bold$Cyan--dir$Reset option.           $Eol" .
"     The default configuration file can be specified using the $Bold$Cyan--cfg$Reset option$Eol" .
"$Eol$Eol" .
"   valid commands:                                                           \n" .
"$Eol" .
"   $Bold$Green BLOCKS  $Reset   Generate block structure of a BCD radio. $Eol" .
"       Inputs:$Bold Name of radio to process. Must be a BCD type of radio.        $Eol".
"       Output:$Yellow radio_name$Bold$Yellow-blocks.txt$White in the default directory$Eol" .
"       Options:    \n" .
$opt_dply{'append'} .
$opt_dply{'baud'} .
$opt_dply{'fspec'} .
$opt_dply{'owrite'} .
$opt_dply{'port'} .
$opt_dply{'notrunk'} .
"          $Bold$Cyan--raw$Reset        Include raw responses from the radio                $Eol" .
"$Eol$Eol" .
"   $Bold$Green CLEAR   $Reset   Clear one or more memory channels in radio. $Eol" .
"       Inputs:$Bold Name of radio to process. Must be a non-dynamic memory type of radio.    $Eol".
"              $Bold First memory channel to clear. $Eol" .
"              $Bold Last memory channel to clear (Optional). If not specified, only one channel cleared.$Eol".
"       Output:$Yellow (none)$White Only messages.$Eol" .
"       Options:                                                              \n" .
$opt_dply{'baud'} .
$opt_dply{'port'} .
"$Eol$Eol" .
"   $Bold$Green CSV2ICOM $Reset   Convert RadioCtl .csv file(s) to ICOM SD card files.   $Eol" .
"       Inputs:$Bold RadioCtl File(s) to process.                             $Eol".
"       Output:$Bold$Yellow name/model-$Green". "xx$White.csv$White in the default directory $Eol" .
"              $Bold$Green xx$Reset is$Yellow 00$Reset to$Yellow 99$Reset " .
"based on the group number assigned to each$Bold freq$Reset record.$Eol" .
"              $Bold$Yellow model$Reset is$Bold$Magenta ICR30$Reset or$Bold$Magenta IC705$Eol" .
"       Options:                                                              \n" .
$opt_dply{'dir'} .
"          $Bold$Cyan--radio$Yellow mmm$Reset  output for radio name$Yellow mmm$Reset only $Eol".
"                       $Bold$Yellow mmm $Reset must be ICOM models $Bold IC705 or ICR30$Eol" .
"                        This option can be specified more than once.$Eol" .
"$Eol$Eol" .
"   $Bold$Green CSV2HPD $Reset   Convert RadioCtl csv file(s) to Uniden .HPD files (for SD Card). $Eol" .
"       Inputs:$Bold RadioCtl File(s) to process.                             $Eol" .
"       Output:$Bold$Yellow f_xxxxxxx.hpd$White and$Yellow f_list.cfg$White ($Yellow" . "xxxxxx$White is each input file name)$Eol" .
"       Options:                                                              \n" .
$opt_dply{'dir'} .
"          $Bold$Cyan--first$Yellow n$Reset    First index for hpd filename. 'n' must be 0-999999. $Eol" .
"          $Bold$Cyan--force$Reset      Force HPD file renumber                $Eol" .
"          $Bold$Cyan--radio$Yellow mmm$Reset  use radio name$Yellow mmm$Reset for output determination $Eol".
"$Eol$Eol" .
"   $Bold$Green FETCH $Reset   Extract all a radio's memories and write to a RadioCtl .csv file.\n" .
"       Input:$Bold Name of radio to read.                             $Eol" .
"                      $Bold Uniden SDS radios cannot run this command $Eol" .
"       Output:$Bold {radio_name}.csv' saved in the default directory.  $Eol" .
"       Options:                                                        \n" .
$opt_dply{'append'} .
"          $Bold$Cyan--count$Yellow n$Reset    Only process 'n' systems or channels. $Eol" .
"                          For Uniden radios, this will be systems.      $Eol" .
"                          For all other radios, this will be channels.  $Eol" .
$opt_dply{'baud'} .
"          $Bold$Cyan--count$Yellow n$Reset    Count of systems or channels to read.$Eol" .
"          $Bold$Cyan--first$Yellow n$Reset    First system or channel Number to read.$Eol" .
"          $Bold$Cyan--force$Reset      Force quickkey re-assignment                     $Eol" .
$opt_dply{'fspec'} .
$opt_dply{'gqkey'} .
$opt_dply{'keyfmt'} .
"          $Bold$Cyan--last$Yellow n$Reset     Last system or channel Number to read.$Eol" .
$opt_dply{'noglobals'} .
$opt_dply{'nohdr'} .
$opt_dply{'nosearch'} .
$opt_dply{'nosys'} .
$opt_dply{'notoneout'} .
$opt_dply{'notrunk'} .
$opt_dply{'owrite'} .
"        $Bold$Cyan--port$Yellow device$Reset  Specify serial or USB port (not normally needed) $Eol" .
$opt_dply{'posfmt'} .
$opt_dply{'renum'} .
"                        If$Bold$Green x$Reset is$Yellow -1$Reset, all channel numbers will be turned off. $Eol" .
"          $Bold$Cyan--skip$Reset       Skip over empty, non-TGID channels (Frequency = 0). $Eol" .
$opt_dply{'sort'} .
$opt_dply{'sqkey'} .
$opt_dply{'tqkey'} .
$opt_dply{'hz'} .
"$Eol$Eol" .
"   $Bold$Green HPD2CSV $Reset   Convert Uniden .hpd & .cfg files to RadioCtl .csv files $Eol" .
"       Input:$Bold Single .hpd file to read.                               $Eol" .
"       Output:$Bold {input_filename}.csv saved in the default directory.          $Eol" .
"       Options:                                                              \n" .
$opt_dply{'append'} .
$opt_dply{'dir'} .
$opt_dply{'dqkey'} .
$opt_dply{'fspec'} .
"          $Bold$Cyan--force$Reset      Force quickkey re-assignment                     $Eol" .
$opt_dply{'gqkey'} .
$opt_dply{'keyfmt'} .
"          $Bold$Cyan--lat$Yellow ord$Reset    Restrict records to this latitude +/- radius      $Eol" .
"          $Bold$Cyan--lon$Yellow ord$Reset    Restrict records to this longitude +/- radius     $Eol" .
"          $Bold$Cyan--loc$Yellow name$Reset   Restrict records to this location +/- radius       $Eol" .
"                           (location$Bold$Yellow name$Reset MUST be defined in radioctl.conf)   $Eol" .
$opt_dply{'nohdr'} .
$opt_dply{'notrunk'} .
$opt_dply{'owrite'} .
$opt_dply{'posfmt'} .
"          $Bold$Cyan--radius$Yellow n$Reset   Radius in miles for lat/lon/loc. Default is 25. $Eol" .
$opt_dply{'sort'} .
$opt_dply{'sqkey'} .
$opt_dply{'tqkey'} .
$opt_dply{'hz'} .
"$Eol$Eol" .
"   $Bold$Green RADIOS$Reset    Display the names of currently defined radios$Eol" .
"       Inputs:$Bold (none)                                                   $Eol" .
"       Output:$Bold Display of available radio names.                        $Eol" .
"       Options: (none)                                                       \n" .
"$Eol$Eol" .
"   $Bold$Green REWRITE$Reset    Read RadioCtl .csv File(s) and generate new output file(s)$Eol" .
"       Inputs:$Bold RadioCtl Files(s) to read.                                $Eol" .
"       Output:$Bold 'rewrite.csv' (or multiple files) in the default directory $Eol" .
"       Options:                                                              \n" .
$opt_dply{'append'} .
$opt_dply{'dir'} .
$opt_dply{'dqkey'} .
$opt_dply{'fspec'} .
"          $Bold$Cyan--force$Reset      Force quickkey re-assignment                     $Eol" .
$opt_dply{'gqkey'} .
$opt_dply{'keyfmt'} .
"          $Bold$Cyan--multi$Reset      Output to individual files rather than a single. $Eol" .
$opt_dply{'nohdr'} .
$opt_dply{'owrite'} .
$opt_dply{'posfmt'} .
$opt_dply{'renum'} .
"                        If$Bold$Green x$Reset is$Yellow -1$Reset, all channel numbers will be turned off. $Eol" .
$opt_dply{'sort'} .
$opt_dply{'sqkey'} .
$opt_dply{'tqkey'} .
$opt_dply{'hz'} .
"$Eol$Eol" .
"  $Bold$Green STORE $Reset  Read one or more RadioCtl .csv file(s) and store the data   \n" .
"               in the selected radio's memory.                               \n" .
"       Inputs:$Bold Name of radio to write (must be specified first)          \n" .
"                   Filespec(s) of .csv to read.                              $Eol" .
"       Output:$Yellow (none)$White Only messages.$Eol" .
"       Options:  \n" .
$opt_dply{'baud'} .
"      $Bold$Cyan--count$Green n$Reset        Store only$Bold$Green n$Reset channels (non-dynamic radios only) $Eol" .
"      $Bold$Cyan--erase$Reset          Clear any existing systems/channels. (dynamic radios only)  $Eol" .
"      $Bold$Cyan--noglobals$Reset      Don't store any Global records in the radio.            $Eol" .
"      $Bold$Cyan--nosearch$Reset       Don't store any SEARCH records in the radio (Uniden Only)    $Eol" .
"      $Bold$Cyan--nossys$Reset         Don't store any SYSTEM records in the radio                  $Eol" .
"      $Bold$Cyan--notoneout$Reset      Don't store TONEOUT records in the radio (Uniden Only)    $Eol" .
$opt_dply{'port'} .
$opt_dply{'renum'} .
"$Eol";
my %radiodb = ();
my %out = ();
my %in = ();
my %parmref = ('out' => \%out,'in' => \%in,'database' => \%radiodb, 'def' =>\%radio_def);
my %radio_parms = ();
my %bench = ();
my %radmaxno = ();
foreach my $key (keys %structure) {$radmaxno{$key} = 0;}
my %create = ('sin' => 'CSY',
'sif' => 'AST',
'tfq' => 'ACC',
'cin' => 'ACC',
'gin' => 'AGC',
'tin' => 'ACT',
);
my %changekey = ('service' => 1,
'qkey'    => 1,
'mot_type' => 1,
'edacs_type' => 1,
'frequency' => 1,
);
my %new = ();
my $debug_addr = '9000';
my $sitecnt = 0;
my $freqcnt = 0;
my $tfqcnt = 0;
my $grpcnt = 0;
my $gidcnt = 0;
my $sgidcnt = 0;
my $altport = '';
my $altbaud = '';
my $append = FALSE;
my $dqkey = FALSE;
my $firstnum   = 0;
my $force = FALSE;
my $freqsort = FALSE;
my %gps_parms = (
'lat' => 0,
'lon' => 0,
'radius' => 25,
);
my $gqkey = FALSE;
my $keyformat = FALSE;
my $lastnum = 9999;
my $loc =  '';
my $nohdr = FALSE;
my $notrunk = FALSE;
my $multi = FALSE;
my $overwrite = FALSE;
my $posformat = FALSE;
my @radio = ();
my $raw = FALSE;
my $renum = '';
my $showhz  = FALSE;
my $skip = FALSE;
my $sqkey = FALSE;
my $tqkey = FALSE;
my $User_conf = '';
my $User_count = '';
my $User_dir  = '';
my $User_fspec = '';
my $default_dir = $RCSettings{'tmpdir'};
my $erase = FALSE;
my $nodie = FALSE;
my $noglobals = FALSE;
my $nosys = FALSE;
my $notoneout = FALSE;
my $nosearch = FALSE;
my $testing = FALSE;
my $testfrq = 0;
my $user_filename = '';
my $dupcheck = FALSE;
$Options{'append'}    = \$append;
$Options{'baud'}      = \$altbaud;
$Options{'count=n'}   = \$User_count;
$Options{'d1'}        = \$Debug1;
$Options{'d2'}        = \$Debug2;
$Options{'d3'}        = \$Debug3;
$Options{'dir=s'}     = \$User_dir;
$Options{'dqkey'}     = \$dqkey;
$Options{'erase'}     = \$erase;
$Options{'f|fspec=s'} = \$User_fspec;
$Options{'first=n'}   = \$firstnum;
$Options{'force'}     = \$force;
$Options{'noglobals'} = \$noglobals;
$Options{'gqkey'}     = \$gqkey;
$Options{'h|help'}    = \&help;
$Options{'multi'}     = \$multi;
$Options{'k|keyfmt'}  = \$keyformat;
$Options{'last=n'}    = \$lastnum;
$Options{'lat=s'}     = \$gps_parms{'lat'};
$Options{'loc=s'}     = \$loc;
$Options{'lon=s'}     = \$gps_parms{'lon'};
$Options{'nodie'}     = \$nodie;
$Options{'notrunk'}   = \$notrunk;
$Options{'nosys'}     = \$nosys;
$Options{'nosearch'}  = \$nosearch;
$Options{'notoneout'} = \$notoneout;
$Options{'nohdr'}     = \$nohdr;
$Options{'o|owrite'}  = \$overwrite;
$Options{'p|posfmt'}  = \$posformat;
$Options{'port=s'}    = \$altport;
$Options{'radio=s'}   = \@radio;
$Options{'radius=n'}  = \$gps_parms{'radius'};
$Options{'raw'}       = \$raw;
$Options{'r|renum:i'} = \$renum;
$Options{'skip'}      = \$skip;
$Options{'s|sort'}    = \$freqsort;
$Options{'sqkey'}     = \$sqkey;
$Options{'testfrq=s'} = \$testfrq;
$Options{'test'}      = \$testing;
$Options{'tqkey'}     = \$tqkey;
$Options{'cfg=s'}     = \$User_conf;
$Options{'z|hz'}      = \$showhz;
Parms_Parse();
my $cmd = shift @ARGV;
if (!$cmd) {$cmd = '?';}
$cmd = lc($cmd);
if (ReadProfile($User_conf)) {exit 1};
if ($altport) {
$altport = Strip($altport);
if (! -e $altport) {LogIt(988,"Serial/USB port $altport does NOT exist!");}
}
if ($altbaud) {
$altbaud = Strip($altbaud);
if (!$baudrates{$altbaud}) {
LogIt(983,"$altbaud is NOT a valid baud rate for RadioCtl!");
}
}
foreach my $name (@radio) {
select_radio($name);
}
if ($User_dir) {
if (DirExist($User_dir,TRUE)) {
LogIt(1006,"Unable to locate or create directory $User_dir for output file");
}
}
if ($User_fspec) {
my ($filename,$path,$ext) = fileparse($User_fspec,qr/\.[^.]*/);
if (DirExist($path,TRUE)) {
LogIt(1023,"Unable to locate or create directory $path for output file");
}
}
if ($cmd eq '?') {help();}
elsif ($cmd =~ /help/i) {help();}
elsif ($cmd =~ /^bl/i)    {  
my $radiosel = shift @ARGV;
if (!$radiosel) {LogIt(1053,"No radio for command $cmd given!");}
$bench{'start_block'} = time();
select_radio(lc($radiosel));
my $protocol = $radio_def{'protocol'};
my $model = $radio_def{'model'};
if (($protocol !~ /uniden/i) or ($model !~ /^bcd/i)) {
LogIt(1078,"This command is only valid for Uniden BCD radios!");
}
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
my $routine = $Radio_Routine{$protocol};
print "Getting radio information...\n";
$parmref{'database'} = \%radiodb;
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
%radiodb = ();
my @outrecs = ();
%out = ();
%in = ('notrunk' => $notrunk);
my $rc = &$routine('getinfo',\%parmref);
push @outrecs,"*** Current structure for $radiosel on " . Time_Format(time()) . "****\n" .
"** Model:$out{'model'}  (Battery status:$out{'bat_level'}v) \n" .
"** Total SYSTEMs:$out{'sys_count'}\n" .
"** Total SITEs:$out{'site_count'}\n";
my $out_tpos = push @outrecs,"";
push @outrecs,"** Total FREQuencies:$out{'chan_count'}\n\n" .
"** Memory Used:$out{'mem_used'}" . '%'.  "\n" .
"** Memory Blocks Free:$out{'mem_free'}\n" ;
if ($raw and $out{'_raw'}) {push @outrecs,"raw=>$out{'_raw'}\n";}
$rc = &$routine('getmem',\%parmref);
my %system_quickkeys = ();
if ($radiodb{'syskey'}[1]{'syskeys'}) {
push @outrecs, "System Quick-Keys:";
my @allkeys = split "",$radiodb{'syskey'}[1]{'syskeys'};
my $count = 0;
foreach my $key (0..99) {
if (looks_like_number($allkeys[$key])) {
my $value = 'Off';
if ($allkeys[$key]) {$value = 'On ';}
push @outrecs," " . sprintf("%02.2u",$key) . "=>$value";
$count++;
if ($count > 10) {
push @outrecs,"\n                  ";
$count = 0;
}
$system_quickkeys{$key} = $value;
}
}
push @outrecs,"\n";
if ($raw and $radiodb{'syskey'}[1]{'_raw'}) {
push @outrecs," raw=>$radiodb{'syskey'}[1]{'_raw'}\n";
}
}
else {
if ($Verbose) {
print "No syskeys were found=>",Dumper($radiodb{'syskey'}),"\n";
}
}
my $syscount = 0;
my $totalgroups = 0;
push @outrecs, "\n*** Record Format:  Block:Database_number:Block_addr qkey=>nn Service (Other info)\n";
foreach my $sysrec (@{$radiodb{'system'}}) {
my $sysno = $sysrec->{'index'};
if (!$sysno) {next;}
my $sysfmt = sprintf("%3.3u",$sysno);
my $sqkey = $sysrec->{'qkey'};
if (looks_like_number($sqkey) and ($sqkey >= 0)) {
$sqkey = sprintf("%02.2u",$sqkey) . ":$system_quickkeys{$sqkey}";
}
else {$sqkey = 'Off';}
my $out = "\nSYSTEM $sysfmt:" .
sprintf("%5.5u",$sysrec->{'block_addr'}) . "  " .
sprintf("%-16.16s",$sysrec->{'service'}) .
" TYPE=>$sysrec->{'systemtype'} " .
" QKEY=>$sqkey" .
"\n";
push @outrecs,$out;
$syscount++;
if ($raw and $sysrec->{'_raw'}) {push @outrecs,"   raw=>$sysrec->{'_raw'}\n";}
my $sitecount = 0;
my $freqcount = 0;
my $groupcount = 0;
my $site_qkeys = '';
my $group_qkeys = '';
my $site_qkey_count = 0;
my $out_spos = push @outrecs,$site_qkeys;
my $out_gpos = push @outrecs,$group_qkeys;
my %group_qkstat = ();
foreach my $qksrec (@{$radiodb{'grpkey'}}) {
if (!$qksrec->{'index'}) {next;}
if ($qksrec->{'sysno'} != $sysno) {next;}
push @outrecs,"  Group quickkey status=>$qksrec->{'grpkeys'}\n";
my %stat = %{$qksrec->{'grpkey'}};
foreach my $key (keys %stat) {
if ($stat{$key}) {$group_qkstat{$key} = 'On ';}
else {$group_qkstat{$key} = 'Off';}
}
last;
}
foreach my $siterec (@{$radiodb{'site'}}) {
my $siteno = $siterec->{'index'};
if (!$siteno) {next;}
if ($siterec->{'sysno'} != $sysno) {next;}
my $sitefmt = sprintf("%3.3u",$siteno);
$sitecount++;
my $tfreqcount = 0;
my $site_qk = $siterec->{'qkey'};
if (looks_like_number($site_qk) and ($site_qk >= 0)) {
$site_qk = sprintf("%02.2u",$site_qk);
}
else {$site_qk = 'Off';}
$site_qkeys = $site_qkeys . "SITE-$sitefmt:$site_qk ";
$site_qkey_count++;
if ($site_qkey_count > 10) {
$site_qkeys = "$site_qkeys\n              ";
$site_qkey_count = 0;
}
my $out = "   SITE:$sitefmt:" .
sprintf("%5.5u",$siterec->{'block_addr'}) . "  " .
" qkey=>$site_qk " .
sprintf("%-16.16s",$siterec->{'service'}) . "\n";
push @outrecs,$out;
if ($raw and $siterec->{'_raw'}) {
push @outrecs,"             raw=>$sysrec->{'_raw'}\n";
}
foreach my $tfrec (@{$radiodb{'tfreq'}}) {
my $tfno = $tfrec->{'index'};
if (!$tfno) {next;}
if ($tfrec->{'siteno'} != $siteno) {next;}
my $out = "      TFREQ:" . sprintf("%3.3u",$tfno) . ':' .
sprintf("%5.5u",$tfrec->{'block_addr'}) .
"   " . rc_to_freq($tfrec->{'frequency'}) . "mhz \n";
push @outrecs,$out;
if ($raw and $tfrec->{'_raw'}) {
push @outrecs,"                 raw=>$tfrec->{'_raw'}\n";
}
$freqcount++;
$tfreqcount++;
}
push @outrecs,"  --------$tfreqcount total TFREQs for site $siteno\n"
}### For Each Site
if ($sitecount) {
$outrecs[$out_spos-1] = "Total SITEs for SYSTEM $sysfmt=$sitecount\n" .
"SITE Quick-Keys=>$site_qkeys\n";
}
foreach my $grprec (@{$radiodb{'group'}}) {
my $grpno = $grprec->{'index'};
if (!$grpno) {next;}
if ($grprec->{'sysno'} != $sysno) {next;}
my $grpfmt = sprintf("%03.3u",$grpno);
$groupcount++;
$totalgroups++;
my $qkey = $grprec->{'qkey'};
if (looks_like_number($qkey) and $qkey >= 0) {
my $status = $group_qkstat{$qkey};
$qkey = sprintf("%02u",$qkey);
$group_qkeys = "$group_qkeys GROUP-$grpfmt:$qkey";
$qkey = "$qkey ($status)";
}
else {$qkey = 'Off';}
my $out = "   GROUP:$grpfmt:" .
sprintf("%5.5u",$grprec->{'block_addr'}) . "  " .
sprintf("%-16.16s",$grprec->{'service'}) .
" qkey=>$qkey " .
"\n";
push @outrecs,$out;
if ($raw and $grprec->{'_raw'}) {
push @outrecs,"             raw=>$grprec->{'_raw'}\n";
}
my $frgrpcount = 0;
my $out_fpos = push @outrecs,'';
foreach my $frqrec (@{$radiodb{'freq'}}) {
my $frqno = $frqrec->{'index'};
if (!$frqno) {next;}
if ($frqrec->{'groupno'} != $grpno) {next;}
my $freq = '';
if ($frqrec->{'tgid_valid'}) {$freq = "TGID=$frqrec->{'tgid'}";}
else {$freq = rc_to_freq($frqrec->{'frequency'}) . "mhz";}
my $out = "      FREQ:" . sprintf("%3.3u",$frqno) . ':' .
sprintf("%5.5u",$frqrec->{'block_addr'}) . "  " .
sprintf("%-16.16s",$frqrec->{'service'}) .
" ($freq) " .
"\n";
push @outrecs,$out;
if ($raw and $frqrec->{'_raw'}) {
push @outrecs,"                   raw=>$frqrec->{'_raw'}\n";
}
$frgrpcount++;
$freqcount++;
}
$outrecs[$out_fpos-1] = "   Total FREQs for GROUP $grpfmt=$frgrpcount\n";
}### For each group
$outrecs[$out_gpos-1] = "Total GROUPs for SYSTEM $sysfmt=$groupcount\n" .
"GROUP Quick-Keys=>$group_qkeys\n"  .
"Total FREQs for System $sysfmt=$freqcount\n\n";
}### For each system
$outrecs[$out_tpos-1] = "** Total Groups:$totalgroups\n";
my $outfile = set_filespec("$radiosel-blocks.txt",'logdir',\%radio_def);
my $msg = "Created $outfile";
my $outspec = ">$outfile";
if (-e $outfile) {
if ($append) {
LogIt(1,"Data will be appended to existing file $Yellow$outfile");
$msg = "Appended to $outfile";
$outspec = ">>$outfile";
}
else {
LogIt(1,"existing file $Yellow$outfile$White will be overwritten.");
if (!$overwrite) {
print "   OK (Y/N)=>";
my $answer = <STDIN>;
chomp($answer);
print STDERR "$Eol";
if (uc(substr($answer,0,1)) ne 'Y') {
$skip = TRUE;
}
}
$msg = "Recreated $outfile";
$outspec = ">$outfile";
}
}
else {
$outspec = ">$outfile";
}
if ($skip) {
LogIt(0,"$Bold Output file generation was bypassed!");
}
else {
if (open OUTFILE,"$outspec") {
print OUTFILE @outrecs;
close OUTFILE;
print $Bold,$msg,$Eol;
}
else {LogIt(1,"Could not create $outfile");}
}
$bench{'end_block'}  = time();
BenchMark(\%bench);
exit 0;
}### Blocks command
elsif ($cmd =~ /^cl/i) {  
$bench{'start_clear'} = time();
my $radiosel = shift @ARGV;
my $start = shift @ARGV;
my $stop = $start;
if (scalar @ARGV) {$stop = shift @ARGV;}
if (!$radiosel) {LogIt(1701,"No radio for command $cmd given!");}
if (!defined $start) {LogIt(1705,"Starting channel is required");}
if ((!looks_like_number($start)) or ($start < 0)) {
LogIt(1707,"Starting channel must be a positive number!");
}
if ((!defined $stop) or (!looks_like_number($stop)) or ($stop < 0)) {
LogIt(1710,"Ending channel must be a positive number!");
}
if ($stop < $start) {
LogIt(1713,"Ending channel must be greater Than or equal to Starting!");
}
select_radio(lc($radiosel));
if (!$radio_def{'protocol'}) {
LogIt(1726,"$Red$radiosel$White is not defined in the profile!");
}
my $protocol = $radio_def{'protocol'};
if ($protocol =~ /uniden/i) {
LogIt(1768,"$Green$cmd$White is not valid for Uniden dynamic radios!");
}
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
my $routine = $Radio_Routine{$protocol};
my $rc = &$routine('init',\%parmref);
my $origin = $radio_def{'origin'};
if (!$origin) {$origin = 0;}
if ($start < $origin) {
LogIt(1784,"$Red$start$White is less than origin ($Green$origin$White)");
}
elsif ($stop > $radio_def{'maxchan'}) {
LogIt(1784,"$Red$stop$White is greater than maxchan ($radio_def{'maxchan'})");
}
%radiodb = ();
my %sysrec = ('service' => 'erase');
my $sysndx = add_a_record(\%radiodb,'system',\%sysrec);
my %grouprec = ('sysno' => $sysndx);
my $groupndx = add_a_record(\%radiodb,'group',\%grouprec);
foreach my $chan ($start .. $stop) {
my %freqrec = ('groupno'=>$groupndx,'frequency' => 0, 'channel' => $chan);
add_a_record(\%radiodb,'freq',\%freqrec);
}
LogIt(0,$Bold,"Attempting clear of channels $Green$start$White " .
"thru $Green$stop$White on radio $Yellow$radiosel");
$rc = &$routine('setmem',\%parmref);
if ($rc) {
if ($rc eq $NotForModel) {
LogIt(1805,"$cmd is not valid for $Yellow" . uc($radiosel));
}
LogIt(1,"$cmd l812:$Bold  failed. return code: $rc");
}
else {
LogIt(0,"Selected channels should be cleared.");
}
$bench{'end_clear'} = time();
BenchMark(\%bench);
exit $rc;
}
elsif ($cmd =~ /^csv2i/i) {
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {LogIt(0,"found $filecount  files to read" );}
else {LogIt(1073,"No files found to read!");}
$User_fspec = '';
my %database = ();
foreach my $fs (@filelist) {
if (!-e $fs) {
LogIt(1,"Unable to locate input file $fs!");
next;
}
my $rc = read_radioctl(\%database,$fs);
if ($rc) {
LogIt(1,"Unable to read input file $fs!");
next;
}
}
my $syscount = scalar @{$database{'system'}};
if ($syscount > 1) {
print "Found ",$syscount -1," possible systems for data generation\n";
}
else {LogIt(1098,"No systems were found to process!");}
my %sd_records = ();
my $rc = icom_sdcard(\%database,\%sd_records);
if (!scalar @radio) {@radio = keys %All_Radios;}
my $radiocount = 0;
foreach my $name (@radio) {
select_radio(lc($name));
if ($radio_def{'protocol'} !~ /icom/i) {next;}
my $model = uc($radio_def{'model'});
if (!defined $sd_records{$model}[0]) {
print "No output generated for $name (model $model does not support SD Cards$Eol";
next;
}
$radiocount++;
my @allout = @{$sd_records{$model}};
my $outfile = set_filespec("$name/$model-all.csv",'sddir',\%radio_def);
my ($filename,$path,$ext) = fileparse($outfile,qr/\.[^.]*/);
if (DirExist($path,TRUE)) {
LogIt(1647,"Unable to locate or create directory $path for output file");
}
print $Bold,"Generating $Yellow$outfile$Eol";
if (open OUTFILE,">$outfile") {
print OUTFILE @allout;
close OUTFILE;
}
else {
LogIt(1,"Could not create $outfile! error=$!");
}
my %groupnos = ();
my $header = $allout[0];
foreach my $rec (@allout) {
my ($gn,$rest) = split /\,/,$rec;
if (looks_like_number($gn)) {
push @{$groupnos{$gn}},$rec;
}
}
my @groups = keys %groupnos;
my $groupcnt = scalar @groups;
if ($groupcnt) {
print $Bold,"Generating $groupcnt individual groups in directory $Yellow$path$Eol";
foreach my $group (keys %groupnos) {
my $outfile = set_filespec("$name/$model-$group.csv",'sddir',\%radio_def);
if (open OUTFILE,">$outfile") {
print OUTFILE $header;
print OUTFILE @{$groupnos{$group}};
close OUTFILE;
}
else {
LogIt(1,"Could not create $outfile!");
}
}## For each of the groups found
}### Groups found
else {
LogIt(1,"No groups were found for $name!");
}
}### For each radio found
if ($radiocount) {
LogIt(0,"$Bold Generated SD Card data for $Green$radiocount$White radios.");
}
else {
LogIt(1,"No ICOM radios with SD card support was found!");
}
exit $GoodCode;
}
elsif ($cmd =~ /^csv2h/) {
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {LogIt(0,"found $filecount  files to process");}
else {LogIt(1923,"No files found to process!");}
$User_fspec = '';
my %database = ();
foreach my $fs (@filelist) {
if (!-e $fs) {
LogIt(1,"Unable to locate input file $fs!");
next;
}
my $rc = read_radioctl(\%database,$fs);
if ($rc) {
LogIt(1,"Unable to read input file $fs!");
next;
}
}
my $syscount = scalar @{$database{'system'}};
if ($syscount > 1) {
print "Found ",$syscount -1," possible systems for data generation\n";
}
else {LogIt(1947,"No systems were found to process!");}
my $defref = '';
if (scalar @radio) {
my $name = lc($radio[0]);
select_radio($name);
$defref = \%radio_def;
}
my $outfile = set_filespec('/BCDx36HP/f_000000.hpd','sddir',$defref);
my ($filename,$path,$ext) = fileparse($outfile,qr/\.[^.]*/);
if (DirExist($path,TRUE)) {
LogIt(1979,"Unable to create directory $path");
}
my $flist_file = "$path/f_list.cfg";
if (-e "$path/favorites/f_list.cfg") {
$flist_file = "$path/favorites/f_list.cfg";
}
my @flistrecs = ();
if (-e $flist_file) {
if (open INFILE,"$flist_file") {
@flistrecs = <INFILE>;
close INFILE;
}
else {
LogIt(1,"Could not open $flist_file for reading!");
}
}
else {LogIt(1,"RADIOWRITE l2003:Existing Flist:$Yellow$flist_file$White was not found!\n" .
"   A new one MAY be created.");}
my $profile_file = "$path/profile.cfg";
my @profrecs = ();
my $config = \@profrecs;
if (-e $profile_file) {
if (open INFILE,"$profile_file") {
@profrecs = <INFILE>;
close INFILE;
}
else {
LogIt(1,"Could not open $profile_file for reading!");
}
}
else {
LogIt(1,"RADIOWRITE l1997:Existing profile:$Yellow$flist_file$White was not found!\n" .
"   No updates will be made.");
$config = 0;
}
my @sdcard = ();
my %parms = ('sdcard' => \@sdcard,
'dbase'  => \%database,
'flist'  => \@flistrecs,
'config' => $config,
);
my $rc = uniden_sdcard(\%parms);
my $count = scalar @sdcard;
print "Generating $count files on $path..\n";
foreach my $rec (@sdcard) {
my $fn = $rec->{'filename'};
my $fspec = "$path/$fn";
if (-e $fspec) {
my $backup = $fspec . "_backup";
`mv $fspec $backup`;
}
if (open OUTFILE, ">$fspec") {
print OUTFILE @{$rec->{'records'}};
close OUTFILE;
print "RadioWrite l2089:Created Favorites file  $Bold$Yellow$fspec$Eol";
}
else {
LogIt(20931,"RadioWrite l2092:Could not open file $fspec for output! Error=$!");
}
}
if (-e $flist_file) {
my $backup = $flist_file . "_backup";
`mv $flist_file $backup`;
}
if (scalar @flistrecs) {
if (open OUTFILE,">$flist_file") {
print OUTFILE @flistrecs;
close OUTFILE;
print "RadioWrite l2112:Created $Bold$Yellow$flist_file$Eol";
}
else {
LogIt(2116,"RadioWrite l2115:Could not create $flist_file! Error=$!");
}
}
print $Bold,"All SDCard files created on $path$Eol";
exit $GoodCode;
}
elsif ($cmd =~ /^fe/i) { 
my $radioname = shift @ARGV;
if (!$radioname) {LogIt(2257,"FETCH:No radio specified!");}
$bench{'start_read'} = time();
if ($firstnum <= 1) {$firstnum = 1;}
my $radiosel = lc($radioname);
select_radio($radiosel);
my $protocol = $radio_def{'protocol'};
my $routine = $Radio_Routine{$protocol};
if (!$routine) {LogIt(2560,"FETCH:Radio routine not set for protocol $protocol");}
if (AutoBaud(\%parmref)) {
LogIt(2289,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
$parmref{'database'} = \%radiodb;
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
%in = ('noport' => FALSE, 'nobaud' => FALSE);
if (($lastnum > 0) and ($firstnum > $lastnum)) {
LogIt(1,"$firstnum is greater than $lastnum. Swapping...");
my $temp = $firstnum;
$firstnum = $lastnum;
$lastnum = $temp;
}
%radiodb = ();
if (&$routine('init',\%parmref) ) {
LogIt(2336,"FETCH:Failed to initialize radio: $radiosel ($protocol)");
}
my $model = $radio_def{'model'};
if (($protocol =~ /uniden/i) and ($model =~ /^sds/i)) {
LogIt(2346,"Cannot run this command for Uniden model $model");
}
my $count = 99999;
if ($User_count and ($User_count > 0)) {$count = $User_count;}
my %options = (
'count'     => $count,
'skip'      => FALSE,
'firstchan' => $firstnum,
'lastchan'  => $lastnum,
'firstsys'  => $firstnum,
'lastsys'   => $lastnum,
'notrunk'   => $notrunk,
);
if (!$skip) {$options{'noskip'} = TRUE;}
$parmref{'options'} = \%options;
if (!$nosys)  {
my $rc = &$routine('getmem',\%parmref);
if ($rc) {
LogIt(1,"FETCH l2340:$Bold GETMEM routine from radio returned code $rc");
}
}
if ($nosearch) {
print "Bypassing fetch of search records due to option$Eol";
}
else {
print "Fetching SEARCH data...\n";
my $rc = &$routine('getsrch',\%parmref);
if ($rc) {
LogIt(0,"FETCH l2383:$Bold GETSRCH routine from radio returned code $rc");
}
}
if ($noglobals) {
print "Bypassing fetch of globals due to option$Eol";
}
else {
my $rc = &$routine('getglob',\%parmref);
if ($rc) {
LogIt(1,"FETCH l2396:$Bold GETGLOB routine from radio returned code $rc");
}
}
if ($protocol =~ /uniden/i) {
if ($notoneout) {
print "Bypassing fetch of tone-out records due to option$Eol";
}
else {
my $rc = &$routine('gettone',\%parmref);
if ($rc) {
LogIt(1,"FETCH 24010:$Bold GETTONE routine from radio returned code $rc");
}
}
}### Protocl is UNIDEN
my %tagrec = ('system' => "All memory data from $radiosel");
add_a_record(\%radiodb,"tag",\%tagrec,FALSE);
my $found = FALSE;
foreach my $rectype (keys %radiodb) {
if (defined $radiodb{$rectype}[1]{'index'}) {
$found = TRUE;
last;
}
}
if ($found) {
LogIt(0,"All input records processed. Generating output file $user_filename");
update_qkey(\%radiodb);
my $outfile = set_filespec("$radioname.csv",'tmpdir',\%radio_def);
write_data($outfile,\%radiodb);
}
else {LogIt(1,"No data was processed from radio! No file created.");}
$bench{'end_read'}  = time();
BenchMark(\%bench);
exit $GoodCode;
}
elsif ($cmd eq 'radios')  {
LogIt(0,"\n\n$Bold  ***$Green Available radios $White ***");
print " Name       protocol   model\n";
print "------------------------------------\n";
foreach my $name (sort keys %All_Radios) {
my $uname = sprintf("%-10.10s",$All_Radios{$name}{'name'});
my $protocol = sprintf("%10.10s",uc($All_Radios{$name}{'protocol'}));
my $model = $All_Radios{$name}{'model'};
if (!$model) {$model = '(n/a)';}
else {$model = uc($model);}
LogIt(0," $Bold$Yellow$uname $Green$protocol $Cyan$model");
}
}
elsif ($cmd eq 'rewrite') {
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {LogIt(0,"found $filecount  files to rewrite" );}
else {LogIt(480,"No files found to rewrite!");}
my $defref = '';
if (scalar @radio) {
my $name = lc($radio[0]);
select_radio($name);
$defref = \%radio_def;
}
if ($User_fspec) {$multi = FALSE;}
if ($multi) {
LogIt(0,"Generating multiple output files");
my %used_sqkey = ();
my $last_skey = 0;
foreach my $fs (@filelist) {
if (!-e $fs) {
LogIt(1,"Unable to locate input file $fs!");
next;
}
my %database = ();
read_radioctl(\%database,$fs);
my ($filename,$filepath,$fileext) = fileparse($fs,qr/\.[^.]*/);
my $outfile = set_filespec("$filename.csv",'tmpdir',\%radio_def);
if ($fs eq $outfile) {
LogIt(2611,"Input file $fs is same as output file!");
}
if ($sqkey) {
foreach my $sysrec (@{$database{'system'}}) {
if (!$sysrec->{'index'}) {next;}
my $old_qkey = $sysrec->{'qkey'};
if (!defined $old_qkey) {$old_qkey = -1;}
if (looks_like_number($old_qkey) and ($old_qkey >= 0)) {
$used_sqkey{$old_qkey} = TRUE;
}
}
foreach my $sysrec (@{$database{'system'}}) {
if (!$sysrec->{'index'}) {next;}
my $sysno = $sysrec->{'index'};
my $sysname = $sysrec->{'service'};
if (!$sysname) {$sysname = "System $sysno";}
$last_skey = qkey_proc($sysrec,\%used_sqkey,'qkey',"$sysname ($sysno)",$last_skey);
}
}
update_qkey(\%database);
write_data($outfile,\%database);
exit $GoodCode;
}
}
else {
my $outfile = set_filespec("rewrite.csv",'tmpdir',\%radio_def);
%radiodb = ();
foreach my $fs (@filelist) {
if ($fs eq $outfile) {
LogIt(2660,"Input $fs is the same as output file!");
}
read_radioctl(\%radiodb,$fs);
}
update_qkey(\%radiodb);
write_data($outfile,\%radiodb);
exit $GoodCode;
}### Generate a single output file
exit 0;
}
elsif ($cmd =~ /^hpd2/i) {
my $fs = shift @ARGV;
if (!$fs) {LogIt(2727,"No input file specified!");}
if (!-e $fs) {LogIt(2728,"Input file $fs does not exist!");}
if ($loc) {
$loc = lc($loc);
if ($known_locations{$loc}{'lat'}) {
$gps_parms{'lat'} = $known_locations{$loc}{'lat'};
$gps_parms{'lon'} = $known_locations{$loc}{'lon'};
print "RADIOWRITE l2759:Using location $Yellow$loc$Reset " .
"lat=>$Bold$gps_parms{'lat'}$Reset lon->$Bold$gps_parms{'lon'}$Eol";
}
else {
LogIt(2763,"Location $Yellow$loc$White was not defined in the$Yellow radioctl.conf$White file!");
}
}
else {
foreach my $type ('lat','lon') {
my $value = $gps_parms{$type};
if ($value) {
my ($dec,$dms) = Lat_Lon_Parse($value,$type);
if ($dec) {$gps_parms{$type} = $dec;}
else {
LogIt(2790,"Invalid $type Coordinate $Yellow$value$White specified!");
}
}
}
}### Checking Latitude & logitude
my $defref = '';
if (scalar @radio) {
my $name = lc($radio[0]);
select_radio($name);
$defref = \%radio_def;
}
my ($filename,$path,$ext) = fileparse($fs,qr/\.[^.]*/);
my $outfile = set_filespec("$filename.csv",'tmpdir',$defref);
my @inrecs = ();
if (open INFILE,$fs) {
@inrecs = <INFILE>;
close INFILE;
}
else {LogIt(3551,"Could not read $fs");}
if (!scalar @inrecs) {LogIt(1335,"No records were read from $fs");}
%radiodb = ();
my $rc = uniden_read_sd(\%radiodb,\@inrecs,\%gps_parms);
if (defined $radiodb{'system'}[1]{'index'}) {
LogIt(0,"All input records processed. Generating output file...");
update_qkey(\%radiodb);
my $radio_dir = '';
write_data($outfile,\%radiodb);
exit $GoodCode;
}
else {LogIt(1,"No input records were processed! No file created.");}
exit 1;
}### HPD2CSV
elsif ($cmd =~ /st/i) { 
my $radioname = shift @ARGV;
if (!$radioname) {LogIt(2941,"No radio for STORE given!");}
$bench{'start_write'} = time();
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {LogIt(0,"found $filecount  files to store into radio");}
else {LogIt(2950,"No files specified or found to store into radio!");}
my $radiosel = lc($radioname);
select_radio($radiosel);
my $protocol = $radio_def{'protocol'};
my $routine = $Radio_Routine{$protocol};
if (!$routine) {LogIt(2961,"STORE:Radio routine not set for protocol $protocol");}
if (AutoBaud(\%parmref)) {
LogIt(2969,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
$parmref{'database'} = \%radiodb;
if (&$routine('init',\%parmref)) {
LogIt(2988,"STORE:Cannot initialize the selected radio=>$radiosel");
}
%radiodb = ();
foreach my $fs (@filelist) {
read_radioctl(\%radiodb,$fs);
}
if (looks_like_number($renum)) {
my $channel = $renum;
foreach my $rec (@{$radiodb{'freq'}}) {
if ($rec->{'index'}) {
$rec->{'channel'} = $channel;
$channel++;
if ($channel > $radio_def{'maxchan'}) {
my $origin = $radio_def{'origin'};
LogIt(1,"Overflow for channel number. Reset to $origin");
$channel = $origin;
}
}
}
}
my %options = (
'erase' => $erase,
'nodie' => $nodie,
'count' => $User_count,
);
$parmref{'options'} = \%options;
my $rc = 0;
if (!$radiodb{'system'}[1]{'index'}) {
$nosys = TRUE;
print "Bypassing system store as no system data$Eol";
}
elsif ($nosys) {
print "Bypassing system store due to NOSYS option$Eol";
}
else {
$rc = &$routine('setmem',\%parmref);
if ($rc) {
if ($rc eq $NotForModel) {
LogIt(3048,"STORE is not valid for $Yellow" . uc($radioname));
}
else {
LogIt(3051,"STORE: $Bold SETMEM routine from radio returned code $rc");
}
}
}
if (scalar @{$radiodb{'search'}} > 1) {
if ($nosearch) {
print "Skipping store of SEARCH records due to NOSEARCH option$Eol";
}
else {
$rc =  &$routine('setsrch',\%parmref);
if ($rc) {
LogIt(1,"STORE 2706:$Bold SETSRCH routine from radio returned code $rc");
}
}
}## Search records available
else {
if ($Verbose) {print "Skipping store of SEARCH records due to no records$Eol";}
}### Search records available
if (scalar @{$radiodb{'global'}} > 1) {
if ($noglobals) {
print "Skipping store of GLOBAL records due to NOGLOBAL option$Eol";
}
else {
my $grc =  &$routine('setglob',\%parmref);
if ($grc) {
LogIt(1,"STORE l2730:$Bold SETGLOB routine from radio returned code $grc");
if (!$rc) {$rc = $grc}
}
}
}### Global records available
else {
if ($Verbose) {print "Skipping store of GLOBAL records due to no GLOBAL records$Eol";}
}
if ((scalar @{$radiodb{'toneout'}} > 1) and ($protocol =~ /uniden/i))  {
if ($notoneout) {
print "Skipping store of TONEOUT records due to NOTONEOUT option$Eol";
}
else {
my $trc =  &$routine('settone',\%parmref);
if ($trc) {
LogIt(1,"STORE l3340:$Bold SETTONE routine from radio returned code $trc");
if (!$rc) {$rc = $trc;}
}
}
}
else {
if ($Verbose) {print "Skipping store of TONEOUT records due to not a UNIDEN radio$Eol";}
}
STOREEND:
$bench{'end_write'}  = time();
BenchMark(\%bench);
exit $rc;
}
elsif ($cmd =~ /sh/) { 
my $radioname = shift @ARGV;
if (!$radioname) {LogIt(2293,"SHOWALL:No radio specified!");}
my $radiosel = lc($radioname);
select_radio($radiosel);
my $protocol = $radio_def{'protocol'};
if (!$protocol) {
LogIt(2302,"No protocol available!");
}
if ($protocol ne 'uniden') {
LogIt(2304,"SHOWALL is NOT valid for protocol $protocol!");
}
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
$parmref{'database'} = \%radiodb;
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
%radiodb = ();
my %options = ();
$parmref{'options'} = \%options;
if (uniden_cmd('_getall',\%parmref)) {LogIt(492,"Could not get systems!");}
shift @{$radiodb{'system'}};
if (scalar @{$radiodb{'system'}}) {
LogIt(0,"\n\n");
foreach my $rcd (@{$radiodb{'system'}}) {
my $name = $rcd->{'service'};
my $addr = sprintf("%6.6u",$rcd->{'block_addr'});
my $type = sprintf("%-7.7s",$rcd->{'systemtype'});
my $qkey = sprintf("%3.3s",$rcd->{'qkey'});
my $sysno = sprintf("%3u",$rcd->{'index'});
LogIt(0,"$Bold System:$Green$sysno"  .
"$White type:$Yellow$type$White" .
" addr:$Blue$addr$White  key:$Magenta$qkey$White  name:$Red$name");
}
LogIt(0,"\n");
}
else {LogIt(1,"No systems found in connected radio!");}
exit 0;
}
elsif ($cmd eq 'range') {
my $radioname =  shift @ARGV;
if (!$radioname) {LogIt(2686,"Need to specify the radio!");}
my %settings = ();
foreach my $key ('start','end','step') {
my $value = shift @ARGV;
if ($value) {
if ($value eq '.') {next;}
elsif (!looks_like_number($value)) {
LogIt(2696,"$key Value MUST be a number or '.'");
}
else {$settings{$key} = $value;}
}
}
if (!$settings{'start'}){$settings{'start'} =      10000;}
if (!$settings{'end'})  {$settings{'end'}   = 1000000000;}
if (!$settings{'step'}) {$settings{'step'}  =     100000;}
$bench{'start_range'} = time();
foreach my $key (keys %settings) {
if ($settings{$key} =~ /\./) { 
my $hz = freq_to_rc($settings{$key});
if ($hz < 0) {
LogIt(2715,"$key for $settings{$key} is not a valid frequency");
}
$settings{$key} = $hz;
}
}
my $frequency = $settings{'start'};
my $endfreq =  $settings{'end'};
my $step = $settings{'step'};
my $radiosel = lc($radioname);
select_radio($radiosel);
my $protocol = $radio_def{'protocol'};
my $routine = $Radio_Routine{$protocol};
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
&$routine('init',\%parmref);
my @valid_ranges = ();
my $okstart = 0;
my $okstop = 0;
my $defref    = $parmref{'def'};
$defref ->{'minfreq'} = $frequency;
$defref ->{'maxfreq'} = $endfreq;
$defref ->{'gstart_1'} = 0;
$defref ->{'gstart_2'} = 0;
$defref ->{'gstop_1'} = 0;
$defref ->{'gstop_2'} = 0;
$defref ->{'cellgap'} = FALSE;
$parmref{'_nowarn'} = TRUE;
print $Eol,$Bold," Starting range test: $Green",Strip(rc_to_freq($frequency)),$White,
' MHz -> ', $Yellow,Strip(rc_to_freq($endfreq)),$White,
' MHz  by ',$Magenta,Strip(rc_to_freq($step)),$White," Mhz$Eol$Eol";
my $cleareol = "\e[K";
while ($frequency < $endfreq) {
print STDERR "   $Bold$Green",
sprintf("%10.6f",rc_to_freq($frequency)),$Reset," Mhz",
"$cleareol\r";
%in = ('frequency' => $frequency, 'mode' => 'fmn');
my $rc = &$routine('setvfo',\%parmref);
if ($rc) {
if ($okstart) {
push @valid_ranges,rc_to_freq($okstart) . '->' . rc_to_freq($okstop);
$okstop = 0;
$okstart = 0;
}
}
else {
if (!$okstart) {$okstart = $frequency;}
$okstop = $frequency;
}
$frequency = $frequency + $step;
}
if ($okstart) { push @valid_ranges,rc_to_freq($okstart) . '->' . rc_to_freq($frequency);}
print $Bold,"\n\nRanges:$Eol";
foreach my $range (@valid_ranges) {print "$Bold$Green$range$Eol";}
$bench{'end_range'}  = time();
BenchMark(\%bench);
exit 0;
}
elsif ($cmd eq 'edit') {
my $fs = shift @ARGV;
if (!$fs) {LogIt(1566,"No input file specified!");}
if (!-e $fs) {LogIt(1567,"Input file $fs does not exist!");}
my @inrecs = ();
if (open INFILE,$fs) {
@inrecs = <INFILE>;
close INFILE;
}
else {LogIt(1334,"Could not read $fs");}
if (!scalar @inrecs) {LogIt(1577,"No records were read from $fs");}
my @out = ();
my $fieldref = \$version1{'freq'};
my $index = 0;
my $recno = 0;
foreach my $linein (@inrecs) {
$recno++;
if (lc(substr($linein,0,4)) eq 'freq') {
my $line = $linein;
chomp $line;
my %outrec = ('_recno' => $recno, '_filespec' =>$fs);
if (read_line($line,\%outrec,\%version1)) {
push @out,$linein;
next;
}
$index++;
$outrec{'index'} = $index;
$outrec{'_rsvd'} = '';
my $lineout = write_format(\%outrec,'freq',$outrec{'protocol'},FALSE);
push @out,"$lineout\n";
}### FREQ record for editing
else {push @out,$linein;}
}
my $tdir = get_directory(FALSE);
my ($filename,$filepath,$fileext) = fileparse($fs,qr/\.[^.]*/);
my $outfile = "$tdir/$filename.csv";
if (-e $outfile) {
LogIt(1,"existing file $Yellow$outfile$White will be overwritten.");
if (!$overwrite) {
print "   OK (Y/N)=>";
my $answer = <STDIN>;
chomp($answer);
print STDERR "$Eol";
if (uc(substr($answer,0,1)) ne 'Y') {
LogIt(0,"$Bold Output file generation was bypassed!");
return 1;
}
}
}
if (open OUT,">$outfile") {
print OUT @out;
close OUT;
}
else {LogIt(1629,"Could not create $outfile!");}
LogIt(0,"$Bold $outfile created with changes....");
}
elsif ($cmd eq 'nullgroup') {
my %database = ();
my $fs = shift @ARGV;
read_radioctl(\%database,$fs);
foreach my $freq (@{$database{'freq'}}) {
if (!$freq->{'index'}) {next;}
if ($freq->{'groupno'}) {
my $groupno = $freq->{'groupno'};
if ($database{'group'}[$groupno]{"index"}) {
if ($database{'group'}[$groupno]{'_freqcnt'}) {
$database{'group'}[$groupno]{'_freqcnt'}++;
}
else {$database{'group'}[$groupno]{'_freqcnt'} = 1;}
}
}
}
foreach my $group (@{$database{'group'}}) {
if (!$group->{'index'}) {next;}
if ($group->{'_freqcnt'}) {next;}
else {
LogIt(0,"$Bold$Yellow$group->{'service'}$White Is not referenced by any FREQ record");
}
}
}
elsif ($cmd eq 'dplysig') {
my @freqlist = (25,30,40,75,80,
120,140,150,160,170,
200,300,400,430,451,470,
500,584,602,700,770,
800,850,900,950,999,
);
if ($testfrq) {
print "Testfrq=>$testfrq\n";
unshift @freqlist,$testfrq;
print Dumper(@freqlist),"\n";
}
my $ndx = -1;
my $freq = -1;
my $lastdply = '.';
my $first = TRUE;
my $radioname = shift @ARGV;
if (!$radioname) {LogIt(1672,"DPLYSIG:No radio for command $cmd given!");}
$bench{'start_read'} = time();
my $radiosel = lc($radioname);
select_radio($radiosel);
my $protocol = $radio_def{'protocol'};
my $routine = $Radio_Routine{$protocol};
if (!$routine) {LogIt(1683,"DPLYSIG:Radio routine not set for protocol $protocol");}
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
%in = ('noport' => FALSE, 'nobaud' => FALSE);
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
$parmref{'database'} = \%radiodb;
%in = ();
if (&$routine('init',\%parmref) ) {
LogIt(1718,"DPLYSIG:Failed to initialize radio: $radiosel ($protocol)");
}
open(TTY, "+</dev/tty") or die "no tty: $!";
system "stty -echo cbreak </dev/tty >/dev/tty 2>&1";
my $direction = 1;
while (TRUE) {
if ($freq < 0) {
$ndx = $ndx + $direction;
if ($ndx > $#freqlist) {$ndx = 0;}
elsif ($ndx < 0) {$ndx = $#freqlist;}
$freq = $freqlist[$ndx];
%in = ('frequency'=> ($freq * 1000000), 'mode' => 'auto');
if (&$routine('setvfo',\%parmref)) {
LogIt(1,"Radio did NOT like frequency $Yellow$freq$White mhz");
$ndx = $ndx + $direction;
sleep 1;
$freq = -1;
next;
}
$lastdply = '.';
}### setting frequency
%out = ('sql'=> 0, 'signal'=> 0, 'meter' => 0, 'rssi'=> 0);
if (&$routine('getsig',\%parmref)) {LogIt(1,"Radio is not responing");}
else {
my $sql = $out{'sql'};
if ($sql) {$sql = $Bold . 'Open ';}
else {$sql = 'Closed';}
my $signal = $out{'signal'};
if ($signal) {$signal = "$Bold$signal";}
else {$signal = 0;}
my $rssi = $out{'rssi'};
if ($rssi) {$rssi = $Bold . sprintf("%03.3u",$rssi);}
else {$rssi = '000';}
my $meter = $out{'meter'};
if ($meter) {$meter = $Bold . sprintf("%2.2u",$meter);}
else {$meter = ' 0';}
$freq = sprintf("%4.1f",$freq);
my $dply = "freq=>$Bold$Yellow$freq MHz$Reset" .
" squelch=>$sql$Reset " .
" signal=>$Green$signal$Reset" .
" meter=>$meter$Reset" .
" rssi=>$Magenta$rssi$Reset";
print STDERR "\r$dply   ";
my $rin;
vec($rin, fileno(TTY), 1) = 1;
if (select($rin,undef,undef,0)) {
my $key = getc();
if (lc($key) eq 'q') {
close TTY;
last;
}
elsif (lc($key) eq 'u') {
$freq = -1;
$direction = 1;
}
elsif (lc($key) eq 'd') {
$freq = -1;
$direction = -1;
}
else {
}
}
}
}
close TTY;
system "stty echo -cbreak </dev/tty >/dev/tty 2>&1";
print "\n";
exit 0;
}
elsif ($cmd eq 'dupcheck') {
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {LogIt(0,"found $filecount  files to check");}
else {LogIt(1132,"No files found to process!");}
my %database = ();
foreach my $fs (@filelist) {
if (!-e $fs) {LogIt(497,"Unable to locate $fs!");}
read_radioctl(\%database,$fs);
}
my %freqs = ();
foreach my $freqrec (@{$database{'freq'}}) {
if (!$freqrec->{'index'}) {next;}
my $frequency = $freqrec->{'frequency'};
if (!$frequency) {next;}
my $oldref = $freqs{$frequency};
if ($oldref) {
print "Duplicate frequency:",rc_to_freq($frequency),"\n";
print "   First record number: $oldref->{'_recno'} Service: $oldref->{'service'}\n";
print "  Current record number:$freqrec->{'_recno'} Service:$freqrec->{'service'}\n";
}
else {$freqs{$frequency} = $freqrec;}
}
}
elsif ($cmd =~ /rc2sdrt/i) {
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {
LogIt(0,"found $filecount  files to convert");
}
else {LogIt(1162,"No files found to rewrite!");}
%radiodb = ();
foreach my $fs (@filelist) {
read_radioctl(\%radiodb,$fs);
}
my @outrecs = ('<playlist version="4">' . "\n");
foreach my $sys (@{$radiodb{'system'}}) {
my $sysno = $sys->{'index'};
if (!$sysno) {next;}
my $systype = $sys->{'systemtype'};
my $proto = 'DMR';
if ($systype =~ /p25/i) {$proto = 'APCO25';}
elsif ($systype =~ /cnv/i) {$proto = 'CNV';}
my $sysname = Strip($sys->{'service'});
if ($systype =~ /cnv/i) {   
push @outrecs,"\n <!-- $sysname (conventional) -->\n";
my %freqs = ();
foreach my $grec (@{$radiodb{'group'}}) {
if (!$grec->{'index'}) {next;}
my $sysid = $grec->{'sysno'};
if ($sysid != $sysno) {next;}
my $grpno = $grec->{'index'};
if (!$grpno) {next;}
my $grpvalid = $grec->{'valid'};
my $grpname = $grec->{'service'};
foreach my $frec (@{$radiodb{'freq'}}) {
my $index =$frec->{'index'};
if (!$index) {next;}
my $grpid = $frec->{'groupno'};
if (!$grpid) {next;}
if ($grpid != $grpno) {next;}
my $freq = $frec->{'frequency'};
if (!$freq) {next;}
if (!$grpvalid) {$freq->{'valid'} = FALSE;}
$freq = Strip($freq);
if ($freqs{$freq}) {
LogIt(1,"Skipping duplicate frequency $freq in record $frec->{'_recno'}");
}
else {$freqs{$freq} = $index;}
}### freq locate
}### Groups
my @sort = sort Numerically keys %freqs;
foreach my $freq (@sort) {
my $index = $freqs{$freq};
my $service = $radiodb{'freq'}[$index]{'service'};
$service =~ s/\&/ and /g;
my $order = '-1';
if ($radiodb{'freq'}[$index]{'valid'}) {$order = '1';}
my $outrec = "\n <!-- $service -->\n" .
'<channel system="' . $service . '" name="' . $service . '" ' .
'enabled="false" order="' . $order . '">' . "\n" .
'   <alias_list_name/> ' . "\n" .
'   <source_configuration type="sourceConfigTuner" frequency="' .
$freq . '" source_type="TUNER"/>' . "\n" .
'    <event_log_configuration>' . "\n" .
'          <logger>CALL_EVENT</logger>' . "\n" .
'          <logger>DECODED_MESSAGE</logger>' . "\n" .
'   </event_log_configuration>' . "\n" .
'   <aux_decode_configuration>' . "\n" .
'       <aux_decoder>FLEETSYNC2</aux_decoder>' . "\n" .
'       <aux_decoder>MDC1200</aux_decoder>' . "\n" .
'       <aux_decoder>TAIT_1200</aux_decoder>' . "\n" .
'   </aux_decode_configuration>' . "\n" .
'   <decode_configuration type="decodeConfigNBFM" ' .
'bandwidth="BW_12_5" squelch="-60" talkgroup="1"/>' . "\n" .
'   <record_configuration/>' . "\n" .
' </channel>' . "\n\n";
push @outrecs,$outrec;
}### foreach sorted records
my $msg = scalar @sort . " channels created";
LogIt(0,$msg);
}### Conventional system
else {
$sysname =~ s/ /\_/g;   
foreach my $grec (@{$radiodb{'group'}}) {
if (!$grec->{'index'}) {next;}
my $sysid = $grec->{'sysno'};
if ($sysid != $sysno) {next;}
my $grpno = $grec->{'index'};
if (!$grpno) {next;}
my $grpvalid = $grec->{'valid'};
my $grpname = Strip($grec->{'service'});
$grpname =~ s/\&/ and /g;
foreach my $frec (@{$radiodb{'freq'}}) {
my $index =$frec->{'index'};
if (!$index) {next;}
my $grpid = $frec->{'groupno'};
if (!$grpid) {next;}
if ($grpid != $grpno) {next;}
my $tgid = $frec->{'tgid'};
if (!$tgid) {next;}
$tgid = Strip($tgid);
my $valid = $frec->{'valid'};
if (!$grpvalid) {$valid = FALSE;}
my $service = Strip($frec->{'service'});
$service =~ s/\&/ and /g;
my $icon = '';
if ($service =~ /pd/i) {$icon = 'Police';}
elsif ($service =~ /dpw/i) {$icon = 'Dump Truck';}
elsif ($service =~ /fd/i) {$icon = 'Fire Truck';}
elsif ($service =~ /ems/i) {$icon = 'Ambulance';}
my $outrec = '<alias group="' . $grpname . '" ' .
'color="0" ' .
'name="' . $service . '" ' .
'list="' . $sysname . '"' ;
if ($icon) {
$outrec = $outrec . ' iconName="' . $icon . '"';
}
push @outrecs,"$outrec>\n";
$outrec = '   <id type="talkgroup" value="' . $tgid . '" ' .
'protocol="' . $proto . '" />';
push @outrecs,"$outrec\n";
my $prio = -1;
if ($valid) {$prio = 1;}
$outrec = '   <id type="priority" priority="' . $prio . '"/>';
push @outrecs,"$outrec\n";
push @outrecs,"</alias>\n";
}### for each FREQ record
}### Alias definitions
foreach my $srec (@{$radiodb{'site'}}) {
if (!$srec->{'index'}) {next;}
my $sysid = $srec->{'sysno'};
if (!$sysid) {next;}
if ($sysid != $sysno) {next;}
if (!$srec->{'valid'}) {next;}
my $siteno = $srec->{'index'};
my $site_number = $srec->{'site_number'};
if (!$site_number) {
print "No site number for siteno $siteno\n";
$site_number = '001';
}
my $site_name = $srec->{'service'};
if (!$site_name) {$site_name = "Site $site_number";}
my @tfreqs = ();
my %lcns = ();
foreach my $trec (@{$radiodb{'tfreq'}}) {
my $tndx = $trec->{'index'};
if (!$tndx) {next;}
if ($trec->{'siteno'} != $siteno) {next;}
my $freq = $trec->{'frequency'};
if (!$freq) {next;}
push @tfreqs,$freq;
my $lcn = $trec->{'lcn'};
if ($lcn and looks_like_number($lcn)) {
$lcns{$lcn} = $freq;
}
}
my $outrec = '   <channel system="' . $sysname . '" ' .
'enabled="false" ' .
'site="' . $site_number . '" name="' . $site_name . '" order="1">';
push @outrecs,"$outrec\n";
$outrec = "      <alias_list_name>$sysname</alias_list_name>\n";
push @outrecs,$outrec;
$outrec = "      <event_log_configuration>\n" .
"         <logger>CALL_EVENT</logger>\n" .
"         <logger>DECODED_MESSAGE</logger>\n" .
"         <logger>TRAFFIC_CALL_EVENT</logger>\n" .
"         <logger>TRAFFIC_DECODED_MESSAGE</logger>\n" .
"      </event_log_configuration>\n";
push @outrecs,$outrec;
$outrec = '      <source_configuration type="sourceConfigTunerMultipleFrequency" ' .
'frequency_rotation_delay="400" ' .
'source_type="TUNER_MULTIPLE_FREQUENCIES">';
push @outrecs,"$outrec\n";
foreach my $freq (@tfreqs) {
$outrec = "         <frequency>$freq</frequency>\n";
push @outrecs,$outrec;
}
$outrec = "      </source_configuration>\n";
push @outrecs,$outrec;
if ($proto =~/apco/i) {
$outrec = "      <aux_decode_configuration/> \n" .
'   <decode_configuration type="decodeConfigP25Phase1" ' .
' modulation="CQPSK" traffic_channel_pool_size="3" ' .
'ignore_data_calls="false"/>' . "\n" .
"      <record_configuration/>\n";
push @outrecs,$outrec;
}
elsif ($proto =~ /dmr/i) {
print "Found DMR decoder\n";
$outrec = "      <aux_decode_configuration/> \n" .
'      <decode_configuration type="decodeConfigDMR" ' .
' use_compressed_talkgroups="false" ignore_crc="false" ' .
'  traffic_channel_pool_size="3" ' .
'ignore_data_calls="false">' . "\n" ;
push @outrecs,$outrec;
foreach my $num (sort Numerically keys %lcns) {
my $lsn1 = ($num * 2) - 1;
my $lsn2 = ($num * 2);
$outrec = '         <timeslot lsn="' . $lsn1 . '" downlink="' .
$lcns{$num} . '" uplink="0"/>' . "\n";
push @outrecs,$outrec;
$outrec = '         <timeslot lsn="' . $lsn2 . '" downlink="' .
$lcns{$num} . '" uplink="0"/>' . "\n";
push @outrecs,$outrec;
}
push @outrecs,"      </decode_configuration>\n";
}
else {
print "Need decoder for $proto\n";
}
push @outrecs,"    <record_configuration/>\n";
push @outrecs,"   </channel>\n";
}### site loop
}### trunked system process
next;
foreach my $srec (@{$radiodb{'site'}}) {
if (!$srec->{'index'}) {next;}
my $sysid = $srec->{'sysno'};
if (!$sysid) {next;}
if ($sysid != $sysno) {next;}
my $siteno = $srec->{'index'};
my $site_number = $srec->{'site_number'};
if (!$site_number) {$site_number = '001';}
my $outrec = '<channel system="' . $sysname .
'enabled="true" ' .
'site="' . $site_number .
' order="1">';
push @outrecs,"$outrec\n";
my @lcn = ();
foreach my $trec (@{$radiodb{'tfreq'}}) {
my $siteid = $trec->{'siteno'};
if (!$siteid) {next;}
if ($siteid != $siteno) {next;}
my $freq = $trec->{'frequency'};
my $outrec = '<frequency>' . $freq . '</frequency>';
push @outrecs,"$outrec\n";
my $lcn = $trec->{'lcn'};
if ($lcn) {
$outrec = '<timeslot lsn="' . $lcn . '" downlink="' .
$freq . '" uplink="0"/>';
push @lcn,"$outrec\n";
}
}### for each TFREQ
if (scalar @lcn) {push @outrecs,@lcn;}
}### For each SITE
foreach my $grec (@{$radiodb{'group'}}) {
if (!$grec->{'index'}) {next;}
my $sysid = $grec->{'sysno'};
if ($sysid != $sysno) {next;}
my $grpno = $grec->{'index'};
if (!$grpno) {next;}
my $grpname = $grec->{'service'};
foreach my $frec (@{$radiodb{'freq'}}) {
if (!$frec->{'index'}) {next;}
my $grpid = $frec->{'groupno'};
if ($grpid != $grpno) {next;}
my $tgid = $frec->{'tgid'};
if (!$tgid) {$tgid = '0';}
my $service = $frec->{'service'};
$service =~ s/\&/ and /g;   
my $outrec  = '';
if ($proto ne 'CNV') {
if (!$tgid) {next;}
my $outrec = '<alias color="0" group="' . $grpname . '" ' .
'name="' . $service . '" list="' . $sysname . '">' . "\n" .
'  <id type="talkgroup" value="' . $tgid . '" protocol="' . $proto . '"/>' . "\n" .
'</alias>';
}
else {
my $freq = $frec->{'frequency'};
if (!$freq) {next;}
$outrec =
'<channel system="' . $service . '" name="' . $service . '" ' .
'enabled="false" order="1">' . "\n" .
'   <alias_list_name/> ' . "\n" .
'   <source_configuration type="sourceConfigTuner" frequency="' .
$freq . '" source_type="TUNER"/>' . "\n" .
'    <event_log_configuration>' . "\n" .
'          <logger>CALL_EVENT</logger>' . "\n" .
'          <logger>DECODED_MESSAGE</logger>' . "\n" .
'   </event_log_configuration>' . "\n" .
'   <aux_decode_configuration>' . "\n" .
'       <aux_decoder>FLEETSYNC2</aux_decoder>' . "\n" .
'       <aux_decoder>MDC1200</aux_decoder>' . "\n" .
'       <aux_decoder>TAIT_1200</aux_decoder>' . "\n" .
'   </aux_decode_configuration>' . "\n" .
'   <decode_configuration type="decodeConfigNBFM" ' .
'bandwidth="BW_12_5" squelch="-60" talkgroup="1"/>' . "\n" .
'   <record_configuration/>' . "\n" .
' </channel>' . "\n";
}### this is a conventional system
push @outrecs,"$outrec\n";
}### foreach freq
}## for each group
last;
}### foreach system
push @outrecs,"</playlist>\n";
my $outfile = "/tmp/temp.xml";
if (open OUTFILE,">$outfile") {
print OUTFILE @outrecs;
close OUTFILE;
print "Output is in $outfile\n";
}
else {LogIt(1365,"Cannot open $outfile!");}
}
elsif ($cmd eq 'signal') {
my $radioname = shift @ARGV;
if (!$radioname) {LogIt(4360,"No radio for command $cmd given!");}
$bench{'start_write'} = time();
my $radiosel = lc($radioname);
select_radio($radiosel);
my $protocol = $radio_def{'protocol'};
my $routine = $Radio_Routine{$protocol};
if (!$routine) {LogIt(4370,"SIGNAL:Radio routine not set for protocol $protocol");}
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
%in = ('noport' => FALSE, 'nobaud' => FALSE);
$parmref{'database'} = \%radiodb;
if (&$routine('init',\%parmref)) {
LogIt(4045,"STORE:Cannot initialize the selected radio=>$radiosel");
}
my $clreol = "\e[K";
print "\n";
print "CTL-Break to terminate this routine\n\n";
while (TRUE) {
my $rc = &$routine('getsig',\%parmref);
my $sql = $out{'sql'};
my $signal = $out{'signal'};
my $rssi = $out{'rssi'};
if (!$rssi) {$rssi = 0;}
my $dbmv = $out{'dbmv'};
my $meter = $out{'meter'};
if (!$meter) {$meter = 0;}
if (!defined $dbmv) {$dbmv = -999;}
print STDERR time()," signal:$Bold$Yellow",sprintf("%2.2i",$signal),$Reset,
" sql:$Bold$sql$Reset",
" rssi:$Bold$Green",sprintf("%4.4i",$rssi),$Reset,
" dbmv:$Bold$Cyan",sprintf("%4.4s",$dbmv),$Reset,
" meter:$Cyan$meter$Reset ",
"\r";
}
}
elsif ($cmd eq 'decrypt') {
my $radiosel = 'ICR30';
select_radio($radiosel);
if (AutoBaud(\%parmref)) {
LogIt(1110,"Failed to connect to radio:$radiosel");
}
if ($Verbose) {
LogIt(0,"$Bold Radio $Yellow$radiosel$White is on port " .
"$Magenta$radio_def{'port'}$White with baud $Green$radio_def{'baud'}");
}
$parmref{'out'} = \%out;
$parmref{'in'} = \%in;
icom_cmd('init',\%parmref);
my $code = 0;
my $count = 0;
while (TRUE) {
icom_cmd('getsig',\%parmref);
if ($out{'signal'}) {
my $signal = $out{'signal'};
my $raw = $out{'raw'};
my $sql = $out{'sql'};
my $time = time();
$parmref{'write'} = FALSE;
icom_cmd('_nxdn_ran',\%parmref);
my $timestamp = Time_Format($time);
my $nxdnran = $out{'nxdnran'};
icom_cmd('_get_nxdn_rx_id',\%parmref);
my $nxdnrxid =  $out{'nxdnrxid'};
icom_cmd('_get_nxdn_rx_status',\%parmref);
my $nxdnrxstatus =  $out{'nxdnrxstatus'};
if ($nxdnrxstatus eq '00') {next;}
$count = $count + 1;
$code++;
if ($code > 32000) {$code = 1;}
$parmref{'write'} = TRUE;
$in{'nxdnkey'} = $code;
icom_cmd('_nxdn_crypt_key',\%parmref);
LogIt(0,"$timestamp count=$count key=$code status=$nxdnrxstatus nxdnran=$nxdnran nxdnrxid=$nxdnrxid signal=$signal raw=$raw");
while ($signal & ($nxdnrxstatus ne '00')) {
icom_cmd('_get_nxdn_rx_status',\%parmref);
my $newstatus =  $out{'nxdnrxstatus'};
icom_cmd('getsig',\%parmref);
$signal = $out{'signal'};
$raw = $out{'raw'};
if ($signal and ($newstatus ne '00') and ($nxdnrxstatus ne $newstatus))  {
LogIt(0,"    NXDN status changed=>$newstatus ");
}
usleep 20000;
}
my $offtime = time();
$timestamp = Time_Format($time);
my $duration = int($offtime - $time);
LogIt(0,"   Signal off at $timestamp ($duration seconds) nxdnrxstatus=$nxdnrxstatus");
}
}
}### DECRYPT command
elsif ($cmd eq 'find') {
my @ports = glob("/dev/tty*");
foreach my $port (@ports) {
print "looking at port $port\n";
}
exit;
}
elsif ($cmd eq 'testgen') {
my $grpcount = 10;
my $frqcount = 1;
my @outrecs = ("*RadioCtl \n","** Data for testing memory limits\n");
my $frqno = 1;
my $sitecnt = 1;
my $tfreqcnt = 1000;
push @outrecs,"SYSTEM   ,    1,Test System                   ,    1,P25s  ,         ,     0,  99,  0,    ,    ,    ,    400,   Auto\n";
foreach my $site (1..$sitecnt) {
push @outrecs,"SITE ,$site,Site $site,1,1,99\n";
foreach my $tfrq (1..$tfreqcnt) {
push @outrecs,"TFREQ,$tfrq,1,$site,850.312500,$tfrq,FMn\n";
}
}
foreach my $grp (1..$grpcount) {
push @outrecs,"GROUP    ,   $grp,Group $grp                    ,    1,    1,         ,  20,    ,   uniden,   01,     20,Off\n";
foreach my $frq (1..$frqcount) {
push @outrecs,"FREQ     ,   $frqno,Freq $frq for grp $grp        ,    1,    $grp,         ,   1, 150.000000,FMn   ,\n";
$frqno++;
}
}
my $outfile = "/tmp/radioctl/test.csv";
if (open OUTFILE,">$outfile") {
print OUTFILE @outrecs;
close OUTFILE;
LogIt(0,"$Bold$Yellow$outfile created");
}
else {LogIt(1,"Could not create $outfile");}
}
elsif ($cmd eq 'test') {
exit 0;
exit;
}#### Test code section
elsif ($cmd eq 'validate') {
LogIt(3832,"VALIDATE is not functional");
my @filelist = ();
get_files(\@filelist);
my $filecount = scalar @filelist;
if ($filecount) {LogIt(0,"found $filecount  files to validate");}
else {LogIt(38422,"No files found to validate!");}
%new = ();
my @warn = ();
my @dumps = ();
foreach my $fs (@filelist) {
LogIt(0,"Validating file $fs...");
read_radioctl(\%new,$fs);
my @systems = sort {$a <=> $b} keys %new;
my $syscount = scalar @systems;
LogIt(0,"  file contains $syscount systems");
foreach my $sysno (@systems) {
LogIt(0,"validating system $sysno..");
my $trunked = TRUE;
my $systype = $new{$sysno}{'system'}{$sysno}{'systemtype'};
my $recno = $new{$sysno}{'system'}{$sysno}{'recno'};
if (!$systype) {
push @warn,"missing SYSTYPE key for system=$sysno record=$recno. Set to 'CNV'";
$systype = 'cnv';
}
if (lc($systype) eq 'cnv') {$trunked = FALSE;}
my @sites =  keys %{$new{$sysno}{'site'}};
my @freqs = keys %{$new{$sysno}{'freq'}};
my @gids = keys %{$new{$sysno}{'gid'}};
my @groups = keys %{$new{$sysno}{'group'}};
my $sitecount = scalar @sites;
my $freqcount = scalar @freqs;
my $gidcount = scalar @gids;
my $groupcount = scalar @groups;
my %frequencies = ();
if ($trunked) {
LogIt(0,"   System $sysno is a TRUNKED $systype system");
LogIt(0,"     Containing $sitecount Sites and $gidcount GIDs");
}
else {LogIt(0,"   System $sysno is a CONVENTIONAL system");}
LogIt(0,"     There are $groupcount groups and $freqcount frequencies defined");
if ($sitecount)  {
}
if ($gidcount)  {
}
if ($freqcount)   {
foreach my $rcd (@freqs) {
my $flags = $new{$sysno}{'freq'}{$rcd}{'freq_flag'};
my $tone  = $new{$sysno}{'freq'}{$rcd}{'tone'};
my $dcs   =  $new{$sysno}{'freq'}{$rcd}{'dcs'};
my $freq  = $new{$sysno}{'freq'}{$rcd}{'frequency'};
my $recno  = $new{$sysno}{'freq'}{$rcd}{'recno'};
my $refno = $new{$sysno}{'freq'}{$rcd}{'refno'};
if (!$flags) {$flags = '';}
if (!$tone)  {$tone = '';}
if (!$dcs)   {$dcs = '';}
if (!$refno) {$refno = 0;}
if (!$freq)  {
if ($flags) {push @warn,"non-blank flags with 0 frequency in record $recno";}
next;
}
if ($flags =~ /t/i) {
if (lc($flags) ne 't') {
push @warn,"multiple flags=>$flags in a trunked freq in record $recno";
}
if ($tone) {push @warn,"'tone' value set in a trunked freq in record $recno";}
if ($dcs) {push @warn,"'dcs' value set in a trunked freq in record $recno";}
if (!$trunked) {push @warn,"Trunked frequency in a conventional system in record $recno";}
elsif (!$refno or (! defined $new{$sysno}{'site'}{$refno}{'siteno'})) {
push @warn,"REFNO for Trunked freq does not reference a valid site in record $recno";
}
}### trunked frequency process
else {
if ($tone) {### tone entered
if ($flags =~ /d/i) {push @warn,"DCS flag set with TONE frequency in record $recno";}
}
else {## no tone entered
if ($flags =~ /c/i) {push @warn,"CTCSS flag set with NO tone frequency in record $recno";}
}
if ($dcs) {### tone entered
if ($flags =~ /c/i) {push @warn,"CTCSS flag set with DCS frequency in record $recno";}
}
else {## no tone entered
if ($flags =~ /d/i) {push @warn,"DCS flag set with NO DCS frequency in record $recno";}
}
if ($flags =~ /s/i) {
if (!$refno or (! defined $new{$sysno}{'freq'}{$refno}{'frequency'})) {
push @warn,"REFNO for split record does not reference a valid record in record $recno";
}
if ($refno == $recno) {
push @warn,"REFNO for split record is self-referencing in record $recno";
}
}
else {
if (!$refno or (! defined $new{$sysno}{'group'}{$refno}{'recno'})) {
push @warn,"REFNO ($refno) does not reference a valid group in record $recno";
}
if ($frequencies{$freq}) {### is this frequency already defined
if ($dupcheck) {
push @warn,"Duplicate frequency $freq in $recno. with  $frequencies{$freq}";
}
$frequencies{$freq} = $frequencies{$freq} . ",rec=$recno";
}
else {$frequencies{$freq} = "rec=$recno";}
}
}### Non-Trunked frequency process
}### For each Freq record
}### Freq record checking
if ($groupcount) {
}
}### for each System in the fs
}### for each FS
if (scalar @warn) {
foreach my $msg (@warn) {
LogIt(1,$msg);
}
}
else {LogIt(0,"$Eol$Bold No inconsistancies found in any file$Eol");}
my $tfile = '/tmp/radiowrite_validate.csv';
if (write_radioctl(\%new,$tfile)) {
}
else {LogIt(0,"$Bold Created $Yellow$tfile$White for validation");}
}
elsif ($cmd eq 'clearall') {
LogIt(1959,"CLEARALL is not functional");
LogIt(1,"This will erase ALL programming and setting in the radio");
Get_Answer("Are you sure you wish to do this?");
LogIt(0,"$Eol$Bold Clearing all programming. Please wait!");
if( bcd396_cmd("PRG") ) {
LogIt(239,"Could not set radio into PRG mode!");
}
bcd396_cmd('CLR');
bcd396_cmd('EPG');
LogIt(0,"$Eol$Bold All programming is now erased!");
}
else {LogIt(627,"Unknown command $cmd!");}
exit;
sub sds_alert {
my $rec = shift @_;
my $atone = 'Off';
my $alevel = 'Auto';
my $acolor = 'Off';
my $apattern = "";
if  ($rec->{'emgalt'} and looks_like_number($rec->{'emgalt'})) {
$atone = $rec->{'emgalt'};
if ($atone > 8) {$atone = 8;}
if ($rec->{'emglvl'} and looks_like_number($rec->{'emglvl'})) {
$alevel = $rec->{'emglvl'};
}
if ($rec->{'emgpat'} and looks_like_number($rec->{'emgpat'})) {
if ($rec ->{'emgpat'} == 1) {$apattern = 'Slow Blink';}
else {$apattern = 'Fast Blink';}
}
if ($rec->{'emgcol'} and looks_like_number($rec->{'emgcol'})) {
$acolor = @xlate_color[$rec->{'emgcol'}];
if ($acolor) {$acolor = ucfirst($acolor);}
else {
LogIt(1,"RadioWrite l3041: Failed translation of $rec->{'emgcol'}");
$acolor = 'Off';
}
}
else { $acolor = 'Red';}
}### Alert is turned on
return ($atone,$alevel,$acolor,$apattern);
}
sub alert_sds {
my $inrec = shift @_;
my %outdata = ();
foreach my $key ('emgalt','emglvl','emgpat','emgcol') {
$outdata{$key} = 0;
if ($key eq 'emgalt') {
if (looks_like_number($inrec->{$key})) {$outdata{$key} = $inrec->{$key};}
}
elsif ($key eq 'emglvl') {
if (looks_like_number($inrec->{$key})) {$outdata{$key} = $inrec->{$key};}
}
elsif ($key eq 'emgpat') {
if ($inrec->{$key} =~ /slow/i) {$outdata{$key} = 1;}
elsif ($inrec->{$key} =~ /fast/i) {$outdata{$key} = 2;}
}
elsif ($key eq 'emgcol') {
$outdata{$key} = $color_xlate{$inrec->{$key}};
if (!$outdata{$key}) {$outdata{$key} = 0;}
}
}
if (!$outdata{'emgalt'}) {
$outdata{'emglvl'} = 0;
$outdata{'emgpat'} = 0;
$outdata{'emgcol'} = 0;
}
foreach my $key (keys %outdata) {$inrec->{$key} = $outdata{$key};}
return 0;
}
sub sds_validate {
my $sysinfo = shift @_;
my $db = shift @_;
my $sysno = $sysinfo->{'sysno'};
if (!$sysno) {LogIt(4683,"SDS_VALIDATE: No system number for $sysinfo!")}
if ($sysinfo->{'trunked'}) {
my @sites = keys %{$sysinfo->{'sites'}};
if (!scalar @sites) {
if ($gps_parms{'lat'} or $gps_parms{'lon'}) {
LogIt(0,"Not keeping system $db->{'system'}[$sysno]{'service'}. Out of range...");### debug
$db->{'system'}[$sysno]{'index'} = 0;}
else {
LogIt(1,"No sites defined for system $sysno ($db->{'system'}[$sysno]{'service'})");
$db->{'system'}[$sysno]{'valid'} = FALSE;
}
}
else {
foreach my $siteno (@sites) {
if (!$sysinfo->{'sites'}{$siteno}) {
LogIt(1,"No Frequencies defined for site $siteno ($db->{'site'}[$siteno]{'service'})");
}
}
}
}### Trunked system
else {
if (!$sysinfo->{'groupcnt'}) {
if ($gps_parms{'lat'} or $gps_parms{'lon'}) {
LogIt(0,"Not keeping system $db->{'system'}[$sysno]{'service'}. Out of range...");### debug
$db->{'system'}[$sysno]{'index'} = 0;
}
else {
LogIt(1,"No valid groups defined for system $sysno ($db->{'system'}[$sysno]{'service'})");
$db->{'system'}[$sysno]{'valid'} = FALSE;
}
}
}#### Conventional system
return 0;
}
sub icr30_cmd {
my $instr = substr($in{'test'},8);
$in{'test'} = lc($in{'test'});
if (       $in{'test'}       eq 'fefe9c0008')   {goto BYPASS;}
if (substr($in{'test'},0,10) eq 'fefe9c0011')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c0007d0') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c0007d1') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c000f11') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c000f12') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c0008a0') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001401') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001402') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001403') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001622') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001643') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001659') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001800') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a00') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a01') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a02') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a03') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a04') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a06') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a07') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a08') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001a09') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0a00') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0a01') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0a02') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0a03') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0a04') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0b00') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0b01') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a0b02') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a1000') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a1001') {goto BYPASS;}
if (substr($in{'test'},0,14) eq 'fefe9c001a1002') {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b07')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b08')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b09')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b0a')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b0b')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b0c')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b0d')   {goto BYPASS;}
if (substr($in{'test'},0,12) eq 'fefe9c001b0e')   {goto BYPASS;}
if (substr($in{'test'},0,10) eq 'fefe9c0020')   {goto BYPASS;}
icom_cmd('test',\%parmref);
my $rsp = '';
my $code = '';
my $outstr = '(none)';
my $stdpl =  'VFO';
if ($in{'state'}) {$stdpl = 'Memory';}
if ($out{'test'}) {
if (length($out{'test'}) > 8) {
$outstr = substr($out{'test'},8);
$code = substr($outstr,0,2);
if (lc($code) eq 'fa') {$rsp = '(bad)';}
}
}
if (!$rsp) {
print "   $instr => $outstr   $stdpl\n";
}
return 0;
BYPASS:
return 1;
}
sub get_files {
my $array = shift @_;
my @filespecs = ();
while (scalar @ARGV)  {push @filespecs,shift @ARGV};
my $errors = 0;
foreach my $fs (@filespecs) {
if (!-e $fs) {
LogIt(1,"GET_FILES l3740:Cannot locate $fs to process!");
$errors++;
next;
}
LogIt(0,"Checking file $fs");
open IN,$fs or LogIt(639,"Cannot open $fs!");
my @records = <IN>;
close IN;
my $ver = $records[0];
if (!$ver) {$ver = '**';}
if (($ver =~ /^\*radioctl/i) or ($ver =~ /^\*3/) ) {
push @{$array},$fs;
}
else {
LogIt(0,"$fs was NOT a radioctl type file. It will be treated as a list of files");
my $recno = 0;
foreach my $rcd (@records) {
$recno++;
chomp $rcd;
if (!$rcd) {next;}
$rcd = Strip($rcd);
if (substr($rcd,0,1) eq '*') {next;}
if (substr($rcd,0,1) eq '#') {next;}
if (!-e $rcd) {
LogIt(1,"Cannot locate file $rcd in record $recno of $fs");
$errors++
}
else {push @{$array},$rcd;}
}
}
}### For all the files specified on the command line
if ($errors) {LogIt(806,"$errors missing files in input file. Please repair before restarting!");}
return 0;
}
sub write_data {
my $outfile  = shift @_;
my $database = shift @_;
my @opt = ();
if ($append) {$nohdr = TRUE;}
if ($keyformat) {push @opt,'keyformat';}
elsif ($posformat) {push @opt,'posformat';}
if (!$showhz) {push @opt,'mhz'};
if ($freqsort) {push @opt,'sort';}
if ($append)   {push @opt,'append';}
if ($nohdr) {push @opt,'nohdr';}
if (looks_like_number($renum)) {
if ($renum < 0) {push @opt,'nochan';}
else {push @opt,"renum=$renum";}
}
if (-e $outfile) {
if ($append) {
LogIt(1,"Data will be appended to existing file $Yellow$outfile");
}
else {
LogIt(1,"existing file $Yellow$outfile$White will be overwritten.");
if (!$overwrite) {
print "   OK (Y/N)=>";
my $answer = <STDIN>;
chomp($answer);
print STDERR "$Eol";
if (uc(substr($answer,0,1)) ne 'Y') {
LogIt(0,"$Bold Output file generation was bypassed!");
return 1;
}
}
}
}
return (write_radioctl($database,$outfile,@opt));
}
sub update_qkey {
my $db = shift @_;
my $optproc = FALSE;
if ($sqkey or $tqkey or $dqkey or $gqkey) {
$optproc = TRUE;
}
if (!$optproc) {return 0;}
my %used_skey = ();
my $last_skey = 0;
if ($sqkey and (!$force)) {
foreach my $rec (@{$db->{'system'}}) {
if (!$rec->{'index'}) {next;}
my $qkey = $rec->{'qkey'};
if (looks_like_number($qkey) and ($qkey >= 0) ) {
$used_skey{$qkey} = TRUE;
}
}
}
foreach my $sysrec (@{$db->{'system'}}) {
if (!$sysrec->{'index'}) {next;}
my $sysno = $sysrec->{'index'};
my $sysname = $sysrec->{'service'};
if (!$sysname) {$sysname = "System $sysno";}
if ($sqkey) {
$last_skey = qkey_proc($sysrec,\%used_skey,'qkey',"$sysname ($sysno)",$last_skey);
}### sqkey
my $site_qk = 0;
my $group_qk = 0;
my $dept_qk = 0;
my %used_site = ();
my %used_dept = ();
my %used_group = ();
if ($tqkey or $gqkey or $dqkey) {
if (!$force) {
if ($tqkey or $dqkey) {
foreach my $rec (@{$db->{'site'}}) {
if (!$rec->{'index'}) {next;}
if ($rec->{'sysno'} != $sysno) {next;}
my $qkey = $rec->{'qkey'};
if (!$qkey) {$qkey = '';}
my $dqkey = $rec->{'dqkey'};
if (!$dqkey) {$dqkey = 0;}
if (looks_like_number($qkey) and ($qkey >= 0)) {
$used_site{$qkey} = TRUE;
}
if (looks_like_number($dqkey) and ($dqkey >= 0)) {
$used_dept{$dqkey} = TRUE;
}
}##### look for keys in sites
}### site key options
if ($gqkey or $dqkey) {
foreach my $rec (@{$db->{'group'}}) {
if (!$rec->{'index'}) {next;}
if ($rec->{'sysno'} != $sysno) {next;}
my $qkey = $rec->{'qkey'};
if (!$qkey) {$qkey = '';}
my $dqkey = $rec->{'dqkey'};
if (!$dqkey) {$dqkey = 0; }
if (looks_like_number($qkey) and ($qkey >= 0)) {
$used_group{$qkey} = TRUE;
}
if (looks_like_number($dqkey) and ($dqkey >= 0)) {
$used_dept{$dqkey} = TRUE;
}
}##### look for keys in groups
}### group key options
}### First pass key inquiry (--FORCE is false)
foreach my $rec (@{$db->{'site'}}) {
if (!$rec->{'index'}) {next;}
if ($rec->{'sysno'} != $sysno) {next;}
if ($sqkey) {
$site_qk = qkey_proc($rec,\%used_site,'qkey',"$sysname ($sysno)",$site_qk);
}### Updating site quickkey
if ($dqkey) {
$dept_qk = qkey_proc($rec,\%used_dept,'dqkey',"$sysname ($sysno)",$dept_qk);
}
}### Cycle through SITE records
}### SITE/DEPT quickkey updates
if ($gqkey or $dqkey) {
foreach my $rec (@{$db->{'group'}}) {
if (!$rec->{'index'}) {next;}
if ($rec->{'sysno'} != $sysno) {next;}
my $groupno = $rec->{'index'};
if ($gqkey) {
$group_qk = qkey_proc($rec,\%used_group,'qkey',"$sysname ($sysno)",$group_qk);
}### Updating group quickkey
if ($dqkey) {
$dept_qk = qkey_proc($rec,\%used_dept,'dqkey',"$sysname ($sysno)",$dept_qk);
}### Updating DEPT quickkey
}#### For each GROUP record
}### GROUP/FREQ process
}### System record loop
return 0;
}
sub qkey_proc {
my $rec = shift @_;
my $used = shift @_;
my $key = shift @_;
my $sysinfo = shift @_;
my $first = shift @_;
if (!$first) {$first = 0;}
my $old_key = $rec->{$key};
if ($force or (!looks_like_number($old_key)) or ($old_key < 0)) {
my $new_key = -1;
foreach my $qk ($first..99) {
if (!$used->{$qk}) {
$new_key = $qk;
last;
}
}
if ($new_key < 0) {
my $rectype = $rec->{'_rectype'};
if (!$rectype) {$rectype = '';}
$rectype = uc($rectype);
my $qt = "$rectype Quick-Key";
if ($key eq 'dqkey') {$qt = "$rectype Department Quick-Key";}
LogIt(1,"$qt overflow for SYSTEM:$sysinfo. Starting again at 0");
$new_key = 0;
%{$used} = ();
$first = 0;
}### Overflow
$rec->{$key} = $new_key;
$used->{$new_key} = TRUE;
$first++;
}### assigning a quickkey
return $first;
}### QKEY_PROC
sub key_proc {
my $keyword = shift @_;
my $sysno = shift @_;
my $newno = shift @_;
my $radsysno = shift @_;
my $type = lc(shift @_);
my $radionum = 0;
my $new_index = 0;
if ($new_index) {
LogIt(0,"checking for existing $keyword block at $new_index");
my @keylist = ();
if ($radsysno) {
@keylist = keys %{$radiodb{$radsysno}{$keyword}};
}
else {
@keylist = keys %radiodb;
}
foreach my $rndx (@keylist) {
my $rno = $radsysno;
if (!$rno) {$rno = $rndx;};
my $radio_addr = $radiodb{$rno}{$keyword}{$rndx}{'block_addr'};
if ($radio_addr and ($new_index eq $radio_addr)) {
$radionum = $rndx;
if (!$radsysno) {$radsysno = $rndx;}
last;
}
}
}
my $changed = FALSE;
if (!$radionum) {
if ($new_index) {LogIt(1,"Did NOT find $new_index for $keyword");exit}
$parmref{'out'} = \%{$new{$sysno}{$keyword}{$newno}};
my $cmd = $create{$type};
my $tflag = $new{$sysno}{$keyword}{$newno}{'trunked'};
if (!$tflag) {$tflag = '';}
if ((lc($tflag) eq 't') and ($type eq 'gin')) {
$cmd = 'AGT';
}
$parmref{'out'} = \%{$new{$sysno}{$keyword}{$newno}};
$parmref{'write'} = TRUE;
if ($doit) {
if( bcd396_cmd($cmd) ){
print "Failed create of $type call\n",
print "'out'->",
Dumper($parmref{'out'}),"\n";
print "cmd=$cmd sysno=$sysno keyword=$keyword newno=$newno ",
"sitecnt=$sitecnt freqcnt=$freqcnt ",
"tfqcnt=$tfqcnt grpcnt=$grpcnt gidcnt=$gidcnt sysgidcnt=$sgidcnt\n";
LogIt(1519,"Could not create new $type block");}
}
else {
LogIt(0," Would have issued BCD396 command $cmd for $type");
$new{$sysno}{$keyword}{$newno}{'block_addr'} = $debug_addr++;
print Dumper($new{$sysno}{$keyword}{$newno}),"\n";
exit;
}
$changed = TRUE;
$radionum = (++$radmaxno{$keyword});
if (defined $radiodb{$radsysno}{$keyword}{$radionum}) {
LogIt(1,"$radionum for $keyword is NOT unique!");
print Dumper(%radmaxno),"\n";
print "radsysno=$radsysno keyword=$keyword radionum=$radionum \n",
Dumper($radiodb{$radsysno}{$keyword}{$radionum}),"\n";
exit;
}
foreach my $key (keys %{$new{$sysno}{$keyword}{$newno}}) {
$radiodb{$radsysno}{$keyword}{$radionum}{$key} =
$new{$sysno}{$keyword}{$newno}{$key};
}
}
else {
LogIt(0, "Found existing $keyword (radio's index=$radionum. Checking for changes\n");
foreach my $key (keys %{$radiodb{$radsysno}{$keyword}{$radionum}}) {
if ($changekey{$key}) {
if ($radiodb{$radsysno}{$keyword}{$radionum}{$key} ne
$new{$sysno}{$keyword}{$newno}{$key}) {
LogIt(0,"$Bold $keyword $key is being changed");
$radiodb{$radsysno}{$keyword}{$radionum}{$key} =
$new{$sysno}{$keyword}{$newno}{$key};
$changed = TRUE;
}
}
else {$new{$sysno}{$keyword}{$newno}{$key} =
$radiodb{$radsysno}{$keyword}{$radionum}{$key};}
}
}
if ($changed) {
$parmref{'out'} = \%{$new{$sysno}{$keyword}{$newno}};
$parmref{'write'} = TRUE;
my $cmd = uc($type);
if ($doit) {
if( bcd396_cmd($cmd) ){LogIt(608,"Could not update $type for system $sysno");}
}
else {
LogIt(0," Would issue bcd396 update command $cmd for $type");
print Dumper($new{$sysno}{$keyword}{$newno}),"\n";
}
}
else {LogIt(0,"No changes needed for New $keyword $sysno\n");}
return $radionum;
}
sub set_group {
my $tag = shift @_;
my $key = 'Other';
if ($tag =~ /law/i) {$key = 'Police';}
elsif ($tag =~ /pd/i) {$key = 'Police';}
elsif ($tag =~ /fire/i) {$key = 'Fire';}
elsif ($tag =~ /fd/i) {$key = 'Fire';}
elsif ($tag =~ /utilit/i) {$key ='Utilities';}
elsif ($tag =~ /public works/i) {$key ='Public_Works';}
elsif ($tag =~ /business/i) {$key ='Business';}
elsif ($tag =~ /emergency/i) {$key ='Police';}
elsif ($tag =~ /interop/i) {$key ='Police';}
elsif ($tag =~ /hospital/i) {$key ='EMS';}
elsif ($tag =~ /ems/i) {$key ='EMS';}
elsif ($tag =~ /med/i) {$key ='EMS';}
elsif ($tag =~ /transport/i) {$key ='Transportation';}
elsif ($tag =~ /bus/i) {$key ='Transportation';}
else {$key = 'Other';}
return $key;
}
sub gps_process {
my $value = shift @_;
my $type = shift @_;
if (!$gps_parms{$type}) {### The user did NOT specify a limit on this type
return TRUE;
}
if (!$value) {return FALSE;}
my ($dec,$dms) = Lat_Lon_Parse($value,$type);
if (!$dec) {return FALSE;}
$dec = abs($dec);
return TRUE;
}
sub grp_process {
my ($recdata,$dqks_status,$type) = @_;
my $add_proc_required = FALSE;
my $qkey = $recdata->{'qkey'};
if ($qkey and looks_like_number($qkey)) {
$qkey = $qkey + 0;
}
else {$qkey = '';}
if ($type =~ /site/i) {$recdata->{'site_qkey'} = $qkey;}
$recdata->{'qkey'} = $qkey;
my $valid = TRUE;
if ($recdata->{'avoid'} =~ /on/i) {
if ($type =~ /site/) {print "L6935: Not valid set due to avoid\n";} 
$valid = FALSE;}
elsif (!looks_like_number($qkey)) {
$valid = FALSE;}
else {
if (scalar keys %{$dqks_status}) {
$valid = $dqks_status->{$qkey};
}
else {$add_proc_required = TRUE;}
}
$recdata->{'valid'} = $valid;
return $add_proc_required;
}
sub check_modulation {
my $mds = lc(Strip(shift @_));
if ($mds == '') {return -1;}
if (defined $rc_hash{$mds}) {
return $rc_hash{$mds};
}
else {return -1;}
}
sub select_radio {
my $radio = lc(shift @_);
if (defined $All_Radios{$radio}) {
foreach my $key (keys %{$All_Radios{$radio}}) {
$radio_def{$key} = $All_Radios{$radio}{$key};
}
$radio_def{'baud'} = $altbaud;
$radio_def{'port'} = $altport;
}
else {LogIt(5759,"$Magenta$radio$White was not defined in the profile");}
return 0;
}
sub set_filespec {
my $filename = shift @_;
my $dirtype = shift @_;
my $radiodef = shift @_;
if ($User_fspec) {return $User_fspec;}
elsif ($User_dir) {return Strip($User_dir) . "/$filename";}
elsif ($radiodef and ($radiodef->{$dirtype})) {
return Strip($radiodef->{$dirtype}) . "/$filename";
}
else {return Strip($RCSettings{$dirtype}) . "/$filename";}
}### Set_filespec
sub help {print "$help\n";exit;}
sub Numerically {
use Scalar::Util qw(looks_like_number);
if (looks_like_number($a) and looks_like_number($b)) { $a <=> $b;}
else {$a cmp $b;}
}
