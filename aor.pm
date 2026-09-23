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
my %valid_steps = (
'10' => 1,
'50' => 2,
'100' => 3,
'500' => 4,
'1000' => 5,
'2000' => 6,
'5000' => 7,
'6250' => 8,
'7500' => 9,
'8330' => 10,
'9000' => 11,
'10000' => 12,
'12500' => 13,
'15000' => 14,
'20000' => 15,
'25000' => 16,
'30000' => 17,
'50000' => 18,
'100000' => 19,
'500000' => 20,
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
print "AOR l034:Verified model to be $model\n";
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
$defref->{'pass'} = TRUE;
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
@gui_adtype = ('ANALOG','P25','NXDN','DMR','DSTAR','AUTO');
@gui_bandwidth = ('(none)','Wide','Medium','Narrow','U_Narrow');
$parmref->{'write'} = TRUE;
$in->{'response'} = TRUE;
aor_cmd('RE',$parmref);
}
elsif ($model =~ /5/) {
$defref->{'minfreq'} = 10000;
$defref->{'maxfreq'} = 2600000000;
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
}
else {
}
$parmref->{'write'} = FALSE;
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
%myin = ('frequency' => $freq,
'mode' => $mode,
'adtype' => $adtype
);
aor_cmd('RF',$parmref);
if ($mode) {
aor_cmd('MD',$parmref);
if (($model =~ /dv/i) and ($adtype !~ /au/i)) {
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
my $origin  =  $defref->{'origin'};
my $maxbank = int($maxcount/50) - 1;
my $maxchan = $maxcount -1;
my $aorchan = rccchan2aor($in,$model);
if ($aorchan < 0) {return $NotForModel;}
$in->{'aorchan'} = $aorchan;
$parmref->{'write'} = FALSE;
my $rc = aor_cmd ('MR',$parmref);
if ($rc) {
$out->{'frequency'} = 0;
$out->{'mode'} = 'FMn';
$out->{'service'} = '';
return ($parmref->{'rc'} = $EmptyChan);
}
aor_cmd('RX',$parmref);
if ($out->{'channel'} eq '-1') {
$out->{'channel'} = $aorchan;
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
if ($channel > 3949) {
LogIt(1,"Firstchan is too large for AOR. Changed to 0");
$channel = 0;
}
elsif (($model =~ /8000/) and ($channel > 1949)) {
LogIt(1,"Firstchan is too large for this model. Changed to 0");
$channel = 0;
}
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
'bank' => sprintf("%02.2u",$bank),
'sysno' => $sysno,
'groupno' => $grpno,
'model' => $model,
'noskip' => $noskip,
);
my $needgroup = TRUE;
if ($model =~ /8000/) {
LogIt(1720,"Using MA for AR8000! Caller=>$caller");
}
aor_cmd('MA',$parmref);
CHANFETCH:
foreach my $ch (0..49) {
my $channel =  sprintf("%02.2i",$bank) . sprintf("%02.2i","$ch");
$vfo{'channel'} = $channel;
threads->yield;
if ($progstate ne $startstate) {goto GETDONE;}
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green$channel$Reset";
}
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
$myin{'aorchan'} = sprintf("%04.4u",$freqrec->{'channel'});
aor_cmd('MR',$parmref);
aor_cmd('IF',$parmref);
if ($mode =~ /fm/i) {
if (defined $myout{'bw'}) {
if ($myout{'bw'} == 4) {$freqrec->{'mode'} = 'FMn';}
elsif ($myout{'bw'} == 0) {$freqrec->{'mode'} = 'WF';}
else {$freqrec->{'mode'} = 'FM';}
}
else {
}
}### FM Modulation
}### Analog Audio
$freqrec->{'sqtone'} = 'Off';
if (($mode =~ /fm/i) and ($audio =~ /an/)) {
$myin{'aorchan'} = sprintf("%04.4u",$freqrec->{'channel'});
aor_cmd('MR',$parmref);
$freqrec->{'sqtone'} = get_tones($parmref);
}
}### Frequency not 0
$freqrec->{'aorchan'} = '';
$count++;
}### Channel process
}### Bank fetch
goto GETDONE;
FETCH_8000:
foreach my $bank (0..19) {
my $grpno = 0;
my $needgroup = TRUE;
foreach my $chan (0..49) {
$myin{'aorchan'} = substr($alpha,$bank,1) . sprintf("%2.2i",$chan);
my $channel =  aorchan2rc($myin{'aorchan'});
$vfo{'channel'} = $channel;
threads->yield;
if ($progstate ne $startstate) {last FETCH_8000;}
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green$channel$Reset" ;
}
%myout  = ('frequency' => 0);
aor_cmd('MR',$parmref);
if ($myout{'frequency'} or $noskip) {
if ($needgroup) {
my %grouprec = ('sysno' =>$sysno,'service' => "AOR Group $bank", 'valid' => TRUE);
$grpno = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$needgroup = FALSE;
}
my %freqrec = (
'groupno' => $grpno,
'sqtone' => 'Off',
'channel' => $channel,
);
foreach my $key ('frequency','mode','valid','service','att') {
$freqrec{$key} = $myout{$key};
}
add_a_record($db,'freq',\%freqrec,$parmref->{'gui'});
$count++;
}
}### For every channel in this AOR group
}### For every group in the AR8000
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
if (!$db->{'freq'}[1]{'index'}) {return $EmptyChan;}
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
my $flushchan = '';
foreach my $frqrec (@{$db->{'freq'}}) {
if (!defined $frqrec->{'index'}) {next;}
my $recno = $frqrec->{'_recno'};
if (!$recno) {$recno = '??';}
my $emsg = "in record $recno";
if ($frqrec->{'tgid_valid'}) {next;}
my $aorchan = rcchan2aor($frqrec,$model);
if ($aorchan eq '-1') {next;}
if ($found_chan{$aorchan}) {
print STDERR "\n";
LogIt(1,"\nChannel $aorchan was found twice $emsg. Second iteration skipped!");
next;
}
$found_chan{$aorchan} = TRUE;
my $freq = $frqrec->{'frequency'};
if (!$freq) {
%myin = ('aorchan' => $aorchan);
my $rc = aor_cmd('MR',$parmref);
if ($rc) {next;}
if (($model =~ /8000/) and (!$myout{'frequency'})) {next;}
push @to_delete,$aorchan;
next;
}
else {
print STDERR "\rSETMEM: Writing channel $Bold$Green",
sprintf("%04.4u",$aorchan), $Reset,
" freq=>$Yellow",rc_to_freq($freq),$Reset;
%myin = (
'aorchan' => $aorchan,
'step' => 5000,
);
if (!$flushchan) {$flushchan = $aorchan;}
if (looks_like_number($frqrec->{'fstep'})) {
$myin{'step'} =  Step_Check($frqrec->{'fstep'},\%valid_steps);
}
foreach my $key ('frequency','valid','adtype',
'mode','service') {
my $value = $frqrec->{$key};
if ($key eq 'mode') {
if (lc($value) eq 'auto') {
$value = AutoMode($freq);
}
}
elsif ($key eq 'service') {
if (!$value) {$value = '.';}
}
$myin{$key} = $value;
}### Set keys for the memory
if ($model =~ /8000/) {
$myin{'atten'} = $frqrec->{'atten'};
}
my $rc =  aor_cmd('MX',$parmref);
if ($rc) {
LogIt(1,"\nRadio rejected write of channel $aorchan");
next;
}
aor_cmd('MR',$parmref);
$count++;
}### Write the basic stuff for this channel
my %record = (
'aorchan'  => $aorchan,
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
my $aorchan = $rec->{'aorchan'};
print STDERR "\rSETMEM: Writing extra fields for channel $Bold$Green",
sprintf("%04.4u",$aorchan),"$Reset";
if (($model !~ /8000/) and
($rec->{'adtype'} =~ /an/i) and
($rec->{'mode'} =~ /fm/i)) {
%myin = ('aorchan' => $aorchan);
my $rc = aor_cmd('MR',$parmref);
if ($rc) {
LogIt(1,"\n L2155 Could not set channel $aorchan for tone setting! rc->$rc");
print "Sent:$parmref->{'_sent'} returned:$parmref->{'_returned'} ",
" code:$parmref->{'_rc'}\n";
next;
}
$rc = set_tones($rec->{'sqtone'},$parmref);
if ($rc) {
LogIt(1,"\n$rec->{'sqtone'} (channel $rec->{'channel'}) " .
"is not valid for this radio!");
}
}### Tone conditions met
if (($model =~ /dv/i) and ($rec->{'adtype'} =~ /an/i)) {
my ($md,$bw) = rcmode2aor($rec->{'mode'},$rec->{'adtype'},$model);
%myin = ('bw' => $bw, 'vfo' => 'A', 'aorchan' => $aorchan);
if (aor_cmd('MR',$parmref)) {
LogIt(1,"\n Could not set channel $channel ($aorchan) for tone setting!");
next;
}
$parmref->{'write'} = TRUE;
aor_cmd('IF',$parmref);
}### Model is DV-1/DV-3
}### For each second pass record
print STDERR $Eol;
foreach my $aorchan (@to_delete) {
print STDERR "\rSETMEM: Deleting channel $Bold$Green",
sprintf("%04.4u",$aorchan), $Reset;
%myin = ('aorchan' => $aorchan);
if ($model =~ /8000/) {aor_cmd('MR',$parmref);}
aor_cmd('MQ',$parmref);
$deleted++;
}
if ($model =~ /dv/i) {
%myin = ('vfo' => 'A', 'aorchan' => $flushchan);
aor_cmd('VF',$parmref);
dv_delay($parmref);
if ($flushchan) {
aor_cmd('MR',$parmref);
}
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
print STDERR "\rReading Search Bank:$Bold$Green" . sprintf("%08.8u",$bank) . $Reset ;
%myin = ('bank' => $bank);
my  $rc = aor_cmd('SR',$parmref);
if ($rc) {
if (($rc == $EmptyChan) or ($rc == $NotForModel)) {
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
'adtype' => $myout{'adtype'},
);
add_a_record($db,'search',\%search,$parmref->{'gui'});
$count++;
}
}### For each bank
$parmref->{'write'} = $writesave;
$parmref->{'out'} = $outsave;
$parmref->{'in'} = $insave;
aor_cmd('EX',$parmref);
print STDERR $Eol,$Eol;
print STDERR "$Eol$Bold$Green$count$White search records were Fetched$Eol";
return ($parmref->{'rc'} = $GoodCode);
}### Getsrch
elsif ($cmdcode eq 'setsrch') {
if ($Debug2) {DebugIt("AOR_CMD:Starting 'setsrch' command");}
if (!$db->{'search'}[1]{'index'}) {return $EmptyChan;}
my $retcode = $GoodCode;
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
my $maxcount = $defref->{'maxchan'};
my $channel =  $defref->{'origin'};
my $maxbank = int($maxcount/50) - 1;
my $maxchan = $maxcount -1;
my $count = 0;
my $removed = 0;
print "$Eol";
my %clear = ();
my %add = ();
foreach my $rec (@{$db->{'search'}}) {
if (!$rec->{'index'}) {next;}
my $chan = $rec->{'channel'};
my $recno = $rec->{'_recno'};
if (!$recno) {$recno = '?';}
if (!defined $chan) {next;}
if (!looks_like_number($chan)) {next;}
if (($chan > 39) or (($model =~ /8000/) and ($chan > 19))) {
LogIt(1,"Skipping record $recno. Channel $chan out of range");
next;
}
my $start = $rec->{'start_freq'};
my $end = $rec->{'end_freq'};
my $step = $rec->{'step'};
if (!$step) {
LogIt(1,"Skipping record $recno. Step '0' not allowed");
next;
}
if (!$start) {
if ($clear{$chan}) {
LogIt(1,"Duplicate delete of channel $chan in record $recno!");
next;
}
else {
$clear{$chan} = $rec;
}
}
else {
if (!$end) {
LogIt(1,"Skipping record $recno. END_FREQ '0' not allowed");
next;
}### END=0
if ($add{$chan}) {
LogIt(1,"Duplicate add of channel $chan in record $recno! Skipped");
next;
}
if ($start > $end) {### Swap
$rec->{'start_freq'} = $end;
$rec->{'end_freq'} = $start;
}
elsif ($start == $end) {
$rec->{'end_freq'} = $end + $step;
}
$rec->{'step'} = Step_Check($step,\%valid_steps);
$add{$chan} = $rec;
}### Start != 0
}### for each search channel
foreach my $bank (sort Numerically keys %add) {
print STDERR "\rSETSRCH: storing search bank $Bold$Green$bank$Reset  ";
my $rec = $add{$bank};
%myin = ();
if ($model =~ /8000/) {
$myin{'bank'} = substr($alpha,$bank,1);
}
else {
$myin{'bank'} = sprintf("%02.2u",$bank);
}
$myin{'step'} = Step_Check($rec->{'step'},\%valid_steps);
if ($rec->{'adtype'} ) {$myin{'adtype'} = $rec->{'adtype'};}
else {$myin{'adtype'} = 'AN';}
foreach my $key ('start_freq','end_freq','mode','service','step') {
$myin{$key} = $rec->{$key};
}
if ($model !~ /dv/i) {
$myin{'atten'} = $rec->{'atten'};
}
$parmref->{'write'} = TRUE;
aor_cmd('SE',$parmref);
$count++;
$parmref->{'write'} = FALSE;
if ($model =~ /dv/i) {
%myin = ('VFO' => 'A');
aor_cmd('VF',$parmref);
%myin = ();
if ($model =~ /8000/) {
$myin{'bank'} = substr($alpha,$bank,1);
}
else {
$myin{'bank'} = sprintf("%02.2u",$bank);
}
aor_cmd('SS',$parmref);
}
}### For each %add bank
print STDERR $Eol,$Eol;
if ($count) {
LogIt(0,"$Bold$Green$count$White search records added");
}
else {LogIt(0,"$Bold No search records were added");}
foreach my $bank (sort Numerically keys %clear) {
print STDERR "\rSETSRCH: Clearing search bank $Bold$Green$bank$Reset  ";
%myin = ();
if ($model =~ /8000/) {
$myin{'bank'} = substr($alpha,$bank,1);
}
else {
$myin{'bank'} = sprintf("%02.2u",$bank);
}
aor_cmd('SX',$parmref);
$removed++;
}
print STDERR $Eol,$Eol;
if ($removed) {
LogIt(0,"$Bold$Green$removed$White search records removed");
}
else {LogIt(0,"$Bold No search records were removed");}
$retcode = $GoodCode;
SETSRCH_DONE:
$parmref->{'write'} = $writesave;
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
aor_cmd('EX',$parmref);
return ($parmref->{'rc'} = $retcode);
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
if (!$db->{'global'}[1]{"index"}) {return $EmptyChan;}
if ($model =~ /8000/) {return ($NotForModel);}
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
elsif ($cmdcode eq 'setpass') {
if ($Debug2) {DebugIt("AOR_CMD:Starting 'setpass' command");}
if (!$db) {LogIt(2856,"AOR_CMD:No database reference for SETPASS");}
if (!$db->{'passfreq'}[1]{'index'}) {return $EmptyChan;}
my %newdb = ();
my $dbsave = $parmref->{'database'};
$parmref->{'database'} = \%newdb;
$parmref->{'options'}->{'noskip'} = FALSE;
aor_cmd('getsrch',$parmref);
$parmref->{'database'} = $dbsave;
my %valid_bank = ();
foreach my $rec (@{$newdb{'search'}}) {
if ($rec->{'index'}) {
my $ch = $rec->{'channel'} + 0;
my $start_freq = $rec->{'start_freq'};
my $end_freq = $rec->{'end_freq'};
if ($end_freq < $start_freq) {
my $temp = $start_freq;
$start_freq = $end_freq;
$end_freq = $temp;
}
$valid_bank{$ch}{'start_freq'} = $start_freq;
$valid_bank{$ch}{'end_freq'} = $end_freq;
}
}
if (!scalar keys %valid_bank) {
LogIt(1,"No search banks defined in radio. Cannot set pass frequencies");
return $EmptyChan;
}
my %myin = ();
my %myout = ();
my $writesave = $parmref->{'write'};
$parmref->{'in'} = \%myin;
$parmref->{'out'} = \%myout;
my $addcount = 0;
my $delcount = 0;
my $max_chan =  $defref->{'searchchan'};
if (!$max_chan) {$max_chan = 20;}
my $srch_max = $max_chan - 1;
my %addfreq = ();
my %delfreq = ();
foreach my $rec (@{$db->{'passfreq'}}) {
if (!$rec->{'index'}) {next;}
my $bank = $rec->{'bankno'};
my $frq = $rec->{'frequency'};
my $recno = $rec->{'_recno'};
if (!$recno) {$recno = '?';}
if (!$frq) {
LogIt(1,"Ignoring record $recno due to 0 frequency");
next;
}
if ((!defined $bank) or (!looks_like_number($bank))) {
$bank = '-';
}### Bank number not specified
else {
if (!$valid_bank{$bank}{'start_freq'}) {
LogIt(1,"Ignoring record $recno due to undefined bank $bank");
next;
}
}### Bank number was specified
if ($rec->{'remove'}) {
if ($bank eq '-') {
foreach my $bk (keys %valid_bank) {
push @{$delfreq{$bk}},$frq;
if ($Verbose) {print "Added removal of $frq from $bk\n";}
}### For each defined bank
}### Bank not specified
else {
push @{$delfreq{$bank}},$frq;
}
}
else {
if ($bank eq '-') {
foreach my $bk (keys %valid_bank) {
if ($Verbose) {print "Adding $frq for $bk\n";}
push @{$addfreq{$bk}},$frq;
}
}
else {
push @{$addfreq{$bank}},$frq;
}### Just one bank specified
}
}### extract data from input records
foreach my $bank (sort Numerically keys %addfreq) {
%myin = ('bank' => $bank);
aor_cmd('SS',$parmref);
foreach my $frq (@{$addfreq{$bank}}) {
$myin{'frequency'} = $frq;
my $rc = aor_cmd('PW',$parmref);
if ($rc) {
LogIt(1,"AOR l2908 Could not set PASS freq $frq for bank $bank");
print "sent=>$parmref->{'_sent'} ",
"recv=>$parmref->{'_received'} rc=$parmref->{'_rc'}\n";
}
else {
print "Set pass frequency $frq for bank $bank\n";
$addcount++;
}
}### Add a pass freq
}### for each record
print $Eol;
if ($addcount) {
LogIt(0,"$Bold Added $Green$addcount$White pass frequencies to the radio");
}
else {
LogIt(0,"$Bold No pass frequencies were added to the radio");
}
my @delbanks = sort Numerically keys %delfreq;
if (scalar @delbanks) {
my %newdb = ();
my $dbsave = $parmref->{'database'};
$parmref->{'database'} = \%newdb;
aor_cmd('getpass',$parmref);
$parmref->{'database'} = $dbsave;
my %freq = ();
foreach my $rec (@{$newdb{'passfreq'}}) {
if (!$rec->{'index'}) {next;}
my $ch = $rec->{'channel'};
my $fq = $rec->{'frequency'};
my $bk = $rec->{'bankno'};
if (looks_like_number($fq)) {$fq = $fq + 0;}
else {$fq = 0;}
if (looks_like_number($ch)) {$ch = $ch + 0;}
else {$ch = 0;}
if (looks_like_number($bk)) {$bk = $bk + 0;}
else {$bk = 0;}
if ($fq) {
$freq{$bk}{$ch} = $fq;
}
}### Extracting new database
foreach my $bankno (@delbanks) {
CHLIST:
foreach my $ch (reverse sort Numerically keys %{$freq{$bankno}}) {
my $thisfrq = $freq{$bankno}{$ch};
foreach my $frq (@{$delfreq{$bankno}}) {
if ($thisfrq == $frq) {
%myin = ('channel'=> $ch, 'bank'=>$bankno);
my $rc = aor_cmd('PD',$parmref);
if ($rc) {
LogIt(1,"AOR l2985: 'PD' command failed. " .
"sent=$parmref->{'_sent'} " .
"received=$parmref->{'_received'} " .
"rc=$parmref->{'_rc'}");
}
else {
print "Removed $frq in channel $ch from bank $bankno\n";
$delcount++;
}
next CHLIST;
}### deleted the frequency
}### For each frequency to removed
}### For each channel  to check for  this bank
}### For each bank number
if ($delcount) {
LogIt(0,"$Bold Removed $Green$delcount$White pass frequencies");
}
else {
LogIt(0,"$Bold No pass frequencies were removed from the radio");
}
}### There are frequencies to remove
aor_cmd('EX',$parmref);
$parmref->{'in'} = $insave;
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = $GoodCode);
}### Setpass
elsif ($cmdcode eq 'getpass') {
if ($Debug2) {LogIt(0,"AOR_CMD l2927 starting 'getpass'");}
if (!$db) {LogIt(2931,"AOR_CMD:No database reference for GETPASS");}
$in->{'database'} = $db;
my $maxbank = $defref->{'searchchan'} -1;
print "$Eol";
foreach my $bank (0..$maxbank) {
print STDERR "\rReading pass for Search Bank:$Bold$Green" . sprintf("%08.8u",$bank) . $Reset ;
$in->{'bank'} = $bank;
if ($model =~ /8000/) {
$parmref->{'write'} = TRUE;
aor_cmd('BN',$parmref);
$parmref->{'write'} = FALSE;
$in->{'bank'} = '';
}
aor_cmd('PR',$parmref);
}
print $Eol;
aor_cmd('EX',$parmref);
return ($parmref->{'rc'} = $GoodCode);
}### GETPASS command process
elsif ($cmdcode eq 'test') {
}
elsif ($cmdcode eq 'AC') {
return ($parmref->{'rc'} = $NotForModel);
}
elsif ($cmdcode eq 'AS') {
if ($model =~ /8000/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $auto = $in->{'autostore'};
if (defined $auto){
if ($auto) {$parmstr = 1;}
else {$parmstr = 0;}
}
else {
LogIt(1,"AOR l3051:Forgot parameter 'autostore' for AS call!");
return $ParmErr;
}
}
else {$parmstr = '';}
}### AS Preprocess
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
if ($model !~ /dv/i) {
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
my $links = $in->{'links'};
if ((!defined $links) or ($links eq '')) {
LogIt(1,"AOR 3124 'BK': LINKS key missing for SET! Caller=$caller");
return $ParmErr;
}
$parmstr = $links;
}
else {$parmstr = '';}
}### BK preprocess
elsif ($cmdcode eq 'BM') {
if ($model =~ /dv/i) {return $NotForModel;}
$parmstr = '';
if ($parmref->{'write'}) {
my $links = $in->{'links'};
if ((!defined $links) or ($links eq '')) {
LogIt(1,"AOR 3168 'BM': LINKS key missing for SET! Caller=$caller");
return $ParmErr;
}
$links =~ s/ //g;
if (length($links) % 2) {
LogIt(1,"AOR 3175 'BM' $in->{'links'} has odd number of chars!");
return $ParmErr;
}
if (!looks_like_number($links)) {
LogIt(1,"AOR l2181:'BM' links: $in->{'links'} contains non-numeric characters!");
return $ParmErr;
}
if ($model =~ /8000/) {
$parmstr = bank_to_char($links,'');
}
else {
while (length($links)) {
my $bank = substr($links,0,2);
$links = substr($links,2);
if ($bank > 39) {next;}
$parmstr = "$parmstr$bank ";
}### while $links
}
if (!$parmstr) {return $NotForModel;}
}### Set
}### BM preprocess
elsif ($cmdcode eq 'BN') {
if ($model !~ /8000/) {return $NotForModel;}
if ($parmref->{'write'}) {
my $bank = $in->{'bank'};
if ((!defined $bank) or ($bank eq '')) {
LogIt(1,"AOR 3071 'BN': Bank number missing for SET! Caller=$caller");
return $ParmErr;
}
if ((!looks_like_number($bank)) and ($bank >= 0)) {
LogIt(1,"AOR 3077 'BN': Invalid bank $bank!");
return $ParmErr;
}
if ($bank > 19) {return $NotForModel;}
$parmstr = substr($alpha,$bank,1);
}#### SET process
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
elsif ($cmdcode eq 'BQ') {
if ($model =~ /dv/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $link = $in->{'lstate'};
if (defined $link) {
if ($link) {$parmstr = '1';}
else {$parmstr = '0';}
}
else {
LogIt(1,"AOR l3333:Forgot parameter 'LSTATE' for BQ call!");
return $ParmErr;
}
}
else {$parmstr = '';}
}### BQ Pre-process
elsif ($cmdcode eq 'BS') {
if ($model =~ /dv/i) {return $NotForModel;}
$parmstr = '';
if ($parmref->{'write'}) {
my $links = $in->{'links'};
if ((!defined $links) or ($links eq '')) {
LogIt(1,"AOR 3384 'BS': LINKS key missing for SET! Caller=$caller");
return $ParmErr;
}
$links =~ s/ //g;
if (length($links) % 2) {
LogIt(1,"AOR 3391 'BS' $in->{'links'} has odd number of chars!");
return $ParmErr;
}
if (!looks_like_number($links)) {
LogIt(1,"AOR l3395:'BS' links: $in->{'links'} contains non-numeric characters!");
return $ParmErr;
}
if ($model =~ /8000/) {
$parmstr = bank_to_char($links,'');
}
else {
while (length($links)) {
my $bank = substr($links,0,2);
$links = substr($links,2);
if ($bank > 39) {next;}
$parmstr = "$parmstr$bank ";
}### while $links
}
if (!$parmstr) {return $NotForModel;}
}### Set
}### BS preprocess
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
elsif ($cmdcode eq 'DJ') {
if ($model !~ /dv/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $dpcode = $in->{'data'};
if (defined $dpcode) {
$parmstr = $dpcode;
}
else {
LogIt(1,"AOR l3066:Forgot parameter 'data' for $cmdcode call!");
return $ParmErr;
}
}### Set
else {$parmstr = '';}
}
elsif ($cmdcode eq 'DL') {
if ($model !~ /dv/i) {return $NotForModel;}
$parmstr = '';
if ($parmref->{'write'}) {
my $delay = $in->{'delay'};
if (!defined $delay) {
LogIt(1,"AOR l3617 'DL': Forgot 'delay' key for set!");
return $ParmErr;
}
if ((!looks_like_number($delay)) or ($delay < 0) or ($delay > 100)) {
LogIt(1,"AOR L3621 'DL': Invalid 'delay' value=>$delay");
return $ParmErr;
}
$parmstr = sprintf("%03.3u",$delay);
}
}### DL command
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
elsif ($cmdcode eq 'FR') {
if ($model !~ /dv/i) {return $NotForModel;}
$parmstr = '';
if ($parmref->{'write'}) {
my $resume = $in->{'resume'};
if (!defined $resume) {
LogIt(1,"AOR l3716 'FR': Forgot 'resume' key for set!");
return $ParmErr;
}
if ((!looks_like_number($resume)) or ($resume < 0) or ($resume > 60)) {
LogIt(1,"AOR L3720 'FR': Invalid 'resume' value=>$resume");
return $ParmErr;
}
$parmstr = sprintf("%02.2u",$resume);
}
}### FR command
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
}### IF
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
if ($model =~ /8000/) {
LogIt(1,"Called MA for model AR8000!");
return $NotForModel;
}
my $dbase = $in->{'database'};
if (!$dbase) {LogIt(4557,"MA command requires a database! Caller=>$caller");}
my $bank = $in->{'bank'};
if (defined $bank) {
if (!looks_like_number($bank))  {
LogIt(1,"AOR l4562: Invalid 'bank'=>$bank spec for $cmdcode");
return $ParmErr;
}
if (($bank < 0) or ($bank > 39)) {
LogIt(1,"AOR l4566: 'bank'=>$bank out of range for $cmdcode");
return $ParmErr;
}
$bank = sprintf("%02.2u",$bank);
$parmstr = $bank;
$in->{'bank'} = $bank;
}
else {
LogIt(1,"AOR l4040: MA command requires a bank spec! Caller=>$caller");
return $ParmErr;
}
$in->{'_chan'} = 0;
$in->{'_multi'} = TRUE;
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
elsif ($cmdcode eq 'MG') {
if ($model !~ /dv/i) {return $NotForModel;}
my $bank = $in->{'bank'};
if (!defined $bank) {
LogIt(1,"AOR l3944 'MG':Forgot required 'bank' key!");
return $ParmErr;
}
if ((!looks_like_number($bank)) or ($bank > 39) or ($bank < 0)) {
LogIt(1,"AOR l3951: '$cmdcode' $bank is NOT a valid bank number");
return $ParmErr;
}
$parmstr = sprintf("%02.2u",$bank);
if ($parmref->{'write'}) {
my $delay = $in->{'delay'};
if (!defined $delay) {
LogIt(1,"AOR l3960 '$cmdcode': Forgot 'delay' key for set!");
return $ParmErr;
}
if ((!looks_like_number($delay)) or ($delay < 0) or ($delay > 100)) {
LogIt(1,"AOR L3965 '$cmdcode': Invalid 'delay' value=>$delay");
return $ParmErr;
}
$parmstr = $parmstr . ' DL' . sprintf("%03.3u",$delay);
my $resume = $in->{'resume'};
if (!defined $resume) {
LogIt(1,"AOR l3966 '$cmdcode': Forgot 'resume' key for set!");
return $ParmErr;
}
if ((!looks_like_number($resume)) or ($resume < 0) or ($resume > 60)) {
LogIt(1,"AOR L3977 '$cmdcode': Invalid 'resume' value=>$resume");
return $ParmErr;
}
$parmstr = $parmstr . ' FR' . sprintf("%02.2u",$resume);
my $links = $in->{'link'};
if (!defined $links) {
LogIt(1,"AOR l3971 'MG': Forgot 'link' key for set!");
return $ParmErr;
}
$links =~ s/ //g;  
if (length $links) {
if (link_check($links)) {return $ParmErr;}
}
else {$links = '99';}
$parmstr = $parmstr . " BK$links";
}### SET
}### MG pre-process
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
my $aorchan = $in->{'aorchan'};
if ((!defined $aorchan) or (!looks_like_number($aorchan)) or ($aorchan < 0)) {
return $ParmErr;
}
if ($model =~ /8000/) {$parmstr = substr($aorchan,1);}
else {$parmstr = $aorchan;}
}### MQ
elsif ($cmdcode eq 'MR') {
my $ch = $in->{'aorchan'};
if (!defined $ch) {
LogIt(5242,"Forgot 'aorchan' for MR. Caller:$caller");
}
$parmstr = sprintf("%04.4u",$ch);
}### MR
elsif ($cmdcode eq 'MS') {
$parmstr = '';
}
elsif ($cmdcode eq 'MX') {
my $aorchan = $in->{'aorchan'};
if (!defined $aorchan) {
LogIt(4725,"Forgot channel for call to MX!");
}
if (!defined $in->{'frequency'}) {
LogIt(4728,"Forgot frequency for call to MX!");
}
$parmstr = "$aorchan " . set_keys($in,$model);
}### MX
elsif ($cmdcode eq 'PD') {
$parmstr = '';
my $bank = $in->{'bank'};
if (!defined $bank) {
LogIt(1,"AOR l4449 $cmdcode: Required key 'bank' missing!");
return $ParmErr;
}
if ((!looks_like_number($bank)) or ($bank > 39)) {
LogIt(1,"AOR l4449 $cmdcode: $bank is not valid for 'bank' key!");
return $ParmErr;
}
my $channel = $in->{'channel'};
if (!defined $channel) {
LogIt(1,"AOR l4460 $cmdcode: Required key 'channel' missing!");
return $ParmErr;
}
if ((!looks_like_number($channel)) or ($channel > 49)) {
LogIt(1,"AOR l4464 $cmdcode: $channel is not valid for 'channel' key!");
return $ParmErr;
}
if ($model =~ /8000/) {
$parmref->{'write'} = TRUE;
my $rc = aor_cmd('BN',$parmref);
if ($rc) {return $rc};
}
else {
$parmstr = sprintf("%02.2u",$bank);
}
$parmstr = $parmstr . sprintf("%02.2u",$channel);
}### 'PD' command process
elsif ($cmdcode eq 'PR') {
my $dbase = $in->{'database'};
if (!$dbase) {LogIt(3739,"PR command requires a database");}
my $bank = $in->{'bank'};
if (!defined $bank) {$bank = '.';}
if ((looks_like_number($bank)) and ($bank >= 0)) {
if ($bank > 39) {
LogIt(1,"AOR L3852 'PR' command value $bank is invalid!");
return $ParmErr;
}
if ($model =~ /8000/) {
if ($bank > 19) {return $NotForModel;}
$bank = substr($alpha,$bank,1);
}
else {$bank = sprintf("%02.2u",$bank);}
$parmstr = $bank;
}## Numeric and >= 0
}### PR Pre-Process
elsif ($cmdcode eq 'PW') {
my $bank = $in->{'bank'};
my $freq = $in->{'frequency'};
if (!defined $bank) {
LogIt(4608,"AOR 'PW' Forgot to define 'aorbank'! Caller:$caller");
}
if (!looks_like_number($bank)) {
LogIt(4611,"AOR 'PW' $bank is not a valid bank number! Caller:$caller");
}
if (($bank < 0) or ($bank > 39) ) {
LogIt(4613,"AOR 'PW' $bank is out of range! Caller:$caller");
}
if (!$freq) {
LogIt(4617,"AOR 'PW' Forgot frequency! Caller:$caller");
}
$freq =  Strip(rc_to_freq($freq));
$parmstr = $freq;
}### PW process
elsif ($cmdcode eq 'RE') {
if ($model !~ /dv/i) {return $NotForModel;}
if ($parmref->{'write'}) {
if ($in->{'response'}) {$parmstr = '1';}
else {$parmstr = '0';}
}
}
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
elsif ($cmdcode eq 'SD') {
if ($model =~ /dv/i) {return $NotForModel;}
if ($parmref->{'write'}) {
my $delay = $in->{'delay'};
if (!defined $delay) {
LogIt(1,"AOR l4560 '$cmdcode': Forgot 'delay' key for set!");
return $ParmErr;
}
if ((!looks_like_number($delay)) or ($delay < 0) or ($delay > 100)) {
LogIt(1,"AOR L4684 '$cmdcode': Invalid 'delay' value=>$delay");
return $ParmErr;
}
if ($delay > 99) {$parmstr = 'FF';}
else {$parmstr =  sprintf("%02.2u",$delay);}
}### Setting
}### SD command
elsif ($cmdcode eq 'SE') {
if (defined $in->{'bank'}) {
$parmstr = "$in->{'bank'} " . set_keys($in,$model);
}
else {
LogIt(1,"Forgot bank code for SR!");
return $ParmErr;
}
}
elsif ($cmdcode eq 'SG') {
if ($model !~ /dv/i) {return $NotForModel;}
my $bank = $in->{'bank'};
$parmstr = '';
if (!defined $bank) {$bank = '';}
else {
if ((!looks_like_number($bank)) or ($bank > 39) or ($bank < 0)) {
LogIt(1,"AOR l4620: '$cmdcode' $bank is NOT a valid bank number");
return $ParmErr;
}
$parmstr = sprintf("%02.2u",$bank);
}
if ($parmref->{'write'}) {
my $delay = $in->{'delay'};
if (!defined $delay) {
LogIt(1,"AOR l4631 '$cmdcode': Forgot 'delay' key for set!");
return $ParmErr;
}
if ((!looks_like_number($delay)) or ($delay < 0) or ($delay > 100)) {
LogIt(1,"AOR L4635 '$cmdcode': Invalid 'delay' value=>$delay");
return $ParmErr;
}
$parmstr = $parmstr . ' DL' . sprintf("%03.3u",$delay);
my $resume = $in->{'resume'};
if (!defined $resume) {
LogIt(1,"AOR l4635 '$cmdcode': Forgot 'resume' key for set!");
return $ParmErr;
}
if ((!looks_like_number($resume)) or ($resume < 0) or ($resume > 60)) {
LogIt(1,"AOR L4646 '$cmdcode': Invalid 'resume' value=>$resume");
return $ParmErr;
}
$parmstr = $parmstr . ' FR' . sprintf("%02.2u",$resume);
my $autostore = $in->{'autostore'};
if (defined $autostore) {
if ($autostore) {$parmstr = "$parmstr AS1";}
else {$parmstr = "$parmstr AS0";}
}
else {
LogIt(1,"AOR L4658 '$cmdcode': Forgot to include 'autostore' key");
return $ParmErr;
}
my $links = $in->{'link'};
if (!defined $links) {
LogIt(1,"AOR l4665 '$cmdcode': Forgot 'link' key for set!");
return $ParmErr;
}
$links =~ s/ //g;  
if (length $links) {
if (link_check($links)) {return $ParmErr;}
}
else {$links = '99';}
$parmstr = $parmstr . " BK$links";
}### SET
}### SG pre-process
elsif ($cmdcode eq 'SR') {
my $bank = $in->{'bank'};
if (!defined $bank) {
LogIt(1,"AOR l4755 $cmdcode: Forgot bank code for SR! Caller=>$caller");
return $ParmErr;
}
if (!looks_like_number($bank)) {
LogIt(1,"AOR l4759 $cmdcode: $bank is not a valid bank number. Caller=>$caller");
return $ParmErr;
}
if ($bank > $defref->{'searchchan'}) {return $NotForModel;}
if ($model =~ /8000/) {
$parmstr = substr($alpha,$bank,1);
}
else {$parmstr = sprintf("%02.2u",$bank);}
}
elsif ($cmdcode eq 'SS') {
my $bank = $in->{'bank'};
if (!defined $bank) {
LogIt(1,"Forgot to define 'bank'");
return $ParmErr;
}
if ($model =~ /8000/) {
$parmstr = substr($alpha,$bank,1);
}
else {$parmstr = sprintf("%02.2u",$bank);}
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
$parmref->{'_sent'} = '';
$parmref->{'_returned'} = '';
$parmref->{'_rc'} = '';
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
$parmref->{'_sent'} = $sent;
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
$parmref->{'_rc'} = $radio_code;
}
}
my @returns = split " ",$instr;
$instr = Strip($instr);
$parmref->{'_returned'} = $instr;
if ($Debug3) {LogIt(0,"AOR_CMD:CMD=$cmdcode AOR returned =>$instr<=");}
$parmref->{'rc'} = $GoodCode;
if ($cmdcode eq 'test') {
$parmref->{'rsp'} = FALSE;
return ($parmref->{'rc'} = $GoodCode);
}
POST_PROCESS:
if ($cmdcode eq 'AC') {
if ($instr =~ /ac/i) {
($out->{'agc'}) = $instr =~ /ac(\d)./;
}
}### AC post-process
elsif ($cmdcode eq 'AS') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L5332: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
if ($instr =~ /as1/i) { $out->{'autostore'} = TRUE;}
else {$out->{'autostore'} = FALSE;}
}
}### AS post process
elsif ($cmdcode eq 'AT') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
if ($instr =~ /at1/i) { $out->{'atten'} = TRUE;}
else {$out->{'atten'} = FALSE;}
}
}
elsif ($cmdcode eq 'BK') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L4653: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
if (substr($instr,0,2) ne 'BK') {
print "AOR l4658:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'link'} = substr($instr,2);
}
}### BK post process
elsif ($cmdcode eq 'BM') {
if ($instr) {
if (substr($instr,0,2) ne 'BM') {
print "AOR l4772:Issued $sent Returned=$instr\n";
goto WAIT;
}
my $link  = substr($instr,2);
$link =~ s/ //g;   
if ($model =~ /8000/) {
$out->{'link'} = bank8_to_num($link);
}
else {
my $out = '';
foreach my $ndx (0..39) {
if (substr($link,$ndx,1) ne '-') {
$out = $out . sprintf("%02.2u",$ndx);
}
}
$out->{'link'} = $out;
}
}### $instr had some value
}## 'BM' post process
elsif ($cmdcode eq 'BN') {
if ($instr) {
my ($sb,$cb) = $instr =~ /SR(.+?) MX(.*)/;
if (defined $sb) {
$out->{'search_bank'} = index($alpha,$sb,0);
}
else {
print "AOR Line 4476:Regex failed for SB! instr=>$instr\n";
$out->{'search_bank'} = -1;
}
if (defined $cb) {
$out->{'scan_bank'} = index($alpha,$cb,0);
}
else {
print "AOR Line 4482:Regex failed for CB! instr=$instr!\n";
$out->{'scan_bank'} = -1
}
}
}### 'BN' command
elsif ($cmdcode eq 'BP') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3698: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
if (substr($instr,0,2) ne 'BP') {
print "AOR l4050:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'beep'} = substr($instr,2);
}
}
elsif ($cmdcode eq 'BQ') {
if ($instr) {
if (substr($instr,0,2) ne 'BQ') {
print "AOR l4906:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'lstate'} = substr($instr,2,1);
}### Something returned
}### BQ Post process
elsif ($cmdcode eq 'BS') {
if ($instr) {
if (substr($instr,0,2) ne 'BS') {
print "AOR l5040:Issued $sent Returned=$instr\n";
goto WAIT;
}
my $link  = substr($instr,2);
$link =~ s/ //g;   
if ($model =~ /8000/) {
$out->{'link'} = bank8_to_num($link);
}
else {
my $out = '';
foreach my $ndx (0..39) {
if (substr($link,$ndx,1) ne '-') {
$out = $out . sprintf("%02.2u",$ndx);
}
}
$out->{'link'} = $out;
}
}### $instr had some value
}### BS post process
elsif ($cmdcode eq 'CI') {
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
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3275: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
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
elsif ($cmdcode eq 'DJ') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne 'DJ') {
print "AOR l5301:Issued $sent Returned=$instr\n";
goto WAIT;
}
if (substr($instr,2,1)){$out->{'data'} = 1;}
else {$out->{'data'} = 0;}
}### value returned
}### DJ post process
elsif ($cmdcode eq 'DL') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne $cmdcode) {
print "AOR l5563:Issued $sent Returned=$instr\n";
goto WAIT;
}
($out->{'delay'}) = substr($instr,2);
}
}
elsif ($cmdcode eq 'DS') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3346: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
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
elsif ($cmdcode eq 'FR') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne $cmdcode) {
print "AOR l5658:Issued $sent Returned=$instr\n";
goto WAIT;
}
($out->{'resume'}) = substr($instr,2);
}
}### FR Post Process
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
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3443: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if (substr($instr,0,2) ne 'LM') {
print "AOR l4344:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
$out->{'rssi'} = 0;
if ($instr) {
extract_keys($out,$instr);
}
else {
LogIt(1,"AOR l3467: LM did not return any value!");
return ($parmref->{'rc'} = $ParmErr);
}
}#### LM post-process
elsif ($cmdcode eq 'MA') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L6722: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
my %out = ();
if ($instr) {
my $first = substr($instr,0,2);
if ($first !~ /mx/i) {
goto WAIT;
}
my $groupno = $in->{'groupno'};
if (!$groupno) {$groupno = 0;}
my ($grp,$chan,$instr) = $instr =~ /MX(\d\d)(\d\d) (.*)/;
if ($grp ne $in->{'bank'}) {
goto WAIT;
}
my $aorchan = "$grp$chan";
my $expecting = $in->{'_chan'};
if (!defined $expecting) {
print Dumper($in),"\n";
LogIt(6779,"'_chan' was not set!");
}
if ($chan != $expecting) {
LogIt(1,"Got mismatch channel. Expecting $expecting. Got $chan");
}
extract_keys(\%out,$instr);
my %freqrec = (
'groupno' => $groupno,
'channel' =>  sprintf("%02.2i",$grp) . sprintf("%02.2i",$chan),
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
$freqrec{'fstep'} = 5000;
if ($out{'step'}) {$freqrec{'fstep'} = $out{'step'};}
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
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3547: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
if (substr($instr,0,2) ne 'MD') {
print "AOR l4530:Issued $sent Returned=$instr\n";
goto WAIT;
}
extract_keys($out,$instr);
}
}
elsif ($cmdcode eq 'MG') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3564: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne $cmdcode) {
print "AOR l5868:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'bank'} = substr($instr,2,2);
my ($delay,$resume,$link) = $instr =~ /DL(\d\d\d) FR(\d\d) BK(.*)/;
$out->{'delay'} = $delay;
$out->{'resume'} = $resume;
$out->{'link'} = $link;
}
}### MG post Process
elsif ($cmdcode eq 'MM') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3564: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
}
elsif ($cmdcode eq 'MP') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3587: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
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
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L6825: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
}
elsif ($cmdcode eq 'MR') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) {
if (substr($instr,0,2) ne 'MX') {
print "AOR l7092:Issued $sent Returned=$instr\n";
goto WAIT;
}
extract_keys($out,$instr);
}
$out->{'state'} = 'MR';
$state_save{'state'} = 'MR';
}
elsif ($cmdcode eq 'MS') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3663: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
print "L2444:Changed to Memory Scan state\n";
$state_save{'state'} = 'MS';
}
elsif ($cmdcode eq 'MX') {
if ($model =~ /dv/i) {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3681: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return  $ParmErr;
}
}
if ($instr) {
print "Line 4825:$cmdcode returned=>$instr\n";
}
$state_save{'state'} = 'MR';
}
elsif ($cmdcode eq 'PD') {
if ($instr) {
print "AOR 6584:'PD returned $instr\n";
}
if ($model =~ /dv/i) {
if ($digit1 ne '2') {
LogIt(1,"AOR l5110: PD returned code $digit1$digit2");
}
}
}### 'PD' post process
elsif ($cmdcode eq 'PR') {
if ($model =~ /dv/i) {  
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L6694: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return  $ParmErr;
}
}
my $database = $in->{'database'};
if ($instr) {
my ($value) = $instr =~ /PR(.*)/;
if ($value =~ /\-\-/) {
}
else {
my $bank = 0;
my $chan = 0;
my $freq = 0;
if (looks_like_number(substr($value,0,1))) {
($bank,$chan,$freq) = $value =~ /(\d\d)(\d\d)\,(.*)/;
}
else {
($bank,$chan,$freq) = $value =~ /(.?)(\d\d?) (.*)/;
if (defined $bank) {$bank = index($alpha,$bank,0);}
}
if (!defined $bank) {
LogIt(1,"line AOR 5366:regex failed for bank. Value=$value");
$bank = -1;
}
if (!defined $chan) {
LogIt(1,"line AOR 5370:regex failed for chan. Value=$value");
$chan = -1;
}
if (!defined $freq) {
LogIt(1,"line AOR 5374:regex failed for freq. Value=$value");
$freq = 0;
}
my %rec = (
'frequency' => freq_to_rc($freq),
'bankno' => $bank,
'channel' => $chan,
);
add_a_record($database,'passfreq',\%rec);
goto WAIT;
}### Got a frequency
}### Got something input
}### PR Post Process
elsif ($cmdcode eq 'PW') {
if ($model =~ /dv/i) {  
if ($digit1 ne '2') {
if ($digit1 eq '3') {
LogIt(1,"AOR l6668  Search bank $Green$in->{'bank'}$White " .
"lockout frequency list is full!\n  " .
$Yellow . rc_to_freq($in->{'frequency'}) . $White .
" was not stored!");
}
elsif ($digit1 eq '5') {
LogIt(1,"AOR 6674: Search Bank $Green$in->{'bank'}$White " .
"is most likely not set!\n  " .
$Yellow . rc_to_freq($in->{'frequency'}) . $White .
" was not stored!");
}
else {
LogIt(1,"AOR l5083: PW returned code $digit1$digit2");
}
return "$digit1$digit2";
}
}
}### PW Post process
elsif ($cmdcode eq 'RE') {
if ($instr) {
if ($instr =~ /re1/i) {$out->{'response'} = TRUE;}
else {$out->{'response'} = FALSE;}
}
}
elsif ($cmdcode eq 'RF') {
if ($model =~ /dv/i) {  
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L4721: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
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
if ($digit1) {
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
elsif ($cmdcode eq 'SD') {
if ($instr) {
if (substr($instr,0,2) ne $cmdcode) {
print "AOR l6720:Issued $sent Returned=$instr\n";
goto WAIT;
}
my $delay = substr($instr,2);
if ($delay =~ /ff/i) {$delay = 100;}
$out->{'delay'} = $delay
}### something returned
}### SD post process
elsif ($cmdcode eq 'SE') {
if ($model =~ /dv/i) {  
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3767: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
$state_save{'state'} = 'SS';
}
elsif ($cmdcode eq 'SG') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L6711: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
if ($instr) {
if (substr($instr,0,2) ne $cmdcode) {
print "AOR l6720:Issued $sent Returned=$instr\n";
goto WAIT;
}
$out->{'bank'} = substr($instr,2,2);
my ($delay,$resume,$autostore,$link) = $instr =~ /DL(\d\d\d) FR(\d\d) AS(\d) BK(.*)/;
$out->{'delay'} = $delay;
$out->{'resume'} = $resume;
$out->{'autostore'} = $autostore;
$out->{'link'} = $link;
}### Something returned
}### SG Post process
elsif ($cmdcode eq 'SR') {
if ($model =~ /dv/i) {  
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
elsif ($cmdcode eq 'SS') {
$state_save{'state'} = 'SS';
}
elsif ($cmdcode eq 'SX') {
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return $EmptyChan;
}
}
elsif ($cmdcode eq 'ST') {
if ($model =~ /dv/i) {  
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3815: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
}
if ($instr) { extract_keys($out,$instr);}
}### RF post-process
elsif (($cmdcode eq 'VA')  or ($cmdcode eq 'VB') or ($cmdcode eq 'VZ')) {
if ($model =~ /dv/i) {  
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
LogIt(1,"L3833: AOR rejected command $sent  returned=>$digit1$digit1$instr Caller=$caller");
return ($parmref->{'rc'} = $ParmErr);
}
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
if ($model =~ /dv/i) {  
if (($digit1 > 2) or ($instr =~ /^\?/)) {   
return ($parmref->{'rc'} = $ParmErr);
}
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
$out->{'step'} = 10;
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
elsif ($key =~ /st/i) {###
my $save = $value;
if ($value =~ /\./) {
$value =  int($value * 1000);
}
else {
}
$out->{'step'} = $value;
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
if ($key =~ /start/i) {$kw = 'SL';}
elsif ($key =~ /end/i) {$kw = 'SU';}
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
$value = sprintf("%06.2f",$value/1000);
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
my $service = $hash->{'service'};
if (!$service) {$service = '.';}
if ($model =~ /8000/) {
$parmstr = "$parmstr TM$hash->{'service'}";
}
else {
$parmstr = "$parmstr TT$hash->{'service'}";
}
}
elsif (defined $hash->{'sserve'}) {
my $service = $hash->{'sserve'};
if (!$service) {$service = '.';}
$parmstr = "$parmstr TT$service";
}
}### parmstr has something
return $parmstr;
}### Set_Keys
sub rcmode2aor {
my ($pkg,$fn,$caller) = caller;
my $mode = shift @_;
my $audio = shift @_;
my $model = shift @_;
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
'au' => '000',
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
'AU',
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
elsif (($a =~ /f/i)) { 
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
my $hash = shift @_;
my $model = shift @_;
if (!$hash) {
LogIt(8978,"RCCHAN2AOR: Missing HASH reference! Caller=>$caller");
}
if (!$model) {
LogIt(8984,"RCCHAN2AOR: Missing model number! Caller=$caller");
}
my $aorchan = $hash->{'aorchan'};
my $channel = $hash->{'channel'};
if ((defined $aorchan) and looks_like_number($aorchan)) {
}
elsif ((defined $channel) and (looks_like_number($channel))) {
if ($channel < 0) {
return -1;
}
$aorchan = $channel;
}
else {
return -1;
}
$aorchan = sprintf("%04.4i",$aorchan);
my $bank = substr($aorchan,0,2);
my $ch = substr($aorchan,2,2);
if ($ch > 49) {return -1;}
if ($model =~ /8000/) {
if ($bank > 19) {return -1;}
$aorchan = substr($alpha,$bank,1) . $ch;
}
else {
if ($bank > 39) {return -1;}
}
return $aorchan;
}### rcchan2aor
sub aorchan2rc {
my $aorchan =  shift @_;
my $rcchan = -1;
if (looks_like_number($aorchan)) {
$rcchan = sprintf("%04.4i",$aorchan);
my $bank = substr($rcchan,0,2);
if ($bank > 39) {return -1;}
my $chan = substr($rcchan,2);
if ($chan > 49) {return -1;}
}
else {
my $bankchar = substr(Strip($aorchan),0,1);
my $bank = index($alpha,$bankchar);
if ($bank < 0) {return -1;}
my $chan = substr($aorchan,1);
if (!looks_like_number($chan)) {return -1;}
if ($chan > 49) { return -1;}
$rcchan = sprintf("%2.2i",$bank) . sprintf("%2.2i",$chan);
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
sub bank8_to_num {
my $a8000 = shift @_;
$a8000 =~ s/ //i; 
my $out = '';
foreach my $ndx (0..(length($a8000)-1)) {
my $char = substr($a8000,$ndx,1);
if ($char eq '-') {next;}
my $index = index($alpha,$char,0);
if ($index >= 0) {$out = $out . sprintf("%02.2u",$index);}
}
return $out;
}
sub bank_to_char {
my $banks = shift @_;
my $pad = shift @_;
if (!defined $pad) {$pad = '';}
my $out = '';
$banks =~ s/ //i; 
if (link_check($banks)) {return $out;}
while (length($banks)) {
my $num = substr($banks,0,2);
$banks = substr($banks,2);
if ($num > 19) {next;}
my $char =  substr($alpha,$num,1);
if (length($out)) {$out = "$pad$out$char";}
else {$out = $char;}
}### while $banks
return $out;
}
sub link_check {
my $links= shift @_;
my $links_save = $links;
my $cmd = shift @_;
my ($pkg,$fn,$caller) = caller;
$links =~ s/ //g;  
if (length $links) {
if (!looks_like_number($links)) {
LogIt(1,"AOR l$caller $cmd: Invalid 'links' value=>$links_save");
return 1;
}
if (length($links) % 2) {
LogIt(1,"AOR l$caller $cmd: Odd number of 'links' value=>$links_save");
return 1;
}
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
