#!/usr/bin/perl -w
package local;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(local_cmd %local_vfo
) ;
use Data::Dumper;
use Text::ParseWords;
use threads;
use threads::shared;
use Thread::Queue;
use Time::HiRes qw(time usleep ualarm gettimeofday tv_interval );
use Scalar::Util qw(looks_like_number);
use radioctl;
use strict;
use autovivification;
no  autovivification;
use constant LOCAL => 'LOCAL';
my %radio_limits = (
&LOCAL => {'minfreq'  =>        30,'maxfreq' =>MAXFREQ ,
'maxchan'  =>       999,
'origin'   =>         1,
'radioscan'=>     FALSE,
'sigdet'   =>         2,
'memory'   =>      'ro',
}
);
my %local = ();
my @localgroups = ('','AM Radio','Ham Radio','Fire','FM Radio', 'Air','Police','Railroad');
my @freqsamp = (
{'groupno' => 1, 'frequency' => '   770000', 'mode' => 'AM', 'service' => 'WABC-AM',   'dlyrsm' => -3,'preamp' => 1,'valid' => 0},
{'groupno' => 1, 'frequency' => '  1390000', 'mode' => 'AM', 'service' => 'WEOK-AM',   'dlyrsm' => 10,'valid' => 0},
{'groupno' => 2, 'frequency' => '  7019000', 'mode' => 'LS','service' => '40 meters', 'dlyrsm' => -5,'valid' => 0},
{'groupno' => 2, 'frequency' => ' 28300000', 'mode' => 'AM ','service' => '10 meters', 'dlyrsm' =>  5,'valid' => 0},
{'groupno' => 3, 'frequency' => ' 46460000', 'mode' => 'FMn','service' => 'UC Fire  ', 'dlyrsm' => -1,'valid' => 0,'tone_type' =>'ctcss','tone' => '94.8'},
{'groupno' => 4, 'frequency' => '101500000', 'mode' => 'FMw','service' => 'WPDH-FM  ', 'dlyrsm' =>  1,'valid' => 0,'atten' => 1},
{'groupno' => 3, 'frequency' => '154205000', 'mode' => 'FMn','service' => 'OC Fire  ', 'dlyrsm' => -4,'valid' => 1,'tone_type' =>'dcs', 'tone' => '047' },
{'groupno' => 8, 'frequency' => '160950000', 'mode' => 'FMn','service' => 'MetroNorth','dlyrsm' =>  4,'valid' => 1},
{'groupno' => 5, 'frequency' => '162475000', 'mode' => 'FMn','service' => 'NOAA     ', 'dlyrsm' => -2,'valid' => 1},
{'groupno' => 7, 'frequency' => '460187500', 'mode' => 'FMn','service' => 'DC-911   ', 'dlyrsm' =>  2,'valid' => 1},
);
my @searchsamp = (
{'start_freq' =>  30000000, 'end_freq' =>  50000000, step => 10000, mode => 'FMn', 'valid' => TRUE, 'service' => 'Low Band' },
{'start_freq' => 15000000,  'end_freq' => 170000000, step => 10000, mode => 'FMn', 'valid' => TRUE, 'service' => 'High Band' },
{'start_freq' => 45000000,  'end_freq' => 500000000, step => 10000, mode => 'FMn', 'valid' => TRUE, 'service' => 'UHF Band' },
{'start_freq' => 85000000,  'end_freq' => 870000000, step => 10000, mode => 'FMn', 'valid' => TRUE, 'service' => '80mhz Band' },
);
my %sample = ('service' => 'Simulated System', 'systemtype' => 'cnv', 'valid' => TRUE);
my $locsysno = add_a_record(\%local,'system',\%sample);
foreach my $groupname (@localgroups) {
if (!$groupname) {next;}
%sample = ('service' => $groupname ,"valid" => TRUE,"sysno" => $locsysno);
my $locgrpno =  add_a_record(\%local,'group',\%sample);
foreach my $frqrec (@freqsamp) {
if ($frqrec->{'groupno'} == $locgrpno) {
my $channo  = add_a_record(\%local,'freq',$frqrec);
$local{'freq'}[$channo]{'channel'} = $channo;
}
}
}
share (our %local_vfo);
%local_vfo = ('frequency' => 30000000,
'mode'      => 'fmn',
'signal'    => 0,
'sql'       => 0,
'channel'   => 0,
'tone'      => 'off',
'tone_type' => 'off',
'atten'     => FALSE,
'preamp'    => FALSE,
);
my $model = LOCAL;
my $protoname = 'local';
use constant PROTO_NUMBER => 0;
$radio_routine{$protoname} = \&local_cmd;
$valid_protocols{$protoname} = TRUE;
TRUE;
sub local_cmd {
my $cmd = shift@_;
if (!$cmd) {LogIt(326,"LOCAL_CMD:No command specified!");}
my $parmref = shift @_;
if (!$parmref) {LogIt(435,"LOCAL_CMD:No parmref reference specified. CMD=$cmd");}
if (ref($parmref) ne 'HASH') {LogIt(4336,"LOCAL_CMD:parmref is NOT a reference to a hash! CMD=$cmd");}
if (!$parmref->{'def'}) {LogIt(439,"LOCAL_CMD:No 'def' specified in parmref");}
my $defref    = $parmref->{'def'};
if (ref($defref) ne 'HASH') {LogIt(441,"LOCAL_CMD:defref is NOT a reference to a hash! CMD=$cmd");}
my $in   = $parmref->{'in'};
if (!$in) {LogIt(445,"LOCAL_CMD:No 'in' defined in parmref! CMD=$cmd");}
if (ref($in) ne 'HASH') {LogIt(446,"LOCAL_CMD:'in' spec in parmref is NOT a hash reference! CMD=$cmd");}
my $out   = $parmref->{'out'};
if (!$out) {LogIt(450,"LOCAL_CMD:No 'out' defined in parmref! CMD=$cmd");}
if (ref($out) ne 'HASH') {LogIt(451,"LOCAL_CMD:Out spec in parmref is NOT a hash reference! CMD=$cmd");}
my $outsave = $out;
my $db = $parmref->{'database'};
my $rc = 0;
if ($cmd eq 'init') {
$model = LOCAL;
foreach my $key (keys %{$radio_limits{$model}}) {
$defref->{$key} = $radio_limits{$model}{$key};
}
$defref->{'model'} = $model;
@gui_modestring = ('FM','WFM','AM','LSB','USB','CW','CW-R','RTTY','RTTY-R');
@gui_bandwidth = @bandwidthstring;
@gui_adtype = ();
@gui_attstring = @attstring;
@gui_tonestring = @alltones;
$defref->{'delay'} = 3000;
$local_vfo{'signal'} = 0;
return ($parmref->{'rc'} = $GoodCode);
}### Init
elsif ($cmd eq 'manual') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'vfoinit') {
$local_vfo{'signal'} = 0;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'meminit') {
$local_vfo{'signal'} = 0;
my $channel = 1;
$local_vfo{'channel'} = $channel;
foreach my $key (keys %{$local{'freq'}[$channel]}) {
my $value = $local{'freq'}[$channel]{$key};
$local_vfo{$key} = $value;
$out->{$key} = $value;
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'poll') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getvfo') {
foreach my $key ('frequency','mode','preamp','sqtone','atten',
'service',) {
my $value = $local_vfo{$key};
if (!$value) {
if ($key =~ /mode/i) {$value = 'FMn';}
elsif ($key =~ /tone/i) {$value = 'off';}
else {$value = 0;}
}
$out->{$key} = $value;
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'setvfo') {
my $freq = $in->{'frequency'};
if (!$freq) {
add_message("LOCAL_CMD:SETVFO-VFO frequency = 0 or undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
if (!check_range($freq,$defref)) {
add_message(rc_to_freq($freq) . " MHz is NOT valid for this radio");
return ($parmref->{'rc'} = $NotForModel);
}
foreach my $key ('frequency','mode','sqtone','atten','preamp') {
if (defined $in->{$key}) {
my $value = $in->{$key};
if (!$value) {
if ($key =~ /mode/i) {$value = 'FMn';}
elsif ($key =~ /tone/i) {$value = 'off';}
else {$value = 0;}
}
$local_vfo{$key} = $value;
}
}### For each of the keys
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'selmem') {
my $channel = $in->{'channel'};
if (!looks_like_number($channel)) {
add_message("LOCAL l649:Channel $channel is not numeric.");
return ($parmref->{'rc'} = $ParmErr);
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
add_message("LOCAL l655:Channel $channel out of range for radio");
return ($parmref->{'rc'} = $NotForModel);
}
if ($local{'freq'}[$channel]{'index'}) {
foreach my $key (keys %{$local{'freq'}[$channel]}) {
$out->{$key} = $local{'freq'}[$channel]{$key};
$local_vfo{$key} = $local{'freq'}[$channel]{$key};
}
}
else {
$out->{'frequency'} = 0;
$out->{'mode'} = '';
}
return ($parmref->{'rc'} = $GoodCode);
}### selmem
elsif ($cmd eq 'getmem') {
my $startstate = $progstate;
my $maxcount = scalar @{$local{'freq'}};
my $maxchan = $maxcount -1;
print "Maxcount=>$maxcount maxchan=>$maxchan\n";
my $channel =  $defref->{'origin'};
my $nodup = FALSE;
my $noskip = FALSE;
my $options = $parmref->{'options'};
if ($options) {
if ($options->{'count'}) {$maxcount = $in->{'count'};}
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
my $sysno = $db->{'system'}[1]{'index'};
if ($sysno and $nodup) {
}
else {
my %sysrec = ('systemtype' => 'CNV','service' => "Simulated Radio System", 'valid' => TRUE);
$sysno = add_a_record($db,'system',\%sysrec,$parmref->{'gui'});
}
CHANLOOP:
foreach my $freqrec (@{$local{'freq'}}) {
my $channel = $freqrec->{'index'};
if (!$channel) {next;}
my $grpndx = $local{'freq'}[$channel]{'groupno'};
my $dbgndx = $local{'group'}[$grpndx]{'dbgndx'};
if (!$dbgndx) {
my %grouprec = ('sysno' => $sysno, 'valid' => TRUE);
my $lgno = $local{'freq'}[$channel]{'groupno'};
if ($lgno) {
$grouprec{'service'} = $local{'group'}[$lgno]{'service'};
}
else {
print "LOCAL l818 lgno for channel $channel is undefined=>",Dumper($local{'freq'}[$channel]),"\n";
$grouprec{'service'} = '';
}
$dbgndx = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$local{'group'}[$grpndx]{'dbgndx'} = $dbgndx;
}
$vfo{'channel'} = $channel;
$vfo{'groupno'} = $dbgndx;
threads->yield;
if ($progstate ne $startstate) {
if ($Debug2) {DebugIt("Exited loop as progstate changed");}
last CHANLOOP;
}
if ($nodup and $duplist{$channel}) {next CHANLOOP;}
my $freq = $local{'freq'}[$channel]{'frequency'};
if ($freq or $noskip) {
my %rec = ();
foreach my $key (keys %{$local{'freq'}[$channel]}) {
$rec{$key} = $local{'freq'}[$channel]{$key};
}
$rec{'groupno'} = $dbgndx;
add_a_record($db,'freq',\%rec,$parmref->{'gui'});
}
$channel++;
}### Channel loop
GETDONE:
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'setmem') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getglob') {
foreach my $rec (@searchsamp) {
add_a_record($db,'search',$rec,$parmref->{'gui'});
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'setglob') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getsrch') {
foreach my $rec (@{$local{'search'}}) {
$rec->{'srch_ndx'} = 'C0';
add_a_record($db,'search',$rec,$parmref->{'gui'});
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'setsrch') {
return $NotForModel;
foreach my $rec (@{$db->{'search'}}) {
if (!$rec->{'index'}) {next;}
add_a_record(\%local,'search',$rec,$parmref->{'gui'});
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getinfo') {
bearcat_cmd('init',$parmref);
$out->{'chan_count'} = (scalar @{$local{'freq'}}) - 1;
$out->{'model'} = 'Local';
return ($parmref->{'rc'});
}
elsif ($cmd eq 'getsig') {
foreach my $key (keys %local_vfo) {
$out->{$key} = $local_vfo{$key};
}
if ($local_vfo{'signal'}) {
$out->{'sql'} = TRUE;
}
else {$out->{'sql'} = FALSE;}
return ($parmref->{'rc'} = $GoodCode);
}### GetSig
elsif ($cmd =~ /auto/i) {
}
else {LogIt(4522,"LOCAL_CMD:Unhandled command $cmd");}
return ($parmref->{'rc'} = $rc);
}
