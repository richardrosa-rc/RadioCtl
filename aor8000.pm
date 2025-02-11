#!/usr/bin/perl -w
package aor8000;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(aor_cmd) ;
use strict;
use Data::Dumper;
use Text::ParseWords;
use radioctl;
use constant AOR_TERMINATOR => pack("H4","0D0A");
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw( time usleep ualarm gettimeofday tv_interval );
use autovivification;
no  autovivification;
my @mode2rc = ('WF','FM','AM','US','LS','CW');
my @rssi2sig   = (4,5,8,12,15,17,20,22,24,28);
my @sig2meter = (0,1,2, 3, 4, 5, 6, 7, 7, 7);
my %aorchans = ();
my $alpha = 'ABCDEFGHIJabcdefghij';
my $rcchan = 0;
foreach my $char (split "",$alpha) {
foreach my $num (0..49) {
my $key = $char . sprintf("%02.2u",$num);
$aorchans{$key} = $rcchan;
$rcchan++;
}
}
my @rcchan2aor = ();
foreach my $key (keys %aorchans) {$rcchan2aor[$aorchans{$key}] = $key;}
use constant AOR8000 => 'AOR-8000';
my %radio_limits = (
&AOR8000 => {'minfreq'  =>    500000,'maxfreq' =>1900000000 ,
'maxchan'  =>       999,
'group'    =>    FALSE,
'sigdet'   =>        2,
'origin'   =>        0,
'radioscan'=>        0,
},
);
my $model = AOR8000;
my $warn = TRUE;
my $chanper = 50;
my %state_save = (
'state' => '',
'mode'  => '',
);
my $protoname = 'aor';
use constant PROTO_NUMBER => 5;
$radio_routine{$protoname} = \&aor_cmd;
$valid_protocols{$protoname} = TRUE;
return TRUE;
sub aor_cmd {
my $cmdcode = shift @_;
my $parmref = shift @_;
my $defref    = $parmref->{'def'};
my $out  = $parmref->{'out'};
my $outsave = $out;
my $portobj = $parmref->{'portobj'};
my $db = $parmref->{'database'};
if ($db) {
}
else {$db = '';}
my $in   = $parmref->{'in'};
if ($in) {
}
else {$in = '';}
my $insave = $in;
my $write = $parmref->{'write'};
if (!$write) {$write = FALSE;}
my $delay = 10000;
$parmref->{'rc'} = $GoodCode;
my $parmstr = '';
if ($Debug2) {DebugIt("AOR l861:command=$cmdcode");}
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
$chanper = 50;
foreach my $key (keys %{$radio_limits{$model}}) {
$defref->{$key} = $radio_limits{$model}{$key};
}
@gui_modestring = ('WFM','FM','AM','LSB','USB','CW');
@gui_bandwidth  = ();
@gui_adtype = ();
@gui_attstring = ();
@gui_tonestring = ();
$parmref->{'write'} = FALSE;
if (aor_cmd('VA',$parmref)) {
LogIt(1,"AOR does not appear to be connected");
return ($parmref->{'rc'});
}
$parmref->{'in'} = $insave;
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'autobaud') {
my $model_save = $defref->{'model'};
my @allports = ();
if ($in->{'noport'} and $defref->{'port'}) {push @allports,$defref->{'port'};}
else {
if (lc($defref->{'model'}) ne 'icr30') {push @allports,glob("/dev/ttyUSB*");}
}
my @allbauds = ();
if ($in->{'nobaud'}) {push @allbauds,$defref->{'baudrate'};}
else {
@allbauds = (9600);
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
$portobj->baudrate($baud);
$warn = FALSE;
$parmref->{'write'} = FALSE;
$out->{'frequency'} = 0;
$rc = aor_cmd('RX',$parmref);
$warn = TRUE;
if (!$rc and $out->{'frequency'}) {### command succeeded
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
elsif ($cmdcode eq 'vfoinit') {
aor_cmd('DD',$parmref);
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'meminit') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'scan') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'poll') {
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'getvfo') {
if ($parmref->{'rc'} = aor_cmd('LM',$parmref)) {return $parmref->{'rc'};}
aor_cmd('RX',$parmref);
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'getsig') {
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
if (aor_cmd('LM',$parmref)) {return $parmref->{'rc'};}
if ($out->{'sql'}) {
aor_cmd('RX',$parmref);
}
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'setvfo') {
my $freq = $in->{'frequency'};
if (!$freq) {
add_message("AOR_CMD_l891:VFO frequency = 0 or undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
if (!check_range($freq,$defref)) {
add_message(rc_to_freq($freq) . " MHz is NOT valid for this radio");
return ($parmref->{'rc'} = $NotForModel);
}
my %out = ();
$parmref->{'out'} = \%out;
aor_cmd('RX',$parmref);
my $state = $out{'state'};
if (!$state) {
LogIt(1,"AOR_CMD l1128:Could not get radio state. " .
"Radio may be disconnected.");
return ($parmref->{'rc'} = $CommErr);
}
if (($state eq 'SCN') or ($state eq 'MEM')) {
aor_cmd('VF',$parmref);
}
elsif ($state eq 'SRC') {
aor_cmd('DD',$parmref);
}
$state = $out{'state'};
$parmref->{'out'} = $outsave;
$parmref->{'write'} = TRUE;
if ($state eq 'VFO') {aor_cmd('VA',$parmref);}
elsif ($state eq 'HLD') {aor_cmd('RF',$parmref);}
else {
LogIt(1,"AOR_CMD:Radio did NOT switch to VFO state. State=$state!");
return ($parmref->{'rc'} = $CommErr);
}
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'selmem') {
my $channel = $in ->{'channel'};
if (!defined $channel) {
add_message("AOR_CMD_l1171:Memory channel undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
if (!looks_like_number($channel)) {
add_message("AOR8000 l1202:Channel $channel is not numeric.");
return ($parmref->{'rc'} = $ParmErr);
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
add_message("AOR8000 l1206:Channel $channel out of range for radio");
return ($parmref->{'rc'} = $NotForModel);
}
aor_cmd ('MR',$parmref);
$parmref->{'in'} = $insave;
return $parmref->{'rc'};
}
elsif ($cmdcode eq 'getmem') {
if ($Debug2) {DebugIt("AOR l1289:got 'getmem'");}
my $startstate = $progstate;
my $maxcount = 1999;
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
my %sysrec = ('systemtype' => 'CNV','service' => "AOR8000", 'valid' => TRUE);
$sysno = add_a_record($db,'system',\%sysrec,$parmref->{'gui'});
}
my $igrp = 0;
my $grpndx = 0;
CHANLOOP:
while ($channel <= $maxchan) {
if (!$grpndx) {
my %grouprec = ('sysno' =>$sysno,
'service' => "AOR8000 Group/Bank:$igrp",
'valid' => TRUE
);
$grpndx = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$igrp++;
}### New group creation
$vfo{'channel'} = $channel;
$vfo{'groupno'} = $grpndx;
threads->yield;
if ($progstate ne $startstate) {
LogIt(0,"$Eol Exited loop as progstate changed");
last CHANLOOP;
}
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green" . sprintf("%02.2u",$channel) .$Reset ;
}
$myout{'valid'} = FALSE;
$myout{'mode'} = 'auto';
$myout{'frequency'} = 0;
$myout{'sqtone'} = 'Off';
$myout{'dlyrsm'} = 0;
$myout{'atten'} = 0;
$myout{'service'} = '';
$myout{'tgid_valid'} = FALSE;
$myout{'channel'} = $channel;
$myout{'groupno'} = $grpndx;
$myin{'channel'} = $channel;
if ($nodup and $duplist{$channel}) {
if ($Debug2) {DebugIt("AOR l1452: Skipping duplicate channel $channel")}
}
else {
my $rc = aor_cmd ('MR',$parmref);
if ($rc) {
if ($Debug1) {DebugIt("AOR l1472: Return code $rc from 'MR'");}
}
else {
my $freq = $myout{'frequency'} + 0;
if ($noskip or $freq) {
if (!$freq) {$myout{'valid'} = FALSE;}
my $recno = add_a_record($db,'freq',\%myout,$parmref->{'gui'});
$vfo{'index'} = $recno;
$count++;
if ($count >= $maxcount) {last CHANLOOP;}
}### Not skipping
}### good return code from memory read routine
}### Not skipping duplicates
$channel++;
if (!($channel % $chanper)) {
$grpndx = 0;
}
}### Channel loop
print STDERR "\n";
$parmref->{'out'} = $outsave;
$parmref->{'in'} = $insave;
$outsave->{'count'} = $count;
$out->{'sysno'} = $sysno;
return ($parmref->{'rc'} = $GoodCode);
}### 'GETMEM'
elsif ($cmdcode eq 'setmem') {
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
my $emsg = "in  record $recno";
if ($frqrec->{'tgid_valid'}) {next;}
my $channel = $frqrec->{'channel'};
if (!looks_like_number($channel) or ($channel < 0)) {
print "\nChannel number $channel $emsg is not defined. Skipped\n";
next;
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
print "\nChannel number $channel $emsg is not within range of radio. Skipped\n";
next;
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
next;
}
if ($found_chan{$channel}) {
LogIt(1,"Channel $channel was found twice $emsg. Second iteration skipped!");
next;
}
$found_chan{$channel} = TRUE;
my $freq = $frqrec->{'frequency'};
if (!looks_like_number($freq)) {next;}
if ($freq) {
if (!check_range($freq,$defref)) {next;}
}
print STDERR "\rSETMEM: Writing channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset,
" freq=>$Yellow",rc_to_freq($freq),$Reset;
%in = ();
foreach my $key (keys %{$frqrec}) {
$in{$key} = $frqrec->{$key};
}
my $rc = 0;
my $clear = FALSE;
$rc =  aor_cmd('MX',$parmref);
if (!$rc) {$count++;}
if ($count >= $max_count) {
print "$Eol$Bold Store terminated due to maximum record count reached$Eol";
last;
}
}### For each FREQ record
print "$Eol$Eol$Bold$Green$count$White Records stored.$Eol";
return 0;
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
aor_cmd('init',$parmref);
$out->{'chan_count'} = $defref->{'maxchan'};
$out->{'model'} = $model;
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'test') {
}
elsif ($cmdcode eq 'setsquelch') {
return;
}
elsif ($cmdcode eq 'AT') {
if ($parmref->{'write'}) {
if ($in->{'atten'}) {$parmstr = 1;}
else {$parmstr = 0;}
}
else { }
}
elsif ($cmdcode eq 'AU') {
if ($parmref->{'write'}) {
if ($in->{'auto'}) {$parmstr = 1;}
else {$parmstr = 0;}
}
else {  }
}
elsif ($cmdcode eq 'BM') {
if ($parmref->{'write'}) {
$parmstr = $in->{'link'};
}
else {  }
}
elsif ($cmdcode eq 'BS') {
if ($parmref->{'write'}) {
$parmstr = $in->{'link'};
}
else {  }
}
elsif ($cmdcode eq 'DD') {
}
elsif ($cmdcode eq 'LM') {
}
elsif ($cmdcode eq 'MQ') {
}
elsif ($cmdcode eq 'MR') {
my $channel = $in->{'channel'};
if (!$channel) {$channel = -1;}
if (looks_like_number($channel) and $channel >= 0) {
if ($channel > $defref->{'maxchan'}) {return $ParmErr;}
$parmstr = rc2aor($channel);
}### Channel specified
}## MR command Pre-Process
elsif ($cmdcode eq 'MX') {
my $channel = $in->{'channel'};
my $rcchan = '';
if (($channel < 0) or ($channel > $defref->{'maxchan'})) {
return ($parmref->{'rc'} = $ParmErr);
}
my $freq =  $in->{'frequency'};
if (!$freq) {
aor_cmd('MR',$parmref);
if ($out->{'frequency'}) {aor_cmd('MQ',$parmref);}
return $parmref->{'rc'};
}
$freq = Strip($freq);
my $lockout = 1;
if ($in->{'valid'}) {$lockout = 0;}
my $service = '.      ';
if ($in->{'service'}) {$service = sprintf("%7.7s",$in->{'service'});}
$parmref->{'write'} = TRUE;
my $aor_chan = rc2aor($channel);
$parmstr = "$aor_chan " .
"RF$freq MP$lockout AU0 " . set_keys($in) . " TM$service";
}## MX command
elsif ($cmdcode eq 'RF') {
if ($parmref->{'write'}) {
my $freq = Strip($in->{'frequency'});
if (!$freq) {
add_message("AOR_CMD_l1217:VFO frequency = 0 or undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = $freq . ' ' . set_keys($in);
}
}
elsif ($cmdcode eq 'RX') {
}
elsif (($cmdcode eq 'VA') or ($cmdcode eq 'VB')){
if ($parmref->{'write'}) {
$parmstr = $in->{'frequency'};
if (!$parmstr) {
add_message("AOR_CMD_l1272:VFO frequency = 0 or undefined not allowed");
return ($parmref->{'rc'} = $ParmErr);
}
$parmstr = "$parmstr " . set_keys($in);
}
}
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => CR,
'delay' => $delay,
'resend' => 0,
'debug' => 0,
'fails' => 1,
'wait' => 30,
);
RESEND:
my $outstr = $cmdcode;
if ($cmdcode eq 'test') {$outstr = $parmstr}
else {
$outstr = Strip("$outstr$parmstr");
}
if ($Debug3) {DebugIt("AOR l2200:sent =>$outstr");}
my $sent = $outstr;
$outstr = $outstr . AOR_TERMINATOR;
WAIT:
if ($Debug3) {DebugIt("AOR l2171:Waiting for Radio_Send..");}
if (radio_send(\%sendparms,$outstr)) {### send with retry
if (!$outstr) {
add_message("Radio did not like $sent...");
$defref->{'rsp'} = 0;
return ($parmref->{'rc'} = $CommErr);
}
else {
if ($defref->{'rsp'}) {$defref->{'rsp'}++;}
else {
$defref->{'rsp'} = 1;
if ($warn) {
LogIt(1,"no response to $outstr");
add_message("AOR8000_CMD l2208:Radio is not responding...");
}
}
return ($parmref->{'rc'} = $CommErr);
}
}### RadioSend error
if ($defref->{'rsp'}) {add_message("Radio is responding again...");}
$defref->{'rsp'} = 0;
$instr = $sendparms{'rcv'};
$instr =~ tr /\n//;
$instr =~ tr /\r//;
chomp $instr;
if ($Debug3) {DebugIt("AOR l2248:Radio returned=>$instr command=>$cmdcode");}
if (!$instr) {
if ($Debug3) {DebugIt("AOR l2253:Command $sent produced no data");}
return ($parmref->{'rc'} = $GoodCode);
}
if ($parmref->{'rsp'}) {add_message("Radio is responding again...");}
$parmref->{'rsp'} = FALSE;
my @returns = split " ",$instr;
$instr = Strip($instr);
my @parms = split " ",$instr;
my $rtcmd = substr($instr,0,2);
if ($Debug3) {DebugIt("AOR l2276:CMD=$cmdcode AOR returned =>$instr<=");}
$parmref->{'rc'} = $GoodCode;
if ($cmdcode eq 'test') {
$parmref->{'rsp'} = FALSE;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'AT') {
if ($instr) {$out->{'atten'} = substr($instr,2,1);}
}### AT post-process
elsif ($cmdcode eq 'AU') {
if ($instr) {$out->{'auto'} = substr($instr,2,1);}
}#### AU post process
elsif ($cmdcode eq 'BM') {
if ($instr) {$out->{'link'} = substr($instr,2);}
}#### BM post process
elsif ($cmdcode eq 'BS') {
if ($instr) {$out->{'link'} = substr($instr,2);}
}#### BS post process
elsif ($cmdcode eq 'DD') {
extract_keys($out,$instr,'DD');
}
elsif ($cmdcode eq 'LM') {
extract_keys($out,$instr,'LM');
}### LM process
elsif ($cmdcode eq 'MQ') {
}
elsif ($cmdcode eq 'MR') {
extract_keys($out,$instr,'MR');
}
elsif ($cmdcode eq 'MX') {
}
elsif ($cmdcode eq 'RF') {
if ($parmref->{'write'}) { }
else { extract_keys($out,$instr,'RF');}
$out->{'state'} = 'HLD';
}
elsif ($cmdcode eq 'RX') {
extract_keys($out,$instr,'RX');
}
elsif (($cmdcode eq 'VA') or ($cmdcode eq 'VB') or ($cmdcode eq 'VF')) {
if ($parmref->{'write'}) { }
else {extract_keys($out,$instr,'VA')};
$out->{'state'} = 'VFO';
}
else {
if (!$instr) {
LogIt(1,"AOR did not like command $cmdcode");
return ($parmref->{'rc'} = $NotForModel);
}
}### No handler process
return ($parmref->{'rc'});
}
sub extract_keys {
my $hash = shift @_;
my $data = shift @_;
my $caller = shift @_;
$hash->{'frequency'} = 0;
$hash->{'mode'} = $mode2rc[0];
$hash->{'atten'} = FALSE;
$hash->{'step'} = 1;
$hash->{'channel'} = -1;
$hash->{'valid'} = FALSE;
my @fields = split " ",$data;
foreach my $parm (@fields) {
my $key = substr($parm,0,2);
if (substr($key,0,1) eq '-') {next;}
my $value = '';
if (length($parm) > 2) {$value = substr($parm,2);}
if ($key eq 'VA') {$hash->{'frequency'} = $value;}
elsif ($key eq 'RF') {$hash->{'frequency'} = $value;}
elsif ($key eq 'VB') {$hash->{'frequency'} = $value;}
elsif ($key eq 'MD') {$hash->{'mode'} = $mode2rc[$value];}
elsif ($key eq 'AT') {$hash->{'atten'} = $value;}
elsif ($key eq 'ST') {$hash->{'step'} = $value;}
elsif ($key eq 'AU') { }### TODO:Auto:What to do with this?
elsif ($key eq 'MX') {
my $ch  = substr($value,1);
my $bank = substr($value,0,1);
my $igrp = index($alpha,$bank);
my $rcchan = $ch + ($igrp * $chanper);
$hash->{'channel'} = $rcchan;
$hash->{'_bank'} = $bank;
$hash->{'_ch'} = $ch;
}
elsif ($key eq 'LM') {
my $signal = rssi_cvt(substr($parm,2),$hash);
}
elsif ($key eq 'MP') {
if ($parm eq 'MP0') {$hash->{'valid'} = TRUE;}
}
elsif ($key eq 'TM') {
($hash->{'service'}) = $data =~ /TM(.*)/; 
last;
}
elsif ($key eq 'MS') {$hash->{'state'} = 'SCN';}
elsif ($key eq 'MR') {$hash->{'state'} = 'MEM';}
elsif ($key eq 'VF') {$hash->{'state'} = 'VFO';}
elsif ($key eq 'DD') {$hash->{'state'} = 'HLD';}
elsif ($key eq 'SS') {$hash->{'state'} = 'SRC';}
else {
if ($warn) {LogIt(1,"AOR_EXTRACT_KEYS:Unprocessed extract key $key");}
}
}
}
sub set_keys{
my $hash = shift @_;
my $options = '';
my $mode = $hash->{'mode'};
my $step = $hash->{'step'};
my $att  = $hash->{'atten'};
my $freq = $hash->{'frequency'};
if (!$freq) {$freq = 0;}
if (defined $mode) {
my $mode = lc(Strip($hash->{'mode'}));
if ($mode eq 'auto') {$mode = lc(AutoMode($freq));}
my $modecode = rc2mode($mode);
$options = "MD$modecode";
}
if (defined $step) {$options = "$options ST$step";}
if (defined $att) {
if ($att) {$att = 1;}
else {$att = 0;}
$options = "$options AT$att";
}
return $options
}
sub rssi_cvt {
my $value = shift @_;
my $out = shift @_;
my $signal = 0;
my $rssi = 0;
my $sql = FALSE;
$out->{'dbmv'} = $value;
if (!$value) {$value = 0;}
$value = Strip($value);
my $ishex = $value =~ /^[[:xdigit:]]+\z/;   
if ($value and $ishex)  {
$rssi = hex($value);
if ($rssi < 128) {$sql = TRUE;}
else {$rssi = $rssi - 128;}
foreach my $cmp (@rssi2sig) {
if (($rssi <=  $cmp) or ($signal >= MAXSIGNAL)){last;}
$signal++;
}
}
if (!$ishex) {
LogIt(1,"Invalid hex value $value passed to RSSI_CVT");
}
$out->{'meter'} = $sig2meter[$signal];
if ($sql and (!$signal)) {$signal = 1;}
$out->{'signal'} = $signal;
$out->{'sql'} = $sql;
$out->{'rssi'} = $rssi;
return $signal;
}
sub rc2aor {
my $channel = shift @_;
my $bank = int($channel / $chanper);
my $ch = $channel % $chanper;
my $aorch =  substr($alpha,$bank,1) . sprintf("%02.2u",$ch);
return $aorch;
}
sub rc2mode {
my $mode = shift @_;
my $code = 1;
if ($mode =~ /fmw/i) {$code = 0;}
elsif ($mode =~ /am/i) {$code = 2;}
elsif ($mode =~ /us/i) {$code = 3;}
elsif ($mode =~ /ls/i) {$code = 4;}
elsif ($mode =~ /cw/i) {$code = 5;}
elsif ($mode =~ /cr/i) {$code = 5;}
elsif ($mode =~ /rt/i) {$code = 5;}
elsif ($mode =~ /rr/i) {$code = 5;}
return $code;
}
