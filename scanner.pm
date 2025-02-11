#!/usr/bin/perl -w
package scanner;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(
manual_state
) ;
use Data::Dumper;
use Text::ParseWords;
use threads;
use threads::shared;
use Thread::Queue;
use Time::HiRes qw( time usleep ualarm gettimeofday tv_interval );
use Scalar::Util qw(looks_like_number);
use radioctl;
use kenwood;
use bearcat;
use uniden;
use icom;
use aor8000;
use local;
my $debug = FALSE;
use strict;
use autovivification;
no  autovivification;
my $use_memory = FALSE;
my $opchanges = 0;
my $dont_update = FALSE;
my $delay_flag  = FALSE;
my $portobj;
my %database = ();
my %delete_count = ();
my %known = ();
my %freq_xref = ();
my %tgid_xref = ();
foreach my $dbndx (@dblist) {
clear_database($dbndx);
$delete_count{$dbndx} = 0;
}
my $sysno = 1;
my %radio_parms = ();
my $last_squelch = 0;
my $radio_db_loaded = FALSE;
my $Resume = 6;
my $StateChange = 7;
my $SigKill = 8;
my $FreqChange = 9;
my $Squelched = 10;
my $Delay = 11;
my %sig_kill_states = (
'channel_scan'   => TRUE,
'frequency_scan' => TRUE,
'search'         => TRUE,
'bank_search'    => TRUE,
);
my $last_timestamp = 0;
my $allow_speed = FALSE;
my $local_on = FALSE;
my @unsolicited = ();
return TRUE;
sub manual_state {
my $cmd;
my $parms;
$scanner_thread = TRUE;
add_message("Starting program Initialization...");
$vfo{'index'} = 0;
$vfo{'service'} = $initmessage;
my $recorder_thread = threads->create('record_thread');
%scan_request = ('_cmd' => 'init');
tell_gui(281);
if (!defined $vfo{'channel'}) {
LogIt(223,"SCANNER l223:VFO 'channel' not defined!");
}
MANUAL_START:
if (!$radio_def{'protocol'}) {$vfo{'channel'} = '----';}
elsif ($radio_def{'protocol'} =~ /uniden/i) {$vfo{'channel'} = '----';}
else {$vfo{'channel'} = $radio_def{'origin'};}
$vfo{'index'} = 0;
$vfo{'freq'} = $radio_def{'minfreq'};
$vfo{'direction'} = 1;
$vfo{'_drok'} = FALSE;
radio_sync('init',227);
radio_sync('manual',383);
radio_sync('getvfo',249);
add_message('manual mode started');
while ($progstate ne 'quit') {
if ($response_pending) {$response_pending = '';}
my $retcode = scanner_sync();
$allow_speed = FALSE;
if (($progstate =~ /frequency/i) or ($progstate =~ /channel/i)) {scan_state();}
elsif ($progstate eq 'radio_scan')     {radio_scan_state();}
elsif ($progstate eq 'search')         {search_state();}
elsif ($progstate eq 'bank_search')    {bank_search_state();}
elsif ($progstate eq 'load')           {load_state();  }
elsif ($progstate eq 'quit') {
LogIt(0,"progstate now=$progstate");
goto MANUAL_END;
}
elsif ($progstate eq 'manual') {
}
else {LogIt(340,"MANUAL_STATE:Unknown progstate $progstate");}
while (scalar @unsolicited) {
my $qe = shift @unsolicited;
if ($qe->{'frequency'}) {
$vfo{'frequency'} = $qe->{'frequency'};
dply_vfo();
}
if ($qe->{'mode'}) {
$vfo{'mode'} = $qe->{'mode'};
dply_vfo();
}
}
if ($radio_def{'active'}) {
radio_sync('getvfo',335);
my $action = 'none';
if ($control{'manlog'}) {$action = 'find';}
if ($radio_def{'active'}) {
signal_check($action,332);
}
}
if (!$vfo{'frequency'} and (!$vfo{'tgid'})) {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
}
dply_vfo();
usleep($usleep{'MANUAL'});
}### while progstate ne QUIT
MANUAL_END:
LogIt(0,"$Bold SCANNER_THREAD:Got $Green QUIT$White from GUI");
if ($recorder_thread) {$recorder_thread->join();}
$scanner_thread = FALSE;
return TRUE;
}
sub scan_state {
my $starting_progstate = $progstate;
my $reason = '';
my $sev = 0;
$allow_speed = TRUE;
my $first_run = TRUE;
$vfo{'_drok'} = TRUE;
radio_sync('manual',479);
if ($progstate =~ /freq/i) {
radio_sync('vfoinit',1504);
}
else {
radio_sync('meminit',828);
}
SCAN_LOOP:
while (TRUE) {
my $found_cnt = 0;
foreach my $sysrec (@{$database{'system'}}) {
if (!$sysrec->{'index'}) {next;}
my $sysno = $sysrec->{'index'};
if ($control{'scansys'} and (!$sysrec->{'valid'})) {next;}
foreach my $grouprec (@{$database{'group'}}) {
if (!$grouprec->{'index'}) {next;}
my $groupno = $grouprec->{'index'};
if ($grouprec->{'sysno'} != $sysno) {next;}
if ($control{'scangroup'} and (!$grouprec->{'valid'})) {next;}
foreach my $freqrec (@{$database{'freq'}}) {
if (!$freqrec->{'index'}) {next;}
if ($freqrec->{'groupno'} != $groupno) {next;}
if (!$freqrec->{'valid'}) {next;}
my $freqno = $freqrec->{'index'};
my $channel = $freqrec->{'channel'};
if (!$channel) {$channel = 0;}
my $freq = $freqrec->{'frequency'};
if (!$freq) {$freq = 0;}
my $cmp = $channel;
if ($progstate =~ /freq/i) {
if (!$freq) {next;}
$cmp = $freqno;
}
if ($control{'start'} and ($cmp < $control{'start_value'} )) {
next;}
if ($control{'stop'} and ($cmp > $control{'stop_value'})) {next;}
if (!$radio_def{'active'}) {
$reason = 'Due To Radio not active';
$sev = 1;
last SCAN_LOOP;
}
if ($starting_progstate ne $progstate) {
$reason = "State change from $starting_progstate to $progstate";
last SCAN_LOOP;
}
$found_cnt++;
my $retcode = 0;
$vfo{'groupno'} = $groupno;
$vfo{'sysno'} = $sysno;
if (looks_like_number($channel) and ($channel >= 0)) {
$vfo{'channel'} = $channel;
}
$vfo{'index'} = $freqno;
if ($progstate =~ /freq/i) {
if (check_range($freq,\%radio_def)) {
foreach  my $key ('frequency','mode','atten','service','sqtone','preamp') {
$vfo{$key} = $database{'freq'}[$freqno]{$key};
}
dply_vfo();
$retcode = mem2vfo($freqno);
}
}### Frequency process
else {
if (($channel <= $radio_def{'maxchan'}) and
($channel >= $radio_def{'origin'})) {
dply_vfo();
$retcode = radio_sync('selmem',870);
}
}
if ($retcode) {
LogIt(0,"SCANNER l874:bypassing signal. Bad Return from RADIO_SYNC");
}
else {
$retcode = radio_sync('getvfo',838);
$retcode = signal_check('exist',839);
if ($retcode == $StateChange) {
$reason = "State change from $starting_progstate to $progstate";
last SCAN_LOOP;
}
}
}### Frequency records
}### Group records
}### system records
if ($found_cnt < 2) {
$reason = 'Too few valid records were found';
$sev = 1;
last SCAN_LOOP;
}
}### Main scanning loop
SCAN_TERMINATE:
if ($radio_def{'protocol'} =~ /uniden/i) {$vfo{'channel'} = '----';}
else {$vfo{'channel'} = $radio_def{'origin'};}
$vfo{'index'} = 0;
$vfo{'delay'} = 0;
$vfo{'resume'} = 0;
$vfo{'service'} = '';
%scan_request = ('_cmd' => 'control');
foreach my $key ('create','clear_db','swap','sortf','sortc','renum') {
$scan_request{$key} = 'enable';
}
tell_gui(867);
add_message("Scan terminated. $reason",$sev);
dply_vfo(788);
if ($progstate eq $starting_progstate) {set_manual_state();}
return $GoodCode;
}
sub radio_scan_state {
my $starting_progstate = $progstate;
my $reason = '';
my $sev = 0;
$vfo{'_drok'} = FALSE;
if (!$radio_def{'radioscan'}) {
return $NotForModel;
}
elsif ($radio_def{'radioscan'} == 1) {
}
else {radio_sync('scan',1020);}
my $index = 0;
my $statstring = '--scanning';
my $dlytime = time();
$allow_speed = FALSE;
%scan_request = ('_cmd' => 'control');
foreach my $key ('start','start_value','stop','stop_value',
'scangroup','scansys',
'rchan',
'att_amp'  ) {
$scan_request{$key} = 'disable';
}
tell_gui(422);
RADIOSCAN_LOOP:
while (TRUE) {
threads->yield;
scanner_sync();
if ($progstate ne $starting_progstate) {
$reason = "Scan state changed from $starting_progstate to $progstate";
last RADIOSCAN_LOOP;
}
my $dply = substr("$statstring$statstring",$index,4);
$vfo{'channel'} = substr($dply,0,4);
$vfo{'service'} = '';
dply_vfo(782);
my $delta = int( (time() - $dlytime) * 10);
if ($delta) {
$index++;
$dlytime = time();
}
if ($index > length($statstring)) {$index = 0;}
my $sigcode = signal_check('find',1098);
if ($starting_progstate ne $progstate) {
$reason = "State change from $starting_progstate to $progstate";
last RADIOSCAN_LOOP;
}
if (!$radio_def{'active'}) {
$reason = "Radio disconnected";
$sev = 1;
last RADIOSCAN_LOOP;
}
@unsolicited = ();
usleep($usleep{'SCAN'});
}### waiting for radio loop
RADIOSCAN_TERMINATE:
if ($radio_def{'radioscan'} == 1) {
pop_up("please press the scan stop button on the radio...");
}
if ($radio_def{'protocol'} =~ /uniden/i) {$vfo{'channel'} = '----';}
else {$vfo{'channel'} = $radio_def{'origin'};}
$vfo{'index'} = 0;
$vfo{'delay'} = 0;
$vfo{'resume'} = 0;
$vfo{'service'} = '';
radio_sync('manual',1043);
add_message("RadioScan mode terminated. $reason",$sev);
dply_vfo(788);
%scan_request = ('_cmd' => 'control');
foreach my $key ('start','start_value','stop','stop_value',
'scangroup','scansys',
'rchan',
'att_amp'  ) {
$scan_request{$key} = 'enable';
}
tell_gui(422);
if ($progstate eq $starting_progstate) {set_manual_state();}
return $GoodCode;
}
sub search_state {
my $starting_progstate = $progstate;
my $reason = '';
my $sev = 0;
$allow_speed = TRUE;
$vfo{'_drok'} = TRUE;
my $index = 0;
my $statstring = '--Searching';
my $dlytime = time();
%scan_request = ('_cmd' => 'control', 'rchan' => 'disable',
'att_amp' => 'disable',
);
tell_gui(1526);
add_message("$progstate Started...");
radio_sync('init',1221);
radio_sync('manual',1222);
radio_sync('vfoinit',1504);
if (!$radio_def{'active'}) {
$reason = "Radio not connected";
$sev = 1;
goto SEARCH_TERMINATE;
}
my $min = $radio_def{'minfreq'};
my $max = $radio_def{'maxfreq'};
if (!$min) {
LogIt(1517,"No minimum frequency defined for this radio!");
}
if (!$max) {
LogIt(1520,"No maximum frequency defined for this radio!");
}
my $freq = $vfo{'frequency'};
if (($freq > $max) or ($freq < $min))  {
$freq = $min;
$vfo{'frequency'} = $freq;
}
my $direction = 1;
$vfo{'direction'} = $direction;
my $step = $vfo{'step'};
if (!$step) {
$reason = 'Step value is 0';
$sev = 1;
GOTO SEARCH_TERMINATE;
}
$freq = $freq - $step;
SEARCH_LOOP:
while ($progstate eq $starting_progstate) {
if ($freq == $vfo{'frequency'}) {
$freq = $freq + ($step * $direction);
}
else  {
$freq = $vfo{'frequency'};
}
if ($freq > $max)  {$freq = $min;}
elsif ($freq < $min) {$freq = $max;}
my $dply = substr("$statstring$statstring",$index,4);
$vfo{'channel'} = substr($dply,0,4);
my $delta = int( (time() - $dlytime) * 10);
if ($delta) {
$index++;
$dlytime = time();
}
if ($index > length($statstring)) {$index = 0;}
my $skip = 0;
my $vfo_index = 0;
if (check_range($freq,\%radio_def)) {
foreach my $index (keys %{$freq_xref{$freq}}) {
if (!$database{'freq'}[$index]{'valid'}) {
$skip = $vfo{'frequency'};
last;
}
if (!$vfo_index) {$vfo_index = $index;}
}
}### frequency within range
else {$skip = $vfo{'frequency'};}
if (!$skip) {
$vfo{'frequency'} = $freq;
}
dply_vfo(1630);
my $freq_save = $vfo{'frequency'};
if (!$skip) {
my $radio_code = radio_sync('setvfo',1552);
$vfo{'index'} = $vfo_index;
my $rc = signal_check('use',1324);
if ($rc eq $StateChange) {
$reason = 'State change';
last SEARCH_LOOP;
}
}
$vfo{'frequency'} = $freq_save;
$step = $vfo{'step'};
if (!$step) {
$reason = 'VFO Step value is 0';
$sev = 1;
last SEARCH_LOOP;
}
$direction = $vfo{'direction'};
if ($skip) {
if ($skip == $vfo{'frequency'}) {$vfo{'frequency'} = $freq;}
}
}### Searching loop
SEARCH_TERMINATE:
add_message("Searching terminated. $reason",$sev);
%scan_request = ('_cmd' => 'control', 'rchan' => 'enable',
'att_amp' => 'enable',
);
tell_gui(1640);
$vfo{'index'} = 0;
if ($radio_def{'protocol'} =~ /uniden/i) {$vfo{'channel'} = '----';}
else {$vfo{'channel'} = $radio_def{'origin'};}
dply_vfo(788);
if ($progstate eq $starting_progstate) {set_manual_state();}
return $GoodCode;
}### Searching state
sub bank_search_state {
my $starting_progstate = $progstate;
my $reason = '';
my $sev = 0;
$allow_speed = TRUE;
$vfo{'_drok'} = TRUE;
my $index = 0;
my $statstring = '--Searching';
my $dlytime = time();
%scan_request = ('_cmd' => 'control', 'rchan' => 'disable', 'igrp' => 'disable',
'att_amp' => 'disable',
);
tell_gui(1526);
add_message("$progstate Started...");
radio_sync('init',1503);
radio_sync('vfoinit',1504);
if (!$radio_def{'active'}) {
$reason = "Radio is not connected";
$sev = 1;
goto BANK_TERMINATE;
}
my $radio_minfreq = $radio_def{'minfreq'};
my $radio_maxfreq = $radio_def{'maxfreq'};
if (!$radio_minfreq) {
LogIt(1517,"No minimum frequency defined for this radio!");
}
if (!$radio_maxfreq) {
LogIt(1520,"No maximum frequency defined for this radio!");
}
BANK_LOOP:
while ($progstate eq $starting_progstate) {
if (!$radio_def{'active'}) {
$reason = 'Radio is disconnected';
$sev = 1;
last BANK_LOOP;
}
my $valid_count = 0;
my $bank = 0;
BANK_RECS:
foreach my $bankrec (@{$database{'search'}}) {
if (!$bankrec->{'valid'}) {next;}
my $start = $bankrec->{'start_freq'};
my $end = $bankrec->{'end_freq'};
my $mode = $bankrec->{'mode'};
my $step = $bankrec->{'step'};
if (!$step) {next;}
my $direction = 1;
if ($end < $start) {$direction = -1;}
my $freq = $start - ($step * $direction);
BANK_FREQ_LOOP:
while (TRUE) {
my $dply = substr("$statstring$statstring",$index,4);
$vfo{'channel'} = substr($dply,0,4);
my $delta = int( (time() - $dlytime) * 10);
if ($delta) {
$index++;
$dlytime = time();
}
if ($index > length($statstring)) {$index = 0;}
$freq = $freq + ($step * $direction);
if ($direction > 0) {
if ($freq > $end) {
last BANK_FREQ_LOOP;
}
}
else {
if ($freq < $end) {
last BANK_FREQ_LOOP;
}
}
if (!check_range($freq,\%radio_def)) {
next BANK_FREQ_LOOP;
}
my $vfo_index = 0;
foreach my $index (keys %{$freq_xref{$freq}}) {
if (!$database{'freq'}[$index]{'valid'}) {
next BANK_FREQ_LOOP
}
if (!$vfo_index) {$vfo_index = $index;}
}
$valid_count++;
$vfo{'frequency'} = $freq;
$vfo{'mode'} = $mode;
dply_vfo(1812);
my $radio_code = radio_sync('setvfo',1552);
$vfo{'index'} = $vfo_index;
my $rc = signal_check('use',1600);
if ($rc eq $StateChange) {
$reason = "State Change from $starting_progstate to $progstate";
last BANK_LOOP;
}
}#### Bank_freq_loop
}### Bank record traversal
if (!$valid_count) {
$reason = 'No valid frequency or search records found';
$sev = 1;
last BANK_LOOP;
}
}#### Main bank loop
BANK_TERMINATE:
add_message("Bank Searching terminated. $reason",$sev);
%scan_request = ('_cmd' => 'control', 'rchan' => 'enable',
'att_amp' => 'enable',
);
tell_gui(1640);
$vfo{'index'} = 0;
if ($radio_def{'protocol'} =~ /uniden/i) {$vfo{'channel'} = '----';}
else {$vfo{'channel'} = $radio_def{'origin'};}
dply_vfo(1834);
if ($progstate eq $starting_progstate) {set_manual_state();}
return $GoodCode;
}## BANK State
sub load_state {
my $ch;
my $stepsave;
my $starting_progstate = $progstate;
my $reason = '';
my $sev = 0;
my $ch_count = 0;
my $end_count = 0;
if (defined $database{'freq'}[1]{'index'}) {
$ch_count = scalar @{$database{'freq'}};
}
$response_pending = "Loading In Progress";
LOADING_START:
add_message("Loading State Started...");
$stepsave = $vfo{"step"};
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
dply_vfo(1806);
radio_sync('init',1151);
if (!$radio_def{'active'}) {
$reason = "Due To Radio Failure";
$sev = 1;
goto LOADING_END;
}
if ($control{'clear'}) {
foreach my $dbndx (@dblist) {
clear_database($dbndx);
%scan_request = ('_cmd' => 'clear', '_dbn' => $dbndx);
tell_gui(2937);
{
lock(%gui_request);
%gui_request = ();
}
threads->yield;
}
}
if ($progstate ne $starting_progstate) {goto LOADING_END;}
scanner_sync();
if ($progstate ne $starting_progstate) {goto LOADING_END;}
radio_sync('getmem',1118);
if ($progstate ne $starting_progstate) {goto LOADING_END;}
radio_sync('getglob',1111);
LOADING_END:
$vfo{"step"} = $stepsave;
if ($radio_def{'protocol'} =~ /uniden/i) {$vfo{'channel'} = '----';}
else {$vfo{'channel'} = $radio_def{'origin'};}
$vfo{'service'} = '';
dply_vfo(1246);
if (defined $database{'freq'}[1]{'index'}) {
$end_count = scalar @{$database{'freq'}};
print "Set end count to $end_count\n";
}
my $new_recs = $end_count - $ch_count;
add_message("Load Ended $reason. $new_recs records added",$sev);
%scan_request = ('_cmd' => 'control');
foreach my $key ('start','start_value',
'stop','stop_value') {
$scan_request{$key} = 'enable';
}
$response_pending = '';
tell_gui(1468);
$radio_db_loaded = TRUE;
if ($progstate eq $starting_progstate) {set_manual_state();}
return $GoodCode;
}
sub vfo2mem_state {
$response_pending = "Setting Radio's Memory";    ### disable GUI while this processing
my $starting_progstate = $progstate;
add_message("VFO To Memory Started...");
if ($control{'useradio'}) {
if ($radio_def{'protocol'} eq 'uniden') {
}
else {
if (($vfo{'channel'} > $radio_def{'maxchan'}) or ($vfo{'channel'} < $radio_def{'origin'})) {
add_message("VFO to Memory ended. Channel is out of range of the radio!");
goto VFO2MEM_END;
}
}
if (!check_range($vfo{'frequency'},\%radio_def)) {
add_message("VFO to Memory ended. Frequency is out of range of the radio!");
goto VFO2MEM_END;
}
my %vfo_save = %vfo;
radio_sync('init',1285);
if (!$radio_def{'active'}) {
add_message("VFO to Memory ended due to radio failure",1);
goto VFO2MEM_END;
}
%vfo = %vfo_save;
radio_sync('vfo2mem',1290);
}
else {
my $maxrec = $#{$database{'freq'}};   
if ((!$vfo{'channel'}) or ($vfo{'channel'} > $maxrec)) {
my $maxchan = 0;
foreach my $rec (@{$database{'freq'}}) {
if (!$rec->{'index'}) {next;}
if ($rec->{'channel'} and ($rec->{'channel'} > $maxchan)) {$maxchan = $rec->{'channel'};}
}
$vfo{'channel'} = ++$maxchan;
print "Scanner4 l1298:Creating a new record\n";
my %newrec = ('frequency' => $vfo{'frequency'},
'mode' => $vfo{'mode'}, 'valid' => TRUE, 'channel' => $vfo{'channel'},
'sqtone' => $vfo{'sqtone'},
'service' => "",);
KeyVerify(\%newrec,@{$structure{'freq'}});
my $reqno = add_a_record(\%database,'freq',\%newrec,\&add_shadow);
$vfo{'index'} = $reqno;
}#### Add a new channel
else {
my $chan = $vfo{'channel'};
%scan_request = ('_cmd' => 'update', '_dbn' => 'freq','_seq' => $chan);
if ($vfo{'frequency'} ne $database{'freq'}[$chan]{'frequency'}) {
foreach my $key ('signal','count','duration') {
$database{'freq'}[$chan]{$key} = 0;
$scan_request{$key} = 0;
}
$database{'freq'}[$chan]{'timestamp'} = '';
$scan_request{'timestamp'} = '';
$database{'freq'}[$chan]{'valid'} = TRUE;
$scan_request{'valid'} = TRUE;
}
foreach my $key ('frequency','mode','channel','sqtone') {
$database{'freq'}[$chan]{$key} = $vfo{$key};
$scan_request{$key} = $vfo{$key};
}
tell_gui(1318);
}### update existing channel
}### use RadioCtl memory
VFO2MEM_END:
add_message("VFO 2 Memory Ended...");
if ($progstate eq $starting_progstate) {set_manual_state();}
return $GoodCode;
}
sub signal_check {
my $action = shift @_;
my $caller = shift @_;
my $retcode = $GoodCode;
my $recorder = '';
if (!defined $vfo{'channel'}) {LogIt(1773,"Signal Check l1773: VFO channel undefined. Caller->$caller");}
my $ontime  = 0;
my $offtime = 0;
my $duration = 0;
my $chkcount = 0;
my $resume = 0;
my $delay = 0;
my $db_duration = 0;
my $nolog = FALSE;
my $create = FALSE;
my $lastfreq = 0;
my $first_sig = TRUE;
my $entry_freq = $vfo{'frequency'};
my $entry_index = $vfo{'index'};
$vfo{'resume'} = 0;
$vfo{'delay'} = 0;
$vfo{'vrsm'} = FALSE;
$vfo{'vdly'} = FALSE;
my $sig_delay = 0;
my $sig_resume = 0;
if ($vfo{'_drok'}) {
if ($control{'dlyrsm'}) {
if ($control{'dlyrsm_value'} > 0) {
$sig_delay = $control{'dlyrsm_value'};
}
elsif ($control{'dlyrsm_value'} < 0) {
$sig_resume = abs($control{'dlyrsm_value'});
}
}
elsif ($control{'dbdlyrsm'} and $entry_index) {
my $value = $database{'freq'}[$entry_index]{'dlyrsm'};
if ($value and ($value > 0)) {
$sig_delay = $value;
}
elsif ($value and ($value < 0)) {
$sig_resume = abs($value);
}
}
}
my %loginfo = ();
my $dbndx = 'freq';
my $entry_ch = $vfo{'channel'};
my $entry_progstate = $progstate;
my $max_signal_count = 1;
my $max_time = 0;
my $speed_value = 0;
if ($allow_speed and $control{'speed_bar'}) {
$speed_value = $control{'speed_bar'};
my %speed_limit = (
'10' =>  40,
'9'  =>  60,
'8'   => 80,
'7'   =>100,
'6'   =>200,
'5'   =>250,
'4'   =>300,
'3'   =>350,
'2'   =>500,
'1'   =>800,
);
$max_time = $speed_limit{Strip($speed_value)};
if (!$max_time) {
$max_time = 1000;
}
}
my $debug_time = time();
my $index = $vfo{'index'};
my $starttime = Time::HiRes::time();
SIGLOOP:
while (TRUE) {
if (!$radio_def{'active'}) {
$retcode = $CommErr;
LogIt(1,"Radio is not active");
last SIGLOOP;
}
threads->yield;
$retcode = scanner_sync();
if ($retcode) {
last SIGLOOP;
}
if ($entry_progstate ne $progstate) {### new program state
$retcode = $StateChange;
last SIGLOOP;
}
radio_sync('getsig',2269);### get any signal value from the radio
radio_sync('getvfo',2270);### get Frequency and other values
$chkcount++;
if ($vfo{'signal'} and squelch_level(2143)) {
$retcode = $Squelched;
last SIGLOOP;
}
if ($vfo{'signal'}) {
radio_sync('getvfo',2270);### get Frequency and other values
if ($lastfreq and ($vfo{'frequency'} != $lastfreq)) {
$retcode = $FreqChange;
last SIGLOOP;
}
dply_vfo(1573);
$starttime = Time::HiRes::time();
$delay = 0;
$vfo{'delay'}  = 0;
$vfo{'vdly'} = FALSE;
$vfo{'chandply'} = '';
$offtime = 0;
if ($first_sig) {
if ($vfo{'service'} eq $initmessage) {$vfo{'service'} = '';}
$nolog = FALSE;
$lastfreq = $vfo{'frequency'};
if ($action =~ /find/i) {
$index = 0;
my $freq = $vfo{'frequency'};
if ($freq) {
$freq = $freq + 0;
if (defined $freq_xref{$freq}) {
my $tone = Strip($vfo{'sqtone'});
foreach my $ndx (sort Numerically keys %{$freq_xref{$freq}}) {
if ($database{'freq'}[$ndx]{'frequency'} != $freq) {
print $Bold,"SCANNER l2258:xref has $freq for record $ndx ",
"but record contains $database{'freq'}[$ndx]{'frequency'}$Eol";
next;
}
if ($database{'freq'}[$ndx]{'sqtone'} =~ /$tone/i) {
$index = $ndx;
last;
}
else {
}
}### For every $ndx
}### xref is defined for this frequency
}
else {
my $tgid = Strip($vfo{'tgid'});
if (defined $tgid_xref{$tgid}) {
my @list = keys %{$tgid_xref{$tgid}};
$index = shift @list;
}
}### TGID search
if ($index) {
if ($database{'freq'}[$index]{'valid'}) {
foreach my $key ('mode','channel','atten','preamp') {
$database{'freq'}[$index]{$key} = $vfo{$key};
}
}
else {$nolog = TRUE;}
}
else {$create = TRUE;}
}### action is 'find'
elsif ($action =~ /exist/i) {
}
elsif ($action =~ /use/i) {
if (!$index) {$create = TRUE;}
}
else {$index = 0;}
if ($create) {
my $sysno = 0;
my $groupno = $vfo{'groupno'};
if ($groupno) {
$sysno = $database{'group'}[$groupno]{'sysno'};
}
if (!$sysno) {
foreach my $rcd (@{$database{'system'}}) {
if ($rcd->{'index'}) {
$sysno = $rcd->{'index'};
last;
}
}
}
if (!$sysno) {
my %newrec = ('service' => 'Autolog System', 'systemtype' => 'cnv', 'valid' => TRUE);
$sysno = add_a_record(\%database,'system',\%newrec,\&add_shadow);
}
if (!$groupno) {
foreach my $rcd (@{$database{'group'}}) {
if ($rcd->{'index'}) {
$groupno = $rcd->{'index'};
last;
}
}
}
if (!$groupno) {
my %newrec = ('service' => 'Autolog Group', 'sysno' => $sysno, 'valid' => TRUE);
$groupno = add_a_record(\%database,'group',\%newrec,\&add_shadow);
}
my %newrec = ('valid' => TRUE,'sysno' => $sysno,
'groupno' => $groupno, 'timestamp' => time());
foreach my $key ('frequency','mode','tgid','sqtone',
'atten','signal','preamp') {
$newrec{$key} = $vfo{$key};
}
if ($progstate !~ /search/i) {$newrec{'channel'} = $vfo{'channel'};}
else {$newrec{'channel'} = '-';}
my $freq = $vfo{'frequency'};
if ($vfo{'service'} and ($vfo{'service'} ne $initmessage)) {$newrec{'service'} = $vfo{'service'};}
elsif ($freq and $known{$freq}) {$newrec{'service'} = $known{$freq};}
else  {$newrec{'service'} = 'Found '. Time_Format(time()) . '. Signal:' . $vfo{'signal'};}
$loginfo{'service'} = $newrec{'service'};
if (!looks_like_number($newrec{'channel'})) {
$newrec{'channel'} = '-';
}
KeyVerify(\%newrec,@{$structure{$dbndx}});
$index = add_a_record(\%database,$dbndx,\%newrec,\&add_shadow);
}#### New record called for
if ($index) {
if (!$nolog) {
$database{'freq'}[$index]{'count'}++;
$database{'freq'}[$index]{'timestamp'} = time();
$database{'freq'}[$index]{'signal'} = $vfo{'signal'};
}
$vfo{'index'} = $index;
if ($database{'freq'}[$index]{'service'}) {
$vfo{'service'} = $database{'freq'}[$index]{'service'};
}
if ($database{'freq'}[$index]{'tgid'}) {
$vfo{'tgid'} = $database{'freq'}[$index]{'tgid'};
}
foreach my $key ('signal','frequency','mode','service','rssi','dbmv','meter',
'sqtone','index','tgid','signal') {
$loginfo{$key} = $vfo{$key};
}
if ($progstate =~ /scan/i) {$loginfo{'channel'} = $vfo{'channel'};}
else {$loginfo{'channel'} = '-';}
$loginfo{'duration'} = 0;
$db_duration = $database{'freq'}[$index]{'duration'};
foreach my $key ('count','timestamp') {
$loginfo{$key} = $database{'freq'}[$index]{$key};
}
%scan_request = ('_cmd' => 'update', '_dbn' => 'freq', '_seq' => $index);
foreach my $key ('frequency','mode','atten','preamp','sqtone',,'channel',
'count','timestamp','signal','tgid') {
$scan_request{$key} = $database{'freq'}[$index]{$key};
}
tell_gui(2500);
}### Index is set
dply_vfo();
$first_sig = FALSE;
}### First signal process
if (!$ontime) {
$ontime = time();
$loginfo{'init_time'} = $ontime;
$vfo{'vrsm'} = FALSE;
$vfo{'resume'} = 0;
$resume = 0;
if ($control{'recorder'} and (!$recorder)and (!$nolog) and (
(!$index) or ($index and $database{'freq'}[$index]{'valid'}))) {
$start_recording = TRUE;
threads->yield;
}### Starting the recorder function
if ($sig_resume) {
$resume = $sig_resume;
$vfo{'resume'} = int($resume);
$vfo{'vrsm'} = TRUE;
}
else {
}
$ontime = time();
$offtime = 0;
}### Signal was off before
else {
if ($vfo{'vrsm'}) {
my $delta = int(time() - $ontime);
$vfo{'resume'} = $resume - $delta;
dply_vfo(1824);
if ($vfo{'resume'} < 1) {
$retcode = $Resume;
last SIGLOOP;
}
}
}### Resume checking
if ($index) {
if ($action =~ /exist/i) {
if (!$database{'freq'}[$index]{'valid'}) {
$retcode = $EmptyChan;
last SIGLOOP;
}
if ($control{'scansys'}) {
my $sysno = $database{'freq'}[$index]{'sysno'};
if ($sysno and (!$database{'system'}[$sysno]{'valid'})) {
$retcode = $EmptyChan;
last SIGLOOP;
}
}
if ($control{'scangroup'}) {
my $groupno = $database{'freq'}[$index]{'groupno'};
if ($groupno  and (!$database{'group'}[$groupno]{'valid'})) {
$retcode = $EmptyChan;
last SIGLOOP;
}
}
}
my $uptime = int((time() - $loginfo{'timestamp'}));
$loginfo{'duration'} = $uptime;
if (!$nolog) {
$database{'freq'}[$index]{'duration'} =
$db_duration + $uptime;
}
$chan_active{'freq'} = $index;
%scan_request = ('_cmd' => 'update', '_dbn' => 'freq', '_seq' => $index,
'index' => $index, 'duration' => $database{'freq'}[$index]{'duration'} );
tell_gui(1598);
}### Logging information
dply_vfo(1582);
}#### signal present
else {### signal is now off
$vfo{'resume'} = 0;
$vfo{'vrsm'} = FALSE;
if ($chan_active{'freq'} ) {
my $ndx = $chan_active{'freq'};
$chan_active{'freq'} = 0;
%scan_request = ('_cmd' => 'update', '_dbn' => 'freq','_seq' => $ndx );
tell_gui(1598);
}
$resume = 0;
if ($progstate ne $entry_progstate) {
print "Scanner l2636: Ending due to progstate change..\n";
$retcode = $StateChange;
last SIGLOOP;
}
if (!$offtime) {$offtime = time();}
if ($ontime) {
$duration = $duration + (time() - $ontime);
my $starttime = Time::HiRes::time();
if ($sig_delay) {
$delay = $sig_delay;
$vfo{'delay'} = $sig_delay;
$vfo{'vdly'} = TRUE;
}
else {
}
}### first off pass
my $now = Time::HiRes::time();
if ($vfo{'vdly'}) {### delay being done
my $delta = int($now - $offtime);
$vfo{'delay'} = $delay - $delta;
dply_vfo(1903);
usleep(4000);
if ($vfo{'delay'} < 1) {
$retcode = $Delay ;
last SIGLOOP;
}
else {next SIGLOOP;}
}
else {
my $elapsed = int(1000 * ($now - $offtime));
if ($speed_value) {
if ($elapsed < $max_time) {
usleep(1000);
next SIGLOOP;
}
}
}### no delay set
last SIGLOOP;
}### Signal is OFF
}### SIGLOOP
END_SIGNAL:
$start_recording = FALSE;
if ($retcode) {
}
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$vfo{'sql'} = FALSE;
$vfo{'vdly'} = FALSE;
$vfo{'delay'} = 0;
$vfo{'vrsm'} = FALSE;
$vfo{'resume'} = 0;
$vfo{'service'} = '';
$vfo{'tgid'} = '';
if ($chan_active{'freq'} > 0) {
my $ndx = $chan_active{'freq'};
$chan_active{'freq'} = 0;
%scan_request = ('_cmd' => 'update', '_dbn' => 'freq','_seq' => $ndx );
tell_gui(1598);
}
dply_vfo(2727);
if ($loginfo{'signal'} and (!$nolog)) {### something happened
my $msg = Time_Format($loginfo{'init_time'}) . ' ' .
rc_to_freq($loginfo{'frequency'}) . 'MHz ' .
$loginfo{'mode'} . ' ' .
"signal:$loginfo{'signal'} " .
"rssi:$loginfo{'rssi'} " .
"dbmv:$loginfo{'dbmv'} " .
"meter:$loginfo{'meter'} " .
"duration:" . $loginfo{'duration'} . " secs " .
$loginfo{'service'};
if ($loginfo{'tgid'}) {$msg = "$msg tgid=>$loginfo{'tgid'}";}
LogIt(0,"$Green$msg");
if (write_log(\%loginfo)) {
%scan_request = ('_cmd' => 'logoff');
tell_gui(2416);
}
}### Logging information
%loginfo = ();
%scan_request = ();
return $retcode;
}
sub open_serial {
%scan_request = ('_cmd' => 'radio','connect' => 'connecting');
tell_gui(1981);
if ($portobj) {$portobj -> close;}
$radio_def{'active'} = FALSE;
$radio_def{'rsp'} = 0;
$radio_def{'unresponsive'} = FALSE;
if (!$radio_def{'port'}) {
print Dumper(%radio_def);
LogIt(2173,"OPEN_SERIAL:No value for radio port!");
}
my $port = $radio_def{'port'};
if ($port ne '(none)') {
$portobj = Device::SerialPort->new($port) ;
if (!$portobj) {
LogIt(1,"OPEN_SERIAL:Cannot connect to port $port");
add_message("cannot connect to $port",1);
return FALSE;
}
else {
$portobj->user_msg("ON");
$portobj->databits(8);
$portobj->baudrate($radio_def{'baudrate'});
$portobj->parity($radio_def{'parity'});
$portobj->stopbits($radio_def{'stopbits'});
$portobj->read_const_time(100);
$portobj->read_char_time(0);
$portobj->write_settings || undef $portobj;
}
}
else {
if ($radio_def{'protocol'} ne 'local') {
LogIt(1,"OPEN_SERIAL:Port of $port is not valid for this protocol");
add_message("Port $port is not valid for this protocol",1);
return FALSE;
}
}
$radio_def{'active'} = TRUE;
return TRUE;
}
sub radio_sync {
my $cmd = shift @_;
my $caller = shift @_;
if (!$radio_def{'active'} and ($cmd ne 'autobaud')) {
return $GoodCode;
}
if (!defined $vfo{'channel'}) {
print Dumper(%vfo),"\n";
LogIt(2270,"RADIO_SYNC:VFO channel not set! Caller=$caller");
}
my $tries = 2;
my $protocol = '';
while ($tries) {
$protocol = $radio_def{'protocol'};
if (!$protocol) {
LogIt(1,"RADIO_SYNC l2373:Got undefined protocol. Retry after wait");
threads->yield;
sleep 1;
$tries--;
}
else {last;}
}
if (!$protocol) {
LogIt(1,"RADIO_SYNC l2382:Undefined protocol. Terminating RADIO_SYNC");
return $ParmErr;
}
delete $vfo{'_rdy'};
my %out = ('_delay' => 0);
my %in  = ();
my $ch = $vfo{'channel'};
my $freq = $vfo{'frequency'};
my  %radio_parms = (
'out'      => \%out,
'in'       => \%in,
'sysno'    => $sysno,
'portobj'  => $portobj,
'msg'      => \&add_message,
'def'      => \%radio_def,
'rc'       => $GoodCode,
'progstate' => $progstate,
'database' => \%database,
'gui'      => \&add_shadow,
'cmd'      => $cmd,
'term'     => FALSE,
'unsolicited' => \@unsolicited,
'delay' => $usleep{'SIGNAL'},
);
if ($cmd eq 'setvfo') {
$in{'mode'} = $vfo{'mode'};
if (!$freq) {
if ($radio_def{'minfreq'}) {
LogIt(1,"RADIOSYNC l2184:Frequency is 0! Caller=$caller. Set to minfreq");
if (!$radio_def{'minfreq'}) {
print Dumper(%radio_def),"\n";
LogIt(2245,"Missing Minfreq");
}
$freq = $radio_def{'minfreq'};
}
else {
LogIt(1,"RADIOSYNC l 2188:No 'minfreq' defined in radio_def!");
$freq = 30000000;
}
}
$in{'frequency'} = $freq;
foreach my $key ('sqtone','atten','preamp','adtype') {
$in{$key} = $vfo{$key};
}
}
elsif (($cmd eq 'getvfo') or ($cmd eq 'selvfo')){
$out{'sqtone'} = 'Off';
$out{'atten'} = FALSE;
$out{'preamp'} = FALSE;
$out{'tgid'} = '';
$out{'frequency'} = 0;
$out{'mode'} = 'FMn';
$out{'adtype'} = 'AN';
}
elsif ($cmd eq 'selmem')  {
$in{'channel'} = $ch;
$in{'sysno'} = $sysno;
}
elsif ($cmd eq 'setmem')  {
if ($radio_def{'protocol'} eq 'uniden') {
}### dynamic process
else {
$sysno = 0;
if (scalar @{$database{'system'}} > 2) {### more than one system defined
}
my @sysnos = ();
$in{'sysno'} = 0;
if ($sysno) {
@sysnos = ($sysno);
$in{'sysno'} = \@sysnos;
}
$radio_parms{'sysno'} = $sysno;
foreach my $opt ('clear','skip','keep') {
if ($control{$opt}) {$in{$opt} = TRUE;}
else {$in{$opt} = FALSE;}
}
}### Non-Dynamic Radio process
}
elsif ($cmd eq 'vfo2mem') {
my %localdb = ();
my $seq  = add_a_record(\%localdb,'freq',\%vfo);
$sysno = $vfo{'sysno'};
$radio_parms{'sysno'} = $sysno;
$radio_parms{'database'} = \%localdb;
$in{'firstnum'} = $vfo{'channel'};
$in{'count'} = 1;
$radio_parms{'cmd'} = 'setmem';
}
elsif ($cmd eq 'getmem') {
my %options = (
'notrunk'   => TRUE,
'firstchan' => $control{'firstchan'},
'lastchan'  => $control{'lastchan'},
'noskip'    => $control{'noskip'},
'nodup'     => $control{'nodup'}
);
$radio_parms{'options'} = \%options;
}### getmem pre-process
elsif ($cmd eq 'getsig') {
$out{'signal'} = 0;
$out{'rssi'} = 0;
$out{'meter'} = 0;
$out{'dbmv'} = -999;
foreach my $key ('frequency','mode') {$out{$key} = $vfo{$key};}
}
elsif (($cmd eq 'optionset') or ($cmd eq 'setglob')) {
$cmd = 'setglob';
return $NotForModel;
}
elsif ($cmd eq 'getglob') {
}
elsif ($cmd eq 'init') {
}
elsif ($cmd eq 'scan') {
if (!$radio_def{'radioscan'}) {
add_message('Radio Does Not support radio scan mode!',1);
return $NotForModel;
}
}
elsif ($cmd eq 'manual') {
}
elsif ($cmd eq 'vfoinit'){
$radio_parms{'cmd'} = $cmd;
}
elsif ($cmd eq 'meminit'){
$radio_parms{'cmd'} = $cmd;
}
elsif ($cmd eq 'autobaud') {
$radio_parms{'cmd'} = $cmd;
}
else {
add_message("Warning! No Pre-Process defined for radio_sync cmd=$cmd",1);
LogIt(1,"RADIO_SYNC:No Pre-Process defined for cmd=$cmd");
return $NotForModel;
}
if (!defined $protocol) {
LogIt(2708,"RADIO_SYNC:Undefined protocol in Radio_Def");
}
$radio_parms{'portobj'} = $portobj;
my $routine = $radio_routine{$protocol};
my $rc = $GoodCode;
if ($routine) {$rc = &$routine($radio_parms{'cmd'},\%radio_parms);}
else {LogIt(2752,"RADIO_SYNC:Radio routine not set for protocol $protocol");}
if ($cmd eq 'autobaud') {return $rc;}
if ($radio_def{'rsp'}) {
if ($radio_def{'rsp'} > 10) {
my $msg = "Could not connect to radio. May be powered off or disconnected";
add_message($msg,1);
LogIt(1,"RADIO_SYNC:$msg");
if ($portobj) {$portobj->close;}
$portobj = '';
$radio_def{'active'} = FALSE;
my %req = ('_cmd' => 'radio','connect' => 'disconnected');
wait_for_command(\%req,2693);
set_manual_state();
}### Too many errors
else {
$radio_def{'unresponsive'} = TRUE;
my %req = ('_cmd' => 'radio','connect' => 'unresponsive');
wait_for_command(\%req,1774);
}
return $CommErr;
}
if ($radio_def{'unresponsive'}) {
my %req = ('_cmd' => 'radio','connect' => 'connected');
wait_for_command(\%req,1781);
$radio_def{'unresponsive'} = FALSE;
}
my $dly = $out{'_delay'};
if ($dly) {
my $start_time = Time::HiRes::time;
while ($dly > 0) {
threads->yield;
usleep(500);
$dly = $dly - ((Time::HiRes::time - $start_time) * 1000);
}
}
if ($cmd eq 'init') {
if ($radio_parms{'rc'}) {
my $msg = "Could not connect to radio. May be powered off";
if ($radio_parms{'rc'} == 2) {
$msg = "Could not connect to radio. May be bad model spec ($radio_def{'model'})";
}
add_message($msg,1);
LogIt(1,"RADIO_SYNC:$msg");
if ($portobj) {$portobj->close;}
$portobj = '';
$radio_def{'active'} = FALSE;
my %req = ('_cmd' => 'radio','connect' => 'disconnected');
wait_for_command(\%req,2693);
set_manual_state();
return $CommErr;
}### got an error
else {
my $starttime = Time::HiRes::time();
radio_sync('getsig');
my $stoptime = Time::HiRes::time();
if ($out{'sqtone'}) {$vfo{'sqtone'} = $out{'sqtone'};}
equate(\%out,\%vfo);
$vfo{'_sigtime'} = $stoptime-$starttime;
delete $vfo{'_rdy'};
dply_vfo(2344);
%scan_request = ('_cmd' => 'radio','connect' => 'connected');
tell_gui(2416);
LogIt(0,"Radio Init Connected to $radio_def{'name'}");
LogIt(0,"Radio's maximum channel number=>$radio_def{'maxchan'}");
}## Connection is OK
}#### Init
elsif ($cmd eq 'getsig') {
if (!$radio_parms{'rc'}) {
if (!defined $out{'signal'}) {
print Dumper(%out),"\n";
LogIt(2381,"Undefined 'signal' for $cmd");
}
$vfo{'signal'} = $out{'signal'};
$vfo{'tgid'} = '';
if ($vfo{'signal'}) {
foreach my $key ('sql','frequency','mode','channel','service','tgid','atten',
'rssi','dbmv','meter') {
if (defined $out{$key}) {$vfo{$key} = $out{$key};}
}
if (!$vfo{'mode'}) {
print Dumper(%out),"\n";
LogIt(1,"SCANNER l2984:No 'mode' in out");
$vfo{'mode'} = 'FMn';
}
}
}### no error
else {LogIt(1,"SCANNER l2879:GETSIG returned $radio_parms{'rc'} signal=$out{'signal'}");}
}### getsig post process
elsif ($cmd eq 'selmem') {
if (FALSE) {
my $start_time = Time::HiRes::time;
my $cnt = 0;
while ($cnt < 1000) {
icom_cmd('_get_tone_squelch',\%radio_parms);
if ($out{'sql'}) {last;}
$cnt++;
usleep 1000;
}
my $extra = ((Time::HiRes::time - $start_time) * 1000);
print "Scanner l3878. Extra time need=>$extra count=>$cnt\n";
}
}
elsif ($cmd eq 'getmem') {update_xref();}
elsif ($cmd eq 'setmem') {
}
elsif ($cmd eq 'vfo2mem') {
}
elsif ($cmd eq 'getvfo')  {
if (!$radio_parms{'rc'}) {
foreach my $key ('frequency','mode','service','atten','preamp','tgid',
'signal','sqtone','adtype') {
if (defined $out{$key}) { $vfo{$key} = $out{$key};}
}
if ($vfo{'signal'}){
if (defined $out{'channel'}) {$vfo{'channel'} = $out{'channel'};}
}
}
}### VFO Getting
elsif ($cmd eq 'setvfo') {
}
elsif ($cmd eq 'getglob') {
}
elsif ($cmd eq 'vfoinit') {
}
elsif ($cmd eq 'meminit') {
$vfo{'frequency'} = $out{'frequency'};
if ($vfo{'frequency'}) {
$vfo{'mode'} = $out{'mode'};
if ($out{'sqtone'}) {$vfo{'sqtone'} = $out{'sqtone'};}
}
foreach my $key ('service') {
if ($out{$key}) {$vfo{$key} = $out{$key};}
}
}
elsif ($cmd eq 'manual') {
}
elsif ($cmd eq 'scan') {
}
else {
LogIt(1,"RADIO_SYNC l4136:No Post-Process defined for radio_sync cmd=$cmd");
}
if ($radio_parms{'rc'}) {
LogIt(1,"RADIO_SYNC:Radio routine $cmd returned a bad code rc=$rc");
}
return ($radio_parms{'rc'});
}
sub scanner_sync {
threads->yield;
my $statechange = FALSE;
my $sigkill = FALSE;
REQ_PROC:
while (defined  $gui_request{'_rdy'}) {
my $command = $gui_request{'_cmd'};
my $time_stamp = $gui_request{'_timestamp'};
if (!$time_stamp) {$time_stamp = 0;}
my $retcode = $GoodCode;
my $errmsg = '';
if ($last_timestamp == $time_stamp) {
print Dumper(%gui_request),"\n";
LogIt(1,"SCANNER Line 4316:Current GUI_REQUEST was previously processed" .
" but NOT cleared!");
clear_gui_request();
return 0;
}
else {
$last_timestamp = $time_stamp;
}
if (!$command) {
print Dumper(%gui_request),"\n";
LogIt(2889,"SCANNER_SYNC: Got a gui_request without a command!");
}
my %req = ();
{
lock %gui_request;
foreach my $key (keys %gui_request) {$req{$key} = $gui_request{$key};}
$gui_request{'_in_process'} = TRUE;
}
if ($command eq 'term') {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$progstate = 'quit';
$statechange = TRUE;
clear_gui_request();
return $StateChange;
}
elsif ($command eq 'clear') {
$response_pending = "Database Clear in Progress";
my $dbndx = $req{'_dbn'};
if (!$dbndx) {LogIt(4423,"SCANNER_SYNC: No _DBN key in CLEAR request");}
$radio_db_loaded = FALSE;
set_manual_state();
$statechange = TRUE;
clear_database($dbndx);
%scan_request = ('_cmd' => 'clear', '_dbn' => $dbndx);
tell_gui(2937);
$response_pending = '';
clear_gui_request();
return $StateChange;
}
elsif ($command eq 'sort') {
$response_pending = "_Sort In Progress.\n Please wait...";
my $type = $req{'type'};
my $field = 'frequency';
if ($type eq 'sortc') {$field = 'channel';}
set_manual_state();
$statechange = TRUE;
$database{'freq'}[0]{'index'} = 0;
$database{'freq'}[0]{'frequency'} = 0;
my @sorted =  sort
{
if ($a->{'index'} and $b->{'index'}) {
$a->{$field} <=> $b->{$field};
}
}
@{$database{'freq'}};
clear_database('freq');
%freq_xref = ();
%scan_request = ('_cmd' => 'clear', '_dbn' => 'freq');
tell_gui(2937);
foreach my $rec (@sorted) {
if ($rec->{'index'}) {
my $recno = add_a_record(\%database,'freq',$rec,\&add_shadow);
}
}
$response_pending = '';
clear_gui_request();
return $StateChange;
}
elsif ($command eq 'statechange') {
my $new_state = $req{'state'};
if (!defined $new_state) {
print Dumper(%req),"\n";
LogIt(4509,"SCANNER_SYNC: No progstate for state change!");
}
clear_gui_request();
if ($new_state eq $progstate) {
next REQ_PROC;
}
$progstate = $new_state;
$statechange = TRUE;
return $StateChange;
}
elsif ($command eq 'newradio') {
$response_pending = 'Connecting to Radio...';
if ($portobj) {$portobj -> close;}
%radio_def = ();
foreach my $key (keys %req) {
if ($key =~ /_/i) {next;}  
$radio_def{$key} = $req{$key};
}
my $radiosel = lc($radio_def{'name'});
if (!$radiosel) {LogIt(4608,"No name on 'CONNECT' request!");}
my $protocol = $radio_def{'protocol'};
if (!$protocol) {
print "RadioDef=>",Dumper(%radio_def),"\n";
print "request=>",Dumper(%req),"\n";
LogIt(4616,"Missing 'protocol' definition for Radio_Def!");
}
$radio_def{'active'} = FALSE;
$radio_def{'origin'} = 1;
$radio_def{'parity'} = 'none';
$radio_def{'stopbits'} = 1;
my $status = 'disconnected';
%scan_request = ('_cmd' => 'radio', 'connect' => $status);
tell_gui(4637);
set_manual_state();
$statechange = TRUE;
%scan_request =  ('_cmd' => 'control');
if (!$radio_def{'protocol'}) {
print "RadioDef=>",Dumper(%radio_def),"\n";
print "request=>",Dumper(%req),"\n";
LogIt(4633,"Missing 'protocol' definition for Radio_Def!");
}
if ($radio_def{'protocol'} =~ /uniden/i) {
$scan_request{'rchan'} = 'disable';
$vfo{'channel'} = '----';
}
else {
$scan_request{'rchan'} = 'enable';
$vfo{'channel'} = $radio_def{'origin'};
}
tell_gui(4661);
if ($radio_def{'protocol'} eq 'local') {
$radio_def{'active'} = TRUE;
$status = 'connected';
%scan_request = ('_cmd' => 'control',
'baud' => 'disable', 'port' => 'disable', 'autobaud' => 'disable');
tell_gui(3305);
}### Local radio
else {
%scan_request = ('_cmd' => 'control',
'autobaud' => 'enable');
tell_gui(4638);
if ($control{'autobaud'}) {
my $state_save = $progstate;
$progstate = 'autobaud';
my $rc = radio_sync('autobaud',4614);
$progstate = $state_save;
if ($rc) {
my $msg = "SCANNER l4652:Could not determine port and/or baud rate. Radio may be powered off";
add_message($msg,1);
$radio_def{'active'} = FALSE;
%scan_request = ('_cmd' => 'radio','connect' => 'disconnected');
print "SCANNER l4658: AUTOBAUD fail=>",Dumper(%scan_request),"\n";
tell_gui(4653);
clear_gui_request();
$progstate = 'manual';
$response_pending = ''   ;
return  $StateChange;
}### Failed AUTOBAUD
}### Autobaud
else {
%scan_request = ('_cmd' => 'control',
'baud' => 'enable', 'port' => 'enable',
'autobaud' => 'enable');
tell_gui(4665);
}
my $rc = open_serial();
}### Not a local radio
if ($radio_def{'active'}) {
$status = 'connected';
radio_sync('init',3126);
$vfo{'_last_radio_name'} = $radiosel;
}
%scan_request = ('_cmd' => 'radio', 'connect' => $status);
tell_gui(3875);
$response_pending = '';
clear_gui_request();
}
elsif ($command eq 'connect')  {
$response_pending = 'Connecting to Radio...';
if ($portobj) {$portobj -> close;}
$radio_def{'active'} = FALSE;
if ($req{'baudrate'}) {$radio_def{'baudrate'} = $req{'baud'};}
if ($req{'port'}) {$radio_def{'port'} = $req{'port'};}
my $status = 'disconnected';
%scan_request = ('_cmd' => 'radio', 'connect' => $status);
tell_gui(4758);
set_manual_state();
$statechange = TRUE;
if ($radio_def{'protocol'} eq 'local') {
$radio_def{'active'} = TRUE;
$status = 'connected';
%scan_request = ('_cmd' => 'control',
'baud' => 'disable', 'port' => 'disable', 'autobaud' => 'disable');
tell_gui(3305);
}
else {
%scan_request = ('_cmd' => 'control',
'autobaud' => 'enable');
tell_gui(4638);
if ($control{'autobaud'}) {
my $state_save = $progstate;
$progstate = 'autobaud';
my $rc = radio_sync('autobaud',4614);
$progstate = $state_save;
if ($rc) {
my $msg = "SCANNER l4652:Could not determine port and/or baud rate. Radio may be powered off";
add_message($msg,1);
$radio_def{'active'} = FALSE;
%scan_request = ('_cmd' => 'radio','connect' => 'disconnected');
print "SCANNER l4658: AUTOBAUD fail=>",Dumper(%scan_request),"\n";
tell_gui(4653);
clear_gui_request();
$progstate = 'manual';
$response_pending = ''   ;
return  $StateChange;
}### Failed AUTOBAUD
}
else {
%scan_request = ('_cmd' => 'control',
'baud' => 'enable', 'port' => 'enable',
'autobaud' => 'enable');
tell_gui(4665);
}
my $rc = open_serial();
}
if ($radio_def{'active'}) {
$status = 'connected';
radio_sync('init',3126);
}
%scan_request = ('_cmd' => 'radio', 'connect' => $status);
tell_gui(3875);
$response_pending = '';
clear_gui_request();
return $StateChange;
}
elsif ($command eq 'disconnect')  {
if ($portobj) {$portobj -> close;}
$radio_def{'active'} = FALSE;
my $status = 'disconnected';
%scan_request = ('_cmd' => 'radio', 'connect' => $status);
tell_gui(4758);
set_manual_state();
$statechange = TRUE;
clear_gui_request();
return $StateChange;
}
elsif ($command eq 'vfoctl') {
$response_pending = '';
my $return = $GoodCode;
if ($statechange) {
clear_gui_request();
next REQ_PROC;
}
my $ctl = $req{'_ctl'};
my $value = $req{'_value'};
if (!defined $value) {$value = '';}
if (!$ctl) {
print Dumper(%req),"\n";
LogIt(4754,"SCANNER l4947: No '_ctl' for control command!");
}
if ($progstate eq 'manual') {
my %vfo_save = ();
foreach my $key ('frequency','mode','index','channel',
'sqtone','atten','preamp','adtype') {
$vfo_save{$key} = $vfo{$key};
}
if ($ctl eq 'signal') {
if ($radio_def{'protocol'} eq 'local') {
$local_vfo{'signal'} = $value;
$vfo{'signal'} = $value;
}
}
elsif ($ctl eq 'vchan') {
if ($database{'freq'}[$value]{'index'}) {
my $rc = mem2vfo($database{'freq'}[$value]{'index'});
if ($rc) {
my $code = $rc;
if ($rc == $CommErr) {
$code = "Disconnected";
$return = $CommErr;
}
add_message("Setting of database record $value  radio failed. Code=>$code",1);
foreach my $key (keys %vfo_save) {$vfo{$key} = $vfo_save{$key};}
}
}
else {
add_message("$value is not a valid RadioCtl record",1);
}
}### VCHAN
elsif ($ctl eq 'rchan')  {
if ($value > 9999) {
print Dumper(%req),"\n";
LogIt(4844,"rchan request larger than 9999!");
}
$vfo{'channel'} = $value;
my $rc = radio_sync('selmem',4850);
if ($rc) {
my $code = $rc;
if ($rc == $CommErr) {
$code = "Disconnected";
$return = $CommErr;
}
add_message("Could not change Radio's channel to $value. Code=>$code",1);
foreach my $key (keys %vfo_save) {$vfo{$key} = $vfo_save{$key};}
}
}### Radio's Channel
else {
if ($ctl =~ /att/i) {set_att_amp($value);}
elsif ($ctl =~ /freq/i) {$vfo{'frequency'} = $value;}
else {$vfo{$ctl} = $value;}
my $rc = radio_sync('setvfo',5063);
if (!$rc) {$rc = radio_sync('getvfo',5064);}
if ($rc) {
my $code = $rc;
if ($rc == $CommErr) {
$code = "Disconnected";
$return = $CommErr;
}
add_message("Setting of $vfo{$ctl} to radio failed. Code=>$code",1);
foreach my $key (keys %vfo_save) {$vfo{$key} = $vfo_save{$key};}
}
}### Changing a VFO control
}### Manual state control process
elsif ($progstate eq 'frequency_scan')  {
if ($ctl =~ /signal/i) {
if ($radio_def{'protocol'} eq 'local') {
$local_vfo{'signal'} = $value;
$vfo{'signal'} = $value;
}
else {
if ($vfo{'signal'} and (!$value)) {
$vfo{'signal'} = 0;
$return = $SigKill;
}
}
}
elsif ($vfo{'signal'}) {
my $change = FALSE;
if ($ctl =~ /mode/i) {
$vfo{'mode'} = $value;
$change = TRUE;
}
elsif ($ctl =~ /att/i) {
set_att_amp();
$change = TRUE;
}
elsif ($ctl =~ /adtype/i) {
$vfo{'adtype'} = $value;
$change = TRUE;
}
if ($change) {
my $rc = radio_sync('setvfo',4588);
if (!$rc) {$rc = radio_sync('getvfo',4589);}
if ($rc) {
my $code = $rc;
if ($rc == $CommErr) {
$code = "Disconnected";
$return = $CommErr;
}
add_message("Setting $ctl=$value to radio failed. Code=>$code",1);
}
}
else {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$return = $SigKill;
}
}### signal present in frequency scan
else {
}
}### frequency scan state
elsif ($progstate eq 'channel_scan') {
if ($ctl =~ /signal/i) {
if ($radio_def{'protocol'} eq 'local') {
$local_vfo{'signal'} = $value;
$vfo{'signal'} = $value;
}
else {
if ($vfo{'signal'} and (!$value)) {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$return = $SigKill;
}
}
}### 'signal' process
elsif ($ctl =~ /chan/i) {
if ($vfo{'signal'}) {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$return = $SigKill;
}
}
}### Channel scan process
elsif ($progstate eq 'search') {
my $return = $GoodCode;
my $change = FALSE;
if ($ctl =~ /signal/i) {
if ($radio_def{'protocol'} eq 'local') {
$local_vfo{'signal'} = $value;
$vfo{'signal'} = $value;
}
else {
if ($vfo{'signal'} and (!$value)) {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$return = $SigKill;
}
}
}#### Signal process
elsif ($ctl =~ /mode/i) {
$vfo{'mode'} = $value;
$change = TRUE;
}
elsif ($ctl =~ /sqtone/i) {
$vfo{'sqtone'} = $value;
$change = TRUE;
}
elsif ($ctl =~ /adtype/i) {
$vfo{'adtype'} = $value;
$change = TRUE;
}
elsif ($ctl =~ /att/i) {
set_att_amp();
$change = TRUE;
}
elsif ($ctl =~ /freq/i) {
$vfo{'frequency'} = $value;
$return = $SigKill;
}
else {
}
if ($change) {
my $rc = radio_sync('setvfo',5137);
if (!$rc) {$rc = radio_sync('getvfo',5138);}
if ($rc) {
my $code = $rc;
if ($rc == $CommErr) {
$code = "Disconnected";
$return = $CommErr;
}
add_message("Setting $ctl=$value to radio failed. Code=>$code",1);
}
}### Allowed VFO control was changed
}### Search
elsif ($progstate eq 'bank_search') {
if ($ctl =~ /signal/i) {
if ($radio_def{'protocol'} eq 'local') {
$local_vfo{'signal'} = $value;
$vfo{'signal'} = $value;
}
else {
if ($vfo{'signal'} and (!$value)) {
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
$return = $SigKill;
}
}
}#### Signal process
elsif ($ctl =~ /freq/i) {
$vfo{'frequency'} = $value;
$return = $SigKill;
}
else {
}
}
elsif ($progstate =~  'radio') {
}
else  {
LogIt(1,"Scanner 5147: No SCANNER_SYNC process for state:$progstate");
}
clear_gui_request();
return $return;
}##### Control process
elsif ($command eq 'open') {
$response_pending = "Loading File..";
set_manual_state();
$statechange = TRUE;
$progstate = 'open';
my $filespec = $req{'filespec'};
my $replace = $req{'replace'};
if ($replace) {$radio_db_loaded = FALSE;}
if (!$filespec) {LogIt(5244,"SCANNER_SYNC:Missing 'filespec' in GUI request");}
clear_gui_request();
if (!-f $filespec) {
add_message("Cannot locate file $filespec",1);
$progstate = 'manual';
$response_pending = '';
return $FileErr;
}
if ($replace) {
}
my $chsave = $vfo{'channel'};
my %dummy = ();
my $rc = read_radioctl(\%dummy,$filespec);
if ($rc) {
add_message("Error $rc reading $filespec",1);
$progstate = 'manual';
$response_pending = '';
return $FileErr;
}
threads->yield;
if ($progstate ne 'open') {
$response_pending = '';
add_message("read of $filespec was interrupted by user",1);
return $StateChange;
}
my %sysxref = ();
foreach my $rec (@{$dummy{'system'}})  {
my $oldndx = $rec->{'index'};
if (!$oldndx) {next;}
my $index = add_a_record(\%database,'system',$rec,\&add_shadow);
$sysxref{$oldndx} = $index;
}
threads->yield;
if ($progstate ne 'open') {
$response_pending = '';
add_message("read of $filespec was interrupted by user",1);
return $StateChange;
}
my %groupxref = ();
foreach my $rec (@{$dummy{'group'}})  {
my $oldndx = $rec->{'index'};
if (!$oldndx) {next;}
my $oldsysno = $rec->{'sysno'};
if (!$oldsysno) {
LogIt(1,"SCANNER l5332:No 'SYSNO' in record $oldndx");
}
if ($sysxref{$oldsysno}) {$rec->{'sysno'} = $sysxref{$oldsysno};}
else {
LogIt(1,"SCANNER l5328:No system xref for $oldsysno in new record $oldndx");
print Dumper(%sysxref),"\n";
}
my $index = add_a_record(\%database,'group',$rec,\&add_shadow);
$groupxref{$oldndx} = $index;
threads->yield;
if ($progstate ne 'open') {
$response_pending = '';
add_message("read of $filespec was interrupted by user",1);
return $StateChange;
}
}
foreach my $rec (@{$dummy{'freq'}})  {
threads->yield;
if ($progstate ne 'open') {
$response_pending = '';
add_message("read of $filespec was interrupted by user",1);
return $StateChange;
}
my $oldndx = $rec->{'index'};
if (!$oldndx) {next;}
my $oldgroupno = $rec->{'groupno'};
if ($groupxref{$oldgroupno}) {$rec->{'groupno'} = $groupxref{$oldgroupno};}
if ($rec->{'tgid_valid'}) {next;}
if (!$rec->{'frequency'}) {next;}
if ($rec->{'channel'} =~ /\-/) {next;}  
my $sql = $rec->{'sqtone'};
if (($sql =~ /nac/i) or ($sql =~ /ccd/i) or ($sql =~ /rpt/i)
or ($sql =~ /ran/i) or ($sql =~ /dsq/i)) {
$rec->{'sqtone'} = 'Off';
}
my $index = add_a_record(\%database,'freq',$rec,\&add_shadow);
if (!$oldgroupno) {
add_message("No Group assigned to record $index ",1);
}
}
foreach my $rec  (@{$dummy{'search'}}){
threads->yield;
if ($progstate ne 'open') {
$response_pending = '';
add_message("read of $filespec was interrupted by user",1);
return $StateChange;
}
if (!$rec->{'index'}) {next;}
if (!$rec->{'step'}) {next;}
if (!$rec->{'start_freq'}) {next;}
if (!$rec->{'stop_freq'}) {next;}
my $index = add_a_record(\%database,'search',$rec,\&add_shadow);
}
foreach my $rec (@{$dummy{'lookup'}}){
my $freq = Strip($rec->{'frequency'});
my $service = Strip($rec->{'service'});
if ($freq and looks_like_number($freq) and $service ) {
$freq = $freq + 0;
my %newrec = ('frequency' => $freq,
'service' => $service
);
add_a_record(\%database,'lookup',\%newrec,\&add_shadow);
$known{$freq} = $service;
}
else {
}
}
update_xref();
LogIt(0,"SCANNER:file read process complete...");
set_manual_state();
$statechange = TRUE;
$vfo{'channel'} = $chsave;
dply_vfo(3416);
$response_pending = '';
}### Open command
elsif ($command eq 'save') {
$response_pending = 'Saving data to file...';
my $filespec = $req{'filespec'};
if (!$filespec) {LogIt(5453,"SCANNER_SYNC:Missing 'filespec' in GUI request");}
clear_gui_request();
my @parms = ('ex_system','ex_group','ex_freq','ex_search','ex_lookup');
push @parms,'sort';
push @parms,'mhz';
my $rc = write_radioctl(\%database,$filespec,@parms);
my $retcode = $GoodCode;
$response_pending  = '';
if ($rc) {
pop_up("Error $rc writing $filespec");
add_message("Error $rc writing $filespec",1);
$retcode = $FileErr;
}
else {
add_message("$filespec was successfully written",0);
}
return $retcode;
}### Save process
elsif ($command eq 'sync') {
my $retcode = $GoodCode;
my $db_no = $req{'_dbn'};
my $seq =  $req{'_seq'};
if (!defined $db_no) {
print Dumper(%req),"\n";
LogIt(5527,"SCANNER_SYNC:No DB_NO in gui_request!");
}
if ($db_no eq 'vfo') {
print Dumper(%req),"\n";
LogIt(5533,"SCANNER_SYNC l5533:Called sync for VFO. Eliminate this call!");
}
if (!defined $seq) {
print Dumper(%req),"\n";
LogIt(5546,"GUI_REQ:No record number in request!");
}
my $index = $vfo{'index'};
my %shadowed = ();
my %change = ('_dbn' => $db_no, '_seq' => $seq, '_caller' => 'sync');
if ($db_no =~ /lookup/i) {
my $freq = $database{'lookup'}[$seq]{'frequency'};
if ($freq) {delete $known{$freq + 0};}
}
my %old = ();
my %new = ();
foreach my $datakey (keys %req) {
if ($datakey =~ /^\_.*$/) {next;}  
my $value = $req{$datakey};
if ($value) {
foreach my $toggle (keys %mutual_exclusive) {
my $exclude = $mutual_exclusive{$toggle};
if (($datakey eq $toggle) and $database{$db_no}[$seq]{$exclude}) {
$database{$db_no}[$seq]{$exclude} = FALSE;
$change{$exclude} = FALSE;
}
}
}### turning on something
if ($datakey eq 'valid') {
if ($vfo{'signal'} and $sig_kill_states{$progstate}) {
if ($db_no eq 'system') {
if ($database{'freq'}[$index]{'sysno'} == $seq) {
if ($control{'scansys'}) {$retcode = $SigKill;}
}
}
elsif ($db_no eq 'group') {
if ($database{'freq'}[$index]{'groupno'} == $seq) {
if ($control{'scangroup'}) {$retcode = $SigKill;}
}
}
elsif ($db_no eq 'freq') {
if ($index == $seq) {$retcode = $SigKill;}
}
}### Signal and scanning
}### Valid flag process
elsif ($sig_kill_states{$progstate} and ($datakey eq 'frequency')
and ($db_no eq 'freq')) {
my $frq = $database{$db_no}[$seq]{'frequency'};
if ((!$frq) or (!looks_like_number($frq))) {$frq = 0;}
if ($frq != $value) {
$old{'frequency'} = $frq;
$new{'frequency'} = $value;
if ($vfo{'signal'} and ($seq == $index)) {
$retcode = $SigKill;
}
}
}### Frequency being updated
elsif (($datakey eq 'tgid') and ($db_no eq 'freq')) {
my $tgid = $database{$db_no}[$seq]{'tgid'};
if (!$tgid) {$tgid = '';}
$tgid = Strip($tgid);
if ($value ne $tgid) {
$old{'tgid'} = $tgid;
$new{'tgid'} = $value;
}
}
elsif ($datakey eq 'sysno') {
if (!$value) {$value = 0;}
if ($value > 0) {
if (!defined $database{'system'}[$value]{'index'}) {
my $errmsg = "System $value does not exist! Change request ignored";
add_message($errmsg,1);
next;
}
}
}### sysno check
elsif ($datakey eq 'groupno') {
if (!$value) {$value = 0;}
if ($value > 0) {
if (!defined $database{'group'}[$value]{'index'}) {
my $errmsg = "Group $value does not exist! Change request ignored";
add_message($errmsg,1);
next;
}
}
}### groupno check
elsif ($datakey eq 'dlyrsm') {
if (looks_like_number($value)) {
$value = int($value);
}
else {
my $errmsg = "DLYRSM $value is NOT a number! Change request ignored";
add_message($errmsg,1);
next;
}
}
elsif ($datakey eq 'att_amp') {
if ($value =~ /att/i) {
$database{$db_no}[$seq]{'atten'} = TRUE;
$database{$db_no}[$seq]{'preamp'} = FALSE;
}
elsif ($value =~ /amp/i) {
$database{$db_no}[$seq]{'atten'} = FALSE;
$database{$db_no}[$seq]{'preamp'} = TRUE;
}
else {
$database{$db_no}[$seq]{'atten'} = FALSE;
$database{$db_no}[$seq]{'preamp'} = FALSE;
}
}
elsif ($datakey =~ /sqtone/i) {
$value = uc($value);
my $tt = substr($value,0,3);
my $tv = substr($value,3);
if (($tt =~ /off/i) or ($database{$db_no}[$seq]{'mode'} !~/fm/i)) {
$value = 'Off';
}
}### SQTONE process
elsif ($datakey eq 'step') {
if ((!looks_like_number($value)) or ($value < 1)) {
my $errmsg = "STEP Must be a number >0! Change request ignored";
add_message($errmsg,1);
next;
}
}
$database{$db_no}[$seq]{$datakey} = $value;
$change{$datakey} = $value;
}
if (defined $scan_request{'service'}) {
if ($db_no eq 'group') {
foreach my $rcd (@{$database{'freq'}}) {
if (!$rcd->{'index'}) {next;}
if ($rcd->{'groupno'} == $seq) {
push @{$shadowed{'freq'}},$rcd->{'index'};
}
}
}### Group shadow
elsif ($db_no eq 'system') {
foreach my $db ('freq','group') {
foreach my $rcd (@{$database{$db}}) {
if (!$rcd->{'index'}) {next;}
if ($rcd->{'sysno'} == $seq) {
push @{$shadowed{$db}},$rcd->{'index'};
}
}### for every record in this database
}### freq/group
}### system shadow
}### SERVICE field was changed
if ($old{'frequency'}) {
delete $freq_xref{$old{'frequency'}}{$seq};
$freq_xref{$new{'frequency'}}{$seq} = TRUE;
}
if ($old{'tgid'}) {
delete $freq_xref{$old{'tgid'}}{$seq};
$freq_xref{$new{'tgid'}}{$seq} = TRUE;
}
add_shadow(\%change);
foreach my $db (keys %shadowed) {
@selected = @{$shadowed{$db}};
%scan_request = ('_dbn' => $db, '_cmd' => 'batch');
if ($db_no eq 'system') {
$scan_request{'systemname'} = $database{'system'}[$seq]{'service'};
}
elsif ($db_no eq 'group') {
$scan_request{'groupname'} = $database{'group'}[$seq]{'service'};
}
else {
LogIt(3868,"SCANNER SYNC:reply error for shadow. No process for database $db_no");
}
tell_gui(3862);
}
if ($db_no =~ /lookup/i) {
my $freq = $database{'lookup'}[$seq]{'frequency'};
my $service = $database{'lookup'}[$seq]{'service'};
if ($freq and $service) {
$freq = $freq + 0;
$known{$freq} = $service;
}
}
clear_gui_request();
$response_pending = '';
return $retcode;
}### data sync command
elsif ($command eq 'create') {
my $dbndx = $req{'_dbn'};
if (!defined $dbndx) {
print Dumper(%req),"\n";
LogIt(1,"SCANNER l5963:Create:No Database name in gui_request!");
clear_gui_request();
next REQ_PROC;
}
my $sysno = 0;
my $groupno = 0;
if ($database{'system'}[1]{'index'}) {$sysno = 1;}
if ($database{'group'}[1]{'index'}) {$groupno = 1;}
if (!$sysno and (($dbndx eq 'freq') or ($dbndx eq 'group'))) {
my %sysrec = ('service' => 'Default System','valid' => TRUE, 'systemtype' => 'cnv');
$sysno = add_a_record(\%database,'system',\%sysrec,\&add_shadow);
}
if (($dbndx eq 'freq') and (!$groupno)) {
my %grouprec = ('service' => 'Default Group','valid' => TRUE, 'sysno' => $sysno);
$groupno = add_a_record(\%database,'group',\%grouprec,\&add_shadow);
}
my %rec = ();
%scan_request = ('_cmd' => 'update','_dbn' => $dbndx);
foreach my $key (@{$structure{$dbndx}}) {
if ($key =~ /^\_.*$/) {next;}   
my $value = $clear{$key};
if ($key eq 'sysno') {$value = $sysno;}
if ($key eq 'groupno') {$value = $groupno;}
$scan_request{$key} = $value;
$rec{$key} = $value;
}
my $reqno = add_a_record(\%database,$dbndx,\%rec,\&add_shadow);
$response_pending = '';
clear_gui_request();
return 0;
}
elsif ($command eq 'batch') {
$response_pending = "_Updating..";
%scan_request = ();
my $dbndx = $req{'_dbn'};
my $type = $req{'_type'};
if (!$type) {
print Dumper(%req),"\n";
LogIt(6055,"SCANNER l6055:Bad BATCH request!");
}
if (($type =~ /edit/i) or ($type =~ /xfer/i))  {
$response_pending = "Updating..";
}
my $retcode = $GoodCode;
my $savestate = $progstate;
clear_gui_request();
if (!defined $dbndx) {
print Dumper(%req),"\n";
LogIt(1,"SCANNER l6034:No Database name in BATCH gui_request!");
next REQ_PROC;
}
if (!defined $type) {
print Dumper(%req),"\n";
LogIt(1,"SCANNER l6041:No type in BATCH gui_request!");
next REQ_PROC;
}
if (!scalar @selected) {
LogIt(1,"SCANNER l6052:No SELECTED records in BATCH gui_request!");
next REQ_PROC;
}
my $sig_test = ($sig_kill_states{$progstate} and
$vfo{'signal'} and
$dbndx eq 'freq');
if ($type eq 'edit') {
$progstate = 'edit';
if ($sig_test) {
if ((!defined $req{'valid'}) or $req{'valid'}) {$sig_test = FALSE;}
}
if ($req{'sysno'}) {
if (!$database{'system'}[$req{'sysno'}]{'index'}) {
add_message("EDIT: SYSTEM number $req{'sysno'} does not exist!" .
" Request ignored.",1);
delete $req{'sysno'};
}
}
if ($req{'groupno'}) {
if (!$database{'group'}[$req{'groupno'}]{'index'}) {
add_message("EDIT: GROUP number $req{'groupno'} does not exist!" .
" Request ignored.",1);
delete $req{'groupno'};
}
}
RECPROC:
foreach my $recno (@selected) {
if ($recno < 0) {next;}
if ($sig_test and ($recno eq $vfo{'index'})) {
$retcode = $SigKill;
}
%scan_request = ('_cmd' => 'batch','_dbn' => $dbndx);
foreach my $datakey (keys %req) {
if (substr($datakey,0,1) eq '_') {next;}
my $value =  $req{$datakey};
$database{$dbndx}[$recno]{$datakey} = $value;
if (($datakey eq 'groupno') or ($datakey eq 'sysno')) {
shadow_sub($dbndx,$recno,\%scan_request);
}
$scan_request{$datakey} = $value;
}### for all datakeys
tell_gui(6116);
if ($progstate ne 'edit') {last RECPROC;}
}### for All Records
$progstate = $savestate;
update_xref();
}### EDIT
elsif ($type eq 'delete') {
my %affected = ();
foreach my $recno (@selected) {
if ($recno < 0) {next;}
$database{$dbndx}[$recno]{'index'} = 0;
$database{$dbndx}[$recno]{'valid'} = FALSE;
$delete_count{$dbndx}++;
$affected{$recno} = TRUE;
if ($sig_test and ($recno eq $vfo{'index'})) {
$retcode = $sigkill;
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
}
}### database delete records
%scan_request = ('_cmd' => 'delete','_dbn' => $dbndx);
tell_gui(3935);
if (($dbndx eq 'system') or ($dbndx eq 'group')) {
foreach my $changedb ('freq','group') {
@selected = ();
if ($dbndx eq $changedb) {next;}
my $xref = 'sysno';
if ($dbndx eq 'group') {$xref = 'groupno';
}
foreach my $rec (@{$database{$changedb}}) {
if (!$rec->{'index'}) {next;}
my $no = $rec->{$xref};
if (!$no) {next;}
if ($affected{$no}) {
$rec->{$xref} = 0;
push @selected,$rec->{'index'};
}
}
if (scalar @selected) {
%scan_request = ('_cmd' => 'batch','_dbn' => $changedb);
shadow_sub($changedb,$selected[0],\%scan_request);
tell_gui(3966);
}
}## GROUP & FREQ record check
}## GROUP or SYSTEM record deleted
}### delete
elsif ($type eq 'swap') {
my $dbndx = $req{'_dbn'};
if (!defined $dbndx) {
print Dumper(%gui_request),"\n";
LogIt(3358,"SCANNER_SYNC:Swap:No Database name in gui_request!");
}
my $rec1_ndx = $selected[0];
my $rec2_ndx = $selected[1];
if ($sig_test and
(($rec1_ndx eq $vfo{'index'})
or($rec2_ndx eq $vfo{'index'} )))  {
$retcode = $sigkill;
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
}
my %temp = ();
foreach my $key (keys %{$database{$dbndx}[$rec1_ndx]}) {
$temp{$key} = $database{$dbndx}[$rec1_ndx]{'key'};
}
%scan_request = ('_cmd' => 'update','_dbn' => $dbndx,'_seq' => $rec1_ndx);
foreach my $key (keys %{$database{$dbndx}[$rec2_ndx]}) {
if ($key eq 'index') {next;}
$scan_request{$key} = $database{$dbndx}[$rec2_ndx]{$key};
}
tell_gui(6303);
%scan_request = ('_cmd' => 'update','_dbn' => $dbndx,'_seq' => $rec2_ndx);
foreach my $key (keys %temp) {
if ($key eq 'index') {next;}
$scan_request{$key} = $temp{$key};
}
tell_gui(6303);
}
elsif ($type eq 'xfer') {
foreach my $recno (@selected) {
my $freq = $database{'freq'}[$recno]{'frequency'};
my $service = $database{'freq'}[$recno]{'service'};
if (!$freq) {next;}
my $fmhz = rc_to_freq($freq);
$freq = $freq + 0;
if ($known{$freq}) {
add_message("$fmhz already in database",0);
}
elsif (!$service) {
add_message("No service defined for $fmhz",0);
}
else {
my %newrec = ('frequency' => $freq,
'service' => $service
);
add_a_record(\%database,'lookup',\%newrec,\&add_shadow);
$known{$freq} = $service;
}
}
}### XFER process
elsif ($type eq 'lookup') {
foreach my $recno (@selected) {
my $freq = $database{'freq'}[$recno]{'frequency'};
my $service = $database{'freq'}[$recno]{'service'};
if (!$freq) {next;}
my $fmhz = rc_to_freq($freq);
if ($service) {
add_message("$recno already has service set. Bypassing",0);
}
if ($known{$freq}) {
$database{'freq'}[$recno]{'service'} = $known{$freq};
%scan_request = ('_cmd' => 'update', '_dbn' => 'freq',
'_seq' => $recno, 'service' => $known{$freq});
tell_gui(6399);
}
else {
add_message("No LOOKUP available for $fmhz (record $recno)",0);
}
}
}### LOOKUP process
else {LogIt(1,"SCANNER_SYNC_Batch:No processing for type=$type");}
@selected = ();
$response_pending = '';
return $retcode;
}### Batch
elsif ($command eq 'renum') {
print "Renum:", Dumper(%gui_request),"\n";
$response_pending = 'Renumber in process..';
clear_gui_request();
$progstate = 'renum';
foreach my $rcd (@{$database{'freq'}}) {
my $index = $rcd->{'index'};
if (!$index) {next;}
$rcd->{'channel'} = $index;
%scan_request = ('_cmd' => 'update','_dbn' => 'freq',
'_seq' => $index, 'channel' => $index);
tell_gui(3358);
if ($progstate ne 'renum') {last;}
}
$progstate = 'manual';
$response_pending = '';
return $statechange;
}
elsif ($command eq 'incr') {
my $ctl = $req{'_ctl'};
my $dir = $req{'_dir'};
if (!$dir) {
LogIt(1,"SCANNER l6349:missing '_dir' value in 'INCR' gui_request");
$dir = 'up';
}
if (!$ctl) {
LogIt(1,"SCANNER l6353:Missing _ctl' in 'INCR' gui_request'");
print Dumper(%req),"\n";
clear_gui_request();
next REQ_PROC;
}
my $retcode = $GoodCode;
if ($vfo{'signal'}) {$retcode = $SigKill;}
if ($ctl =~ /freq/i) {
if (($progstate eq 'manual') or
($progstate eq 'frequency_scan') or
($progstate eq 'search') or
($progstate eq 'bank_search')) {
$vfo{'direction'} = 1;
my $freq = $vfo{'frequency'} + $vfo{'step'};
if ($dir =~ /down/i) {
$freq = $vfo{'frequency'} - $vfo{'step'};
$vfo{'direction'} = -1;
}
if (!check_range($freq,\%radio_def)) {
if ($dir =~ /up/i) {$freq = $radio_def{'minfreq'};}
else {$freq = $radio_def{'maxfreq'};}
}
$vfo{'frequency'} = $freq;
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
dply_vfo(6405);
clear_gui_request();
radio_sync('setvfo',6166);
return $retcode;
}### Valid states for FREQUENCY update
}### FREQUENCY value update
elsif ($ctl eq 'rchan') {
if ($radio_def{'memory'} and ($radio_def{'memory'} =~ /dy/i)) {
clear_gui_request();
next REQ_PROC;
}
if (($progstate eq 'manual') or ($progstate eq 'channel_scan')) {
my $chan = $vfo{'channel'};
if ((!defined $chan) or (!looks_like_number($chan))) {$chan = -1;}
if ($dir =~ /up/i) {$chan = $chan + 1;}
else {$chan = $chan - 1;}
if ($chan > $radio_def{'maxchan'}) {$chan = $radio_def{'origin'};}
elsif ($chan < $radio_def{'origin'}) {$chan = $radio_def{'maxchan'};}
$vfo{'channel'} = $chan;
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
dply_vfo(6405);
clear_gui_request();
radio_sync('selmem',6452);
return $retcode;
}### Valid  states for RCHAN update
}### RCHAN update
elsif ($ctl eq 'vchan') {
if (($progstate eq 'manual')) {
my $dbrecs = scalar @{$database{'freq'}};
if ($dbrecs < 2 ) {
print "SCANNER l6471:No channels to select\n";
clear_gui_request();
next REQ_PROC;
}
my $max_index = $dbrecs - 1;
my $index = $vfo{'index'};
if (!$index) {$index = 0;}
if ($dir =~ /up/i) {$index = $index + 1;}
else {$index = $index - 1;}
if ($index < 1) {$index = $max_index;}
elsif ($index > $max_index) {$index = 1;}
foreach my $key ('frequency','mode','sqtone','atten','preamp') {
$vfo{$key} = $database{'freq'}[$index]{$key};
}
$vfo{'index'} = $index;
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
dply_vfo(6493);
clear_gui_request();
radio_sync('setvfo',6499);
return $retcode;
}### Valid states for VCHAN update
}### VCHAN control
else {
print Dumper(%req),"\n";
LogIt(6510,"Bad control $ctl specified in request");
}
}### INCR command process
else  {
LogIt(1,"SCANNER_SYNC:No processing defined for command $command on scanner!");
print Dumper(%req);
$response_pending = '';
}
$response_pending = '';
clear_gui_request();
}### waiting for a request
my $retcode = $GoodCode;
if ($statechange) {$retcode = $StateChange;}
elsif ($sigkill) {$retcode = $SigKill;}
return $retcode;
}## Scanner sync
sub clear_gui_request {
lock(%gui_request);
%gui_request = ();
threads->yield;
usleep 100;
}
sub mem2vfo {
my $index = shift @_;
if (!looks_like_number($index)) {
my ($pkg,$fn,$caller) = caller;
LogIt(1,"SCANNER l6084:MEM2VFO non-numeric value $index passed! Caller=$caller");
return $ParmErr;
}
if (!$database{'freq'}[$index]{'index'}) {
my ($pkg,$fn,$caller) = caller;
LogIt(1,"SCANNER l5089:Mem2VFO $index is a non-existant database record! Caller=$caller");
return $ParmErr;
}
$vfo{'index'} = $index;
foreach my $key ('frequency','mode','sqtone') {
$vfo{$key} = $database{'freq'}[$index]{$key};
}
my $att   = $database{'freq'}[$index]{'att_amp'};
$vfo{'atten'} = FALSE;
$vfo{'preamp'} = FALSE;
if ($att =~ /att/i) {$vfo{'atten'} = TRUE;}
elsif ($att =~ /pre/i) {$vfo{'preamp'} = TRUE;}
my $retcode = radio_sync('setvfo',6064);
if (!$retcode) {$retcode = radio_sync('getvfo',6065);}
return $retcode;
}
sub set_att_amp {
my $value = shift @_;
if ($value =~ /att/i) {
$vfo{'atten'} = TRUE;
$vfo{'preamp'} = FALSE;
}
elsif ($value =~ /amp/i) {
$vfo{'atten'} = FALSE;
$vfo{'preamp'} = TRUE;
}
else {
$vfo{'atten'} = FALSE;
$vfo{'preamp'} = FALSE;
}
return 0;
}
sub vfo2mem {
my $dbndx = shift @_;
my $seq = shift @_;
%scan_request = ('_dbn' => $dbndx, '_seq' => $seq, );
foreach my $key (@{$structure{$dbndx}}) {
my $value = $vfo{$key};
if (!defined $value) {$value = $clear{$key};}
if ($key eq 'dlyrsm') {$value = $control{'dlyrsm'};}
elsif ($key eq 'valid') {
if (($dbndx eq 'freq') and ($vfo{'frequency'} == 0)) {$value = FALSE;}
}
elsif ($key eq 'service') {
if (($dbndx eq 'freq') and $vfo{'tgid'} and (!$database{$dbndx}[$seq]{'service'})) {
$value = $vfo{'systemname'};
}
}
else {
}
$database{$dbndx}[$seq]{$key} = $value;
$scan_request{$key} = $value;
}
tell_gui(4811);
return 0;
}
sub squelch_level {
if (!$vfo{'signal'}) {return TRUE;}
my $cmpr = $control{'squelch'}/10;
if ($vfo{'signal'} < $cmpr) {return TRUE;}
else {return FALSE;}
}
sub tell_gui {
my $cmd = $scan_request{'_cmd'};
my $line    = shift @_;
if (!$line) {$line = '??';}
if (!$cmd) {
my ($pack,$file,$cline) = caller();
print "Scan Request=>",Dumper(%scan_request),"\n";
LogIt(4127,"TELL_GUI:Forgot the command from line $line (caller=>$file:$cline)");
}
if ($progstate eq 'quit') {return;}
if ($cmd eq 'term')      {return;}
usleep(10);
$scan_request{'_rdy'} = TRUE;
my $i=0;
while ($scan_request{'_cmd'}) {
threads->yield;
usleep(30000);
threads->yield;
$i++;
}
%scan_request = ();
return 0;
}
sub add_shadow {
my $ref = shift @_;
my $dbn = $ref->{'_dbn'};
if (!$dbn) {LogIt(4782,"ADD_SHADOW:No _DBN spec");}
my @records = ();
my $cmd = 'update';
if ($ref->{'_seq'}) {@records = ($ref->{'_seq'});}
else {
LogIt(1,"ADD_SHADOW called for $ref->{'_dbn'} record 0");
return 0;
}
%scan_request = ('_cmd' => $cmd,'_dbn' => $dbn, '_seq'=> $records[0]);
foreach my $key (keys %{$ref}) {
if (substr($key,0,1) eq '_') {next;}
if (!defined $ref->{$key}) {
LogIt(1,"SCANNER l5019:Undefined value for key $key database=>$dbn");
next;
}
$scan_request{$key} = $ref->{$key};
}
if (($dbn eq 'freq') or ($dbn eq 'group')) {
foreach my $recno (@records) {
if (!$database{$dbn}[$recno]{'index'}) {
LogIt(4798,"ADD_SHADOW:Called update for a non-existant record!");
}
shadow_sub($dbn,$recno,\%scan_request);
}### for all records
}### Group or System
tell_gui(4985);
dply_vfo(4986);
if ($dbn eq 'freq') {
my $ndx = $ref->{'_seq'};
if ($ndx) {
my $freq = $database{$dbn}[$ndx]{'frequency'};
my $tgid = $database{$dbn}[$ndx]{'tgid'};
if ($freq) {
$freq = $freq + 0;
$freq_xref{$freq}{$ndx} = TRUE;
}
if ($tgid) {
$tgid = Strip($tgid);
$tgid_xref{$tgid}{$ndx} = TRUE;
}
}
}
}
sub shadow_sub {
my $dbn = shift @_;
if ($dbn eq 'SYSTEM') {return 0;}
my $recno = shift @_;
my $hash = shift @_;
foreach my $refdb ('system','group') {
if (($refdb eq 'group') and ($dbn ne 'freq')) {next;}
if (($refdb eq 'system') and ($dbn eq 'freq')) {next;}
my $keytype = 'sysno';
if ($refdb eq 'group') {$keytype = 'groupno';}
my $shadow = $refdb . 'name';
my $keyno = $database{$dbn}[$recno]{$keytype};
if ($keyno) {
my $keyname = '';
if ($database{$refdb}[$keyno]{'index'}) {
$keyname = $database{$refdb}[$keyno]{'service'};
}
else {$keyno = 0;}
$database{$dbn}[$recno]{$shadow} = $keyname;
$database{$dbn}[$recno]{$keytype} = $keyno;
$hash->{$keytype} = $keyno;
$hash->{$shadow} = $keyname;
}
else {
print "SCANNER l5197:Keyno for database $dbn record=$recno keytype=$keytype is not defined\n";
$keyno = 0;
}
}### for each database
return 0;
}### Shadow_sub
sub wait_for_command {
if ($progstate eq 'quit') { return;}
if ($gui_request{'_cmd'} and ($gui_request{'_cmd'} eq 'term')) {return;}
my $request = shift @_;
my $line_no = shift @_;
my $cmd = $request->{'_cmd'};
if (!$cmd) {
LogIt(4160,"WAIT_FOR_COMMAND:Missing command!");
}
my $i=0;
{
lock(%scan_request);
%scan_request = %{$request};
$scan_request{'_rdy'} = TRUE;
}
while ($scan_request{'_cmd'}) {
threads->yield;
usleep(20000);
threads->yield;
$i++;
}
LogIt(0,"Scanner received completion from last request after $i waits");
%scan_request = ();
return 0;
}
sub pop_up {
if ($progstate eq 'quit') {return;}
if ($gui_request{'_cmd'} and ($gui_request{'_cmd'} eq 'term')) {return;}
my $msg = shift @_;
{
lock (%scan_request);
%scan_request = ('_cmd' => 'pop-up','msg' => $msg);
$scan_request{'_rdy'} = TRUE;
}
while ($scan_request{'_cmd'}) {
threads->yield;
usleep(20000);
threads->yield;
}
}
sub dply_vfo {
my $caller = shift @_;
foreach my $dbndx (@dblist) {
if (defined $database{$dbndx}) {
if (!$delete_count{$dbndx}) {$delete_count{$dbndx} = 0;}
$dbcounts{$dbndx} = (scalar @{$database{$dbndx}}) - $delete_count{$dbndx} - 1;
}
else {$dbcounts{$dbndx} = 0;}
}
if (!defined $vfo{'sysno'}) {
LogIt(1,"DPLY_VFO:vfo{sysno} is undefined from caller=>$caller");
$vfo{'sysno'} = 0;
}
%scan_request = ('_dbn' => 'vfo','_cmd' => 'vfodply');
tell_gui(399);
return 0;
}
sub dply_sig {
my $caller = shift @_;
%scan_request = ('_dbn' => 'vfo','_cmd' => 'sigdply');
tell_gui(5003);
return 0;
}
sub set_manual_state {
if ($progstate eq 'manual') {return;}
radio_sync('manual',4559);
$vfo{'signal'} = 0;
$local_vfo{'signal'} = 0;
dply_sig(2925);
usleep(200000);
$progstate = 'manual';
%scan_request = ('_cmd' => 'statechange', 'state' => $progstate);
tell_gui(4396);
return 0;
}
sub update_xref {
%freq_xref = ();
%tgid_xref = ();
foreach my $rcd (@{$database{'freq'}}) {
my $reqno = $rcd->{'index'};
if (!$reqno) {next;}
$reqno = $reqno + 0;
my $freq = $rcd->{'frequency'};
my $tgid = $rcd->{'tgid'};
if ($freq) {
$freq = $freq + 0;
$freq_xref{$freq}{$reqno} = TRUE;
}
if ($tgid) {
$tgid = Strip($tgid);
$tgid_xref{$freq}{$reqno} = TRUE;
}
my $sql = $rcd->{'sqtone'};
if (($sql =~ /nac/i) or ($sql =~ /ccd/i) or ($sql =~ /rpt/i)
or ($sql =~ /ran/i) or ($sql =~ /dsq/i)) {
$rcd->{'sqtone'} = 'Off';
}
}
}
sub in_scope_variables {
my %in_scope = %{peek_our(1)};
my $lexical  = peek_my(1);
while (my ($var, $ref) = each %$lexical) {
$in_scope{$var} = $ref;
}
return \%in_scope;
}
sub clear_database {
my $dbndx = shift @_;
if (!$dbndx) {LogIt(4758,"SCANNER Clear_database:Called with no dbndx!");}
$database{$dbndx} = ();
$delete_count{$dbndx} = 0;
push @{$database{$dbndx}},{%dummy_record};
$chan_active{$dbndx} = 0;
%freq_xref = ();
%tgid_xref = ();
}
sub record_thread {
my $snd_type = 'wav';
my $tempdir = $settings{'tempdir'};
my $temp_file = "$tempdir/temp.$snd_type";
my $mergefile = "$tempdir/mergefile.$snd_type";
my $recdir = $settings{'recdir'};
while (TRUE) {
while (!$start_recording and ($progstate ne 'quit') ) {
threads->yield;
usleep 100;
}
if ($progstate eq 'quit') {
print $Bold,"Recording thread terminating$Eol";
threads->exit(0);
}
my $filename =  Strip(rc_to_freq($vfo{'frequency'}));
if ($vfo{'tgid'}) {
$filename = Strip($vfo{'tgid'}) . '-' . Strip($vfo{'service'});
}
$filename =~ s/\//_/g;   
$filename =~ s/\&/and/g; 
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
localtime(time());
my $timestamp = sprintf("%4.4u",$year+1900) .
sprintf("%02.2u",$mon+1) .
sprintf("%02.2u",$mday) .
sprintf("%02.2u",$hour) .
sprintf("%02.2u",$min) .
sprintf("%02.2u",$sec) ;
print "Recording started at $timestamp\n";
if ($control{'recorder_multi'}) {
$filename = "$filename-$timestamp";
}
else {
print "L8132:record_multi was not set\n";
}
$filename = "$recdir/$filename.$snd_type";
$record_file = $filename;
if (-d $tempdir) {
my $cmd = "parecord --file-format=$snd_type --format=s32be $temp_file &";
my $rtn = `$cmd`;
while ($start_recording) {usleep 100;}
`killall parecord`;
if (-e  $temp_file) {
if (-e $filename) {
`sox  "$filename" $temp_file $mergefile`;
my $rtn = `mv $mergefile "$filename"`;
if ($rtn) {LogIt(1,"SCANNER l5000:'mv' returned $rtn");}
print "L8169: updated recording $filename\n"
}
else {
my $rtn = `mv $temp_file "$filename"`;
if ($rtn) {LogIt(1,"SCANNER l8177:'mv' returned $rtn");}
print "L8179: created recording $filename\n"
}
}
else { LogIt(1,"Scanner l8180:No recording file was found");}
}### Temporary directory exists
else {
LogIt(1,"Scanner l8184:Cannot record audio. $tempdir does not exist!");
lock($start_recording);
$start_recording = FALSE;
threads->yield;
next;
}
}### do forever
}
sub Numerically {
use Scalar::Util qw(looks_like_number);
if (looks_like_number($a) and looks_like_number($b)) { $a <=> $b;}
else {$a cmp $b;}
}
