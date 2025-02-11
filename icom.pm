#!/usr/bin/perl -w
package icom;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(R7000 IC703 IC705 R8600 ICR30 IC7300 OTHER
icom_cmd
%radio_limits
%icom_decode
%icom_encode
packet_decode
icom_sdcard
rcmode2icom
) ;
use Data::Dumper;
use Text::ParseWords;
use threads;
use threads::shared;
use Thread::Queue;
use Time::HiRes qw(time usleep ualarm gettimeofday tv_interval );
use Device::SerialPort qw ( :PARAM :STAT 0.07 );
use Scalar::Util qw(looks_like_number);
use radioctl;
use strict;
use autovivification;
no  autovivification;
use constant ICOM_SIG_ADJUST     => int(255/MAXSIGNAL);
use constant FA                  => 250;
use constant FB                  => 251;
use constant FC                  => 252;
use constant FD                  => 253;
use constant FE                  => 254;
use constant FF                  => 255;
use constant ICOM_TERMINATOR     => FD;
use constant ICOM_PREAMBLE       => FE;
my %icom_commands = ('_set_freq_noack' => {'code' => '00'  ,'ack' => 0,},
'_set_mode_noack' => {'code' => '01'  ,'ack' => 0,},
'_get_range'      => {'code' => '02'  ,'ack' => 2,},
'_get_freq'       => {'code' => '03'  ,'ack' => 2,},
'_get_mode'       => {'code' => '04'  ,'ack' => 2,},
'_set_freq'       => {'code' => '05'  ,'ack' => 1,},
'_set_mode'       => {'code' => '06'  ,'ack' => 1,},
'_vfo_state'      => {'code' => '07'  ,'ack' => 1,},
'_select_vfoa'    => {'code' => '0700','ack' => 1,},
'_select_vfob'    => {'code' => '0701','ack' => 1,},
'_equalize_vfo'   => {'code' => '07A0','ack' => 1,},
'_swap_vfo'       => {'code' => '07B0','ack' => 1,},
'_select_aband'   => {'code' => '07D0','ack' => 1,},
'_select_bband'   => {'code' => '07D1','ack' => 1,},
'_memory_state'   => {'code' => '08'  ,'ack' => 1,},
'_select_chan'    => {'code' => '08'  ,'ack' => 1,},
'_select_group'   => {'code' => '08A0','ack' => 1,},
'_vfo_to_mem'     => {'code' => '09'  ,'ack' => 1,},
'_mem_to_vfo'     => {'code' => '0A'  ,'ack' => 1,},
'_clear_mem'      => {'code' => '0B'  ,'ack' => 1,},
'_read_offset'    => {'code' => '0C'  ,'ack' => 2,},
'_write_offset'   => {'code' => '0D'  ,'ack' => 1,},
'_stop_scan'      => {'code' => '0E00','ack' => 1,},
'_memory_scan'    => {'code' => '0E01','ack' => 1,},
'_prog_scan'      => {'code' => '0E02','ack' => 1,},
'_delta_scan'     => {'code' => '0E03','ack' => 1,},
'_select_scan'    => {'code' => '0E23','ack' => 1,},
'_read_duplex'    => {'code' => '0F'  ,'ack' => 2,},
'_split_off'      => {'code' => '0F00','ack' => 1,},
'_split_on'       => {'code' => '0F01','ack' => 1,},
'_duplex_off'     => {'code' => '0F10','ack' => 1,},
'_duplex_plus'    => {'code' => '0F12','ack' => 1,},
'_vfo_step'       => {'code' => '10',  'ack' => 2,},
'_vfo_atten'      => {'code' => '11'  ,'ack' => 2,},
'_select_antenna' => {'code' => '12'  ,'ack' => 1,},
'_af_gain'        => {'code' => '1401','ack' => 2,},
'_rf_gain'        => {'code' => '1402','ack' => 2,},
'_sq_level'       => {'code' => '1403','ack' => 2,},
'_if_shift'       => {'code' => '1404','ack' => 2,},
'_nr_level'       => {'code' => '1406','ack' => 2,},
'_twin_pbt_inside_level' => {'code' => '1407','ack' => 2,},
'_twin_pbt_outside_level' => {'code' => '1408','ack' => 2,},
'_cw_pitch_level'  => {'code' => '1409','ack' => 2,},
'_rf_power_level' => {'code' => '140A','ack' => 2,},
'_mic_gain_level' => {'code' => '140B','ack' => 2,},
'_key_speed' => {'code' => '140C','ack' => 2,},
'_comp_level' => {'code' => '140E','ack' => 2,},
'_breakin_delay' => {'code' => '140F','ack' => 2,},
'_get_squelch'    => {'code' => '1501','ack' => 2,},
'_get_signal'     => {'code' => '1502','ack' => 2,},
'_get_tone_squelch'    => {'code' => '1505','ack' => 2,},
'_get_rf_meter'     => {'code' => '1511','ack' => 2,},
'_get_swr_meter'     => {'code' => '1512','ack' => 2,},
'_get_als_meter'     => {'code' => '1513','ack' => 2,},
'_vfo_preamp'     => {'code' => '1602','ack' => 2,},
'_vfo_agc'        => {'code' => '1612','ack' => 2,},
'_vfo_noise_blanker'     => {'code' => '1622','ack' => 2,},
'_vfo_noise_reduction'   => {'code' => '1640','ack' => 2,},
'_vfo_auto_notch'   => {'code' => '1641','ack' => 2,},
'_vfo_repeater_state'  => {'code' => '1642','ack' => 2,},
'_vfo_ctc_state'       => {'code' => '1643','ack' => 2,},
'_speech_compress'  => {'code' => '1644','ack' => 2,},
'_monitor'   => {'code' => '1645','ack' => 2,},
'_vox'       => {'code' => '1646','ack' => 2,},
'_breakin'      => {'code' => '1647','ack' => 2,},
'_afc'   => {'code' => '164A','ack' => 2,},
'_vfo_dcs_state'  => {'code' => '164B','ack' => 2,},
'_vsc'   => {'code' => '164C','ack' => 2,},
'_p25_dsql'   => {'code' => '1652','ack' => 2,},
'_dply_type'   => {'code' => '1659','ack' => 2,},
'_dstar_dsql'   => {'code' => '165B','ack' => 2,},
'_dpmr_dsql'   => {'code' => '165F','ack' => 2,},
'_ndxn_dsql'   => {'code' => '1660','ack' => 2,},
'_dcr_dsql'   => {'code' => '1661','ack' => 2,},
'_dpmr_scrambler'   => {'code' => '1662','ack' => 2,},
'_nxdn_encrypt'    => {'code' => '1663','ack' => 2,},
'_dcr_encrypt'    => {'code' => '1664','ack' => 2,},
'_turn_off'       => {'code' => '1800','ack' => 0,},
'_turn_on'        => {'code' => '1801','ack' => 0,},
'_get_id'         => {'code' => '1900','ack' => 2,},
'_memory_direct'  => {'code' => '1A00','ack' => 2,},
'_band_stack'     => {'code' => '1A01','ack' => 2,},
'_earphone'       => {'code' => '1A01','ack' => 2,},
'_memory_keyer'  => {'code' => '1A02','ack' => 2,},
'_rcv_frequency'  => {'code' => '1A02','ack' => 1,},
'_change_direction' => {'code' => '1A03','ack' => 1,},
'_beep_emission'  => {'code' => '1A0301','ack' => 2,},
'_band_edge_beep'  => {'code' => '1A0302','ack' => 2,},
'_beep_level'  => {'code' => '1A0303','ack' => 2,},
'_beep_limit'  => {'code' => '1A0304','ack' => 2,},
'_cw_carrier_point'  => {'code' => '1A0305','ack' => 2,},
'_side_tone_level'  => {'code' => '1A0306','ack' => 2,},
'_op_state' => {'code' => '1A04','ack' => 2,},
'_ab_sync' => {'code' => '1A06','ack' => 2,},
'_af_gain_07' => {'code' => '1A07','ack' => 2,},
'_skip_setting' => {'code' => '1A03','ack' => 2,},
'_recording' => {'code' => '1A09','ack' => 1,},
'_start_a_scan'  => {'code' => '1A0A00','ack' => 1,},
'_cancel_scan'   => {'code' => '1A0A01','ack' => 1,},
'_temp_skip'     => {'code' => '1A0A02','ack' => 1,},
'_get_temp_skip' => {'code' => '1A0A03','ack' => 2,},
'_cancel_temp_skip' => {'code' => '1A0A04','ack' => 1,},
'_transceive_scan'  => {'code' => '1A0B00','ack' => 2,},
'_transceive_settings'  => {'code' => '1A0B01','ack' => 1,},
'_get_transceive_settings'  => {'code' => '1A0B01','ack' => 2,},
'_get_scan_condition'  => {'code' => '1A0B02','ack' => 2,},
'_get_scan_info'   => {'code' => '1A0C','ack' => 2,},
'_get_program_link_name'  => {'code' => '1A0D00','ack' => 2,},
'_get_program_edge_name'  => {'code' => '1A0E00','ack' => 2,},
'_get_program_edge_name_change'  => {'code' => '1A0E01','ack' => 2,},
'_get_memory_group_name'  => {'code' => '1A0F00','ack' => 2,},
'_get_memory_group_name_change'  => {'code' => '1A0F01','ack' => 2,},
'_display_content_change_report'  => {'code' => '1A1000','ack' => 2,},
'_get_display_change_transceive'  => {'code' => '1A1001','ack' => 2,},
'_get_display'  => {'code' => '1A11','ack' => 2,},
'_get_noise_smeter'  => {'code' => '1A12','ack' => 2,},
'_bluetooth_detection'  => {'code' => '1A1300','ack' => 2,},
'_bluetooth_transceive_detection'  => {'code' => '1A1301','ack' => 2,},
'_vfo_repeater_value'  => {'code' => '1B00','ack' => 2,},
'_vfo_ctc_value'  => {'code' => '1B01','ack' => 2,},
'_vfo_dcs_value'   => {'code' => '1B02','ack' => 2,},
'_vfo_nac_value'   => {'code' => '1B03','ack' => 2,},
'_vfo_dsq_value'   => {'code' => '1B07','ack' => 2,},
'_vfo_ran_value'   => {'code' => '1B0A','ack' => 2,},
'_vfo_crypt_key'   => {'code' => '1B0D','ack' => 2,},
'_get_nxdn_rx_id'  => {'code' => '200A02','ack' => 2,},
'_get_nxdn_rx_status'  => {'code' => '200B02','ack' => 2,},
);
my %cmd_lookup = ();
foreach my $cmd (keys %icom_commands) {$cmd_lookup{$icom_commands{$cmd}{'code'}} = $cmd;}
use constant R7000      => 'R7000';
use constant IC703      => 'IC703';
use constant IC705      => 'IC705';
use constant R8600      => 'R8600';
use constant IC7300     => 'IC7300';
use constant ICR30      => 'ICR30';
use constant OTHER      => 'ICOM';
my %default_addr = ('68' => IC703,
'96' => R8600,
'08' => R7000,
'9C' => ICR30,
'A4' => IC705,
'94' => IC7300,
);
my %radio_limits = (
&R7000 => {'minfreq'      =>  25000000,'maxfreq'    => 999999000,
'sigdet'       => 0,
'radioscan'    => 0,
'maxchan'      => 99,
'origin'       => 1,
'group'        => FALSE,
'serv_len'     => 0,
'split'        => FALSE,
'scangrp'      => 0,
'digital'      => FALSE,
'dcs'          => FALSE,
},
&IC703 => {'minfreq'      =>     30000,'maxfreq'    =>  60000000,
'sigdet'       => 2,
'radioscan'    => 2,
'maxchan'      => 99,
'origin'       => 1,
'group'        => FALSE,
'serv_len'     => 9,
'split'        => TRUE,
'scangrp'      => 0,
'digital'      => FALSE,
'dcs'          => FALSE,
},
&IC705 => {'minfreq'      =>     30000,'maxfreq'    => 470000000,
'gstart_1' => 199999001,'gstop_1' => 400000000,
'sigdet'       => 2,
'radioscan'    => 2,
'maxchan'      => 9999,
'origin'       => 0,
'group'        => TRUE,
'serv_len'     => 16,
'split'        => TRUE,
'scangrp'      => 3,
'digital'      => FALSE,
'dcs'          => TRUE,
},
&ICR30 => {'minfreq'      =>    100000,'maxfreq'    =>3304999990,
'gstart_1' => 821999991,'gstop_1' => 851000000,
'gstart_2' => 866999991,'gstop_2' => 896000000,
'sigdet'       => 2,
'radioscan'    => 2,
'maxchan'      => 9999,
'origin'       => 0,
'group'        => TRUE,
'split'        => FALSE,
'scangrp'      => 0,
'digital'      => TRUE,
'dcs'          => TRUE,
},
&R8600 => {'minfreq'      =>    010000,'maxfreq'    =>3000000000,
'gstart_1' => 822000000,'gstop_1' => 851000000,
'gstart_2' => 867999999,'gstop_2' => 896000000,
'sigdet'       => 2,
'radioscan'    => 2,
'maxchan'      => 9999,
'origin'       => 0,
'group'        => TRUE,
'serv_len'     => 16,
'split'        => FALSE,
'scangrp'      => 9,
'digital'      => TRUE,
'dcs'          => TRUE,
},
&IC7300 => {'minfreq'      =>  030000,'maxfreq'    => 748000000,
'sigdet'       => 2,
'radioscan'    => 2,
'maxchan'      => 99,
'origin'       => 1,
'group'        => FALSE,
'serv_len'     => 10,
'split'        => TRUE,
'scangrp'      => 0,
'digital'      => FALSE,
'dcs'          => FALSE,
},
&OTHER => {'minfreq'      =>  030000,'maxfreq'    => 512000000,
'sigdet'       => 0,
'radioscan'    => 0,
'maxchan'      => 99,
'origin'       => 1,
'group'        => FALSE,
'dcs'          => FALSE,
'split'        => FALSE,
'scangrp'      => 0,
'digital'      => FALSE,
},
);
my %direct_format = (
&OTHER => [
'chan',
'flag1',
'frequency','mode',
'tt1',
'rsvd',
'rpt',
'rsvd',
'ctc',
'sfreq','smode',
'stt1','rsvd',
'srptr','rsvd','sctc',
'service',
],
&IC703 => [
'chan',
'flag1',
'frequency','mode',
'tt1','rsvd',
'rpt','rsvd',
'ctc',
'sfreq','smode',
'stt1','rsvd',
'srpt',
'rsvd',
'sctc',
'service',
],
&IC705 => [
'igrp','chan',
'split',
'frequency','mode',
'rsvd',
'tt2',
'rsvd',
'rsvd',
'rpt',
'rsvd',
'ctc',
'rsvd',
'dcs',
'rsvd',
'fof',
'callsignur',
'callsignr1',
'callsignr2',
'sfreq','smode',
'rsvd',
'stt2',
'rsvd',
'rsvd',
'srpt',
'rsvd',
'sctc',
'rsvd',
'sdcs',
'rsvd',
'sfof',
'callsignur',
'callsignr1',
'callsignr2',
'service',
],
&IC7300 => [
'chan',
'split',
'frequency','mode',
'tt1',
'rsvd',
'rpt',
'rsvd',
'ctc',
'sfreq','smode',
'nybl','stt',
'rsvd',
'srpt',
'rsvd',
'sctc',
'service',
],
&R8600 => [
'igrp','chan',
'select',
'frequency','mode',
'duplex',
'fof4',
'ts',
'pts',
'atten',
'preamp',
'rsvd',
'rsvd',
'service',
'special',
],
);
my %supported = ();
foreach my $key (keys %default_addr) {$supported{$default_addr{$key}} = $key;}
my $preamble = 'FEFE';
my $model = R7000;
my %state_save = ();
my %state_init = (
'state' => '',
'mode'  => '',
'atten' => -1,
'preamp' => -1,
'igrp' => -1,
'cmd'   => '',
'sig'   => FALSE,
'freq'  => 0,
'ctcss_flag' => -1,
);
foreach my $key (keys %state_init) {$state_save{$key} = $state_init{$key};}
my %rssi2sig = (
&ICR30 => [0,1,33,67,101,135,169,203,237,254 ],
&IC703 => [0,1,22,49, 75,101,130,169,211,255 ],
&IC705 => [0,8,33,62, 91,120,138,160,199,232 ],
&R8600 => [0,8,33,02, 91,120,138,160,199,232 ],
);
my %sig2meter = (
&IC705 => [0,1,19,33,48,63,76,91,106,120,138,160,178,199,218,242,255],
&R8600 => [0,1,19,33,48,63,76,91,106,120,138,160,178,199,218,242,255],
&ICR30 => [0,1,16,33,67,84,84,101,118,135,152,169,186,203,220,237,255],
);
my @sigmeter = (0,1,2,3,4,5,6,7,8,9,15,20,30,40,50,60,60);
my %step_code  = (
&ICR30 => [
10,
100,
1000,
3125,
5000,
6250,
8330,
9000,
10000,
12500,
15000,
20000,
25000,
30000,
50000,
100000,
125000,
200000,
],
&IC703 =>  [
10,
100,
1000,
5000,
9000,
10000,
12500,
20000,
25000,
100000,
]
);
my %scancodes = ('all'      => '00',
'band'     => '01',
'plink'    => '02',
'pgm'      => '03',
'memory'   => '04',
'mode'     => '05',
'near'     => '06',
'link'     => '07',
'group'    => '08',
'dup'      => '09',
'tone'     => '10',
);
my $default_scan = 'link';
my @send_packet;
my $instr;
my $freqbytes = 5;
my $getmemsize = 40;
my @icom_packet ;
my $warn = TRUE ;
my $protoname = 'icom';
use constant PROTO_NUMBER => 2;
$radio_routine{$protoname} = \&icom_cmd;
$valid_protocols{'icom'} = TRUE;
my %sd_format = (
&ICR30 => [
{'Group No'         => 'icomgroup'},
{'Group Name'       => 'groupname'},
{'CH No'            => 'icomch'},
{'Name'             => 'service'},
{'Frequency'        => 'freqmhz'},
{'DUP'              => 'dup'},
{'Offset'           => 'off_zero'},
{'TS'               => 'step'},
{'Mode'             => 'mode'},
{'RF Gain'          => 'gain'},
{'SKIP'             => 'skip'},
{'Tone'             => 'ttype'},
{'TSQL Frequency'   => 'ctcss'},
{'DTCS Code'        => 'dcs'},
{'DTCS Polarity'    => 'polarity'},
{'VSC'              => 'vsc'},
{'DV SQL'           => 'dvsql'},
{'DV CSQL'          => 'dvcode'},
{'P25 SQL'          => 'p25sql'},
{'P25 NAC'          => 'p25nac'},
{'dMPR SQL'         => ''},
{'dPMR Common ID'   => ''},
{'dPMR CC'          => ''},
{'dPMR Scrambler'   => ''},
{'dPMR Scrambler Key' => ''},
{'NXDN SQL'         => 'nxdnsql'},
{'NXDN RAN'         => 'nxdnran'},
{'NXDN Encryption'  => 'nxdnenc'},
{'NXDN Encryption Key' => 'nxdnkey'},
{'DCR SQL'          => ''},
{'DCR UC'           => ''},
{'DCR Encryption'   => ''},
{'DCR Encryption Key' => ''},
{'Position'         => 'position'},
{'Latitude'         => 'lat'},
{'Longitude'        => 'lon'},
],
&IC705 => [
{'Group No'         => 'icomgroup'},
{'Group Name'       => 'groupname'},
{'CH No'            => 'icomch'},
{'Name'             => 'service'},
{'SEL'              => 'select'},
{'Frequency'        => 'freqmhz'},
{'DUP'              => 'off'},
{'Offset'           => 'off_zero'},
{'Mode'             => 'mode'},
{'DATA'             => 'data'},
{'Filter'           => 'bw'},
{'TONE'             => 'ttype'},## OFF/TSQL/DTCS/TONE
{'Repeater Tone'    => 'rptr'},
{'TSQL Frequency'   => 'ctcss'},
{'DTCS Code'        => 'dcs'},
{'DTCS Polarity'    => '5polarity',},
{'DV SQL'           => 'dvsql'},
{'DV CSQL Code'     => 'dvcode'},
{'Your Call Sign'   => ''},
{'RPT1 Call Sign'   => ''},
{'RPT2 Call Sign'   => ''},
{'Split'            => 'split'},
{'Frequency(2)'     => 'sfreq'},
{'Dup(2)'           => 'off'},
{'Offset(2)'        => 'off_zero'},
{'Mode(2)'          => 'mode'},
{'DATA(2)'          => 'sdata'},
{'Filter(2)'        => 'bw'},
{'TONE(2)'          => 'sttype'},
{'Repeater Tone(2)' => 'srptr'},## xx.xHz, where 'xx.x' is the tone
{'TSQL Frequency(2)'=> 'sctcss'},
{'DTCS Code(2)'     => 'sdcs'},
{'DTCS Polarity(2)' => 'spolarity'},## For now, defaults to 'BOTH N'
{'DV SQL(2)'        => ''},
{'DV CSQL Code(2)'  => ''},
{'Your Call Sign(2)' => ''},
{'RPT1 Call Sign(2)' => ''},
{'RPT2 Call Sign(2)'=> ''},
],
);
my $chanper = 100;
my $debug_count = 0;
TRUE;
sub icom_cmd {
my $cmd = shift @_;
my $parmref = shift @_;
my $defref    = $parmref->{'def'};
my $out   = $parmref->{'out'};
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
if ($Debug2) {DebugIt("ICOM_CMD l2468: call cmd=$cmd");}
my $compaddr = '00';
my $radioaddr = '08';
if (defined $defref->{'radioaddr'}) {$radioaddr = uc($defref->{'radioaddr'});}
$getmemsize = 40;
my $delay = '1000';
$delay = '1';
my $sendhex = "$preamble$radioaddr$compaddr";
my $cmdcode = '00';
my $ack = 0;
my $rc = 0;
$parmref->{'rc'} = $GoodCode;
if (defined $icom_commands{$cmd}) {
$cmdcode = $icom_commands{$cmd}{'code'};
$sendhex = "$sendhex$cmdcode";
$ack = $icom_commands{$cmd}{'ack'};
}
if ($cmd eq 'init') {
if ($Debug1) {DebugIt("ICOM_CMD:Starting 'init' command");}
foreach my $key (keys %state_init) {$state_save{$key} = $state_init{$key};}
$model = uc($defref->{'model'});
if ($Debug1) {DebugIt("ICOM l2578: Model selected=>$model");}
$defref->{'model'} = $model;
if ($model !~ /R7000/i) {### Don't do this for the R7000
my $rc = icom_cmd('_get_id',$parmref);
if ($rc) {
if ($rc == $NotForModel) {
LogIt(1,"ICOM l2566:Could not get model from Radio. Set to R7000");
$model = R7000;
}
else {
LogIt(1,"ICOM l2571:get_id failed rc=>$rc for $model\n" .
"   sent=>$parmref->{'sent'}");
return ($parmref->{'rc'} = $CommErr);
}
}### Bad return from '_get_id'
else {
if ($Debug1) {DebugIt("ICOM l2317:GET_ID returned:$model");}
}
}
if ($model eq R7000) {
@gui_modestring = ('WFM','FM','AM','LSB');
@gui_bandwidth = ();
@gui_adtype = ();
@gui_attstring = ();
@gui_tonestring = ();
}
elsif ($model eq IC703) {
icom_cmd('_get_range',$parmref);
if ($out->{'minfreq'}) {
$radio_limits{$model}{'minfreq'} = $out->{'minfreq'};
}
else {LogIt(1,"IC-703 did NOT return low range!");}
if ($out->{'maxfreq'}) {
$radio_limits{$model}{'maxfreq'} = $out->{'maxfreq'};
}
else {LogIt(1,"IC-703 did NOT return high range!");}
@gui_modestring = ('FM','AM','LSB','USB','CW','RTTY','CW-R','RTTY-R');
@gui_bandwidth = ('(none)','Wide','Narrow');
@gui_adtype = ();
@gui_tonestring = @ctctone;
@gui_attstring = @attstring;
}
elsif ($model eq ICR30) {
$parmref->{'write'} = FALSE;
icom_cmd('_op_state',$parmref);
icom_cmd('_get_scan_condition',$parmref);
if ($Debug1){
DebugIt("ICOM l2609:R30 is in state: $out->{'state'} scanning: $out->{'scan'}");
}
@gui_modestring = ('FM','WFM','AM','LSB','USB','CW','CW-R');
@gui_bandwidth = ('(none)','Wide','Narrow');
@gui_adtype = ('ANALOG','P25','NXDN','VN-NXDN','DSTAR');
@gui_attstring = @attstring;
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
}
elsif ($model eq R8600) {
@gui_modestring = ('FM','WFM','AM','LSB','USB','CW','CW-R','RTTY','RTTY-R');
@gui_bandwidth =  @bandwidthstring;
@gui_adtype = ('ANALOG','P25','NXDN','VN-NXDN','DSTAR');
@gui_attstring = @attstring;
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
}
elsif ($model eq IC7300) {
@gui_modestring = ('FM','AM','LSB','USB','CW','RTTY','CW-R','RTTY-R');
@gui_bandwidth = ('(none)','Wide','Medium','Narrow');
@gui_adtype = ();
@gui_attstring = @attstring;
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
}
else {
@gui_modestring = ('FM','WFM','AM','LSB','USB','CW','CW-R','RTTY','RTTY-R');
@gui_bandwidth = @bandwidthstring;
@gui_adtype = ();
@gui_attstring = @attstring;
@gui_tonestring = (@ctctone,@dcstone[1..$#dcstone]);  
}
foreach my $key (keys %{$radio_limits{$model}}) {
$defref->{$key} = $radio_limits{$model}{$key};
}
my $frq = 0;
my $atten = FALSE;
if (icom_cmd('_get_freq',$parmref)) {
return ($parmref->{'rc'} = $CommErr);
}
icom_cmd('_get_mode',$parmref);
if ($Debug2) {DebugIt("$Bold 'init' complete");}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'autobaud') {
if ($Debug1) {DebugIt("ICOM_CMD:Starting 'init' command");}
my $startstate = $progstate;
if (!$defref->{'model'}) {
LogIt(1,"Model number not specified in .CONF file. " .
" Cannot automatically determine port/baud");
return ($parmref->{'rc'} = 1);
}
LogIt(0,"Autobaud started for $defref->{'model'}");
my @allports = ();
if ($in->{'noport'} and $defref->{'port'}) {push @allports,$defref->{'port'};}
else {
if (lc($defref->{'model'}) ne  'r7000') {@allports = glob("/dev/ttyACM*");}
if (lc($defref->{'model'}) ne 'icr30') {push @allports,glob("/dev/ttyUSB*");}
}
my @allbauds = ();
if ($in->{'nobaud'}) {push @allbauds,$defref->{'baudrate'};}
else {push @allbauds,keys %baudrates;}
@allbauds = sort {$b <=> $a} @allbauds;
@allports = sort {$b cmp $a} @allports;
PORTLOOP:
foreach my $port (@allports) {
threads->yield;
if ($progstate ne $startstate) {
if ($Debug1) {
DebugIt("ICOM l2685:Exited loop as progstate changed");
}
last PORTLOOP;
}
if ($Debug3) {DebugIt("ICOM l2689:trying port $port progstate=$progstate");}
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
threads->yield;
if ($progstate ne $startstate) {
if ($Debug1) {
DebugIt("ICOM l2707:Exited loop as progstate changed");
}
last PORTLOOP;
}
if ($Debug3) {DebugIt("ICOM l2712:trying baud $baud progstate=$progstate");}
$portobj->baudrate($baud);
$warn = FALSE;
$rc = icom_cmd('_get_freq',$parmref);
$warn = TRUE;
if (!$rc) {### command succeeded
$defref->{'baudrate'} = $baud;
$defref->{'port'} = $port;
$defref->{'handshake'} = 'none';
$portobj->close;
$parmref->{'portobj'} = undef;
LogIt(0,"ICOM $defref->{'model'} detected on port $port with baudrate $baud");
return ($parmref->{'rc'} = $GoodCode);
}
else {
if ($Debug3) {DebugIt(" Baudrate/port did not work");}
}
}
$portobj->close;
$parmref->{'portobj'} = undef;
}## All ports
return ($parmref->{'rc'} = 1);
}### Autobaud
elsif ($cmd eq 'manual' ) {
LogIt(0,"$Bold ICOM_CMD l2849:Starting 'manual' command");
$state_save{'cmd'} = $cmd;
if ($model eq ICR30) {
icom_cmd('_cancel_scan',$parmref);
$parmref->{'write'} = FALSE;
icom_cmd('_op_state',$parmref);
}
elsif (($model eq IC703) ) {
icom_cmd('_select_vfoa',$parmref);
}
else {
icom_cmd('_stop_scan',$parmref);
}
icom_cmd('_get_freq',$parmref);
icom_cmd('_get_mode',$parmref);
usleep(300);
$state_save{'igrp'} = $state_init{'igrp'};
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'vfoinit') {
if ($Debug1) {DebugIt("ICOM_CMD:Starting 'vfoinit' command");}
$state_save{'cmd'} = $cmd;
if ($model eq ICR30) {
icom_cmd('_cancel_scan',$parmref);
$parmref->{'write'} = TRUE;
$in->{'state'} = 'vfo';
icom_cmd('_op_state',$parmref);
$in->{'dual'} = FALSE;
icom_cmd('_dply_type',$parmref);
icom_cmd('_select_aband',$parmref);
}
elsif ($model eq IC703) {
icom_cmd('_select_vfoa',$parmref);
}
else {
icom_cmd('_stop_scan',$parmref);
}
icom_cmd('_get_freq',$parmref);
icom_cmd('_get_mode',$parmref);
$state_save{'igrp'} = $state_init{'igrp'};
if ($Debug1) {DebugIt("ICOM l2802:VFO setup complete");}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'meminit') {
if ($Debug1) {DebugIt("ICOM_CMD:Starting 'meminit' command");}
$state_save{'cmd'} = $cmd;
$out->{'igrp'} = 0;
if ($model eq ICR30) {
$parmref->{'write'} = TRUE;
$in->{'state'} = 'mem';
icom_cmd('_op_state',$parmref);
get_r30_display($parmref);
}
else {
icom_cmd('_memory_state',$parmref);
icom_cmd('_get_freq',$parmref);
icom_cmd('_get_mode',$parmref);
}
$state_save{'igrp'} = $state_init{'igrp'};
if ($Debug1) {DebugIt("ICOM l2841:VFO setup complete");}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getinfo') {
if ($Debug1) {DebugIt("ICOM_CMD:Starting 'getinfo' command");}
icom_cmd('init',$parmref);
$out->{'chan_count'} = $defref->{'maxchan'};
$out->{'model'} = $model;
return ($parmref->{'rc'});
}
elsif ($cmd eq 'getmem') {
if ($Debug1) {DebugIt("ICOM_CMD:Starting 'getmem' command");}
$state_save{'cmd'} = $cmd;
my $startstate = $progstate;
my $maxcount = $defref->{'maxchan'};
my $maxchan = $defref->{'maxchan'};
my $channel =  $defref->{'origin'};
my $hasgroups = $defref->{'group'};
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
$parmref->{'_ignore'} = FALSE;
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
my %sysrec = ('systemtype' => 'CNV','service' => "ICOM model $model", 'valid' => TRUE);
$sysno = add_a_record($db,'system',\%sysrec,$parmref->{'gui'});
}
my $igrp = 0;
my $grpndx = 0;
my $restore_state = $state_save{'state'};
my $restore_scan = $state_save{'scan'};
if ($model eq ICR30) {
$parmref->{'write'} = FALSE;
icom_cmd('_op_state',$parmref);
$restore_state = $myout{'state'};
icom_cmd('_get_scan_condition',$parmref);
$restore_scan = $myout{'scan'};
if ($restore_state ne 'mem') {
$myin{'state'} = 'mem';
$parmref->{'write'} = TRUE;
my $msg = "ICOM_CMD l3058:ICOM $model cannot set MEMORY state";
if (icom_cmd('_op_state',$parmref)) {
LogIt(1,$msg);
add_message($msg);
return ($parmref->{'rc'} = $NotForModel);
}
$parmref->{'write'} = FALSE;
icom_cmd('_op_state',$parmref);
if ($myout{'state'} ne 'mem') {
LogIt(1,$msg);
add_message($msg);
return ($parmref->{'rc'} = $NotForModel);
}
}
}### ICR30 needs memory state
CHANLOOP:
while ($channel <= $maxchan) {
if (!$grpndx) {
my %grouprec = ('sysno' =>$sysno,
'service' => "ICOM $model Group:$igrp",
'valid' => TRUE
);
$grpndx = add_a_record($db,'group',\%grouprec,$parmref->{'gui'});
$igrp++;
}### New group creation
$vfo{'channel'} = $channel;
$vfo{'groupno'} = $grpndx;
threads->yield;
if ($progstate ne $startstate) {
if ($Debug2) {DebugIt("Exited loop as progstate changed");}
last CHANLOOP;
}
if (!$parmref->{'gui'}) {
print STDERR "\rReading channel:$Bold$Green" . sprintf("%04.4u",$channel) . $Reset ;
}
;
$myout{'valid'} = TRUE;
$myout{'mode'} = 'fmn';
$myout{'frequency'} = 0;
$myout{'sqtone'} = 'Off';
$myout{'spltone'} = 'Off';
$myout{'service'} = '';
$myout{'tgid_valid'} = FALSE;
$myout{'atten'} = 0;
$myout{'preamp'} = 0;
$myout{'channel'} = $channel;
$myout{'dlyrsm'} = 0 ;
$myout{'groupno'} = $grpndx;
$myout{'splfreq'} = '';
$myin{'channel'} = $channel;
$myin{'chan_extra'} = 0;
$myin{'group_extra'} = 0;
my $rc = 0;
if ($nodup and $duplist{$channel}) {
if ($Debug2) {DebugIt("bypassing channel $channel due to duplicate");}
}
else {
if ($model eq ICR30) {
$rc = icom_cmd('_select_group',$parmref);
if ($rc) {
my $msg = "ICOM_CMD l3181:Cannot set group for model $model!";
LogIt(1,$msg);
add_message($msg);
return ($parmref->{'rc'} = $NotForModel);
}
$rc = icom_cmd('_select_chan',$parmref);
if (!$rc) {get_r30_display($parmref);}
}### IC-R30
elsif (defined $direct_format{$model}) {
$rc =  $rc = icom_cmd('_memory_direct',$parmref);
}
else {
$parmref->{'_ignore'} = TRUE;
icom_cmd('_select_group',$parmref);
$parmref->{'_ignore'} = FALSE;
$rc = icom_cmd('_select_chan',$parmref);
if (!$rc) {$rc = icom_cmd('_get_freq',$parmref);}
if (!$rc) {$rc = icom_cmd('_get_mode',$parmref);}
vfo_get_tones($in,$out,$parmref);
$parmref->{'_ignore'} = FALSE;
}
my $freq = $myout{'frequency'} + 0;
if ($noskip or $freq) {
if (!$freq) {$myout{'valid'} = FALSE;}
my $recno = add_a_record($db,'freq',\%myout,$parmref->{'gui'});
$vfo{'index'} = $recno;
$count++;
if ($count >= $maxcount) {last CHANLOOP;}
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
}### GETMEM
elsif ($cmd eq 'setmem') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'setmem' command");}
if ($model eq ICR30) {return $NotForModel;}
my $max_count = 99999;
my $options = $parmref->{'options'};
if ($options->{'count'}) {$max_count = $options->{'count'};}
my %found_chan = ();
my $count = 0;
my %in = ();
$parmref->{'in'} = \%in;
foreach my $frqrec (@{$db->{'freq'}}) {
if (!$frqrec->{'index'}) {next;}
my $recno = $frqrec->{'_recno'};
if (!$recno) {$recno = '??';}
my $emsg = "in record $recno";
if ($frqrec->{'tgid_valid'}) {next;}
my $channel = $frqrec->{'channel'};
if ((!looks_like_number($channel)) or ($channel < 0) ) {
print STDERR "\nChannel number $emsg is not defined. Skipped";
next;
}
if (($channel < $defref->{'origin'}) or ($channel > $defref->{'maxchan'})) {
print STDERR "\nChannel number $channel $emsg is not within range of radio. Skipped\n";
next;
}
if ($found_chan{$channel}) {
print STDERR "\n";
LogIt(1,"\nChannel $channel was found twice $emsg. Second iteration skipped!");
next;
}
$found_chan{$channel} = TRUE;
my $freq = $frqrec->{'frequency'};
if (!looks_like_number($freq)) {next;}
if ($freq and (!check_range($freq,\%{$radio_limits{$model}}))) {next;}
my $grpno = $frqrec->{'groupno'};
foreach my $mdl ('705','8600') {
if ($model =~ /$mdl/) {  
my $grp_mdl = "scan$mdl";
if ($frqrec->{$grp_mdl}) {
}
elsif ($frqrec->{'scangrp'}) {
}
elsif ($grpno and $db->{'group'}[$grpno]{$grp_mdl}) {
$frqrec->{$grp_mdl} = $db->{'group'}[$grpno]{$grp_mdl};
}
elsif ($grpno and $db->{'group'}[$grpno]{'scangrp'}) {
$frqrec->{'scangrp'} = $db->{'group'}[$grpno]{'scangrp'};
}
}### Model we are interested in
}### For each $mdl
print STDERR "\rSETMEM: Writing channel $Bold$Green",
sprintf("%04.4u",$channel), $Reset,
" freq=>$Yellow",rc_to_freq($freq),$Reset;
%in = ();
foreach my $key (keys %{$frqrec}) {
$in{$key} = $frqrec->{$key};
}
my $rc = 0;
if (defined $direct_format{$model}) {
$in->{'chan_extra'} = 0;
$in->{'group_extra'} = 0;
$parmref->{'write'} = TRUE;
$rc = icom_cmd('_memory_direct',$parmref);
}
else {
$parmref->{'_ignore'} = TRUE;
icom_cmd('_select_group',$parmref);
$parmref->{'_ignore'} = FALSE;
$rc = icom_cmd('_select_chan',$parmref);
if ($rc) {
LogIt(1,"\nCould not set radio to channel $channel");
next;
}
usleep 500;
if ($freq) {
$rc = icom_cmd('_set_freq',$parmref);
usleep 500;
if (!$rc) {$rc = icom_cmd('_set_mode',$parmref);}
vfo_tone_squelch($parmref);
usleep 500;
if (!$rc) {$rc = icom_cmd('_vfo_to_mem',$parmref);}
}
else {
$rc = icom_cmd('_clear_mem',$parmref);
}
}### All other radios
if (!$rc) {$count++;}
if ($count >= $max_count) {
print STDERR "$Eol$Bold Store terminated due to maximum record count reached$Eol";
last;
}
}### Frequency record process
print STDERR "$Eol$Bold$Green$count$White Records stored.$Eol";
return 0;
}### Setmem
elsif ($cmd eq 'selmem') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'selmem' command");}
$state_save{'cmd'} = $cmd;
if (!defined $in->{'channel'}) {
LogIt(1,"ICOM l3484:No 'channel' in 'in' for SELMEM!");
return ($parmref->{'rc'} = $ParmErr);
}
my $channel = $in->{'channel'};
if (!looks_like_number($channel)) {### bad parameter
add_message("ICOM l3211:Channel $channel is not numeric.");
return ($parmref->{'rc'} = $ParmErr);
}
if (($channel > $defref->{'maxchan'}) or ($channel < $defref->{'origin'})) {
add_message("ICOM l3223:channel/group $channel is outside range of the radio");
return ($parmref->{'rc'} = $NotForModel);
}
my $retcode = $GoodCode;
if  (!$state_save{'state'} ne 'mem'){
if ($model eq ICR30) {
$in->{'state'} = 'mem';
$parmref->{'write'} = TRUE;
icom_cmd('_op_state',$parmref);
}
elsif  ($model ne R7000) {icom_cmd('_memory_state',$parmref);}
else {
}
}### Radio NOT in memory state
if ($defref->{'group'}) {### Radio supports groups
if (icom_cmd("_select_group",$parmref)) {
add_message("ICOM could not select group for channel $channel");
return ($parmref->{'rc'} = $ParmErr);
}
usleep(500);
}
$parmref->{'write'} = FALSE;
$in->{'caller'} = 'selmem';
if (icom_cmd('_select_chan',$parmref)) {
LogIt(1,"ICOM:l3538:could not select channel $in->{'channel'}");
add_message("ICOM could not select channel $in->{'channel'}");
return ($parmref->{'rc'} = $ParmErr);
}
$out->{'_delay'} = 3000;
if ($model eq ICR30) {
$out->{'_delay'} =  40000;
}
return ($parmref->{'rc'});
}
elsif ($cmd eq 'getvfo') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'getvfo' command");}
$state_save{'cmd'} = $cmd;
if (icom_cmd('_get_freq',$parmref)) {
return $parmref->{'rc'};
}
if ($out->{'frequency'}) {
if (icom_cmd('_get_mode',$parmref)) {
return $parmref->{'rc'};
}
$parmref->{'write'} = FALSE;
$parmref->{'_ignore'} = TRUE;
icom_cmd('_vfo_atten',$parmref);
icom_cmd('_vfo_preamp',$parmref);
if ($out->{'mode'} =~ /fm/i) {
vfo_get_tones($in,$out,$parmref);
}### FM modulation detected
$parmref->{'_ignore'} = FALSE;
}### A frequency is set
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'setvfo') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'setvfo' command");}
$state_save{'cmd'} = $cmd;
my $freq = $in->{'frequency'};
if (!looks_like_number($freq)) {$freq = 0;}
if (!$freq) {
add_message("VFO cannot have a 0 frequency");
return ($parmref->{'rc'} = $ParmErr);
}
if (!check_range($freq,\%{$radio_limits{$model}})) {
add_message(rc_to_freq($freq) . " MHz is NOT valid for this radio");
return ($parmref->{'rc'} = $NotForModel);
}
if (!$in->{'mode'}) {
add_message("ICOM routine detected empty 'mode'. Changed to 'AUTO'");
$in->{'mode'} = 'auto';
}
if ($state_save{'state'} !~ /vfo/i) {
if ($model eq ICR30) {
$in->{'state'} = 'vfo';
$parmref->{'write'} = TRUE;
icom_cmd('_op_state',$parmref);
}
elsif ($model eq R7000) {
}
elsif ($model eq IC705) {
}
else {
icom_cmd('_vfo_state',$parmref);
}
}
$state_save{'igrp'} = $state_init{'igrp'};
if (icom_cmd('_set_freq',$parmref)) {return $parmref->{'rc'}};
if (icom_cmd('_set_mode',$parmref)) {return $parmref->{'rc'}};
$parmref->{'_ignore'} = TRUE;
my $att = $in->{'atten'};
if (!$att) {$att = 0;}
my $pamp = $in->{'preamp'};
if (!$pamp) {$pamp = 0;}
if ($att) {$pamp = 0;}
$in->{'atten'} = $att;
$in->{'preamp'} = $pamp;
$parmref->{'write'} = TRUE;
icom_cmd("_vfo_atten",$parmref);
icom_cmd('_vfo_preamp',$parmref);
vfo_set_tones($parmref);
$parmref->{'_ignore'} = FALSE;
$out->{'_delay'} = 1000;
if ($model eq ICR30) {  $out->{'_delay'}  = 39000;}
elsif ($model eq IC705) {$out->{'_delay'} = 3000;}
icom_cmd('poll',$parmref);
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getglob') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'getglob' command");}
$state_save{'cmd'} = $cmd;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'setglob') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'setglob' command");}
$state_save{'cmd'} = $cmd;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'getsrch') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'getsrch' command");}
return $NotForModel;
}### GETSRCH
elsif ($cmd eq 'setsrch') {
if ($Debug2) {DebugIt("ICOM_CMD:Starting 'setsrch' command");}
return $NotForModel;
}### SETSRCH
elsif ($cmd eq 'getsig') {
if ($Debug3) {DebugIt("ICOM_CMD:Starting 'getsig' command");}
$out->{'signal'} = 0;
$out->{'sql'} = FALSE;
$out->{'rssi'} = 0;
my $udelay = 100;
$rc = $GoodCode;
my $tries = 0;
if ($model eq R7000) {
icom_cmd('poll',$parmref);
return ($parmref->{'rc'});
}### R7000 section
elsif ($model eq ICR30) {
icom_cmd('_get_tone_squelch',$parmref);
if ($out->{'sql'}) {
get_r30_display($parmref);
if (!$out->{'service'}) {$out->{'service'} = '.';}
icom_cmd('_get_signal',$parmref);
}
return ($parmref->{'rc'} = $rc);
}### ICR30
elsif ($model eq IC703) {
icom_cmd('_get_squelch',$parmref);
}### IC703
else {
icom_cmd('_get_tone_squelch',$parmref);
}
if ($out->{'sql'}) {
icom_cmd('_get_signal',$parmref);
if (!$out->{'signal'}) {$out->{'signal'} = 1;}
if ($Debug3) {Debugit("ICOM l4225: sql broken, signal=>$out->{'signal'}");}
icom_cmd('_get_freq',$parmref);
icom_cmd('_get_mode',$parmref);
$out->{'service'} = '';
}### got a signal
else {
if ($progstate eq 'manual') {
$rc = icom_cmd('_get_freq',$parmref);
if ( !$rc and ($out->{'frequency'})) {
$vfo{'frequency'} = $out->{'frequency'};
$rc = icom_cmd('_get_mode',$parmref);
$vfo{'mode'} = $out->{'mode'};
}
}### Manual state
}
$state_save{'cmd'} = $cmd;
return ($parmref->{'rc'} = $rc);
}### GETSIG process
elsif ($cmd eq 'scan') {
if ($model eq ICR30) {
$in->{'state'} = 'mem';
$parmref->{'write'} = TRUE;
if (icom_cmd('_op_state',$parmref)) {
LogIt(1,"ICOM_CMD l2881:Cannot set op_state");
add_message("ICOM ICR30 cannot set op_state");
return ($parmref->{'rc'} = $NotForModel);
}
$in->{'scan_type'} = $default_scan;
if(icom_cmd('_start_a_scan',$parmref)) {
LogIt(1,"ICOM_CMD l2887:Cannot start scan");
add_message("ICOM ICR30 cannot start scan");
return ($parmref->{'rc'} = $NotForModel);
}
}
elsif ($model eq R7000) {
LogIt(1,"ICOM l3791: Scan not supported on model $model!");
add_message("ICOM model $model does not support radio scan");
return ($parmref->{'rc'} = $NotForModel);
}
elsif (($model eq IC705) or ($model eq R8600)) {
if(icom_cmd('_select_scan',$parmref)) {
LogIt(1,"ICOM_CMD l4321:Cannot start scan");
add_message("ICOM cannot start scan");
return ($parmref->{'rc'} = $NotForModel);
}
}
else {
if(icom_cmd('_memory_scan',$parmref)) {
LogIt(1,"ICOM_CMD l4330:Cannot start scan");
add_message("ICOM cannot start scan");
return ($parmref->{'rc'} = $NotForModel);
}
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmd eq 'test') {
$ack = 1;
$sendhex = $in->{'_test'};
if ($Debug3) {DebugIt("TEST command will send=>$sendhex");}
}
elsif ($cmd eq 'poll') {
$sendhex = '';
}
elsif ($cmd eq '_set_freq_noack') {
$sendhex = "$sendhex" .
num2bcd($in->{"frequency"} + 0,$freqbytes,TRUE );
}
elsif ($cmd eq '_set_mode_noack')    {
my ($modecode) =  rcmode2icom($in,$model);
$sendhex = "$sendhex$modecode";
}
elsif ($cmd eq '_get_range')    {  }
elsif ($cmd eq '_get_freq') { }
elsif ($cmd eq '_get_mode' ) { }
elsif ($cmd eq '_set_freq')     {
if (!defined $in ->{'frequency'}) {
LogIt(1384,"ICOM_CMD: No 'frequency' in out for cmd $cmd");
}
KeyVerify($in ,'frequency');
my $freq = $in ->{'frequency'} + 0;
if (!$freq) {$freq = 0;}
$sendhex = "$sendhex" . num2bcd($freq,$freqbytes,TRUE );
$state_save{'freq'} = $freq;
}
elsif ($cmd eq '_set_mode' ) {
KeyVerify($in ,'mode');
my $mode = $in->{'mode'};
if (!$mode) {$mode = 'fmn';}
my ($modecode) =  rcmode2icom($in,$model);
$sendhex = "$sendhex$modecode";
if ($mode !~ /auto/i) {
$state_save{'mode'} = $mode;
}
}
elsif ($cmd eq '_vfo_state')  {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_select_vfoa') {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_select_vfob') {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_equalize_vfo') {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_swap_vfo') {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_select_aband') {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_select_bband') {
$state_save{'state'} = 'vfo';
}
elsif ($cmd eq '_memory_state')     {
$state_save{'state'} = 'mem';
}
elsif ($cmd eq '_select_chan')     {
my $chan = $in ->{'channel'};
if (!looks_like_number($chan) or ($chan < 0) or ($chan > 9999)) {
return ($parmref->{'rc'} = $ParmErr);
}
my $len = 2;
if ($model eq R7000) {
if (($chan < 1) or ($chan > 99)) {
return ($parmref->{'rc'} = $ParmErr);
}
$len = 1;
}
else {$state_save{'state'} = 'mem';}
my $chfmt = sprintf("%04.4i",$chan);
my $igrp = substr($chfmt,0,2);
my $ch = substr($chfmt,2,2);
$state_save{'freq'} = '';
$state_save{'mode'} = '';
$sendhex = $sendhex . num2bcd($ch,$len,FALSE);
}
elsif ($cmd eq '_select_group')  {
my $chan = $in->{'channel'};
if (!looks_like_number($chan) or ($chan < 0) or ($chan > 9999)) {
return ($parmref->{'rc'} = $ParmErr);
}
my $chfmt = sprintf("%04.4i",$chan);
my $igrp = substr($chfmt,0,2);
my $ch = substr($chfmt,2,2);
$state_save{'igrp'} = $igrp;
$sendhex = $sendhex . num2bcd($igrp,2,FALSE);
}
elsif ($cmd eq '_vfo_to_mem')     { }
elsif ($cmd eq '_mem_to_vfo')     { }
elsif ($cmd eq '_clear_mem')     { }
elsif ($cmd eq '_stop_scan') {
print "ICOM line 4741 _stop_scan => $sendhex\n";
}
elsif ($cmd eq '_memory_scan')  { }
elsif ($cmd eq '_select_scan')  { }
elsif ($cmd eq '_split_off')  { }
elsif ($cmd eq '_split_on' )  { }
elsif ($cmd eq '_vfo_step') {
if (!defined $step_code{$model}[0]) {
add_message("ICOM_CMD: STEP setting is not defined for $model");
return ($parmref->{'rc'} = $NotForModel);
}
if ($parmref->{'write'}) {
my $step = $in ->{'step'};
if (!$step) {
$step = 5000;
LogIt(1,"ICOM_CMD:Step=0 detected. Changed to 5khz");
}
elsif (lc($step) eq 'auto') {$step = 5000;}
elsif (!looks_like_number($step)) {
LogIt(1,"ICOM_CMD:Step=$step is NOT valid number. Changed to 5khz");
$step = 5000;
}
my $sendhex  = $sendhex . rctostepbcd($step);
}
}
elsif ($cmd eq '_vfo_atten') {
if ($parmref->{'write'}) {
my $att = '00';
if ($in ->{'atten'}) {
$att = '20';
if ($model eq ICR30) {$att = '15';}
elsif ($model eq R8600) {$att = '10';}
}
$sendhex = "$sendhex$att";
if ((defined $state_save{'atten'}) and ($att == $state_save{'atten'})) {
return ($parmref->{'rc'} = $GoodCode);
}
$state_save{'atten'} = $att;
}
}
elsif ($cmd eq '_rf_gain') {
if ($parmref->{'write'}) {
my $parm = sprintf("%04d",$in->{'rfgain_v'});
$sendhex = "$sendhex$parm";
}
}
elsif ($cmd eq '_get_squelch')     { }
elsif ($cmd eq '_get_tone_squelch')     { }
elsif ($cmd eq '_get_signal')     { }
elsif ($cmd eq '_vfo_preamp') {
if ($parmref->{'write'}) {
my $preamp = '00';
if ($in ->{'preamp'}) {$preamp = '01';}
$sendhex = "$sendhex$preamp";
if ((defined $state_save{'preamp'}) and ($preamp eq $state_save{'preamp'})) {
return ($parmref->{'rc'} = $GoodCode);
}
$state_save{'preamp'} = $preamp;
}
}
elsif ($cmd eq '_vfo_repeater_state') {
if ($parmref->{'write'}) {
my $rptr = '00';
if ($in->{'_tone_state'}) {$rptr = '01';}
$sendhex = "$sendhex$rptr";
}
}
elsif ($cmd eq '_vfo_ctc_state') {
if ($parmref->{'write'}) {
my $ctcss = '00';
if ($in->{'_tone_state'}) {$ctcss = '01';}
$state_save{'ctcss_flag'} = $ctcss;
$sendhex = "$sendhex$ctcss";
}
}
elsif ($cmd eq '_vfo_dcs_state') {
if ($parmref->{'write'}) {
my $dtcs = '00';
if ($in->{'_tone_state'}) {$dtcs = '01';}
$state_save{'dcs_flag'} = $dtcs;
$sendhex = "$sendhex$dtcs";
}
}
elsif ($cmd eq '_dply_type') {
if ($parmref->{'write'}) {
my $parm = '00';
if ($in->{'dual'}) {$parm = '01';}
$sendhex = "$sendhex$parm";
}
}
elsif ($cmd eq '_nxdn_encrypt') {
if ($parmref->{'write'}) {
my $parm = '00';
if ($in->{'nxdncrypt'}) {$parm = '01';}
$sendhex = "$sendhex$parm";
}
}
elsif ($cmd eq '_vfo_ran_value') {
if ($parmref->{'write'}) {
my $parm = sprintf("%02d",$in->{'_tone'});
$sendhex = "$sendhex$parm";
}
}
elsif ($cmd eq '_vfo_crypt_key') {
if ($parmref->{'write'}) {
my $parm = sprintf("%06d",$in->{'enc'});
$sendhex = "$sendhex$parm";
}
}
elsif ($cmd eq '_get_id')     { }
elsif ($cmd eq '_memory_direct') {
if ($Debug2) {DebugIt("ICOM l5122:Preprocessing '_memory_direct'");}
my $channel = $in->{'channel'};
my $chfmt = sprintf("%04.4i",$channel);
my $igrp = substr($chfmt,0,2);
my $chan = substr($chfmt,2,2);
if ($in->{'chan_extra'}) {$chan = $chan + $in->{'chan_extra'};}
if ($in->{'group_extra'}) {$igrp = $igrp + $in->{'group_extra'};}
my $mdl = $model;
if (!defined $direct_format{$mdl}) {$mdl = OTHER;}
my $fmt = $direct_format{$mdl};
my $skip_flag = 0;
my $split_flag = 0;
my $select_flag = 0;
my %data = (
'igrp'      => sprintf("%04u",$igrp),
'chan'      => sprintf("%04u",$chan),
'split'     => '00',
'flag1'     => '00',
'select'    => '00',
'tt1'       => '00',
'tt2'       => '00',
'tt3'       => '00',
'stt1'      => '00',
'stt2'      => '00',
'atten'     => '00',
'preamp'    => '00',
'frequency' => '0000000000',
'sfreq'     => '0000000000',
'mode'      => '0502',
'smode'     => '0502',
'ctc'       => '0885',
'rpt'       => '0885',
'dcs'       => '0023',
'sctc'      => '0885',
'srpt'      => '0885',
'sdcs'      => '0023',
'fof'       => '000000',
'sfof'      => '000000',
'fof4'      => '00000000',
'ts'        => '0005',
'pts'       => '0004',
'service'   => '202020202020202020202020202020',
'special'   => '',
'test'      => 'FF',
'rsvd'      => '00',
'duplex'    => '00',
'sduplex'   => '00',
);
if ($parmref->{'write'}) {
if ($in->{'frequency'}) {
$data{'frequency'} =  num2bcd($in->{'frequency'},5,TRUE);
$data{'sfreq'} = $data{'frequency'};
$data{'mode'} = rcmode2icom($in,$mdl);
$data{'smode'} = $data{'mode'};
if ($in->{'preamp'}) {$data{'preamp'} = '01';}
if ($in->{'atten'}) {$data{'atten'} = '20';}
my $cs = uc(unpack("H*",'CQ      '));
foreach my $ky ('ur','r1','r2') {
$data{"callsign$ky"} = $cs;
}
my $count = $radio_limits{$mdl}{'serv_len'};
my $service = substr($in->{'service'} . (' ' x $count),0,$count);
$data{'service'} = uc(unpack("H*",$service));
if ($in->{'splfreq'}) {
my $split = $in->{'splfreq'};
if ($radio_limits{$mdl}{'split'}) {
$data{'sfreq'} =  num2bcd($split,5,TRUE);
$split_flag = 1;
}
else {
}
}### Offset process
my $mode = $in->{'mode'};
if ($mode =~ /fm/i) {
my $tt = 'Off';
my $tone = 0;
if ($in->{'sqtone'} ) {
($tt,$tone) = Tone_Xtract($in->{'sqtone'});
}
my $modecode = substr($data{'mode'},0,2) + 0;
if ($modecode == 16) {
if ($tt =~ /nac/i) {
$data{'special'} = '01';
my $dec = hex($tone);
my $nac = sprintf("%03.3x",$dec);
my @digits = split('',$nac);
foreach my $ch (@digits) {
$data{'special'} = $data{'special'} . '0' . $ch;
}
}
else {$data{'special'} = '00000000';}
}
elsif ($modecode == 17) {
if ($tt =~ /dsq/i) {
$data{'special'} = '02' . sprintf("%02.2i",$tone);
}
else {$data{'special'} = '0000';}
}
elsif (($modecode == 19) or ($modecode == 20) ){
if ($tt =~ /ran/i) {
$data{'special'} = '01' . sprintf("%02.2i",$tone);
}
else {$data{'special'} = '0000';}
my $encrypt = '00';
my $key = '000001';
if ($in->{'enc'}) {
$encrypt = '01';
$key = sprintf("%06.6i",$in->{'enc'});
}
$data{'special'} = $data{'special'} . $encrypt .$key;
}
elsif ($modecode > 9) {
}
else {
if ($tone) {
if ($tt =~ /rpt/i) {
$data{'tt1'} = '01';
$data{'tt2'} = '01';
$data{'rpt'} = tone2bcd($tone);
}
elsif ($tt =~ /ctc/i) {### CTCSS tone
$data{'tt1'} = '02';
$data{'tt2'} = '02';
$data{'ctc'} = tone2bcd($tone);
$data{'special'} = '0100' . $data{'ctc'} . '000023';
}
elsif ($tt =~ /dcs/i) {
my $pol = '00';
$data{'tt2'} = '03';
$data{'dcs'} = sprintf("%04.3u",$tone);
$data{'special'} = '02000885' . $pol . $data{'dcs'};
}
}### Analog tone available
else {
$data{'special'} = '00000885000023';
}
my $stt = '';
my $stone = 0;
if ($split_flag and $in->{'spltone'}) {
($stt,$stone) = Tone_Xtract($in->{'spltone'});
if ($tt =~ /rpt/i) {
$data{'stt1'} = '01';
$data{'stt2'} = '01';
$data{'srpt'} = tone2bcd($stone);
}
elsif ($stt =~ /ctc/i) {### CTCSS tone
$data{'stt1'} = '02';
$data{'stt2'} = '02';
$data{'sctc'} = tone2bcd($stone);
}
elsif ($stt = /dcs/i) {
my $pol = '00';
$data{'stt2'} = '03';
$data{'Sdcs'} = sprintf("%04.3u",$stone);
}
}
else {
$data{'stt1'} = $data{'tt1'};
$data{'stt2'} = $data{'tt2'};
$data{'sdcs'} = $data{'dcs'};
$data{'sctc'} = $data{'ctc'};
$data{'srpt'} = $data{'rpt'};
}
}#### Analog audio
}#### Modulation is Frequency Modulation
my $selection = '0';
if ($in->{'scangrp'}) {$selection = $in->{'scangrp'};}
if (($mdl =~ /705/i) and $in->{'scan705'}) {
$selection = $in->{'scan705'};
}
elsif ($in->{'scan8600'} and ($mdl =~ /8600/)) {
$selection = $in->{'scan8600'};
}
if ($selection > $radio_limits{$mdl}{'scangrp'})  {
$selection = 0;
}
if (looks_like_number($selection)) {$selection = $selection + 0;}
else {$selection = 0;}
$data{'split'} = "$split_flag$selection";
my $skip = '0';
if (!$in->{'valid'}) {$skip = '1';}
$data{'select'} = "$skip$selection";
my $bit6 = '0';
my $bit7 = '0';
if ($in->{'valid'}) {$bit6 = '1';}
if ($split_flag) {$bit7 = '1';}
my $hex = hex($bit7 + ($bit6 * 2));
$data{'flag1'} = sprintf("%02.2X",$hex);
}### Frequency is NOT 0
else {
foreach my $key (keys %data) {
if ($key =~ /chan/i) {next;}
elsif ($key =~ /igrp/i) {next;}
elsif ($key =~ /flag1/i) {$data{$key} = 'FF';} 
elsif ($key =~ /split/i) {$data{$key} = 'FF';} 
elsif ($key =~ /select/i) {$data{$key} = 'FF';} 
else {$data{$key} = '';}
}
}
}#### Write selected
foreach my $fld (@{$fmt}) {
my $value = $data{$fld};
if (!defined $value) {
LogIt(5363,"ICOM l5548: No value for $fld");
$value = '00';
}
$sendhex = $sendhex . $value;
if ($fld eq 'igrp') {next;}
if (($fld eq 'chan') and (!$parmref->{'write'})){last;}
if (!$in->{'frequency'}) {
$sendhex = $sendhex . 'FF';
last;
}
}
if ($Debug1) {
DebugIt("ICOM 5640:'_Memory_Direct' packet to send:\n$Bold  $sendhex");
}
}### Set/Get Memory channel
elsif ($cmd eq '_band_stack')     {
LogIt(1,"ICOM_CMD:_band_stack command not yet implemented!");
return ($parmref->{'rc'} = $NotForModel);
}
elsif ($cmd eq '_op_state') {
if ($parmref->{'write'}) {
my $state = '00';
if ($in->{'state'}) {
if ($in->{'state'} eq 'vfo') {$state = '00';}
elsif ($in->{'state'} eq 'mem') {$state = '01';}
elsif ($in->{'state'} eq 'wx') {$state = '02';}
else {LogIt(3986,"ICOM:_OP_STATE command invalid state $in->{'state'} given!");}
}
$state_save{'state'} = $state;
$sendhex = "$sendhex$state";
}
}
elsif ($cmd eq '_start_a_scan') {
if (!defined $in->{'scan_type'}) {### oops
LogIt(1,"ICOM l6173:_start_a_scan missing 'scan_type'");
return ($parmref->{'rc'} = $ParmErr);
}
my $mwscan = '00';
my $scancode = $scancodes{$in->{'scan_type'}};
if (!defined $scancode){
LogIt(1,"ICOM l6180:_start_a_scan invalid 'scan_type' $in->{'scan_type'}");
return ($parmref->{'rc'} = $ParmErr);
}
if (($scancode eq '02') or ($scancode == 03)) {
my $groupcd = '00';
if ($in->{'group'}) {
}
$scancode = "$scancode$groupcd";
}
elsif ($scancode eq '08') {
my $groupcd = '0000';
if ($in->{'group'}) {
}
$scancode = "$scancode$groupcd";
}
$sendhex = "$sendhex$mwscan$scancode";
}
elsif ($cmd eq '_cancel_scan') {
}
elsif ($cmd eq '_stop_scan') {
print "ICOM l6264:_stop_scan preprocess...\n";
}
elsif ($cmd eq '_get_scan_condition') {
}
elsif ($cmd eq '_get_display') {
}
elsif ($cmd eq '_get_noise_smeter')     { }
elsif ($cmd eq '_vfo_repeater_value') {
if ($parmref->{'write'}) {
my $tone = tone2bcd(substr($in ->{'sqtone'},3));
if ($Debug2) {
DebugIt("ICOM_CMD l6441:_VFO_REPEATER_VALUE in->$in->{'sqtone'}" .
"hex=>$tone");
}
$sendhex = "$sendhex$tone";
}
}
elsif ($cmd eq '_vfo_ctc_value') {
if ($parmref->{'write'}) {
my $tone = $in->{'_tone'};
if (!$tone) {
print "ICOM l6549:No tone was set. _VFO_CTC_VALUE nullified\n";
return 1;
}
my $code = tone2bcd($tone);
if ($Debug2) {
DebugIt("ICOM_CMD l6545:_VFO_CTC_VALUE in->$in->{'_tone'}" .
"hex=>$code");
}
$sendhex = "$sendhex$code";
}
}
elsif ($cmd eq '_vfo_dcs_value') {
if ($parmref->{'write'}) {
my $rev = '00';
if ($in->{'polarity'}) {$rev = '01';}
my $tone = $in ->{'_tone'};
my $tone_code = '0000';
if (looks_like_number($tone)) {
$tone_code = sprintf("%04.4i",$tone);
}
$sendhex = "$sendhex$rev$tone_code";
if ($Debug2) {
DebugIt("ICOM_CMD l6351:_VFO_DSC_CODE in->$in->{'sqtone'}" .
"hex=>$tone_code");
}
}
}
elsif ($cmd eq '_vfo_nac_value') {
if ($parmref->{'write'}) {
my $tone = sprintf("%03.3X",$out->{'_tone'});
$tone = '0' . substr($tone,0,1) .
'0' . substr($tone,1,1) .
'0' . substr($tone,2,1);
$sendhex = "$sendhex$tone";
}
}
elsif ($cmd eq '_vfo_dsq_value') {
if ($parmref->{'write'}) {
$sendhex = $sendhex . sprintf("%02.2u",$out->{'_tone'});
}
}
elsif ($cmd eq '_get_nxdn_rx_id') {
}
elsif ($cmd eq '_get_nxdn_rx_status') {
}
else {
LogIt(1,"ICOM l6446: No preprocess defined for command $cmd");
$parmref->{'rc'} = $NotForModel;
return $NotForModel;
}
if (($cmd !~ /poll/i) and (length($sendhex) < 9)) {
LogIt(1,"ICOM l6541:Missing command code for cmd=>$cmd");
return ($parmref->{'rc'} = $ParmErr);
}
$sendhex = $sendhex . 'FD';
my $outstr = pack("H*",$sendhex);
my $outlen = length($outstr);
my $ptobj = $parmref->{'portobj'};
RESEND:
if ($cmd ne 'poll') {
my ($cnt,$leftover) = $portobj->read();
if ($leftover and $Debug3) {DebugIt("ICOM l3439:Leftover before send->",unpack("H*",$leftover));}
$parmref->{'sent'} = $sendhex;
if ($Debug3) {DebugIt("ICOM_CMD l6497:sent=>$sendhex (command=$cmd) ack=$ack");}
my $countout = $ptobj->write($outstr);
if (!$countout or ($countout != $outlen)) {### send failed
if (!$countout) {$countout = 0;}
if ($Debug3) {DebugIt("ICOM:Write failure len=$outlen countout=$countout sent=>$sendhex");}
goto UNRESPONSIVE;
}
if (!$ack) {return $parmref->{'rc'} = $GoodCode;}
}### CMD ne 'POLL'
my $st = Time::HiRes::time;
WAITFORREPLY:
if ($Debug3) {DebugIt("ICOM l6514:waiting for reply to $cmd ack=$ack");}
my $byte = '';
my $bstr = '';
my $gotpre = FALSE;
my @rcv_packet = ();
my $rcvhex = '';
my $waitcnt = 10;
while (TRUE) {
$ptobj->read_const_time(10);
my ($count_in, $binary) = $ptobj->read(1);
if ($count_in) {
my $byte = uc(unpack("H*",$binary));
if ($Debug3) {DebugIt("Byte=>$byte");}
if ($byte eq 'FD') {### packet terminator
$rcvhex = "$rcvhex$byte";
last;
}
elsif ($byte eq 'FE') {
if (length($rcvhex) > 2) {
LogIt(0,"ICOM l3469:Got start of new packet with no end of last ($rcvhex)!");
@rcv_packet = ();
$rcvhex = '';
}
$gotpre = TRUE;
$rcvhex = "$rcvhex$byte";
}
elsif ($byte eq 'FC') {
$waitcnt = 10;
next;
}
elsif ($gotpre) {
push @rcv_packet,$byte;
$rcvhex = "$rcvhex$byte";
}
else {if ($warn) {LogIt(1,"ICOM l4412:got byte $byte before preamble");}}
$waitcnt = 10;
}
else {
if ($cmd eq 'poll') {return ($parmref->{'rc'} = $GoodCode);}
--$waitcnt;
if ($Debug3) {DebugIt("Wait count=$waitcnt");}
if (!$waitcnt) {goto UNRESPONSIVE;}
usleep(10);
}
}
if ($Debug3) {DebugIt("ICOM l6573:recv packet =@rcv_packet")};
if ((scalar @rcv_packet) < 3) {
LogIt(0,"ICOM l3489:Got short packet $rcvhex. waiting some more");
goto WAITFORREPLY;
}
my $pt =Time::HiRes::time;
if ($cmd eq 'test') {
if ($rcvhex eq $sendhex) {
LogIt(0,"Got echo of packet for test");
goto WAITFORREPLY;
}
else {
$out->{'test'} = $rcvhex;
return ($parmref->{'rc'} = $GoodCode);
}
}#### TEST command
my $dest = shift @rcv_packet;
my $source = shift @rcv_packet;
if ($source ne $radioaddr) {
if ($Debug3) {DebugIt("ICOM l 6600:Got packet from $source but not from $radioaddr");}
goto WAITFORREPLY;
}
$rc = 0;
$parmref->{'rc'} = $GoodCode;
my $firstbyte = shift @rcv_packet;
if ($firstbyte eq 'FA') {
if ($cmd eq '_op_state') {$state_save{'state'} = '';}
elsif ($cmd eq '_set_freq') {$state_save{'freq'} = 0;}
elsif ($cmd eq '_set_mode') {$state_save{'mode'} = '';}
elsif ($cmd eq '_vfo_atten') {$state_save{'atten'} = -1;}
elsif ($cmd eq '_vfo_preamp') {$state_save{'preamp'} = -1;}
elsif ($cmd eq '_select_chan') {print "L6232:Bad data=>",Dumper($in),"\n";}
elsif ($cmd eq '_vfo_ctc_state') {$state_save{'ctcss_flag'} = -1;}
elsif (($cmd eq '_get_freq') or ($cmd eq '_get_mode')) {goto UNRESPONSIVE;}
elsif ($cmd eq '_get_tone_squelch') {
if ($model eq ICR30) {goto UNRESPONSIVE;}
elsif ($model eq IC705) {goto UNRESPONSIVE;}
elsif ($model eq R8600) {goto UNRESPONSIVE;}
elsif ($model eq IC7300) {goto UNRESPONSIVE;}
}
$defref->{'rsp'}= 0;
if (!$parmref->{'_ignore'}) {
LogIt(1,"ICOM l6082 rejected packet=>$sendhex returned=$rcvhex command issued=>$cmd");
}
return ($parmref->{'rc'} = $NotForModel);
}
elsif ($firstbyte eq 'FF') {
$defref->{'rsp'}= 0;
if ($Debug3) {DebugIt("ICOM_CMD l2007:no data returned..");}
return ($parmref->{'rc'} = $EmptyChan);
}
elsif ($firstbyte eq 'FB') {
$defref->{'rsp'}= 0;
if ($Debug3) {DebugIt("ICOM_CMD l2013:ICOM accepted command. No data returned");}
return ($parmref->{'rc'} = $GoodCode);
}
$defref->{'rsp'}= 0;
my $cmdlength = int(length($cmdcode)/2);
if (!$cmdlength) {
LogIt(3223,"ICOM_CMD:Got NO byte length for command code $cmdcode");
}
my $retcmd = $firstbyte;
my @save_packet = @rcv_packet;
foreach (2..$cmdlength) {$retcmd = $retcmd . shift @rcv_packet;}
if ($Debug3) {DebugIt("ICOM l6682: return command code=$retcmd");}
if (($cmd eq 'poll') or ($retcmd ne $cmdcode)) {
if ($Debug3) {DebugIt("ICOM l6692:Unsolicited message cmdcode=$firstbyte packet=>@save_packet (packet=>$rcvhex)");}
my $queue = $parmref->{'unsolicited'};
my %qe = ('icom_msg' =>$rcvhex,'frequency' => ' ', 'mode' => ' ' );
if ($firstbyte eq '00') {
$qe{'frequency'} =  bcd2num(\@save_packet,TRUE,'4471');
}
elsif ($firstbyte eq '01') {
($qe{'mode'},$qe{'adtype'}) = bcd2mode(\@save_packet,$model) ;
}
else {
LogIt(1,"ICOM_CMD l6707:Unsolicited command $firstbyte ($rcvhex).");
}
if ($queue) {push @{$queue},{%qe};}
else {
print STDERR "ICOM l6347:Got unsolicited message:freq=>$qe{'frequency'} mode=>$qe{'mode'}\n";
}
if ($cmd eq 'poll') {return ($parmref->{'rc'} = $GoodCode);}
goto WAITFORREPLY;
}
my $retcmdstr = $cmd_lookup{$retcmd};
if (!$retcmdstr) {
print Dumper(%cmd_lookup),"\n";
LogIt(1,"ICOM l6724:No lookup for return command code=>$retcmd!");
return ($parmref->{'rc'} = $ParmErr);
}
if ($Debug3) {
DebugIt("ICOM l6596: return command=>$retcmdstr");
}
if ($ack < 1) {
LogIt(1,"ICOM l6736:Got unexpected response for $cmd$Eol Received:$Bold$rcvhex");
return ($parmref->{'rc'} = $OtherErr);
}
elsif ($retcmdstr eq '_get_range') {
my @low = ();
my @high = ();
foreach my $count (1..$freqbytes){
if (scalar @rcv_packet) {push @low,shift @rcv_packet;}
}
my $sep = shift @rcv_packet;
foreach my $count (1..$freqbytes){
if (scalar @rcv_packet) {push @high,shift @rcv_packet;}
}
my $low = bcd2num(\@low,$freqbytes);
my $high = bcd2num(\@high,$freqbytes);
if ($Debug2) {DebugIt("ICOM_CMD l1905:Returned high=$high low=$low");}
if ($high < $low) {
my $temp = $high;
$high = $low;
$low = $temp;
}
$out->{'maxfreq'} = $high;
$out->{'minfreq'} = $low;
}
elsif ($retcmdstr eq '_get_freq')  {
my $freq = 0;
if ($rcv_packet[0] ne 'FF') {
$freq = bcd2num(\@rcv_packet,TRUE,'1999');
}
$out->{"frequency"} = $freq;
$state_save{'frequency'} = $freq;
if ($Debug2)   {DebugIt("ICOM_CMD l2014:Returned frequency=$freq");}
if ($out->{"frequency"}) {$out->{'valid'} = TRUE;}
else {$out->{'valid'} = FALSE;}
}
elsif ($retcmdstr eq '_get_mode')   {
my $mode = '';
my $bw = 0;
my $adtype = 'AN';
if ($rcv_packet[0] ne 'FF') {
($mode,$adtype) =  bcd2mode(\@rcv_packet,$model);
if ($mode =~ /\?/) {
print "ICOM l6382:Bad MODE code from '_get_mode'\n";
$mode = 'FMn';
$adtype = 'AN';
}
}
$state_save{'mode'} = $mode;
if ($Debug2)   {DebugIt("ICOM_CMD l2136:Returned mode=$mode packet=@save_packet");}
$out->{'mode'}   = $mode;
$out->{'adtype'} = $adtype ;
$out->{'bw'} = $bw;
}
elsif ($retcmdstr eq '_vfo_step') {
my $scode = shift @rcv_packet;
my $step = $step_code{$model}[$scode];
if (!$step) {### could not get a code
LogIt(1,"ICOM l6838:Could not find a step for code=$scode");
$step = 5000;
}
$out->{'step'} = $step;
}
elsif ($retcmdstr eq '_vfo_atten') {
my $atten = shift @rcv_packet;
if ($atten eq '00') {$out->{'atten'} = FALSE;}
else {$out->{'atten'} = TRUE;}
$state_save{'atten'} = $atten;
}
elsif ($cmd eq '_rf_gain') {
my $rfgain = bcd2num(\@rcv_packet,0,5869);
if (!$rfgain) {$rfgain = 0;}
$out->{'rfgain_v'} = $rfgain;
my $rfg = 1;
if    ($rfgain > 230) {$rfg = 0;}
elsif ($rfgain > 204) {$rfg = 9;}
elsif ($rfgain > 178) {$rfg = 8;}
elsif ($rfgain > 153) {$rfg = 7;}
elsif ($rfgain > 127) {$rfg = 6;}
elsif ($rfgain > 102) {$rfg = 5;}
elsif ($rfgain >  76) {$rfg = 4;}
elsif ($rfgain >  52) {$rfg = 3;}
elsif ($rfgain >  25) {$rfg = 2;}
$out->{'rfgain'} = $rfg;
}
elsif ($retcmdstr eq  '_get_squelch')   {
my $sql = shift @rcv_packet;
if ($sql eq '01') {$out->{'sql'} = TRUE;}
else {$out->{'sql'} = FALSE;}
}
elsif ($retcmdstr eq  '_get_tone_squelch')   {
my $sql = shift @rcv_packet;
if ($sql eq '01') {$out->{'sql'} = TRUE;}
else {$out->{'sql'} = FALSE;}
}
elsif ($retcmdstr eq  '_get_signal')   {
my $sql = FALSE;
if ($out->{'sql'} ) {$sql = TRUE;}
my $rssi = '';
foreach my $ndx (0..1) {
my $byte = $rcv_packet[$ndx];
if (!defined $byte) {
LogIt(1,"_get_signal did not return a value");
print Dumper(@rcv_packet),"\n";
return ($parmref->{'rc'} =  $OtherErr);
}
$rssi = "$rssi$byte";
}
if (!looks_like_number($rssi)) {### gotta problem
LogIt(1,"ICOM l6848: _Get_Signal returned a non-numeric value $rssi");
return ($parmref->{'rc'} = $OtherErr);
}
$rssi = $rssi + 0;
my $signal = 0;
if ($sql) {$signal = 1;}
my $meter = 0;
if ($rssi) {### gotta be at LEAST one level
if ($rssi2sig{$model}) {
foreach my $cmp (@{$rssi2sig{$model}}) {
if (!$cmp) {next;}
if (($rssi < $cmp) or ($signal >= MAXSIGNAL)){
last;
}
$signal++;
}
}
else {if ($sql) {$signal = MAXSIGNAL;}}
if ($sig2meter{$model}) {
my $meter_ndx = 0;
my @meter_table = @{$sig2meter{$model}};
foreach my $cmp (@meter_table) {
if (!$cmp) {next;}
if ($rssi < $cmp) {last;}
$meter_ndx++;
}
$meter = $sigmeter[$meter_ndx];
}### Signal2meter is available
else {if ($sql) {$meter = 9;}}
}### $sig has a value
$out->{'rssi'} = $rssi;
$out->{'signal'} = $signal;
$out->{'meter'} = $meter;
}### _get_signal
elsif ($retcmdstr eq '_vfo_preamp') {
my $preamp = shift @rcv_packet;
if ($preamp eq '01') {$out->{'preamp'} = TRUE;}
else {$out->{'preamp'} = FALSE;}
$state_save{'preamp'} = $preamp;
}
elsif ($retcmdstr eq '_vfo_repeater_state') {
my $rptr = shift @rcv_packet;
if ($rptr and looks_like_number($rptr)) {$rptr = $rptr + 0;}
else {$rptr = 0;}
$out->{'_tone_state'} = $rptr;
}
elsif ($retcmdstr eq '_vfo_ctc_state') {
my $state = shift @rcv_packet;
if ($state and looks_like_number($state)) {$state = $state + 0;}
else {$state = 0;}
$out->{'_tone_state'} = $state;
$state_save{'ctcss_flag'} = $state;
}
elsif ($retcmdstr eq '_vfo_dcs_state') {
my $state = shift @rcv_packet;
if ($state and looks_like_number($state)) {$state = $state + 0;}
else {$state = 0;}
$out->{'_tone_state'} = $state;
$state_save{'dtcs_flag'} = $state;
}
elsif ($retcmdstr eq '_dply_type') {
$out->{'dual'} = shift @rcv_packet;
}
elsif ($retcmdstr eq '_nxdn_encrypt') {
$out->{'nxdncrypt'} = shift @rcv_packet;
}
elsif ($retcmdstr eq '_vfo_ran_value') {
my $ran = 0;
if (scalar @rcv_packet) {$ran = shift @rcv_packet;}
if (looks_like_number($ran)) {$ran = $ran + 0;}
else {$ran = 0;}
$out->{'_tone'} = $ran;
}
elsif ($retcmdstr eq '_vfo_crypt_key') {
$out->{'enc'} = '';
while (scalar @rcv_packet) {
$out->{'enc'} = $out->{'enc'} . shift @rcv_packet;
}
}
elsif ($retcmdstr eq '_get_nxdn_rx_id') {
$out->{'nxdnrxid'} = '';
while (scalar @rcv_packet) {
$out->{'nxdnrxid'} = $out->{'nxdnrxid'} . shift @rcv_packet;
}
}
elsif ($retcmdstr eq '_get_nxdn_rx_status') {
$out->{'nxdnrxstatus'} = '';
while (scalar @rcv_packet) {
$out->{'nxdnrxstatus'} = $out->{'nxdnrxstatus'} . shift @rcv_packet;
}
}
elsif ($retcmdstr eq  '_get_id')   {
my $addr = shift @rcv_packet;
if ($addr) {
$model =  $default_addr{$addr};
if (!$model) {$model = R7000;}
$out->{'model'} = $model;
$out->{'addr'} = $addr;
if ($Debug2) {DebugIt("set model number to $model");}
}
else {return $NotForModel;}
}
elsif ($retcmdstr eq '_memory_direct') {
if ($Debug1) {
DebugIt("ICOM l7149:'_memory_direct' returned:\n$Bold$rcvhex");
}
if ($parmref->{'write'}) {
}
else {
$out->{'service'} = '';
$out->{'frequency'} = 0;
$out->{'splfreq'} = '';
$out->{'mode'}  = 'FMn';
$out->{'bw'} = 0;
$out->{'sqtone'} = 'Off';
$out->{'valid'} = TRUE;
$out->{'atten'} = FALSE;
$out->{'preamp'} = FALSE;
$out->{'scangrp'} = 0;
$out->{'scan705'} = 0;
$out->{'scan8600'} = 0;
$out->{'adtype'} = 'AN';
$out->{'enc'} = 0;
$out->{'channel'} = -1;
$out->{'spltone'} = '';
my $mdl = $model;
my $igrp = 0;
my $group_extra = 0;
my $chan_extra = 0;
my $nybble = 0;
my $split = FALSE;
my $duplex = 0;
my $sduplex = 0;
my $offset = 0;
my $soffset = 0;
my $select = 0;
my $splfreq = 0;
my $spltone = '';
my $tt = 'Off';
if (!defined $direct_format{$mdl}) {$mdl = OTHER;}
my @packet_save = @rcv_packet;
my $shift = 0;
my $ndx = 0;
foreach my $fld (@{$direct_format{$mdl}}) {
$ndx++;
if ($fld eq 'igrp') {
my @grp = (shift @rcv_packet, shift @rcv_packet);
$shift++;
$shift++;
$igrp = bcd2num(\@grp,FALSE,'1886');
if ($igrp > 99) {
$group_extra = int($igrp/100);
$igrp = $igrp - $group_extra;
}
}### Group number process
elsif ($fld eq 'chan') {
my @memchan = (shift @rcv_packet, shift @rcv_packet);
$shift++;
$shift++;
my $ch = bcd2num(\@memchan,FALSE,'1886');
if ($ch > 99) {
$chan_extra = int($ch/100);
$ch = $ch - $chan_extra;
}
my $channel = $ch + ($igrp * 100);
if ($channel != ($in->{'channel'})) {
my $emsg = "ICOM got info for ch $channel but requested $in->{'channel'}!";
LogIt(1,$emsg);
return ($parmref->{'rc'} = $OtherErr);
}
$out->{'channel'} = $channel;
$out->{'chan_extra'} = $chan_extra;
$out->{'group_extra'} = $group_extra;
if ($rcv_packet[0] =~ /ff/i) {last;}
}### Channel number process
elsif ($fld =~ /rsvd/i) {
shift @rcv_packet;
$shift++;
}
elsif ($fld eq 'split') {
my $byte = shift @rcv_packet;
$shift++;
if (substr($byte,0,1)) {$split = 1;}
my $value = substr($byte,1,1);
if ($value and looks_like_number($value)) {$select = $value + 0;}
$out->{'scan705'} = $select;
}
elsif ($fld =~ /duplex/i) {
my $byte = shift @rcv_packet;
$shift++;
if (!$byte or !looks_like_number($byte)) {$duplex = 0;}
else {$duplex = $byte + 0;}
}
elsif ($fld eq 'select') {
my $byte = shift @rcv_packet;
$shift++;
my $skip = substr($byte,0,1);
my $scan = substr($byte,1,1);
if ($skip and looks_like_number($skip)) {$skip = $skip + 0;}
else {$skip = 0;}
if ($scan and looks_like_number($scan)) {$scan = $scan + 0;}
else {$scan = 0;}
if ($skip) {$out->{'valid'} = FALSE;}
$out->{'scan8600'} = $scan;
}
elsif ($fld =~ /tt/i) {
my $byte = shift @rcv_packet;
$shift++;
my $c1 = substr($byte,0,1);
my $c2 =  substr($byte,1,1);
if ($c1 and looks_like_number($c1)) {$c1 = $c1 + 0;}
else {$c1 = 0;}
if ($c2 and looks_like_number($c2)) {$c2 = $c2 + 0;}
else {$c2 = 0;}
if ($fld =~ /s/i) {
if (!$c2) {$spltone = 'Off';}
elsif ($c2 == 1) {$spltone = 'RPT';}
elsif ($c2 == 2) {$spltone = 'CTC';}
elsif ($c2 == 3) {$spltone = 'DCS';}
}
else {
if ($fld =~ /2/) {$duplex = $c1;}
if ($c2 == 0) {$tt = 'Off';}
elsif ($c2 == 1) {
if ($fld =~ /3/) {$tt = 'CTC';}  
else {$tt = 'RPT';}
}
elsif ($c2 == 2) {
if ($fld =~ /3/) {$tt = 'DCS';} 
else {$tt = 'CTC';}
}
elsif ($c2 == 3) {$tt = 'DCS';}
else {
LogIt(1,"ICOM l7841: Bad tone code $c2");
print " byte=>$byte shift=>$shift mdl=$mdl packet=>@packet_save\n";
}
}### non-split field
}
elsif (($fld =~ /rpt/i) or ($fld =~ /ctc/i) or ($fld =~ /dcs/i)) {
my $tone = 0;
if (($fld =~ /rpt/i) or ($fld =~ /ctc/i)) {
$tone = packet_decode(\@rcv_packet,'tone',2);
$tone = Strip(sprintf("%5.1f",$tone));
}
elsif ($fld =~ /dcs/i) {
$tone = (shift @rcv_packet) . (shift @rcv_packet);
$tone = sprintf("%03.3i",$tone);
}
if ($fld =~ /^s/i) {
my $type = substr($fld,1);
if ($type =~ /$spltone/i) {
$spltone = "$type$tone";
}
}#### Split field
else {
if ($fld =~ /$tt/i) {
$out->{'sqtone'} =  uc("$fld$tone");
}
}### Non-split field
}### Tone process
elsif ($fld eq 'flag1' ) {
my $flags = shift @rcv_packet;
my $bits = sprintf("%8.8B",$flags);
if (substr($bits,6,1) > 0) {$out->{'valid'} = TRUE;}
else {$out->{'valid'} = FALSE;}
if (substr($bits,7,1) > 0) {$split = TRUE;}
}
elsif ($fld eq 'atten') {
my $att = shift @rcv_packet;
if (looks_like_number($att)) {$att = $att + 0;}
else {$att = 0;}
if ($att)  { $out->{'atten'} = TRUE;}
}
elsif ($fld eq 'preamp') {
my $pamp = shift @rcv_packet;
if (looks_like_number($pamp)) {$pamp = $pamp + 0;}
else {$pamp = 0;}
if ($pamp) {$out->{'preamp'} = TRUE;}
}
elsif ($fld =~ /freq/i) {
my @freqbcd = ();
if ((scalar @rcv_packet)< 5) {
LogIt(1,"ICOM:l7553:Short packet returned for $fld:Received:$rcvhex");
last;
}
foreach (1..5) {push @freqbcd,shift @rcv_packet;}
my $freq = bcd2num(\@freqbcd,TRUE,'7554');
if ($fld =~ /s/i) {$splfreq = $freq;}
else {$out->{'frequency'} = $freq;}
}### FREQ field
elsif ($fld =~ /mode/i) {
my @modebcd = (shift @rcv_packet,  shift @rcv_packet);
my ($mode,$adtype) =  bcd2mode(\@modebcd,$mdl);
if ($mode =~ /\?/) {
print "ICOM l7264:Bad MODE code in memory_direct. $fld Index=>$ndx packet =>@packet_save\n";
$mode = 'FMn';
$adtype = 'AN';
}
if ($fld =~ /s/i) {
}
else {
$out->{'mode'} = $mode;
$out->{'adtype'} = $adtype;
}
}### Mode field
elsif ($fld =~ /fof/i) {
my $len = 3;
if ($fld =~ /4/) {$len = 4;} 
my $value =  packet_decode(\@rcv_packet,'frequency',$len);
}
elsif ($fld eq 'ts') {
my @ts = (shift @rcv_packet, shift @rcv_packet);
}
elsif ($fld eq 'pts') {
my @pts = (shift @rcv_packet, shift @rcv_packet);
}
elsif ($fld =~ /callsign/i) {
my $callsign  = packet_decode(\@rcv_packet,'ascii',8);
my $len = length($callsign);
}
elsif ($fld eq 'service') {
my $service = '';
my $dummy = '';
my $count = $radio_limits{$mdl}{'serv_len'};
if ($count) {
$out->{'service'} =  packet_decode(\@rcv_packet,'ascii',$count)
}
}
elsif ($fld eq 'special') {
if ($out->{'mode'} =~ /fm/i) {
my @save = @rcv_packet;
my $tsql = shift @rcv_packet;
if ($tsql and looks_like_number($tsql)) {$tsql = $tsql + 0;}
else {$tsql = 0;}
if ($tsql) {
my $adtype = $out->{'adtype'};
if (!$adtype) {
$adtype = 'AN';
}
if ($adtype =~ /an/i) {
my $ctc = packet_decode(\@rcv_packet,'tone',3);
$ctc = 'CTC' . Strip(sprintf("%5.1f",$ctc));
my $polarity = shift @rcv_packet;
my $byte1 = shift @rcv_packet;
my $byte2 = shift @rcv_packet;
if ((!defined $byte1) or (!defined $byte2)) {
print "Packet problem with DCS original packet=>@save\n";
if (!$byte1) {$byte1 = '00';}
if (!$byte2) {$byte2 = '00';}
}
my $dcs = 'DCS' . sprintf("%03.3u","$byte1$byte2");
if ($tsql == 1) {
$out->{'sqtone'} = $ctc;
}
elsif ($tsql == 2) {
$out->{'sqtone'} = $dcs;
if ($polarity > 0) {$out->{'polarity'} = 1;}
}
else {
$out->{'sqtone'} = 'Off';
}
}##### Analog squelch mode
elsif ($adtype =~ /nxdn/i) {
if ($tsql > 0) {
my $ran = shift @rcv_packet;
$out->{'sqtone'} = "RAN$ran";
my $encrypt = shift @rcv_packet;
if ($encrypt > 0) {
$out->{'enc'} = packet_decode(\@rcv_packet,'number',3);
}
}
}
elsif ($adtype =~ /p25/i) {
if ($tsql > 0) {
my $nac = packet_decode(\@rcv_packet,'nac',3);
$out->{'sqtone'} = "NAC$nac";
}
}
elsif ($adtype =~ /star/i) {
if ($tsql > 0) {
my $dsq = shift @rcv_packet;
$out->{'sqtone'} = "DSQ$dsq";
}
}
}#### FMn modulation and $tsql
else {
$out->{'sqtone'} = 'Off';
}
}### FM modulation detected
last;
}#### Special field process
else {
LogIt(1,"ICOM l7523:Missing decode for field $fld");
last;
}
}### Field process loop
my $freq = $out->{'frequency'};
if ($split) {
$out->{'splfreq'} = $splfreq;
}
return ($parmref->{'rc'} = $rc);
}### Read process for '_Memory Direct'
}### Memory Direct
elsif ($retcmdstr eq '_op_state') {
my $state = shift @rcv_packet;
if (!$state) {$state = 0;}
if ($state == 0) {$out->{'state'} = 'vfo';}
elsif ($state == 1) {$out->{'state'} = 'mem';}
elsif ($state == 2) {$out->{'state'} = 'wx';}
else {
LogIt(1,"ICOM_CMD l8328:_OP_STATE returned unknown state=$state");
$out->{'state'} = '?';
}
$state_save{'state'} = $out->{'state'};
}
elsif ($cmd eq '_get_scan_condition') {
my $state = shift @rcv_packet;
if (!$state) {$state = 0;}
if ($state == 0) {$out->{'scan'} = 'off';}
elsif ($state == 1) {$out->{'scan'} = 'up';}
elsif ($state == 2) {$out->{'scan'} = 'down';}
elsif ($state == 3) {$out->{'scan'} = 'up';}
elsif ($state == 4) {$out->{'scan'} = 'down';}
else {
LogIt(1,"ICOM_CMD l8355:_SCAN_CONDITION returned unknown condition=$state");
$out->{'scan'} = '?';
}
$state_save{'scan'} = $out->{'scan'};
}
elsif ($retcmdstr eq '_get_display') {
my $status = $rcv_packet[0];
my $state = $rcv_packet[1];
if ($state == 0) {$out->{'state'} = 'vfo';}
elsif ($state == 1) {$out->{'state'} = 'mem';}
elsif ($state == 2) {$out->{'state'} = 'wx';}
else {
LogIt(1,"ICOM l8407:Unknown state $state returned for _GET_DISPLAY");
$out->{'state'} = '';
}
$state_save{'state'} = $out->{'state'};
$out->{'rfgain'} = '';
$out->{'atten'} = FALSE;
$out->{'preamp'} = FALSE;
$out->{'spltone'} = '';
my @freqbcd = ();
foreach my $ndx (2..6) {push @freqbcd,$rcv_packet[$ndx];}
if (lc($freqbcd[0]) eq 'ff') {
$out->{'frequency'} = 0;
$out->{'mode'} = 'FMn';
$out->{'adtype'} = 'AN';
$out->{'sqtone'} = 'Off';
$out->{'valid'} = FALSE;
}
else {
$out->{'frequency'} = bcd2num(\@freqbcd,TRUE,'4732');
my @modebcd = ($rcv_packet[8], $rcv_packet[9]);
my $mode = 'FMn';
my $adtype = 'AN';
if (lc($modebcd[0]) eq 'ff') {$mode = 'FMn';}
else {
($mode,$adtype)  = bcd2mode(\@modebcd,$model);
if ($mode =~ /\?/) {
print "ICOM l7631:Bad MODE code from '_get_display'\n";
$mode = 'FMn';
$adtype = 'AN';
}
}
$out->{'mode'} = $mode;
$out->{'adtype'} = $adtype;
$out->{'enc'} = 0;
if (($adtype =~ /dp/i) or ($adtype =~ /dc/i)) {
$out->{'adtype'} = 'AN';
}
my %rfgain_lookup = (
'0012' => 1, '0038' => 2, '0064' => 3, '0089' => 4, '0115' => 5,
'0140' => 6, '0166' => 7, '0192' => 8,  '0217' => 9, '0243' => 10);
my $gain =  $rcv_packet[10] . $rcv_packet[11];
if (!looks_like_number($gain)) {
if ($Debug2) {DebugIt("ICOM l8445:Invalid gain in packet => $rcv_packet[10] $rcv_packet[11]");}
$gain = 0;
}
my $rfgain = '';
if ($rfgain_lookup{$gain}) {
$rfgain = $rfgain_lookup{$gain};
}
else {print STDERR "ICOM l7748:RFGAIN lookup failure for gain=$gain\n";}
if ($rfgain) {
if ($rfgain == 10) {$out->{'preamp'} = TRUE;}
elsif ($rfgain < 4) {$out->{'atten'} = TRUE;}
$out->{'rfgain'} = $rfgain;
}
if ($rcv_packet[12] + 0) {$out->{'att'} = TRUE;}
else {$out->{'att'} = FALSE;}
$out->{'duplex'} = $rcv_packet[13];
$out->{'wx'}     = $rcv_packet[14];
$out->{'mute'}   = $rcv_packet[15];
$out->{'afc'}    = $rcv_packet[16];
$out->{'valid'} = TRUE;
if ($rcv_packet[17] + 0) {
$out->{'valid'} = FALSE;}
my $igrp = $rcv_packet[18] . $rcv_packet[19];
if (!$igrp) {$igrp = 0;}
my $ch  = $rcv_packet[20] . $rcv_packet[21];
if (!$ch) {$ch = 0;}
$out->{'channel'} = (($igrp * 100) + $ch) + 0;
my $service = '';
foreach my $ndx (22..37) {
my $char = $rcv_packet[$ndx];
if ($char)  {$service = $service . chr(hex($char));}
}
if ($state_save{'state'} eq 'mem'){$out->{'service'} = $service;}
$out->{'vsc'} = $rcv_packet[38];
my $tb1 = $rcv_packet[39];
if (!$tb1 or (!looks_like_number($tb1))) {$tb1 = 0;}
my $tb2 = $rcv_packet[40];
if (!$tb2 or (!looks_like_number($tb2))) {$tb2 = 0;}
$tb1 = $tb1  + 0;
$tb2 = $tb2  + 0;
$out->{'sqtone'} = 'Off';
if ($mode =~ /fm/i) {
if ($adtype =~ /dc/i) {
}
elsif ($adtype =~ /dp/i) {
}
elsif (($adtype =~ /nx/i) or ($adtype =~ /vx/i)) {
if ($tb1) {
$parmref->{'write'} = FALSE;
$out->{'_tone'} = 0;
icom_cmd('_vfo_ran_value',$parmref);
$out->{'sqtone'} = "RAN$out->{'_tone'}";
}
if ($tb2) {
icom_cmd('_vfo_crypt_key',$parmref);
}
}#### NXDN audio type
elsif ($adtype =~ /ds/i) {###
if ($tb1) {
$parmref->{'write'} = FALSE;
$out->{'_tone'} = 0;
icom_cmd('_vfo_dsq_value',$parmref);
$out->{'sqtone'} = "DSQ$out->{'_tone'}";
}
}### D-STAR audio
elsif ($adtype =~ /p2/i) {### P25 format
if ($tb1)  {## P25 NAC squelch
$out->{'_tone'} = 0;
icom_cmd('_vfo_nac_value',$parmref);
$out->{'sqtone'} = "NAC$out->{'_tone'}";
}
}### P25 audio
else {
if ($tb1) {
$parmref->{'write'} = FALSE;
icom_cmd('_vfo_ctc_value',$parmref);
}### DCS squelch
elsif ($tb2) {
$parmref->{'write'} = FALSE;
icom_cmd('_vfo_dcs_value',$parmref);
}### DCS squelch
}### Analog tone types
}### FM Modulation
}### non-empty channel
}### _get_display post process
elsif ($retcmdstr eq '_get_noise_smeter') {
my $sq =  $rcv_packet[0] + 0;
$out->{'sql'} = $sq;
my $sig = '';
foreach my $ndx (1..2) {
my $byte = $rcv_packet[$ndx];
if (!defined $byte) {
LogIt(1,"_get_noise_smeter did not return a value");
return ($parmref->{'rc'} =  $OtherErr);
}
$sig = "$sig$byte";
}
if (!looks_like_number($sig)) {### gotta problem
LogIt(1,"ICOM l8622: '_get_noise_smeter' returned a non-numeric value $sig");
return ($parmref->{'rc'} = $OtherErr);
}
$sig = $sig + 0;
$out->{'rssi'} = $sig;
my $signal = 0;
if ($sq) {
if ($sig > 221) {$signal = 9;}
elsif ($sig > 169) {$signal = 8;}
elsif ($sig > 135) {$signal = 7;}
elsif ($sig > 101) {$signal = 6;}
elsif ($sig >  84) {$signal = 5;}
elsif ($sig > 67) {$signal = 4;}
elsif ($sig > 50) {$signal = 3;}
elsif ($sig > 33) {$signal = 2;}
else {$signal = 1;}
}
$out->{'signal'} = $signal;
}### _get_noise_meter
elsif ($retcmdstr eq '_vfo_repeater_value') {
my @packet_save = @rcv_packet;
shift @rcv_packet;
my $tone = packet_decode(\@rcv_packet,'tone');
if (looks_like_number($tone)) {
my $sqtone = 'CTC' . Strip(sprintf("%5.1f",$tone));
if ($valid_ctc{$sqtone}) {$out->{'sqtone'} = $sqtone;}
else {
LogIt(1,"ICOM l8566:VFO_REPEATER_VALUE $tone " .
" is not a valid RadioCtl tone =>Packet=@packet_save");
$out->{'sqtone'} = 'Off';
}
}
else {
LogIt(1,"ICOM l8570:VFO_REPEATER_VALUE bad decode. Packet=@packet_save");
$out->{'sqtone'} = 'Off';
}
}
elsif ($retcmdstr eq '_vfo_ctc_value') {
my @packet_save = @rcv_packet;
shift @rcv_packet;
my $tone = packet_decode(\@rcv_packet,'tone');
if (looks_like_number($tone)) {
my $sqtone = 'CTC' . Strip(sprintf("%5.1f",$tone));
if ($valid_ctc{$sqtone}) {$out->{'sqtone'} = $sqtone;}
else {
LogIt(1,"ICOM l8599:VFO_CTC_VALUE $tone (sqtone=>$sqtone)" .
" is not a valid RadioCtl tone =>Packet=@packet_save");
print Dumper(%valid_ctc),"\n";exit;
$out->{'sqtone'} = 'Off';
}
}
else {
LogIt(1,"ICOM l8599:VFO_CTC_VALUE bad decode. Packet=@packet_save");
$out->{'sqtone'} = 'Off';
}
}
elsif ($retcmdstr eq '_vfo_dcs_value') {
my @packet_save = @rcv_packet;
my $polarity = shift @rcv_packet;
if ($polarity and looks_like_number($polarity)) {$polarity = $polarity + 0;}
else {$polarity = 0;}
if ($polarity) {$out->{'polarity'} = TRUE;}
else {$out->{'polarity'} = FALSE;}
my $tone = '';
foreach (0..2) {
if (scalar @rcv_packet) {$tone = $tone . shift @rcv_packet;}
}
if ($tone and looks_like_number($tone)) {
$tone = substr($tone,-3,3);
my $sqtone = 'DCS' . sprintf("%03.3i",$tone);
if ($valid_dcs{$sqtone}) {$out->{'sqtone'} = $sqtone;}
else {
LogIt(1,"ICOM l8648:VFO_DCS_VALUE=>$sqtone<=" .
" is not a valid RadioCtl tone =>Packet=@packet_save");
$out->{'sqtone'} = 'Off';
}
}
else {
LogIt(1,"ICOM l8645:VFO_DSC_VALUE bad decode. Packet=@packet_save");
$out->{'sqtone'} = 'Off';
}
}### VFO_DCS_VALUE postprocess
elsif ($retcmdstr eq '_vfo_nac_value') {
$out->{'_tone'} = packet_decode(\@rcv_packet,'nac',3);
}
elsif ($retcmdstr eq '_vfo_dsq_value') {
my $tone = 0;
if (scalar @rcv_packet) {$tone = shift @rcv_packet;}
$tone = $tone + 0;
$out->{'_tone'} = $tone;
}
else {
LogIt(1,"ICOM l8733:No post process for retcmdstr=$retcmdstr cmd=$cmd. Need handler!");
add_message("ICOM got response to $cmd ($cmdcode) retcmdstr=$retcmdstr. Need handler!");
}
return ($parmref->{'rc'} = $rc);
UNRESPONSIVE:
if ($cmd eq 'test') {
LogIt(1,"ICOM l8745:No response from the radio for command $sendhex");
$out->{'test'} = '';
}
else {
if (!$defref->{'rsp'}) {
my $msg = "Radio is not responding";
if ($warn) {
if ($sendhex) {LogIt(1,"ICOM l8756:Radio did not repond to $sendhex");}
else {LogIt(1,$msg);}
add_message($msg);
}
$defref->{'rsp'} = 1;
}
else {$defref->{'rsp'}++;}
}
return ($parmref->{'rc'} = $CommErr);
}
sub get_r30_display {
my $parmref = shift @_;
my $out = $parmref->{'out'};
my $timeout = 1000;
while ($timeout) {
usleep(300);
$timeout--;
if (icom_cmd('_get_display',$parmref)) {
LogIt(1,"ICOM l8797: _get_display command failed");
return ($parmref->{'rc'});
}
if ($out->{'mode'} !~ /dc/i) {
$timeout = 0;
}
}
if ($out->{'mode'} =~ /dc/i) {
LogIt(1,"ICOM l8188: DCR modulation found after 1000 times!");
}
return ($parmref->{'rc'});
}
sub tone2bcd {
my $tone = shift @_;
my $newtone = '0670';
if ($tone and  (looks_like_number($tone))){
my $int = int($tone);
my ($dec) = $tone =~ /\d*?\.(\d)/;
if (!$dec) {$dec = 0;}
if ($int < 67) {
LogIt(1,"ICOM l8090:Conversion error for tone $tone!");
}
else {
$newtone = sprintf("%04.4u","$int$dec");
}
}
return $newtone;
}
sub num2bcd {
my ($num,$bytes,$rev) = @_;
my $digits = $bytes*2;
my $i;
my $out = '';
if (!$num) {$num = '0';}
$num = sprintf("%${digits}.${digits}ld",$num);
if ($rev) {
$i = $digits-2;
while ($i >= 0) {
$out =  $out .  substr($num,$i,2);
$i = $i - 2;
}
}
else {
$i = 0;
while ($i < $digits) {
$out = $out . substr($num,$i,2);
$i = $i + 2;
}
}
return $out;
}
sub rctostepbcd {
my $step = shift @_;
my $bcd = 0;
if (!defined $step_code{$model}[0]) {
LogIt(1,"ICOM l8918: '_rctostepbcd' Unsupported model $model for STEP");
return '00';
}
my $code_count = $#{$step_code{$model}};
foreach my $dcd (@{$step_code{$model}}) {
if ($step <= $dcd) {last;}
if ($bcd < $code_count) {$bcd ++};
}
return sprintf("%02.2u",$bcd);
}
sub bcd2mode {
my $array  = shift @_;
my $imodel = shift @_;
if (!$imodel) {$imodel = '';}
my $adtype = 'AN';
my $mode = 'fm';
my $byte1 = $array->[0];
if (looks_like_number($byte1)) {$byte1 = $byte1 + 0;}
else {
LogIt(1,"ICOM l8758:Array byte $byte1 is NOT numeric");
return $mode,$adtype;
}
my $byte2 = $array->[1];
if ((!$byte2) or (!looks_like_number($byte2))) {
$byte2 = -1;
}
else {$byte2 = $byte2 + 0;}
if ($imodel eq R7000) {
if ($byte1 == 2) {return 'AM',$adtype;}
elsif ($byte2 == -1) {return 'WF',$adtype;}
elsif ($byte1 == 0) {return 'LS',$adtype;}
elsif (($byte1 == 5) and ($byte2 == 0)) {return 'ls',$adtype;}
else {return 'FMn',$adtype;}
}
if    ($byte1 == 0) {$mode = 'ls';}
elsif ($byte1 == 1) {$mode = 'us';}
elsif ($byte1 == 2) {$mode = 'am';}
elsif ($byte1 == 3) {$mode = 'cw';}
elsif ($byte1 == 4) {$mode = 'rt';}
elsif ($byte1 == 5) {$mode = 'fm';}
elsif ($byte1 == 6) {
return "wf",$adtype;
}
elsif ($byte1 == 7) {$mode = 'cr';}
elsif ($byte1 == 8) {$mode = 'rr';}
elsif ($byte1 < 11) {
LogIt(1,"ICOM l8801:Unknown mode byte code:$byte1");
return "FMn",$adtype;
}
elsif ($byte1 < 16) {$mode = 'am';}
elsif (($byte1 > 15) and ($byte1 < 22)) {
$mode = 'FMn';
if ($imodel ne ICR30) {
if ($byte2 == 1) {$mode = 'FMm';}
elsif ($byte2 == 3) {$mode = 'FMu';}
}
elsif ($imodel eq R8600) {
if ($byte2 == 1) {$mode = 'FMw';}
elsif ($byte2 == 2) {$mode = 'FMn';}
elsif ($byte2 == 3) {$mode = 'FMu';}
}
if    ($byte1 == 16) {return $mode,'p2';}
elsif ($byte1 == 17) {return $mode,'ds';}
elsif ($byte1 == 18) {return $mode,'dp';}
elsif ($byte1 == 19) {return $mode,'vn';}
elsif ($byte1 == 20) {return $mode,'nx';}
elsif ($byte1 == 21) {return $mode,'dc';}
else {
LogIt(1,"ICOM l8813:Unknown mode byte code:$byte1");
return $mode,'';
}
}### Digital codes
else {
LogIt(1,"ICOM l8830:Unknown mode byte code $byte1 input=>@{$array}");
return '?','';
}
if ($imodel eq ICR30) {
if ($byte2 == 2) {$mode = $mode . 'n';}
}
elsif ($imodel eq IC703) {
if ($byte2 == 3) {
if ($mode =~ /fm/i) {$mode = $mode . 'm';}
else {$mode = $mode . 'w';}
}
elsif ($byte2 == 2) {$mode = $mode . 'n';}
}
else {
if ($mode =~ /fm/i) {
if ($byte2 == 1) {$mode = $mode . 'm';}
elsif ($byte2 == 3) {$mode = $mode . 'u';}
else {$mode = $mode . 'n';}
}
else {
if ($byte2 == 1) {$mode = $mode . 'w';}
elsif ($byte2 == 3) {$mode = $mode . 'n';}
}
}#### All other radios
return ($mode,$adtype);
}
sub bcd2num {
my ($ref, $rev,$caller) = @_;
my $num = "";
my $temp;
my $start = 0;
my $len = @{$ref};
while ($len) {
my $value = $ref->[$start];
if (!defined $value) {
print Dumper($ref),"\n";
LogIt(1,"ICOM l9070:'BCD2num' bad array value for index $start caller=>$caller");
return 0;
}
$temp  = $ref->[$start];
if ($temp eq 'FF') {return 0;}
$start++;
$len--;
if ($rev) {$num =   $temp . $num;}
else {$num = $num . $temp ;}
}
return $num;
}
sub packet_decode {
my $ref = shift @_;
my $type = shift @_;
my $count = shift @_;
if (!$count) {$count = scalar (@{$ref});}
$type = lc($type);
my $tmodel = shift @_;
if (!$tmodel) {$tmodel = '';}
my $result = '';
my $filter = 0;
my @data = ();
my $data_str = '';
if (!scalar @{$ref}) {
$result = -1;
$filter = -1;
}
foreach (1..$count) {
if (!scalar @{$ref}) {last;}
my $byte = shift @{$ref};
push @data,$byte;
$data_str = "$data_str$byte";
}
if (scalar @data) {
if ($type eq 'bits') {
return unpack('B*',pack("H*",$data_str));
}
elsif ($type eq 'number') {
return  hex($data_str);
}
elsif ($type eq 'frequency') {
foreach my $byte (@data) {
if (lc($byte)  eq 'ff') {
$result = 0;
last;
}
$result = "$byte$result";
}
return $result;
}
elsif ($type eq 'tone')   {
$result = substr($data_str,0,-1) . '.' . substr($data_str,-1,1);
if (!looks_like_number($result)) {
print "ICOM l8658:Tone is not numeric=>$result\n";
$result = '88.1';
}
return  sprintf("%3.1f",$result) ;
}
elsif ($type eq 'mode') {
my ($mode,$adtype) = bcd2mode(\@data,$tmodel);
if ($mode =~ /\?/) {
print "ICOM l8591:Bad MODE code from 'packet_decode' input=>@{$ref}\n";
$mode = 'FMn';
$adtype = 'AN';
}
return $mode,$adtype;
}
elsif ($type eq 'ascii') {
return  pack('H*',$data_str);
}
elsif ($type eq 'nac') {
my $hex = '';
foreach (0..2) {
if (scalar @data) {
my $byte = shift @data;
$hex = $hex . substr($byte,1,1);
}
}
if (!$hex) {$hex = 0;}
return  $hex;
}
else {
LogIt(1,"ICOM l9260: 'PACKET_DECODE' No process for $type");
return -1;
}
}### got some data to process
return $result;
}
sub vfo_get_tones {
my $in = shift @_;
my $out = shift @_;
my $parmref = shift @_;
$out->{'sqtone'} = 'Off';
$out->{'polarity'} = FALSE;
$out->{'_tone_state'} = FALSE;
$in->{'_ignore'} = TRUE;
$parmref->{'write'} = FALSE;
foreach my $type ('ctc','dcs') {
my $cmd = "_vfo_$type" . '_state';
icom_cmd($cmd,$parmref);
if ($out->{'_tone_state'}) {
$cmd = "_vfo_$type" . '_value';
icom_cmd($cmd,$parmref);
last;
}
}
$parmref->{'_ignore'} = FALSE;
return 0;
}
sub vfo_set_tones {
my $parmref = shift @_;
my $in = $parmref->{'in'};
$parmref->{'write'} = TRUE;
$parmref->{'_ignore'} = TRUE;
if ((!$in->{'sqtone'}) or ($in->{'sqtone'} =~ /off/i)) {
$in->{'_tone_state'} = FALSE;
icom_cmd('_vfo_ctc_state',$parmref);
icom_cmd('_vfo_dcs_state',$parmref);
}
else {
my ($tt,$tone) = Tone_Xtract($in->{'sqtone'});
if (($tt =~ /ctc/i) or ($tt =~ /dcs/i)) {
$in->{'_tone_state'} = TRUE;
$in->{'_tone'} = $tone;
my $cmd = '_vfo_' . lc($tt) . '_value';
my $rc = icom_cmd($cmd,$parmref);
if ($rc) {$in->{'_tone_state'} = FALSE;}
$cmd =  '_vfo_' . lc($tt) . '_state';
icom_cmd($cmd,$parmref);
}
else {
$in->{'_tone_state'} = FALSE;
icom_cmd('_vfo_ctc_state',$parmref);
icom_cmd('_vfo_dcs_state',$parmref);
}
}## 'sqtone' is not off
return 0;
}### VFO_SET_TONES
sub rcmode2icom {
my ($pkg,$fn,$caller) = caller;
my $ref = shift @_;
my $imodel = shift @_;
my $bytes = '0502';
my $rcmode = $ref->{'mode'};
if (!$rcmode) {$rcmode = 'fmn';}
if ($rcmode =~ /auto/i) {
my $freq = $ref->{'frequency'};
if (!$freq) {$freq = 30000000;}
$rcmode = lc(Strip(AutoMode($freq)));
}
my $adtype = $ref->{'adtype'};
if (!$adtype) {$adtype = 'AN';}
$rcmode = Strip($rcmode);
my $bw = substr($rcmode,2,1);
if (!$bw) {$bw = '';}
if ($imodel eq R7000) {
if ($rcmode =~ /am/i) {$bytes = '02';}
elsif ($rcmode =~ /wf/i) {$bytes = '05';}
elsif ($rcmode =~ /fm/i) {$bytes = '0502';}
elsif ($rcmode =~ /us/i) {$bytes = '0500';} 
elsif ($rcmode =~ /ls/i) {$bytes = '0500';} 
elsif ($rcmode =~ /rtty/i) {$bytes = '0500';} 
elsif ($rcmode =~ /cw/i) {$bytes = '0500';}
else {$bytes = '0502';}
return $bytes;
}
elsif ($imodel eq IC703) {
if ($rcmode =~ /wf/i) {return '0501';}
elsif ($rcmode =~ /fm/i) {return '0502';}
elsif ($rcmode =~ /ls/i) {return '0001';}
elsif ($rcmode =~ /ls/i) {return '0101';}
elsif ($rcmode =~ /am/i) {return '0201';}
elsif ($rcmode =~ /cw/i) {return '0301';}
elsif ($rcmode =~ /rt/i) {return '0401';}
elsif ($rcmode =~ /cr/i) {return '0701';}
elsif ($rcmode =~ /rr/i) {return '0801';}
else {return $bytes;}
}
elsif ($imodel eq ICR30) {
if ($rcmode =~ /wf/i) {return '0601';}   
elsif ($rcmode =~ /fm/i) {### For FM modulation allow digital
if ($adtype and ($adtype !~ /an/i)) {
if ($adtype =~ /p2/i) {return '1601';}  
elsif ($adtype =~ /ds/i) {return '1701';} 
elsif ($adtype =~ /vn/i) {return '1901';} 
elsif ($adtype =~ /nx/i) {return '2001';} 
else {print "ICOM l9312:$imodel does not support digital mode $adtype\n";}
}
if ($rcmode =~ /fmw/i) {return '0501';}
else {return '0502';}
}
else {
if ($rcmode =~ /am/i) {
if (($rcmode =~ /amn/i) or ($rcmode =~ /amm/i)) {return '0202';}
else {return '0201';}
}
elsif ($rcmode =~ /ls/i) {return '0001';}
elsif ($rcmode =~ /us/i) {return '0101';}
elsif ($rcmode =~ /cw/i) {return '0301';}
elsif ($rcmode =~ /rt/i) {return '0701';} 
elsif ($rcmode =~ /rr/i) {return '0301';}
elsif ($rcmode =~ /cr/i) {return '0701';} 
else {
LogIt(1,"ICOM l933: Model $imodel: Unable to find code for modulation $rcmode");
return $bytes;
}
}### Modulations other than FM
}### ICR30 Encode
elsif ($imodel eq IC705) {
if ($rcmode =~ /wf/i) {return '0601';}   
elsif ($rcmode =~ /fm/i) {### For FM modulation allow digital
if ($adtype and ($adtype !~ /an/i)) {
if ($adtype =~ /ds/i) {return '1701';} 
else {print "ICOM l9350:$imodel does not support digital mode $adtype\n";}
}
if ($rcmode =~ /fmw/i) {return '0501';}
elsif ($rcmode =~ /fmm/i) {return '0502';}
elsif ($rcmode =~ /fmu/i) {return '0503';} 
else {return '0502';}
}### FM modulation
else {
my $bc = '01';
if ($bw =~ /m/i) {$bc = '02';}
elsif ($bw =~ /n/i) {$bc = '03';}
elsif ($bw =~ /u/i) {$bc = '03';} 
if    ($rcmode =~ /ls/i) {return "00$bc";}   
elsif ($rcmode =~ /us/i) {return "01$bc";}   
elsif ($rcmode =~ /am/i) {return "02$bc";}   
elsif ($rcmode =~ /cw/i) {return "03$bc";}   
elsif ($rcmode =~ /rt/i) {return "04$bc";}   
elsif ($rcmode =~ /cr/i) {return "07$bc";}   
elsif ($rcmode =~ /rr/i) {return "08$bc";}   
else {
LogIt(1,"ICOM l9374: Model $imodel: Unable to find code for modulation $rcmode");
return $bytes;
}
}### All other modulations
}### IC705
elsif ($imodel eq R8600) {
if ($rcmode =~ /wf/i) {return '0601';}   
elsif ($rcmode =~ /fm/i) {### For FM modulation allow digital
my $bc = '02';
if ($bw =~ /w/i) {$bc = '01';}
elsif ($bw =~ /u/i) {$bc = '03';}
if ($adtype and ($adtype !~ /an/i)) {  
if ($adtype =~ /p2/i)    {return "16$bc";}  
elsif ($adtype =~ /ds/i) {return "17$bc";} 
elsif ($adtype =~ /vn/i) {return "19$bc";} 
elsif ($adtype =~ /nx/i) {return "20$bc";} 
else {print "ICOM l9415:$imodel does not support digital mode $adtype\n";}
}
return "05$bc";
}### FM Modulations
else {
my $bc = '01';
if ($bw =~ /m/i) {$bc = '02';}
elsif ($bw =~ /n/i) {$bc = '03';}
elsif ($bw =~ /u/i) {$bc = '03';} 
if    ($rcmode =~ /ls/i) {return "00$bc";}   
elsif ($rcmode =~ /us/i) {return "01$bc";}   
elsif ($rcmode =~ /am/i) {return "02$bc";}   
elsif ($rcmode =~ /cw/i) {return "03$bc";}   
elsif ($rcmode =~ /rt/i) {return "04$bc";}   
elsif ($rcmode =~ /cr/i) {return "07$bc";}   
elsif ($rcmode =~ /rr/i) {return "08$bc";}   
else {
LogIt(1,"ICOM l9435: Model $imodel: Unable to find code for modulation $rcmode");
return $bytes;
}
}
}
else {
if ($rcmode =~ /wf/i)    {return '0601';}   
elsif ($rcmode =~ /fm/i) {return '0501';}   
elsif ($rcmode =~ /ls/i) {return "0001";}   
elsif ($rcmode =~ /us/i) {return "0101";}   
elsif ($rcmode =~ /am/i) {return "0201";}   
elsif ($rcmode =~ /cw/i) {return "0301";}   
elsif ($rcmode =~ /rt/i) {return "0401";}   
elsif ($rcmode =~ /cr/i) {return "0701";}   
elsif ($rcmode =~ /rr/i) {return "0801";}   
else {
LogIt(1,"ICOM l9453: Model $imodel: Unable to find code for modulation $rcmode");
return $bytes;
}
}
}### rcmode2icom
sub icom_sdcard {
my $db = shift @_;
my $sd_hash = shift @_;
my %found_chan = ();
my %group_names = ();
foreach my $frqrec (@{$db->{'freq'}}) {
if (!$frqrec->{'index'}) {next;}
my $recno = $frqrec->{'_recno'};
if (!$recno) {$recno = '??';}
my $emsg = "for record $Green$recno$White";
my $freq = $frqrec->{'frequency'};
if ((!$freq) or (!looks_like_number($freq))) {next;}
if ($frqrec->{'tgid_valid'}) {next;}
my $fullchan = $frqrec->{'channel'};
if ((!looks_like_number($fullchan)) or ($fullchan < 0) ) {
LogIt(0,"$Bold ICOM l8695:Channel number $Green$fullchan$White $emsg is not valid. Skipped");
next;
}
my $chfmt = sprintf("%04.4i",$fullchan);
my $group = substr($chfmt,0,2);
if ($group > 99) {
LogIt(0,"$Bold ICOM l8703:Channel $Green$chfmt$White $emsg is out of range. Skipped");
next;
}
my $channel = substr($chfmt,2,2);
if ($found_chan{$chfmt}) {
LogIt(1,"ICOM l8710:Channel $Green$chfmt$White was found twice $emsg. Second iteration skipped!");
next;
}
$found_chan{$chfmt} = TRUE;
my $freqmhz = Strip(rc_to_freq($freq));
my $groupname = "Group-$group";
my $groupno = $frqrec->{'groupno'};
if ($group_names{$groupno}) {
$groupname = $group_names{$groupno};
}
else {
if ($db->{'group'}[$groupno]{'service'}) {
$groupname = substr($db->{'group'}[$groupno]{'service'},0,16);
}
$group_names{$groupno} = $groupname;
}
my $service = substr($frqrec->{'service'},0,16);
if (!$service) {$service = '-';}
my $digital = FALSE;
my $mode = $frqrec->{'mode'};
if ((!$mode) or ($mode eq '-') or ($mode eq '.')) {
$mode = 'FMn';
}
if ($mode =~ /auto/i) {$mode = AutoMode($freq);}
my $skip = 'OFF';
if (!$frqrec->{'valid'}) {$skip  = 'SKIP';}
foreach my $mdl (keys %sd_format) {
my %sd_data = (
'off'       => 'OFF',
'off_zero'      => '0.000000',
'step'      => '25kHz',
'data'      => 'OFF',
'sdata'     => 'OFF',
'sdup'      => 'OFF',
'groupname' => $groupname,
'service'   => $service,
'freqmhz'   => $freqmhz,
'select'    => 'OFF',
'skip'      => $skip,
'icomgroup' => $group,
'icomch'    => $channel,
'mode'    => $mode,
'bw'      => '',
'offset' => '0.000000',
'split'  => 'OFF',
'dup'    => 'OFF',
'position' => 'None',
'lat'    => 0,
'lon'    => 0,
'ttype' => 'OFF',
'gain'    => 'RFG 7',
'sfreq' => $freqmhz,
'sttype' => 'OFF',
'spolarity' => 'BOTH N',
'sdup'   => 'OFF',
'dcs'    => '023',
'ctcss'  => '88.5Hz',
'sctcss' => '88.5Hz',
'sdcs'   => '23',
'rptr'   => '88.5Hz',
'srptr'  => '88.5Hz',
'polarity' => 'Normal',
'5polarity' => 'BOTH N',
'vsc' => 'OFF',
'dvsq'   => '',
'dvcode' => '',
'p25sql' => '',
'p25nac' => '',
'nxdnsql' => '',
'nxdnran' => '',
'nxdnenc' => '',
'nxdnkey' => '',
);
my $sd_ref = $sd_hash->{$mdl};
if (!check_range($freq,\%{$radio_limits{$mdl}})) {
LogIt(0,"$Bold ICOM 8854. Skipping channel $Green$fullchan$White for $mdl. " .
"$Yellow" . rc_to_freq($freq) . "$White is out of range of radio");
next;
}
if (!$sd_ref) {
my $header = '';
foreach my $rcd (@{$sd_format{$mdl}}) {
foreach my $key (keys %{$rcd}) {
if ($header) {$header = "$header,$key";}
else {$header = $key;}
}
}### For each field in the header
$sd_hash->{$mdl}[0] = "$header\n";
$sd_ref = $sd_hash->{$mdl};
}### Build a header record
my $grpno = $frqrec->{'groupno'};
if ($frqrec->{'scan705'}) {
$sd_data{'select'} = 'SEL' . $frqrec->{'scan705'};
}
elsif ($frqrec->{'scangrp'} and ($frqrec->{'scangrp'} < 4)) {
$sd_data{'select'} = 'SEL' . $frqrec->{'scangrp'};
}
elsif ($grpno and $db->{'group'}[$grpno]{'scan705'}) {
$sd_data{'select'} = $db->{'group'}[$grpno]{'scan705'};
}
elsif ($grpno and $db->{'group'}[$grpno]{'scangrp'} and
($db->{'group'}[$grpno]{'scangrp'} < 4) ) {
$sd_data{'select'} = $db->{'group'}[$grpno]{'scangrp'};
}
else {$sd_data{'select'} = 'OFF';}
if ($frqrec->{'splfreq'}) {
$sd_data{'split'} = 'ON';
$sd_data{'sfreq'} = Strip(rc_to_freq($frqrec->{'sfreq'}));
}
my $bw = substr($mode,2,1);
if (!$bw) {$bw = '';}
if ($mdl eq ICR30) {
if ($mode =~ /wf/i) {$sd_data{'mode'} = 'WFM';}
elsif ($mode =~ /fmm/i) {
$sd_data{'mode'} = 'FM';
if ($frqrec->{'vsc'}) {$sd_data{'vsc'} = 'ON';}
}
elsif ($mode =~ /fm/i) {
$sd_data{'mode'} = 'FM-N';
if ($frqrec->{'vsc'}) {$sd_data{'vsc'} = 'ON';}
}
elsif ($mode =~ /us/i) {
$sd_data{'mode'} = 'USB';
$sd_data{'vsc'} = '';
}
elsif ($mode =~ /ls/i) {
$sd_data{'mode'} = 'LSB';
$sd_data{'vsc'} = '';
}
elsif ($mode =~ /cw/i) {
$sd_data{'mode'} = 'CW';
$sd_data{'vsc'} = '';
}
elsif ($mode =~ /cr/i) {
$sd_data{'mode'} = 'CW-R';
$sd_data{'vsc'} = '';
}
elsif ($mode =~ /am/i) {
if ($bw =~ /n/i) {$sd_data{'mode'} = 'AM-N';}
else {$sd_data{'mode'} = 'AM';}
}
elsif (($mode =~ /rt/i) or ($mode =~ /rr/i)) {
$sd_data{'mode'} = 'LSB';
$sd_data{'vsc'} = '';
}
my $adtype = $frqrec->{'adtype'};
if (!$adtype) {$adtype = 'AN';}
if ($mode =~ /fm/i) {
if ($adtype =~ /ds/i) {
$sd_data{'mode'} = 'DV';
$digital = TRUE;
}
elsif ($adtype =~ /p2/i) {
$sd_data{'mode'} = 'P25';
$digital = TRUE;
}
elsif (($adtype =~ /nx/i) or ($adtype =~ /vn/i))  {
$digital = TRUE;
my $enc = $frqrec->{'enc'};
if (!$enc) {$enc = 1;}
if ($enc and looks_like_number($enc)) {
$sd_data{'nxdnenc'} = 'ON';
$sd_data{'nxdnkey'} = $enc;
}
if ($adtype =~ /vn/i) {$sd_data{'mode'} = 'NXDN-VN';}
else {$sd_data{'mode'} = 'NXDN-N';}
}### NXDN process
}### Mode is FM for digital modulations
}
elsif ($mdl eq IC705) {
$sd_data{'bw'} = 1;
if ($bw =~ /m/i) {$sd_data{'bw'} = 1;}  
elsif ($bw =~ /n/i) {$sd_data{'bw'} = 2;}  
elsif ($bw =~ /u/i) {$sd_data{'bw'} = 3;}  
else {$sd_data{'bw'} = 2;}
if ($mode =~ /wf/i) {
$sd_data{'mode'} = 'WFM';
$sd_data{'bw'} = 1;
}
elsif ($mode =~ /fm/i) {$sd_data{'mode'} = 'FM';}
elsif ($mode =~ /us/i) {$sd_data{'mode'} = 'USB';}
elsif ($mode =~ /ls/i) {$sd_data{'mode'} = 'LSB';}
elsif ($mode =~ /am/i) {$sd_data{'mode'} = 'AM';}
elsif ($mode =~ /cw/i) {$sd_data{'mode'} = 'CW';}
elsif ($mode =~ /cr/i) {$sd_data{'mode'} = 'CW-R';}
elsif ($mode =~ /rt/i) {$sd_data{'mode'} = 'RTTY';}
elsif ($mode =~ /rr/i) {$sd_data{'mode'} = 'RTTY-R';}
else {LogIt(1,"ICOM L9551:No SD decode for mode $mode");}
my $adtype = $frqrec->{'adtype'};
if ($adtype and ($mode =~ /fm/i) and ($adtype =~ /ds/i)) {
$sd_data{'mode'} = 'D-STAR';
$digital = TRUE;
}
}
elsif ($mdl eq IC7300) {
}
my $sqtone = $frqrec->{'sqtone'};
my ($ttype,$tone)  = Tone_Xtract($sqtone);
if (!$tone) {$tone = 'Off';}
if ($digital) {
$sd_data{'ttype'} = '';
$sd_data{'dcs'} = '';
$sd_data{'sctcss'} = '';
$sd_data{'ctcss'} = '';
$sd_data{'polarity'} = '';
$sd_data{'vsc'} = '';
$sd_data{'5polarity'} = '';
$sd_data{'spolarity'} = '';
$sd_data{'dvsq'} = 'OFF';
$sd_data{'dvcode'} = '0';
$sd_data{'p25sql'} = 'OFF';
$sd_data{'p25nac'} = '000';
$sd_data{'nxdnsql'} = 'OFF';
$sd_data{'nxdnran'} = '0';
$sd_data{'nxdnenc'} = 'OFF';
$sd_data{'nxdnkey'} = '1';
if ($mdl ne IC705) {
if ($ttype =~ /dsq/i)   {
$sd_data{'dvsql'} = 'CSQL';
$sd_data{'dvcode'} = $tone;
$sd_data{'p25nac'} = '';
$sd_data{'p25sql'} = '';
$sd_data{'nxdnsql'} = '';
$sd_data{'nxdnran'} = '';
$sd_data{'nxdnenc'} = '';
$sd_data{'nxdnkey'} = '';
}
elsif ($ttype =~ /nac/i)  {
$sd_data{'p25sql'} = 'NAC';
$sd_data{'p25nac'} = $tone;
$sd_data{'dvsql'} = '';
$sd_data{'dvcode'} = '';
$sd_data{'nxdnsql'} = '';
$sd_data{'nxdnran'} = '';
$sd_data{'nxdnenc'} = '';
$sd_data{'nxdnkey'} = '';
}
elsif ($ttype =~ /ran/i) {
$sd_data{'nxdnsql'} = 'RAN';
$sd_data{'nxdnran'} = $tone;
if ($frqrec->{'enc'}) {
$sd_data{'nxdnenc'} = 'ON';
$sd_data{'nxdnkey'} = $frqrec->{'enc'};
}
else {
$sd_data{'nxdnenc'} = 'OFF';
$sd_data{'nxdnkey'} = '1';
}
$sd_data{'dvsql'} = '';
$sd_data{'dvcode'} = '';
$sd_data{'p25nac'} = '';
$sd_data{'p25sql'} = '';
}
}### Not IC-705
}### Digital modulation process
elsif ($mode =~ /fm/i) {  
$sd_data{'ctcss'} = '88.5Hz';
$sd_data{'rptrtone'} = '88.5Hz';
$sd_data{'dcs'} = '023';
if ($mdl eq IC705) {
$sd_data{'DTCS Polarity'} = 'BOTH N';
}
if (($ttype =~ /off/i)) {
$sd_data{'ttype'} = 'OFF';
}
elsif ($ttype =~ /rpt/i) {
if ($mdl eq IC705) {
$tone = sprintf("%03.1f",$tone);
$sd_data{'rptr'} = $tone . 'Hz';
$sd_data{'ttype'} = 'TONE';
$sd_data{'5polarity'} = 'BOTH N';
$sd_data{'spolarity'} = 'BOTH N';
}
else {$sd_data{'ttype'} = 'OFF';}
}
elsif ($ttype =~ /ctc/i) {
$sd_data{'ttype'} = 'TSQL';
$sd_data{'ctcss'} = sprintf("%03.1f",$tone) . 'Hz';
}
elsif ($ttype =~ /dcs/i) {
$sd_data{'ttype'} = 'DTCS';
$sd_data{'dcs'} = sprintf("%03d",$tone);
}
foreach my $fld ('rptr','ctcss','dcs') {
$sd_data{"s$fld"} = $sd_data{$fld};
}
my $spltone = $frqrec->{'spltone'};
if ($spltone) {
my ($stt,$stone) = Tone_Xtract($spltone);
if ($stone) {
if ($stt =~ /rpt/i) {### Repeater type
$sd_data{'srptr'} = sprintf("%03.1f",$stone) . 'Hz';
$sd_data{'sttype'} =  'TONE';
}
elsif ($stt =~ /ctc/i) {### CTCSS
$sd_data{'sctcss'} = sprintf("%03.1f",$stone) . 'Hz';
$sd_data{'sttype'} =   'TSQL';
}
elsif ($stt =~ /dcs/i) {### DCS
$sd_data{'sdcs'} = sprintf("%03u",$stone) ;
$sd_data{'sttype'} =   'DTCS';
}
else {
LogIt(1,"ICOM l9757:ICOM does not support split tone of $spltone");
}
}### $STONE is not 0
}### SPLIT Tone setting
}### FM Analog Tone values
else {
$sd_data{'dcs'} = '';
$sd_data{'ctcss'} = '';
$sd_data{'sctcss'} = '';
$sd_data{'polarity'} = '';
$sd_data{'rptr'} = '';
$sd_data{'srptr'} = '';
$sd_data{'sdcs'} = '';
$sd_data{'ttype'} = '';
$sd_data{'spolarity'} = '';
$sd_data{'5polarity'} = '';
$sd_data{'stone_type'} = '';
}
my $gain = $frqrec->{'rfgain'};
if ($gain) {
if ($gain > 9) {$sd_data{'gain'} = 'RFG MAX';}
else {$sd_data{'gain'} = "RFG$gain";}
}
else {
if ($frqrec->{'atten'} or $frqrec->{'r30att'}) {$sd_data{'gain'} = 'RFG3';}
elsif ($frqrec->{'preamp'}) {$sd_data{'gain'} = 'RFG MAX';}
}
my $outrec = '';
foreach my $rcd (@{$sd_format{$mdl}}) {
foreach my $key (keys %{$rcd}) {
my $rc_key = $rcd->{$key};
my $value = $sd_data{$rc_key};
if (!defined $value) {$value = '';}
if ($outrec) {$outrec = "$outrec,$value";}
else {$outrec = $value;}
}
}### update SD Card fields
push @{$sd_ref},"$outrec\n";
}### For each model
}### For each FREQ record
return $GoodCode;
}### ICOM_SDCard
sub Numerically {
use Scalar::Util qw(looks_like_number);
if (looks_like_number($a) and looks_like_number($b)) { $a <=> $b;}
else {$a cmp $b;}
}
