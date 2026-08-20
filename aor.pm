#!/usr/bin/perl -w
package aor;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(aor_cmd rcchan2aor aorchan2rc rcmode2aor aormode2rc) ;
use strict;
use Data::Dumper;
use Text::ParseWords;
use Scalar::Util qw(looks_like_number);
use radioctl;
use constant AOR_TERMINATOR => pack("H4","0D0A");
use autovivification;
no  autovivification;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );
use Device::SerialPort qw ( :PARAM :STAT 0.07 );
my $model = 'AOR-DV1';
my %state_save = (
'state' => '',
'mode'  => '',
);
my $alpha = 'ABCDEFGHIJabcdefghij';
my @aor_ctcs = ('Off','67.0');
foreach my $tone (@alltones) {
if ($tone =~ /\./) { 
if ($tone =~ /123/) {
push @aor_ctcs,"120.0";
}
push @aor_ctcs,Strip($tone);
}
}
my %ctcss_aor = ();
foreach my $ndx (0.. $#aor_ctcs) {
my $key = $aor_ctcs[$ndx];
$ctcss_aor{$key} = $ndx;
}
my %if2mode = (
'fm' => {
'0' => 'FMw',
'1' => 'FMw',
'2' => 'FM',
'3' => 'FMn',
'4' => 'FMu',
},
'am' => {
'0' => 'AMw',
'1' => 'AMm',
'2' => 'AM',
'3' => 'AMn',
},
);### Bandwidth definitions
my %mode2if = (
'fmw' => 0,
'fmm' => 2,
'fm'  => 2,
'fmn' => 3,
'fmu' => 4,
'amw' => 0,
'amm' => 1,
'am'  => 2,
'amn' => 3,
);
my $protoname = 'aor';
use constant PROTO_NUMBER => 6;
$Radio_Routine{$protoname} = \&aor_cmd;
$Radio_Validation{$protoname} = 'RX';
return TRUE;
sub aor_cmd {
my $cmdcode = shift @_;
if (!$cmdcode) {LogIt(779,"AOR_CMD:No command code specified");}
my ($pkg,$fn,$caller) = caller;
my $parmref = shift @_;
if (!$parmref) {LogIt(782,"AOR_CMD:No parmref reference specified. Command=>$cmdcode");}
if (ref($parmref) ne 'HASH') {LogIt(783,"AOR_CMD:parmref is NOT a reference to a hash! CMD=$cmdcode");}
if (!$parmref->{'def'}) {LogIt(786,"AOR_CMD:No 'def' specified in parmref");}
my $defref    = $parmref->{'def'};
if (ref($defref) ne 'HASH') {LogIt(788,"AOR_CMD:defref is NOT a reference to a hash! CMD=$cmdcode");}
my $out  = $parmref->{'out'};
if (!$out) {
LogIt(792,"AOR_CMD:No 'out' defined in parmref! Command=>$cmdcode fn=>$fn Caller=>$caller");
}
if (ref($out) ne 'HASH') {LogIt(793,"AOR_CMD:Out spec in parmref is NOT a hash reference! CMD=$cmdcode");}
my $outsave = $out;
if (!$parmref->{'portobj'}) {LogIt(797,"AOR_CMD:No portobj in parmref! CMD=$cmdcode");}
my $portobj = $parmref->{'portobj'};
my $db = $parmref->{'database'};
if ($db) {
if (ref($db) ne 'HASH') {LogIt(584,"AOR_CMD:Database spec in parmref is NOT a hash reference! CMD=$cmdcode");}
}
else {$db = '';}
my $write = $parmref->{'write'};
if (!$write) {$write = FALSE;}
my $in   = $parmref->{'in'};
if ($in) {
if (ref($in) ne 'HASH') {LogIt(580,"IN spec in parmref is NOT a hash reference! CMD=$cmdcode");}
}
else {$in = '';}
my $insave = $in;
my $delay = 400;
$parmref->{'rc'} = $GoodCode;
my $parmstr = '';
if ($Debug1) {LogIt(0,"AOR_CMD:command=$cmdcode");}
my $countout = 0;
my $instr= "";
my $rc = 0 ;
my $data_in;
my $count_in;
my $hex_data;
my $gotit = FALSE;
my $radio_set = $out;
my $channel = 0;
if ($cmdcode eq 'init') {
$delay = 500;
$parmref->{'write'} = FALSE;
$model = $defref->{'model'};
if (!$model) {$model = '';}
if ((!$model) or ($model =~ /dv/i))   {
my $rc = aor_cmd('WI',$parmref);
print "Finished 'WI' command\n";
if ($out->{'model'}) {$model = $out->{'model'};}
}
if ($model !~ /dv/i) {
$in->{'aorchan'} = -1;
my $rc = aor_cmd('MR',$parmref);
if ($out->{'aorchan'} and (looks_like_number($out->{'aorchan'}))) {
if ((!$model) or ($model =~ /8000/)) {
$model = 'AR5000';
}
}
else { $model = 'AR8000';}
print "AOR l973:Verified model to be $model\n";
}
$defref->{'model'} = $model;
$defref->{'sigdet'} = 2;
$defref->{'radioscan'} = 2;
$defref->{'maxchan'} = 1000;
$defref->{'maxfreq'} = 1300000000;
$defref->{'minfreq'} = 100000;
$defref->{'searchchan'} = 20;
$defref->{'origin'} = 0;
$defref->{'radioscan'} = 2;
@gui_modestring = ('FM','AM','LSB', 'USB', 'CW');
@gui_adtype = ();
@gui_tonestring = ();
if ($model =~ /8000/) {
}
elsif ($model =~ /dv/i) {
$defref->{'minfreq'} = 100000;
$defref->{'maxchan'} = 2000;
$defref->{'searchchan'} = 40;
if ($model =~ /3/) {
$defref->{'maxfreq'} = 3000000000;
}
else {$defref->{'maxfreq'} = 1300000000;}
$defref->{'radioscan'} = 1;
@gui_attstring = ();
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
@gui_adtype = ('ANALOG','P25','NXDN','DMR','DSTAR');
@gui_bandwidth = ('(none)','Wide','Medium','Narrow','U_Narrow');
}
elsif ($model =~ /5/) {
$defref->{'minfreq'} = 10000;
$defref->{'maxfreq'} = 2600000000;
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
}
else {
}
if (aor_cmd('RF',$parmref)) {
print "Issuing 'RF' command..\n";
LogIt(1,"Radio does not appear to be connected");
return ($parmref->{'rc'});
}
if ($out->{'channel'}) {$vfo{'channel'} = $out->{'channel'};}
else {$vfo{'channel'} = 0;}
aor_cmd('EX',$parmref);
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
print "AOR Init complete\n";
return ($parmref->{'rc'} = 0);
}
elsif ($cmdcode eq 'scan') {
if ($defref->{'radioscan'} == 2) {
if (aor_cmd('MS',$parmref)) {
LogIt(1,"Radio rejected MS command!");
return ($parmref->{'rc'} = $ParmErr);
}
}
aor_cmd('EX',$parmref);
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'poll') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'getvfo') {
if (!$outsave) {LogIt(684,"No 'out' reference in parmref for GETVFO call!");}
aor_cmd('getsig',$parmref);
if (!defined $out->{'channel'}) {$out->{'channel'} = 0;}
my $mode = $out->{'mode'};
my $adtype = $out->{'adtype'};
if ($model =~ /dv/i) {
if (($mode =~ /fm/i) or ($mode =~ /am/i)) {
$parmref->{'write'} = FALSE;
my $modekey = substr(lc(Strip($mode)),0,2);
aor_cmd('IF',$parmref);
my $ikey = $out->{'bw'};
$out->{'mode'} = $if2mode{$modekey}{$ikey};
if (!$out->{'mode'}) {
LogIt(1,"AOR 1129: Failed lookup for $modekey $ikey");
$out->{'mode'} = $mode;
}
}
}
if (($model !~ /8000/) and ($mode =~ /fm/i) and ($adtype =~ /an/i)) {
$out->{'sqtone'} = get_tones($parmref);
}
aor_cmd('EX',$parmref);
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'getsig') {
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
$out->{'rssi'} = '0';
my %outsave = ();
if ($model !~ /dv/i) {
if (aor_cmd('LM',$parmref)) {return $parmref->{'rc'};}
}
aor_cmd('RX',$parmref);
aor_cmd('EX',$parmref);
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'setvfo') {
my $sqtone = $in->{'sqtone'};
my $freq = $in->{'frequency'};
my $atten = $in->{'atten'};
my $mode = $in->{'mode'};
my $adtype = $in->{'adtype'};
if (!$adtype) {$adtype = 'AN';}
if (!$freq) {
add_message("AOR_CMD_1201:VFO frequency = 0 or undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
my %myout = ();
my %myin = ();
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
aor_cmd('RX',$parmref);
if (($myout{'state'} !~ /^v/i) and ($myout{'state'} !~ /dd/)) {
$parmref->{'write'} = FALSE;
if ($model =~ /dv/i) {
%myin = ('VFO' => 'A');
aor_cmd('VF',$parmref);
}
else {
aor_cmd("VA",$parmref);
}
}
else {
}
$parmref->{'write'} = TRUE;
%myin = ('frequency' => $freq);
aor_cmd('RF',$parmref);
if ($mode) {
%myin = ('mode' => $mode);
aor_cmd('MD',$parmref);
if ($model =~ /dv/i) {
my ($code,$bw) = rcmode2aor($mode,$adtype,$model);
%myin = ('bw' => $bw);
$parmref->{'write'} = TRUE;
aor_cmd('IF',$parmref);
}### DV-1
}
if ((defined($atten)) and ($model =~ /8000/i)) {
%myin = ('atten' => $atten);
aor_cmd('AT',$parmref);
}
if ($sqtone and ($model !~ /8000/) and ($adtype =~ /an/i)) {
my $rc = set_tones($sqtone,$parmref);
if ($rc) {
LogIt(1,"failed to set tone $sqtone");
}
}
VFODONE:
$parmref->{'out'} = $outsave;
$parmref->{'write'} = FALSE;
aor_cmd('EX',$parmref);
return $parmref->{$GoodCode};
}
elsif ($cmdcode eq 'selmem') {
my $maxcount = $defref->{'maxchan'};
my $channel =  $defref->{'origin'};
my $maxbank = int($maxcount/50) - 1;
my $maxchan = $maxcount -1;
my $ch = $in->{'channel'};
if (!defined $ch) {
LogIt(1,"AOR_CMD_l1207:Undefined channel number. Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if (!looks_like_number($ch)) {
LogIt(1,"AOR_CMD_l1211:Non-Numeric channel number $ch. Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($channel > $maxchan) {
LogIt(1,"AOR_CMD_l1215:Channel $ch out of range of radio. Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($ch < 0) {
my $gui_save = $parmref->{'gui'};
if ($model =~ /8000/) {
$ch = 0;
}
else {
print "Looking for the next available channel..\n";
my %db = ();
my %myout = ();
my %myin = ('database' => \%db,'model' => $model);
$parmref->{'out'} = \%myout;
$parmref->{'in'} = \%myin;
$parmref->{'gui'} = '';
foreach my $bank (0..$maxbank) {
%db = ();
my $rc = aor_cmd('MA',$parmref);
if (!$db{'freq'}[1]) {
print "Nothing stored in bank $bank\n";
next;
}
$ch = $db{'freq'}[1]{'channel'};
print "AOR l1245: Located first active channel $ch\n";
last;
}### For every bank
}###  Not the AR80000
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
$parmref->{'gui'} = $gui_save;
if ($ch < 0) {
LogIt(1,"No memory channels were found");
$out->{'frequency'} = 0;
$out->{'channel'} = -1;
return ($parmref->{'rc'} = $EmptyChan);
}
else {$in->{'channel'} = $ch;}
}### Specified channel < 0
$parmref->{'write'} = FALSE;
$ch = $in->{'channel'};
my $rc = aor_cmd ('MR',$parmref);
if ($rc) {
$out->{'frequency'} = 0;
$out->{'mode'} = 'FMn';
$out->{'service'} = '';
return ($parmref->{'rc'} = $EmptyChan);
}
aor_cmd('RX',$parmref);
if ($out->{'channel'} eq '-1') {
$out->{'channel'} = $ch;
$out->{'valid'} = FALSE;
}
aor_cmd('EX',$parmref);
return $parmref->{'rc'};
}### Selmem
elsif ($cmdcode eq 'getmem') {
if ($Debug2) {LogIt(0,"AOR_CMD l526 starting 'getmem'");}
if (!$in) {LogIt(1288,"AOR_CMD:No 'in' defined for GETMEM");}
if (!$db) {LogIt(1280,"AOR_CMD:No database reference for GETMEM");}
my $startstate = $progstate;
my $maxcount = $defref->{'maxchan'};
my $channel =  $defref->{'origin'};
my $maxbank = int($maxcount/50) - 1;
my $maxchan = $maxcount -1;
my $nodup = FALSE;
my $noskip = FALSE;
my $options = $parmref->{'options'};
if ($options) {
if ($options->{'count'}) {$maxcount = $options->{'count'};}
if ($options->{'firstchan'} and ($options->{'firstchan'} > 0)) {
$channel = $options->{'firstchan'};
}
my $lastchan = $options->{'lastchan'};
if ($lastchan and ($lastchan < $maxchan)) {
$maxchan = $lastchan
}
if ($options->{'noskip'}) {$noskip = TRUE;}
if ($options->{'nodup'}) {$nodup = TRUE;}
}
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
my %sysrec = ('systemtype' => 'CNV','service' => "AOR model $model", 'valid' => TRUE);
$sysno = add_a_record($db,'system',\%sysrec,$parmref->{'gui'});
}
LogIt(0,"getting system $sysno data for $model...");
my $freqrecs = $db->{'freq'};
if ($model =~ /8000/i) {goto FETCH_8000;}
my $lastrec = $freqrecs->[-1];
foreach my $bank (0..$maxbank) {
threads->yield;
if ($progstate ne $startstate) {goto GETDONE;}
print STDERR "\rReading bank:$Bold$Green" . sprintf("%02.2u",$bank) . $Reset ;
my $grpno = 1;
my $nextndx = 0;
my $lastrec = $freqrecs->[-1];
if (defined $lastrec) {
$nextndx = $lastrec->{'index'};
}
%myin = (
'database' => $db,
'aorbank' => sprintf("%02.2u",$bank),
'sysno' => $sysno,
'groupno' => $grpno,
'model' => $model,
'noskip' => $noskip,
);
my $needgroup = TRUE;
if ($model =~ /8000/) {
$myin{'aorbank'} = substr($alpha,$bank,1);
}
aor_cmd('MA',$parmref);
CHANFETCH:
foreach my $ch (0..49) {
threads->yield;
if ($progstate ne $startstate) {goto GETDONE;}
$nextndx++;
my $freqrec = $freqrecs->[$nextndx];
if (!$freqrec->{'index'}) {last CHANFETCH;}
if ($needgroup) {
my %grouprec = ('sysno' =>$sysno,'service' => "AOR Group $bank", 'valid' => TRUE);
$grpno = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$needgroup = FALSE;
}
$freqrec->{'groupno'} = $grpno;
my $freq = $freqrec->{'frequency'};
if ($freq) {
my $mode = $freqrec->{'mode'};
my $audio = $freqrec->{'adtype'};
if (($audio =~ /an/i) and ($model =~ /dv/i)) {
$myin{'channel'} = $freqrec->{'channel'};
aor_cmd('MR',$parmref);
aor_cmd('IF',$parmref);
if ($mode =~ /fm/i) {
if (defined $myout{'bw'}) {
if ($myout{'bw'} == 4) {$freqrec->{'mode'} = 'FMn';}
elsif ($myout{'bw'} == 0) {$freqrec->{'mode'} = 'WF';}
else {$freqrec->{'mode'} = 'FM';}
}
else {
print "AOR 1439 'IF; command returned=>",Dumper(%myout),"\n";
}
}### FM Modulation
}### Analog Audio
$freqrec->{'sqtone'} = 'Off';
if (($mode =~ /fm/i) and ($audio =~ /an/)) {
$freqrec->{'sqtone'} = get_tones($parmref);
}
}### Frequency not 0
$count++;
}### Channel process
}### Bank fetch
goto GETDONE;
FETCH_8000:
foreach my $bank (split '',$alpha) {
my $grpno = 0;
my $needgroup = TRUE;
foreach my $chan (0..49) {
$in->{'channel'} = $channel;
threads->yield;
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green" . sprintf("%04.4u",$channel) . $Reset ;
}
if ($progstate ne $startstate) {last FETCH_8000;}
%myout  = ('frequency' => 0);
%myin = ('channel' => $channel);
aor_cmd('MR',$parmref);
if ($myout{'frequency'} or $noskip) {
if ($needgroup) {
my %grouprec = ('sysno' =>$sysno,'service' => "AOR Group $bank", 'valid' => TRUE);
$grpno = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$needgroup = FALSE;
}
my %freqrec = (
'channel' => $channel,
'groupno' => $grpno,
'sqtone' => 'Off',
);
foreach my $key ('frequency','mode','valid','service','att') {
$freqrec{$key} = $myout{$key};
}
add_a_record($db,'freq',\%freqrec,$parmref->{'gui'});
$count++;
}
$channel++;
}### For every channel in this AOR group
}### For every group in the radio
GETDONE:
aor_cmd('EX',$parmref);
$parmref->{'out'} = $outsave;
$outsave->{'count'} = $count;
$out->{'sysno'} = $sysno;
return ($parmref->{'rc'} = $GoodCode) ;
}### GETSYS process
elsif ($cmdcode eq 'setmem') {
if (!$in) {LogIt(1076,"AOR_CMD:No 'in' defined for SETMEM");}
if (!$db) {LogIt(1076,"AOR_CMD:No database reference for SETMEM");}
if ($Debug1) {LogIt(0,"Processing AOR SETMEM command");}
my $options = $parmref->{'options'};
my $max_count = $defref->{'maxchan'};
if ($options->{'count'}) {$max_count = $options->{'count'};}
my %found_chan = ();
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
my $count = 0;
my $deleted = 0;
if ($model =~ /8000/) {
aor_cmd('MR',$parmref);
}
my @to_delete = ();
my @to_write = ();
foreach my $frqrec (@{$db->{'freq'}}) {
if (!defined $frqrec->{'index'}) {next;}
my $recno = $frqrec->{'_recno'};
if (!$recno) {$recno = '??';}
my $emsg = "in record $recno";
if ($frqrec->{'tgid_valid'}) {next;}
my $channel = $frqrec->{'channel'};
my $aorchan = $frqrec->{'aorchan'};
if ((defined $aorchan) and (looks_like_number($aorchan))) {
$channel = $aorchan;
}
if ((!looks_like_number($channel)) or ($channel < 0) ) {
next;
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
next;
}
if ($found_chan{$channel}) {
next;
}
my $aor_chan = rcchan2aor($channel,$model);
if ($aor_chan eq '-1') {next;}
$found_chan{$channel} = TRUE;
my $freq = $frqrec->{'frequency'};
if (!$freq) {
%myin = ('channel' => $channel);
my $rc = aor_cmd('MR',$parmref);
if ($rc) {next;}
if (($model =~ /8000/) and (!$myout{'frequency'})) {next;}
push @to_delete,$channel;
next;
}
else {
print STDERR "\rSETMEM: Writing channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset,
" freq=>$Yellow",rc_to_freq($freq),$Reset;
%myin = ('channel' => $channel);
foreach my $key ('frequency','valid','adtype',
'mode','service') {
my $value = $frqrec->{$key};
if ($key eq 'mode') {
if (lc($value) eq 'auto') {$value = AutoMode($freq);}
}
$myin{$key} = $value;
}### Set keys for the memory
if ($model =~ /8000/) {
$myin{'atten'} = $frqrec->{'atten'};
}
my $rc =  aor_cmd('MX',$parmref);
if ($rc) {
LogIt(1,"Radio rejected write of channel $channel");
next;
}
$count++;
}### Write the basic stuff for this channel
my %record = (
'channel'  => $channel,
'aor_chan' =>$aorchan,
'mode'     => $frqrec->{'mode'},
'adtype'   => $frqrec->{'adtype'},
'sqtone'   => $frqrec->{'sqtone'},
);
push @to_write,{%record};
}### For every Frequency record in the database
if ($model =~ /dv/i) {
$parmref->{'write'} = FALSE;
%myout = ('vfo' => 'A', 'channel' => $channel);
aor_cmd('VF',$parmref);
dv_delay($parmref);
aor_cmd('MR',$parmref);
}
print STDERR "\n";
foreach my $rec (@to_write) {
my $channel = $rec->{'channel'};
print STDERR "\rSETMEM: Writing extra fields for channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset;
if (($model !~ /8000/) and
($rec->{'adtype'} =~ /an/i) and
($rec->{'mode'} =~ /fm/i)) {
%myin = ('channel' => $channel);
if (aor_cmd('MR',$parmref)) {
LogIt(1,"\n Could not set channel $channel for tone setting!");
next;
}
my $rc = set_tones($rec->{'sqtone'},$parmref);
if ($rc) {
LogIt(1,"\n$rec->{'sqtone'} (channel $rec->{'channel'}) " .
"is not valid for this radio!");
}
}### Tone conditions met
if ($model =~ /dv/i) {
my ($md,$bw) = rcmode2aor($rec->{'mode'},$rec->{'adtype'},$model);
%myin = ('bw' => $bw, 'vfo' => 'A', 'channel' => $channel);
if (aor_cmd('MR',$parmref)) {
LogIt(1,"\n Could not set channel $channel for tone setting!");
next;
}
$parmref->{'write'} = TRUE;
aor_cmd('IF',$parmref);
}### Model is DV-1/DV-3
}### For each second pass record
print STDERR "\n";
foreach my $channel (@to_delete) {
print STDERR "\rSETMEM: Deleting channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset;
%myin = ('channel' => $channel);
if ($model =~ /8000/) {aor_cmd('MR',$parmref);}
aor_cmd('MQ',$parmref);
$deleted++;
}
if ($model =~ /dv/i) {
%myin = ('vfo' => 'A', 'channel' => $channel);
aor_cmd('VF',$parmref);
dv_delay($parmref);
aor_cmd('MR',$parmref);
}
$out->{'count'} = $count;
print STDERR "\n\n";
LogIt(0,"$count records were stored in the radio");
if ($deleted) {
LogIt(0,"$deleted records were removed from the radio");
}
aor_cmd('EX',$parmref);
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
$parmref->{'write'} = $writesave;
return $parmref->{'rc'};
}### SETMEM
elsif ($cmdcode eq 'getsrch') {
if ($Debug2) {DebugIt("AOR_CMD:Starting 'getsrch' command");}
my $options = $parmref->{'options'};
my $noskip = FALSE;
if ($options) {
if ($options->{'noskip'}) {$noskip = TRUE;}
}
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
my $retcode =  $NotForModel;
my $count = 0;
my $srch_max = $defref->{'searchchan'}-1;
if (!$srch_max) {$srch_max = 20;}
foreach my $bank (0..$srch_max) {
if (!$parmref->{'gui'}) {
print STDERR "\rReading Bank:$Bold$Green" . sprintf("%08.8u",$bank) . $Reset ;
if ($model =~ /8000/) {
$myin{'bank'} = substr($alpha,$bank,1);
}
else {
$myin{'bank'} = sprintf("%02.2u",$bank);
}
my  $rc = aor_cmd('SR',$parmref);
if ($rc) {
if ($rc == $EmptyChan) {
if (!$noskip) {next;}
}
else {next;}
}
my %search = (
'valid' => TRUE,
'start_freq' => $myout{'start_freq'},
'end_freq' => $myout{'end_freq'},
'step' => $myout{'step'},
'mode' => $myout{'mode'},
'channel' => $bank,
'service' => $myout{'service'},
);
add_a_record($db,'search',\%search,$parmref->{'gui'});
$count++;
}
}### For each bank
aor_cmd('EX',$parmref);
$parmref->{'write'} = $writesave;
$parmref->{'out'} = $outsave;
print STDERR "$Eol$Bold$Green$count$White search records were Fetched$Eol";
return ($parmref->{'rc'} = $GoodCode);
}### Getsrch
elsif ($cmdcode eq 'setsrch') {
if ($Debug2) {DebugIt("AOR_CMD:Starting 'setsrch' command");}
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
my $valid_channel = 0;
if ($model =~ /dv/i) {
$parmref->{'write'} = FALSE;
%myin = ('channel' => -1);
aor_cmd('selmem',$parmref);
$valid_channel = $out->{'channel'};
}
$parmref->{'write'} = FALSE;
if ($model =~ /dv/i) {
%myin = ('VFO' => 'A');
aor_cmd('VF',$parmref);
}
else {aor_cmd('VA',$parmref);}
my @special = (
{'empty' => TRUE,'channel' => '00', 'start_freq' => 30000000,
'end_freq' => 31000000, 'step'=> 10000, 'mode' => 'FMn',
'service' => 'Dummy-1','special' => 1,
},
{'empty' => TRUE,'channel' => '39', 'start_freq' => 30000000,
'end_freq' => 31000000, 'step'=> 10000, 'mode' => 'FMn',
'service' => 'Dummy-2','special' => 2,
},
);
if ($model =~ /dv/i) {
foreach my $ndx (0,1) {
$myin{'bank'} = $special[$ndx]{'channel'};
my $rc = aor_cmd('SR',$parmref);
if (!$rc) {### If this worked, there is data in this channel
foreach my $key ('start_freq','end_freq','step','mode','service') {
$special[$ndx]{$key} = $myout{$key};
}
$special[$ndx]{'empty'} = FALSE;
}### Search bank has data
}### For each special channel
}### DV-1/DV-3 channel 0 & 39 fetch
$parmref->{'write'} = TRUE;
my $retcode =  $NotForModel;
my $count = 0;
my $max_chan =  $defref->{'searchchan'};
if (!$max_chan) {$max_chan = 20;}
my $srch_max = $max_chan - 1;
my %clear_chan = ();
my %active_chan = ();
foreach my $rec (@{$db->{'search'}}) {
if (!$rec->{'index'}) {next;}
my $ch = $rec->{'channel'};
if (!defined $ch) {next;}
if (!looks_like_number($ch)) {next;}
if ($ch > $max_chan) {
LogIt(1,"Search channel $ch in record $rec->{'_recno'} ".
"exceeds radio's maximum ($max_chan). Ignored!");
next;
}
if ($ch >= 0) {
if ($rec->{'start_freq'}) {
if ($active_chan{$ch}) {
LogIt(1,"Duplicate search channel $ch found in record " .
$rec->{'_recno'} . " Ignored!");
next;
}
$active_chan{$ch} = $rec;
}### Non-zero frequency
else {
if ($clear_chan{$ch}) {
LogIt(1,"Duplicate clear search channel $ch found in record " .
$rec->{'_recno'} . " Ignored!");
next;
}
else {$clear_chan{$ch} = $rec;}
}
}### Channel specified and
}### First pass
my $curchan = 0;
FINDCHAN:
foreach my $rec (@{$db->{'search'}}) {
if (!$rec->{'index'}) {next;}
my $ch = $rec->{'channel'};
if (!defined $ch) {$ch = -1;}
elsif (!looks_like_number($ch)) {$ch = -1;}
if ($ch >= 0) {next;}
if ((!$rec->{'start_freq'}) or (!$rec->{'end_freq'})) {
LogIt(1,"Search record with 0 start/end frequency cannot be used ".
"without a channel number (record=$rec->{'_recno'}). Ignored!");
next;
}
while ($active_chan{$curchan} or ($clear_chan{$curchan})) {
$curchan++;
if ($curchan > $srch_max) {
$rec->{'channel'} = -1;
last;
}
}
if ($curchan > $srch_max) {
LogIt(1,"Maximum search channels reached. " .
" Some records may not be stored!");
last FINDCHAN;
}
$rec->{'channel'} = $curchan;
$active_chan{$curchan} = $rec;
}#### Locate channels without numbers
if ($model =~ /dv/i) {
my $ndx = 0;
foreach my $ch (0,39) {
if (!$active_chan{$ch}) {
$active_chan{$ch} = $special[$ndx];
if ($special[$ch]{'empty'}) {
$clear_chan{$ch} = $special[$ndx];
}
$ndx++;
}
}## Min and Max channel numbers
}### DV-1/DV-3 code
my @chan_list = sort Numerically keys %active_chan;
my $bank_count = scalar @chan_list;
if (!$bank_count) {
LogIt(1,"No SEARCH records were found to store!");
}
foreach my $bank (@chan_list) {
my $rec = $active_chan{$bank};
%myin = ();
if ($model =~ /8000/) {
$myin{'bank'} = substr($alpha,$bank,1);
}
else {
$myin{'bank'} = sprintf("%02.2u",$bank);
}
foreach my $key ('start_freq','end_freq','step','mode','service') {
$myin{$key} = $rec->{$key};
}
if ($model !~ /dv/i) {
$myin{'atten'} = $rec->{'atten'};
}
print "Setting search bank $bank..\n";
$parmref->{'write'} = TRUE;
aor_cmd('SE',$parmref);
if ($model =~ /dv/i) {
my $rec = $active_chan{0};
if ($bank < 20) {$rec = $active_chan{39};}
foreach my $key ('start_freq','end_freq','step','mode','service') {
$myin{$key} = $rec->{$key};
}
$myin{'bank'} = $rec->{'channel'};
$parmref->{'write'} = TRUE;
aor_cmd('SE',$parmref);
sleep 1;
}### DV-1/DV-3 Flush
$count++;
}### For all search records
if ($model =~ /dv/i) {
my @delist = sort Numerically keys %clear_chan;
if ((!scalar @delist) and (!$bank_count)) {
LogIt(1,"No search memories were updated!");
}
foreach my $bank (@delist) {
print "clearing $bank\n";
%myin = ('bank' =>$bank);
aor_cmd('SX',$parmref);
if ($active_chan{$bank}) {
my $rec = $active_chan{$bank};
if ($rec->{'special'}) {$count--;}
}
if ($valid_channel) {
%myin = ('VFO' => 'A','channel' => $valid_channel);
aor_cmd('MR',$parmref);
sleep 1;
aor_cmd('VF',$parmref);
sleep 1;
}
}### For each deleted record
if ($valid_channel) {
%myin = ('VFO' => 'A','channel' => $valid_channel);
aor_cmd('MR',$parmref);
sleep 1;
aor_cmd('VF',$parmref);
sleep 1;
}
else {
LogIt(1,"Please press VFO and SCAN buttons to assure write of data!");
}
}### DV-1/DV-3
print STDERR "$Eol$Bold$Green$count$White search records were Stored$Eol";
aor_cmd('EX',$parmref);
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = $GoodCode);
}### setsrch
elsif ($cmdcode eq 'getglob') {
if ($model =~ /8000/) {return ($parmref->{'rc'} = $GoodCode);}
if (!$db) {LogIt(2666,"AOR_CMD:No 'database' defined in parmref for GETGLOB");}
if ($Debug2) {DebugIt("AOR_CMD:Starting 'getglob' command");}
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
aor_cmd('BP',$parmref);
my %record = ('beep' => $myout{'beep'});
if ($model =~ /dv/i) {
aor_cmd('LB',$parmref);
$record{'light'} = $myout{'light'};
}
add_a_record($db,'global',\%record);
aor_cmd('EX',$parmref);
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = $GoodCode);
}### Getglob
elsif ($cmdcode eq 'setglob') {
if (!$db) {LogIt(2716,"AOR_CMD:No 'database' defined in parmref for SETGLOB");}
if ($Debug2) {DebugIt("AOR_CMD:Starting 'setglob' command");}
if ($model =~ /8000/) {return ($parmref->{'rc'} = $GoodCode);}
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
my $beep = '.';
my $light = '.';
foreach my $rec (@{$db->{'global'}}) {
if (!$rec->{'index'}) {next;}
if (defined $rec->{'light'} and ($rec->{'light'} ne '.'))  {
$light = $rec->{'light'};
}
if (defined $rec->{'beep'} and ($rec->{'beep'} ne '.')) {
$beep = $rec->{'beep'};
}
}
if ($light ne '.') {
$parmref->{'write'} = TRUE;
$myin{'light'} = $light;
print "Setting light to $light\n";
aor_cmd('LB',$parmref);
}
if ($beep ne '.') {
$parmref->{'write'} = TRUE;
$myin{'beep'} = $beep;
aor_cmd('BP',$parmref);
}
aor_cmd('EX',$parmref);
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'test') {
}
elsif ($cmdcode eq 'AC') {
return ($parmref->{'rc'} = $NotForModel);
}
elsif ($cmdcode eq 'AT') {
if ($model !~ /8000/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $att = $in->{'atten'};
if (defined $att) {
$parmstr = "AT$att";
}
else {
LogIt(1,"AOR l2824:Forgot parameter 'atten' for AT call!");
return $ParmErr;
}
}
else {$parmstr = '';}
}
elsif ($cmdcode eq 'BK') {
return ($parmref->{'rc'} = $NotForModel);
}### BK preprocess
elsif ($cmdcode eq 'BN') {
if ($model !~ /8000/) {return $NotForModel;}
if ($parmref->{'write'}) {
my $bank = $in->{'bank'};
if (defined $bank) {
$parmstr = $bank;
}
else {
LogIt(1,"AOR l2824:Forgot parameter 'bank' for BN call!");
return $ParmErr;
}
}
}### BN Preprocess
elsif ($cmdcode eq 'BP') {
if ($model =~ /8000/) {return $NotForModel;}
if ($parmref->{'write'}) {
my $beep = $in->{'beep'};
if (defined $beep) {
my $value = 0;
if (looks_like_number($in->{'beep'})) {
$value = $in->{'beep'};
if ($value > 7) {$value = 7;}
}
$parmstr = $value;
print "AOR 1984:Set beep=>$value\n";
}### Defined value
else {
LogIt(1,"AOR l2029:Forgot parameter 'beep' for BP call!");
return $ParmErr;
}
}### SETing
}### BP-Preprocess
elsif ($cmdcode eq 'CI') {
if ($model !~ /dv1/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $ctc = $in->{'ctc'};
if (defined $ctc) {
$parmstr = $ctc;
}
else {
LogIt(1,"AOR l2967:Forgot parameter 'ctc' for CI call!");
return $ParmErr;
}
}
else {$parmstr = '';}
}### CI command code
elsif ($cmdcode eq 'CN') {
if ($model =~ /8000/) {return $NotForModel;}
if ($parmref->{'write'}) {
my $sqtone = $in->{'tone'};
if (defined $sqtone) {
$parmstr = $sqtone;
}
else {
LogIt(1,"AOR l3003:Forgot parameter 'tone' for $cmdcode call!");
return $ParmErr;
}
}### Set
else {$parmstr = '';}
}### CN command code
elsif ($cmdcode eq 'DI') {
if ($model !~ /dv1/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $dcs = $in->{'dcs'};
if (defined $dcs) {
$parmstr = $dcs;
}
else {
LogIt(1,"AOR l3036:Forgot parameter 'dcs' for $cmdcode call!");
return $ParmErr;
}
}
else {$parmstr = '';}
}
elsif ($cmdcode eq 'DS') {
if ($model =~ /8000/) {return $NotForModel;}
if ($parmref->{'write'}) {
my $sqcode = $in->{'code'};
if (defined $sqcode) {
$parmstr = $sqcode;
}
else {
LogIt(1,"AOR l3066:Forgot parameter 'code' for $cmdcode call!");
return $ParmErr;
}
}### Set
else {$parmstr = '';}
}### DS command code
elsif ($cmdcode eq 'EX') {
if ($model !~ /dv/i) {
return ($NotForModel);
}
$parmstr = '';
}
elsif ($cmdcode eq 'IF') {
if ($model !~ /dv/i) {return $NotForModel;}
if ($parmref->{'write'}) {
if (!defined $in->{'bw'}) {
LogIt(1,"AOR l3113:Forgot 'bw' value for $cmdcode call!");
return $ParmErr;
}
$parmstr = Strip($in->{'bw'});
}
else {$parmstr = '';}
}### Bandwidth
elsif ($cmdcode eq 'LB') {
if ($model !~ /dv/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $value = $in->{'light'};
if (defined $value) {
if ((!$value) or ($value =~ /off/i)) {
$parmstr = '0';
}
elsif ($value =~ /on/i) {$parmstr = '1';}
else {$parmstr = '2';}
}### key was defined
else {
LogIt(1,"AOR l3157:Forgot 'light' value for $cmdcode call!");
return $ParmErr;
}
}### Setting
else {$parmstr = '';}
}
elsif ($cmdcode eq 'LM') {
$parmstr = '';
}
elsif ($cmdcode eq 'MA') {
my $dbase = $in->{'database'};
if ($model =~ /8000/) {
LogIt(1,"Called MA for model AR8000!");
return $NotForModel;
}
if (!$dbase) {LogIt(3274,"MA command requires a database");}
my $aorbank = $in->{'aorbank'};
if (defined $aorbank) {
if (looks_like_number($aorbank)) {
$aorbank = sprintf("%02.2u",$aorbank);
}
$parmstr = $aorbank;
$in->{'aorbank'} = $aorbank;
}
else {
LogIt(1,"AOR l3285: MA command requires a bank spec!");
return $ParmErr;
}
if ((defined $in->{'aorchan'}) and ($in->{'aorchan'} ne '-1')) {
$parmstr = $parmstr . sprintf("%02.2u",$in->{'aorchan'});
$in->{'_chan'} = $in->{'aorchan'};
$in->{'_multi'} = FALSE;
}
else {
$in->{'_chan'} = 0;
$in->{'_multi'} = TRUE;
}
}### MA pre-process
elsif ($cmdcode eq 'MD') {
if ($parmref->{'write'}) {
if (!$in->{'mode'}) {
LogIt(1,"AOR l1587:Missing modulation code for MD call");
return $ParmErr;
}
my $mode = $in->{'mode'};
if (!$mode) {$mode = 'FMn';}
if ($mode =~ /^au/i) {### Auto. Need to set
if ($in->{'frequency'}) {
$mode = AutoMode($in->{'frequency'});
}
else {
LogIt(1,"Need frequency for call to 'MD' for auto. Caller=$caller");
$mode = 'FMn';
}
}
my $adtype = $in->{'adtype'};
if (!$adtype) {$adtype = 'AN';}
my ($code,$bw) = rcmode2aor($mode,$adtype,$model);
$parmstr = $code;
}### SET
else {$parmstr = '';}
}
elsif ($cmdcode eq 'MM') {
$parmstr = '';
}
elsif ($cmdcode eq 'MP') {
if ($parmref->{'write'}) {
if ($in->{'valid'}) {$parmstr = '0';}
else {$parmstr = '1';}
}
}
elsif ($cmdcode eq 'MQ') {
my $ch = $in->{'channel'};
if ((!defined $ch) or (!looks_like_number($ch)) or ($ch < 0)) {
return $ParmErr;
}
my $aorchan = rcchan2aor($ch,$model);
if ($aorchan eq '-1') {return $ParmErr;}
if ($model =~ /8000/) {$parmstr = substr($aorchan,1);}
else {$parmstr = $aorchan;}
$out->{'aorchan'} = $aorchan;
}### MQ
elsif ($cmdcode eq 'MR') {
my $ch = $in->{'channel'};
if (!defined $ch) {return $ParmErr;}
my $aorchan = rcchan2aor($ch,$model);
if ($aorchan eq '-1') {return $NotForModel;}
$out->{'aorchan'} = $aorchan;
$parmstr = $aorchan;
}### MR
elsif ($cmdcode eq 'MS') {
$parmstr = '';
}
elsif ($cmdcode eq 'MX') {
my $channel = $in->{'channel'};
if (!defined $channel) {
LogIt(3660,"Forgot channel for call to MX!");
}
if (!defined $in->{'frequency'}) {
LogIt(3664,"Forgot frequency for call to MX!");
}
my $aorchan = rcchan2aor($channel,$model);
if ($aorchan eq '-1') {return $NotForModel;}
$parmstr = "$aorchan " . set_keys($in,$model);
}### MX
elsif ($cmdcode eq 'RF') {
if ($parmref->{'write'}) {
if (!$in) {LogIt(1915,"AOR:Missing IN for AC  command!");}
my $freq = $in->{'frequency'};
if (!$freq) {
LogIt(1,"AOR l1918:0 frequency for VFO set");
return $ParmErr;
}
if (($freq !~ /\./) and ($model =~ /dv/i)) {
$freq =  Strip(rc_to_freq($freq));
}
$parmstr = $freq;
}
else {$parmstr = '';}
}### RF
elsif ($cmdcode eq 'RX') {
$parmstr = '';
}
elsif ($cmdcode eq 'SE') {
if (defined $in->{'bank'}) {
$parmstr = "$in->{'bank'} " . set_keys($in,$model);
}
else {
LogIt(1,"Forgot bank code for SR!");
return $ParmErr;
}
}
elsif ($cmdcode eq 'SR') {
if (defined $in->{'bank'}) {
$parmstr = $in->{'bank'};}
else {
LogIt(1,"Forgot bank code for SR!");
return $ParmErr;
}
}
elsif ($cmdcode eq 'SX') {
if ($model !~ /dv/i) {return $NotForModel;}
if (defined $in->{'bank'}) {
$parmstr = $in->{'bank'};}
else {
LogIt(1,"Forgot bank code for SX!");
return $ParmErr;
}
}
elsif ($cmdcode eq 'ST') {
if ($parmref->{'write'}) {
$parmstr = $in->{'step'};
}
}
elsif ($cmdcode eq 'WI') {
$parmstr = '';
}
elsif (($cmdcode eq 'VA')  or ($cmdcode eq 'VB') ) {
if ($in->{'frequency'}) {
my $freq = $in->{'frequency'};
if ($freq < 1) {return $ParmErr;}
$parmstr = $freq;
}
}
elsif ($cmdcode eq 'VF')  {
if ($model !~ /dv/i) {return $NotForModel;}
if ($in->{'vfo'}) {$parmstr = $in->{'vfo'};}
else {$parmstr = 'A';}
if ($parmref->{'write'}) {
$parmstr = "$parmstr " . set_keys($in,$model);
}
}
else {LogIt(1,"No preprocess for AOR command code $cmdcode!");}
if (!$parmref->{'portobj'}) {
LogIt(2464,"AOR.PM: No open port detected!");
}
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => "\n",
'delay' => $delay,
'resend' => 0,
'debug' => 0,
'fails' => 1,
'wait' => 30,
);
AOR_SENDIT:
my $outstr = $cmdcode;
if ($cmdcode eq 'test') {$outstr = $parmstr}
else {
if (!defined $parmstr) {
LogIt(2875,"AOR_CMD Undefined parmstr for $cmdcode");
}
if (length($parmstr) > 0) {
$outstr = Strip("$outstr$parmstr");
}
}
if ($Debug3) {LogIt(0,"AOR_CMD l2517:sent =>$outstr");}
my $sent = $outstr;
if (($cmdcode eq 'EX') and ($model =~ /8000/)) {
return ($NotForModel);
}
$countout = $portobj->write($outstr . AOR_TERMINATOR);
if ($Debug3) {
LogIt(0,"AOR_CMD l4015: Sent $sent to radio.");
}
WAIT:
if ($Debug3) {LogIt(0,"AOR_CMD l2534: Waiting for input from radio..");}
$instr = '';
my $waitcount = 30;
my $resend = 2;
while (TRUE) {
my ($count_in, $data_in) = $portobj->read(1);
if ($count_in) {
if ($data_in eq "\n") {
last;
}
elsif ($data_in eq "\r") {next;}
else {$instr = "$instr$data_in";}
$waitcount = 30;
$resend = 2;
}
else {
$waitcount--;
if ($waitcount) {
usleep($delay);
next;
}
else {
if ($cmdcode eq 'EX') {return $GoodCode;}
$resend--;
if ($resend) {
print "No response for =>$sent Waiting some more\n";
$portobj->write(AOR_TERMINATOR);
$waitcount = 30;
next;
}
else {
LogIt(1,"no response to =>$sent<=");
if (!$parmref->{'rsp'}) {add_message("AOR_CMD l2473:Radio is not responding...");}
$parmref->{'rsp'} = TRUE;
return ($parmref->{'rc'} = $CommErr);
}### To many timeouts
}### Wait timeout
}### Empty buffer
}
if ($parmref->{'rsp'}) {add_message("Radio is responding again...");}
$parmref->{'rsp'} = FALSE;
my $radio_code = '';
my $digit1 = 0;
my $digit2 = 0;
if ($instr) {
if ($instr =~ /^\d/) {
($digit1,$digit2,$instr) = $instr =~ /^(\d)(\d)(.*)/;
if (!$digit1) {$digit1 = 0;}
if (!$digit2) {$digit2 = 0;}
$radio_code = "$digit1$digit2";
}
}
my @returns = split " ",$instr;
$instr = Strip($instr);
if ($Debug3) {LogIt(0,"AOR_CMD:CMD=$cmdcode AOR returned =>$instr<=");}
$parmref->{'rc'} = $GoodCode;
if ($cmdcode eq 'test') {
$parmref->{'rsp'} = FALSE;
return ($parmref->{'rc'} = $GoodCode);
}
if ($cmdcode eq 'AC') {
if ($instr =~ /ac/i) {
($out->{'agc'}) = $instr =~ /ac(\d)./;
}
}### AC post-process
elsif ($cmdcode eq 'AT') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if ($instr =~ /at1/i) { $out->{'atten'} = TRUE;}
else {$out->{'atten'} = FALSE;}
}
}
elsif ($cmdcode eq 'BN') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3212: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
my ($sb,$cb) = $instr =~ /SR(.+?) MX(.*)/;
if (!defined $sb) {
print "Line 2486:Regex failed! instr=>$instr\n";
$sb = '';}
if (!defined $cb) {
print "Line 2489:Regex failed!\n";
$cb = '';}
$out->{'search_bank'} = $sb;
$out->{'scan_bank'} = $cb;
}
}### 'BN' command
elsif ($cmdcode eq 'BP') {
$out->{'_raw'} = $instr;
$out->{'_rc'} = "$digit1$digit2";
$out->{'_sent'} = $sent;
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3698: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'BP') {
print "AOR l4050:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'beep'} = substr($instr,2);
}
}
elsif ($cmdcode eq 'CI') {
$out -> {'_raw'} = $instr;
$out->{'_rc'} = "$digit1$digit2";
$out->{'_sent'} = $sent;
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'CI') {
print "AOR l4093:Issued $sent Returned=$instr\n";
goto WAIT;
}
if (substr($instr,2,1)){$out->{'ctc'} = 1;}
else {$out->{'ctc'} = 0;}
}
}### CI command code
elsif ($cmdcode eq 'CN') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3275: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'CN') {
print "AOR l4128:Issued $sent Returned=$instr\n";
goto WAIT;
}
my ($code) = $instr =~ /.*(\d\d)/;   
if (looks_like_number($code)) {$code = $code + 0;}
else {
LogIt(1,"AOR l2975:Non-Numeric code $code returned for 'CN'");
return ($parmref->{'retcode'} = $ParmErr);
}
if ($code) {
my $value = $aor_ctcs[$code];
if (!defined $value) {
LogIt(1,"AOR 2925: CTCSS Lookup failed for $code");
$value = 'Off';
}
$out->{'sqtone'} = "CTC$value";
}
else {$out->{'sqtone'} = 'Off';}
}
}### CN post process
elsif ($cmdcode eq 'DI') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'DI') {
print "AOR l4175:Issued $sent Returned=$instr\n";
goto WAIT;
}
if (substr($instr,2,1)){$out->{'dcs'} = 1;}
else {$out->{'dcs'} = 0;}
}### value returned
}### DI Post Process
elsif ($cmdcode eq 'DS') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3346: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'DS') {
print "AOR l4209:Issued $sent Returned=$instr\n";
goto WAIT;
}
my $value = substr($instr,2);
if (!$value) {$value = 'OFF';}
else {$value = "DCS$value";}
$out->{'sqtone'} = $value;
}
}## DS command post process
elsif ($cmdcode eq 'EX') {
}
elsif ($cmdcode eq 'IF') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'IF') {
print "AOR l4253:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'bw'} = substr($instr,2);
}
}
elsif ($cmdcode eq 'LB') {
$out->{'_raw'} = $instr;
$out->{'_rc'} = "$digit1$digit2";
$out->{'_sent'} = $sent;
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $NotForModel);
}
if ($instr) {
if (substr($instr,0,2) ne 'LB') {
print "AOR l4293:Issued $sent Returned=$instr\n";
goto WAIT;
}
my $value = substr($instr,2);
if (looks_like_number($value)) {
if ($value == 0) {$out->{'light'} = 'Off';}
elsif ($value == 1) {$out->{'light'} = 'On';}
else {$out->{'light'} = '30';}
}
else {$out->{'light'} = 0;}
}
}
elsif ($cmdcode eq 'LM') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3443: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if (substr($instr,0,2) ne 'LM') {
print "AOR l4344:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
$out->{'rssi'} = 0;
if ($instr) {
$out->{'_raw'} = $instr;
extract_keys($out,$instr);
}
else {
LogIt(1,"AOR l3467: LM did not return any value!");
return ($parmref->{'rc'} = $ParmErr);
}
}#### LM post-process
elsif ($cmdcode eq 'MA') {
$out->{'_sent'} = $sent;
$out->{'_raw'} = $instr;
$out->{'_rc'} = "$digit1$digit2";
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L4629: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
my %out = ();
if ($instr) {
my $first = substr($instr,0,2);
if ($first !~ /mx/i) {
LogIt(1,"\nMA returned=>$instr. Re-waiting");
goto WAIT;
}
my $groupno = $in->{'groupno'};
if (!$groupno) {$groupno = 0;}
my ($grp,$chan,$instr) = $instr =~ /MX(\d\d)(\d\d) (.*)/;
if ($grp ne $in->{'aorbank'}) {
print "\nAOR l4374: Expecting group $in->{'aorbank'} got $grp. Re-waiting\n";
goto WAIT;
}
my $aorchan = "$grp$chan";
my $expecting = $in->{'_chan'};
if (!defined $expecting) {
print Dumper($in),"\n";
LogIt(4687,"'_chan' was not set!");
}
if ($chan != $expecting) {
LogIt(1,"Got mismatch channel. Expecting $expecting. Got $chan");
}
extract_keys(\%out,$instr);
my %freqrec = (
'groupno' => $groupno,
'channel' =>  aorchan2rc($aorchan),
'aorchan' => $aorchan,
);
foreach my $key ('frequency','mode','adtype',
'service','valid','atten') {
if (defined $out{$key}) {
$freqrec{$key} = $out{$key};
}
else {
if ($key =~ /mode/i) {$freqrec{$key} = 'FMn';}
else {$freqrec{$key} = 0;}
}
}### For default keys
my $freq = $freqrec{'frequency'};
if ($freq or ($in->{'noskip'})) {
my $recno = add_a_record($in->{'database'},'freq',\%freqrec,$parmref->{'gui'});
}
$chan++;
if ($chan > 49) {
return $GoodCode;
}
$in->{'_chan'} = $chan;
goto WAIT;
}### Data returned
else {
print "MA did not return any data.\n";
print "return code =$digit1$digit2";
my $waitcnt = $sendparms{'wait'};
$waitcnt--;
if ($waitcnt) {
$sendparms{'wait'} = $waitcnt;
print "Waiting some more\n";
goto WAIT;
}### Still some more wait left
}### No data returned
LogIt(1,"Timeout waiting for data from MA");
return $CommErr;
}### MA Post Process
elsif ($cmdcode eq 'MD') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3547: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'MD') {
print "AOR l4530:Issued $sent Returned=$instr\n";
goto WAIT;
}
extract_keys($out,$instr);
}
}
elsif ($cmdcode eq 'MM') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3564: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
elsif ($cmdcode eq 'MP') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3587: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'MP') {
print "AOR l4582:Issued $sent Returned=$instr\n";
goto WAIT;
}
my $value = substr($instr,2,1);
if ($value) {$out->{'valid'} = FALSE;}
else {$out->{'valid'} = TRUE;}
}
}
elsif ($cmdcode eq 'MQ') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3606: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
elsif ($cmdcode eq 'MR') {
$out->{'_raw'} = $instr;
$out->{'_rc'} = "$digit1$digit2";
$out->{'_sent'} = $sent;
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'MX') {
print "AOR l4658:Issued $sent Returned=$instr\n";
goto WAIT;
}
extract_keys($out,$instr);
}
$out->{'state'} = 'MR';
$state_save{'state'} = 'MR';
}
elsif ($cmdcode eq 'MS') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3663: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
print "L2444:Changed to Memory Scan state\n";
$state_save{'state'} = 'MS';
}
elsif ($cmdcode eq 'MX') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3681: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return  $ParmErr;
}
if ($instr) {
print "Line 4825:$cmdcode returned=>$instr\n";
}
$state_save{'state'} = 'MR';
}
elsif ($cmdcode eq 'RF') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L4721: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'RF') {
print "AOR l4729:Issued $sent Returned=$instr\n";
goto WAIT;
}
extract_keys($out,$instr);
}
$state_save{'state'} = 'DD';
}### RF post-process
elsif ($cmdcode eq 'RX') {
$out->{'_raw'} = $instr;
$out->{'_rc'} = "$digit1$digit2";
$out->{'_sent'} = $sent;
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
if ($digit1 == 6) {
$sendparms{'resend'}++;
if ($sendparms{'resend'} < 3) {
goto AOR_SENDIT;
}
else {
LogIt(1,"no response to =>$sent<=");
if (!$parmref->{'rsp'}) {add_message("AOR_CMD l2473:Radio is not responding...");}
$parmref->{'rsp'} = TRUE;
return ($parmref->{'rc'} = $CommErr);
}
}
LogIt(1,"L3734: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,2,1) ne ' ') {
print "AOR l4781:Issued $sent Returned=$instr model=>$model\n";
goto WAIT;
}
extract_keys($out,$instr);
}
else {
print "RX did not return any data code=$radio_code\n";
$waitcount--;
if ($waitcount > 0) {
print "Waiting some more\n";
$outstr = '';
goto WAIT;
}
print "Wait timed out\n";
return ($parmref->{'rc'} = $ParmErr);
}
}### RX post-process
elsif ($cmdcode eq 'SE') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3767: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
$state_save{'state'} = 'SS';
}
elsif ($cmdcode eq 'SR') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
if ($digit1 == 3) {
$out->{'start_freq'} = 0;
$out->{'end_freq'} = 0;
$out->{'step'} = 0;
$out->{'mode'} = 'FMn';
$out->{'service'} = '';
return $EmptyChan;
}
else {
LogIt(1,"L4851: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
my $two = substr($instr,0,2);
if (($two ne 'SE') and ($two ne 'SR')) {
print "AOR l4729:Issued $sent Returned=$instr\n";
goto WAIT;
}
extract_keys($out,$instr);
}
else {$out->{'start_freq'} = 0;}
}
elsif ($cmdcode eq 'SX') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return $EmptyChan;
}
}
elsif ($cmdcode eq 'ST') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3815: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) { extract_keys($out,$instr);}
}### RF post-process
elsif (($cmdcode eq 'VA')  or ($cmdcode eq 'VB') or ($cmdcode eq 'VZ')) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3833: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) { extract_keys($out,$instr);}
$state_save{'state'} = $cmdcode;
}
elsif ($cmdcode eq 'VF') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3658: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) { extract_keys($out,$instr);}
$state_save{'state'} = $cmdcode;
}
elsif ($cmdcode eq 'WI') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {$out->{'model'} = $instr;}
else {$out->{'model'} = '';}
}
else {
LogIt(1,"AOR L3886: No post process for command $cmdcode");
return ($parmref->{'rc'} = $NotForModel);
}### No handler process
return ($parmref->{'rc'});
}
sub extract_keys{
my $out = shift @_;
my $data = shift @_;
my $data_save = $data;
my ($pkg,$fn,$caller) = caller;
$out->{'frequency'} = 0;
$out->{'mode'} = 'FMn';
$out->{'atten'} = FALSE;
$out->{'step'} = 1;
$out->{'aorchan'} = -1;
$out->{'channel'} = -1;
$out->{'valid'} = FALSE;
$out->{'service'} = '';
$out->{'state'} = '';
$out->{'bank'} = '';
$out->{'atten'} = FALSE;
$out->{'adtype'} = 'AN';
my %vfo_ids = ('VA' => 'VFO-A',
'VB' => 'VFO-B',
'VC' => 'VFO-C',
'VD' => 'VFO-D',
'VE' => 'VFO-E',
'DD' => 'VFO',
);
if ($data =~ / TM/) {
($data,$out->{'service'}) = $data =~ /(.*?) TM(.*)/i;
}
elsif ($data =~ / TT/) {
($data,$out->{'service'}) = $data =~ /(.*?) TT(.*)/i;
}
my @fields = split " ",$data;
foreach my $parm (@fields) {
my $key = substr($parm,0,2);
if (substr($key,0,1) eq '-') {next;}
my $value = '';
if (length($parm) > 2) {$value = substr($parm,2);}
if ($key =~ /al/i) {
}
elsif ($key =~ /at/i) {
if ($value) {$out->{'atten'} = TRUE;}
}
elsif ($key =~ /au/i) {
}
elsif ($key =~ /bp/i) {
}
elsif ($key =~ /dd/i) {
$out->{'state'} = 'DD';
$state_save{'state'} = 'DD'
}
elsif ($key =~ /ff/i) {
$out->{'state'} = 'FF';
$state_save{'state'} = 'FF'
}
elsif ($key =~ /lm/i) {
my $rssi = 0;
my $signal = 0;
if ($value) {
my @rssi_table = ();
if (length($value) == 2) {
if($value =~ /^[[:xdigit:]]+\z/) { 
$rssi = hex($value);
if ($rssi < 128) {$out->{'sql'} = TRUE;}
else {$rssi = $rssi - 128;}
@rssi_table = (
);
$signal = 0;
if ($rssi > 19) {$signal = 9;}
elsif ($rssi > 14) {$signal = 8;}
elsif ($rssi > 13) {$signal = 7;}
elsif ($rssi > 12) {$signal = 6;}
elsif ($rssi > 11) {$signal = 5;}
elsif ($rssi > 10) {$signal = 4;}
elsif ($rssi > 9)  {$signal = 3;}
elsif ($rssi > 8)  {$signal = 2;}
elsif ($rssi > 5)  {$signal = 1;}
else {$signal = 0;}
}### Valid HEX
else {
LogIt(1,"AOR L5628:Invalid HEX value $value for LM");
}
}### Two digit lookup
elsif (length($value) == 4) {
$rssi = substr($value,0,3);
if (substr($value,3,1)) {$out->{'sql'} = TRUE;}
@rssi_table = (
117,108,102, 98, 88, 84, 78, 68, 61, 58,
);
foreach my $cmp (@rssi_table) {
if (($rssi >=  $cmp) or ($signal >= MAXSIGNAL)){
last;
}
$signal++;
}### RSSI table search
}### 4 digit signal
else {
@rssi_table = ();
$out->{'rssi'} = substr($value,1);
if (substr($value,0,1) ne '%') {
$signal = 9;
$out->{'sql'} = TRUE;
}
}
if ($out->{'sql'}) {
if (!$signal) {$signal = 1;}
}
else {$signal = 0;}
$out->{'signal'} = $signal;
}### If there is a VALUE
}
elsif ($key =~ /md/i) {### Modulation
($out->{'mode'},$out->{'adtype'}) = aormode2rc($value);
}
elsif ($key =~ /mp/i) {### Pass
if (!$value) {$out->{'valid'} = TRUE;}
}
elsif ($key =~ /mr/i) {
$out->{'state'} = 'MR';
$state_save{'state'} = 'MR';
if ($value) {
$out->{'aorchan'} = $value;
$out->{'channel'} = aorchan2rc($value);
}### Value found for 'MR' state
}
elsif ($key =~ /ms/i) {
$out->{'state'} = 'MS';
$state_save{'state'} = 'MS';
if ($value) {
$out->{'aorchan'} = $value;
$out->{'channel'} = aorchan2rc($value);
}
}
elsif ($key =~ /mx/i) { 
$out->{'aorchan'} = $value;
$out->{'channel'} = aorchan2rc($value);
}### Key = MX
elsif ($key =~ /pt/i) {### Write protect
}
elsif (($key =~ /rf/i) or ($key =~ /sl/i) or ($key =~ /su/i)) { 
my $freq = $value;
if ($value =~ /\./) {
$freq = freq_to_rc($value);
}
if ($key =~ /sl/i) {$out->{'start_freq'} = $freq;}
elsif ($key =~ /su/i) {$out->{'end_freq'} = $freq;}
else {$out->{'frequency'} = $freq;}
}
elsif ($key =~ /rx/i) {
}
elsif ($key =~ /se/i) {
$out->{'bank'} = $value;
}
elsif ($key =~ /sh/i) {### Step adjust in khz
}
elsif ($key =~ /sm/i) {
$out->{'state'} = 'SM';
$state_save{'state'} = 'SM';
}
elsif ($key =~ /sp/i) {
}
elsif ($key =~ /sr/i) {
if ($value) {
if (length($value) == 1) {
$value = index($alpha,$value);
if (!defined $value) {
LogIt(1,"AOR l5702: could not decode bank for $value");
$value = -1;
}
}
$out->{'bank'} = $value;
}### $value returned
$out->{'state'} = 'SR';
$state_save{'state'} = 'SR';
}
elsif ($key =~ /ss/i) {
$out->{'state'} = 'SS';
$state_save{'state'} = 'SS'
}
elsif ($key =~ /st/i) {### Step in KHz
if ($value =~ /\./) {$value =  int($value * 100);} 
$out->{'step'} = $value
}
elsif ($key =~ /tr/i) {
}
elsif (($key =~ /vf/i) or $vfo_ids{$key}) {
$out->{'state'} = uc($key);
$state_save{'state'} = uc($key);
if ($value) {
if ($value =~ /\./) {
$out->{'frequency'} = freq_to_rc($value);
}
else {$out->{'frequency'} = $value;}
}
}
elsif ($key =~ /vs/i) {### VFO Search state
$out->{'state'} = 'VS';
$state_save{'state'} = 'VS'
}
else {
LogIt(1,"AOR l5806:EXTRACT_KEYS:Unprocessed extract key $key. caller=$caller Data=>$data ");
}
}### For each parm in the string
return 0;
}#### Extract keys
sub set_keys {
my $hash = shift @_;
my $model = shift @_;
my ($pkg,$fn,$caller) = caller;
if (not $model) {LogIt(2888,"SET_KEYS: Forgot model parameter. Caller=>$caller");}
my $parmstr = '';
foreach my $key (keys %{$hash}) {
my $value = $hash->{$key};
if (!defined $value) {
print "l2986: Empty value for key $key Caller=$caller\n";
next;
}
$value = Strip($value);
if ($key =~ /mode/i) {
my $audio = 'AN';
if ($hash->{'adtype'}) {$audio = $hash->{'adtype'};}
my ($code,$bw) = rcmode2aor($value,$audio,$model);
if ((defined $code) and ($code ne '')) {
if ($parmstr) {$parmstr = "$parmstr MD$code";}
else {$parmstr = "MD$code";}
}
}#### Processing the MODE key
elsif ($key =~ /freq/i) {
if (($value !~ /\./) and ($model =~ /dv/i)) {
$value =  sprintf("%010.5f",Strip(rc_to_freq($value)));
}
else {
}
my $kw = 'RF';
if ($key =~ /start/i) {$kw = 'SU';}
elsif ($key =~ /end/i) {$kw = 'SL';}
if ($parmstr) {$parmstr = "$parmstr $kw$value";}
else {$parmstr = "$kw$value";}
}
elsif ($key =~ /valid/i) {
my $pass = '0';
if (!$value) {$pass = '1';}
if ($parmstr) {$parmstr = "$parmstr MP$pass";}
else {$parmstr = "MP$pass";}
}### Memory Pass
elsif ($key =~ /atten/i) {
if ($model =~ /dv/i) {
}
else {
my $atten = '0';
if ($value) {$atten = '1';}
if ($parmstr) {$parmstr = "$parmstr AT$atten";}
else {$parmstr = "AT$atten";}
}
}### Attenuation
elsif ($key =~ /step/i) {
my $org = $value;
if ($model =~ /dv/i) {
$value = sprintf("%06.1f",$value/100);
}
if ($value) {
if ($parmstr) {$parmstr = "$parmstr ST$value";}
else {$parmstr = "ST$value";}
}
else {
LogIt(1,"AOR-4567: Step value was 0 (original input=>$org)");
}
}### Step
}### For each key in the hash
if ($parmstr) {
if (defined $hash->{'service'}) {
if ($model =~ /8000/) {
$parmstr = "$parmstr TM$hash->{'service'}";
}
else {
$parmstr = "$parmstr TT$hash->{'service'}";
}
}
elsif (defined $hash->{'sserve'}) {
$parmstr = "$parmstr TT$hash->{'sserve'}";
}
}### parmstr has something
return $parmstr;
}### Set_Keys
sub rcmode2aor {
my ($pkg,$fn,$caller) = caller;
my $mode = shift @_;
my $audio = shift @_;
my $model = shift @_;
if (!$mode) {LogIt(3190,"RCMODE2AOR: Forgot modulation code!");}
if (!$audio) {LogIt(3191,"RCMODE2AOR: Forgot audio code!");}
if (!$model) {LogIt(3192,"RCMODE2AOR: Forgot model!");}
my $aormode = '';
my $aorbw = 0;
if ($mode =~ /^au/i) { 
LogIt(1,"RCMOD2AOR l6194: Mode=$mode. Set to 'FMn'. Caller=>$caller");
$mode = 'FMn';
}
if ($model =~ /dv/i) {
my %dv1_mode_lookup = (
'wf' => '0F0',
'am' => '0F1',
'us' => '0F4',
'ls' => '0F5',
'rt' => '0F6',
'rr' => '0F6',
'cw' => '0F6',
'cr' => '0F6',
);
my %dv1_audio_lookup = (
'an' => '0F0',
'p2' => '050',
'dm' => '070',
'nx' => '040',
'vn' => '040',
'ds' => '010',
);
if ($mode =~ /^fm/i) {
my $audiokey = lc(substr($audio,0,2));
$aormode = $dv1_audio_lookup{$audiokey};
}
else {
my $modekey = lc(substr($mode,0,2));
$aormode = $dv1_mode_lookup{$modekey};
}
if (!$aormode) {
LogIt(1,"AOR 6230Could not decode mode $mode (audio=>$audio) for $model. Caller=$caller");
$aormode = '';
}
my $key = lc($mode);
$aorbw = $mode2if{$key};
if (!defined $aorbw) {$aorbw = 0;}
}### DV-1/DV-3
elsif ($model =~ /8000/) {
my $modekey = lc(substr($mode,0,2));
my %lookup = (
'wf' => 0,
'fm' => 1,
'am' => 2,
'us' => 3,
'ls' => 4,
'cw' => 5,
'cr' => 5,
'rt' => 5,
'rr' => 5,
);
$aormode = $lookup{$modekey};
if (!defined $aormode) {
LogIt(1,"Could not decode mode $mode for $model modekey=>$modekey<=");
$aormode = '';
}
}### AR8000
else {
my $modekey = lc(substr($mode,0,2));
my %other_lookup = (
'wf' => '00',
'fm' => '01',
'am' => '02',
'us' => '04',
'ls' => '05',
'cw' => '06',
'cr' => '06',
'rt' => '06',
'rr' => '06',
);
$aormode = $other_lookup{$modekey};
if (!defined $aormode) {
LogIt(1,"Could not decode mode $mode for $model");
$aormode = '';
}
if (($model =~ /5700/) and ($modekey =~ /fm/i)) {
if (($audio =~ /nx/i) or ($audio =~ /vx/i)) {
$aormode = '41';
}
elsif ($audio =~ /dm/i) {$aormode = '43';}
elsif ($audio =~ /p2/i) {$aormode = '45';}
elsif ($audio =~ /ds/i) {$aormode = '46';}
else {
}
}
}
return $aormode,$aorbw;
}
sub aormode2rc {
my $aormode = shift @_;
my $mode = 'FMn';
my $audio = 'AN';
my $l = length($aormode);
if ($l == 1) {
my @mode8000 = ('WF','FMn','AM','US','LS','CW');
$mode = $mode8000[$aormode];
if (!$mode) {
LogIt(1,"AOR l3258:Cannot decode MD code=>$aormode");
$mode = 'FMn';
}
}
elsif (($l == 2) and (looks_like_number($aormode))) {
my @mode5000 = (
'WF','WF','AM','AM','US','LS','CW','FMn','FMn','FMn','FMn',
'FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn',
'FMn','WF','WF','WF','FMn','FMn','AM','AM','AM','AM','US',
'LS','CW','CW','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn',
'FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn','FMn',
);
if ($aormode > 39) {
if ($aormode == 43) {$audio = 'DM';}
elsif ($aormode == 41) {$audio = 'NX';}
elsif ($aormode == 45) {$audio = 'P2';}
elsif ($aormode == 46) {$audio = 'DS';}
$mode = 'FM';
}
else {
$mode = $mode5000[$aormode];
if (!$mode) {
LogIt(1,"AOR l3291:Cannot decode MD=>$aormode");
$mode = 'FM';
}
}
}### Two character
else {
my @mode_lookup = (
'FM',
'AM',
'AM',
'AM',
'US',
'LS',
'CW',
);
my @dig_lookup = (
'AN',
'DS',
'AN',
'AN',
'NX',
'P2',
'AN',
'DM',
);
my @chars = split(//,Strip($aormode));
my $d = $chars[0];
my $a = $chars[1];
my $n = $chars[2];
if (!defined $n) {
$mode = 'FMn';
$audio = 'AN';
print "N was not specified.\n";
}
elsif (($a =~ /f/i) or ($a =~ /0/)) { 
$audio = 'AN';
$mode = $mode_lookup[$n];
if (!defined $mode) {
LogIt(3347,"AORMODE2RC Failed mode lookup for $aormode!");
}
}
else {
$mode = 'FMn';
$audio = $dig_lookup[$a];
if (!defined $audio) {
LogIt(3357,"AORMODE2RC Failed audio lookup for $aormode!");
}
}
}### DV1/DV3 code
return $mode,$audio;
}
sub rcchan2aor {
my ($pkg,$fn,$caller) = caller;
my $channel = shift @_;
if (!defined $channel) {
LogIt(6334,"RCCHAN2AOR: Missing Channel number! Caller=>$caller");
}
my $model = shift @_;
my $aorchan = -1;
if (!$model) {
LogIt(6340,"RCCHAN2AOR: Missing model number! Caller=$caller");
}
if (($channel > 1999) or ($channel < 0)) {
return -1;
}
if ($model =~ /8000/)  {
if ($channel > 999) {return -1;}
my $group = int($channel/50);
my $bank = substr($alpha,$group,1);
if (!$bank) {
Logit(1,"Could not encode channel $channel for $model");
return -1;
}
my $chan = $channel % 50;
$aorchan = $bank . sprintf("%02.2u",$chan);
}
else {
my $group = int($channel/50);
my $chan = $channel % 50;
$aorchan =  sprintf("%02.2u",$group) . sprintf("%02.2u",$chan);
}
return $aorchan;
}### rcchan2aor
sub aorchan2rc {
my $aorchan =  shift @_;
my $rcchan = -1;
if (looks_like_number($aorchan)) {
if (length($aorchan) < 4 ) {
LogIt(1,"Cannot deal with AOR channel specification $aorchan");
}
else {
$aorchan = sprintf("%04.4u",$aorchan);
my $group = substr($aorchan,0,2);
my $chan = substr($aorchan,2,2);
$rcchan = int($group * 50) + ($chan % 50);
}
}
else {
my $bank = substr(Strip($aorchan),0,1);
my $chan = substr($aorchan,1);
my $igrp = index($alpha,$bank);
$rcchan = int($igrp * 50) + ($chan % 50);
}
return $rcchan;
}
sub set_tones {
my $rc_tone = shift @_;
my $parmref = shift @_;
my %myin = ('ctc' => 0,'tone'=> 0, 'dcs' => 0, 'code' => 0);
my %myout = ();
my $insave =  $parmref->{'in'};
my $outsave = $parmref->{'out'};
my $retcode = 0;
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
my $tone_code = 0;
if ($rc_tone =~ /off/i) {
}
elsif ($rc_tone =~ /ctc/i) {
my ($tone) = $rc_tone =~ /ctc(.*)/i;  
$tone_code = $ctcss_aor{$tone};
if ($tone_code) {
$myin{'tone'} = $tone_code;
$myin{'ctc'} = 1;
}
else {
$retcode = 1;
print "AOR l6072:Lookup for $tone failed\n";
goto TONEDONE;
}
}
elsif ($rc_tone =~ /dcs/i) {
my ($code) = $rc_tone =~ /dcs(.*)/i;  
$myin{'code'} = $code;
$myin{'dcs'} = 1;
}
else {
goto TONEDONE;
}
if ($myin{'ctc'}) {
$parmref->{'write'} = TRUE;
my $rc = aor_cmd('CN',$parmref);
if ($model =~ /dv/i) {
aor_cmd('CI',$parmref);
}
}
elsif ($myin{'dcs'}) {
my $rc = aor_cmd('DS',$parmref);
if ($model =~ /dv/i) {
aor_cmd('DI',$parmref);
}
}
else {
if ($model =~ /dv/i) {
aor_cmd('CI',$parmref);
}
else {
print "Line6680:",Dumper(%myin),"\n";
aor_cmd('CN',$parmref);
aor_cmd('DS',$parmref);
}
}### All tones are off
TONEDONE:
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return $retcode;
}### Set_Tones
sub get_tones {
my $parmref = shift @_;
my $rc_tone = 'Off';
my %myin = ();
my %myout = ();
my $insave =  $parmref->{'in'};
my $outsave = $parmref->{'out'};
my $retcode = 0;
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
$parmref->{'write'} = FALSE;
if ($model =~ /dv/i) {
aor_cmd('CI',$parmref);
if ($myout{'ctc'}) {
aor_cmd('CN',$parmref);
$rc_tone = $myout{'sqtone'};
}
else {
aor_cmd('DI',$parmref);
if ($myout{'dcs'}) {
aor_cmd('DS',$parmref);
$rc_tone = $myout{'sqtone'};
}
}
}### Model is DV-1/DV3
else {
aor_cmd('CN',$parmref);
my $sqtone = $myout{'sqtone'};
if (!$sqtone) {goto GETTONEDONE;}
if ($sqtone =~ /off/i) {
aor_cmd('DS',$parmref);
$rc_tone = $myout{'sqtone'};
}
else {$rc_tone = 'Off';}
}
GETTONEDONE:
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return $rc_tone;
}### Get Tones
sub dv_delay {
my $parmref = shift @_;
my $count = 10;
until (!aor_cmd('RX',$parmref)) {
usleep(100);
$count--;
if ($count < 0) {last};
}
return 0;
}
sub dummy {
my $parmref = shift @_;
return 0;
}
sub Numerically {
use Scalar::Util qw(looks_like_number);
if (looks_like_number($a) and looks_like_number($b)) { $a <=> $b;}
else {$a cmp $b;}
}
