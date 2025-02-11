#!/usr/bin/perl -w
package kenwood;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(kenwood_cmd
) ;
use strict;
use autovivification;
no  autovivification;
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw( time usleep ualarm gettimeofday tv_interval );
use Data::Dumper;
use Text::ParseWords;
use radioctl;
my $light_on = FALSE;
use constant THF6A => 'TH-F6';
use constant THG71 => 'TH-G71';
use constant THD74 => 'TH-D74';
use constant KENWOOD_TERMINATOR  => CR;
use constant KENWOOD_GET         => 1;
use constant KENWOOD_SET         => 0;
use constant KENMODE_FMN     => 0;
use constant KENMODE_FMW     => 1;
use constant KENMODE_AM      => 2;
use constant KENMODE_LSB     => 3;
use constant KENMODE_USB     => 4;
use constant KENMODE_CW      => 5;
my %steps = (
0 => {'step' =>  5000, 'low'=>         0, 'high' => 470000000},
1 => {'step' =>  6250, 'low'=>         0, 'high' => 470000000},
2 => {'step' =>  8330, 'low'=> 108000000, 'high' => 137000000},
3 => {'step' =>  9000, 'low'=>    100000, 'high' =>   1800000},
4 => {'step' => 10000, 'low'=> 470000000, 'high' =>1299900001},
5 => {'step' => 12500, 'low'=> 470000000, 'high' =>1299900001},
6 => {'step' => 15000, 'low'=>         0, 'high' => 470000000},
7 => {'step' => 20000, 'low'=> 470000000, 'high' =>1299900001},
8 => {'step' => 25000, 'low'=> 470000000, 'high' =>1299900001},
9 => {'step' => 30000, 'low'=> 470000000, 'high' =>1299900001},
a => {'step' => 50000, 'low'=> 470000000, 'high' =>1299900001},
b => {'step' =>100000, 'low'=> 470000000, 'high' =>1299900001},
);
my @modes = (
'FM' ,
'WF' ,
'AM ',
'LS',
'US',
'CW ',
);
my @kenctc = ('Off',
'67.0', '69.3', '71.9', "74.4", "77.0", "79.7", "82.5", "85.4", "88.5", "91.5",
"94.8", "97.4","100.0","103.5","107.2","110.9","114.8","118.8","123.0","127.3",
"131.8","136.5","141.3","146.2","151.4","156.7","162.2","167.9","173.8","179.9",
"186.2","192.8","203.5","206.5","210.7","218.1","225.7","229.1","233.6","241.8",
"250.3","254.1",
);
my %ctcrev = ();
foreach my $i (1..$#kenctc) {$ctcrev{$kenctc[$i]} = $i}
$ctcrev{'159.8'} = 126;
$ctcrev{"165.5"} = 128;
$ctcrev{"171.3"} = 129;
$ctcrev{"177.3"} = 130;
$ctcrev{"183.5"} = 131;
$ctcrev{"189.9"} = 132;
$ctcrev{"196.6"} = 133;
$ctcrev{"199.5"} = 133;
my %revdcs = (
'006' => '023',
'007' => '023',
'015' => '023',
'017' => '023',
'021' => '023',
'050' => '051',
'141' => '143',
'214' => '223',
);
my $model = THF6A;
my $warn = TRUE;
my $chanper = 50;
my %state_save = (
'state' => '',
'mode'  => '',
'atten' => -1,
'vfonum' => 1,
);
my @ken2state = ('vfo','mem','call','fine','info');
my %state2ken = ('vfo' => 0, 'mem' => 1, 'call' => 2, 'fine' => 3, 'info' => 4);
my @vfo_limits = ();
my %splitdb = ();
my %radio_limits = (
&THF6A => {'minfreq'  =>    100000,'maxfreq' =>1299900000 ,
'maxchan'  => 399,
'origin'   => 0,
'sigdet'   => 1,
},
&THG71 => {'minfreq'  => 144000000,'maxfreq' => 450000000 ,
'gstart_1' => 148000001,'gstop_1' => 438000000 ,
'maxchan'  => 199,
'origin'   => 0,
'sigdet'   => 1,
},
&THD74 => {'minfreq'  => 000100000,'maxfreq' => 524000000 ,
'maxchan'  => 999,
'origin'   => 0,
'sigdet'   => 1,
},
);
my $protoname = 'kenwood';
use constant PROTO_NUMBER => 3;
$radio_routine{$protoname} = \&kenwood_cmd;
$valid_protocols{'kenwood'} = TRUE;
return TRUE;
sub kenwood_cmd {
my $cmdcode = lc(shift @_);
my $parmref = shift @_;
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
else {
$in = '';
}
my $insave = $in;
my $delay = 100;
$parmref->{'rc'} = $GoodCode;
my $parmstr = '';
if ($Debug3) {DebugIt("KENWOOD l1224:command=$cmdcode");}
my %split;
my $splitflag = 0;
my $countout = 0;
my $instr= "";
my $rc = 0 ;
my $data_in;
my $count_in;
my $hex_data;
my $gotit = FALSE;
if ($cmdcode eq 'init') {
%state_save = ('state' => '', 'mode'  => '', 'atten' => -1, 'vfonum' => 1);
$delay = 100;
$defref->{'radioscan'} = FALSE;
$defref->{'group'} = FALSE;
@gui_modestring = ('WFM','FM','AM','LSB','USB','CW');
@gui_bandwidth  = ();
@gui_adtype = ();
@gui_attstring = ('Off','Attenuation');
@gui_tonestring = ();
my %out = ();
my %in = ();
if (kenwood_cmd('ID',$parmref)) {
LogIt(1,"KENWOOD l1277: Radio does not appear to be connected");
return ($parmref->{'rc'} = $CommErr);
}
LogIt(0," Kenwood ID =>$model");
$parmref->{'in'} = \%in;
%in = ('method' => 0);
$parmref->{'write'} = TRUE;
kenwood_cmd('MRM',$parmref);
%in = ('vfonum' => 0);
$parmref->{'write'} = FALSE;
kenwood_cmd('FL',$parmref);
%in = ('vfonum' => 1);
kenwood_cmd('FL',$parmref);
if ($vfo_limits[1][0]{'low'}) {
$radio_limits{'minfreq'} = $vfo_limits[1][0]{'low'};
if ($vfo_limits[1][-1]{'high'}) {$radio_limits{'maxfreq'} = $vfo_limits[1][-1]{'high'};}
}
elsif ($vfo_limits[0][0]{'low'}) {
$radio_limits{'minfreq'}  = $vfo_limits[0][0]{'low'};
if ($vfo_limits[0][-1]{'high'}) {$radio_limits{'maxfreq'} = $vfo_limits[0][-1]{'high'};}
}
foreach my $key (keys %{$radio_limits{$model}}) {
$defref->{$key} = $radio_limits{$model}{$key};
}
if ($Debug1) {
DebugIt("Kenwood l1341: Radio minfreq=$defref->{'minfreq'} maxfreq=$defref->{'maxfreq'}");
}
$parmref->{'write'} = FALSE;
kenwood_cmd('BC',$parmref);
kenwood_cmd('VMC',$parmref);
$parmref->{'in'} = $insave;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'autobaud') {
if (!$defref->{'model'}) {
LogIt(1,"Model number not specified in .CONF file. " .
" Cannot automatically determine port/baud");
return ($parmref->{'rc'} = 1);
}
my $model_save = $defref->{'model'};
if (lc($model_save) eq 'thf6a') {$model_save = THF6A;}
elsif (lc($model_save) eq 'th-f6a') {$model_save = THF6A;}
$model_save = uc($model_save);
my @allports = ();
if ($in->{'noport'} and $defref->{'port'}) {push @allports,$defref->{'port'};}
else {
push @allports,glob("/dev/ttyUSB*");
}
my @allbauds = ();
if ($in->{'nobaud'}) {push @allbauds,$defref->{'baudrate'};}
else {
push @allbauds,keys %baudrates;
if ($Debug2) {DebugIt("KENWOOD l1400:model_save=>$model_save");}
if ($model_save eq THF6A) {@allbauds = (9600);}
}
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
LogIt(0,"Trying port=>$port baudrate=>$baud");
$portobj->baudrate($baud);
$warn = FALSE;
$rc = kenwood_cmd('ID',$parmref);
$warn = TRUE;
if (!$rc) {### command succeeded
if ($model eq $model_save) {
$defref->{'baudrate'} = $baud;
$defref->{'port'} = $port;
$portobj->close;
$parmref->{'portobj'} = undef;
return ($parmref->{'rc'} = $GoodCode);
}
else {
$defref->{'model'} = $model_save;
$model = $model_save;
next PORTLOOP;
}
}
}
$portobj->close;
$parmref->{'portobj'} = undef;
}
return ($parmref->{'rc'} = 1);
}
elsif (($cmdcode eq 'manual') or ($cmdcode eq 'vfoinit')) {
my %in = ();
$parmref->{'in'} = \%in;
if ($model ne THG71) {
$parmref->{'write'} = TRUE;
%in = ('vfosel' => 'b');
if (kenwood_cmd('BC',$parmref)) {return ($parmref->{'rc'} = $ParmErr);}
}
else {$state_save{'vfonum'} = 0;}
%in = ('state' => 'VFO');
$parmref->{'write'} = TRUE;
kenwood_cmd('VMC',$parmref);
$parmref->{'write'} = FALSE;
$parmref->{'in'} = $insave;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'meminit') {
my %in = ('state' => 'mem');
$parmref->{'in'} = \%in;
$parmref->{'write'} = TRUE;
kenwood_cmd('VMC',$parmref);
$parmref->{'in'} = $insave;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'scan') {
return ($parmref->{'rc'} = $NotForModel);
}
elsif ($cmdcode eq 'getvfo') {
if (!$outsave) {LogIt(1281,"KENWOOD_CMD:No 'out' reference in parmref for GETVFO call!");}
if ($parmref->{'rc'} = kenwood_cmd('BY',$parmref)) {return $parmref->{'rc'};}
$parmref->{'write'} = FALSE;
if ($parmref->{'rc'} = kenwood_cmd('FQ',$parmref)) {return $parmref->{'rc'};}
$out->{'mode'} = 'fm';
$out->{'atten'} = 0;
if ($model ne THG71) {
if ($parmref->{'rc'} = kenwood_cmd('MD',$parmref)) {return $parmref->{'rc'};}
kenwood_cmd('ATT',$parmref);
}
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'getsig') {
$out->{'sq'} = FALSE;
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
foreach my $cnt (1..2) {
if (kenwood_cmd('by',$parmref)) {return $parmref->{'rc'};}
if ($out->{'sql'}) {
last;
}
usleep(500);
}
if ($out->{'sql'}) {
$parmref->{'write'} = FALSE;
if ($model eq THF6A) {
kenwood_cmd('fq',$parmref);
kenwood_cmd('md',$parmref);
kenwood_cmd('att',$parmref);
}
elsif ($model eq THG71) {
kenwood_cmd('sm',$parmref);
kenwood_cmd('fq',$parmref);
$out->{'mode'} = 'FM';
}
elsif ($model eq THD74) {
}
}
return ($parmref->{'rc'} = $GoodCode);
}### GETSIG
elsif ($cmdcode eq 'setvfo') {
my $freq = $in->{'frequency'};
if (!$freq) {
add_message("KENWOOD_CMD:SETVFO-VFO frequency = 0 or undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
if (!check_range($freq,$defref)) {
add_message(rc_to_freq($freq) . " MHz is NOT valid for this radio");
return ($parmref->{'rc'} = $NotForModel);
}
if ($state_save{'state'} ne 'vfo') {
if ($model ne THD74) {kenwood_cmd('vmc',$parmref);}
else {
}
}
$parmref->{'write'} = TRUE;
if (kenwood_cmd("fq",$parmref)) {return $parmref->{'rc'};}
if ($model eq THF6A) {
if ($in->{'mode'} and ($in->{'mode'} ne $state_save{'mode'})) {
kenwood_cmd("md",$parmref);
}
if (defined $in->{'atten'} and ($in->{'atten'} ne $state_save{'atten'})) {
kenwood_cmd('att',$parmref);
}
}
elsif ($model eq THG71) { }
elsif ($model eq THD74) {
LogIt(1,"KENWOOD_CMD l1415:Need MODE/ATTEN setting for TH-D74");
}
usleep(100);
$parmref->{'write'} = FALSE;
if (kenwood_cmd("fq",$parmref)) {return $parmref->{'rc'};}
if ($out->{'frequency'} != $freq) {
LogIt(1,"KENWOOD l1592:Requested $freq but $out->{'frequency'} set instead!");
}
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'selmem') {
if (!defined $in->{'channel'}) {
LogIt(1528,"KENWOOD_CMD l1434:SELMEM - Channel not defined");
}
my $ch = $in->{'channel'};
if (!looks_like_number($ch)) {
LogIt(1,"KENWOOD l1675:SELMEM - Channel $ch is non-numeric.");
return ($parmref->{'rc'} = $ParmErr);
}
if (($ch < $defref->{'origin'}) or ($ch > $defref->{'maxchan'})) {
LogIt(1,"KENWOOD l1680:SELMEM - Channel $ch out of range of radio.");
return ($parmref->{'rc'} = $NotForModel);
}
my $retcode = $GoodCode;
$out->{'igrp'} = 0;
my %myin = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
if ($model ne THD74) {
if ($state_save{'state'} ne 'mem') {
$myin{'state'} = 'mem';
$parmref->{'write'} = TRUE;
if (kenwood_cmd('VMC',$parmref) ) {
$retcode = $parmref->{'rc'};
goto SELMEMRTN;
}
}
$parmref->{'write'} = TRUE;
$myin{'channel'} = $ch;
if (kenwood_cmd ('mc',$parmref)) {$retcode = $EmptyChan;}
}
else {
}
SELMEMRTN:
$parmref->{'in'} = $insave;
$parmref->{'write'} = $writesave;
return ($parmref->{'rc'} = $retcode);
}
elsif ($cmdcode eq 'getmem') {
if ($Debug2) {DebugIt("KENWOOD l1784:Started 'getmem'");}
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
my %sysrec = ('systemtype' => 'CNV','service' => "Kenwood model $model", 'valid' => TRUE);
$sysno = add_a_record($db,'system',\%sysrec,$parmref->{'gui'});
}
my $igrp = 0;
my $grpndx = 0;
KENCHAN:
while ($channel <= $maxchan) {
if (!$grpndx) {
my %grouprec = ('sysno' =>$sysno,
'service' => "Kenwood $model Group/Bank:$igrp",
'valid' => TRUE
);
$grpndx = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$igrp++;
}### New group creation
$vfo{'channel'} = $channel;
$vfo{'groupno'} = $grpndx;
threads->yield;
if ($progstate ne $startstate) {
if ($Debug1) {DebugIt("Kenwood l1923:Exited loop as progstate changed");}
last KENCHAN;
}
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green" . sprintf("%03.3u",$channel) .$Reset ;
}
$myout{'valid'} = TRUE;
$myout{'mode'} = 'fm';
foreach my $key ('frequency','splfreq','srptr','sctcss','sdcs','atten','dlyrsm') {
$myout{$key} = 0;
}
$myout{'sqtone'} = 'Off';
$myout{'spltone'} = '';
$myout{'service'} = '';
$myout{'tgid_valid'} = FALSE;
$myout{'channel'} = $channel;
$myout{'groupno'} = $grpndx;
$myin{'channel'} = $channel;
if ($nodup and $duplist{$channel}) {
}
else {
my $rc = 0;
if ($model ne 'TH-74A') {
$myin{'split'} = FALSE;
$rc = kenwood_cmd('mr',$parmref);
if ((!$rc) and $myout{'frequency'}){
kenwood_cmd ('mna',$parmref);
$myin{'split'} = TRUE;
kenwood_cmd('mr',$parmref);
$myin{'split'} = FALSE;
}
}
else {
LogIt(1,"Kenwood l1937:Need code for $model");
}
my $freq = $myout{'frequency'} + 0;
if ($noskip or $freq) {
if (!$freq) {$myout{'valid'} = FALSE;}
my $recno = add_a_record($db,'freq',\%myout,$parmref->{'gui'});
$vfo{'index'} = $recno;
$count++;
if ($count >= $maxcount) {last KENCHAN;}
}
}### Not skipping duplicates
$channel++;
if (!($channel % $chanper)) {
$grpndx = 0;
}
}### channel creation
print STDERR "\n";
$parmref->{'out'} = $outsave;
$parmref->{'in'} = $insave;
$parmref->{'write'} = $writesave;
$outsave->{'count'} = $count;
$out->{'sysno'} = $sysno;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'setmem') {
if ($model eq THD74) {return $NotForModel;}
my $max_count = 99999;
my $options = $parmref->{'options'};
if ($options->{'count'}) {$max_count = $options->{'count'};}
my %in = ();
$parmref->{'in'} = \%in;
my %found_chan = ();
my $count = 0;
foreach my $frqrec (@{$db->{'freq'}}) {
if (!$frqrec->{'index'}) {next;}
my $recno = $frqrec->{'_recno'};
if (!$recno) {$recno = '??';}
my $emsg = "for record $recno";
if ($frqrec->{'tgid_valid'}) {next;}
my $channel = $frqrec->{'channel'};
if ((!looks_like_number($channel)) or ($channel < 0) ) {
print "Channel number $emsg is not defined. Skipped\n";
next;
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
print "\nChannel number $channel $emsg is not within range of radio. Skipped\n";
next;
}
if ($found_chan{$channel}) {
LogIt(1,"Channel $channel was found twice $emsg. Second iteration skipped!");
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
my $split = FALSE;
my $splfreq = $frqrec->{'splfreq'};
if ($splfreq and ($splfreq != $freq)) {$split = TRUE;}
print STDERR "\rSETMEM: Writing channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset,
" freq=>$Yellow",rc_to_freq($freq),$Reset;
%in = ();
foreach my $key (keys %{$frqrec}) {
$in{$key} = $frqrec->{$key};
}
my $rc = 0;
$parmref->{'write'} = TRUE;
if ($model eq THD74) {
}
else {
$in{'split'} = FALSE;
$rc =  kenwood_cmd('mw',$parmref);
if ((!$clear) and (!$rc)) {
$rc = kenwood_cmd('mna',$parmref);
if ( (!$rc) and $split) {
$in{'split'} = TRUE;
$in{'frequency'} = $splfreq;
kenwood_cmd('mw',$parmref);
}### Split process
}### set service and split
}### THF6A process
if (!$rc) {$count++;}
if ($count >= $max_count) {
LogIt(1,"$Eol$Bold Store terminated due to maximum record count reached");
last;
}
}### For each FREQ record
LogIt(0,"$Eol$Bold$Green$count$White Records stored.");
return 0;
}### SETMEM
elsif ($cmdcode eq 'getglob') {
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
if (!kenwood_cmd('bep',$parmref)) {
my $value = 0;
if ($myout{'beep'}) {$value = 15;}
my %rec = ('volume' => $value);
$db->{'beep'} = ();
add_a_record($db,'beep',\%rec);
}
else {LogIt(1,"Kenwood l1994:Could not get BEEP setting");}
if (!kenwood_cmd('lmp',$parmref)) {
my $value = 'Off';
if ($myout{'light'}) {$value = 'On';}
$db->{'light'} = ();
my %rec = ('event' => $value, 'bright' => 3);
add_a_record($db,'light',\%rec);
}
else {LogIt(1,"Kenwood l2012:Could not get BEEP setting");}
if (!kenwood_cmd('mes',$parmref)) {
my %rec = ('msg1' => $myout{'msg1'},
'msg2' => '', 'msg3' => '', 'msg4' => '');
add_a_record($db,'powermsg',\%rec);
}
else {LogIt(1,"Kenwood l2018:Could not get Power On Message");}
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
%myin = ('beep' => 0);
if ($db->{'beep'}[1]{'volume'}) {$myin{'beep'} = 1;}
if (kenwood_cmd('bep',$parmref)) {
LogIt(1,"Kenwood l2051:Could not set the BEEP value");
}
if ($db->{'light'}[1]{'event'}) {
%myin = ('light' => 0);
if (lc($db->{'light'}[1]{'event'}) ne 'off') {$myin{'light'} = 1;}
if (kenwood_cmd('lmp',$parmref)) {
LogIt(1,"Kenwood l2062:Could not set the LIGHT value");
}
}
if (defined $db->{'powermsg'}[1]{'msg1'}) {
%myin = ('msg1' => $db->{'powermsg'}[1]{'msg1'});
if (kenwood_cmd('mes',$parmref)) {
LogIt(1,"Kenwood l2062:Could not set the Power On Message value");
}
}
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'getsrch') {
return $NotForModel;
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
my $startstate = $progstate;
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
my $count = 0;
SRCHC:foreach my $chan (0..9) {
my %rec = ();
foreach my $bounds ('U','L') {
my $channel = "$bounds$chan";
$myin{'channel'} = $channel;
threads->yield;
if ($progstate ne $startstate) {last SRCHC;}
if (!$parmref->{'gui'}) {
print STDERR "\rReading search channel $channel";
}
$myout{'valid'} = FALSE;
$myout{'mode'} = 'fm';
$myout{'frequency'} = 0;
$myout{'sqtone'} = 'Off';
$myout{'service'} = '';
if ($model ne 'TH-74A') {
$myin{'split'} = FALSE;
if (kenwood_cmd('mr',$parmref)) {
}
else {
if ($myout{'frequency'}) {
kenwood_cmd ('mna',$parmref);
}
}
}
else {
LogIt(1,"Kenwood l1683:Need code for $model");
}
if ($bounds eq 'U') {
$rec{'stop_freq'} = $myout{'frequency'};
foreach my $key ('mode','sqtone','service') {
$rec{$key} = $myout{$key};
}
}
else {
$rec{'start_freq'} =  $myout{'frequency'};
}
}### Upper/lower loop
my $recno = add_a_record($db,'search',\%rec,$parmref->{'gui'});
$count++;
}
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'setsrch') {
return $NotForModel;
my %myin = ();
my %myout = ();
my $startstate = $progstate;
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = TRUE;
my $count = 0;
my $dbndx = 1;
SRCHW:foreach my $channel (0..9) {
if (!$db->{'search'}[$dbndx]{'index'}) {last SRCHW;}
threads->yield;
if ($progstate ne $startstate) {last SRCHW;}
if (!$parmref->{'gui'}) {
print STDERR "\rWriting search channel $channel";
}
foreach my $key ('valid','mode','sqtone','service') {
$myin{$key} = $db->{'search'}[$dbndx]{$key};
}
$myin{'split'} = FALSE;
if ($model ne 'TH-74A') {
$myin{'channel'} = "L$channel";
$myin{'frequency'} = $db->{'search'}[$dbndx]{'start_freq'};
if (kenwood_cmd('mw',$parmref)) {
LogIt(1,"Kenwood l2232:Unable to write search channel $myin{'channel'}");
}
else {kenwood_cmd('mna',$parmref);}
$myin{'channel'} = "U$channel";
$myin{'frequency'} = $db->{'search'}[$dbndx]{'stop_freq'};
if (kenwood_cmd('mw',$parmref)) {
LogIt(1,"Kenwood l2241:Unable to write search channel $myin{'channel'}");
}
else {kenwood_cmd('mna',$parmref);}
}
else {
LogIt(1,"Kenwood l1683:Need code for $model");
}
$dbndx++;
}### for each of the radio's search channels
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'getinfo') {
kenwood_cmd('init',$parmref);
$out->{'chan_count'} = $defref->{'maxchan'};
$out->{'model'} = $model;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'test') {
}
if ($cmdcode eq 'poll') {
}
elsif ($cmdcode eq 'ant') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:ANT command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
$parmstr = 0;
if ($in->{'antenna'}) {$parmstr = 1;}
}
else {
}
}
elsif ($cmdcode eq 'apo') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:APO command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if (!defined $in->{'apo'}) {
LogIt(1,"KENWOOD_CMD:APO command missing 'apo' value!");
return ($parmref->{'rc'} = $ParmErr);
}
my $apo = $in->{'apo'};
if (!looks_like_number($apo)) {
LogIt(1,"KENWOOD_CMD:APO command-'apo' value $apo not numeric!");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = 0;
if ($apo) {
if ($apo <= 30) {$parmstr = 1;}
else {$parmstr = 2;}
}
}### set
else {
}
}## APO
elsif ($cmdcode eq 'att') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:ATT command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if (!defined $in->{'atten'}) {
LogIt(1,"KENWOOD_CMD l2101:'atten' key missing for ATT");
print Dumper($in),"\n";
return ($parmref->{'rc'} = $ParmErr);
}
if ($in->{'atten'}) {$parmstr = 1;}
else {$parmstr = 0;}
}
else { }
}
elsif ($cmdcode eq 'bc') {
if ($model eq THG71) {
LogIt(1,"KENWOOD_CMD:BC command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if ($in->{'vfosel'} eq 'a') {$parmstr = 0;}
elsif ($in->{'vfosel'} eq 'b') {$parmstr = 1;}
else {
LogIt(1,"KENWOOD_CMD l2868:Invalid value $in->{'vfosel'} for VFOSEL");
return ($parmref->{'rc'} = $ParmErr);
}
}
else {
}
}
elsif ($cmdcode eq 'bep') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:BEP command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if ($in->{'beep'}) {$parmstr = 1;}
else {$parmstr = 0;}
}
else { }
}
elsif ($cmdcode eq 'by') {
$parmstr = $state_save{'vfonum'};
}
elsif ($cmdcode eq "fq") {
if ($parmref->{'write'}) {
my $freq = $in->{'frequency'};
if (!$freq) {
add_message("KENWOOD_CMD:frequency 0 or missing for FQ command!");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = sprintf("%011.11u",$freq);
my $step = get_step_code($parmstr);
if ($step == -1) {
add_message("KENWOOD_CMD FQ:Step cannot be set for freq =$freq");
return ($parmref->{'rc'} = $ParmErr);
}
if ($model eq THD74) {
my $vfonum = $state_save{'vfonum'};
if (defined $in->{'state'}) {$vfonum = $in->{'state'};}
$parmstr = "$vfonum,$parmstr";
}
else {$parmstr = "$parmstr,$step";}
}
}
elsif ($cmdcode eq 'fl') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:BEP command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if (!$in) {LogIt(1912,"KENWOOD_CMD:Missing IN for FL  command!");}
if (!defined $in->{'vfonum'}) {LogIt(1913,"KENWOOD_CMD:Missing IN for FL  command!");}
$parmstr = 0;
if ($in->{'vfonum'}) {$parmstr = 1;}
}
elsif ($cmdcode eq 'id') {
}
elsif ($cmdcode eq 'lmp') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:LMP command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if ($in->{'light'}) {$parmstr = 1;}
else {$parmstr = 0;}
}
else { }
}
elsif ($cmdcode eq 'mc') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:MC command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if (!$in) {LogIt(1598,"Missing IN for MC command!");}
if (!defined $in->{'channel'}) {LogIt(1988,"No Channel defined in IN for MC command!");}
my $ch = format_channel($in->{'channel'});
if ($ch < 0) {
LogIt(1,"KENWOOD l2980:$in->{'channel'} is not Valid for command $cmdcode");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = "$state_save{'vfonum'},$ch";
}
}
elsif ($cmdcode eq 'md') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:MD command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
my $mode = lc(Strip($in->{'mode'}));
$parmstr = 1;
if (!$mode or ($mode eq 'auto')) {
my $freq = $in->{'frequency'};
if ($freq) {$mode = AutoMode($freq);}
else {
LogIt(1,"Cannot convert AUTO mode. Frequency missing. Set FMn default!");
$mode = 'fmn';
}
}
$parmstr = set_mode_code($mode);
}
else {
}
}
elsif ($cmdcode eq 'mes') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD:MES command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
my $msg = $in->{'msg1'};
if (!$msg) {$msg = '        ';}
$parmstr = sprintf("%8.8s",$msg);
}
}
elsif ($cmdcode eq 'mna') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:MNA command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if (!$in) {LogIt(2354,"Missing IN for MNA command!");}
if (!defined $in->{'channel'}) {LogIt(2355,"No CHANNEL defined in IN for MNA command!");}
$parmstr = format_channel($in->{'channel'});
if ($parmstr eq '-1') {
LogIt(1,"KENWOOD_CMD l2358:$in->{'channel'} is not Valid for command $cmdcode");
return ($parmref->{'rc'} = $ParmErr);
}
if (substr($parmstr,0,1) eq 'P') {
LogIt(1,"KENWOOD_CMD l2366:Priority channel not valid for MNA command!");
return ($parmref->{'rc'} = $ParmErr);
}
if ($parmref->{'write'}) {
if (!defined $in->{'service'}) {LogIt(2372,"No SERVICE defined in IN for MNA command!");}
my $service = $in->{'service'};
if ($service) {$service = sprintf("%-8.8s",$service);}
else {$service = '        ';}
$parmstr = "$parmstr,$service";
}
if ($model eq THG71) {$parmstr = "0,$parmstr";}
}
elsif ($cmdcode eq 'mr') {
if (!$in) {LogIt(2435,"KENWOOD_CMD l2437:Missing IN for MR command!");}
my $ch = $in->{'channel'};
if ($model eq THD74) {
if (defined $in->{'vfonum'}) {$parmstr = $in->{'vfonum'};}
else {$parmstr = $state_save{'vfonum'};}
if ($parmref->{'write'}) {
if (!defined $ch) {LogIt(2442,"KENWOOD_CMD l2442:Missing in->channel for MR command!");}
$ch = format_channel($ch);
if ($ch < 0) {
LogIt(1,"KENWOOD_CMD l3445:$in->{'channel'} is not valid for MR command!");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = "$parmstr,$ch";
}
}
else {
if (!defined $ch) {LogIt(2461,"KENWOOD_CMD l2461:Missing in->channel for MR command!");}
$ch = format_channel($ch);
if ($ch eq '-1') {
LogIt(1,"KENWOOD_CMD l2931:$in->{'channel'} is not valid for MR command!");
return ($parmref->{'rc'} = $ParmErr);
}
my $split = 0;
if ($in->{'split'}) {$split = 1;}
$parmstr = "$split,$ch";
if ($model eq THG71) {$parmstr = "0,$parmstr";}
}### TH-F6A/TH-G71
}
elsif ($cmdcode eq 'mrm') {
if ($model ne THF6A) {
LogIt(1,"KENWOOD_CMD l2499:MRM command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
if ($in->{'method'}) {$parmstr = 1;}
else {$parmstr = 0;}
}
}
elsif ($cmdcode eq 'mw') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:MW command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if (!$in) {LogIt(2124,"Missing IN for MW command!");}
if (!defined $in->{'channel'}) {LogIt(2126,"Missing CHANNEL for MW command!");}
if (!defined $in->{'frequency'}) {LogIt(2126,"Missing FREQUENCY for MW command!");}
my $chan = sprintf("%03.3u",$in->{'channel'});
my $freq = $in->{'frequency'};
my $lock = 1;
if ($in->{'valid'}) {$lock = 0;}
my $split = 0;
if ($in->{'split'} and ($model ne THG71)) {$split = 1;}
$parmstr = "$split,$chan";
if ($freq) {
my $pkt = gen_packet($in);
if ($pkt eq '-1') {return ($parmref->{'rc'} = $ParmErr);}
$parmstr = "$parmstr," . $pkt;
$parmstr = "$parmstr,$lock";
}
}### MW
elsif ($cmdcode eq 'sm') {
if ($model eq THF6A) {
LogIt(1,"KENWOOD_CMD:SM command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if    ($model eq 'THG71') {$parmstr = '0';}
elsif ($model eq 'THD74') {
$parmstr = $state_save{'vfonum'};
if ($in->{'vfonum'}) {$parmstr = $in->{'vfonum'};}
}
}
elsif ($cmdcode eq 'sq') {
my $vfonum = $state_save{'vfonum'};
if (defined $in->{'vfonum'}) {$vfonum = $in->{'vfonum'};}
$parmstr = $vfonum;
if ($parmref->{'write'}) {
if (!$in) {LogIt(2593,"Missing IN for SQ command!");}
my $squelch = $in->{'squelch'};
if (!defined $squelch) {
LogIt(1,"KENWOOD_CMD l2596:SQ-Missing 'squelch' key");
return ($parmref->{'rc'} = $ParmErr);
}
if (!looks_like_number($squelch) or ($squelch < 0) or ($squelch > 5)) {
LogIt(1,"KENWOOD_CMD:SQ-Invalid squelch value => $squelch");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = "$parmstr," . sprintf("%02.2u",$squelch);
}### write
}### SQ
elsif ($cmdcode eq 'vmc') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:VMC command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
$parmstr = $state_save{'vfonum'};
if ($parmref->{'write'}) {
if (! defined $in->{'state'}) {LogIt(2321,"Missing STATE for VMC command!");}
my $state = $state2ken{lc(Strip($in->{'state'}))};
if (!defined $state) {
LogIt(2716,"KENWOOD l2716:Undefined state translation for $in->{'state'}");
}
if ($parmstr and ($state == 2) ) {
LogIt(1,"KENWOOD_CMD l2642:CALL state cannot be set for VFO 1!");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = "$parmstr,$state";
}
}
elsif ($cmdcode eq 'vr') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:VR command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if (!$in) {LogIt(2354,"Missing IN for VR command!");}
if (!defined $in->{'band'}) {LogIt(3255,"KENWOOD_CMD:Missing 'BAND' for VR command!");}
$parmstr = $in->{'band'};
}
elsif ($cmdcode eq 'vw') {
if ($model eq THD74) {
LogIt(1,"KENWOOD_CMD:VW command not valid for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if (!$in) {LogIt(2784,"KENWOOD_CMD l2785:Missing IN for VW command!");}
if (!defined $in->{'band'}) {LogIt(2785,"KENWOOD_CMD l2785:Missing 'BAND' for VW command!");}
if (!defined $in->{'frequency'}){LogIt(2381,"KENWOOD_CMD l2786:Missing 'FREQUENCY' for VW command!");}
my $freq = $in->{'frequency'};
if (!$freq) {
LogIt(1,"KENWOOD_CMD l2709:Frequency cannot be 0 for VW command");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = $in->{'band'} . "," . gen_packet($in);
}
elsif ($cmdcode eq 'AE') {}
elsif ($cmdcode eq 'AG') {}
elsif ($cmdcode eq 'AI') {}
elsif ($cmdcode eq 'ARO') { }
elsif ($cmdcode eq 'AS') {}
elsif ($cmdcode eq 'ASC') { }
elsif ($cmdcode eq 'BAL') { }
elsif ($cmdcode eq 'BAT') { }
elsif ($cmdcode eq 'BE') {}
elsif ($cmdcode eq 'BEL') { }
elsif ($cmdcode eq 'BL') {}
elsif ($cmdcode eq 'BS') {}
elsif ($cmdcode eq 'BT') {}
elsif ($cmdcode eq 'CKEY') { }
elsif ($cmdcode eq 'CNT') { }
elsif ($cmdcode eq 'CR') {  }
elsif ($cmdcode eq 'CW') {}
elsif ($cmdcode eq 'DATP') {}
elsif ($cmdcode eq 'DL') {}
elsif ($cmdcode eq 'DLK') {}
elsif ($cmdcode eq 'DM') {}
elsif ($cmdcode eq 'DMN') {}
elsif ($cmdcode eq 'DW') {}
elsif ($cmdcode eq 'ELK') {}
elsif ($cmdcode eq 'FL') {}
elsif ($cmdcode eq 'FST') {}
elsif ($cmdcode eq 'LAN') {}
elsif ($cmdcode eq 'LK') {}
elsif ($cmdcode eq 'MGL') {}
elsif ($cmdcode eq 'MNF') {}
elsif ($cmdcode eq 'NAR') {}
elsif ($cmdcode eq 'NSFT') {}
elsif ($cmdcode eq 'PC') {}
elsif ($cmdcode eq 'PT') {}
elsif ($cmdcode eq 'PV') {}
elsif ($cmdcode eq 'RBN') {}
elsif ($cmdcode eq 'RX') {}
elsif ($cmdcode eq 'SCR') {}
elsif ($cmdcode eq 'SR') {}
elsif ($cmdcode eq 'SV') {}
elsif ($cmdcode eq 'TH') {}
elsif ($cmdcode eq 'TSP') {}
elsif ($cmdcode eq 'TT') {}
elsif ($cmdcode eq 'TX') {}
elsif ($cmdcode eq 'TXH') {}
elsif ($cmdcode eq 'TXS') {}
elsif ($cmdcode eq 'TYD') {}
elsif ($cmdcode eq 'UP') {}
elsif ($cmdcode eq 'VOX') {}
else {LogIt(1,"No preprocess for Kenwood command code $cmdcode!");}
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => KENWOOD_TERMINATOR,
'delay' => $delay,
'resend' => 0,
'debug' => 0,
'fails' => 1,
'wait' => 30,
);
RESEND:
my $outstr = $cmdcode;
if ($cmdcode eq 'test') {$outstr = $parmstr;}
elsif ($cmdcode eq 'poll') {$outstr = '';}
else {
$outstr = Strip("$outstr $parmstr");
}
if ($Debug3) {DebugIt("KENWOOD l3459:sent =>$outstr");}
my $sent = $outstr;
if ($outstr) {$outstr = $outstr . KENWOOD_TERMINATOR;}
WAIT:
if ($Debug3) {DebugIt("KENWOOD l3467:Waiting for Radio_Send..");}
if (radio_send(\%sendparms,$outstr)) {### send with retry
if ($cmdcode eq 'poll') {return ($parmref->{'rc'} = $GoodCode);}
if (!$outstr) {
add_message("Radio did not like $sent...");
$defref->{'rsp'} = 0;
$parmref->{'rc'} = $CommErr;
return $CommErr;
}
else {
if ($defref->{'rsp'}) {$defref->{'rsp'}++;}
else {
$defref->{'rsp'} = 1;
if ($warn) {
LogIt(1,"no response to $outstr");
add_message("KENWOOD_CMD l3491:Radio is not responding...");
}
}
return ($parmref->{'rc'} = $CommErr);
}
}
$instr = $sendparms{'rcv'};
if ($Debug3) {DebugIt("KENWOOD l3612:Radio returned=>$instr command=>$cmdcode");}
if ($defref->{'rsp'}) {add_message("Radio is responding again...");}
$defref->{'rsp'} = 0;
if ($cmdcode eq 'poll') {
my $queue = $parmref->{'unsolicited'};
if (!$queue) {LogIt(1,"KENWOOD l3321:Missing unsolicited queue reference in parmref!");}
else {
if ($instr) {
my %qe = ('kenwood_msg' => $instr);
push @{$queue},{%qe};
}
}
return ($parmref->{'rc'} = $GoodCode);
}
if (lc($instr) eq 'n') {
if ($cmdcode eq 'vmc') {
LogIt(1,"\nVMC returned 'N'. Sent->$sent");
}
elsif ($cmdcode eq 'mc') {
return ($parmref->{'rc'} = $EmptyChan);
}
elsif ($cmdcode eq 'mw') {
LogIt(1,"\nMW returned 'N' to $sent");
}
if ($parmref->{'write'}) {
add_message("Radio rejected parameter for cmd=>$sent");
}
return ($parmref->{'rc'} = $EmptyChan);
}
elsif ($instr eq '?') {
if ($sendparms{'fails'}) {
add_message("KENWOOD_CMD:$sent not recognized by radio. retrying...");
$sendparms{'fails'}--;
goto RESEND;
}
add_message("KENWOOD_CMD:Radio rejected command $sent");
$parmref->{'rsp'} = FALSE;
return($parmref->{'rc'} = $NotForModel);
}
my ($retcmd,$rest) = split " ",$instr,2;
if ($retcmd) {$retcmd = lc($retcmd);}
else {$retcmd = '';}
my @retvalues = ();
if (defined $rest) {@retvalues = split ',',$rest;}
$parmref->{'rc'} = $GoodCode;
if ($cmdcode eq 'test') {
$parmref->{'rsp'} = FALSE;
return ($parmref->{'rc'} = $GoodCode);
}
if ($retcmd ne $cmdcode) {
if ($warn) {
add_message("wrong response for cmdcode=$sent. Got =>$retcmd");
$outstr = '';
goto WAIT;
}
else { return ($parmref->{'rc'} = $CommErr);}
}
elsif ($cmdcode eq 'ant') {
$out->{'antenna'} = shift @retvalues;
}
elsif ($cmdcode eq 'apo') {
my $apo = shift @retvalues;
$out->{'apo'} = 0;
if ($apo) {
if ($apo == 1) {$out->{'apo'} = 30;}
elsif ($apo == 2) {$out->{'apo'} = 60;}
}
}### APO
elsif ($cmdcode eq 'att') {
if ($Debug3) {DebugIt("KENWOOD l3819:Post process for ATT write=$parmref->{'write'}");}
my $att = shift @retvalues;
if ($att) {$out->{'atten'} = TRUE;}
else {$out->{'atten'} = FALSE;}
$state_save{'atten'} = $out->{'atten'};
}
elsif ($cmdcode eq 'bc') {
my $vfonum = shift @retvalues;
$state_save{'vfo_num'} = $vfonum;
if ($vfonum) {$out->{'vfonum'} = 'b';}
else {$out->{'vfonum'} = 'a';}
}
elsif ($cmdcode eq 'bep') {
$out->{'beep'} = shift @retvalues;
}
elsif ($cmdcode eq 'by') {
my $bd = shift @retvalues;
my $sq = shift @retvalues;
if ($sq) {
$out->{'sql'} = 1;
$out->{'signal'} = MAXSIGNAL;
}
else {
$out->{'sql'} = 0;
$out->{'signal'} = 0;
}
}
elsif ($cmdcode eq "fq") {
if ($model eq THD74) {shift @retvalues;}
$out->{'frequency'} = shift @retvalues;
if ($model ne THD74) {
my $stepcode = lc(shift @retvalues);
$out->{'step'} = $steps{$stepcode}{'step'};
}
}
elsif ($cmdcode eq 'fl') {
my $vfonum = shift @retvalues;
$out->{'vfonum'} = $vfonum;
my $ndx = 0;
my $type = 'low';
my $ref = $parmref->{'vfo_limits'};
my %hash = ();
if ($ref) {
if (ref($ref) ne 'ARRAY') {
LogIt(1,"KENWOOD_CMD:FL-'vfo_limits' is not an array. Not used");
$ref = 0;
}
}
while (scalar @retvalues) {
my $freq = shift @retvalues;
if (length($freq) > 5) {$freq = $freq . '0000';}
else {$freq = $freq . '000000';}
if (looks_like_number($freq)) {$freq = $freq + 0;}
$hash{$type} = $freq;
if ($type eq 'low') {$type = 'high';}
else {
push @{$vfo_limits[$vfonum]},{%hash};
if ($ref) {push @{$ref->[$vfonum]},{%hash};}
$type = 'low';
$ndx++;
}
}
}
elsif ($cmdcode eq 'id') {
$model = shift @retvalues;
if (!$model) {
if ($warn) {add_message("Kenwood:No model returned for ID. May be wrong radio!");}
return ($parmref->{'rc'} = $CommErr);
}
$out ->{'model'} = $model;
}
elsif ($cmdcode eq 'lmp') {
$out->{'light'} = shift @retvalues;
}
elsif ($cmdcode eq "mc") {
shift @retvalues;
$out->{'channel'} =  shift @retvalues;
if ($Debug3) {DebugIt("KENWOOD l4008:MC-returned $instr");}
}
elsif ($cmdcode eq "md") {
my $modecode = shift @retvalues;
$out->{'mode'} = $modes[$modecode];
if (!defined $out->{'mode'}) {
LogIt(1,"KENWOOD l2248:No definition for modulation code $modecode");
$out->{'mode'} = 'FM';
}
$state_save{'mode'} = $out->{'mode'};
}
elsif ($cmdcode eq 'mes') {
if ($parmref->{'write'}) { }
my $msg = '';
foreach my $str (@retvalues) {$msg = "$msg$str";}
$out->{'msg1'} = Strip(substr($instr,4));
}
elsif ($cmdcode eq 'mna') {
if ($model eq THG71) {shift @retvalues;}
$out->{'channel'} = shift @retvalues;
$out->{'service'} = shift @retvalues;
}
elsif ($cmdcode eq 'mr') {
my @packet_save = @retvalues;
if ($model eq THD74) {
$out->{'vfonum'} = shift @retvalues;
$out->{'channel'} = shift @retvalues;
}
else {
if ($model eq THG71) {shift @retvalues;}
my $split = shift @retvalues;
$out->{'channel'} = shift @retvalues;
my %pkt = ();
memory_packet(\%pkt,@retvalues);
if ($in->{'split'}) {
my $sfreq = $pkt{'frequency'};
my $freq = $out->{'frequency'};
if ($freq and $sfreq and ($sfreq != $freq)) {
$out->{'splfreq'} = $sfreq;
}### Split frequency found
my $spltone = $pkt{'sqtone'};
if (!$spltone) {$spltone = '';}
my $sqtone = $out->{'sqtone'};
if (!$sqtone) {$out->{'sqtone'} = 'Off';}
else {
if ($spltone and  ($spltone !~ /$sqtone/i)){
$out->{'spltone'} = $spltone;
}
else {$out->{'spltone'} = '';}
}
}### Split read pass
else {
foreach my $key ('frequency','mode','valid','shift','rev') {
if (!$pkt{$key}) {$pkt{$key} = 0;}
$out->{$key} = $pkt{$key};
}
if ($pkt{'sqtone'}) {$out->{'sqtone'} = $pkt{'sqtone'};}
else {$pkt{'sqtone'} = 'Off';}
}### Not a split read pass
}### TH-F6A/TH-G71
}### MR post process
elsif ($cmdcode eq 'mrm') {
$out->{'method'} = shift @retvalues;
}
elsif ($cmdcode eq 'mw') {
if (scalar @retvalues) {
LogIt(1,"KENWOOD_CMD l3396:$cmdcode returned $instr");
}
}
elsif ($cmdcode eq 'sm') {
shift @retvalues;
my $value = shift @retvalues;
if (!$value) {$value = 0;}
if ($model eq THG71) {$out->{'signal'} = $value;}
elsif ($model eq THD74) {$out->{'sq'} = $value;}
}
elsif ($cmdcode eq 'sq') {
$out->{'vfonum'} = shift @retvalues;
$out->{'squelch'} = shift @retvalues;
}## sq
elsif ($cmdcode eq 'vmc') {
my $vfonum = shift @retvalues;
my $kenstate = shift @retvalues;
if (defined $ken2state[$kenstate]) {$out->{'state'} = $ken2state[$kenstate];}
else {
LogIt(1,"KENWOOD l3514:No state translation for $kenstate!");
$out->{'state'} = '';
}
$state_save{'state'} = $out->{'state'};
}
elsif ($cmdcode eq 'vr') {
$out->{'band'} = shift @retvalues;
memory_packet($out,@retvalues);
}
elsif ($cmdcode eq 'vw') {
if (scalar @retvalues) {
LogIt(1,"KENWOOD_CMD l3513:$cmdcode returned $instr");
}
}
elsif ($cmdcode eq 'ARO') {}
elsif ($cmdcode eq 'ASC') {}
elsif ($cmdcode eq 'BAL') {}
elsif ($cmdcode eq 'BAT') {}
elsif ($cmdcode eq 'BEL') {}
elsif ($cmdcode eq 'CKEY') {}
elsif ($cmdcode eq 'CNT') {}
elsif ($cmdcode eq 'CR') {}
elsif ($cmdcode eq 'CW') {}
elsif ($cmdcode eq 'DATP') {}
elsif ($cmdcode eq 'DL') {}
elsif ($cmdcode eq 'DLK') {}
elsif ($cmdcode eq 'DM') {}
elsif ($cmdcode eq 'DMN') {}
elsif ($cmdcode eq 'DW') {}
elsif ($cmdcode eq 'ELK') {}
elsif ($cmdcode eq 'FST') {}
elsif ($cmdcode eq 'LAN') {}
elsif ($cmdcode eq 'LK') {}
elsif ($cmdcode eq 'MC') {}
elsif ($cmdcode eq 'MGL') {}
elsif ($cmdcode eq 'MNF') {}
elsif ($cmdcode eq 'MRM') {}
elsif ($cmdcode eq 'NAR') {}
elsif ($cmdcode eq 'NSFT') {}
elsif ($cmdcode eq 'PC') {}
elsif ($cmdcode eq 'PT') {}
elsif ($cmdcode eq 'PV') {}
elsif ($cmdcode eq 'RBN') {}
elsif ($cmdcode eq 'RX') {}
elsif ($cmdcode eq 'SCR') {}
elsif ($cmdcode eq 'SR') {}
elsif ($cmdcode eq 'SV') {}
elsif ($cmdcode eq 'TH') {}
elsif ($cmdcode eq 'TSP') {}
elsif ($cmdcode eq 'TT') {}
elsif ($cmdcode eq 'TX') {}
elsif ($cmdcode eq 'TXH') {}
elsif ($cmdcode eq 'TXS') {}
elsif ($cmdcode eq 'TYD') {}
elsif ($cmdcode eq 'UP') {}
elsif ($cmdcode eq 'VOX') {}
elsif ($cmdcode eq 'VXB') {}
elsif ($cmdcode eq 'VXD') {}
elsif ($cmdcode eq 'VXG') {}
else {LogIt(1,"No Kenwood post-process for $cmdcode");}
return ($parmref->{'rc'});
}
sub format_channel {
my $ch = uc(shift @_);
my $fc = substr($ch,0,1);
if ($fc eq 'P') {
if (($ch ne 'PR1') and ($ch ne 'PR2')) {return -1;}
}
elsif (($fc eq 'L') or ($fc eq 'U')) {### search Lower/Upper channel
my $num = substr($ch,1);
if ((!defined $num) or (!looks_like_number($num)) or ($num < 0) or ($num > 9)) {return -1;}
}
elsif ($fc eq 'I') {
if (substr($fc,0,2) ne 'I-') {return -1;}
my $num = substr($ch,2);
if ((!defined $num) or (!looks_like_number($num)) or ($num < 0) or ($num > 9)) {return -1;}
}
else {
if (!looks_like_number($ch)) {return -1;}
$ch = sprintf("%03.3u",$ch);
}
return $ch
}
sub gen_packet {
my $in = shift @_;
if (!$in) {LogIt(3289,"KENWOOD_CMD:GEN_PACKET-Missing IN");}
my $freq = $in->{'frequency'};
if (!$freq) {$freq = 0;}
my $mode = $in->{'mode'};
if (!$mode) {$mode = 'fmn';}
else {
$mode = lc($mode);
if ($mode eq 'auto') {$mode = lc(AutoMode($freq));}
}
my $modeno = set_mode_code($mode);
if (!defined $modeno) {
LogIt(1,"KENWOOD_CMD:MW-$mode is not recognized. Changed to FMn");
$modeno = 0;
}
my $rptrno = '01';
my $ctcssno = '01';
my $dcsno = '023';
my $rptrflag = 0;
my $ctcssflag = 0;
my $dcsflag = 0;
my $sqtone = $in->{'sqtone'};
if ($in->{'split'}) {
if ($sqtone and $in->{'spltone'} and ($in->{'spltone'} ne $sqtone)) {
$sqtone = $in->{'spltone'};
}
}
my ($tt,$tone) = Tone_Xtract($sqtone);
if ($tone) {
if ($tt =~ /ctc/i) {
$ctcssflag = 1;
$ctcssno = $ctcrev{$tone};
if ($ctcssno) {$ctcssno = sprintf("%02.2i",$ctcssno);}
else {
LogIt(1,"KENWOOD l4484:Could not decode tone $tone");
$ctcssno = '01';
}
}
elsif ($tt =~ /dcs/i) {
$dcsflag = 1;
$dcsno = sprintf("%03.3u",$dcsno);
}
elsif ($tt =~ /rpt/i) {
$rptrflag = 1;
$rptrno = $ctcrev{$tone};
if ($rptrno) {$rptrno =  sprintf("%02.2i",$rptrno);}
else{
LogIt(1,"KENWOOD l4497:Could not decode tone $tone");
$rptrno = '01';
}
}
else {
}
}
my $offset = '000000000';
my $reverse = 0;
my $shift   = 0;
my $stepno = 0;
if ($freq) {
$stepno = get_step_code($freq);
if ($stepno == -1) {
my $oldfreq = $freq;
if ($freq < 470000000) {$freq = int($freq/5000) * 5000;}
else {$freq = int($freq/10000) * 10000;}
$stepno =  get_step_code($freq);
if ($stepno == -1) {
LogIt(0,"\n $Bold$Yellow WARNING!$White KENWOOD l4348:" .
"Cannot determine correct step for Frequency:$Green" .
rc_to_freq($oldfreq) . $White .
"(Tried:$Cyan" .rc_to_freq($freq) . $White . ")");
return -1;
}
else {LogIt(0,"\n$Bold  KENWOOD l4351:" .
"Frequency $Green" . rc_to_freq($oldfreq) . $White .
" adjusted to $Cyan" . rc_to_freq($freq) . $White . " for radio");}
}
}
if ($model eq THG71) {
$dcsflag = '';
$dcsno = '';
}
my $packet  = sprintf("%011.11u",$freq) . ",$stepno" .
",$shift,$reverse,$rptrflag,$ctcssflag,$dcsflag,$rptrno,$ctcssno,$dcsno";
if ($model eq THF6A) {$packet = "$packet,$offset,$modeno";}
return $packet
}
sub memory_packet {
my $dbref = shift @_;
my @packet = @_;
foreach my $key ('frequency','step','tone','shift','step','reverse','valid') {$dbref->{$key} = 0;}
$dbref->{'mode'} = 'FM';
$dbref->{'frequency'} =  $packet[0];
if (!$dbref->{'frequency'}) {
$dbref->{'frequency'} = 0;
return 0;
}
if ($packet[1]) {$dbref->{'step'} = $packet[1];}
if ($packet[2]) {$dbref->{'shift'} = $packet[2];}
if ($packet[3]) {$dbref->{'rev'} = $packet[3];}
if ($packet[11]) {$dbref->{'mode'} = $modes[$packet[11]]; }
if (!$packet[12]) {$dbref->{'valid'} = TRUE;}
my %tones = (
'dcs' => 'Off',
'ctc' => 'Off',
'rpt' => 'Off'
);
my $ndx = 7;
foreach my $type ('rpt','ctc') {
my $code = $packet[$ndx];
if ($code and looks_like_number($code)) {$code = $code + 0;}
if ($code) {
my $decode = $kenctc[$code];
if ($decode) {$tones{$type} = $type . Strip(sprintf("%5.1f",$decode));}
else {
LogIt(1,"Kenwood l4670:No decode value for $type code $code index=$ndx");
print "Packet=>@packet\n";
}
}
$ndx++;
}
if ($packet[9]) {$tones{'dcs'} = 'DCS' . sprintf("%03.3u",$packet[9]);}
if ($packet[5]) {$dbref->{'sqtone'} = $tones{'ctc'};}
elsif ($packet[6]) {$dbref->{'sqtone'} = $tones{'dcs'};}
elsif ($packet[4]) {$dbref->{'sqtone'} = $tones{'rpt'};}
else { }
}
sub get_step_code {
my $frq = shift(@_);
$frq = sprintf("%011.11i",$frq);
foreach my $ndx (sort keys %steps) {
if (($frq < $steps{$ndx}{'high'}) and ($frq > $steps{$ndx}{'low'})) {
my $step = $steps{$ndx}{'step'};
my $mod = $frq % $step;
if (!$mod) {
if ($Debug2) {DebugIt("KENWOOD l4619:Found step $step for $frq => $ndx")};
return $ndx;
}
else {
if ($Debug2) {DebugIt("KENWOOD l46221: $Bold Failed Mod value=>$mod");}
}
}
}
return -1;
}
sub set_mode_code {
my $mode = shift @_;
my $code = 0;
if ($mode =~ /fmw/i) {$code = 1;}
elsif ($mode =~ /am/i) {$code = 2;}
elsif ($mode =~ /ls/i) {$code = 3;}
elsif ($mode =~ /us/i) {$code = 4;}
elsif ($mode =~ /rt/i) {$code = 5;}
elsif ($mode =~ /rr/i) {$code = 5;}
elsif ($mode =~ /cw/i) {$code = 5;}
elsif ($mode =~ /cr/i) {$code = 5;}
return $code;
}
sub Numerically {
use Scalar::Util qw(looks_like_number);
if (looks_like_number($a) and looks_like_number($b)) { $a <=> $b;}
else {$a cmp $b;}
}
