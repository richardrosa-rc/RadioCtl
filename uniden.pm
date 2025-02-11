#!/usr/bin/perl -w
package uniden;
require Exporter;
@ISA   = qw(Exporter);
@EXPORT = qw(uniden_cmd
Get_XML
Get_SDS_Status
uniden_sdcard
uniden_read_sd
);
use Data::Dumper;
use Text::ParseWords;
use threads;
use threads::shared;
use Thread::Queue;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );
use autovivification;
no  autovivification;
use Scalar::Util qw(looks_like_number);
use radioctl;
use constant FALSE => 0;
use constant TRUE => 1;
use strict;
my $protoname = 'uniden';
use constant PROTO_NUMBER => 1;
$radio_routine{$protoname} = \&uniden_cmd;
$valid_protocols{'uniden'} = TRUE;
my $ready = TRUE;
use constant BCD325P2 => 'BCD325P2';
use constant BCD396T => 'BCD396T';
use constant SDS100 => 'SDS100';
use constant SDS200 => 'SDS200';
my %radio_limits = (
&BCD325P2 => {'minfreq'  =>  25000000,'maxfreq' => 960000000 ,
'gstart_1' => 512000001,'gstop_1' => 758000000 ,
'gstart_2' => 823987501,'gstop_2' => 849012500 ,
'gstart_3' => 868987501,'gstop_3' => 894012500 ,
'memory' => 'dy',
'radioscan' => 2,
},
&BCD396T => {'minfreq'  =>  25000000,'maxfreq' =>1300000000 ,
'gstart_1' => 512000001,'gstop_1' => 764000000 ,
'gstart_2' => 775987501,'gstop_2' => 794000000 ,
'gstart_3' => 823987501,'gstop_3' => 849012500 ,
'gstart_4' => 868987501,'gstop_4' => 894012500 ,
'gstart_5' => 956000001,'gstop_5' =>1240000000 ,
'memory' => 'dy',
'radioscan' => 1,
},
&SDS100  => {'minfreq'  =>  25000000,'maxfreq' =>1300000000 ,
'gstart_1' => 512000001,'gstop_1' => 758000000 ,
'gstart_2' => 824000001,'gstop_2' => 849000000 ,
'gstart_3' => 869000001,'gstop_3' => 894000000 ,
'gstart_4' => 960000001,'gstop_4' =>1240000000 ,
'memory' => 'no dy',
'radioscan' => 2,
},
&SDS200  => {'minfreq'  =>  25000000,'maxfreq' =>1300000000 ,
'gstart_1' => 512000001,'gstop_1' => 758000000 ,
'gstart_2' => 824000001,'gstop_2' => 849000000 ,
'gstart_3' => 869000001,'gstop_3' => 894000000 ,
'gstart_4' => 960000001,'gstop_4' =>1240000000 ,
'memory' => 'no dy',
'radioscan' => 2,
},
);
my %service_search = ( 1 => 'Public Safety',
2 => "News",
3 => "HAM Radio",
4 => "Marine",
5 => "Railroad",
6 => "Air",
7 => "CB Radio",
8 => "FRS/GMRS/MURS",
9 => "Racing",
10 => "TV Broadcast",
11 => "FM Broadcast",
12 => "Special",
15 => "Military Air",
);
my $queue_head  = -1;
my $queue_tail  = -1;
my %blocks = (
SIN => [
{'block_addr'   => 'q'},
{'systemtype'   => 'r'},
{'service'      => 'b'},
{'qkey'         => 'b'},
{'hld'          => 'b'},
{'lout'         => 'b'},
{'dlyrsm'       => 'b'},
{'skip'         => 'b'},
{'mode'         => 'b'},
{'atten'        => 'b'},
{'p25mode'      => 'b'},
{'p25lvl'       => 'b'},
{'rev_index'    => 'r'},
{'fwd_index'    => 'r'},
{'chn_head'     => 'r'},
{'chn_tail'     => 'r'},
{'seq_no'       => 'r'},
{'start_key'    => '3'},
{'rsvd'         => '3'},
{'rsvd'         => '3'},
{'rsvd'         => '3'},
{'rsvd'         => '3'},
{'rsvd'         => '3'},
{'rsvd'         => 'x'},
{'utag'         => '3'},
{'agc_analog'   => '3'},
{'agc_digital'  => '3'},
{'p25wait'      => '3'},
{'protect'      => 's'},
{'rsvd'         => 's'},
],
SIF => [
{'block_addr'   => 'q'},
{'rsvd'         => 'r'},
{'service'      => 'b'},
{'qkey'         => 'b'},
{'hld'          => 'b'},
{'lout'         => 'b'},
{'mode'         => 'b'},
{'atten'        => 'b'},
{'c_ch'         => 'b'},
{'rsvd'         => 'b'},
{'rsvd'         => 'b'},
{'rev_index'    => 'r'},
{'fwd_index'    => 'r'},
{'sys_index'    => 'r'},
{'chn_head'     => 'r'},
{'chn_tail'     => 'r'},
{'seq_no'       => 'r'},
{'start_key'    => 'b'},
{'lat',         => 'b'},
{'lon',         => 'b'},
{'radius'       => 'b'},
{'gps_enable'   => 'b'},
{'rsvd'         => 'b'},
{'mot_type'     => 'b'},
{'edacs_type'   => 'b'},
{'p25wait'      => 'b'},
{'rsvd'         => 'b'},
],
TRN => [
{'block_addr'   => 'q'},
{'id_search'    => 'b'},
{'s_bit'        => 'b'},
{'endcode'      => 'b'},
{'afs'          => 'b'},
{'i_call'       => 'b'},
{'c_ch'         => 'b'},
{'emgalt'       => 'b'},
{'emglvl'       => 'b'},
{'fleetmap'     => 'b'},
{'custmap'      => 'b'},
{'frequency_l1' => 'b'},
{'spacing_1'    => 'b'},
{'offset_1'     => 'b'},
{'frequency_l2' => 'b'},
{'spacing_2'    => 'b'},
{'offset_2'     => 'b'},
{'frequency_l3' => 'b'},
{'spacing_3'    => 'b'},
{'offset_3'     => 'b'},
{'mfid'         => 'b'},
{'chn_head'     => 'r'},
{'chn_tail'     => 'r'},
{'lo_head'      => 'r'},
{'lo_tail'      => 'r'},
{'moto_id'      => '3'},
{'emgcol'       => '3'},
{'emgpat'       => '3'},
{'dsql'         => '3'},
{'priority'     => '3'},
],
TFQ  => [
{'block_addr'   => 'q'},
{'frequency'    => 'b'},
{'lcn'          => 'b'},
{'lout'         => 'b'},
{'rev_index'    => 'r'},
{'fwd_index'    => 'r'},
{'sys_index'    => 'r'},
{'site_index'   => 'r'},
{'rsvd'         => '3'},
{'utag'         => '3'},
{'voloff'       => '3'},
{'rsvd'         => '3'},
{'ccode'        => '3'},
],
GIN => [
{'block_addr'   => 'q'},
{'grp_type'     => 'r'},
{'service'      => 'b'},
{'qkey'         => 'b'},
{'lout'         => 'b'},
{'rev_index'    => 'r'},
{'fwd_index'    => 'r'},
{'sys_index'    => 'r'},
{'chn_head'     => 'r'},
{'chn_tail'     => 'r'},
{'seq_no'       => 'r'},
{'lat',              => '3'},
{'lon',               => '3'},
{'radius',      => '3'},
{'gps_enable'   => '3'},
],
MCP => [
{'block_addr'   => 'q'},
{'frequency_l1' => 'b'},
{'frequency_u1' => 'b'},
{'spacing_1'    => 'b'},
{'offset_1'     => 'b'},
{'frequency_l2' => 'b'},
{'frequency_u2' => 'b'},
{'spacing_2'    => 'b'},
{'offset_2'     => 'b'},
{'frequency_l3' => 'b'},
{'frequency_u3' => 'b'},
{'spacing_3'    => 'b'},
{'offset_3'     => 'b'},
{'frequency_l4' => 'b'},
{'frequency_u4' => 'b'},
{'spacing_4'    => 'b'},
{'offset_4'     => 'b'},
{'frequency_l5' => 'b'},
{'frequency_u5' => 'b'},
{'spacing_5'    => 'b'},
{'offset_5'     => 'b'},
{'frequency_l6' => 'b'},
{'frequency_u6' => 'b'},
{'spacing_6'    => 'b'},
{'offset_6'     => 'b'},
],
TIN =>[
{'block_addr'   => 'q'},
{'service'      => 'b'},
{'tgid'         => 'b'},
{'lout'         => 'b'},
{'priority'     => 'b'},
{'emgalt'       => 'b'},
{'emglvl'       => 'b'},
{'rev_index'    => 'r'},
{'fwd_index'    => 'r'},
{'sys_index'    => 'r'},
{'grp_index'    => 'r'},
{'rsvd'         => '3'},
{'audio'        => '3'},
{'utag'         => '3'},
{'emgcol'       => '3'},
{'emgpat'       => '3'},
{'voloff'       => '3'},
{'tslot'        => '3'},
],
CIN =>[
{'block_addr'   => 'q'},
{'service'      => 'b'},
{'frequency'    => 'b'},
{'mode'         => 'b'},
{'ctcsdcs'      => 'b'},
{'tonelock'     => 'b'},
{'lout'         => 'b'},
{'priority'     => 'b'},
{'atten'        => 'b'},
{'emgalt'       => 'b'},
{'emglvl'       => 'b'},
{'rev_index'    => 'r'},
{'fwd_index'    => 'r'},
{'sys_index'    => 'r'},
{'grp_index'    => 'r'},
{'rsvd'         => '3'},
{'audio'        => '3'},
{'dsql'         => '3'},
{'utag'         => '3'},
{'emgcol'       => '3'},
{'emgpat'       => '3'},
{'voloff'       => '3'},
],
ACC =>[
{'block_base'   => 'q'},
{'block_addr'   => 'r'},
],
ACT =>[
{'block_base'   => 'q'},
{'block_addr'   => 'r'},
],
AGC =>[
{'block_base'   => 'q'},
{'block_addr'   => 'r'},
],
AGT =>[
{'block_base'   => 'q'},
{'block_addr'   => 'r'},
],
AST =>[
{'block_base'   => 'q'},
{'rsvd'         => 'w'},
{'block_addr'   => 'r'},
],
REV =>[
{'block_base'   => 'q'},
{'block_addr'   => 'r'},
],
FWD =>[
{'block_base'   => 'q'},
{'block_addr'   => 'r'},
],
DSY => [
{'block_addr'   => 'q'},
],
DGR => [
{'block_addr'   => 'q'},
],
AGV => [
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'a_response'  => 'b'},
{'a_reference' => 'b'},
{'a_gain'      => 'b'},
{'d_response'  => 'b'},
{'d-gain'      => 'b'},
{'rsvd'        => 'b'},
],
BAV => [{'bat_level'  => 'r'}],
BLT => [
{'event'       => 'b'},
{'rsvd'        => '3'},
{'bright'      => '3'},
],
BSV => [
{'bat_save'    => 'b'},
{'charge_time' => 'b'},
],
DBC => [
{'band_no'      => 'q'},
{'step'         => 'b'},
{'mode'         => 'b'},
],
CIE => [
{'frequency'    => 'q'},
],
CLC => [
{'cc_mode'      => 'b'},
{'cc_ovrd'      => 'b'},
{'rsvd'         => 'b'},
{'emgalt'       => 'b'},
{'al_lvl'       => 'b'},
{'pause'        => 'b'},
{'cc_band'      => 'b'},
{'lout'         => 'b'},
{'hld'          => 'b'},
{'qkey'         => 'b'},
{'utag'         => 'b'},
{'emgcol'       => 'b'},
{'emgpat'       => 'b'},
],
CNT => [
{'contrast'     => 'b'},
],
CSP => [
{'channel'     => 'q'},
{'service'     => 'b'},
{'end_freq'    => 'b'},
{'start_freq'  => 'b'},
{'step'        => 'b'},
{'mode'        => 'b'},
{'atten'       => 'b'},
{'dlyrsm'      => 'b'},
{'skp'         => 'b'},
{'hld'         => 'b'},
{'lout'        => 'b'},
{'c_ch'        => 'b'},
{'p25mode'     => 'b'},
{'p25lvl'      => 'b'},
{'qkey'         => '3'},
{'start_key'    => '3'},
{'rsvd'         => '3'},
{'utag'         => '3'},
{'agc_analog'   => '3'},
{'agc_digital'  => '3'},
{'p25wait'      => '3'},
],
CSY => [
{'systemtype'   => 'q'},
{'protect'     => 'x'},
{'block_addr'  => 'r'},
],
GID => [
{'systemtype'  => 'r'},
{'tgid'        => 'r'},
{'id_srch'     => 'r'},
{'sitename'    => 'r'},
{'groupname'   => 'r'},
{'service'     => 'r'},
],
GIE => [
{'frequency'    => 'r'},
],
GLF => [
{'frequency'    => 'r'},
],
GLG => [
{'frq_tgid'    => 'r'},
{'mode'        => 'r'},
{'atten'       => 'r'},
{'ctcsdcs'     => 'r'},
{'systemname'  => 'r'},
{'groupname'   => 'r'},
{'service'     => 'r'},
{'sql'         => 'r'},
{'mute'        => 'r'},
{'sys_tag'     => 'r'},
{'ch_tag'      => 'r'},
{'dsql'        => 'r'},
],
JPM => [
{'jmp_mode'    => 'q'},
{'jmp_index'   => 'w'},
],
JNT => [
{'sys_tag'     => 'w'},
{'ch_tag'      => 'w'},
],
KEY => [
{'key_code'    => 'q'},
{'key_mode'    => 'q'},
],
KBP => [
{'beep'        => 'b'},
{'lock'        => '3'},
{'safe'        => '3'},
],
LOF => [
{'frequency'    => 'q'},
],
MEM => [
{'mem_used'    => 'r'},
{'sys_count'   => 'r'},
{'site_count'  => 'r'},
{'chan_count'  => 'r'},
{'loc_count'   => 'r'},
],
MDL => [{'model'      => 'r'}],
MNU => [{'menu_ndx'   => 'q'}],
OMS => [
{'msg1'        => 'b'},
{'msg2'        => 'b'},
{'msg3'        => 'b'},
{'msg4'        => 'b'},
],
P25 => [
{'rsvd'        => 'r'},
{'rsvd'        => 'r'},
{'err_rate'    => 'r'},
],
PRI => [
{'pri_mode'    => 'b'},
{'max_chan'    => 'b'},
{'interval'    => 'b'},
],
PWR => [
{'rssi'        => 'r'},
{'freq'        => 'r'},
],
QSH => [
{'frequency'    => 'q'},
{'rsvd'         => 'w'},
{'mode'         => 'w'},
{'atten'        => 'w'},
{'dlyrsm'       => 'w'},
{'rsvd'         => 'w'},
{'code_srch'    => 'w'},
{'bsc'          => 'w'},
{'rep'          => 'w'},
{'rsvd'         => 'xy'},
{'agc_analog'   => 'xy'},
{'agc_digital'  => 'xy'},
{'p25wait'   => 'xy'},
],
QSC =>[
{'frequency'    => 'q'},
{'rsvd'         => 'w'},
{'mode'         => 'w'},
{'atten'        => 'w'},
{'dlyrsm'       => 'w'},
{'rsvd'         => 'w'},
{'code_srch'    => 'w'},
{'bsc'          => 'w'},
{'rep'          => 'w'},
{'rsvd'         => 'w'},
{'agc_analog'   => 'w'},
{'agc_digital'  => 'w'},
{'p25wait'      => 'w'},
{'rssi'         => 'r'},
{'frequency'    => 'r'},
{'sql'          => 'r'},
],
RIE => [
{'frequency'    => 'q'},
],
RMB => [### Number of free blocks
{'mem_free'    => 'r'},
],
SCN => [
{'disp_mode'   => 'b'},
{'rsvd'        => 'b'},
{'cc_logging'  => 'b'},
{'atten'       => 'b'},
{'rsvd'        => 'b'},
{'p25_lpf'     => 'b'},
{'disp_uid'    => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
{'rsvd'        => 'b'},
],
SCT => [{'system_cnt' => 'r'}],
SIH => [{'block_addr' => 'r'}],
SIT => [{'block_addr' => 'r'}],
SQL => [{'squelch'    => 'b'}],
SSP =>[
{'channel'     => 'q'},
{'channel'     => 'r'},
{'dlyrsm'      => 'b'},
{'atten'       => 'b'},
{'hld'         => 'b'},
{'lout'        => 'b'},
{'qkey'         => '3'},
{'start_key'    => '3'},
{'rsvd'         => '3'},
{'utag'         => '3'},
{'agc_analog'   => '3'},
{'agc_digital'  => '3'},
{'p25wait'      => '3'},
],
TON => [### Tone-out settings
{'channel'     => 'q'},
{'service'     => 'b'},
{'frequency'   => 'b'},
{'mode'        => 'b'},
{'atten'       => 'b'},
{'dlyrsm'      => 'b'},
{'emgalt'      => 'b'},
{'emglvl'      => 'b'},
{'toneout_a'   => 'b'},
{'dur'         => 'b'},
{'toneout_b'   => 'b'},
{'dur'         => 'b'},
{'dur'         => 'b'},
{'rsvd'        => '3'},
{'emgcol'      => '3'},
{'emgpat'      => '3'},
{'agc_analog'  => '3'},
{'rsvd'        => '3'},
{'rsvd'        => '3'},
],
ULF => [
{'frequency'    => 'q'},
],
VER => [{'version'    => 'r'}],
VOL => [{'vol_level'  => 'b'}],
WIN => [{'w_voltage'  => 'r'}],
);
my %nodata = (
'CLR'=>TRUE,
'EPG'=>TRUE,
'POF'=>TRUE,
'PRG'=>TRUE,
'nop'=>TRUE,
);
my %special = ('CLR' => {'delay' => 10000,'wait' => 200 },
'PRG' => {'delay' => 1000,'wait' => 50, 'resend' => 1, 'fails'=> 1},
'EPG' => {'delay' => 1000,'wait' => 50, 'resend' => 1, 'fails'=> 1},
'DSY' => {'delay' => 5000,'wait' => 50, },
'MDL' => {'delay' =>  100,'wait' =>  5, 'fails'=> 1},
);
my %unsolicited = ('DMR' => TRUE,'EDW'=> TRUE,'CSC'=> TRUE);
$struct_fields{'rev_index'}    = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'fwd_index'}    = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'sys_index'}    = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'site_index'}   = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'grp_index'}    = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'chn_head'}     = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'chn_tail'}     = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'lo_head'}      = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'lo_tail'}      = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'system_cnt'}   = ['i', 5,0,     0,0,'.'     ,0,];
$struct_fields{'grp_type'}     = ['c', 1,'a',  '', 0,0       ,0,];
$struct_fields{'block_type'}     = ['c', 1,'a',  '', 0,0       ,0,];
$struct_fields{'ctcsdcs'}      = ['i', 2,0,    '', 0,239     ,0,];
$struct_fields{'seq_no'}       = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'lout'}         = ['b', 1,0,     0,0,1        ,0,];
$struct_fields{'tonelock'}       = ['b', 1,0,     0,0,1      ,0,];
$struct_fields{'color_code'}   = ['i', 2,0,     0,0,15       ,0,'SRCH'];
$struct_fields{'audio'}        = ['i', 1,0,     0,0,2        ,0,];
$struct_fields{'base1'}        = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'base2'}        = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'base3'}        = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'step1'}        = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'step2'}        = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'step3'}        = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'offset1'}      = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'offset2'}      = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'offset3'}      = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'mfid'}         = ['n', 1,'a',  '',0,2        ,0];
$struct_fields{'lock'}         = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'safe'}         = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'start_key'}    = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'gps_enable'}   = ['b', 1,0,     0,0,1        ,0,];
$struct_fields{'protect'}      = ['b', 1,0,     0,0,1        ,0,];
$struct_fields{'rep'}          = ['b', 1,0,     0,0,1        ,0,];
$struct_fields{'bsc'}          = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'frq_tgid'}    = ['c', 10,'a',  '',0,0        ,0];
$struct_fields{'ch_name'}     = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'mute'   }     = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'ch_tag' }     = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'sys_tag'}     = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'cconly'}      = ['b', 1,0,     0,0,1        ,0,];
$struct_fields{'block_base'}  = ['i', 5,0,    -1,-1,'.'     ,0,];
$struct_fields{'code_srch'}   = ['i', 1,0,     0,0,2        ,0,];
$struct_fields{'syskeys'} = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'grpkeys'} = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'key_code'}    = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'key_mode'}    = ['c', 1,'a',  '',0,0        ,0];
$struct_fields{'dur'}         = ['c', 5,0  ,   0.0,1        ,0];
push @{$struct_fields{'systemtype'}},'edc';
my %state_save = (
'state' => '',
);
my $last_tgid = '';
my $last_mode = '';
my $setit = FALSE;
my $dbgfile = "/tmp/radioctl.log";
my $bcd325p2 = FALSE;
my $model = '';
my $warn = TRUE;
my %rssi2sig = (### SDSx00 radios the RSSI is in DBMV
'sds' => [-200,-115,-110,-107,-104,-102,-100 ,-98, -95,   0],
'bcd396t' => [134, 320, 350, 375, 400, 425, 450, 475, 500,  999],
'bcd325p2' => [201, 285, 300, 308, 320, 340, 350, 361, 400,  999],
);
my @sig2meter = (0,1,2,2,3,3,4,4,5,5);
my @meter2sig = ( 0,2,4,5,8,9);
my %system_qkeys = ();
my %bcd396_systypes = (
'cnv' => 'CNV',
'ltr' => 'LTR',
'eds' => 'EDS',
'edw' => 'EDW',
'edn' => 'EDN',
'mots' => 'M82S',
'motp' => 'M82P',
'motc' => 'M92',
'p25s' => 'MP25',
'p25f' => 'MP25',
);
my %systypes_bcd396 = (
'm82s' => 'mots',
'm82p' => 'motp',
'm92'  => 'motc',
'mp25' => 'p25s',
'm81p' => 'motp',
'mv2'  => 'mots',
'mu2'  => 'mots',
'm81s' => 'mots',
);
my %bcd325p2_systypes = (
'eds' => 'EDC',
'edw' => 'EDC',
'edn' => 'EDC',
'mots' => 'MOT',
'motp' => 'MOT',
'motc' => 'MOT',
);
my %systypes_bcd325p2 = (
'edc' => 'edw',
'mot' => 'mots',
);
my %sds_systypes = (
'ltr'   => 'Ltr',
'dmr'   => 'DmrOneFrequency',
'nxdn'  => 'Nxdn',
'nxdn1' => 'NxdnOneFrequency',
'eds'   => 'Scat',
'edw'   => 'Edacs',
'edn'   => 'Edacs',
'p25s'  => 'P25Standard',
'p25f'  => 'P25OneFrequency',
'p25x'  => 'P25X2_TDMA',
'trbo'  => 'MotoTrbo',
'turbo' => 'MotoTrbo',
'mots'  => 'Motorola',
'motp'  => 'Motorola',
'motc'  => 'Motorola',
'cnv'   => 'Conventional',
);
my %sds2rctype = (
'edacs' => 'edw',
'scat'  => 'eds',
'ltr'   => 'ltr',
'motorola' => 'mots',
'p25standard' => 'p25s',
'mototrbo'   => 'trbo',
'dmronefrequency' => 'dmr',
'nxdn'  => 'nxdn',
'nxdnonefrequency' => 'nxdn1',
);
my %hpdrecs = (
'conventional' => ['myid','parent','service','avoid','rsvrd','systemtype',
'qkey','utag','hld','agc_analog','agc_digital','p25wait','p25mode','p25lvl'],
'trunk' => ['myid','parent','service','avoid','rsvrd','systemtype',
'id_search','emgalt','emglvl','s_bit','dsql',
'qkey','utag','hld','agc_analog','agc_digital',
'endcode','priority','emgcol','emgpat','tgid_fmt'],
'c-freq' => [ 'myid','parent','service','avoid','frequency','mode',
'squelch', 'svcode','dlyrsm','voloff','emgalt','emglvl','emgcol','emgpat',
'utag','priority'],
'site'   => [ 'myid','parent','service','avoid','lat','lon','radius',
'mode','mottype','edacstype','loc_type','atten',
'p25wait','p25mode','p25lvl','qkey','dsql','filter'],
't-freq' => [ 'myid','parent','rsvrd','avoid','frequency','lcn','ccran'],
'bandplan_mot' => [ 'myid','frequency_l1','frequency_u1','spacing_1','offset_1',
'frequency_l2','frequency_u2','spacing_2','offset_2',
'frequency_l3','frequency_u3','spacing_3','offset_3',
'frequency_l4','frequency_u4','spacing_4','offset_4'],
'fleetmap' => [ 'myid','b0','b1','b2','b3','b4','b5','b6','b7'],
't-group' => [ 'myid','parent','service','avoid','lat','lon','radius',
'loc_type','qkey'],
'c-group' => [ 'myid','parent','service','avoid','lat','lon','radius',
'loc_type','qkey','filter'],
'c-freq'  => [ 'myid','parent','service','avoid','frequency','mode','squelch',
'svcode','atten','dlyrsm','voloff','emgalt','emglvl','emgcol','emgpat',
'utag','priority'],
'tgid'  => [ 'myid','parent','service','avoid','tgid','adtype',
'svcode','dlyrsm','voloff','emgalt','emglvl','emgcol','emgpat',
'utag','priority','tslot'],
'f-list'  => ['name','filename','locctl','monitor','qkey','utag',
'start0','start1','start2','start3','start4','start5',
'start6','start7','start8','start9',
'qk_0','qk_1','qk_2','qk_3','qk_4','qk_5','qk_6','qk_7','qk_8','qk_9',
'qk_10','qk_11','qk_12','qk_13','qk_14','qk_15','qk_16','qk_17','qk_18','qk_19',
'qk_20','qk_21','qk_22','qk_23','qk_24','qk_25','qk_26','qk_27','qk_28','qk_29',
'qk_30','qk_31','qk_32','qk_33','qk_34','qk_35','qk_36','qk_37','qk_38','qk_39',
'qk_40','qk_41','qk_42','qk_43','qk_44','qk_45','qk_46','qk_47','qk_48','qk_49',
'qk_50','qk_51','qk_52','qk_53','qk_54','qk_55','qk_56','qk_57','qk_58','qk_59',
'qk_60','qk_61','qk_62','qk_63','qk_64','qk_65','qk_66','qk_67','qk_68','qk_69',
'qk_70','qk_71','qk_72','qk_73','qk_74','qk_75','qk_76','qk_77','qk_78','qk_79',
'qk_80','qk_81','qk_82','qk_83','qk_84','qk_85','qk_86','qk_87','qk_88','qk_89',
'qk_90','qk_91','qk_92','qk_93','qk_94','qk_95','qk_96','qk_97','qk_98','qk_99',],
'dqks_status' => ['myid',
'qk_0','qk_1','qk_2','qk_3','qk_4','qk_5','qk_6','qk_7','qk_8','qk_9',
'qk_10','qk_11','qk_12','qk_13','qk_14','qk_15','qk_16','qk_17','qk_18','qk_19',
'qk_20','qk_21','qk_22','qk_23','qk_24','qk_25','qk_26','qk_27','qk_28','qk_29',
'qk_30','qk_31','qk_32','qk_33','qk_34','qk_35','qk_36','qk_37','qk_38','qk_39',
'qk_40','qk_41','qk_42','qk_43','qk_44','qk_45','qk_46','qk_47','qk_48','qk_49',
'qk_50','qk_51','qk_52','qk_53','qk_54','qk_55','qk_56','qk_57','qk_58','qk_59',
'qk_60','qk_61','qk_62','qk_63','qk_64','qk_65','qk_66','qk_67','qk_68','qk_69',
'qk_70','qk_71','qk_72','qk_73','qk_74','qk_75','qk_76','qk_77','qk_78','qk_79',
'qk_80','qk_81','qk_82','qk_83','qk_84','qk_85','qk_86','qk_87','qk_88','qk_89',
'qk_90','qk_91','qk_92','qk_93','qk_94','qk_95','qk_96','qk_97','qk_98','qk_99',],
'areastate' => ['myid'],
'areacounty' => ['myid'],
);
my %filter2sds = (
'n' => 'Normal',
'g' => 'Global',
'i' => 'Invert',
'a' => 'Auto',
'nw' => 'Normal Wide',
'gw' => 'Global Wide',
'iw' => 'Invert Wide',
'o'  => 'Off'
);
my $f_eol = "\r\n";
my $tab = "\t";
my $header_l1 = "TargetModel$tab" . "BCDx36HP$f_eol";
my $header_l2 = "FormatVersion$tab" . "1.00$f_eol";
TRUE;
sub uniden_cmd {
my ($package,$caller,$callerline) = caller();
my $cmdcode = shift @_;
my $parmref = shift @_;
my $defref    = $parmref->{'def'};
my $out  = $parmref->{'out'};
my $outsave = $out;
my $in   = $parmref->{'in'};
my $insave = $in;
my $portobj = $parmref->{'portobj'};
my $db = $parmref->{'database'};
if ($db) {
}
else {$db = '';}
my $write = $parmref->{'write'};
if (!$write) {$write = FALSE;}
my $retcode = 0;
my $cmd_parms = '';
my $noprocess = FALSE;
$parmref->{'term'} = CR;
my $delay = 100;
if (!defined $radio_def{'model'}) {
LogIt(1,"Uniden L2022:No Model number was defined for this radio!");
$radio_def{'model'} = '';
}
if ($radio_def{'model'} ne 'BCD325P2') {$delay = 400;}
my @send_validate = ();
my @rcv_validate = ();
my $blockname = $cmdcode;
if ($cmdcode eq 'init') {
my %myout = ();
$parmref->{'out'} = \%myout;
if (uniden_cmd('MDL',$parmref)) {return $parmref->{'rc'};}
if ($model eq 'BCD325P2') {
$bcd325p2 = TRUE;
if ($Debug1) {DebugIt("UNIDEN l2216: Model returned $model");}
}
if ($model !~ /sda/i)   {
if (uniden_cmd('STS',$parmref)) {return  $parmref->{'rc'};}
if ($myout{'state'} =~ /prg/i)  {exit_prg($parmref);}
elsif ($myout{'state'} =~ /mnu/i) {
%myout = ('key_code' => 'H','key_mode' => 'P');
$parmref->{'out'} = \%myout;
uniden_cmd('KEY',$parmref);
uniden_cmd('STS',$parmref);
}
}
$parmref->{'out'} = $outsave;
$out = $outsave;
$out->{'model'} = $model;
foreach my $key (keys %{$radio_limits{$model}}) {
$defref->{$key} = $radio_limits{$model}{$key};
}
@gui_modestring = ('WFM','FM','AM');
@gui_bandwidth  = ('(none)','Narrow','Ultra-Narrow');
@gui_adtype = ();
@gui_attstring = ('Off','Attenuation');
@gui_tonestring = ();
$defref->{'radioscan'} = 2;
$defref->{'model'} = $model;
$defref->{'maxchan'} = -1;
uniden_cmd('getvfo',$parmref);
uniden_cmd('getsig',$parmref);
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'autobaud') {
if (!$defref->{'model'}) {
LogIt(1,"Model number not specified in .CONF file. " .
" Cannot automatically determine port/baud");
return ($parmref->{'rc'} = 1);
}
my $model_save = $defref->{'model'};
my @allports = ();
if ($in->{'noport'} and $defref->{'port'}) {push @allports,$defref->{'port'};}
else {
if (lc($model_save) ne 'bcd396t') {@allports = glob("/dev/ttyACM*");}
else {push @allports,glob("/dev/ttyUSB*");}
}
my @allbauds = ();
if ($in->{'nobaud'}) {push @allbauds,$defref->{'baudrate'};}
else {push @allbauds,115200;}
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
my $rc = uniden_cmd('MDL',$parmref);
$warn = TRUE;
if (!$rc) {### command succeeded
if ($model and ($model eq $model_save)) {
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
if ($cmdcode eq 'manual') {
my $outsave = $parmref->{'out'};
uniden_cmd('STS',$parmref);
if (($state_save{'state'}  =~ /scan/i) or ($state_save{'state'} =~ /srch/i)) {
if ($state_save{'state'} !~ /hold/i) {
my %myout = ('jpm_state' => 'SCN_MODE');
$parmref->{'out'} = \%myout;
$parmref->{'out'} = \%myout;
%myout = ('key_code' => 'H','key_mode' => 'P');
if ($model eq 'SDS200') {
$myout{'key_code'} = 'C';
}
uniden_cmd('KEY',$parmref);
$parmref->{'out'} = $outsave;
}
}
if ($model ne 'SDS200') {
uniden_cmd('GLG',$parmref);
}
uniden_cmd('getsig',$parmref);
return ($parmref->{'rc'} = $GoodCode);
}
if ($cmdcode eq 'vfoinit') {
if ($state_save{'state'} =~ /quick\-hold/i) {
return ($parmref->{'rc'} = $GoodCode);
}
my %myout = ();
my $outsave = $parmref->{'out'};
$parmref->{'out'} = \%myout;
if ($defref->{'radioscan'} == 2) {
%myout = ('jpm_state' => 'QSH_MODE');
uniden_cmd('JPM',$parmref);
$parmref->{'out'} = \%myout;
%myout = ('key_code' => 'H','key_mode' => 'P');
if ($model eq 'SDS200') {
$myout{'key_code'} = 'C';
}
uniden_cmd('KEY',$parmref);
}
else {
if (check_range($vfo{'frequency'},$defref)) {
$myout{'frequency'} = $vfo{'frequency'};
}
else {$myout{'frequency'} = $defref->{'minfreq'};}
$myout{'code_srch'} = 0;
$myout{'bsc'} = '0000000000000000';
$myout{'rep'} = 0;
$myout{'agc_analog'} = 0;
$myout{'agc_digital'} = 0;
$myout{'p25wait'} = 400;
uniden_cmd('QSH',$parmref);
}
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
if ($cmdcode eq 'meminit') {
if ($state_save{'state'} =~ /scan\-hold/i) {
return ($parmref->{'rc'} = $GoodCode);
}
my %myout = ();
my $outsave = $parmref->{'out'};
$parmref->{'out'} = \%myout;
if ($defref->{'radioscan'} == 2) {
%myout = ('jpm_state' => 'SCN_MODE');
uniden_cmd('JPM',$parmref);
$parmref->{'out'} = \%myout;
%myout = ('key_code' => 'H','key_mode' => 'P');
if ($model eq 'SDS200') {
$myout{'key_code'} = 'C';
}
uniden_cmd('KEY',$parmref);
}
else {
if ($state_save{'state'} =~ /srch/i) { 
my %myout = ('key_code' => 'S','key_mode' => 'P');
$parmref->{'out'} = \%myout;
uniden_cmd('KEY',$parmref);
uniden_cmd('STS',$parmref);
}
if ($state_save{'state'} =~ /scan/) {
my %myout = ('key_code' => 'H','key_mode' => 'P');
$parmref->{'out'} = \%myout;
uniden_cmd('KEY',$parmref);
uniden_cmd('STS',$parmref);
}
}
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}### MEMINIT
if ($cmdcode eq 'scan'   ) {
if ($defref->{'radioscan'} == 2) {
my %myout = ('jpm_state' => 'SCN_MODE');
$parmref->{'out'} = \%myout;
uniden_cmd('JPM',$parmref);
uniden_cmd('STS',$parmref);
$parmref->{'out'} = $outsave;
$out = $outsave;
return ($parmref->{'rc'});
}
}
if ($cmdcode eq 'selmem') {
return ($parmref->{'rc'} = $NotForModel);
}
elsif ($cmdcode eq '_getall') {
if (lc($model) eq 'sds200') {
LogIt(1,"Cannot issue _getall for SDS200");
return ($parmref->{'rc'} = 11);
}
LogIt(0,"GETALL l2432:Starting GETALL state=>$state_save{'state'}\n");
my $options = $parmref->{'options'};
my $firstnum = $options->{'firstsys'};
if ((!$firstnum) or ($firstnum < 0)) {$firstnum = 0;}
my $count = $options->{'count'};
if (!$count) {$count = 0;}
my $notrunk = $options->{'notrunk'};
my $blk_ref = $options->{'blk'};
my $nam_ref = $options->{'nam'};
if ($blk_ref) {$nam_ref = '';}
$retcode = 0;
my $db = $parmref->{'database'};
if (enter_prg($parmref)) {
add_message("_GETALL: command failed to get Uniden into program state!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
%system_qkeys = ();
if (uniden_cmd('QSL',$parmref)) {
exit_prg($parmref,"_GETALL:Could not fetch SYSTEM quick-keys!");
return 11;
}
my $outstr = '';
foreach my $qkey (0..99) {
my $value = $system_qkeys{$qkey};
if (!defined $value) {$value = '-';}
$outstr = "$outstr$value";
}
$work_blk{'syskeys'} = $outstr;
add_a_record($db,'syskey',\%work_blk);
my %used_qkeys = ();
if (uniden_cmd('SIH',$parmref)) {
exit_prg($parmref,"_GETALL:Could not fetch System Start (SIH)");
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
my $sin_index = $work_blk{'block_addr'};
my $system_count = 0;
my $system_number = 0;
SINLOOP:
while ($sin_index ne '-1') {
%work_blk = ('block_addr' => $sin_index);
if (uniden_cmd('SIN',$parmref)) {
exit_prg($parmref,"_GETALL:Could not fetch Uniden System Info block (SIN) =$sin_index!");
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'});
}
$system_number++;
$work_blk{'valid'} = !$work_blk{'lout'};
my $systemname = $work_blk{'service'};
my $systemtype = lc($work_blk{'systemtype'});
if (!$systemtype) {
print Dumper(%work_blk),"\n";
print Dumper($parmref),"\n";
LogIt(1,"Uniden l2740:Bad SYSTEMTYPE in SIN");
return ($parmref->{'rc'} = $NotForModel);
}
my $qkey = $work_blk{'qkey'};
if (looks_like_number($qkey) and ($qkey >= 0)) {
if ($used_qkeys{$qkey}) {### warn about multiple assignments
$used_qkeys{$qkey} = "$used_qkeys{$qkey},$systemname";
LogIt(1,"Uniden l2556:Multiple systems assigned to system quickkey $qkey:$used_qkeys{$qkey}");
}
else {$used_qkeys{$qkey} = $systemname;}
if (!defined $system_qkeys{$qkey}) {
print Dumper(%work_blk),"\n";
LogIt(1,"Uniden l7777:Quickkey $qkey set in SYSTEM $work_blk{'service'} ($sin_index) but Not returned by 'QSL'!");
}
}### Key is defined
else {
if (($systemtype eq 'cnv') and ($work_blk{'service'} !~ /close call/i)) {
LogIt(1,"Uniden l2806:No quick key assigned to system " .
"$Magenta$work_blk{'service'}$White ($Green$sin_index$White)" .
" systemtype=>$Cyan$work_blk{'systemtype'}");
}
}
my $keep = TRUE;
if ($notrunk and ($systemtype ne 'cnv')) {$keep = FALSE;}
elsif (($firstnum > 0) and ($system_number < $firstnum)) {$keep = FALSE;}
elsif ($blk_ref and (!$blk_ref->{$sin_index})) {$keep = FALSE;}
elsif ($nam_ref and (!$nam_ref->{$systemname})) {$keep = FALSE;}
if ($keep) {
KeyVerify(\%work_blk, @{$structure{'system'}});
my $sysno = add_a_record($db,'system',\%work_blk);
}
else {LogIt(0,"Bypassing $systemname");}
$system_count++;
if ($count and ($system_count > $count)) {last SINLOOP;}
$sin_index = $work_blk{'fwd_index'};
}
my $syscount = scalar @{$db->{'system'}};
if (!$syscount) {
exit_prg($parmref,"UNIDEN:GETMEM-No systems found for this radio");
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = $EmptyChan);
}
if ($parmref->{'noexit'}) {
}
else {exit_prg($parmref);}
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'getinfo') {
if (uniden_cmd('MDL',$parmref)) {
add_message("GETINFO:Could not get Uniden model number!");
return $parmref->{'rc'};
}
if (substr(lc($model),0,3)  eq 'bcd') {
uniden_cmd('BAV',$parmref);
if (!$out->{'bat_level'}) {$out->{'bat_level'} = 0;}
$out->{'bat_level'} = sprintf("%.2f",(3.2 * $out->{'bat_level'} * 2)/1023);
if (enter_prg($parmref)) {
add_message("GETINFO l2689: command failed to get Uniden into program state!");
return $parmref->{'rc'};
}
uniden_cmd('MEM',$parmref);
my $rawsave = $out->{'_raw'};
uniden_cmd('RMB',$parmref);
$rawsave = "$rawsave\n    $out->{'_raw'}";
exit_prg($parmref);
$out->{'_raw'} = $rawsave;
}
else {
}
return ($parmref->{'rc'} = $GoodCode);
}
elsif ($cmdcode eq 'getsrch') {
if ($model =~ /sds/i) {return $NotForModel;}
LogIt(0,"Getting search records");
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("GETMEM: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
foreach my $channel (0..9) {
$parmref->{'write'} = FALSE;
%work_blk = ('channel' => $channel);
if (uniden_cmd('CSP',$parmref)) {
add_message("GETSRCH:Command failed CSP!");
$retcode = $parmref->{'rc'};
last;
}
$work_blk{'srch_ndx'} = 'c' .$channel;
my $recno =  add_a_record($db,'search',\%work_blk,$parmref->{'gui'});
}
if (FALSE) {
foreach my $channel (sort Numerically keys %service_search) {
$parmref->{'write'} = FALSE;
if (($model ne 'BCD325P2') and ($channel > 12)) {next;}
if (($model eq 'BCD325P2') and ($channel == 10)) {next;}
%work_blk = ('channel' => $channel);
if (uniden_cmd('SSP',$parmref)) {
add_message("GETSRCH:Command failed SSP!");
$retcode = $parmref->{'rc'};
next;
}
$work_blk{'srch_ndx'} = 's' . $channel;
$work_blk{'channel'} = 's' . $channel;
$work_blk{'service'} = $service_search{$channel};
$work_blk{'start_freq'} = 0;
$work_blk{'end_freq'} = 0;
$work_blk{'step'} = 0;
$work_blk{'mode'} = 'FM';
my $recno =  add_a_record($db,'search',\%work_blk,$parmref->{'gui'});
}
}### Do NOT read fixed service blocks
$parmref->{'out'} = $outsave;
exit_prg($parmref);
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'setsrch') {
if ($model =~ /sds/i) {return $NotForModel;}
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("GETMEM: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
LogIt(0,"setting SEARCH records into the radio...");
my $count = 0;
foreach my $rec (@{$db->{'search'}}) {
if (!$rec->{'index'}) {next;}
my $call = 'CSP';
my $channel = $rec->{'channel'};
my $chsave = $channel;
if (looks_like_number($channel)) {
if (($channel < 0) or ($channel > 9)) {next;}
if (!$rec->{'step'}) {next;}
my $step = $rec->{'step'};
if ($step and looks_like_number($step)) {$step = int($step/10);}
else {$step = 500;}
$rec->{'step'} = $step;
}
else {
$call = 'SSP';
$channel = substr($channel,1);
if ((!looks_like_number($channel)) or ($channel > 15)) {
next;
}
$rec->{'channel'} = $channel;
}
%work_blk = %{$rec};
$work_blk{'lout'} = 0;
if (!$work_blk{'valid'}) {$work_blk{'lout'} = 1;}
foreach my $key ('skp','p25mode','p25lvl','start_key') {
$work_blk{$key} = '';
}
$parmref->{'write'} = TRUE;
if (uniden_cmd($call,$parmref)) {
add_message("SETSRCH:Command failed call to $call!");
$retcode = $parmref->{'rc'};
next;
}
if ($Debug3) {DebugIt("UNIDEN l3106:Stored search channel $chsave $work_blk{'service'}");}
}
exit_prg($parmref);
return ($parmref->{'rc'});
}
elsif ($cmdcode eq 'getmem') {
LogIt(0,"GETMEM L2904:Starting routine. Radio state=>$state_save{'state'}");
$retcode = 0;
if (!$model) {
if (uniden_cmd('MDL',$parmref)) {
add_message("GETMEM:Could not get Uniden model number!");
return $parmref->{'rc'};
}
}
if (lc($model) eq 'sds200') {
LogIt(0,"GETMEM l2917:Calling SDSx00 routine");
Get_All_SDS($parmref);
LogIt(0,"UNIDEN GetMem l2218:SDSx00 routine Finished");
return $parmref->{'rc'};
}
if (!$state_save{'state'}) {uniden_cmd('STS',$parmref);}
my $startstate = $progstate;
my %allsys = ();
my @systems = ();
$parmref->{'database'} = \%allsys;
$parmref->{'noexit'} = TRUE;
my $rc = uniden_cmd('_getall',$parmref);
$parmref->{'database'} = $db;
if ($rc) {return $rc;}
$parmref->{'noexit'} = FALSE;
my $syscount = scalar @{$allsys{'system'}};
if (!$syscount) {
add_message("UNIDEN:GETMEM-Could not get systems in this Uniden radio!");
return ($parmref->{'rc'} = $EmptyChan);
}
threads->yield;
if ($progstate ne $startstate) {
exit_prg($parmref,"GETMEM terminated by user");
return ($parmref->{'rc'} = $GoodCode);
}
foreach my $rec (@{$allsys{'syskey'}}) {
if (!$rec->{'index'}) {next;}
add_a_record($db,'syskey',$rec);
}
my $firstdbsysno = 0;
my $count = 0;
my $p2 = FALSE;
my $t1 = TRUE;
if ($radio_def{'model'} eq 'BCD325P2') {
$p2 = TRUE;
$t1 = FALSE;
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
if ($Debug3) {DebugIt("UNDEN l3310: GETMEM system count=>$syscount");}
my @group_keys  =  @{$structure{'group'}};
my @site_keys   =  @{$structure{'site'}};
my @tfreq_keys   =  @{$structure{'tfreq'}};
my @freq_keys   =  @{$structure{'freq'}};
my @chan_keys   = @freq_keys;
my $rcchan = 0;
SYSLP:
foreach my $sinrcd (@{$allsys{'system'}}) {
threads->yield;
if ($progstate ne $startstate) {last SYSLP;}
my $sysndx = $sinrcd->{'index'};
if (!$sysndx) {next;}
if (lc($sinrcd->{'service'}) eq 'close call') {next;}
if (!$parmref->{'gui'}) {
print STDERR "\rretrieving radio system $sysndx ";
}
my $systype = lc($sinrcd->{'systemtype'});
my $sinndx = $sinrcd->{'block_addr'};
if ($Debug3) {DebugIt("UNIDEN_CMD l3351:systype from SIN=$systype");}
if (($systype eq 'm82s') or ($systype eq 'm81s')) {$systype = 'mots';}
elsif (($systype eq 'm82p') or ($systype eq 'm81p')) {$systype = 'motp';}
elsif ( ($systype eq 'm92') or ($systype eq 'mv2') or ($systype eq 'mu2')) {$systype = 'motc';}
elsif ($systype eq 'mp25') {$systype = 'p25s';}
elsif ($systype eq 'turbo') {$systype = 'trbo';}
$sinrcd->{'systemtype'} = $systype;
my $sysno = add_a_record($db,'system',$sinrcd,$parmref->{'gui'});
if (!$firstdbsysno) {$firstdbsysno = $sysno;}
if ($Debug2) {DebugIt("UNIDEN_CMD l1738:finished getting SIN block");}
my $grpno  = 1;
my $channo = -1;
my $siteno = 1;
my $freqno = 1;
my $trnkno = 1;
my $grpndx = $sinrcd->{'chn_head'};
my $chncmd  = 'CIN';
if ($systype ne 'cnv') {
$chncmd = 'TIN';
my $sifndx = $grpndx;
%work_blk = ('block_addr' => $sinndx);
if (uniden_cmd('TRN',$parmref)) {
$parmref->{'out'} = $outsave;
exit_prg($parmref,
"GETMEM:Could not fetch Uniden Trunk Info Block (TRN) for index $sinndx!",
);
return ($parmref->{'rc'});
}
my @trunk_keys = ();
foreach my $key (keys %work_blk) {
if ($key eq 'block_addr') {
$db->{'system'}[$sysno]{'trn_addr'} = $work_blk{$key};
}
elsif ($key eq '_raw') {
$db->{'system'}[$sysno]{'_raw'} = $db->{'system'}[$sysno]{$key} .
'|' . $work_blk{'_raw'};
}
elsif ($key eq 'dsql') {
$db->{'system'}[$sysno]{'dsql'} = dsql_to_rc($work_blk{$key});
}
else {$db->{'system'}[$sysno]{$key} = $work_blk{$key};}
}
if ($Debug2) {DebugIt("UNIDEN l1511:finished getting TRN block $sinndx");}
$grpndx = $work_blk{'chn_head'};
my $firstsif = TRUE;
my $foundsite = FALSE;
my %site_keys = ();
if ( $db->{'system'}[$sysno]{'qkey'} ne '.') {
$site_keys{$db->{'system'}[$sysno]{'qkey'}} = TRUE;
}
SITE:
while ($sifndx != -1) {
if ($progstate ne $startstate) {last SYSLP;}
%work_blk = ('block_addr' => $sifndx);
if ($p2) {
if (uniden_cmd('SIF',$parmref)) {
add_message("GETMEM:Cannot read Uniden SIF block at $sifndx");
foreach my $key (keys %{$sinrcd}) {LogIt(0,"$key => $sinrcd->{$key}");}
LogIt(0,"sent =>$parmref->{'sent'} rcv=>$parmref->{'str'} rc=>$parmref->{'rc'}");
last SITE;
}### Error encountered
if ($firstsif) {
my $newsystype = '';
if ($systype eq 'edw') {
my $edwtype = lc($work_blk{'edacs_type'});
if ($edwtype eq 'wide') {$newsystype = 'edw';}
elsif ($edwtype eq 'narrow') {$newsystype = 'edn';}
else {add_message("GETMEM:unhandled EDACS type $edwtype");}
}
elsif ($systype eq 'mots') {
my $mottype = lc($work_blk{'mot_type'});
if ($mottype eq 'std') {$newsystype = 'mots';}
elsif ($mottype eq 'spl') {$newsystype = 'motp';}
elsif ($mottype eq 'custom') {$newsystype = 'motc';}
else {add_message("GETMEM:unhandled MOTO type $mottype");}
}
else { }
if ($newsystype) {
$db->{'system'}[$sysno]{'systemtype'} = uc($newsystype);
$systype = $newsystype;
if ($Debug3) {DebugIt("UNIDEN l3534: Changed systype to $systype");}
}
foreach my $key ('p25wait') {
$db->{'system'}[$sysno]{$key} = $work_blk{$key};
}
}### FIRST SIF process
}### BDC325P2
else {
if (uniden_cmd('GIN',$parmref)) {
exit_prg($parmref,
"GETMEM:Could not Read Uniden Group Info Block (GIN) for index $sifndx!",
);
$parmref->{'out'} = $outsave;
}### GIN error
$foundsite = TRUE;
}### Older radio
$work_blk{'sysno'} = $sysno;
$work_blk{'valid'} = !$work_blk{'lout'};
if ($work_blk{'valid'}) {$foundsite = TRUE;}
if ($p2 and $work_blk{'valid'}) {
my $qkey = $work_blk{'qkey'};
if (looks_like_number($qkey)) {
$qkey = $qkey + 0;
$site_keys{$qkey} = TRUE;
my $sqk = $db->{'system'}[$sysno]{'qkey'};
if ((!defined $sqk) or (!looks_like_number($sqk))) {
$db->{'system'}[$sysno]{'qkey'} = $qkey
}
}### quickkey defined
else {LogIt(1,"Uniden l3395:No quickkey assigned for site $siteno ($db->{'site'}[$siteno]{'service'} ) for system $sysno!");}
}### BDC325P2
KeyVerify(\%work_blk,@site_keys);
$siteno = add_a_record($db,'site',\%work_blk);
if ($Debug2) {DebugIt("UNIDEN l1591:finished getting SIF/GIN block $sifndx");}
my $tfqndx = $work_blk{'chn_head'};
$sifndx = $work_blk{'fwd_index'};
my $mot_type = $db->{'site'}[$siteno]{'mot_type'};
if (!$mot_type) {$mot_type = '';}
if (lc($mot_type) eq 'custom') {
%work_blk = ('block_addr' => $db->{'site'}[$siteno]{'block_addr'});
if (uniden_cmd('MCP',$parmref)) {
LogIt(1,"Could not retrieve Bandplan for Site $siteno");
}
else {
$work_blk{'siteno'} = $siteno;
$work_blk{'flags'} = '';
my $bplan = add_a_record($db,'bplan',\%work_blk);
}
}
while ($tfqndx ne '-1') {
if ($progstate ne $startstate) {last SYSLP;}
%work_blk = ('block_addr' => $tfqndx);
if (uniden_cmd('TFQ',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg(
"GETMEM:Could not Read Trunked Frequency (TFQ) for index $tfqndx!",
$parmref);
}### TFQ error encountered
$work_blk{'siteno'} = $siteno;
$work_blk{'valid'} = !$work_blk{'lout'};
my $ccode = $work_blk{'ccode'};
$work_blk{'ccode'} = 's';
$work_blk{'ran'} = 's';
if (looks_like_number($ccode)) {
if (($systype =~ /dmr/i) or ($systype =~ /tr/i)) {
$work_blk{'ccode'} = $ccode;
}
}
$work_blk{'flags'} = '';
KeyVerify(\%work_blk,@tfreq_keys);
my $tfreqno = add_a_record($db,'tfreq',\%work_blk);
if ($Debug2) {DebugIt("UNDEN l36356:finished getting TFQ block $tfqndx for site=>$siteno");}
$tfqndx = $work_blk{'fwd_index'};
}### all the TFQs
}### get all sites
if ($foundsite) {
my $sysqkey = $db->{'system'}[$sysno]{'qkey'};
if ($sysqkey ne '.') {
}
else {
LogIt(1,"Uniden 2761:No valid system quickkey was defined for $db->{'system'}[$sysno]{'service'}");
}
}
else {
LogIt(1,"Uniden l2761:No valid sites found for system $db->{'system'}[$sysno]{'service'}!");
$db->{'system'}[$sysno]{'valid'} = FALSE;
}
}### Trunked system unique process
if ($Debug3) {DebugIt("UNIDEN L3716: Group index=$grpndx");}
my %group_qkeys = ();
%work_blk = ('block_addr' => $sinndx, 'grpkey' => \%group_qkeys);
if (uniden_cmd('QGL',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg(
"GETMEM:Could not fetch GROUP keys for index $sinndx!",
$parmref);
}
my $outstr = '';
foreach my $qkey (0..9) {
my $value = $group_qkeys{$qkey};
if (!defined $value) {$value = '-';}
$outstr = "$outstr$value";
}
$work_blk{'grpkeys'} = $outstr;
$work_blk{'sysno'} = $sysno;
add_a_record($db,'grpkey',\%work_blk);
my $grp_raw = $work_blk{'_raw'};
my $grp_add = $work_blk{'block_addr'};
my %used_gkeys = ();
GRP:
while ($grpndx ne '-1') {
if ($progstate ne $startstate) {last SYSLP;}
%work_blk = ('block_addr' => $grpndx);
if (uniden_cmd('GIN',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg(
"GETMEM:Could not Read Uniden Group Info Block (GIN) for index $grpndx!",
$parmref);
}
$work_blk{'sysno'} = $sysno;
$work_blk{'valid'} = !$work_blk{'lout'};
my $gqkey = $work_blk{'qkey'};
my $keymsg = '';
if (looks_like_number($gqkey) and ($gqkey >= 0)) {
if (defined $group_qkeys{$gqkey}) {
}
else {
if ($Debug2) {
DebugIt("Uniden 3748:Firmware bug:Group quickkey $gqkey " .
"was not set correctly by QGL. Fixed");
}
$group_qkeys{$gqkey} = 0;
}
if ($group_qkeys{$gqkey}) {$work_blk{'valid'} = TRUE;}
else {$work_blk{'valid'} = FALSE;}
if ($used_gkeys{$gqkey}) {
$keymsg = "Other groups also have the same quickkey:$Green$gqkey$White";
}
else {$used_gkeys{$gqkey} = TRUE;}
}
else {
$keymsg = "No quickkey assigned for this group";
}
KeyVerify(\%work_blk,@group_keys);
$grpno = add_a_record($db,'group',\%work_blk,$parmref->{'gui'});
if ($keymsg) {LogRad(1,$db,'group',$grpno,$keymsg);}
if ($Debug2) {DebugIt("UNIDEN l1648:finished getting GIN block $grpndx");}
my $chnndx = $work_blk{'chn_head'};
my %grpblk = %work_blk;
if ($chnndx eq '-1') {
my $msg = "No channels found for this group";
LogRad(1,$db,'group',$grpno,$msg);
}
$grpndx = $work_blk{'fwd_index'};
if ($Debug2) {DebugIt("UNIDEN l1649: Next group address=$grpndx");}
$channo = 0;
CHN:     while ($chnndx ne '-1') {
if ($progstate ne $startstate) {last SYSLP;}
%work_blk = ('block_addr' => $chnndx);
if (uniden_cmd($chncmd,$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg(
"\n GETMEM:Could not Read Uniden $chncmd for index $chnndx!",
$parmref);
}### error encountered
$work_blk{'adtype'} = 'AN';
$work_blk{'sqtone'} = 'Off';
if ($systype =~ /cnv/i) {
if ($work_blk{'tonelock'}) {
my $dsql = dsql_to_rc($work_blk{'dsql'});
if ($dsql =~ /nac/i) {
$work_blk{'adtype'} = 'P2';
$work_blk{'sqtone'} = $dsql;
}
elsif ($dsql =~ /ccd/i) {
$work_blk{'adtype'} = 'DM';
$work_blk{'sqtone'} = $dsql;
}
elsif ($dsql =~ /ran/i) {
$work_blk{'adtype'} = 'NX';
$work_blk{'sqtone'} = $dsql;
}
else {
my $code = $work_blk{'ctcsdcs'};
if ($code and looks_like_number($code)) {
if ($code > 127) {
$work_blk{'sqtone'} = $dcstone[$code - 127];
}
elsif ($code > 63) {
$work_blk{'sqtone'} = $ctctone[$code - 63];
}
else {
print "Uniden line 3913:No decode for tone code $code\n";
}
}### Valid analog code
}### Analog tone
}### Tone value is used
}### Conventional system
elsif (($systype =~ /rbo/i) or ($systype =~ /dmr/)) { 
$work_blk{'adtype'} = 'DM';
$work_blk{'sqtone'} =  $db->{'system'}[$sysno]{'dsql'};
}
elsif ($systype =~ /p25/i) {  
$work_blk{'adtype'} = 'p2';
$work_blk{'sqtone'} =  $db->{'system'}[$sysno]{'dsql'};
}
elsif ($systype =~ /ed/i) { 
}
elsif ($systype =~ /ltr/i) { 
}
elsif ($systype =~ /mot/i) { 
}
elsif ($systype =~ /nxd/i) { 
}
else {
LogIt(1,"UNIDEN l3926:No tone process for system type=$systype!");
}
if ($systype eq 'cnv') {
$work_blk{'lcn'} = '-';
$work_blk{'tgid'} = '-';
$work_blk{'tgid_valid'} = FALSE;
$work_blk{'channel'} = ++$channo;
}
else {
$work_blk{'frequency'} = 0;
$work_blk{'mode'} = '-';
$work_blk{'tgid_valid'} = TRUE;
$work_blk{'channel'} = '-';
}
$work_blk{'valid'} = TRUE;
if ($work_blk{'lout'}) {$work_blk{'valid'} = FALSE;}
KeyVerify(\%work_blk,@freq_keys);
$work_blk{'groupno'} = $grpno;
$work_blk{'sysno'} = $sysno;
my $newrec = add_a_record($db,'freq',\%work_blk,$parmref->{'gui'});
if ($Debug2) {DebugIt("UNIDEN l1681:finished getting $chncmd block $chnndx");}
$chnndx = $work_blk{'fwd_index'};
}### channel process
}### group process
$count++;
}#### while count
LogIt(0,"$Eol$Bold GETMEM complete");
exit_prg($parmref);
$parmref->{'out'} = $outsave;
$out ->{'sysno'} = $firstdbsysno;
$out ->{'count'} = $count;
return ($parmref->{'rc'} = $GoodCode);
}### GETMEM
elsif ($cmdcode eq 'setmem') {
LogIt(0,"Called Uniden SETMEM");
$ready = TRUE;
if ($Debug1) {DebugIt("UNIDEN l4115:Processing SETMEM command");}
my $erase = FALSE;
my $dumpit = FALSE;
my $nodie = FALSE;
my $opt_ref = $parmref->{'options'};
if ($opt_ref) {
if ($opt_ref->{'erase'}) {$erase = TRUE;}
if ($opt_ref->{'nodie'}) {$nodie = TRUE;}
}
if (!$model) {
if (uniden_cmd('MDL',$parmref)) {
LogIt(0,"$Bold$Red" . "Error!$White Could Not Get Uniden Model number");
LogIt(0,"SETMEM:Could not get Uniden model number!");
return $parmref->{'rc'};
}
}
if ((lc($model) eq 'sds200') or (lc($model) eq 'sds100'))  {
LogIt(0,"$Bold$Red" . "Error!$White SETMEM cannot be used with model$Green $model");
return ($parmref->{'rc'} = $NotForModel);
}
my $p2 = FALSE;
if ($model eq 'BCD325P2') {$p2 = TRUE;}
my @systems = @{$db->{'system'}};
my %new_syskeys = ();
my $retcode = 0;
SYSPROC:
foreach my $sysrec (@systems) {
if ($sysrec->{'_bypass'}) {next;}
my $sysno = $sysrec->{'index'};
if (!$sysno) {next;}
my $systype = $sysrec->{'systemtype'};
if (!$systype) {
LogIt(1,"SETMEM l3984:No 'systemtype' key set in $sysno! Cannot process!");
$sysrec->{'_bypass'} = TRUE;
$retcode = $ParmErr;
next SYSPROC;
}
$systype = lc(Strip($systype));
my $sysname =  "$Yellow$sysrec->{'service'}$White ($Green$sysno$White)";
if (!$system_type_valid{$systype}) {
LogIt(1,"SETMEM l3992:System $sysname " .
"type $Magenta$systype$White is NOT a valid RadioCtl system type");
$retcode = $ParmErr;
$sysrec->{'_bypass'} = TRUE;
next SYSPROC;
}
if ((!$p2) and (!$bcd396_systypes{$systype})) {
LogIt(1,"SETMEM l4002:System $sysname " .
"type $Magenta$systype$White is NOT a valid for model $model");
$retcode = $NotForModel;
$sysrec->{'_bypass'} = TRUE;
next SYSPROC;
}
my $sqkey = $sysrec->{'qkey'};
if (!defined $sqkey) {$sqkey = '.';}
if (($systype eq 'cnv') or (!$p2)) {
if ((!looks_like_number($sqkey)) or ($sqkey < 0)) {
LogIt(1,"SETMEM l4150:System $sysname\n " .
"      Quick-Key is not defined. Cannot store this system");
$retcode = $NotForModel;
$sysrec->{'_bypass'} = TRUE;
next SYSPROC;
}
$sqkey = $sqkey + 0;
if ((!$p2) and (!$sqkey)) {$sqkey = 100;}
my $oldkey = $new_syskeys{$sqkey};
$new_syskeys{$sqkey} = $sysrec->{'valid'};
my $turnqk = $sysrec->{'turnqk'};
if ($turnqk) {
if (lc($turnqk) eq 'off') {$new_syskeys{$sqkey} = 0;}
elsif (lc($turnqk) eq 'on') {$new_syskeys{$sqkey} = 1;}
}
if ((defined $oldkey) and ($oldkey != $new_syskeys{$sqkey})) {
LogIt(1,"Consistency issue with System Quick-Key $Green$sqkey$White for system $sysname!\n" .
"   Key is assigned to two systems or sites with different states (On/Off)\n" .
"   Last value set: $Yellow$new_syskeys{$sqkey}$White will be used.");
}
}
$sysrec->{'qkey'} = $sqkey;
$sysrec->{'lout'} = 0;
if ($p2 and ($sysrec->{'systemtype'} ne 'cnv')) {
my $sitecount = 0;
SITEPROC:   foreach my $siterec (@{$db->{'site'}}) {
my $siteno = $siterec->{'index'};
if (!$siteno) {next;}
if ($siterec->{'sysno'} ne $sysno) {next;}
my $sitename = "$Yellow$siterec->{'service'}$White ($Green$siteno$White)";
my $qkey = $siterec->{'qkey'};
if (!defined $qkey) {$qkey = -1;}
if ((!looks_like_number($qkey)) or ($qkey < 0)) {
LogIt(1,"SETMEM l4080:Site $sitename quickkey is NOT valid! Cannot process.");
$retcode = $ParmErr;
$siterec->{'_bypass'} = TRUE;
next SITEPROC;
}
$qkey = $qkey + 0;
$siterec->{'qkey'} = $qkey;
my $oldkey = $new_syskeys{$qkey};
$new_syskeys{$qkey} = $siterec->{'valid'};
my $turnqk = $siterec->{'turnqk'};
if ($turnqk) {
if (lc($turnqk) eq 'off') {$new_syskeys{$qkey} = 0;}
elsif (lc($turnqk) eq 'on') {$new_syskeys{$qkey} = 1;}
}
if ((defined $oldkey) and ($oldkey != $new_syskeys{$qkey})) {
LogIt(1,"Consistency issue with System Quick-Key $Green$qkey$White for site $sitename\n" .
"   Key is assigned to two systems or sites with different states (On/Off)\n" .
"   Last value set: $Yellow$new_syskeys{$qkey}$White will be used.");
}
$siterec->{'lout'} = 0;
my $tfcnt = 0;
foreach my $tfrec (@{$db->{'tfreq'}}) {
if ($tfrec->{'_bypass'}) {next;}
if (!$tfrec->{'index'}) {next;}
if ($tfrec->{'siteno'} != $siteno) {next;}
if (!check_range($tfrec->{'frequency'},\%{$radio_limits{$model}})) {
LogIt(1,"SETMEM l4308:Frequency$Yellow" .
rc_to_freq($tfrec->{'frequency'}) .
" MHz$White is out of range of the radio. Bypassed..");
next;
}
$tfcnt++;
}
if (!$tfcnt) {
LogIt(1,"SETMEM l3914 :No valid tfreq records found for site $siterec->{'service'} Cannot process.");
$siterec->{'_bypass'} = TRUE;
$retcode = $EmptyChan;
next SITEPROC;
}
$sitecount++;
}
if (!$sitecount) {
LogIt(1,"SETMEM l3924:No valid sites found for system $Yellow$sysrec->{'service'}$White" .
"($Green$sysno$White). Cannot process.");
$retcode = $EmptyChan;
$sysrec->{'_bypass'} = TRUE;
next SYSPROC;
}
}### trunked system
my $firstgrprec = 0;
my $groupcnt = 0;
my $validcnt = 0;
GRPPROC: foreach my $grprec (@{$db->{'group'}}) {
my $grpno = $grprec->{'index'};
if (!$grpno) {next;}
if ($grprec->{'sysno'} ne $sysno) {next;}
my $qkey = $grprec->{'qkey'};
if (!defined $qkey) {$qkey = -1;}
if ( (!looks_like_number($qkey)) or ($qkey < 0)) {$qkey = '.';}
else {
$qkey = $qkey % 10;
}
$grprec->{'_keyon'} = FALSE;
if ($qkey eq '.') {
LogIt(1,"SETMEM l4014:Group $grprec->{'index'} quickkey is not set." .
" Group will NOT be able to be selected!");
if ($grprec->{'valid'}) {
$grprec->{'lout'} = 0;
$validcnt++;
}
else {$grprec->{'lout'} = 1;}
}
else {
$grprec->{'lout'} = 0;
if ($grprec->{'valid'}) {$grprec->{'_keyon'} = TRUE;}
my $turnqk = $grprec->{'turnqk'};
if ($turnqk) {
if (lc($turnqk) eq 'off') {$grprec->{'_keyon'} = FALSE;}
elsif (lc($turnqk) eq 'on') {$grprec->{'_keyon'} = TRUE;}
}
if ($grprec->{'_keyon'}) {$validcnt++;}
}
$grprec->{'qkey'} = $qkey;
my $chanfound = FALSE;
foreach my $freq (@{$db->{'freq'}}) {
if ($freq->{'_bypass'}) {next;}
if (!$freq->{'index'}) {next;}
if ($freq->{'groupno'} == $grpno) {
if ($freq->{'frequency'} and (!check_range($freq->{'frequency'},\%{$radio_limits{$model}}))) {
LogIt(1,"SETMEM l4429:Frequency$Yellow" .
rc_to_freq($freq->{'frequency'}) .
" MHz$White is out of range of the radio. Bypassed..");
$freq->{'_bypass'} = TRUE;
next;
}
$chanfound = TRUE;
}
}
if ($chanfound) {
if (!$firstgrprec) {$firstgrprec = $grprec;}
$groupcnt++;
if ($grprec->{'valid'}) {$validcnt++;}
}
else {
LogIt(1,"SETMEM l4051:No channels assigned to group " .
"$Yellow$grprec->{'service'}$White) ($Green$grpno$White). Group setting bypassed.");
$grprec->{'_bypass'} = TRUE;
next;
}
}### check for all groups
if ((!$groupcnt) and (!$retcode)) {
LogIt(1,"SETMEM l4061:No groups found for system  $Yellow$sysrec->{'service'}$White" .
"($Green$sysno$White). Cannot process.");
$retcode = $EmptyChan;
$sysrec->{'_bypass'} = TRUE;
next;
}
if (!$validcnt) {
if ($firstgrprec) {
LogIt(1,"SETMEM l4072:No groups with 'valid' set! " .
"Turning on first group to prevent problems!");
$firstgrprec->{'valid'} = TRUE;
}
else {
LogIt(1,"No groups were valid! This file will most likely not work right in the radio!");
}
}
if ($groupcnt > 20) {
LogIt(1,"SETMEM L4086: More than 20 groups defined. " .
"Group storage may get exhasted during writing...");
}
}### check of all systems
if ($retcode) {
if ($nodie) {
LogIt(1,"SETMEM will store only Database records NOT in error");
}
else {
LogIt(1,"Radio was NOT updated due to database errors! Retcode=$retcode");
return ($parmref->{'rc'} = $retcode);
}
}
my %allsys = ();
my @delsys = ();
if ($erase) {
$parmref->{'database'} = \%allsys;
my $rc = uniden_cmd('_getall',$parmref);
$parmref->{'database'} = $db;
foreach my $sysrec (@systems) {
if ($sysrec->{'_bypass'}) {next;}
my $name = Strip($sysrec->{'service'});
foreach my $radsys (@{$allsys{'system'}}) {
if (!$radsys ->{'index'}) {next;}
my $thisname = Strip($radsys->{'service'});
my $len = length($thisname);
if ($thisname eq substr($name,0,$len)) {
push @delsys,$radsys;
LogIt(0,"Uniden l4528:Scheduled system $name for removal");
}
}## for each system in the radio
}### Each database system
}### Removing systems
my $count = 0;
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("SETMEM: command failed to get Uniden into program state!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'outsave'} = $outsave;
$parmref->{'out'} = \%work_blk;
my $startstate = $progstate;
LogIt(0,"Found $Bold$Green" . scalar @delsys . "$Reset Systems to delete");
foreach my $sin (@delsys) {
my $addr = $sin->{'block_addr'};
LogIt(0,"$Bold Deleting system $Yellow$sin->{'service'}$White (addr=>$Green$addr) ");
%work_blk = ('block_addr' => $addr);
my $system_cnt = 0;
if ($ready) {
if (uniden_cmd('DSY',$parmref)) {
add_message("SETMEM:unable to delete addr=$sin");
}
else {
$parmref->{'quiet'} = TRUE;
if (! uniden_cmd('SCT',$parmref)) {$system_cnt = $work_blk{'system_cnt'};}
if ($Debug3) {DebugIt("UNIDEN l4663: SCT returned=>$parmref->{'rcv'}");}
while (uniden_cmd('SCT',$parmref)) {
if ($Debug3) {DebugIt("UNIDEN l4665: Issued SCT waiting for system");}
sleep 1;
}
while (! uniden_cmd('nop',$parmref)) {
if ($Debug3) {DebugIt("UNIDEN l4670: Waiting for bus to clear");}
}
$parmref->{'quiet'} = FALSE;
if ($Debug3) {DebugIt("UNIDEN l4670: After delete number of systems=$system_cnt");}
}### delete successful
}### ready
else {
if ($Debug3) {DebugIt("UNIDEN l4670:  bypassed clear. block_addr=$sin");}
}
}
%system_qkeys = ();
$parmref->{'write'} = FALSE;
if (uniden_cmd('QSL',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg($parmref,"GETMEM:Could not fetch SYSTEM quick-keys!");
}
foreach my $qkey (keys %new_syskeys) {
$system_qkeys{$qkey} = $new_syskeys{$qkey};
}
$retcode = 0;
my $firstpass = TRUE;
my $system_cnt = 0;
$parmref->{'write'} = TRUE;
SYSNO:foreach my $sysrec (@systems) {
if ($sysrec->{'_bypass'}) {next SYSNO;}
my $sysno = $sysrec->{'index'};
if (!$sysno) {next;}
my %group_qkeys = ();
my $sysndx = -1;
my $systype = lc(Strip($sysrec->{'systemtype'}));
my $radio_systype = uc($systype);
if ($p2) {
if ($bcd325p2_systypes{$systype}) {
$radio_systype = uc($bcd325p2_systypes{$systype});
}
}
else {
$radio_systype = uc($bcd396_systypes{$systype});
}
%work_blk = ('systemtype' => $radio_systype, 'block_addr' => 0);
if ($ready) {
if (uniden_cmd('CSY',$parmref)){
return exit_prg(
"SETMEM:Could not create new system $sysno of system type $systype!",
$parmref);
}### CSY failed
}### ready
$sysndx = $work_blk{'block_addr'};
LogIt(0,"Uniden l4702:Created new system block address=$sysndx");
if ($sysndx eq '-1') {
$parmref->{'rc'} = $OtherErr;
print Dumper(%work_blk),"\n";
return exit_prg("SETMEM l4705:Radio system capacity exceeded!",$parmref);
}
$db->{'system'}[$sysno]{'block_addr'} = $sysndx;
%work_blk = %{$db->{'system'}[$sysno]};
$work_blk{'lout'}  = 0;
$work_blk{'systemtype'} = $radio_systype;
if ($p2) {$work_blk{'skip'} = 0;}
else {$work_blk{'skip'} = 1;}
$work_blk{'p25mode'} = 'AUTO';
$work_blk{'p25lvl'} = '0';
$work_blk{'start_key'} = '.';
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('SIN',$parmref)){
return exit_prg("SETMEM l4263:Cannot update SIN for system $sysno ",$parmref);
}### failure
}### ready
my $grpcmd = 'AGC';
my $chncmd = 'ACC';
my $chantype = 'freq';
my $chnblk = 'CIN';
if ($systype ne 'cnv') {
$grpcmd = 'AGT';
$chncmd = 'ACT';
$chnblk = 'TIN';
$chantype = 'tgid';
%work_blk = %{$db->{'system'}[$sysno]};
$work_blk{'dsql'} = 'SRCH';
my ($tt,$dsql) = Tone_Xtract($db->{'system'}[$sysno]{'dsql'});
if ($tt =~ /nac/i) {
$work_blk{'dsql'} = $dsql;
}
elsif ($tt =~ /ccd/i) {
$work_blk{'dsql'} = sprintf("%4.4x",($dsql + 4096));
}
foreach my $key ('frequency_l1','spacing_1','offset_1',
'frequency_l2','spacing_2','offset_2',
'frequency_l3','spacing_3','offset_3','mfid') {
$work_blk{$key} = '.';
}
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('TRN',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l3988:Cannot update TRN for system $sysno ",$parmref);
}### failure
}
my $sitecount = 0;
foreach my $siterec (@{$db->{'site'}}) {
if ($siterec->{'_bypass'}) {next;}
my $siteno = $siterec->{'index'};
if (!$siteno) {next;}
if ($siterec->{'sysno'} ne $sysno) {next;}
if ($siterec->{'_bypass'}) {next;}
my $site_addr = -1;
my $chan_addr = -1;
if ($p2) {
%work_blk = ('block_base' => $sysndx, 'block_addr' => 0);
if ($ready) {
if (uniden_cmd('AST',$parmref)) {
return exit_prg("SETMEM l4041:Cannot create SIF for system $sysno ",$parmref);
}
}### ready
$site_addr = $work_blk{'block_addr'};
if ($site_addr eq '-1') {
my $msg = "Site capacity ($Green$sitecount$White) exceeded for this system!";
LogRad(1,$db,"system",$sysno,$msg);
last;
}
$sitecount++;
$siterec->{'block_addr'} = $site_addr;
%work_blk = %{$siterec};
foreach my $key ('p25lvl','p25wait') {
my $value = $db->{'system'}[$sysno]{$key};
if ((!$value) and $key =~ /wait/i) {
$value = 400;
}
if (!$value) {$value = 0;}
if (!looks_like_number($value)) {$value = 0;}
$work_blk{$key} = $value;
}
$work_blk{'edacs_type'} = '.';
$work_blk{'mot_type'} = '.';
if ($systype eq 'edw') {$work_blk{'edacs_type'} = 'WIDE';}
elsif ($systype eq 'edn' ) {$work_blk{'edacs_type'} = 'NARROW';}
elsif ($systype eq 'mots') {$work_blk{'mot_type'} = 'STD';}
elsif ($systype eq 'motp') {$work_blk{'mot_type'} = 'SPL';}
elsif ($systype eq 'motc') {$work_blk{'mot_type'} = 'CUSTOM';}
$work_blk{'start_key'} = '.';
$work_blk{'gps_enable'} = 0;
if ($siterec->{'lat'} or $siterec->{'lon'}) {
$work_blk{'gps_enable'} = 1;
}
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('SIF',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l4074:Cannot update SIF for system $sysno ",$parmref);
}
}### ready
if ($systype eq 'motc') {
my $found = TRUE;
foreach my $bp (@{$db->{'bplan'}}) {
if ($bp->{'_bypass'}) {next;}
if (!$bp->{'index'}) {next;}
if (!$bp->{'siteno'}) {
LogIt(1,"Bandplan $bp->{'index'} has no site index!");
next;
}
if ($bp->{'siteno'} == $siteno) {
$found = TRUE;
%work_blk = %{$bp};
$work_blk{'block_addr'} = $site_addr;
$parmref->{'write'} = TRUE;
foreach my $ndx (1..6) {
my $var = "spacing_$ndx";
my $value = $work_blk{$var};
if (!$value) {$value = '25000';}
if (!looks_like_number($value) or ($value < 0)) {
LogIt(1,"Unden l2721:Spacing value of $value is not valid. Set to 25000");
$value = '25000';
}
if ($value > 100000) {
LogIt(1,"Uniden l2721:$blockname MCP Spacing of $value is too large. Limited to 100khz");
$value = 100000;
}
$value = (substr(sprintf("%6.6ld",$value),0,-1)) + 0;
$work_blk{$var} = $value;
}
if (uniden_cmd('MCP',$parmref)) {
LogIt(1,"Could not write Bandplan for Site $siteno");
}
}### Looking for a bandplan
if (!$found) {LogIt(1,"No custom bandplan available for site $siteno!");}
}
}
}### BCD325P2 process
else {
%work_blk = ('block_addr' => $sysndx);
$parmref->{'write'} = FALSE;
if ($ready) {
if (uniden_cmd('SIN',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l4153:Cannot get SIN for system $sysno ",$parmref);
}
}### ready
$site_addr = $work_blk{'chn_head'};
}#### BCD396 process
my $tfreqcnt = 0;
foreach my $freqrec (@{$db->{'tfreq'}}) {
threads->yield;
if ($progstate ne $startstate) {last SYSNO;}
if ($freqrec->{'_bypass'}) {next;}
if (!$freqrec->{'index'}) {next;}
if ($freqrec->{'siteno'} != $siteno) {next;}
if (!$freqrec->{'frequency'}) {
print Dumper($freqrec),"\n";
LogIt(1,"Unden 4991:SITE frequency for TFREQ index=>$freqrec->{'index'} cannot be '0'");
next;
}
%work_blk = ('block_base' => $site_addr, 'block_addr' => 0);
if ($ready) {### debug
if (uniden_cmd('ACC',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM:Cannot create TFQ for Siteno=$siteno addr=$site_addr system $sysno ",$parmref);
}### error
}### ready
my $tfq_addr = $work_blk{'block_addr'};
if ($tfq_addr eq '-1') {
LogIt(1,"Number of frequencies ($tfreqcnt) exceeded radio's capacity!");
last;
}
$freqrec->{'block_addr'} = $tfq_addr;
%work_blk = %{$freqrec};
$work_blk{'ccode'} = 'SRCH';
if (looks_like_number($freqrec->{'ccode'})) {
if (($systype =~ /dmr/i) or ($systype =~ /trbo/i)) {
$work_blk{'ccode'} = $freqrec->{'ccode'};
}
}
$work_blk{'lout'} = 0;
$work_blk{'voloff'} = 0;
$work_blk{'utag'} = 'NONE';
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('TFQ',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM:Cannot update TFQ for addr=$tfq_addr for system $sysno ",$parmref);
}### error
}### ready
$tfreqcnt++;
}### each frequency for this site
if (!$tfreqcnt) {
LogIt(1,"SETMEM:No Frequencies assigned to site $siteno system $sysno ");
}
}### for each SITE
}### Trunked system process
my $groupcount = 0;
foreach my $grprec (@{$db->{'group'}}) {
if ($grprec->{'_bypass'}) {next;}
my $groupno = $grprec->{'index'};
if (!$groupno) {next;}
if ($grprec->{'sysno'} != $sysno) {next;}
if ($grprec->{'_bypass'}) {next;}
%work_blk = ('block_base' => $sysndx, 'block_addr' => 0);
if ($ready) {
if (uniden_cmd($grpcmd,$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l4264:Cannot create new group $grpcmd for system $sysno ",$parmref);
}
}### Ready
my $group_addr = $work_blk{'block_addr'};
if ($group_addr eq '-1') {
my $msg = "Group capacity ($Green$groupcount$White) exceeded for this system!";
LogRad(1,$db,"system",$sysno,$msg);
last;
}
$groupcount++;
$db->{'group'}[$groupno]{'block_addr'} = $group_addr;
%work_blk = %{$db->{'group'}[$groupno]};
$work_blk{'gps_enable'} = 0;
if ($db->{'group'}[$groupno]{'lat'} or $db->{'group'}[$groupno]{'lon'}) {
$work_blk{'gps_enable'} = 1;
}
if (looks_like_number($work_blk{'qkey'})) {
$group_qkeys{$work_blk{'qkey'}} = $work_blk{'_keyon'};
}
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('GIN',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l4301:Cannot update GIN for Group $groupno addr=$group_addr for system $sysno ",$parmref);
}### error
}### debug
my @recs = ();
my $chancount = 0;
foreach my $freqrec (@{$db->{'freq'}}) {
threads->yield;
if ($progstate ne $startstate) {last SYSNO;}
if ($freqrec->{'_bypass'}) {next;}
my $freqno = $freqrec->{'index'};
if (!$freqno) {next;}
if ($freqrec->{'groupno'} != $groupno) {next;}
if ($freqrec->{'siteno'}) {next;}
if (($freqrec->{'groupno'}) and ($freqrec->{'groupno'} == $groupno)) {
push @recs,$freqrec;
}
%work_blk = ('block_base' => $group_addr,'block_addr' => 0);
if ($ready) {
if (uniden_cmd($chncmd,$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l4334:Cannot create new $chncmd  for system $sysno ",$parmref);
}### Error
}### Ready
my $chan_addr = $work_blk{'block_addr'};
if ($chan_addr eq '-1') {#### no more room at the inn
uniden_cmd('MEM',$parmref);
if (!$work_blk{'chan_count'}) {$work_blk{'chan_count'} = '?';}
my $msg = "Channel capacity exceeded.\n" .
"          $Green$chancount$White channels in group addr:$Magenta$group_addr$White " .
"(radio total:$Cyan$work_blk{'chan_count'}$White)";
LogRad(1,$db,"group",$groupno,$msg);
last;
}
$freqrec->{'block_addr'} = $chan_addr;
%work_blk = %{$freqrec};
$work_blk{'lout'} = !$work_blk{'valid'};
$work_blk{'audio'} = 0;
$work_blk{'dsql'} = 'SRCH';
$work_blk{'ctcsdcs'} = 0;
$work_blk{'tonelock'} = 0;
$work_blk{'tslot'} = 'ANY';
if ($work_blk{'mode'} and ($work_blk{'mode'} =~ /fm/i)) {
my ($tt,$tone) = Tone_Xtract($freqrec->{'sqtone'});
if ($tt =~ /ctc/i) {
$work_blk{'ctcsdcs'} = $valid_ctc{$tone} + 63;
$work_blk{'tonelock'} = 1;
}
elsif ($tt =~ /dcs/i) {
$work_blk{'ctcsdcs'} = $valid_dcs{$tone} + 127;
$work_blk{'tonelock'} = 1;
}
elsif ($tt =~ /nac/i) { 
$work_blk{'dsql'} = $tone;
$work_blk{'audio'} = 2;
}
elsif ($tt =~ /ccd/i) { 
$work_blk{'dsql'} = sprintf("%4.4x",($tone + 4096));
$work_blk{'audio'} = 2;
}
else {
}
}### FM mode found for tone process
$work_blk{'priority'} = FALSE;
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd($chnblk,$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM:Cannot update $chnblk for system $sysno ",$parmref);
}### error
}### ready
$chancount++;
}### Each record
}### Group process
%work_blk = ('block_addr' => $sysndx, 'grpkey' => \%group_qkeys);
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('QGL',$parmref)) {
$parmref->{'out'} = $outsave;
return exit_prg("SETMEM l4464:Could not update Group QuickKeys for system $sysno ",$parmref);
}### error
}### Ready
$count++;
}### system process
$parmref->{'write'} = TRUE;
uniden_cmd('QSL',$parmref);
SETDONE:
exit_prg($parmref);
$parmref->{'out'} = $outsave;
$outsave->{'count'} = $count;
LogIt(0,"System Write complete");
return ($parmref->{'rc'} = $retcode);
}###setmem
elsif ($cmdcode eq '_delete') {
my $sysno = $in->{'sysno'};
my %allsys = ();
$parmref->{'database'} = \%allsys;
my $rc = uniden_cmd('_getall',$parmref);
$parmref->{'database'} = $db;
if ($rc) {
add_message("_DELETE:Could not get systems in this Uniden radio!");
return $rc;
}
if (defined $allsys{'system'}[$sysno]{'block_addr'}) {
my $name = $allsys{$sysno}{'system'}{$sysno}{'service'};
my $addr = $allsys{$sysno}{'system'}{$sysno}{'block_addr'};
LogIt(0,"System $sysno (name=$name addr=$addr) is being removed");
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("_DELETE: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
$out->{'block_addr'}  = $addr;
if (uniden_cmd('DSY',$parmref)) {
return exit_prg("_DELETE:unable to delete system $sysno",$parmref);
}
if ($Debug3) {DebugIt("Uniden l5437: 'DSY' returned=>$parmref->{'rcv'}");}
uniden_cmd('SCT',$parmref);
while (! uniden_cmd('nop',$parmref)) {
if ($Debug3) {DebugIt("Waiting for bus to clear");}
}
LogIt(0,"system $sysno removed!");
}
else {
LogIt(1,"$sysno does not exist in the connected radio. Cannot delete.");
return ($parmref->{'rc'} = $EmptyChan);
}
goto DONE;
}
elsif ($cmdcode eq 'getglob') {
if (!$model) {
if (uniden_cmd('MDL',$parmref)) {
add_message("GETGLOG:Could not get Uniden model number!");
return $parmref->{'rc'};
}
}
if ($model eq 'SDS200') {return;}
my $p2 = FALSE;
if ($radio_def{'model'} eq 'BCD325P2') {$p2 = TRUE;}
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("GETGLOB: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
$retcode = 0;
foreach my $cmd ('OMS','BLT','KBP') {
%work_blk = ();
$parmref->{'write'} = FALSE;
if (uniden_cmd($cmd,$parmref)) {
add_message("GETGLOB: command failed $cmd!");
$retcode = $parmref->{'rc'};
}
else {
foreach my $key (keys %work_blk) {
if ($key eq 'block_type') {next;}
if ($key eq 'rsvd') {next;}
my $value = Strip($work_blk{$key});
$radio_def{$key} = $value;
}
}
}
$db->{'powermsg'} = ();
my %newrec = ();
foreach my $key ('msg1','msg2','msg3','msg4') {$newrec{$key} = $radio_def{$key};}
my $pwndx = add_a_record($db,'powermsg',\%newrec);
$db->{'light'} = ();
my $event = $radio_def{'event'};
if (!$event) {
if ($Debug2) {DebugIt("Unden l5562:Empty event!");}
$event = '';
}
$event = lc($event);
my $dimmer = $radio_def{'dimmer'};
if ($event eq 'if') {$event = 'on';}
%newrec = ('event' => $event, 'bright' => $dimmer);
my $lightdx = add_a_record($db,'light',\%newrec);
$db->{'beep'} = ();
my $level = $radio_def{'beep'};
if ($level == 0) {$level = 15;}
elsif ($level == 99) {$level = 0;}
%newrec = ('volume' => $level);
my $beepdx =  add_a_record($db,'beep',\%newrec);
if ($p2) {
$db ->{'ifxchng'} = ();
my $ifcount = 0;
my $lastfreq = '1';
while ($lastfreq > 0) {
%work_blk = ();
if (uniden_cmd('GIE',$parmref)) {
add_message("GETGLOB:Command failed GIE!");
$retcode = $parmref->{'rc'};
last;
}
$lastfreq = Strip($work_blk{'frequency'});
if ($lastfreq > 0) {
my %newrec = ('frequency' => $lastfreq);
my $newrec = add_a_record($db,'ifxchng',\%newrec);
$ifcount++;
}
}
LogIt(0,"found $ifcount IF Exchange records");
}
my $lastfreq = '1';
my $lockcount = 0;
LogIt(0,"Getting Lockout records");
$db ->{'lockfreq'} = ();
while ($lastfreq > 0) {
$parmref->{'write'} = FALSE;
%work_blk = ();
if (uniden_cmd('GLF',$parmref)) {
add_message("GETGLOB:Command failed GLF!");
$retcode = $parmref->{'rc'};
last;
}
$lastfreq = Strip($work_blk{'frequency'});
if ($lastfreq > 0) {
my %newrec = ('frequency' => $lastfreq);
my $newrec = add_a_record($db,'lockfreq',\%newrec);
$lockcount++;
}
if ($Debug3) {DebugIt("UNIDEN l5631: lastfreq=$lastfreq");}
}
LogIt(0,"found $lockcount lockout records");
%work_blk = ();
exit_prg($parmref);
$parmref->{'out'} = $outsave;
LogIt(0,"GET_GLOBALS is complete");
return ($parmref->{'rc'} = $retcode);
}
elsif ($cmdcode eq 'setglob') {
LogIt(0,"Called Uniden SETGLOB");
if (!$model) {
if (uniden_cmd('MDL',$parmref)) {
add_message("SETGLOB:Could not get Uniden model number!");
return $parmref->{'rc'};
}
}
if (substr(lc($model),0,3) ne 'bcd') {
LogIt(1,"SETGLOB not valid for $model");
return $NotForModel;
}
my $p2 = FALSE;
if ($radio_def{'model'} eq 'BCD325P2') {$p2 = TRUE;}
my $clear = FALSE;
if ($in->{'erase'}) {$clear = TRUE;}
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("SETGLOB: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
$retcode = $GoodCode;
if (defined $db->{'powermsg'}[1]) {
%work_blk = ();
foreach my $key ('msg1','msg2','msg3','msg4') {
my $msg = $db->{'powermsg'}[1]{$key};
if (!$msg) {$msg = '';}
$work_blk{$key} = $msg;
}
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('OMS',$parmref)) {
add_message("SETGLOB:Command failed to set opening message!");
$retcode = $parmref->{'rc'};
}### failure
}### ready
}
if ($db->{'light'}[1]{'index'}) {
%work_blk = ('event' => '10','bright' => 3);
if ($db->{'light'}[1]{'event'}) {
my $event = uc($db->{'light'}[1]{'event'});
if ($event eq 'ON') {$event = 'IF';}
elsif ($event eq 'OFF') {$event = '10';}
elsif ($event eq 'KEY') {$event = 'KY';}
elsif (($event ne '30') and ($event ne '10')
and ($event ne 'KY') and ($event ne 'SQ') ) {
LogIt(1,"Unknown LIGHT event $Green$event$White. Changed to '10'");
$event = '10';
}
$work_blk{'event'} = $event;
}
if ($db->{'light'}[1]{'bright'}) {
my $bright = $db->{'light'}[1]{'bright'};
if (!$bright) {$bright = 0;}
if (!looks_like_number($bright) or ($bright < 1) or ($bright > 3)) {
LogIt(1,"Light bright level of $Green$bright$White not valid. Set to 3");
}
else {$work_blk{'bright'} = $bright;}
}
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('BLT',$parmref)) {
add_message("SETGLOB:Command failed to set BackLight setting!");
$retcode = $parmref->{'rc'};
}### failure
}### ready
}### 'LIGHT' setting defined.
if (defined $db->{'beep'}[1]{'beep'}) {
%work_blk = ('beep' => 0,'lock' => 0,'safe' => 0);
my $beep = $db->{'beep'}[1]{'beep'};
if (looks_like_number($beep)) {
if ($beep < 1) {$beep = 99;}
elsif ($beep > 15) {$beep = 0;}
$work_blk{'beep'} = $beep;
}
else {LogIt(1,"Beep value of $Green$beep$White is not valid!. Set to default.")}
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('KBP',$parmref)) {
add_message("SETGLOB:Command failed to set Keyboard Beep setting!");
$retcode = $parmref->{'rc'};
}### failure
}### ready
}### Keyboard beep
if ($p2 and $db->{'ifxchng'}[1]{'frequency'}) {
if ($clear) {
my @clrfreq = ();
my $lastfreq = '1';
while ($lastfreq > 0) {
%work_blk = ();
if (uniden_cmd('GIE',$parmref)) {
add_message("GETGLOB:Command failed GIE!");
$retcode = $parmref->{'rc'};
last;
}
$lastfreq = Strip($work_blk{'frequency'});
if ($lastfreq > 0) {push @clrfreq,$lastfreq;}
}
foreach my $freq (@clrfreq) {
if ($Debug2) {DebugIt("Uniden l5871 Clearing IF Exchange Frequency $freq");}
%work_blk = ('frequency' => $freq);
$parmref->{'write'} = TRUE;
if (uniden_cmd('CIE',$parmref)) {
add_message("GETGLOB:Command failed CIE!");
$retcode = $parmref->{'rc'};
last;
}
}
}
foreach my $rec (@{$db->{'ifxchng'}}) {
if (!$rec->{'index'}) {next;}
my $freq = $rec->{'frequency'};
if (!$freq) {next;}
%work_blk = ('frequency' => $freq);
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('RIE',$parmref)) {
add_message("SETGLOB:Command failed RIE!");
$retcode = $parmref->{'rc'};
last;
}### error
}## Ready
}### ifxchng records
}### process IF exchange frequencies
if ($db->{'lockfreq'}[1]{'frequency'}) {
if ($clear) {
}
foreach my $rec (@{$db->{'lockfreq'}}) {
if (!$rec->{'index'}) {next;}
my $freq = $rec->{'frequency'};
if (!$freq) {next;}
%work_blk = ('frequency' => $freq);
$parmref->{'write'} = TRUE;
if ($ready) {
if (uniden_cmd('LOF',$parmref)) {
add_message("SETGLOB:Command failed LOF!");
$retcode = $parmref->{'rc'};
last;
}### Error
}### Debug
}### For each lockout record
}### Process lockfreq records
exit_prg($parmref);
$parmref->{'out'} = $outsave;
LogIt(0,"SET_GLOBALS is complete");
return ($parmref->{'rc'} = $retcode);
}
elsif ($cmdcode eq 'gettone') {
LogIt(0,"Called Uniden GETTONE");
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("GETTONE: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
foreach my $ch (0..9) {
$work_blk{'channel'} = $ch;
$parmref->{'write'} = FALSE;
if (uniden_cmd('TON',$parmref)) {
add_message("GETTON: Command failed for getting tone setting $ch");
next;
}
my %newrec = ('channel' => $ch);
foreach my $key (keys %work_blk) {
if ($key eq 'index') {next;}
else {$newrec{$key} = $work_blk{$key};}
}
my $ndx = add_a_record($db,'toneout',\%newrec,FALSE);
}
exit_prg($parmref);
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = 0);
}
elsif ($cmdcode eq 'settone') {
LogIt(0,"Called Uniden SETTONE");
if ((!$db->{'toneout'}) or (scalar @{$db->{'toneout'}} < 2)) {
LogIt(1,"UNIDEN_CMD-SETTONE:No 'toneout' records found");
return $parmref->{'rc'} = $EmptyChan;
}
$parmref->{'write'} = FALSE;
if (enter_prg($parmref)) {
add_message("SETTONE: command failed to get Uniden into program mode!");
return $parmref->{'rc'};
}
my %work_blk = ();
$parmref->{'out'} = \%work_blk;
foreach my $rec (@{$db->{'toneout'}}) {
if (!$rec->{'index'}) {next;}
my $ch = $rec->{'channel'};
if (defined $ch) {
if ((!looks_like_number($ch)) or ($ch < 0) or ($ch > 9)) {
LogIt(1,"SETONE l5681:Channel $ch invalid. Ignored");
next;
}
}
else {
LogIt(1,"SETONE l5682:No channel number in record. Ignored");
next;
}
my $frq = $rec->{'frequency'};
if (!$frq) {
LogIt(1,"SETONE l5693:Frequency is 0 in record. Ignored");
next;
}
foreach my $key (keys %{$rec}) {
$work_blk{$key} = $rec->{$key};
}
$parmref->{'write'} = TRUE;
if (uniden_cmd('TON',$parmref)) {
add_message("SETTON: Command failed for setting tone for $ch");
next;
}
}
exit_prg($parmref);
$parmref->{'out'} = $outsave;
return ($parmref->{'rc'} = 0);
}### SETTONE
elsif (($cmdcode eq 'getsig') or ($cmdcode eq 'getvfo')) {
$out->{'sql'} = FALSE;
$out->{'signal'} = 0;
$out->{'rssi'} = 0;
$out->{'dbmv'} = -999;
$out->{'meter'} = 0;
$out->{'tgid'} = '';
if ($cmdcode eq 'getsig') {
$out->{'frequency'} = 0;
$out->{'mode'} = '';
}
if ($model =~ /sds/i) {
if (!Get_SDS_Status($parmref)) {
if ($out->{'tgid'}) {$out->{'frequency'} = 0;}
}
return ($parmref->{'rc'});
}### SDS radio process
if (uniden_cmd('GLG',$parmref)) {
add_message("GETSIG l4456:GLG Command failed!");
return ($parmref->{'rc'});
}### failure
if ($out->{'sql'}) {
print "Uniden l6175:GLG returned $out->{'mode'}\n";
if (!$out->{'frq_tgid'}) {
LogIt(1,"Uniden line 5817:Not defined 'frq_tgid'");
$out->{'frq_tgid'} = 0;
}
if ($out->{'frq_tgid'} =~ /\./) {
$out->{'frequency'} = freq_to_rc($out->{'frq_tgid'});
$out->{'tgid'} = '';
}
else {
$out->{'tgid'} = $out->{'frq_tgid'};
$out->{'frequency'} = 0;
}
if (!$out->{'service'}) {
$out->{'service'} = '';
if ($out->{'groupname'}) {$out->{'service'} = $out->{'groupname'};}
}
else {
if ($out->{'groupname'}) {
$out->{'service'} = "$out->{'groupname'}:$out->{'service'}";
}
}
if  ($model =~ /bcd325p2/i) {
if (uniden_cmd('PWR',$parmref)) {
add_message("GETSIG:PWR Command failed!");
return ($parmref->{'rc'});
}### failure
}
elsif ($model =~ /bcd396t/i) {
uniden_cmd('STS',$parmref);
}
else {
}
if (!$out->{'signal'}) {$out->{'signal'} = 1;}
}### Squelch open
else {
$last_tgid = '';
$out->{'mode'} = 'FM';
$out->{'frequency'} = $vfo{'frequency'};
uniden_cmd('STS',$parmref);
if ($out->{'mhz'}) {
$out->{'frequency'} = freq_to_rc($out->{'mhz'});
}
$out->{'sql'} = 0;
$out->{'signal'} = 0;
}
return ($parmref->{'rc'} = $retcode);
}### GETSIG/GETVFO
elsif ($cmdcode eq 'setvfo') {
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
add_message("UNIDEN routine detected empty 'mode'. Changed to 'FM'");
$in->{'mode'} = 'FM';
}
$parmref->{'write'} = TRUE;
foreach my $key ('frequency','atten','mode') {
$out->{$key} = $in->{$key};
}
$out->{'dlyrsm'} = 0;
$out->{'code_srch'} = 0;
$out->{'bsc'} = '0000000000000000';
$out->{'rep'} = 0;
$out->{'agc_analog'} = 0;
$out->{'agc_digital'} = 0;
$out->{'p25wait'} = 400;
if (uniden_cmd('QSH',$parmref)) {
add_message("SETVFI:QSH failure");
return ($parmref->{'rc'});
}### failure
if ($model =~ /sds/i) {
$out->{'_delay'} = 1000;
}
else {
$out->{'_delay'}  =  9000;
}### SDS radio process
return ($parmref->{'rc'});
}
elsif ($nodata{$cmdcode}) {
if ($blocks{$cmdcode}) {
LogIt(1,"UNIDEN l6323:Bad data for Uniden command $cmdcode");
return ($parmref->{'rc'} = $ParmErr);
}
}
elsif ($cmdcode eq 'QSL') {
$cmd_parms = '';
if ($parmref->{'write'}) {
foreach my $page (0..9) {
my $bitmap = '';
foreach my $no (1..9,0) {
my $keyno = ($page * 10) + $no;
my $value = '2';
if ($system_qkeys{$keyno}) {$value = 1;}
$bitmap = "$bitmap$value";
}
$cmd_parms = "$cmd_parms,$bitmap";
}
}
}
elsif ($cmdcode eq 'QGL') {
my $sinndx = $out->{'block_addr'};
my $grpkey = $out->{'grpkey'};
$cmd_parms = ",$sinndx";
if ($parmref->{'write'}) {
my $bitmap = '';
foreach my $keyno (1..9,0) {
my $value = 0;
if (defined $grpkey->{$keyno}) {
if ($grpkey->{$keyno}) {$value = 1;}
else {$value = 2;}
}
$bitmap = "$bitmap$value";
}
$cmd_parms = "$cmd_parms,$bitmap";
}
}
elsif ($cmdcode eq 'JPM') {
my $scnmode = uc($out->{'jpm_state'});
$cmd_parms = ",$scnmode";
}
elsif ($cmdcode eq 'ABP') {
}
elsif ($cmdcode eq 'STS') {
}
elsif ($cmdcode eq 'PRG') {
if ($model eq 'SDS200') {return;}
if ($model eq 'SDS100') {return;}
my $outsave = $parmref->{'out'};
my %out = ();
$parmref->{'out'} = \%out;
uniden_cmd('STS',$parmref);
$parmref->{'out'} = $outsave;
}
elsif ($cmdcode eq 'CSY') {
$cmd_parms = ",$out->{'systemtype'}";
if ($model =~ /bcd325/i) {$cmd_parms = "$cmd_parms,0";}
}
elsif ($cmdcode eq 'MEM') {
}
elsif ($cmdcode eq 'BLT') {
if ($parmref->{'write'}) {
$cmd_parms = ",$out->{'event'},,$out->{'bright'}";
}
else {$cmd_parms = '';}
}
elsif (defined $blocks{$blockname}) {
my $p2 = FALSE;
if ($radio_def{'model'} eq 'BCD325P2') {$p2 = TRUE;}
my @reflist = @{$blocks{$blockname}};
foreach my $ref (@reflist) {
my ($keyword) = keys %{$ref};
my $flag = lc($ref->{$keyword});
if ($blockname eq 'TON') {
if ($keyword eq 'channel') {
if (!defined $out->{$keyword}) {
print Dumper($out),"\n";
LogIt(1,"Missing required keyword:$keyword for Uniden command $cmdcode");
return ($parmref->{'rc'} = $ParmErr);
}
push @send_validate,$keyword;
push @rcv_validate,$keyword;
}
else {
if ($parmref->{'write'}) {
my $keep = TRUE;
if (!$p2) {
if ($keyword eq 'emgcol') {$keep = FALSE;}
elsif ($keyword eq 'rsvd') {$keep = FALSE;}
elsif ($keyword eq 'emgcol') {$keep = FALSE;}
elsif ($keyword eq 'agc_analog') {$keep = FALSE;}
}
if ($keep) {
push @send_validate,$keyword;
}
}
else {
push @rcv_validate,$keyword;
}
}
next;
}### 'TON' process
elsif ($flag =~ /q/i) {### required parameter for read and write
if (!defined $out->{$keyword}) {
print Dumper($out),"\n";
LogIt(1,"Missing required keyword:$keyword for Uniden command $cmdcode");
return ($parmref->{'rc'} = $ParmErr);
}
push @send_validate,$keyword;
}
elsif (($flag =~ /r/i) or
(($flag =~ /s/i) and ($model =~ /bcd325p2/i)) or
(($flag =~ /t/i) and ($model =~ /sds/i)) or
(($flag =~ /u/i) and ($model =~ /bcd396t/i)) ) {
push @rcv_validate,$keyword;
}
elsif (($flag =~ /b/i) or
(($flag =~ /3/i) and ($model =~ /bcd325p2/i)) or
(($flag =~ /2/i) and ($model =~ /sds/i)) or
(($flag =~ /1/i) and ($model =~ /bcd396t/i)) ) {
if ($parmref->{'write'}) {push @send_validate,$keyword;}
else {push @rcv_validate,$keyword;}
}
elsif ($parmref->{'write'} and (
($flag =~ /w/i) or
(($flag =~ /x/i) and ($model =~ /bcd325p2/i)) or
(($flag =~ /y/i) and ($model =~ /sds/i)) or
(($flag =~ /z/i) and ($model =~ /bcd396t/i)) ) ) {
push @send_validate,$keyword;
}
}### Each key in the block
if (scalar @send_validate) {
my $parmcnt = 1;
foreach my $parm (@send_validate) {
my $value = '';
if ($parm ne 'rsvd') {$value = $out->{$parm};}
if (!defined $value) {
LogIt(1,"UNIDEN_CMD l3522:Undefined value for $blockname->$parm ");
$value = '';
}
elsif ($parm =~ /freq/)  {
if (looks_like_number($value) and ($value > 0)) {
$value = substr(sprintf("%011.11ld",$value),1,8);
}
}
elsif (($parm eq 'step')  ) {
if (!$value) {$value = 0;}
if (!looks_like_number($value)) {
LogIt(1,"Unden l5061:Step value of $value is not valid. Set to 100hz");
$value = '100';
}
if  ($value > 0) {
$value = substr(sprintf("%011.11ld",$value),1,9);
}
}
elsif ($parm eq 'beep') {
if (!$value) {$value = '99';}
elsif (lc($value) eq 'auto') {$value = 16;}
elsif (looks_like_number($value)) {
if ($value >15) {$value = 15;}
if ($value < 1) {$value = 1;}
}
else {$value = 99;}
}
elsif ($parm eq 'service') {
if (length($value) > 16) {$value = substr($value,0,16);}
}
elsif ($parm eq 'mode') {
$value = rc2mode($value);
if (($blockname eq 'SIF') or ($blockname eq 'TON')) {
if (($value ne 'FM') and ($value ne 'NFM')) {$value = 'NFM';}
}
$last_mode = $value;
}
elsif ($parm eq 'emgalt') {
if (($blockname eq 'TON') and (!$p2)) {
$out->{'emgcol'} = 1;
}
else {
if ($value) {$out->{'emgcol'} = 'RED';}
else {$out->{'emgcol'} = 'OFF';}
}
}
elsif ($parm eq 'emgcol') {
if (($blockname eq 'TON') and (!$p2)) {
$value = 1;
}
}
elsif ($parm eq 'dur') {
if (($blockname eq 'TON') and (!$p2)) {
$value = 1;
}
else {$value  = '';}
}
elsif ($parm =~ /toneout/i) {
$value = sprintf("%05i",$value);
}
elsif ($parm eq 'endcode') {
if (!$value) {$value = 0;}
elsif ($value =~ /^a*/i) {$value = 1;}
elsif ($value =~ /^b*/i) {$value = 2;}
else {$value = 0;}
}
elsif ($parm eq 'p25wait') {
if (!$value) {$value = 400};
if (!looks_like_number($value)) {$value = 0;}
}
elsif ($parm eq 'dlyrsm') {
if ($value) {
my $oldvalue = $value;
if (!$p2) {
if ($value < 1) {$value = 0;}
if ($value > 5) {$value = 5;}
}
else {
if (FALSE) {
if ($value < -8) {$value = -10;}
elsif ($value < -4) {$value = -5;}
elsif ($value <  0) {$value = -2;}
elsif ($value <  3) { }
elsif ($value <  7) {$value = 5;}
elsif ($value <  20) {$value = 10;}
else {$value = 30;}
}
}
if ($blockname eq 'TON') {
if ($value < 1) {$value = 0;}
}
}### DLYRSM not 0
}
elsif (($parm eq 'lat') or ($parm eq 'lon')) {
my ($dec,$dms) = Lat_Lon_Parse($value,$parm);
if ($dec) {
my ($dd,$mm,$sec,$dir) = $dms =~ /(.*?)\:(.*?)\:(.*?)\:(.*)/;
if ($parm eq 'lon') {$dd = substr('000' . $dd,-3,3);}
else {$dd = substr('00' . $dd,-2,2);}
$mm = substr('00' . $mm,-2,2);
$sec =~ s/\.//g;  
$sec = substr($sec . '0000',0,4);
$value = "$dd$mm$sec" . uc(Strip($dir));
}
else {
$value = '00000000N';
if ($parm eq 'lon') {$value = '000000000W';}
}
}
elsif ($parm eq 'utag') {
if (($value eq '') or (!looks_like_number($value)) or ($value < 0)) {
$value = 'NONE';
}
elsif ($value > 999) {
LogIt(1,"UTAG value of $value is too high. Adjusted to 999!");
$value = 999;
}
}
$cmd_parms = "$cmd_parms,$value";
}
}
}### Block pre-process
elsif (lc($cmdcode) eq 'glt') {
LogIt(1,"Uniden 4952:GLT Called. Cannot be processed here");
return 1;
$cmdcode = 'GLT';
$cmd_parms = "," . Strip($in->{'type'});
}
elsif (lc($cmdcode) eq 'poll') {
$cmdcode = lc($cmdcode);
$noprocess = TRUE;
$cmd_parms = '';
}
else {
LogIt(1,"UNIDEN:No pre-process defined for $cmdcode");
$noprocess = TRUE;
$cmd_parms = '';
}
my $sent = '';
my $outstr = '';
my $rc = '';
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => CR,
'delay' => $delay,
'resend' => 0,
'debug' => 0,
'fails' => 0,
'wait' => 30,
);
if ($noprocess or $parmref->{'test'} or ($cmdcode eq 'autobaud')) {
$sendparms{'wait'} = 1;
}
if (defined $special{$cmdcode}) {
foreach my $key (keys %{$special{$cmdcode}}) {
$sendparms{$key} = $special{$cmdcode}{$key};
}
}
my $wait_restore = $sendparms{'wait'};
RESEND:
$sent = Strip($cmdcode);
if ($cmd_parms) {$sent = $sent . $cmd_parms;}
$outstr = '';
if ((!$cmdcode) or ($cmdcode eq 'nop')) {$sent = '';}
else { $outstr = $sent . CR; }
$parmref->{'sent'} = $sent;
if ($Debug2) {DebugIt("UNIDEN l7204:sent=$sent cmdcode=>$cmdcode");}
WAIT:
if ($rc = radio_send(\%sendparms,$outstr)) {
if ($rc eq '-2') {
LogIt(1,"UNIDEN.PM:No open port detected!");
return ($parmref->{'rc'} = $CommErr);
}
if ($Debug3) {DebugIt("UNIDEN l7216:Radio_Send returned $sendparms{'rcv'} retcode=$rc");}
if ($sent) {
if ($sendparms{'wait'}--) {
$outstr = '';
usleep(100);
if ($warn) {print "Waiting...\n";}
else {
return ($parmref->{'rc'} = $CommErr);
}
goto WAIT;
}
if (!$defref->{'rsp'}) {
my $msg = "Radio is not responding. Last command=>$sent.";
if ($warn) {add_message($msg);}
$defref->{'rsp'} = 1;
}
else {$defref->{'rsp'}++;}
return ($parmref->{'rc'} = $CommErr);
}### sent something
else {return( $parmref->{'rc'} = $EmptyChan);}
}
$parmref->{'rsp'} = 0;
my $instr = $sendparms{'rcv'};
if (!defined $instr) {$instr = ''}
if ($Debug3) {DebugIt("UNIDEN l7252: Received $instr");}
if (!$instr) {
if ($sendparms{'wait'}--) {
$outstr = '';
usleep(100);
goto WAIT;
}
add_message("Uniden l5134:radio returned empty response to $cmdcode");
return ($parmref->{'rc'} = $EmptyChan);
}
$parmref->{'rc'} = $GoodCode;
$parmref->{'rcv'} = $instr;
if ($noprocess) {
if (!$instr) {### Should NOT get here, but log it if we do
LogIt(1,"Nothing in the buffer, but got to NOPROCESS...");
$parmref->{'rc'} = $EmptyChan;
}
else {
my $queue = $parmref->{'unsolicited'};
if (!$queue) {LogIt(1,"UNIDEN l4318:Missing unsolicited queue reference in parmref!");}
else {
my %qe = ('uniden_msg' => $instr);
push @{$queue},{%qe};
}
}
return $parmref->{'rc'};
}
my @retvalues = split ',',$instr;
my $retcmd = shift @retvalues;
if (!$retcmd) {$retcmd = '';}
if ($retcmd eq 'ERR') {
if ($sendparms{'fails'}) {
$sendparms{'fails'}--;
$sendparms{'wait'} = $wait_restore;
LogIt(1,"$cmdcode got ERR, Retrying...");
sleep 1;
goto RESEND;
}
else {
if (! $parmref->{'quiet'}) {
LogIt(1,"Uniden gave 'ERR' for $parmref->{'sent'}");
}
return ($parmref->{'rc'} = $ParmErr);
}
}
elsif ($retcmd eq 'NG') {
if (! $parmref->{'quiet'}) {
LogIt(1,"Uniden gave 'NG' for $parmref->{'sent'}");
}
return ($parmref->{'rc'} = $ParmErr);
}
elsif ($retcmd eq 'FER') {
LogIt(1,"Uniden Communications error. ");
return ($parmref->{'rc'} = $CommErr);
}
elsif ($retcmd eq 'ORER') {
LogIt(1,"Uniden Overrun error. ");
return ($parmref->{'rc'} = $CommErr);
}
elsif ($retcmd ne $cmdcode) {
if ($unsolicited{$retcmd}) {
LogIt(1,"Uniden sent unsolicited $retcmd. Cannot issue commands!");
return ($parmref->{'rc'} = $OtherErr);
}
if (! $parmref->{'quiet'}) {
LogIt(1,"Uniden wrong response for $cmdcode! returned=>$instr");
}
if ($parmref->{'test'}) {
return ($parmref->{'rc'} = $OtherErr);
}
if (! $parmref->{'quiet'}) {LogIt(0,"$Bold...Waiting some more..");}
$outstr = '';
goto WAIT;
}
$out->{'_raw'} = $instr;
my $firstparm  = $retvalues[0];
if (!defined $firstparm) {$firstparm = '';}
$parmref->{'rc'} = $GoodCode;
if (lc($firstparm) eq 'ng') {
LogIt(1,"Uniden Returned NG. May be in wrong state. Sent=>$Green" . $parmref->{'sent'});
$parmref->{'rc'} = $ParmErr;
}
elsif (lc($firstparm) eq 'err') {
LogIt(1,"Uniden Returned ERR. Maybe bad parm. Sent=>$Green" . $parmref->{'sent'});
$parmref->{'rc'} = $ParmErr;
}
elsif (lc($firstparm) eq 'ok') {
if ($Debug2) {DebugIt("UNIDEN l7417:Radio returned $instr");}
if ($cmdcode eq 'EPG') {
sleep 1;
}
}
elsif ($retcmd eq 'STS') {
$out->{'dsp_form'} = Strip(shift @retvalues);
my $linecnt = length($out->{'dsp_form'});
my $this_mode = $last_mode;
my $menu = FALSE;
my $ndx = 1;
$out->{'raw'} = '';
$out->{'sigmeter'} = 0;
my $hold = FALSE;
my $lockout = FALSE;
while ($linecnt) {
my $cvar = 'lchar' . $ndx;
my $dvar = 'ldply' . $ndx;
$out->{$cvar} = '';
$out->{$dvar} = '';
my $line = shift @retvalues;
if (!$line) {$line = '';}
my $fmt = shift @retvalues;
if (!$fmt) {$fmt = '';}
$out->{$cvar} = $line;
$out->{$dvar} = $fmt;
if ($ndx == 1) {
if ($line) {
$out->{'raw'} = unpack("H32",$line);
my $sigoff = 10;
if ($model =~ /sds/i) {
$sigoff = 26;
}
else {
if (($line =~ /[a-zA-Z]/)) {
$state_save{'state'} = 'mnu';
$out->{'state'} = 'mnu' ;
$out->{'signal'} = 0;
return 0;
}
my $hex = unpack("H2",substr($line,1,1));
if (lc($hex) eq '8d') {$hold = TRUE;}
$hex = unpack("H2",substr($line,5,1));
if (lc($hex) eq '95') {$lockout = TRUE;}
}### Not the SDS200 process
my $sigmeter = hex(unpack("H4",substr($line,$sigoff,2)));
$out->{'sigmeter'} = $sigmeter;
my $signal = 0;
my $meter = 0;
if ($sigmeter >= 44205)   {$meter  = 5;}
elsif ($sigmeter > 43691) {$meter  = 4;}
elsif ($sigmeter > 43177) {$meter = 3;}
elsif ($sigmeter > 42784) {$meter = 2;}
elsif ($sigmeter > 42528) {$meter = 1;}
elsif ($sigmeter >8224)   {$meter = 0;}
$signal = $meter2sig[$meter];
if (!$signal) {$signal = 1;}
my $rssi = 0;
if ($rssi2sig{$model}[$signal]) {
$rssi = $rssi2sig{$model}[$signal];
}
my $dbmv = $rssi2sig{'sds'}[$signal];
$out->{'meter'} = $meter;
$out->{'signal'} = $signal;
$out->{'rssi'} = $rssi;
$out->{'dbmv'} = $dbmv;
}### data on line one
}### Line one process
else {
if ($line =~ /mhz/i) {
($out->{'mhz'}) = $line =~ /(.*)mhz/i;
}
elsif ($line =~ /fm/i) {$this_mode = 'FMn';}
elsif ($line =~ /am/i) {$this_mode = 'AM';}
elsif ($line =~ /auto/i) {
$this_mode = 'FM';
}
}
$ndx++;
$linecnt--;
}### For each linecount
if ($this_mode) {$last_mode = $this_mode;}
$out->{'mode'} = mode2rc($last_mode);
my @keys = ('sql','mute','battery','wat');
my @extrakeys = ('rsvd1','rsvd2','sigl');
if ($model =~ /396/) {@extrakeys = ();}
foreach my $key (@keys,@extrakeys) {
if (scalar @retvalues) {$out ->{$key} = shift @retvalues;}
else {$out->{$key} = '';}
}
if (!$out->{'signal'}) {$out->{'signal'} = 0;}
my $state =  $state_save{'state'};
if ($out->{'lchar2'} =~ /remote/i) {$state = 'prg';}
else {
if ($model =~ /396/) {
if (substr($out->{'lchar5'},0,1) eq 'S') {### system quick-keys for scanning
$state = 'scan';
}
elsif ($out->{'lchar3'} =~ /yes/i) {### asking a question
$state = 'mnu';
}
elsif ($out->{'lchar2'} =~ /quick/i) {### Quick search
$state = 'srchquick';
}
elsif ($out->{'lchar5'} =~ /scr/i) {### Custom search
$state = 'srchcust'
}
else {
$state = 'srchserv'
}
}### Model BCD396T
elsif ($model =~ /325/) {
if (substr($out->{'lchar6'},0,3) eq 'GRP') {
$state = 'scan';
}
elsif ($out->{'lchar3'} =~ /yes/i) {### asking a question
$state = 'mnu';
}
elsif ($out->{'lchar2'} =~ /tone/i) { 
$state = 'tone';
}
elsif ($out->{'lchar2'} =~ /quick/i) {### Quick search
$state = 'srchquick';
}
elsif ($out->{'lchar6'} =~ /[0-9]/) {
$state = 'srchcust';
}
else {
$state = 'srchserv';
}
}
elsif ($model =~ /sds/i) {
$state = 'scn';
}
else {
LogIt(1,"No state code for model $model");
}
if ($hold) {$state = $state . '-hold';}
}### Not in program mode
$out->{'state'} = $state;
$state_save{'state'} = $state;
}### STS
elsif ($cmdcode eq 'MDL') {
$model = $retvalues[0];
$out->{'model'} = $retvalues[0];
}
elsif ($cmdcode eq 'QSL') {
foreach my $pageno (0..9) {
my $page = shift @retvalues;
if (!defined $page) {last;}
my @bits = split "",$page;
foreach my $no (1..9,0) {
my $keyno = ($pageno * 10) + $no;
my $bit = shift @bits;
if ($bit eq '1') {$system_qkeys{$keyno} = 1;}
elsif ($bit eq  '2') {$system_qkeys{$keyno} = 0;}
else {delete $system_qkeys{$keyno};}
}
}
}
elsif ($cmdcode eq 'QGL') {
my $grpkey = $out->{'grpkey'};
my @bits = split "",$retvalues[0];
foreach my $keyno (1..9,0) {
my $bit = shift @bits;
if ($bit) {
if ($bit == 1) {$grpkey->{$keyno} = 1;}
else {$grpkey->{$keyno} = 0;}
}
}
}
elsif ($cmdcode eq 'GID') {
if ($retvalues[1]) {
$out->{'tgid'} = $retvalues[1];
$last_tgid = $retvalues[1];
}
}
elsif ($cmdcode eq 'GLT') {
$out->{'xml'} = $instr;
}
elsif ($cmdcode eq 'CSY') {
$out->{'block_addr'} = shift @retvalues;
}
elsif ($cmdcode eq 'MEM') {
$out->{'block_type'} = $cmdcode;
foreach my $ref (@{$blocks{'MEM'}}) {
foreach my $key (keys %{$ref}) {$out->{$key} = shift @retvalues;}
}
}
elsif ($cmdcode eq 'BLT') {
foreach my $key ('event','rsvd','bright') {
my $value = shift @retvalues;
if (!$value) {$value = '';}
$out->{$key} = $value;
}
}
elsif ($cmdcode eq 'PWR') {
my $rssi = shift @retvalues;
rssi_cvt($rssi,$out);
my $signal = $out->{'signal'};
$out->{'meter'} = $sig2meter[$signal];
}### PWR process
elsif ($blocks{$cmdcode}) {
$out->{'block_type'} = $cmdcode;
foreach my $key (@rcv_validate) {
if (!scalar @retvalues) {
if ($Debug2) {
DebugIt("Uniden l8152: Ran out of values for $cmdcode at key $key instr=>$instr");
}
last;
}
my $value = shift @retvalues;
if (!defined $value) {last;}
if ($key eq 'lout') {
}
elsif ($key =~ /freq/) {
if (!$value) {$value = '0';}
if (looks_like_number($value)) {
if ($value > 0) {
$value = $value . '00';
}
}
else {
LogIt(1,"Uniden l8064:Non-number returned for key=$key value=$value instr=$instr");
}
}
elsif ($key eq 'frq_tgid') {
if (looks_like_number($value) and ($value > 99999) ) {
$out->{'frequency'} = $value . '00';
}
else {$out->{'tgid'} = $value;}
}
elsif ($key eq 'systemtype') {
$value = lc($value);
if ($model =~ /325/) {  
if ($systypes_bcd325p2{$value}) {$value = $systypes_bcd325p2{$value};}
}
else {
if ($systypes_bcd396{$value}) {$value = $systypes_bcd396{$value};}
}
}
elsif ($key =~ /spacing/) {
if (!$value) {$value = '0';}
else {$value = $value . '0';}
}
elsif ($key eq 'step') {### value MAY be 10hz or AUTO{
if (looks_like_number($value) and ($value > 0)) {
$value = $value . '0';
}
elsif (lc($value) eq 'auto') {
$value = 5000;
my $lf = $out->{'start_freq'};
if ($lf) {
if (   $lf <=  27995000) {$value =   5000;}
elsif ($lf <=  29680000) {$value =  20000;}
elsif ($lf <=  49990000) {$value =  10000;}
elsif ($lf <=  53980000) {$value =  20000;}
elsif ($lf <=  71950000) {$value =  50000;}
elsif ($lf <=  75995000) {$value =   5000;}
elsif ($lf <=  87950000) {$value =  50000;}
elsif ($lf <= 107900000) {$value = 100000;}
elsif ($lf <= 136991600) {$value =   8330;}
elsif ($lf <= 143987500) {$value =  12500;}
elsif ($lf <= 147995000) {$value =   5000;}
elsif ($lf <= 150787500) {$value =  12500;}
elsif ($lf <= 161995000) {$value =   5000;}
elsif ($lf <= 173987500) {$value =  12500;}
elsif ($lf <= 215995000) {$value =  50000;}
elsif ($lf <= 224980000) {$value =  20000;}
elsif ($lf <= 379975000) {$value =  25000;}
elsif ($lf <= 757999500) {$value =  12500;}
elsif ($lf <= 805993750) {$value =   6250;}
else                     {$value =  12500;}
}### LF is specified
}
}
elsif ($key eq 'mode') {
if ($value) {$last_mode = $value;}
$value = mode2rc($value);
}
elsif ($key eq 'qkey') {
if (!looks_like_number($value)) {$value = -1;}
elsif ($value > 99) {$value = 0;}
}
elsif ($key eq 'rssi') {
my $signal = rssi_cvt($value,$out);
}### rissi
elsif ($key eq 'beep') {### Need to convert BEEP value to RadioCtl
if ($value eq '99') { $value = 0;}
elsif ($value eq '0') {$value = 'AUTO';}
}
elsif ($key eq 'endcode') {
if (looks_like_number($value)) {
if ($value == 2) {$value = 'b';}
elsif ($value ==1) {$value = 'a';}
else {$value = '';}
}
else {$value = '';}
}
elsif ($key eq 'emgcol') {
my $index = 'off';
if ($value) {$index = lc($value);}
if (defined $color_xlate{$index}) {$value = $color_xlate{$index};}
else {$value = 0;}
}
elsif ($key eq 'utag') {
if (!looks_like_number($value)) {$value = -1;}
}
elsif (($key eq 'lat') or ($key eq 'lon')) {
my ($dd,$mm,$ss,$dir) = $value =~ /(..)(..)(....)(.)/;
if ($key eq 'lon') {($dd,$mm,$ss,$dir) = $value =~ /(...)(..)(....)(.)/;}
$ss = $ss / 100;
my ($dec,$dms) = Lat_Lon_Parse("$dd:$mm:$ss:$dir",$key);
$value = $dec;
}
elsif ($key =~ /ccode/i) {
if ((!looks_like_number($value)) or ($value > 15)) {
$value = 's';
}
}
else {
}
$out->{$key} = $value;
}### Validate each key
}### Block process
else {
LogIt(1,"No post processing defined for command $cmdcode");
}
return $parmref->{'rc'};
DONE:
if (($model ne 'SDS200') and ($model ne 'SDS100')) {
uniden_cmd('EPG',$parmref);
}
NOPRG:
if ($outsave) {$parmref->{'out'} = $outsave;}
$parmref->{'rc'} = $retcode;
return $retcode;
}
sub rssi_cvt {
my $value = shift @_;
my $out = shift @_;
my $signal = 0;
my $mod = lc(substr($model,0,3));
if ($mod ne 'sds') {$mod = lc($model);}
my $tabref = $rssi2sig{$mod};
if (!$tabref) {
LogIt(1,"No RSSI_CVT process defined for model $model");
return $signal;
}
my @rssi_table = @{$tabref};
foreach my $cmp (@rssi_table) {
if (($value < $cmp) or ($signal >= MAXSIGNAL)){
last;
}
$signal++;
}
$out->{'signal'} = $signal;
if ($mod eq 'sds') {
$out->{'rssi'} = $rssi2sig{'bcd325p2'}[$signal];
$out->{'dbmv'} = $value;
}
else {
$out->{'rssi'} = $value;
$out->{'dbmv'} = $rssi2sig{'sds'}[$signal];
}
return $signal;
}
sub exit_prg {
my $parmref = shift @_;
my $msg = shift @_;
if (!$msg) {$msg = '';}
my $oldrc = $parmref->{'rc'};
my $outsave = $parmref->{'out'};
my $prior = $state_save{'state'};
if (!$prior) {$prior = '';}
my %out = ();
$parmref->{'out'} = \%out;
uniden_cmd('EPG',$parmref);
if ($prior =~ /mnu/i) {
}
elsif ($prior =~ /quick/i) {
}
elsif ($prior =~ /scan/i) {
$out{'jpm_state'} = 'SCN_MODE';
uniden_cmd('JPM',$parmref);
}
elsif ($prior =~ /cust/i) {
$out{'jpm_state'} = 'CTM_MODE';
uniden_cmd('JPM',$parmref);
}
elsif ($prior =~ /serv/i) {
$out{'jpm_state'} = 'SVC_MODE';
uniden_cmd('JPM',$parmref);
}
elsif ($prior =~ /tone/i) {
$out{'jpm_state'} = 'FTO_MODE';
uniden_cmd('JPM',$parmref);
}
else {
LogIt(1,"UNIDEN 8890:Don't know how to return to $prior state!");
}
if ($prior =~ /hold/i) {
$out{'key_code'} = 'H';
$out{'key_mode'} = 'P';
uniden_cmd('KEY',$parmref);
}
uniden_cmd('STS',$parmref);
$parmref->{'out'} = $outsave;
$parmref->{'rc'} = $oldrc;
if ($msg) {add_message($msg);}
return 0;
}
sub enter_prg {
my $parmref = shift @_;
my $oldrc = $parmref->{'rc'};
my $outsave = $parmref->{'out'};
my %out = ();
$parmref->{'out'} = \%out;
my $rc = uniden_cmd('STS',$parmref);
if ((!$rc) and ($state_save{'state'} !~ /prg/i)) {
$rc = uniden_cmd('PRG',$parmref);
}
$parmref->{'out'} = $outsave;
$parmref->{'rc'} = $oldrc;
if ($rc) {$rc = 1};
return $rc;
}
sub select_systems {
my $in = shift @_;
my $allsys = shift @_;
my $system = shift @_;
if ($in->{'clear'} or $in->{'blk'} or $in->{'num'} or $in->{'nam'}) {
my $fld = '';
my $ref = '';
my %cmp = ();
if ($in->{'blk'}) {
$fld = 'block_addr';
$ref = $in->{'blk'};
}
elsif ($in->{'num'}) {
$fld = 'index';
$ref = $in->{'num'};
}
elsif ($in->{'nam'}) {
$fld = 'service';
$ref = $in->{'nam'};
}
elsif ($in->{'clear'}) {
$ref = '*';
}
else {LogIt(4498,"UNIDEN l8582:SELECT - Bad logic!");}
foreach my $rec (@{$allsys->{'system'}}) {
if (!$rec->{'index'}) {next;}
my $key = Strip($rec->{$fld});
if ($ref eq '*') {push @{$system},$rec;}
else {$cmp{$key} = $rec;}
}
if ($ref ne '*') {
foreach my $value (@{$ref}) {
my $key = Strip($value);
if ($cmp{$key}) {push @{$system},$cmp{$key};}
}
}
}### system search
return 0;
}
sub mode2rc {
my $uniden = shift @_;
my ($package, $filename, $line) = caller;
if (!$uniden) {$uniden = 'FM';}
my $mode = 'FMn';
if ($uniden =~ /am/i) {$mode = 'AM';}
elsif ($uniden =~ /wfm/i) {$mode = 'WF';}
elsif ($uniden =~ /fmb/i) {$mode = 'WF';}
elsif ($uniden =~ /nfm/i) {$mode = 'FMu';}
elsif ($uniden =~ /fm/i) {$mode = 'FMn';}
elsif ($uniden =~ /auto/i) {$mode = 'FM';}
else {
print "Uniden l8700:$Bold Uniden mode $uniden was not decoded. Caller=>$line$Eol";
$mode = 'FM';
}
return $mode;
}
sub rc2mode {
my $mode = shift @_;
if (!$mode) {$mode = 'FMn';}
my $uniden = 'FM';
if ($mode =~ /am/i) {$uniden = 'AM';}
elsif ($mode =~ /ls/i) {$uniden = 'AM';}  
elsif ($mode =~ /us/i) {$uniden = 'AM';}  
elsif ($mode =~ /cw/i) {$uniden = 'AM';}  
elsif ($mode =~ /cr/i) {$uniden = 'AM';}  
elsif ($mode =~ /rt/i) {$uniden = 'AM';} 
elsif ($mode =~ /rr/i) {$uniden = 'AM';} 
elsif ($mode =~ /wf/i) {$uniden = 'WFM';} 
elsif ($mode =~ /fmu/i) {$uniden = 'NFM';} 
elsif ($mode =~ /fm/i) {$uniden = 'FM';}  
else {
LogIt(1,"Uniden l871:No encode for RC Mode:$mode");
$uniden = 'FM';
}
return $uniden;
}
sub Get_All_SDS {
my $parmref = shift @_;
my $db = $parmref->{'database'};
my $out  = $parmref->{'out'};
my $in = $parmref->{'in'};
my $startstate = $progstate;
my $notrunk = $in->{'notrunk'};
if (!$notrunk) {$notrunk = FALSE;}
my %fldb = ();
my $rc = Get_XML('FL',0,\%fldb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l5990:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
LogIt(0,"Get_All_SDS l6006: Got all Favorites...");
my $channel = 0;
FAVLOOP:
foreach my $flndx (keys %fldb) {### for each favorites
if (   lc($fldb{$flndx}{'name'}) eq 'search with scan') {next;}
elsif (lc($fldb{$flndx}{'monitor'}) eq 'off') {next;}
LogIt(0,"Processing favorites index $flndx");
my %sysdb = ();
my $rc = Get_XML('SYS',$flndx,\%sysdb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6004:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
SYSLP:
foreach my $sysndx (keys %sysdb) {
my %rec = ('valid' => TRUE,
'block_addr' => $sysndx,
);
XML_Proc(\%rec,\%{$sysdb{$sysndx}},'system');
my $systype = $rec{'systemtype'};
if ($systype =~ /unknown/i) {
LogIt(1,"UNIDEN l8845: No code to deal with systemtype:$systype");
next SYSLP;
}
LogIt(0,"UNIDEN l8848:System type=$systype");
if ($notrunk and ($systype !~ /cnv/i)) {next SYSLP;}
my $sysno = add_a_record($db,'system',\%rec,$parmref->{'gui'});
if ($systype =~ /cnv/i) {
my %deptdb = ();
my $rc = Get_XML('DEPT',$sysndx,\%deptdb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6030:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
foreach my $grpndx (keys %deptdb) {
my %rec = ('valid' => TRUE,
'block_addr' => $grpndx,
'sysno' =>$sysno,
);
XML_Proc(\%rec,\%{$deptdb{$grpndx}},'group');
my $grpno = add_a_record($db,'group',\%rec,$parmref->{'gui'});
my %freqdb = ();
my $rc = Get_XML('CFREQ',$grpndx,\%freqdb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6051:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
foreach my $frqndx (keys %freqdb) {
my %rec = ('valid' => TRUE,
'block_addr' => $frqndx,
'channel' => '-',
'adtype' => 'analog',
'sqtone' => 'Off',
'tgid_valid' => FALSE,
'sysno' => $sysno,'groupno'=> $grpno,
);
XML_Proc(\%rec,\%{$freqdb{$frqndx}},'freq');
my $freqno = add_a_record($db,'freq',\%rec,$parmref->{'gui'});
threads->yield;
if ($progstate ne $startstate) {last FAVLOOP;}
}
}### Group process
}
else {
LogIt(0,"Trunked system type is $systype");
my %sitedb = ();
my $rc = Get_XML('SITE',$sysndx,\%sitedb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6095:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
foreach my $sitendx (keys %sitedb) {
my %rec = ('valid' => TRUE,
'block_addr' => $sitendx,
'sysno' => $sysno,
);
XML_Proc(\%rec,\%{$sitedb{$sitendx}},'site');
my $siteno = add_a_record($db,'site',\%rec);
my %tfreq = ();
my $rc = Get_XML('SFREQ',$sitendx,\%tfreq,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6112:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
foreach my $tfqndx (keys %tfreq) {
my %rec = ('valid' => TRUE,
'siteno' => $siteno,
);
XML_Proc(\%rec,\%{$tfreq{$tfqndx}},'tfreq');
my $tfreqno = add_a_record($db,'tfreq',\%rec);
}### For each tfreq
threads->yield;
if ($progstate ne $startstate) {last FAVLOOP;}
}### For each site
my %groupdb = ();
$rc = Get_XML('DEPT',$sysndx,\%groupdb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6030:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
foreach my $grpndx (keys %groupdb) {
my %rec = ('valid' => TRUE,
'block_addr' => $grpndx,
'sysno' =>$sysno,
);
XML_Proc(\%rec,\%{$groupdb{$grpndx}},'group');
my $grpno = add_a_record($db,'group',\%rec);
my %tgiddb = ();
my $rc = Get_XML('TGID',$grpndx,\%tgiddb,$parmref);
if ($rc) {
LogIt(1,"Get_All_SDS l6030:Bad return from Get_XML=>$rc");
return ($parmref->{'rc'} = $rc);
}
foreach my $tgidndx (keys %tgiddb) {
my %rec = ('valid' => TRUE,
'block_addr' => $tgidndx,
'frequency' => 0, 'mode' => '-',
'tgid_valid' => TRUE,
'groupno' => $grpno,
'sysno' =>$sysno,
);
XML_Proc(\%rec,\%{$tgiddb{$tgidndx}},'tgid');
my $freqno = add_a_record($db,'freq',\%rec);
threads->yield;
if ($progstate ne $startstate) {last FAVLOOP;}
}### TGID records
}### Groups for trunked system
threads->yield;
if ($progstate ne $startstate) {last FAVLOOP;}
}#### Trunked system process
threads->yield;
if ($progstate ne $startstate) {last FAVLOOP;}
}### All systems
threads->yield;
if ($progstate ne $startstate) {last FAVLOOP;}
}### For all favorites
return ($parmref->{'rc'} = $GoodCode);
}
sub Get_SDS_Status {
my $parmref = shift @_;
my $out  = $parmref->{'out'};
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => "</ScannerInfo>",
'delay' => 200,
'resend' => 0,
'debug' => 0,
);
my $outstr = "GSI\r";
my $rc = radio_send(\%sendparms,$outstr);
if ($rc) {
LogIt(1,"Get_SDS_Status l6288:Radio_Send failed! RC=$rc");
return ($parmref->{'rc'} = $rc);
}
my $xml = Strip($sendparms{'rcv'});
my %infotypes = ();
my @rcds = split "\n",$xml;
foreach my $rcd (@rcds) {
if (!$rcd) {next;}
if (lc(substr($rcd,0,3)) eq 'gsi') {next;}
if (lc(substr($rcd,0,3)) eq '<?x') {next;}
$rcd = Strip($rcd);
if (substr($rcd,0,2) eq '</') {next;}
my $rectype = '';
my $rest = '';
($rectype,$rest) = $rcd =~ /^\<(.*?) (.*?)\>/; 
if (!$rectype) {
next;
}
$rectype = Strip(lc($rectype));
if (!$rectype) {next;}
my @fields = quotewords(" ",FALSE,$rest);
foreach my $fld (@fields) {
my ($key,$value) = split '=',$fld,2;
$key = Strip(lc($key));
if ($key eq '/') {next;}
if (!defined $value) {
LogIt(1,"No value for key $key rectype=$rectype");
next;
}
$value = Strip($value);
$infotypes{$rectype}{$key} = $value;
}
}
my $scan_state = '?';
if (defined $infotypes{'scannerinfo'}{'mode'}) {
$scan_state = $infotypes{'scannerinfo'}{'mode'};
}
$out->{'state'} = $scan_state;
if (!defined $infotypes{'property'}{'sig'}) {
LogIt(0,"$Bold RadioCtl  cannot process with radio in scan state=>$Yellow$scan_state");
foreach my $key ('meter','signal','dbmv','rssi') {
$out->{$key} = 0;
}
return ($parmref->{'rc'} = $CommErr);
}
$out->{'meter'} = $infotypes{'property'}{'sig'};
rssi_cvt($infotypes{'property'}{'rssi'},$out);
my $sql = $infotypes{'property'}{'mute'} =~ /unmute/i;
$out->{'sql'} = $sql;
if (!$sql) {$out->{'signal'} = 0;}
elsif (!$out->{'signal'}) {$out->{'signal'} = 1;}
$out->{'atten'} = FALSE;
if (lc($infotypes{'property'}{'att'}) eq 'on') {$out->{'atten'} = TRUE;}
$out->{'qkey'} = $infotypes{'department'}{'q_key'};
$out->{'groupname'} = $infotypes{'department'}{'name'};
$out->{'qkey'} = $infotypes{'system'}{'q_key'};
$out->{'system_name'} = $infotypes{'system'}{'name'};
if (defined $infotypes{'convfrequency'}{'freq'}) {
$out->{'mode'} = mode2rc($infotypes{'convfrequency'}{'mod'});
my ($freq)  = $infotypes{'convfrequency'}{'freq'} =~ /(.*)mhz/i;  
$out->{'frequency'} = freq_to_rc($freq);
$out->{'service'} = $infotypes{'convfrequency'}{'name'};
if (defined $infotypes{'department'}{'name'}) {
$out->{'service'} = "$infotypes{'department'}{'name'}:$out->{'service'}";
}
$out->{'tgid'} = '';
$out->{'sqtone'} = 'Off';
my $tone = $infotypes{'convfrequency'}{'sad'};
if ($tone =~ /none/i) {$out->{'sqtone'} = 'Off';}
elsif ($tone =~ /ctcss/i) {### CTCSS tone definition
$out->{'sqtone'} = 'CTC' . substr($tone,5);
}
else {
LogIt(0,"Get_SDS_Status l9569:Tone $tone needd process");
}
}### Conventional frequency information
if (defined $infotypes{'tgid'}{'tgid'}) {
($out->{'tgid'}) = $infotypes{'tgid'}{'tgid'} =~ /tgid\:(.*)/i;
$out->{'service'} = $infotypes{'tgid'}{'name'};
$out->{'frequency'} = 0;
if (defined $infotypes{'department'}{'name'}) {
$out->{'service'} = "$infotypes{'department'}{'name'}:$out->{'service'}";
}
}
if (defined $infotypes{'sitefrequency'}{'freq'}) {
my ($freq) = $infotypes{'sitefrequency'}{'freq'};
$out->{'site_frequency'} = freq_to_rc($freq);
}
if (defined $infotypes{'site'}{'name'}) {
$out->{'site_name'} = $infotypes{'site'}{'name'};
$out->{'mode'} = mode2rc($infotypes{'site'}{'mod'});
}
if (defined $infotypes{'srchfrequency'}{'freq'}) {
my ($freq) = $infotypes{'srchfrequency'}{'freq'} =~ /(.*)mhz/i; 
$out->{'frequency'} = freq_to_rc($freq);
}
$out->{'mode'} = mode2rc($infotypes{'srchfrequency'}{'mod'});
if ($out->{'frequency'}) {
$out->{'frequency'} =~ s/MHz//i;  
$out->{'frequency'} = freq_to_rc($out->{'frequency'});
}
if ($out->{'tone'}) {
$out->{'tone'} =~ s/Hz//i;   
}
return 0;
}### GET_SDS_STATUS
sub Get_XML {
my $rtype = Strip(shift @_);
my $index = shift @_;
my $db = shift @_;
my $parmref = shift @_;
my %sendparms = (
'portobj' => $parmref->{'portobj'},
'term' => "</GLT>",
'delay' => 200,
'resend' => 0,
'debug' => 0,
);
my $outstr = "GLT,$rtype,$index\r";
my $eot = FALSE;
my $page = 0;
PAGEPROC:
while (!$eot) {
my $rc = radio_send(\%sendparms,$outstr);
if ($rc) {
LogIt(1,"Get_XML l5998:Radio_Send failed! RC=$rc page=$page");
if ($page > 0) {
LogIt(0,"May have lost the EOT");
return $GoodCode;
}
else {return $rc;}
}
$outstr = '';
my $xml = Strip(substr($sendparms{'rcv'},11));
my @lines = split "\n",$xml;
LINEPROC:
foreach my $line (@lines) {
$line = Strip($line);
if (substr($line,0,2) eq '<?') {next;}
if ($line eq '<GLT>') {next;}
if ($line eq '</GLT>') {next;}
if (substr($line,0,7) eq '<Footer') {
my ($procline) = $line =~ /\<Footer (.*)\/\>/;
my @fields = quotewords(' ',FALSE,$procline);
foreach my $fld (@fields) {
my ($key,$value) = split '=',$fld;
$key = lc(Strip($key));
if ($key eq 'eot') {
$eot = $value;
last LINEPROC;
}
elsif ($key eq 'no') {
$page = $value;
}
}
}
my ($procline) = $line =~ /\<$rtype (.*) \/\>/;
my @fields = quotewords(' ',FALSE,$procline);
my %rec = ();
foreach my $fld (@fields) {
my ($key,$value) = split '=',$fld;
$key = lc(Strip($key));
$rec{$key} = $value;
}
my $index = $rec{'index'};
if (!defined $index) {
LogIt(1,"GET_XML l6331:No index defined for $line");
next LINEPROC;
}
$db->{$index} = {%rec};
}### process all the lines
}
return $GoodCode
}### GET_XML
sub XML_Proc {
my $rec = shift @_;
my $xml = shift @_;
my $type = shift @_;
foreach my $key (keys %{$xml}) {
my $value = $xml->{$key};
if ($key =~ /index/i) {next;}  
elsif ($key =~ /name/i) {$rec->{'service'} = Strip($value);}
elsif ($key =~ /avoid/i) {
if ($value =~ /avoid/i) {$rec->{'valid'} = FALSE;}
}
elsif ($key =~ /key/i) { 
my $qk = 'qkey';
if ($type =~ /group/i) {$qk = 'qkey';}
if ($value =~ /none/i) {$rec->{$qk} = 'Off';}
else {$rec->{$qk} = lc($value);}
}### Quickkey process
elsif ($key =~ /cfreqid/i) {
if (!$value) {
}
else {
LogIt(1,"Uniden l9730:$type $key=>$value not processed");
}
}
elsif ($key =~ /freq/i) {
if (!$value) {
LogIt(1,"Uniden 9738:$key was 0 or undefined!");
$value = 0;
}
else {$value=~ s/mhz//i;}   
$rec->{'frequency'} = freq_to_rc($value);
}### Frequency process
elsif ($key =~ /mod/i) {
if (!$value) {
LogIt(1,"Uniden 9749:Modulation was 0 or undefined!");
$value = 'FMn';
}
$rec->{'mode'} = mode2rc($value);
}### Modulation
elsif ($key =~ /sas/i) {
my $tone = 'Off';
my $adtype = 'Analog';
if ($value =~ /all/i) {
}
elsif ($value =~ /ctcss/i) {
($tone) = $value =~ /ctcss (.*?)hz/i;
$tone = "CTC$tone";
}
elsif ($value =~ /dcs/i) {
($tone) = $value =~ /dcs (.*)/i;
$tone = "DCS$tone";
}
else {LogIt(1,"Uniden l9974:No process for $type SAS=>$value");}
$rec->{'sqtone'} = $tone;
$rec->{'adtype'} = $adtype;
}### SAS process
elsif ($key =~ /sal/i) {
if ($value =~ /off/i) {
}
else {
LogIt(1,"Uniden l9782:$key=>$value not processed");
}
}### Sal
elsif ($key =~ /type/i) {
if ($value =~ /conv/i) {$rec->{'systemtype'} = 'cnv';}
elsif ($value =~ /edacs/i) {$rec->{'systemtype'} = 'edw';}
elsif ($value =~ /mototrbo/i) {$rec->{'systemtype'} = 'trbo';}
elsif ($value =~ /ltr/i) {$rec->{'systemtype'} = 'ltr';}
elsif ($value =~ /p25/i) {$rec->{'systemtype'} = 'p25s';}
elsif ($value =~ /motorola/i) {$rec->{'systemtype'} = 'mots';}
elsif ($value =~ /nxdn/i) {$rec->{'systemtype'} = 'nxdn';}
elsif ($value =~ /dmr/i) {$rec->{'systemtype'} = 'dmr';}
else {$rec->{'systemtype'} = "unknown:$value";}
}### System type
elsif ($key =~ /tag/i) {
if (looks_like_number($value)) {
$value = $value + 1;
if ($value > 100) {$value = 100;}
}
else {$value = 0;}
$rec->{'tag'} = $value;
}### 'n_tag'
elsif ($key =~ /cgroupid/i) {
if ($value) {
LogIt(1,"Uniden l9833:No process for $type key=>$key value=>$value");
}
}
elsif ($key =~ /sal/i) {
if ($value =~ /off/i) {
}
else {
LogIt(1,"Uniden l9845:No process for $type key=>$key value=>$value");
}
}### SAL
elsif ($key =~ /tgid/i) {
$rec->{'tgid'} = Strip($value);
}
elsif ($key =~ /tid/i) {
if ($value) {
LogIt(1,"Uniden l9857:No process for $type key=>$key value=>$value");
}
}
else {
}
}### All keys in this XML record
return 0;
}# XML_PROC
sub sds_alert {
my $rec = shift @_;
my $atone = 'Off';
my $alevel = 'Auto';
my $acolor = 'Off';
my $apattern = "";
if  ($rec->{'emgalt'} and looks_like_number($rec->{'emgalt'})) {
$atone = $rec->{'emgalt'};
if ($atone > 9) {$atone = 9;}
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
}### SDS_Alert
sub p25_set {
my $inrec = shift @_;
my $pwait = 400;
my $pmode = 'Auto';
my $plevel = '5';
my $pnac = 'Srch';
if ($inrec->{'p25wait'} and looks_like_number($inrec->{'p25wait'})) {
$pwait = $inrec->{'p25wait'} + 0;
if ($pwait > 1000) {$pwait = 1000;}
}
if ($inrec->{'p25lvl'} and looks_like_number($inrec->{'p25lvl'})) {
$plevel = $inrec->{'p25lvl'} + 0;
if ($plevel > 13) {$plevel = 13;}
elsif ($plevel < 5) {$plevel = 5;}
}
if ($inrec->{'dsql'}) {
if ($inrec->{'dsql'} =~ /[0-9a-f]/i) { 
$pnac = $inrec->{'dsql'};
}
}
return $pwait,$pmode,$plevel,$pnac;
}# P25_SET
sub dsql_to_rc {
my $dsql = shift @_;
if (!$dsql) {return 'Off';}
if ($dsql =~ /[[:xdigit:]]/i) {
my $dec = hex $dsql;
if ($dec < 4096) {return 'NAC' . Strip($dsql);}
elsif ($dec < 4112) {return 'CCD' . ($dec - 4112); }
else {return 'RAN' . ($dec - 4128);}
}
else {return 'Off';}
}
sub uniden_sdcard {
my $retcode = $GoodCode;
my ($db,$flist,$sd) = @_;
my $file = '';
my %f_list = ();
foreach my $rec (@{$flist}) {
chomp $rec;
my @fields = split "\t",$rec;
my $rectype = shift @fields;
if ($rectype !~ /^f\-list/i) {next;}  
my $filename = $fields[1];
if (!$filename) {
LogIt(1,"UNIDEN l10170:Bad filename in flist record =>$rec");
print Dumper($flist),"\n";exit;
next;
}
foreach my $key (@{$hpdrecs{'f-list'}}) {
if (scalar @fields) {
my $value = shift @fields;
$f_list{$filename}{$key} = $value;
}
else {last;}
}### Every field in the f-list
}
my $system_no = 0;
SYSRCLOOP:
foreach my $sysrec (@{$db->{'system'}}) {
my $sysno = $sysrec->{'index'};
if (!$sysno) {next;}
my $file_index = $sysrec->{'hpd'};
if (!defined $file_index) {$file_index = -1;}
if (!looks_like_number($file_index) or ($file_index < 0)) {
LogIt(1,"Uniden l10330:HPD key missing or <0! Changed to 0");
$file_index = 0;
}
$file = 'f_' . sprintf("%06.6i",$file_index) . '.hpd';
$system_no++;
push @{$sd->{$file}},"$header_l1";
push @{$sd->{$file}},"$header_l2";
my $frecs = $sd->{$file};
my $recno=$sysrec->{'recno'};
if (!$recno) {$recno = '?';}
my $systype =  lc($sysrec->{'systemtype'});
my $service = $sysrec->{'service'};
if (!$service) {$service = "System $system_no";}
$service =~ s/\=//g;  
$sysrec->{'service'} = $service;
my $qkey = $sysrec->{'qkey'};
if ((!looks_like_number($qkey)) or ($qkey < 0)) {
LogIt(1,"UNIDEN l10240:System $service ($file) recno=>$recno " .
"quickkey is not defined. System bypassed!");
next SYSRCLOOP;
}
my $rectype = 'Conventional';
if ($systype !~ /cnv/i) {$rectype = 'Trunk';}
$f_list{$file}{'name'} = $service;
$f_list{$file}{'filename'} = $file;
foreach my $fkey ('locctl','monitor','qkey','utag') {
$f_list{$file}{$fkey} = 'Off';
}
foreach my $no (0..9) {$f_list{$file}{"start$no"} = 'Off';}
foreach my $no (0..99) {$f_list{$file}{"qk_$no"} = 'Off';}
$f_list{$file}{'qkey'} = $qkey;
if ($sysrec->{'valid'}) {
$f_list{$file}{'monitor'} = 'On';
}
my $turnqk = $sysrec->{'turnqk'};
if ($turnqk) {
if (lc($turnqk) eq 'off')   {$f_list{$file}{'monitor'} = 'Off';}
elsif (lc($turnqk) eq 'on') {$f_list{$file}{'monitor'} = 'On';}
}
$f_list{$file}{"qk_$qkey"} = $f_list{$file}{'monitor'};
my $value = $sysrec->{'utag'};
if ((!looks_like_number($value)) or ($value < 0)) {$value = 'Off';}
$f_list{$file}{'utag'} = $value;
my $edacs_type = '';
if ($systype eq 'edn') {$edacs_type = 'Narrow';}
elsif ($systype eq 'edw') {$edacs_type = 'Wide';}
my $moto_type = '';
if ($systype eq 'mots')    {$moto_type = 'Standard';}
elsif ($systype eq 'motp') {$moto_type = 'Sprinter';}
elsif ($systype eq 'motc') {$moto_type = 'Custom';}
$sysrec->{'valid'} = TRUE;
$sysrec->{'tgid_fmt'} = 'NEXEDGE';
if ($sysrec->{'idas'}) {$sysrec->{'tgid_fmt'}= 'IDAS';}
push @{$frecs},rckey2hpd($rectype,$sysrec);
my $dqk_status = "DQKs_Status$tab";
my $no_rcds = push  @{$sd->{$file}},$dqk_status;
my $dqk_index = $no_rcds - 1;
my $custmap = '';
if (($systype =~ /motc/i) and
(looks_like_number($sysrec->{'fleetmap'})) and
($sysrec->{'fleetmap'} == 16) and
($sysrec->{'custmap'}) ) {
foreach my $char (split "",$sysrec->{'custmap'}) {
if (!$char) {next;}
$custmap = "$custmap\t$char";
}
push @{$frecs},"$custmap$f_eol";
}### Generating custom fleet map
my %deptqk = ();
my %dupdqk  = ();
my %dupdply = ();
my $group_type = 'C-Group';
my $freq_type = 'C-Freq';
if ($systype ne 'cnv') {
$group_type = 'T-Group';
$freq_type = 'TGID';
my $site_no = 0;
SITERCLOOP:
foreach my $siterec (@{$db->{'site'}}) {
my $siteno = $siterec->{'index'};
if (!$siteno) {next;}
if ($siterec->{'sysno'} != $sysno) {next;}
$site_no++;
my $site_name = $siterec->{'service'};
if (!$site_name) {
$site_name = "Site $site_no";
}
$site_name =~ s/\=//g;
$siterec->{'service'} = $site_name;
$site_name = "$Cyan$site_name$White ($Green$siteno$White)";
my $qkey = $siterec->{'qkey'};
my $dqkey = $siterec->{'dqkey'};
if (!defined $dqkey) {$dqkey = -1;}
if (looks_like_number($dqkey) and ($dqkey >= 0)) {
$qkey = $dqkey;
$siterec->{'qkey'} = $dqkey;
}
if ( (!looks_like_number($qkey)) or ($qkey < 0)) {
LogIt(1,"UNIDEN l10560:Cannot use site $site_name! " .
"No quickkey defined!");
next SITERCLOOP;
}
my $last_qkey = $deptqk{$qkey};
if ($siterec->{'valid'}) {$deptqk{$qkey} = 'On'}
else {$deptqk{$qkey} = 'Off';}
my $turnqk = $siterec->{'turndqk'};
if (!$turnqk) {$turnqk = $siterec->{'turnqk'};}
if ($turnqk) {
if (lc($turnqk) eq 'off')   {$deptqk{$qkey} = 'Off';}
elsif (lc($turnqk) eq 'on') {$deptqk{$qkey} = 'On';}
}### Override specified
my $msg = "SITE:$site_name";
if ($dupdqk{$qkey}[0]) {
$dupdply{$qkey} = TRUE;
if ($last_qkey ne $deptqk{$qkey}) {
$msg = "$msg Conflict with Quickkey ON/OFF detected!";
}
}
push @{$dupdqk{$qkey}},$msg;
$siterec->{'valid'} = TRUE;
$siterec->{'mottype'} = $moto_type;
$siterec->{'edacstype'} = $edacs_type;
$siterec->{'dsql'} = $sysrec->{'dsql'};
$siterec->{'loc_type'} = 'Circle';
$siterec->{'mode'} = 'Auto';
push @{$frecs},rckey2hpd('Site',$siterec);
if ($systype =~ /motc/i) {
foreach my $bplan (@{$db->{'bplan'}}) {
if (!$bplan->{'index'}) {next;}
if ($bplan->{'siteno'} != $siteno) {next;}
push @{$frecs},rckey2hpd('BandPlan_Mot',$bplan);
last;
}
}
my $freqcount = 0;
foreach my $frqrec (@{$db->{'tfreq'}}) {
if (!$frqrec->{'index'}) {next;}
if ($frqrec->{'siteno'} != $siteno) {next;}
if (!check_range($frqrec->{'frequency'},\%{$radio_limits{'SDS200'}})) {
LogIt(1,"UNIDEN l0711:Site Frequency$Yellow" .
rc_to_freq($frqrec->{'frequency'}) .
" MHz$White is out of range of the radio. Bypassed..");
}
my $ccran = 'Srch';
if (($systype =~ /dmr/i) or ($systype =~ /trb/i)) {
if (looks_like_number($frqrec->{'ccode'})) {
$ccran = $frqrec->{'ccode'};
}
}
elsif ($systype =~ /nxdn/i) {
if (looks_like_number($frqrec->{'ran'})) {
$ccran = $frqrec->{'ran'};
}
}
$frqrec->{'ccran'} = $ccran;
$frqrec->{'valid'} = TRUE;
push @{$frecs},rckey2hpd('T-Freq',$frqrec);
$freqcount++;
}### TFREQ records
if (!$freqcount) {
LogIt(1,"Uniden l11184:No TFREQ records found for site $site_name");
}
}### SITE Records
}### Trunked SYSTEM definition
my $group_no = 0;
foreach my $grouprec (@{$db->{'group'}}) {
my $groupno = $grouprec->{'index'};
if (!$groupno) {next;}
if ($grouprec->{'sysno'} != $sysno) {next;}
$group_no++;
my $service = $grouprec->{'service'};
if (!$service) {$service = 'Group $group_no';}
$service =~ s/\=//g;   
$grouprec->{'service'} = $service;
my $group_name = "$Cyan$service$White ($Green$groupno$White)";
my $qkey = $grouprec->{'qkey'};
my $dqkey = $grouprec->{'dqkey'};
if (!defined $dqkey) {$dqkey = -1;}
if (looks_like_number($dqkey) and ($dqkey >= 0)) {
$qkey = $dqkey;
$grouprec->{'qkey'} = $dqkey;
}
if ( (!looks_like_number($qkey)) or ($qkey < 0)) {
LogIt(1,"Uniden l10535: No quickkey assigned for group " .
"$group_name\n" .
"    Group will not be able to be selected!");
}
else {
my $last_qkey = $deptqk{$qkey};
if ($grouprec->{'valid'}) {$deptqk{$qkey} = 'On';}
else {$deptqk{$qkey} = 'Off';}
my $turnqk = $grouprec->{'turndqk'};
if (!$turnqk) {$turnqk = $grouprec->{'turnqk'};}
if ($turnqk) {
if (lc($turnqk) eq 'off')   {$deptqk{$qkey} = 'Off';}
elsif (lc($turnqk) eq 'on') {$deptqk{$qkey} = 'On';}
}### Override specified
my $msg = "GROUP:$group_name";
if ($dupdqk{$qkey}[0]) {
$dupdply{$qkey} = TRUE;
if ($last_qkey ne $deptqk{$qkey}) {
$msg = "$msg Conflict with Quickkey ON/OFF detected!";
}
}
push @{$dupdqk{$qkey}},$msg;
}
$grouprec->{'valid'} = TRUE;
$grouprec->{'loc_type'} = 'Circle';
push @{$frecs},rckey2hpd($group_type,$grouprec);
FREQCLOOP:
foreach my $freqrec (@{$db->{'freq'}}) {
my $freqno = $freqrec->{'index'};
if (!$freqno) {next;}
if ($freqrec->{'groupno'} != $groupno) {next;}
my $service = $freqrec->{'service'};
if (!$service) {$service = '(unknown)';}
$service =~ s/\=//g;   
$freqrec->{'service'} = $service;
my $frequency = $freqrec->{'frequency'};
if ((!$frequency) and ($systype eq 'cnv')) {
next FREQCLOOP;
}
if ($frequency and (!check_range($frequency,\%{$radio_limits{'SDS200'}}))) {
LogIt(1,"SETMEM l10864:Frequency$Yellow" . rc_to_freq($frequency) .
" MHz$White is out of range of the radio. Bypassed..");
next FREQCLOOP;
}
if (!$freqrec->{'tgid'}) {$freqrec->{'tgid'} = '?';}
my $svcode = $freqrec->{'svcode'};
my $grpsvcode = $grouprec->{'svcode'};
if (!looks_like_number($svcode) or ($svcode < 1)) {
if (looks_like_number($grpsvcode) and ($grpsvcode > 0)) {
$freqrec->{'svcode'} = $grpsvcode;
}
}
push @{$frecs},rckey2hpd($freq_type,$freqrec);
}### For every FREQ record
}### For every GROUP record
my @dup_key_list = sort Numerically keys %dupdply;
if (scalar @dup_key_list) {
LogIt(1,"##  Duplicate SITE/DEPT quickkey assignments found ###");
foreach my $qk (@dup_key_list) {
print "Site/Dept QuickKey:$Bold$Green$qk$White:$Eol";
foreach my $string (@{$dupdqk{$qk}}) {
print "$Bold    $string$Eol";
}
}
}
$dqk_status = "DQKs_Status$tab";
foreach my $ndx (0..99) {
my $value = 'Off';
if ($deptqk{$ndx}) {$value = $deptqk{$ndx};}
$dqk_status = "$dqk_status$tab$value";
}
$frecs->[$dqk_index] = "$dqk_status$f_eol";
}### For every SYSTEM record
@{$flist} = ();
push @{$flist},"TargetModel\tBCDx36HP$f_eol";
push @{$flist},"FormatVersion\t1.00$f_eol";
foreach my $fn (sort keys %f_list) {
my $rec = 'F-List';
foreach my $key (@{$hpdrecs{'f-list'}}) {
my $value = $f_list{$fn}{$key};
$rec = "$rec\t$value";
}
push @{$flist},"$rec$f_eol";
}
return $retcode;
}### UNIDEN_SDCARD
sub rckey2hpd {
my ($hpdrc,$rcrcd) =  @_;
my @fields = @{$hpdrecs{lc($hpdrc)}};
if (!scalar @fields) {
LogIt(1,"UNIDEN l10893:Need to define record for $hpdrc!");
return '';
}
my $outrec = $hpdrc;
foreach my $key (@fields) {
my $value = $rcrcd->{$key};
if (!defined $value) {$value = '';}
if ($key eq 'avoid') {
$value = 'Off';
if (!$rcrcd->{'valid'}) {$value = 'On';}
}
elsif ($key eq 'systemtype') {
$value = $sds_systypes{$value};
}
elsif (($key eq 'qkey') or ($key eq 'utag')) {
if (!looks_like_number($value) or ($value < 0)) {
$value = 'Off';
}
}
elsif (($key =~ /agc/i) or
($key eq 'priority') or
($key eq 'id_search') or
($key eq 'atten') ) {
if ($value) {$value = 'On';}
else {$value = 'Off';}
}
elsif ($key eq 'p25lvl') {
if (!$value) {$value = 0;}
elsif (!looks_like_number($value)) {$value = 5;}
elsif ($value < 5) {$value = 5;}
elsif ($value > 13) {$value = 13;}
}
elsif ($key eq 'dsql') {
if (($value eq '') or (lc(substr($value,0,1)) eq 's')) {
$value = 'Srch';
}
}
elsif ($key eq 'p25wait') {
if (!$value) {$value = 400;}
if (!looks_like_number($value)) {$value = 400;}
}
elsif ($key eq 'emgalt') {
if (!$value) {$value = 'Off';}
}
elsif ($key eq 'emglvl') {
if (!$value) {$value = 'Auto';}
}
elsif ($key eq 'emgpat') {
if (looks_like_number($value)) {
if ($value == 2) {$value = 'Fast Blink';}
elsif ($value == 1) {$value = 'Slow Blink';}
else {$value = 'On';}
}
else {$value = 'On';}
}
elsif ($key eq 'emgcol') {
$value = 'Off';
if ($rcrcd->{'emgalt'}) {$value = 'Red';}
}
elsif ($key eq 's_bit') {
if ($value) {$value = 'Yes';}
else {$value = 'Ignore';}
}
elsif ($key eq 'endcode') {
if (!$value) {$value = 'Ignore';}
elsif ($value =~ /^a*/i) {$value = 'Analog';}
elsif ($value =~ /^b*/i) {$value = 'Analog+Digital';}
else {$value = 'Ignore';}
}
elsif ($key eq 'mode') {
$value = rc2mode($value);
}
elsif ($key eq 'dlyrsm') {
if (!$value) {$value = 0;}
if ($value < -8) {$value = -10;}
elsif ($value < 0) {$value = -5;}
elsif ($value < 6) { }
elsif ($value < 20) {$value = 10;}
else {$value = 30;}
}
elsif ($key eq 'adtype') {
if (!$value) {$value = 'ALL';}
if ($value =~ /analog/i) {$value = 'ANALOG';}
elsif ($value =~ /all/i) {$value = 'ALL';}
else {$value = 'DIGITAL';}
}
elsif ($key eq 'squelch') {
my $tone = $rcrcd->{'sqtone'};
$value = 'Srch';
if ($tone) {
my $num = substr($tone,3);
if ($tone =~ /ctc/i) {$value = "C$num";}
elsif ($tone =~ /dcs/i) {$value = "D$num";}
elsif ($tone =~ /nac/i) {$value = "NAC=$num";}
elsif ($tone =~ /ccode/i) {$value = "Color Code $num";}
elsif ($tone =~ /ran/i) {$value = "RAN=$num";}
else {
}
}### Tone is NOT off
}### Squelch key
elsif ($key eq 'svcode') {
if (looks_like_number($value) and ($value > 0)) {
if (($value > 37) and ($value < 208)) {$value = 208;}
}
else {
$value = 1;
my $service = $rcrcd->{'service'};
if ($service) {
if ($service =~ /fire/i) {$value = 3;}
elsif ($service =~ /pd/i) {$value = 2;}
elsif ($service =~ /police/i) {$value = 2;}
elsif ($service =~ /ems/i) {$value = 4;}
elsif ($service =~ /busi/i) {$value = 17;}
elsif ($service =~ /rail/i) {$value = 20;}
elsif ($service =~ /rr/i) {$value = 20;}
elsif ($service =~ /air/i) {$value = 15;}
}
}### Was not a number
}
elsif ($key eq 'tslot') {
if (!looks_like_number($value) or ($value < 1)) {$value = 'Any';}
}
elsif ($key eq 'p25mode') { $value = 'Auto';}
elsif ($key eq 'id_search') {
if ($value) {$value = 'On';}
else {$value = 'Off';}
}
elsif ($key eq 'lat') {
if (!$value) {$value = '0.000000';}
}
elsif ($key eq 'lon') {
if (!$value) {$value = '-0.000000';}
}
elsif ($key eq 'radius') {
if (!$value) {$value = 50;}
}
elsif ($key eq 'filter') {
if (!$value) {$value = 'Off';}
if ($filter2sds{$value}) {$value = $filter2sds{$value}}
}
elsif ($key eq 'hld') {
if (!looks_like_number($value)) {$value = 0;}
}
$outrec = "$outrec\t$value";
}
return "$outrec$f_eol";
}# RCKEY2HPD
sub uniden_read_sd {
my $db = shift @_;
my $raw = shift @_;
my $opts = shift @_;
my @inrecs = @{$raw};
my @systems = ();
my $maxrec = $#inrecs;
foreach my $ndx (0..$maxrec) {
my $rec = $inrecs[$ndx];
if (($rec =~ /^conventional/i) or ($rec =~ /^trunk/i)) {
push @systems,$ndx;
}
}
LogIt(0,"Uniden l11053:Located ",scalar @systems," systems to process");
my $maxsystem = $#systems;
SYSLOOP:
foreach my $ndx (0..$maxsystem) {
my $currecno = $systems[$ndx];
my $nextsysrec = $maxrec + 1 ;
if ($ndx != $maxsystem) {$nextsysrec = $systems[$ndx+1];}
my $first_site = TRUE;
my $sysno = 0;
my $siteno = 0;
my $groupno = 0;
my $systype = 'cnv';
RECLOOP:
while ($currecno < $nextsysrec) {
my $record = $inrecs[$currecno];
$currecno++;
chomp $record;
if (substr($record,0,1) eq '#') {next;}
my @fields = split "\t",$record;
my $rectype = lc(shift @fields);
my %rec = ('valid' => TRUE);
if (defined $hpdrecs{$rectype}) {
foreach my $key (@{$hpdrecs{$rectype}}) {
if (scalar @fields) {
my $value = shift @fields;
$rec{$key} = $value;
}
else {last;}
}
}
else {
LogIt(1,"UNIDEN l11105:Need hpdrecs for $rectype");
}
if ($rec{'avoid'} and ($rec{'avoid'} =~ /on/i)) {$rec{'valid'} = FALSE;}
if ($rec{'mode'}) {
$rec{'mode'} = mode2rc($rec{'mode'});
}
if (($rectype =~ /trunk/i) or ($rectype =~ /conv/i)) {
if ($rectype =~/conv/i) {$systype = 'cnv';}
else {$systype = $sds2rctype{lc($rec{'systemtype'})}; }
if (!$systype) {
LogIt(1,"UNIDEN l11064Failed to find system type for $rec{'systemtype'}\n" .
"    Changed to 'cnv'");
$systype = 'cnv';
}
if ($opts->{'notrunk'} and ($systype ne 'cnv')) {
LogIt(0,"Uniden L11140:$Bold Bypassing trunked system $rec{'service'} due to --NOTRUNK option");
next SYSLOOP;
}
if ($opts->{'lat'} or $opts->{'lon'}) {
if ($systype eq 'cnv') {
my $group_count = 0;
foreach my $rcndx (($currecno + 1)..($nextsysrec - 1)) {
if ($inrecs[$rcndx] =~ /^..group*/i) {  
my $ok  = gps_proc(\$inrecs[$rcndx],$opts);
if ($ok) {$group_count++;}
}
elsif ($inrecs[$rcndx] =~ /^..freq*/i) {last;}
}### All records in this system
if (!$group_count) {
LogIt(0,"Uniden L11166:$Bold Bypassing system $rec{'service'} " .
" due to no groups within GPS range");
next SYSLOOP;
}
}### Conventional proc
else {
my $site_count = 0;
foreach my $rcndx (($currecno + 1)..($nextsysrec - 1)) {
if ($inrecs[$rcndx] =~ /^site*/i) {  
my $ok  = gps_proc(\$inrecs[$rcndx],$opts);
if ($ok) {$site_count++;}
else {
foreach my $t (($rcndx + 1) .. ($nextsysrec-1)) {
if ($inrecs[$t] =~ /^t\-freq*/i) {
$inrecs[$t] = '#' . $inrecs[$t];
}
else {last;}
}
}
}
elsif ($inrecs[$rcndx] =~ /^site*/i) {last;}
}### All records in this system
if (!$site_count) {
LogIt(0,"Uniden L11198:$Bold Bypassing system $rec{'service'} " .
"due to no sites within GPS range");
next SYSLOOP;
}
}### Trunked proc
}### Lat/Lon specified
$rec{'systemtype'} = $systype;
my $value = $rec{'endcode'};
if (!$value) {$rec{'endcode'} = '';}
elsif ($value =~ /dig/i) {$rec{'endcode'} = 'b';}
elsif ($value =~ /ana/i) {$rec{'endcode'} = 'a';}
else {$rec{'endcode'} = '';}
$sysno = add_a_record($db,'system',\%rec);
}
elsif ($rectype =~ /site/i) {
if ($first_site) {
if ($systype =~ /mot/i) {
if ($rec{'mottype'} =~ /cus/i) {
$db->{'system'}[$sysno]{'systemtype'} = 'motoc';
$systype = 'motoc';
}
elsif ($rec{'mottype'} =~ /spr/i) {
$db->{'system'}[$sysno]{'systemtype'} = 'motop';
$systype = 'motop';
}
}
elsif ($systype =~ /edw/i) {
if ($rec{'edacstype'} =~ /nar/i) {
$db->{'system'}[$sysno]{'systemtype'} = 'edn';
$systype = 'edn';
}
}
$first_site = FALSE;
}### First site process
$rec{'sysno'} = $sysno;
$siteno = add_a_record($db,'site',\%rec);
}
elsif ($rectype =~ /t\-freq/i) {
my $value = $rec{'ccran'};
$rec{'ran'} = 's';
$rec{'ccode'} = 's';
if ($value and looks_like_number($value)) {
if ($systype =~ /nxdn/i) {$rec{'ran'} = $value;}
elsif ( ($systype =~ /dmr/i) or ($systype =~ /trbo/i) ) {
$rec{'ccode'} = $value;
}
}
$rec{'siteno'} = $siteno;
my $s_freqno = add_a_record($db,'tfreq',\%rec);
}
elsif ($rectype =~ /bandplan_mot/i) {
if ($systype ne 'motc') {next;}
if ($db->{'bplan'}[1]{'index'}) {
LogIt(1,"UNIDEN l11149:More than one bandplan for system $sysno");
}
$rec{'siteno'} = $siteno;
my $bplan = add_a_record($db,'bplan',\%rec);
}
elsif ($rectype =~ /fleetmap/i) {
my $custmap = '';
foreach my $n (0..7) {
$custmap = $custmap . $rec{"b$n"};
}
$db->{'system'}[$sysno]{'custmap'} = $custmap;
$db->{'system'}[$sysno]{'fleetmap'} = 16;
}
elsif ($rectype =~ /group/i) {
$rec{'sysno'} = $sysno;
$groupno =  add_a_record($db,'group',\%rec);
}### Group process
elsif ($rectype =~ /tgid/i) {
$rec{'groupno'} = $groupno;
my $freqno =  add_a_record($db,'freq',\%rec);
}
elsif ($rectype =~ /c\-freq/i) {
if ($rec{'squelch'}) {
$rec{'sqtone'} = 'Off';
my ($key,$value) = split '=',$rec{'squelch'};
if ($key =~ /tone/i) {
my $char = lc(substr($value,0,1));
my $tone = substr($value,1);
if ($tone and looks_like_number($tone)) {
$tone = Strip($tone);
if ($char eq 'c') {$rec{'sqtone'} = "CTC$tone";}
elsif ($char eq 'd') {$rec{'sqtone'} = "DCS$tone";}
else {
LogIt(1,"UNIDEN l11614:Cannot deal with tone value $rec{'squelch'}");
}
}
}### CTCSS/DCS
elsif ($key =~ /nac/i) { 
if ($value !~ /s/i) {$rec{'sqtone'} = "NAC$value";}
}
elsif ($key =~ /color/i) { 
if ($value !~ /s/i) {$rec{'sqtone'} = "CCD$value";}
}
elsif ($key =~ /ran/i) {
if ($value !~ /s/i) {$rec{'sqtone'} = "RAN$value";}
}
else  {
}
}### Tone processing
$rec{'groupno'} = $groupno;
my $freqno =  add_a_record($db,'freq',\%rec);
}
elsif ($rectype =~ /area/i) {next;}
else {
LogIt(1,"UNIDEN L11421:No process for =>$rectype<=");
}
}
}### All systems in this file
return $GoodCode;
}
sub gps_proc {
my $rec = shift @_;
my $gps_opts = shift @_;
my @fields = split "\t",$$rec;
my $rctype = shift @fields;
my $ok = TRUE;
foreach my $key (@{$hpdrecs{lc($rctype)}}) {
my $value = shift @fields;
if (!$value) {$value = 0;}
if ($key eq 'lat') {
if ($gps_opts->{'lat'}) {
my $delta = abs($gps_opts->{'lat'} - $value) / .01923;
if ($delta > $gps_opts->{'radius'}) {
$$rec = '#' . $$rec;
$ok = FALSE;
}
}
}### key is $lat
if ($key eq 'lon') {
if ($gps_opts->{'lon'}) {
my $delta = abs($gps_opts->{'lon'} - $value) / .0166;
if ($delta > $gps_opts->{'radius'}) {
$$rec = '#' . $$rec;
$ok = FALSE;
}
}
}### key is $lat
}### Lat/Lon key location
return $ok;
}
sub Numerically {
use Scalar::Util qw(looks_like_number);
if (looks_like_number($a) and looks_like_number($b)) { $a <=> $b;}
else {$a cmp $b;}
}
