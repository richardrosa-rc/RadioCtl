#!/usr/bin/perl -w
package bearcat;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(bearcat_cmd) ;
use strict;
use autovivification;
no  autovivification;
use Scalar::Util qw(looks_like_number);
use Data::Dumper;
use Text::ParseWords;
use threads;
use threads::shared;
use Thread::Queue;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );
use radioctl;
use constant BEARCAT_TERMINATOR  => CR;
use constant BEARCAT_GET         => 1;
use constant BEARCAT_SET         => 0;
use constant BEARCAT_VFOCHAN     => 300;
use constant RADIOSCAN           => $rc_hash{'radio scan'};
use constant BC895XLT      => 'BC895XLT';
my %radio_limits = (
&BC895XLT => {'minfreq'  =>  29000000,'maxfreq' => 956000000 ,
'gstart_1' =>  54000001,'gstop_1' => 108000000 ,
'gstart_2' => 512000001,'gstop_2' => 806000000 ,
'origin' => 1,
'maxchan' => 300,
'group' => FALSE,
'sigdet' => 2,
'radioscan' => 2,
},
);
my @beartone   = ("off",
" 67.0"," 71.9"," 74.4"," 77.0"," 79.7",
" 82.5"," 85.4"," 88.5"," 91.5"," 94.8",
" 97.4","100.0","103.5","107.2","110.9",
"114.8","118.8","123.0","127.3","131.8",
"136.5","141.3","146.2","151.4","156.7",
"162.2","167.9","173.8","179.9","186.2",
"192.8","203.5","210.7","218.1","225.7",
"233.6","241.8","250.3",
);
my @tones4gui = ('Off');
my %tone2bear  ;
foreach my $i (0..$#beartone) {
$tone2bear{Strip($beartone[$i])} = $i ;
if ($i) {push @tones4gui,'CTC' . Strip($beartone[$i]);}
}
$tone2bear{" 69.3"} = 2;
$tone2bear{"159.8"} = 25;
$tone2bear{"165.5"} = 27;
$tone2bear{"171.3"} = 28;
$tone2bear{"177.3"} = 29;
$tone2bear{"183.5"} = 30;
$tone2bear{"189.9"} = 31;
$tone2bear{"196.6"} = 32;
$tone2bear{"199.5"} = 32;
$tone2bear{"206.6"} = 33;
$tone2bear{"229.1"} = 36;
$tone2bear{"254.1"} = 38;
$models{'bearcat'}{BC895XLT} = 1;
my $to_get = -1;
my @radiostates = ('scan',
'mem',
'srch',
'lim-hold',
'wx-scan',
'wx-hold',
'prog',
'id-srch',
'id-srch-hold',
'id-scan',
'id-manual',
'id-lock',
'srch-ctl',
'prog-ctcss',
'wx-alert',
'freq-send',
'auto-store',
'vfo',
);
my %state2bear = ();
foreach my $ndx (0..$#radiostates) {$state2bear{$radiostates[$ndx]} = $ndx;}
my $instring = '';
my $model = BC895XLT;
my $warn = TRUE;
my $chanper = 30;
my %state_save = (
'state' => '',
'mode'  => '',
);
my @ranges = ( {'low' =>  29000000,'high' =>  54000000,},
{'low' => 108000000,'high' => 174000000,},
{'low' => 216000000,'high' => 400000000,},
{'low' => 406000000,'high' => 512000000,},
{'low' => 806000000,'high' => 868000000,},
{'low' => 894000000,'high' => 956000000,},
);
my $protoname = 'bearcat';
use constant PROTO_NUMBER => 4;
$radio_routine{$protoname} = \&bearcat_cmd;
$valid_protocols{'bearcat'} = TRUE;
TRUE;
sub bearcat_cmd {
my ($cmdcode,$parmref) = @_;
my $cmd = lc($cmdcode);
my $defref    = $parmref->{'def'};
my $out  = $parmref->{'out'};
my $outsave = $out;
my $portobj = $parmref->{'portobj'};
my $db = $parmref->{'database'};
if ($db) {
}
else {$db = '';}
my $write = $parmref->{'write'};
if (!$write) {$write = FALSE;}
my $in   = $parmref->{'in'};
if ($in) {
}
else {$in = '';}
my $insave = $in;
my $delay = 100;
$parmref->{'rc'} = $GoodCode;
$parmref->{'term'} = BEARCAT_TERMINATOR;
my $parmstr = '';
if ($Debug3) {DebugIt("Bearcat 908:cmdcode=$cmdcode parmref=$parmref");}
if ($cmd eq 'init') {
%state_save = ('state' => '','mode' => '');
my $rc = 0;
@gui_modestring = ('FM','AM');
@gui_bandwidth = ();
@gui_adtype = ();
@gui_attstring = ();
@gui_tonestring = ();
foreach my $key (keys %{$radio_limits{$model}}) {
$defref->{$key} = $radio_limits{$model}{$key};
}
bearcat_cmd('MD',$parmref);
if ($out->{'state'} =~ /vfo/i) {bearcat_cmd('getvfo',$parmref);}   
return ($parmref->{'rc'} = $rc);
}
elsif ($cmdcode eq 'autobaud') {
my $model_save = BC895XLT;
my @allports = ();
if ($in->{'noport'} and $defref->{'port'}) {push @allports,$defref->{'port'};}
else {
@allports = glob("/dev/ttyUSB*");
}
my @allbauds = ();
if ($in->{'nobaud'}) {push @allbauds,$defref->{'baudrate'};}
else {push @allbauds,9600;}
@allbauds = sort {$b <=> $a} @allbauds;
@allports = sort {$b cmp $a} @allports;
PORTLOOP:
foreach my $port (@allports) {
my $portobj =  Device::SerialPort->new($port) ;
if (!$portobj) {next;}
$parmref->{'portobj'} = $portobj;
$portobj->user_msg("ON");
$portobj->databits(8);
$portobj->handshake('none');
$portobj->read_const_time(100);
$portobj->write_settings || undef $portobj;
$portobj->read_char_time(0);
foreach my $baud (@allbauds) {
$portobj->baudrate($baud);
$warn = FALSE;
my $rc = bearcat_cmd('md',$parmref);
$warn = TRUE;
if (!$rc) {### command succeeded
$defref->{'baudrate'} = $baud;
$defref->{'port'} = $port;
$portobj->close;
$parmref->{'portobj'} = undef;
return ($parmref->{'rc'} = $GoodCode);
}
}
$portobj->close;
$parmref->{'portobj'} = undef;
}
return ($parmref->{'rc'} = 1);
}
elsif (($cmd eq 'manual') or ($cmd eq 'meminit')) {
my $rc = $GoodCode;
my %myin = ('key' => '1');
$parmref->{'in'} = \%myin;
if (bearcat_cmd('key',$parmref)) {return $parmref->{'rc'}}
$parmref->{'write'} = FALSE;
bearcat_cmd('MD',$parmref);
bearcat_cmd('MA',$parmref);
$parmref->{'in'} = $insave;
return ($parmref->{'rc'} = $rc)
}
elsif ($cmd eq 'vfoinit') {
if ($Debug2) {DebugIt("BEARCAT l1087:Got VFOINIT command");}
return bearcat_cmd('getvfo',$parmref);
}
elsif ($cmd     eq 'scan') {
if (bearcat_cmd("MD",$parmref)) {return $parmref->{'rc'};} ;
if ($state_save{'state'} ne 'scan') {
my %myin = ('key' => 0, 'hold' => 0, 'keyparm' => 0);
$parmref->{'in'} = \%myin;
bearcat_cmd("KEY",$parmref);
$parmref->{'in'} = $insave;
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'poll') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getvfo') {
bearcat_cmd('MD',$parmref);
if ($state_save{'state'} !~ /vfo/i) {
return 0;
}
bearcat_cmd('SG',$parmref);
bearcat_cmd('SQ',$parmref);
if (!$out->{'sql'}) {$out->{'signal'} = 0;}
bearcat_cmd('RM',$parmref);
$parmref->{'write'} = FALSE;
$out->{'sqtone'} = 'Off';
return ($parmref->{'rc'});
}
elsif ($cmd eq 'getsig') {
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
if (bearcat_cmd('sq',$parmref)) {return ($parmref->{'rc'});}
if ($out->{'sql'}) {
bearcat_cmd('sg',$parmref);
}
return ($parmref->{'rc'});
}
elsif ($cmd eq 'getmem') {
if ($Debug2) {DebugIt("BEARCAT l1234: 'getmem' started");}
my $startstate = $progstate;
my $maxcount = 999;
my $maxchan = $defref->{'maxchan'};
my $channel =  $defref->{'origin'};
my $nodup = FALSE;
my $noskip = FALSE;
my $options = $parmref->{'options'};
if ($options) {
if ($options->{'count'}) {$maxcount = $options->{'count'};}
if ($options->{'firstchan'} and ($options->{'firstchan'} > 0)) {
$channel = $options->{'firstchan'};
}
if ($options->{'lastchan'} and ($options->{'lastchan'} > 0)) {
$maxchan = $options->{'lastchan'};
}
if ($options->{'noskip'}) {$noskip = TRUE;}
if ($options->{'nodup'}) {$nodup = TRUE;}
}
my %duplist = ();
if ($nodup) {
foreach my $rec (@{$db->{'freq'}}) {
my $ch = $rec->{'channel'};
if ((defined $ch) and (looks_like_number($ch))) {
$ch = $ch + 0;
$duplist{$ch} = $rec->{'index'}
}### Found a channel number
}### Looking through the current database
}### NODUP specified
my $count = 0;
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
my $sysno = $db->{'system'}[1]{'index'};
if ($sysno and $nodup) {
}
else {
my %sysrec = ('systemtype' => 'CNV','service' => "Bearcat model $model", 'valid' => TRUE);
$sysno = add_a_record($db,'system',\%sysrec,$parmref->{'gui'});
}
my $igrp = 0;
my $grpndx = 0;
CHANLOOP:
while ($channel <= $maxchan) {
if (!$grpndx) {
my %grouprec = ('sysno' =>$sysno,
'service' => "Bearcat $model Group/Bank:$igrp",
'valid' => TRUE
);
$grpndx = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$igrp++;
}### New group creation
$vfo{'channel'} = $channel;
$vfo{'groupno'} = $grpndx;
threads->yield;
if ($progstate ne $startstate) {
LogIt(0,"\nBearcat l1359: Exited loop as progstate changed");
last CHANLOOP;
}
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green" . sprintf("%02.2u",$channel) .$Reset ;
}
$myout{'valid'} = FALSE;
$myout{'mode'} = 'auto';
$myout{'frequency'} = 0;
$myout{'sqtone'} = 'off';
$myout{'dlyrsm'} = 0;
$myout{'atten'} = 0;
$myout{'service'} = '';
$myout{'tgid_valid'} = FALSE;
$myout{'channel'} = $channel;
$myout{'groupno'} = $grpndx;
$myin{'channel'} = $channel;
if ($nodup and $duplist{$channel}) {
if ($Debug2) {DebugIt("BEARCAT l1392: Skipping duplicate channel $channel");}
}
else {
my $rc = bearcat_cmd('PM',$parmref);
if ($rc) {
if ($Debug2) {DebugIt("BEARCAT:line 1405: Return code $rc from 'PM'");}
next CHANLOOP;
}
else {
my $freq = $myout{'frequency'} + 0;
if ($noskip or $freq) {
if (!$freq) {$myout{'valid'} = FALSE;}
my $recno = add_a_record($db,'freq',\%myout,$parmref->{'gui'});
$vfo{'index'} = $recno;
$count++;
if ($count >= $maxcount) {last CHANLOOP;}
}### not skipping
}### Good return code from memory read routine
}### Not skipping duplicates
$channel++;
if (!($channel % $chanper)) {
$grpndx = 0;
}
}### Channel loop
print STDERR "\n";
$parmref->{'out'} = $outsave;
$parmref->{'in'} = $insave;
$parmref->{'write'} = $writesave;
$out->{'count'} = $count;
$out->{'sysno'} = $sysno;
return ($parmref->{'rc'} );
}### GETMEM
elsif ($cmdcode eq 'setmem') {
my $max_count = 99999;
my $options = $parmref->{'options'};
if ($options->{'count'}) {$max_count = $options->{'count'};}
my %in = ();
$parmref->{'in'} = \%in;
my $rc = bearcat_cmd("MD",$parmref);
if (!$rc) {
if ($state_save{'state'} eq 'prog') {
$in{'key'} = 13;
$in{'hold'} = FALSE;
$in{'keyparm'} = '';
$rc = bearcat_cmd("KEY",$parmref);
}
}
my %found_chan = ();
my $count = 0;
foreach my $frqrec (@{$db->{'freq'}}) {
if (!$frqrec->{'index'}) {next;}
my $recno = $frqrec->{'_recno'};
if (!$recno) {$recno = '??';}
my $emsg = "in record $recno";
if ($frqrec->{'tgid_valid'}) {next;}
my $channel = $frqrec->{'channel'};
if ((!looks_like_number($channel)) or ($channel < 0) ) {
print STDERR "\nChannel number $channel $emsg is not defined. Skipped\n";
next;
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
print STDERR "\nChannel number $channel $emsg is not within range of radio. Skipped\n";
next;
}
if ($found_chan{$channel}) {
LogIt(1,"\nChannel $channel was found twice $emsg. Second iteration skipped!");
next;
}
$found_chan{$channel} = TRUE;
my $freq = $frqrec->{'frequency'};
if (!looks_like_number($freq)) {next;}
my $clear = FALSE;
if ($freq) {
if (!check_range($freq,$defref)) {next;}
}
else {$clear = TRUE;}
print STDERR "\rSETMEM: Writing channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset,
" freq=>$Yellow",rc_to_freq($freq),$Reset;
%in = ();
foreach my $key (keys %{$frqrec}) {
$in{$key} = $frqrec->{$key};
}
my $rc = 0;
$parmref->{'write'} = TRUE;
if (!$rc) {$rc = bearcat_cmd('PM',$parmref);}
if (!$rc and $freq) {
$rc = bearcat_cmd('LO',$parmref);
if (!$rc) {$rc = bearcat_cmd('DL',$parmref);}
set_tone($in->{'sqtone'},$parmref);
}#$### Freq is NOT 0
if (!$rc) {$count++;}
if ($count >= $max_count) {
LogIt(0,"$Eol$Bold Store terminated due to maximum record count reached");
last;
}
}### For each FREQ record
LogIt(0,"$Eol$Bold$Green$count$White Records stored.");
return 0;
}### SETMEM
elsif ($cmd eq 'selmem') {
if (!$in->{'channel'}) {
add_message("BEARCAT_CMD:Invalid channel 0 for SELMEM");
return ($parmref->{'rc'} = $ParmErr);
}
my $channel = $in->{'channel'};
if (!looks_like_number($channel)) {
add_message("BEARCAT l1681:Channel $channel is not numeric.");
return ($parmref->{'rc'} = $ParmErr);
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
add_message("BEARCAT l1686:Channel $channel out of range for radio");
return ($parmref->{'rc'} = $NotForModel);
}
bearcat_cmd('MA',$parmref);
if ($state_save{'state'} ne 'mem') { bearcat_cmd('MD',$parmref);}
if ($parmref->{'rc'} == $GoodCode) {
if (!$out->{'frequency'}) {$parmref->{'rc'} = $EmptyChan;}
}
return $parmref->{'rc'};
}
elsif ($cmd eq 'setvfo') {
my $freq = $in->{'frequency'};
if (!$freq) {
add_message("BEARCAT_CMD:Invalid frequency 0 for SETVFO");
return ($parmref->{'rc'} = $ParmErr);
}
if (!check_range($freq,$defref)) {
add_message(rc_to_freq($freq) . " MHz is NOT valid for this radio");
return ($parmref->{'rc'} = $NotForModel);
}
$parmref->{'write'} = TRUE;
$parmref->{'_nomsg'} = TRUE;
if (bearcat_cmd('RF',$parmref)) {
bearcat_cmd('manual',$parmref);
$parmref->{'write'} = TRUE;
$parmref->{'_nomsg'} = FALSE;
if (bearcat_cmd('RF',$parmref)) {return $parmref->{'rc'};}
}
$parmref->{'_nomsg'} = FALSE;
usleep(100);
$parmref->{'write'} = FALSE;
bearcat_cmd('SG',$parmref);
if ($freq != $out->{'frequency'}){
LogIt(1,"BEARCAT l1715:Requested $freq but got $out->{'frequency'} set instead");
}
if ($state_save{'state'} ne 'vfo') { bearcat_cmd('MD',$parmref);}
return  ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'getglob') {
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'setglob') {
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = TRUE;
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'getsrch') {
return $NotForModel;
}
elsif ($cmdcode eq 'setsrch') {
return $NotForModel;
}
elsif ($cmdcode eq 'getinfo') {
bearcat_cmd('init',$parmref);
$out->{'chan_count'} = $defref->{'maxchan'};
$out->{'model'} = $model;
return ($parmref->{'rc'});
}
elsif ($cmd     eq 'test') {
}
elsif ($cmd eq 'ac') {
add_message("Bearcat_CMD:AC command is NOT allowed from RadioCtl");
return ($parmref->{'rc'} = 2);
}
elsif ($cmd eq 'af') {
}
elsif ($cmd eq 'al') {
}
elsif ($cmd eq 'at') {
}
elsif ($cmd eq 'ar') {
if ($parmref->{'write'}) {
if (!defined $in->{'record'}) {
}
my $record = lc(Strip($in->{'record'}));
if ($record) {$parmstr = 'N';}
else {$parmstr = 'F';}
}
}
elsif ($cmd eq 'BT') { }
elsif ($cmd eq 'cc') {
}
elsif ($cmd eq 'cd') {
if ($parmref->{'write'}) {
$parmstr = $in->{'_cdtone'};
}
}
elsif ($cmd eq 'cs') {
if ($parmref->{'write'}) {
$parmstr = $in->{'_cstone'};
}
}
elsif ($cmd eq 'ct') {
if ($parmref->{'write'}) {$parmstr = $in->{'_ctstate'};}
}### CT preprocess
elsif ($cmd eq 'dl') {
if ($parmref->{'write'}) {
if (!defined $in->{'dlyrsm'}) {
}
my $dlyrsm = $in->{'dlyrsm'};
if ($dlyrsm and (looks_like_number($dlyrsm)) and ($dlyrsm > 0 )) {$parmstr = 'N';}
else {$parmstr = 'F';}
}
}### DL preprocess
elsif ($cmd eq 'ds') {
}
elsif ($cmd eq 'fi') { }
elsif ($cmd eq 'ic') {
}
elsif ($cmd eq 'id') {
}
elsif ($cmd eq 'il') {
}
elsif ($cmd eq 'is') {
}
elsif ($cmd eq 'LL') { }
elsif ($cmd eq 'key') {
if (!defined $in->{'key'}) {
}
my $key = $in->{'key'};
if (!looks_like_number($key)) {
LogIt(1,"BEARCAT-CMD:Key command, invalid key number=> $key");
return ($parmref->{'rc'} = 2);
}
$parmstr = sprintf("%02.2u",$key);
if ($in->{'hold'}) {$parmstr = $parmstr . "H";}
if ($in->{'keyparm'}) {$parmstr = "$parmstr $in->{'keyparm'}";}
}
elsif ($cmd eq 'lo') {
if ($parmref->{'write'}) {
if (!defined $in->{'valid'}) {
}
if ($in->{'valid'}) {$parmstr = 'F';}
else {$parmstr = 'N';}
}
}### LO command
elsif ($cmd eq 'lt') { }
elsif ($cmd eq 'lu') { }
elsif ($cmd eq 'ma') {
$out->{'channel'} = 0;
$out->{'frequency'} = 0;
$out->{'valid'} = FALSE;
$out->{'sqtone'} = 'Off';
$out->{'trunk'} = FALSE;
$out->{'atten'} = 0;
$out->{'dlyrsm'} = 0;
if ( (defined $in->{'channel'}) and ($in->{'channel'})) {
my $channel = $in->{'channel'};
if ($channel > $defref->{'maxchan'}) {
LogIt(1,"channel $channel exceeds radio memory of $defref->{'maxchan'}");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = sprintf("%03.3u",$channel);
}
}
elsif ($cmd eq 'md') {
}
elsif ($cmd eq 'MU') { }
elsif ($cmd eq 'PC') { }
elsif ($cmd eq 'PI') { }
elsif ($cmd eq 'pm') {
my $channel = $in->{'channel'};
if (!$channel) {
LogIt(1,"BEARCAT_CMD channel = 0 for PM");
return ($parmref->{'rc'} = 2);
}
if ($channel > $defref->{'maxchan'}) {
LogIt(1,"channel $channel exceeds radio memory of $defref->{'maxchan'}");
return ($parmref->{'rc'} = 2);
}
$parmstr = sprintf("%03.3u",$channel);
$out->{'channel'} = $channel;
$out->{'frequency'} = 0;
$out->{'valid'} = FALSE;
$out->{'sqtone'} = 'Off';
$out->{'trunk'} = FALSE;
$out->{'atten'  } = 0;
$out->{'dlyrsm'} = 0;
if ($parmref->{'write'}) {
$parmstr = "$parmstr " . freq_rc2bear($in->{'frequency'});
}
}
elsif ($cmd eq 'PR') { }
elsif ($cmd eq 'QU') { }
elsif ($cmd eq 'rf') {
if ($parmref->{'write'}) {
my $freq = $in->{'frequency'};
if (!$freq) {
LogIt(1,"BEARCAT-CMD:RF command, Frequency CANNOT be 0");
return ($parmref->{'rc'} = 2);
}
$parmstr = freq_rc2bear($freq);
}
}
elsif ($cmd eq 'RG') { }
elsif ($cmd eq 'RI') { }
elsif ($cmd eq 'rm') {
}
elsif ($cmd eq 'SB') { }
elsif ($cmd eq 'sg') {
}
elsif ($cmd eq 'SI') { }
elsif ($cmd eq 'sq') {
}
elsif ($cmd eq 'SS') { }
elsif ($cmd eq 'ST') { }
elsif ($cmd eq 'TB') { }
elsif ($cmd eq 'TD') { }
elsif ($cmd eq 'TR') { }
elsif ($cmd eq 'VR') { }
elsif ($cmd eq 'WI') { }
else {
add_message("Warning! Bearcat command code $cmd no preprocess!");
}
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => BEARCAT_TERMINATOR,
'delay' => $delay,
'resend' => 0,
'debug' => 0,
'fails' => 1,
'wait' => 30,
);
my $retry = 1;
RESEND:
my $outstr = uc($cmd);
if ($cmdcode eq 'test') {$outstr = $parmstr}
else {
$outstr = Strip("$outstr$parmstr");
}
if ($Debug3) {DebugIt("BEARCAT l2508:sent =>$outstr");}
my $sent = $outstr;
$outstr = $outstr . BEARCAT_TERMINATOR;
WAIT:
if (radio_send(\%sendparms,$outstr)) {
if ($cmdcode eq 'poll') {return ($parmref->{'rc'} = $GoodCode);}
if (!$outstr) {
add_message("Radio did not respond to $sent correctly...");
LogIt(1,"Bearcat: No response to $sent");
$defref->{'rsp'} = 0;
return ($parmref->{'rc'} = $ParmErr);
}
else {
if ($defref->{'rsp'}) {$defref->{'rsp'}++;}
else {
$defref->{'rsp'} = 1;
if ($warn) {
LogIt(1,"no response to $outstr");
add_message("BEARCAT_CMD l2484:Radio is not responding...");
}
}
return ($parmref->{'rc'} = $CommErr);
}
}### Radiosend returned error
$instring = $sendparms{'rcv'};
if (!defined $instring) {$instring = '';}
$parmref->{'rc'} = $GoodCode;
if ($Debug3) {DebugIt("Bearcat 2496:radio returned $instring");}
if ($defref->{'rsp'}) {add_message("Radio is responding again...");}
$defref->{'rsp'} = 0;
if ($instring eq 'ERR') {
if ($warn) {
add_message("$Red$sent$White not recognized by Bearcat.");
return ($parmref->{'rc'} = $NotForModel);
}
else {return $GoodCode;}
}
elsif ($instring eq 'NG') {### command format problem
if (!$parmref->{'_nomsg'}) {
add_message("$sent was rejected by Radio...");
}
return ($parmref->{'rc'} = $ParmErr);
}
elsif (($instring eq 'FER') or ($instring eq 'ORER')) {### Timing issues
if ($retry) {
add_message("$sent caused timing issues. Retrying..");
$retry = 0;
goto RESEND;
}
else {
add_message("$sent terminated due to timing issues");
return ($parmref->{'rc'} = $CommErr);
}
}
elsif ($instring eq 'OK') {
if ($Debug3) {DebugIt("Bearcat 2605:Got OK response to $cmd");}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'ac') {
}
elsif ($cmd eq 'af') {
}
elsif ($cmd eq 'al') {
}
elsif ($cmd eq 'ar') {
if ($instring eq 'OK') { }
else {
if (substr($instring,0,2) ne 'AR') {
add_message("BEARCAT_CMD-AR:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
if (substr($instring,2,1) eq 'F') {$out->{'record'} = FALSE;}
elsif (substr($instring,2,1) eq 'N') {$out->{'record'} = TRUE;}
else {
add_message("BEARCAT_CMD-AR:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
}
}### AR postprocess
elsif ($cmd eq 'at') {
}
elsif ($cmd eq 'bt') {
}
elsif ($cmd eq 'cc') {
}### CTCSS decode
elsif ($cmd eq 'cd') {
if ($instring =~ /ok/i) { }   
else {$out->{'_cdtone'} = substr($instring,2);}
}
elsif ($cmd eq 'cs') {
if ($instring eq 'OK') { }
else {
if (substr($instring,0,2) ne 'CS') {
add_message("BEARCAT_CMD-CS:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
$out->{'_cstone'} = Strip(substr($instring,2));
}
}### CS command process
elsif ($cmd eq 'ct') {
if ($instring eq 'OK') { }
else {
if (substr($instring,0,2) ne 'CT') {
add_message("BEARCAT_CMD-CT:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
$out->{'_ctstate'} = substr($instring,2,1);
}
}### CT process
elsif ($cmd eq 'dl') {
if ($instring eq 'OK') { }
else {
if (substr($instring,0,2) ne 'DL') {
add_message("BEARCAT_CMD-DL:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
if (substr($instring,2,1) eq 'F') {$out->{'dlyrsm'} = 0;}
elsif (substr($instring,2,1) eq 'N') {$out->{'dlyrsm'} = 1;}
else {
add_message("BEARCAT_CMD-DL:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
}
}## DL post process
elsif ($cmd eq 'ds') {
}
elsif ($cmd eq 'fi') { }
elsif ($cmd eq 'ic') {
}
elsif ($cmd eq 'id') {
}
elsif ($cmd eq 'il') {
}
elsif ($cmd eq 'is') {
}
elsif ($cmd eq 'LL') { }
elsif ($cmd eq 'key') {
if ($instring ne 'OK') {$parmref->{'rc'} = $OtherErr;}
}
elsif ($cmd eq 'lo') {
if ($instring eq 'OK') { }
else {
if (substr($instring,0,2) ne 'LO') {
add_message("BEARCAT_CMD-LO:Got return of $instring");
return ($parmref->{'rc'} = $OtherErr);
}
if (substr($instring,2,1) eq 'F') {$out->{'valid'} = TRUE;}
elsif (substr($instring,2,1) eq 'N') {$out->{'valid'} = FALSE;}
else {
add_message("BEARCAT_CMD-LO:Got return of $instring");
return ($parmref->{'rc'} = $OtherErr);
}
}
}### LO command
elsif ($cmd eq 'LT') { }
elsif ($cmd eq 'LU') { }
elsif (($cmd eq 'ma') or ($cmd eq 'pm')) {
if ($Debug3) {DebugIt("Bearcat 2911: $cmd returned $instring");}
return parm_proc($parmref,$cmd);
}
elsif ($cmd eq 'md') {
if (substr($instring,0,2) ne 'MD') {
LogIt(1,"BEARCAT_CMD l2715: MD:Got return of $instring");
return ($parmref->{'rc'} = $OtherErr);
}
if (length($instring) > 2) {
my $state = Strip(substr($instring,2));
$out->{'state'} = $radiostates[$state];
if (!defined $out->{'state'}) {
LogIt(1,"BEARCAT_CMD l2860:No STATE name for state $state!");
return ($parmref->{'rc'} = $OtherErr);
}
$state_save{'state'} = $out->{'state'};
}
else {
if ($warn) {
LogIt(1,"BEARCAT_CMD l2868:MD did not return any state number");
}
return ($parmref->{'rc'} = $OtherErr);
}
}
elsif ($cmd eq 'MU') { }
elsif ($cmd eq 'PC') { }
elsif ($cmd eq 'PI') { }
elsif ($cmd eq 'PR') { }
elsif ($cmd eq 'QU') { }
elsif ($cmd eq 'rf') {
if ($instring eq 'OK') { }
else {
if (substr($instring,0,2) ne 'RF') {
add_message("BEARCAT_CMD-RF:Got return of $instring");
return ($parmref->{'rc'} = 5);
}
$out->{'frequency'} = Strip(substr($instring,2)) . '00';
}
}
elsif ($cmd eq 'RG') { }
elsif ($cmd eq 'RI') { }
elsif ($cmd eq 'rm') {
if ($Debug3) {DebugIt("Bearcat 3002: $cmd returned $instring");}
my @flds = split " ",Strip($instring);
if ($flds[0] ne 'RM') {
LogIt(1,"BEARCAT_CMD-RM:Got $flds[0] instead of RM");
return ($parmref->{'rc'} = $OtherErr);
}
$out->{'mode'} = 'FMn';
if ($flds[1] =~ /wfm/i) {$out->{'mode'} = 'FMw';}
elsif ($flds[1] =~ /am/i) {$out->{'mode'} = 'AM';}
}
elsif ($cmd eq 'SB') { }
elsif ($cmd eq 'sg') {
return (parm_proc($parmref,$cmd));
}
elsif ($cmd eq 'SI') { }
elsif ($cmd eq 'sq') {
if ($instring eq '+') {
$out->{'sql'} = TRUE;
}
elsif ($instring eq '-') {
$out->{'sql'} = FALSE;
}
else {
LogIt(1,"unexpected value $instring for SQ. Waiting a bit...");
$outstr = '';
goto WAIT;
}
}
elsif ($cmd eq 'SS') { }
elsif ($cmd eq 'ST') { }
elsif ($cmd eq 'TB') { }
elsif ($cmd eq 'TD') { }
elsif ($cmd eq 'TR') { }
elsif ($cmd eq 'VR') { }
elsif ($cmd eq 'WI') { }
else {
add_message("Bearcat got response to $cmd. Need handler!");
}
$parmref->{'rsp'} = FALSE;
return $parmref->{'rc'};
}
sub parm_proc {
my $parmref = shift @_;
my $cmd     = shift @_;
my $out = $parmref->{'out'};
my $in  = $parmref->{'in'};
my @parms = split " ",$instring;
my %keytrans = ('C' => 'channel',
'F' => 'frequency',
'D' => 'dlyrsm',
'A' => 'amp'  ,
'N' => 'sqtone',
'T' => 'trunk',
'R' => 'record',
'L' => 'valid',
'S' => 'signal',
);
foreach my $word (@parms) {
my ($ky,$value) = split //,Strip($word),2;
my $key = $keytrans{$ky};
if (!$key) {
LogIt(1,"BEARCAT_CMD-PM/MA-no process for key=>$ky instr=>$instring");
next;
}
if ($value eq 'N') {$value = TRUE;}
elsif ($value eq 'F') {$value = FALSE;}
if ($key eq 'channel') {
if (($cmd eq 'pm') and ($value != $in->{'channel'})) {
add_message("BEARCAT_CMD-PM/PA:Requested channel " . $in->{'channel'} .
" but got $value!");
return ($parmref->{'rc'} = $OtherErr);
}
}
elsif ($key eq 'frequency') {
$value = $value . '00';
}
elsif ($key eq 'valid') {$value = !$value;}
elsif ($key eq 'dlyrsm') {
if ($value) {$value = 1;      }
else {$value = 0;    ;}
}
elsif ($key eq 'atten') {
if ($value) {$value = 1;}
else {$value = 0;}
}
elsif ($key eq 'tone') {
if (looks_like_number($value)) {
$value = $value + 0;
if ($value) {
$value = 'CTC' . Strip($beartone[$value]);
}
else {$value = 'Off';}
}
else {
LogIt(1,"BEARCAT l3077:Non-Numeric Tone code $value");
next;
}
}
elsif ($key eq 'signal') {
if (looks_like_number($value)) {
$value = $value + 0;
$out->{'rssi'} = $value;
my @rssi2sig = (0,15,17,19,21,22,23,24,25,26);
my @meter =    (0, 1, 2, 3, 4, 5, 5, 5, 5, 5);
my $signal = 0;
foreach my $cmp (@rssi2sig) {
if (!$cmp) {next;}
if ($value < $cmp) {last};
$signal++;
}
$out->{'signal'} = $signal;
$out->{'meter'} = $meter[$signal];
}
else {
LogIt(1,"BEARCAT_CMD-SG:Non-Numeric signal value $value");
next;
}
}
$out->{$key} = $value;
}
return ($parmref->{'rc'} = 0);
}
sub set_tone {
my $sqtone = shift @_;
my $parmref = shift @_;
my $btone = '00';
my $tstate = 'F';
if ($sqtone and ($sqtone =~ /ctc/i)) {
my ($tt,$tone) = Tone_Xtract($sqtone);
$btone = $tone2bear{$tone};
if ($btone) {
$btone = sprintf("%02.2u",$btone);
$tstate = 'N';
}
else {
LogIt(1,"BEARCAT 3225:No decode for tone $tt");
$btone = '00';
}
}### Tone is a CTC type of tone
my $in = $parmref->{'in'};
$in->{'_cstone'} = $btone;
$in->{'_cstate'} = $tstate;
$parmref->{'write'} = TRUE;
$parmref->{'_nomsg'} = TRUE;
bearcat_cmd('CS',$parmref);
bearcat_cmd('CT',$parmref);
$parmref->{'_nomsg'} = FALSE;
}
sub freq_ok {
my $frq = shift @_;
foreach my $i (0..$#ranges) {
if ( ($frq >= $ranges[$i]{'low'}) and ($frq <= $ranges[$i]{'high'})) {
return 0;
}
}
return 1;
}
sub freq_rc2bear {
my $rcfrq = shift @_;
return substr(sprintf("%011.11ld",$rcfrq),1,8);
}
sub freq_bear2rc {
my $bearfrq = shift @_;
return $bearfrq . '00';
}
