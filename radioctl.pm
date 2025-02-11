#!/usr/bin/perl -w
package radioctl;
require Exporter;
use constant FALSE => 0;
use constant TRUE => 1;
@ISA   = qw(Exporter);
@EXPORT = qw(
CR
%clear equate %valid_protocols spec_read
MAXSIGNAL radio_send %radio_routine %mutual_exclusive
rc_to_freq freq_to_rc KeyVerify
$Red $Bold $Green $Blue $Magenta $Yellow $White $Reset $Eol
%scan_request %gui_request $scanner_thread
SQUELCH_MAX MAXCHAN MAXINDEX MAXFREQ MINFREQ %xrefs
@db_channel_max $progstate %vfo %version1
%radio_def %systypes %modelookup
%usleep %rc_hash @modestring @bandwidthstring @system_type
@database $Debug1 $Debug2 $Debug3
%db_kwd cvt_signal %models %settings
write_radioctl write_radioctl2 read_radioctl read_def %struct_fields
write_format read_line
@dblist %structure %struct_format %binary
%chan_active $initial_local %dummy_record add_a_record
%version2 %ifexchange %freq_lock %syskey AutoMode
%dbcounts %control add_message @messages $initmessage
%extra_char %valid_ctc %valid_dcs $header2
@selected $response_pending $record_file $start_recording
$GoodCode $CommErr $ParmErr $NotForModel $EmptyChan $OtherErr $FileErr
LogRad %OneOnly %All_Radios $defaultradio
%system_type_valid %baudrates %color_xlate @xlate_color
$Red $Bold $Green $Blue $Magenta $Cyan $Yellow $White $Reset $Eol $Rev $Blink
%OptDescript %Options $Debug @Warning_Log @Error_Log @Info_Log
%known_locations
TrueFalse LogIt Strip Time_format Lat_Lon_Parse Parms_Parse Time_Format ConfigFileProc BenchMark
write_log str_cmpr $fdigits $fdecimal check_range
@gui_modestring @gui_bandwidth @gui_adtype @gui_tonestring @gui_attstring %audio_types
@rc_modes %rc_modes %tn_type @attstring @ctctone @dcstone @alltones Tone_Xtract
DebugIt $Logfile_Name DirExist
);
use threads;
use threads::shared;
use Scalar::Util qw(looks_like_number);
use constant CR    =>  pack("H2","0D");
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );
use File::Path qw(make_path);
use File::Basename;
use Data::Dumper;
use Text::CSV;
use autovivification;
no  autovivification;
use Scalar::Util qw(looks_like_number);
use strict;
our  $Rev = '0.4.118';# xx/xx/24
use constant MAXCHAN         => 9999;
use constant MAXINDEX        => 99999;
use constant MAXFREQ         => 9999999999;
use constant SQUELCH_MAX     => 15;
use constant MINFREQ         => 30;
use constant MAXSIGNAL       => 9;
our $Red = "\e[31m";
our $Bold = "\e[1m";
our $Green = "\e[32m";
our $Blue = "\e[34m";
our $Magenta = "\e[35m";
our $Yellow = "\e[33m";
our $Cyan   =  "\e[36m";
our $White  = "\e[37m";
our $Blink  = "\e[5m";
our $Reset =  "\e[0m";
our $Eol = "$Reset\n";
our $LineFeed = pack("H2","0A");
our @Warning_Log = ();
our @Error_Log = ();
our @Info_Log = ();
our $Debug = 0;
our %Options = (
'b|debug' => \$Debug,
'h|help' => \&Help_Me,
);
our %OptDescript = (
'b|debug' => 'Turn On Debugging Stuff',
'h|help'  => 'Display Help',
);
our $fdigits = 11;
our $fdecimal = 6;
our $Debug1 = FALSE;
our $Debug2 = FALSE;
our $Debug3 = FALSE;
our $homedir = '';
if (substr($^O,0,3) eq 'MSW') {
$homedir = $ENV{"USERPROFILE"};
LogIt(1,"This program will most likely NOT work correctly on Windows");
}
else {
$homedir = $ENV{"HOME"};
}
our $Logfile_Name = 'radioctl_log.csv';
our %usleep = (
'TIMEPOP' => 5,
'MANUAL' => 500,
'SCAN'   => 1000,
'SEARCH' => 10,
'SIGNAL' => 200,
);
our %rc_hash = ();
our @rc_modes = ('FM','WF','AM','LS','US','RT','RR','CW','CR');
our %rc_modes = ('FM' => 'FM',
'WF' => 'WFM',
'AM' => 'AM',
'LS' => 'LSB',
'US' => 'USB',
'RT' => 'RTTY',
'RR' => 'RTTY-R',
'CW' => 'CW',
'CR' => 'CW-R',
);
our @modestring  = ('WF');
foreach my $mode (@rc_modes) {
foreach my $bw ('','n','m','w') {
my $string = uc($mode) . $bw;
push @modestring,sprintf("%-7.7s",$string);
}
if ($mode =~ /fm/i) {push @modestring,sprintf("%-7.7s","FMu");}
}
our %audio_types = (
'AN' => 'Analog',
'P2' => 'P25',
'DM' => 'DMR',
'NX' => 'NXDN',
'VN' => 'VN-NXDN',
'DS' => 'DSTAR',
);
our @alltones = ('Off');
our @ctctone = ('Off');
our %valid_rpt = (
'Off' => TRUE,
);
foreach my $tone  (
" 67.0"," 69.3"," 71.9"," 74.4"," 77.0",
" 79.7"," 82.5"," 85.4"," 88.5"," 91.5",
" 94.8"," 97.4","100.0","103.5","107.2",
"110.9","114.8","118.8","123.0","127.3",
"131.8","136.5","141.3","146.2","151.4",
"156.7","159.8","162.2","165.5","167.9",
"171.3","173.8","177.3","179.9","183.5",
"186.2","189.9","192.8","196.6","199.5",
"203.5","206.5","210.7","218.1","225.7",
"229.1","233.6","241.8","250.3","254.1",
) {
my $tn = Strip($tone);
push @alltones,$tn;
push @ctctone,"CTC$tn";
$valid_rpt{"RPT$tn"} = TRUE;
}
our %valid_ctc = ();
foreach my $ndx (0..$#ctctone) {
$valid_ctc{Strip($ctctone[$ndx])} = $ndx;
}
our @dcstone = ('Off');
foreach my $tone  (
'023','025','026','031','032','036','043','047','051','053',
'054','065','071','072','073','074','114','115','116','122',
'125','131','132','134','143','145','152','155','156','162',
'165','172','174','205','212','223','225','226','243','244',
'245','246','251','252','255','261','263','265','266','271',
'274','306','311','315','325','331','332','343','346','351',
'356','364','365','371','411','412','413','423','431','432',
'445','446','452','454','455','462','464','465','466','503',
'506','516','523','526','532','546','565','606','612','624',
'627','631','632','654','662','664','703','712','723','731',
'732','734','743','754','006','007','015','017','021','050',
'141','214',
) {
push @alltones,Strip($tone);
push @dcstone,"DCS$tone";
}
our %valid_dcs = ();
foreach my $ndx (0..$#dcstone) {
$valid_dcs{$dcstone[$ndx]} = $ndx;
}
our @attstring = ("Off","Attenuation","Preamp");
our @bandwidthstring = ("(None)","Wide","Medium","Narrow","Ultra-Narrow");
our %tn_type = (
'ctc' => 1,'dcs'=> 1,'rpt'=>1, 'ccd'=>1,'ran'=>1,'nac'=>1,'dsq'=>1,'off'=>1
);
our %color_xlate = ('off' => 0, 'red' => 1, 'blue' => 2,
'green' => 3, 'cyan' => 4, 'yellow' => 5, 'white' => 6);
our @xlate_color = ();
foreach my $key (keys %color_xlate) {$xlate_color[$color_xlate{$key}] = $key;}
our $defaultradio = 'Local';
our %All_Radios = (lc($defaultradio) => {
model      => '',
radioaddr  => 0,
protocol   => 'local',
baudrate   => 9600,
handshake  => "none",
port       => "none",
portset    => FALSE,
origin     => 0,
maxchan    => MAXCHAN,
maxfreq    => MAXFREQ,
minfreq    => MINFREQ,
radioscan  => 0,
signal     => 2,
active     => FALSE,
group      => FALSE,
name => ucfirst($defaultradio),
sdir => "$homedir/radioctl",
},
);
our %known_locations = (
'home' => {'lat' => 41.605425, 'lon' => -73.971687},
);
our %flagchar = (
'atten'        => 'a',
'i_call'       => 'c',
'idas'         => 'd',
'afs'          => 'f',
'tgid_valid'   => 'g',
'agc_digital'  => 'h',
'id_search'    => 'i',
'agc_analog'   => 'j',
'skip'         => 'k',
'preamp'       => 'm',
'c_ch'         => 'o',
'priority'     => 'p',
's_bit'        => 't',
'vsc'          => 'v',
'moto_id'      => 'x',
);
our %extra_char = (
'emgalt'  => {'system' => TRUE,'freq'  => TRUE,'min' => 1},
'emglvl'  => {'system' => TRUE,'freq'  => TRUE,'min' => 1},
'emgpat'  => {'system' => TRUE,'freq'  => TRUE,'min' => 1},
'hpd'     => {'system' => TRUE,'min' => 0},
'p25wait' => {'system' => TRUE},
'p25lvl'  => {'system' => TRUE},
'endcode' => {'system' => TRUE},
'fleetmap'=> {'system' => TRUE},
'custmap' => {'system' => TRUE},
'turnqk'  => {'system' => TRUE,'site'  => TRUE,'group' => TRUE},
'utag'    => {'system' => TRUE,'min' => 0},
'turndqk' => {'site'   => TRUE,'group' => TRUE},
'filter'  => {'site'   => TRUE,'group' => TRUE},
'dqkey'   => {'site'   => TRUE,'group' => TRUE,'min' => 0},
'enc'     => {'freq'   => TRUE},
'lat'     => {'freq'   => TRUE},
'lon'     => {'freq'   => TRUE},
'rfgain'  => {'freq'   => TRUE},
'scangrp' => {'freq'   => TRUE,'group' => TRUE},
'scan705' => {'freq'   => TRUE,'group' => TRUE},
'scan8600' => {'freq'   => TRUE,'group' => TRUE},
'svcode'  => {'freq'   => TRUE,'group' => TRUE},
'tslot'   => {'freq'   => TRUE},
'voloff'  => {'freq'   => TRUE},
'spltone' => {'freq'   => TRUE},
'splfreq' => {'freq'   => TRUE},
);
our %baudrates = (
'9600'   => -1,
'19200'  => -1,
'38400'  => -1,
'57600'  => -1,
'115200' => -1,
);
our %handshake = ('none' => TRUE, 'rts' => TRUE);
our @system_type = (
'cnv',
'ltr',
'eds',
'edw',
'edn',
'mots',
'motp',
'motc',
'trbo',
'p25s',
'p25f',
'p25x',
'dmr',
'nxdn',
'nxdns',
);
our %system_type_valid = ();
foreach my $st (@system_type) {$system_type_valid{$st} = TRUE;}
our @dblist = ('system','site','bplan','tfreq','group','freq','search','lookup',
'powermsg','light','beep','ifxchng','lockfreq');
our %OneOnly = ('powermsg' => TRUE, 'beep' => TRUE, 'light' => TRUE);
our %version1 = (
system => ['index',
'service',
'valid',
'systemtype',
'flags',
'dlyrsm',
'qkey',
'hld',
'dsql',
'_extra',
],
site   => ['index',
'service',
'valid',
'sysno',
'qkey',
'hld',
'flags',
'mode',
'lat',
'lon',
'radius',
'site_number',
'_extra',
],
bplan => ['index',
'siteno',
'flags',
'frequency_l1',
'frequency_u1',
'spacing_1',
'offset_1',
'frequency_l2',
'frequency_u2',
'spacing_2',
'offset_2',
'offset_2',
'frequency_l3',
'frequency_u3',
'spacing_3',
'offset_3',
'frequency_l4',
'frequency_u4',
'spacing_4',
'offset_4',
'frequency_l5',
'frequency_u5',
'spacing_5',
'offset_5',
'frequency_l6',
'frequency_u6',
'spacing_6',
'offset_6',
],
tfreq =>  ['index',
'valid',
'siteno',
'frequency',
'lcn',
'mode',
'ccode',
'ran',
'utag',
'flags',
'_extra',
],
group  => ['index',
'service',
'valid',
'sysno',
'flags',
'qkey',
'lat',
'lon',
'radius',
'_extra',
],
freq   => ['index',
'service',
'valid',
'groupno',
'flags',
'channel',
'frequency',
'mode',
'sqtone',
'dlyrsm',
'tgid',
'adtype',
'_extra',
],
'log' => ['index',
'count',
'signal',
'duration',
'timestamp',
],
search => ['index',
'service',
'valid',
'channel',
'start_freq',
'end_freq',
'step',
'mode',
'flags',
'qkey',
'_extra',
'dlyrsm',
'hld',
'utag',
],
toneout => [
'index',
'service',
'channel',
'frequency',
'mode',
'toneout_a',
'toneout_b',
'flags',
'dlyrsm',
'emgalt',
'emglvl',
'emgpat',
'emgcol',
],
lookup => [
'frequency',
'service',
],
powermsg => ['msg1',
'msg2',
'msg3',
'msg4',
],
light    => ['event',
'bright',
],
beep     => ['volume',
],
ifxchng => ['frequency',
],
lockfreq => ['infile',
'ingrpno',### Input group number to select
],
);
our %structure = (
system => ['index',
'valid',
'systemtype',
'service',
'_guiend',
'atten',
'agc_digital',
'agc_analog' ,
'skip',
'dlyrsm',
'qkey',
'hld',
'mode',
'p25lvl',
'p25wait',
'i_call',
'afs',
'c_ch',
'priority',
's_bit',
'moto_id',
'id_search',
'idas',
'dsql',
'endcode',
'fleetmap',
'custmap',
'emgalt',
'emglvl',
'emgpat',
'utag',
'hpd',
'_raw',
'block_addr',
'turnqk',
],
site => ['index',
'valid',
'sysno',
'qkey',
'service',
'hld',
'mode',
'filter',
'site_number',
'lat',
'lon',
'radius',
'atten',
'c_ch',
'dqkey',
'turnqk',
'turndqk',
'block_addr',
'_raw',
],
tfreq =>  ['index',
'valid',
'siteno',
'frequency',
'lcn',
'mode',
'ccode',
'utag',
'ran',
'block_addr',
'_raw',
],
bplan => ['index',
'siteno',
'flags',
'frequency_l1',
'frequency_u1',
'spacing_1',
'offset_2',
'frequency_l2',
'frequency_u2',
'spacing_2',
'offset_2',
'offset_2',
'frequency_l3',
'frequency_u3',
'spacing_3',
'offset_3',
'frequency_l4',
'frequency_u4',
'spacing_4',
'offset_4',
'frequency_l5',
'frequency_u5',
'spacing_5',
'offset_5',
'frequency_l6',
'frequency_u6',
'spacing_6',
'offset_6',
'_raw',
],
group  => [
'index',
'valid',
'sysno',
'systemname',
'service',
'_guiend',
'filter',
'qkey',
'lat',
'lon',
'radius',
'_raw',
'scangrp',
'scan705',
'scan8600',
'dqkey',
'turnqk',
'turndqk',
],
freq   => [
'index',
'valid',
'channel',
'frequency',
'mode',
'sqtone',
'dlyrsm',
'att_amp',
'service',
'tgid',
'groupno',
'groupname',
'count',
'signal',
'duration',
'timestamp',
'_guiend',
'_noshow',
'adtype',
'lat',
'lon',
'_raw',
'tgid_valid',
'atten',
'preamp',
'vsc',
'polarity',
'emgalt',
'emglvl',
'emgpat',
'utag',
'svcode',
'enc',
'scangrp',
'scan705',
'scan8600',
'rfgain',
'voloff',
'tslot',
'spltone',
'splfreq',
],
search  => [
'index',
'valid',
'start_freq',
'end_freq',
'step',
'mode',
'service',
'_guiend',
'_raw',
'agc_analog',
'agc_digital',
'atten',
'hld',
'c_ch',
'p25wait',
'qkey',
'utag',
'channel',
],
lookup => [
'index',
'frequency',
'service',
],
tag => [ ],
powermsg => ['msg1',
'msg2',
'msg3',
'msg4',
],
light    => ['event',
'bright',
],
beep     => ['volume',
],
lockfreq => [
'frequency',
],
ifxchng => [
'frequency',
],
syskey => [
'syskeys',
'_raw',
],
grpkey => [
'sysno',
'grpkeys',
'_raw',
],
toneout => [
'index',
'service',
'channel',
'frequency',
'mode',
'toneout_a',
'toneout_b',
'atten',
'agc_analog',
'dlyrsm',
'emgalt',
'emglvl',
'emgpat',
'emgcol',
'_raw',
],
);
my @non_indexed = ('lookup','ifxchng','lockfreq','beep','powermsg','light',
'lockfreq','toneout');
our %notsetable = ('count' => TRUE, 'systemname' => TRUE,
'signal' => TRUE, 'duration' => TRUE,
'timestamp' => TRUE, 'groupname' => TRUE,
);
our %struct_fields = (
'service'     => ['c',-30,'a',''],
'systemname'  => ['s',-20,'a',''],
'groupname'   => ['s',-20,'a',''],
'sitename'    => ['s',-20,'a',''],
'option'      => ['c',-20,'ab'],
'value'       => ['c',-20,'a'],
'_rsvd'       => ['c',4,'a','-'],
'_extra'      => ['c',-10,'a','-'],
'protocol'    => ['c',9,'a','-'],
'valid'       => ['b',  5,0,     0,0,1        ,0,],
'atten'       => ['b',  1,0,     0,0,1        ,0,],
'preamp'      => ['b',  1,0,     0,0,1        ,0,],
'vsc'         => ['b',  1,0,     0,0,1        ,0,],
'priority'    => ['b',  1,0,     0,0,1        ,0,],
'agc_digital' => ['b',  1,0,     0,0,1        ,0,],
'agc_analog'  => ['b',  1,0,     0,0,1        ,0,],
'moto_id'     => ['b',  1,0,     0,0,1        ,0,],
'i_call'      => ['b',  1,0,     0,0,1        ,0,],
'id_search'   => ['b',  1,0,     0,0,1        ,0,],
's_bit'       => ['b',  1,0,     0,0,1        ,0,],
'c_ch'       => ['b',  1,0,     0,0,1        ,0,],
'afs'         => ['b',  1,0,     0,0,1        ,0,],
'hex'         => ['b',  1,0,     0,0,1        ,0,],
'skip'        => ['b',  1,0,     0,0,1        ,0,],
'trunked'     => ['b',  1,0,     0,0,1        ,0,],
'tgid_valid'  => ['b',  1,0,     0,0,1        ,0,],
'sql'         => ['b',  1,0,     0,0,1        ,0,],
'vrsm'        => ['b',  1,0,     0,0,1        ,0,],
'vdly'        => ['b',  1,0,     0,0,1        ,0,],
'monitor'     => ['b',  1,0,     0,0,1        ,0,],
'useloc'      => ['b',  1,0,     0,0,1        ,0,],
'_noshow'     => ['b',  1,0,     0,0,1        ,0,],
'polarity'    => ['b',  1,0,     0,0,1        ,0,],
'idas'        => ['b',  1,0,     0,0,1        ,0,],
'frequency'    => ['f',11,0,25000000,0,9999999999],
'start_freq'   => ['f',11,0,25000000,0,9999999999],
'end_freq'     => ['f',11,0,26000000,0,9999999999],
'systemtype'   => ['c',-6,'bn','CNV',0,0        ,0,@system_type],
'edacs_type'   => ['c', 6,0,    '',0,0        ,0,'wide','narrow'],
'mot_type'     => ['c', 6,0,    '',0,0        ,0,'std','spl','custom'],
'lcn'          => ['i', 4,0,    '',0,4094     ,0,],
'flags'        => ['l', 9,0,   '',0,0         ,0,'0'],
'rec_type'     => ['l', 1,0,   '',0,0         ,0,'0'],
'sqtone'       => ['o', 8,  0, 'Off',0,0     ,0,@ctctone,@dcstone],
'spltone'      => ['o', 8,  0, '',0,0        ,0,sort keys %valid_rpt],
'att_amp'      => ['c', 5,  0, 'Off','.', '.',0,'off','att','amp'],
'mode'         => ['c', 6,  0, 'FMn',0,0     ,0,@modestring,"auto"],
'enc'          => ['n', 5,  0, ''   ,0,32767 ,0],
'dlyrsm'       => ['i', 6,  0, 0    ,-10,30  ,0],
'delay_value'  => ['i', 5,  0, '', 0,'.'     ,0],
'resume_value' => ['i', 5,  0, '', 0,'.'     ,0],
'resume'       => ['i', 3,  0, 0,-10,30      ,0],
'delay'        => ['i', 3,  0, 0,-10,30      ,0],
'step'         => ['f',10,0,   100,0,9999999999,0,'AUTO'],
'_comment'     => ['c',-20,'a'],
'site_number ' => ['c', 6,'a',''],
'channel'     => ['i', 4,'0','-'   ,-1,MAXCHAN  ,0,'-'],
'msg1'     => ['c',-20,'a',''],
'msg2'     => ['c',-20,'a',''],
'msg3'     => ['c',-20,'a',''],
'msg4'     => ['c',-20,'a',''],
'volume'    => ['i',  2,0,     0,0,15       ,0,],
'event'     => ['c', 6,0,   'Off',0,0        ,0,'on','off','key','sq','10','30'],
'bright'   =>  ['i', 1,0,       1,1,3        ,0,    ],
'tgid'        => ['g', 8,'ar',     '',0,0      ,0,],
'index'       => ['i', 5,'r',      0,0,'.'    ,0,],
'groupno'     => ['i', 5,'x',      0, 0,'.'      ,0,],
'siteno'      => ['i', 6,'xn',     0, 0,'.'      ,0,],
'sysno'       => ['i', 5,'x',      0, 0,'.'      ,0,],
'bank'        => ['i', 5,'x',      0, 0,'.'      ,0,],
'count'       => ['n', 5,'r',      0,0,'.'       ,0,],
'duration'    => ['n', 5,'r',      0,0,'.'       ,0,],
'timestamp'   => ['t', 10,'r',    '',0,'.'       ,0,],
'signal'      => ['n',  1,'r',     0,0,9         ,0,],
'dummy'       => ['c', 1,'ra',  ''],
'rssi'        => ['n', 5,'r',      0,0,'.'       ,0,],
'dbmv'        => ['n', 5,'r',      0,0,'.'       ,0,],
'meter'       => ['n', 5,'r',      0,0,'.'       ,0,],
'splfreq'  => ['f',10,'n',0,0,9999999999],
'lat'         => ['r',-12,'n',  '',0,0            ,0],
'lon'         => ['r',-12,'n',  '',0,0            ,0],
'radius'      => ['n',-12,'n',  '25',0,99999      ,0],
'scangrp'     => ['i', 7,'n',  '',0,9       ,0,'-','.'],
'scan705'     => ['i', 7,'n',  '',0,3       ,0,'-','.'],
'scan8600'    => ['i', 7,'n',  '',0,9       ,0,'-','.'],
'rfgain'      => ['i', 2,'n',  '',0,10       ,0],
'ran'         => ['i' ,2,'n', 's',0,69       ,0,'s'],
'qkey'        => ['i', 4,'n',   '-1',-1,99       ,0,'.','Off'],
'dqkey'       => ['i', 4,'n',   '-1',-1,99       ,0,'.','Off'],
'turnqk'      => ['c', 4,'n',     '','.','.'     ,0,'.','Off','On'],
'turndqk'     => ['c', 4,'n',     '','.','.'     ,0,'.','Off','On'],
'utag'        => ['i', 4,'n',   '-1',-1,999      ,0,'.','Off'],
'srch_ndx'    => ['c', 8,'b',   'S0','.',     '.',0,
'c0','c1','c2','c3','c4','c5','c6','c7','c8','c9',
's1','s2','s3','s4','s5','s6','s7','s8','s9','s11','s12','s15'],
'hld'         => ['i', 3,'n',   '0',0,255       ,0,],
'hpd'         => ['i', 6,'n',   -1,-1,999999    ,0],
'p25wait'     => ['i', 7,'n',   '',0,1000      ,0],
'emgalt'      => ['i', 6,'n',    '',0,9         ,0,],
'emgpat'      => ['i', 6,'n',    '',0,2         ,0,],
'emglvl'      => ['i', 6,'n',    '',0,15        ,0,],
'emgcol'      => ['i', 6,'n',    '',0,7         ,0,],
'toneout_a'   => ['n', 6,'n', 00000,00000,99999 ,0,],
'toneout_b'   => ['n', 6,'n', 00000,00000,99999 ,0,],
'endcode'     => ['c', 9,'nf',   '',0,0    ,0,'a','analog','b','both','i','ignore'],
'p25lvl'      => ['i', 6,'n',   '' ,0,63        ,0,],
'dsql'        => ['o', 8,  0, 'Off',0,0     ,0,'Off'],
'block_addr'  => ['i',10,'n',    '',0,'.'       ,0,],
'site_number' => ['c',11,'an',   '',0,0         ,0,],
'fleetmap'    => ['i', 8,'n',  '',0,16          ,0,] ,
'custmap'     => ['x', 8,'n',   '',0,4008536142 ,0,] ,
'tslot'       => ['n', 7,'n',  '',0,2           ,0,'Any'],
'adtype'      => ['c', 8,'n',   'AN' ,0,0,    ,0,keys %audio_types],
'voloff'      => ['i', 7,'n',   '',-3,3          ,0,],
'svcode'      => ['i', 6,'n',  '',0,216         ,0,],
'ccode'       => ['i' ,2,'nf', 's',0,15          ,0,'s'],
'filter'      => ['c',-12,'n',"",0,0         ,0,'g','i','a','n','o','off','wi','wn','wa',
'normal','global','invert','normal wide','global wide','invert wide'],
'frequency_l1'   => ['f',11,0,25000000,0,9999999999],
'frequency_u1'   => ['f',11,0,25000000,0,9999999999],
'frequency_l2'   => ['f',11,0,25000000,0,9999999999],
'frequency_u2'   => ['f',11,0,25000000,0,9999999999],
'frequency_l3'   => ['f',11,0,25000000,0,9999999999],
'frequency_u3'   => ['f',11,0,25000000,0,9999999999],
'frequency_l4'   => ['f',11,0,25000000,0,9999999999],
'frequency_u4'   => ['f',11,0,25000000,0,9999999999],
'frequency_l5'   => ['f',11,0,25000000,0,9999999999],
'frequency_u5'   => ['f',11,0,25000000,0,9999999999],
'frequency_l6'   => ['f',11,0,25000000,0,9999999999],
'frequency_u6'   => ['f',11,0,25000000,0,9999999999],
'spacing_1'      => ['f',11,0,25000000,0,9999999999],
'spacing_2'      => ['f',11,0,25000000,0,9999999999],
'spacing_3'      => ['f',11,0,25000000,0,9999999999],
'spacing_4'      => ['f',11,0,25000000,0,9999999999],
'spacing_5'      => ['f',11,0,25000000,0,9999999999],
'spacing_6'      => ['f',11,0,25000000,0,9999999999],
'offset_1'       => ['i', 8,0,       0,-1023,1023,0,],
'offset_2'       => ['i', 8,0,       0,-1023,1023,0,],
'offset_3'       => ['i', 8,0,       0,-1023,1023,0,],
'offset_4'       => ['i', 8,0,       0,-1023,1023,0,],
'offset_5'       => ['i', 8,0,       0,-1023,1023,0,],
'offset_6'       => ['i', 8,0,       0,-1023,1023,0,],
'infile'     => ['c',-20,'n','.'],
'ingrpno'    => ['i',   8,'n' , 1,1,99 ,0],
'outgrpno'   => ['i',   8,'n' , 1,1,99 ,0],
'outfirst'   => ['i',   8,'n' , 1,0,9999,0],
'outlast'    => ['i',   8,'n' , 1,0,9999,0],
'radio'      => ['c',-20,'bn','.'],
'_raw'       => ['c',1,'a',''],
);
our %binary = ('valid' => 1,'atten' => 1,'priority' => 1,
'alert' => 1,'skip'=> 1,'agc_analog'=>1, 'agc_digital' => 1,
'id_search' => 1,'s_bit'=> 1,'afs' => 1,'hex' => 1,'preamp' => 1,
'vsc' => 1,
);
my $type_dply = '';
foreach my $type (@system_type) {
if ($type_dply) {$type_dply = "$type_dply,$type";}
else {$type_dply = $type;}
}
our $header2 = "*********** RadioCtl Data Records *****************\n" .
"* Records are in the format: \n" .
"*record_type,field1,field2,field3,....\n" .
"*     or \n".
"*record_type,key1=value,key2=value,...\n" .
"* records starting with '*' or '#' are ignored\n".
"*rectypes:System,Site,TFreq,Group,Freq    (all case insensitive)\n" .
"* At least one 'System' record is required for each file\n" .
"*\n" .
"*fields/keys:\n" .
"*  Index: Unique number for the record\n".
"*  Valid: If 'F','0','N', record will not be scanned or selected in the radio\n" .
"*  Service: Any string with any characters except ',','#' or '" . '"' . "' \n" .
"*  SystemType: (SYSTEM Records) =>cnv,ltr,eds,edw,edn,mots,motc,trbo,p25s,p25f,p25f,dmr,nxdn\n" .
"*  Flags:Single Character turns on item. \n" .
"*    Flags for FREQ records: \n" .
"*      'a'-Attenuation\n" .
"*      'm'-Preamp\n" .
"*      'g'-Record is a TGID type (Frequency MUST be 0)\n".
"*    Flags for SYSTEM records: \n" .
"*      'f'-EDACS AFS format \n" .
"*      'h'-AGC_digital, 'i'-id_search (trunked systems), 'j'-AGC_analog, 'k'-data skip \n" .
"*      'o'-Control Channel only, 'p'-Turn on priority \n" .
"*  Dlyrsm:A number between -10 and +30. Negative number is Resume. 0 is Off\n" .
"*  Sysno:SYSTEM record index. Required for SITE & GROUP records\n" .
"*  Siteno:SITE record Index. Required for TFREQ records\n" .
"*  Groupno:GROUP record Index. Required for FREQ records\n" .
"*  Hld:(SYSTEM/SITE records). Time in seconds to hold on the system or site\n" .
"*  Frequency:(FREQ & TFREQ records). Can be in Hz or MHz. MHz must have decimal point\n" .
"*  Mode:Modulation:AM,AMw,AMm,AMn,WFM (Broadcast),FMn,FMu,LSB,USB,CW,RTTY\n" .
"*  Lat/Lon: Decimal value  or DMS (DD:MM:SS.SS:direction)\n" .
"*  P25wait:Time in ms to wait for a P25 decode to complete\n" .
"*  filter:(SDS200 only):  G-Global N-Normal I-Invert A-Auto O-Off WN-Wide Normal WI-Wide Invert WA-Wide Auto\n" .
"*  Channel - RadioCtl channel number. 0-9999 \n" .
"*  _Extra field: UTAG=x - Uniden User tag (0-1000)\n" .
"*                EMGALT=x - Uniden Emergency Alert (0-9) EMGLVL=x - Uniden Alert Level (0-15)\n" .
"*                SVCODE - SDS200 Service code           RFGAIN=x - R30 Gain (0-9)\n" .
"*                SCANGRP=x  - IC705/R8600 Scan group number (1-9)\n" .
"*                SCAN705=x  - IC705 Scan group number (1-3)\n" .
"*                SCAN8600=x - R8600 Scan group number (1-9)\n" .
"*\n" .
"*Keywords are not case sensitive\n" .
"*For keyword=value format, any keyword for the record not specified will be set to the default\n";
our %ver4_headers = ();
$ver4_headers{'freq'} = "******   Frequency records in format keyword=value ******* \n" .
"*   valid keywords:\n" .
"*     rectype - Value is 'freq' (required)\n" .
"*   frequency - Frequency in HZ or Mhz (required). Use '0' for blank channel\n" .
"*     service - Text for the service. If blanks, enclose in quotes\n" .
"*       valid - Logical value. Defaults to False\n" .
"*       sysno - System number. Must reference a 'SYSTEM' record in the file.\n".
"*     groupno - Group number. Must reference a 'GROUP' record in the file.\n" .
"*      siteno - Site number. Must reference a 'SITE' record in the file.\n" .
"*      sqtone - DCS/CTCSS tone value. Defaults to 'Off'\n" .
"*        mode - Modulation (AM/Fmn/Fmw/etc). Defaults to 'FMn' \n" .
"*       tgid  - Trunked Group ID. Only valid if 'siteno' > 0\n" .
"*    splfreq  - Split frequency (used by transmitters only)\n" .
"*  \n";
$ver4_headers{'system'} = "********* System records in format keyword=value ***********\n" .
"*     rectype - Value is 'system' (required)\n" .
"*     index   - System number (referenced by other record types\n" .
"*     service - Text for the system. If blanks, enclose in quotes\n" .
"*     valid   - Logical value. Defaults to False\n" .
"*\n";
my %edacs_types = ('wide' =>1,'narrow' => 1);
my %moto_types = ('std'=>1,'spl' => 1,'custom'=>1);
our %dummy_record = ('_comment' => 'Reserved record');
our %clear = ();
our %radio_routine = ();
our %valid_protocols = ();
our $GoodCode = 0;
our $CommErr  = 1;
our $ParmErr  = 2;
our $NotForModel = 3;
our $EmptyChan = 4;
our $OtherErr = 5;
our $FileErr  = 6;
our %syskey = ();
our %ifexchange = ();
our %freq_lock = ();
our $initmessage = '';
share(our %gui_request);
%gui_request = ();
share(our %scan_request);
%scan_request = ();
share(our %settings);
%settings = ('tempdir' => "$homedir/radioctl",
'recdir'  => "$homedir/radioctl",
'logdir'  => "$homedir/radioctl",
);
share (our @messages);
@messages = ();
share (our @selected);
@selected = ();
share (our @gui_modestring);
@gui_modestring = ();
foreach my $key (@rc_modes) {push @gui_modestring,$rc_modes{$key};}
share (our @gui_bandwidth);
@gui_bandwidth = ('(none)','Wide','Medium','Narrow','Ultra-Narrow');
share (our @gui_adtype);
@gui_adtype = ();
share (our @gui_tonestring);
@gui_tonestring = (@ctctone);
share (our @gui_attstring);
@gui_attstring = (@attstring);
share (our %chan_active );
share (our %radio_def);
%radio_def = ('maxchan' => MAXCHAN,'origin'  => 0,);
share (our %control);
%control  = (
'dlyrsm'  => FALSE,
'dbdlyrsm' => FALSE,
'dlyrsm_value' => 0,
'squelch' => 0,
'start_value' => 1,
'stop_value' => MAXCHAN,
'start'   => FALSE,
'stop'    => FALSE,
'logging' => FALSE,
'logging_dir' => "$homedir/radioctl/",
'clear' => FALSE,
'usesys' => FALSE,
'noskip'  => FALSE,
'nodup' => FALSE,
'manlog' => FALSE,
'scansys' => FALSE,
'scangroup' => FALSE,
'recorder' => FALSE,
'recorder_dir' => "$homedir/radioctl/",
'recorder_multi' => FALSE,
'autobaud' => TRUE,
);
share (our $response_pending);
$response_pending = FALSE;
share(our $scanner_thread);
$scanner_thread = FALSE;
share(our $progstate);
$progstate = 'manual';
share (our $record_file);
$record_file = '';
share (our $start_recording);
$start_recording = '';
share (our %vfo);
share (our %dbcounts);
foreach my $dbndx (@dblist) {$dbcounts{$dbndx} = 0;}
TRUE;
sub equate {
my $thread_ptr = threads->self;
my $thread_id = $thread_ptr->tid;
my ($source, $dest) = @_;
foreach my $kwd (keys %{$source}) {
$$dest{$kwd} = $$source{$kwd};
}
}
sub radio_send {
my ($parms,$outstr) = @_;
if (!$parms) {LogIt(993,"RADIO_SEND:No $parms for call!");}
my $portobj = $parms->{'portobj'};
if (!$portobj) {
print STDERR "## Radio_Send called without a portobj!\n";
return -2;
}
my $debug = FALSE;
my $term = '';
my $clear = FALSE;
if (defined $parms->{'term'}) {$term = $parms->{'term'};}
if (defined $parms->{'debug'}) {$debug = $parms->{'debug'};}
if (defined $parms->{'clear'}) {$clear = $parms->{'clear'};}
my $len = length($term);
$parms->{'rcv'} = '';
$parms->{'sent'} = $outstr;
while ($clear) {
my ($count_in, $data_in) = $portobj->read(1);
if ($count_in) {
if ($debug) {
my $dplybyte = "$data_in";
if ($parms->{'binary'}) {$dplybyte = hexdply($data_in);}
LogIt(0,"RADIO_SEND:Clearing byte=$dplybyte");
}
}
else {$clear = FALSE;}
}
my $countout = 0;
my $startflag = TRUE;
if ($outstr ne '') {
$countout = $portobj->write($outstr);
if ($debug) {
my $dply = $outstr;
if ($parms->{'binary'}) {$dply = hexdply($outstr)}
if ($debug) {LogIt(0, "RADIO_WRITE:Sent=>$dply<=\n count=$countout");}
}
}
if ($term eq '') {return 0 ;}
my $instr = '';
my $bytecnt = 0;
my $wait_count = 10;
my $resend = 0;
if ($parms->{'resend'}) {$resend = $parms->{'resend'};}
my $delay = 10;
if ($parms->{'delay'}) {$delay = $parms->{'delay'};}
while (TRUE) {
my ($count_in, $data_in) = $portobj->read(1);
if ($count_in) {
if ($data_in eq $term) {
$parms->{'rcv'} = $instr;
return 0;
}
else {
if (ord($data_in) eq 254) {$startflag = TRUE;}
if (ord($data_in) eq 252) {### ICOM Jamming code
$instr = '';
next;
}
if ($startflag) {
if ($data_in eq "\r") {$data_in = "\n";}
$instr = $instr . $data_in;
if ($instr =~ /$term/) {
$parms->{'rcv'} = $instr;
if ($debug) {LogIt(0,"RADIO_SEND:Found terminator");}
return 0;
}
}
}
$bytecnt++;
if ($debug) {
my $dplybyte = "$data_in";
if ($parms->{'binary'}) {$dplybyte = hexdply($data_in);}
LogIt(0,"RADIO_SEND:Got byte=$dplybyte");
}
$wait_count = 3;
}
else {
--$wait_count;
if ($wait_count < 1) {
if ($debug) {
my $what = unpack "H*",$term;
LogIt(0,"RADIO_SEND:$Bold Got timeout waiting for response $Yellow$what" . "x");
LogIt(0,"RADIO_SEND:   Sent->$outstr");
}
if (!$resend) {
if ($debug) {LogIt(0,"RADIO_SEND:Re-sent too many times. Giving up!");}
return 1;
}
else {
if ($outstr ne '') {$countout = $portobj->write($outstr);}
$resend--;
$wait_count = 3;
if ($debug) {LogIt(0,"RADIO_WRITE:resending...");}
}
}
threads->yield;
if ($debug) {LogIt(0,"RADIO_WRITE:delaying for $delay us. Wait count=$wait_count");}
usleep($delay);
}
}
}
sub cvt_signal {
my $radio_max = shift @_;
my $radio_signal = shift @_;
my $cvt = int($radio_max/MAXSIGNAL);
if ($radio_max < MAXSIGNAL) {
}
my $signal = int($radio_signal/$cvt);
if ($signal > MAXSIGNAL) {$signal = MAXSIGNAL;}
if (!$signal and $radio_signal) {$signal = 1;}
return $signal;
}
sub add_hash {
my @data = @_;
foreach my $ndx (0 .. $#data) {
my $str = lc(Strip($data[$ndx]));
if (defined $rc_hash{$str}) {
print STDERR "Error 1766. Redefined dropdown hash string $str\n";
exit 1766;
}
$rc_hash{$str} = $ndx;
}
}
sub mod_bandwidth {
my ($mode,$bw,$caller) = @_;
return $bw;
}
sub bandwidth_mod {
my ($bw,$mode,$caller) = @_;
return $mode;
}
sub rc_to_freq {
my ($hz) = @_;
if (!defined $hz) {$hz = 0;}
if (!$hz) {$hz = 0;}
if (!looks_like_number($hz)) {
LogIt(1,"RC_TO_FREQ:Bad input $hz");
return "0.000000";
}
my $mhz = 0;
if ($hz =~ /\./) { $mhz = $hz;}
else {
$hz = sprintf("%0${fdigits}.${fdigits}u",$hz);
my $lo = substr($hz,-($fdecimal));
my $hi = substr($hz,0,$fdigits-$fdecimal);
$mhz = "$hi.$lo";
}
$mhz = sprintf("%${fdigits}.${fdecimal}f",$mhz);
return $mhz;
}
sub freq_to_rc {
my ($fp) = @_;
my $num = -1;
my $mhz;
my $khz;
$fp =~ s/\,//;                            
$fp =~ s/^\s*(.*?)\s*$/$1/;               
if (!$fp) {return 0;}
if ($fp =~ /^(([ ]*)\d+\.?\d*|\.\d+)/ ) { 
if ($fp =~ /\./) {                     
($mhz,$khz) = $fp =~ /(\d*)\.(\d*)/; 
if (!$mhz) {$mhz = '0';}
if (!$khz) {$khz = '0';}
$khz = substr($khz . '000000',0,6);
$num = $mhz . $khz;
}
else {$num = $fp;}
}
return $num;
}
sub write_radioctl {
my $data = shift @_;
if (!$data) {LogIt(807,"write_radioctl: no data reference");}
my $filespec = shift @_;
if (!$filespec) {LogIt(810,"write_radioctl: no filename given!");}
LogIt(0,"Call to WRITE_RADIOCTL for filespec=$filespec");
my @options = @_;
my $sortfreq = FALSE;
my $write_global = FALSE;
my $mhz = FALSE;
my $append = FALSE;
my $no0 = FALSE;
my $renum = FALSE;
my $sysonly = FALSE;
my $nohdr = FALSE;
my $nochan = FALSE;
my $firstchan = 0;
my %exclude = ();
my %system_qkeys = ();
my $noorphan = FALSE;
my $keyformat = FALSE;
my $posformat = FALSE;
my $mergerec = FALSE;
foreach my $opt (@options) {
$opt = Strip(lc($opt));
if (!$opt) {next;}
if ($opt eq 'sort') {$sortfreq = TRUE;}
elsif ($opt eq 'global') { }
elsif ($opt eq 'search') { }
elsif ($opt eq 'append') {$append = TRUE;}
elsif ($opt eq 'mhz') {$mhz = TRUE;}
elsif ($opt eq 'keyformat') {$keyformat = TRUE;}
elsif ($opt eq 'posformat') {$posformat = TRUE;}
elsif ($opt eq 'no0') {$no0 = TRUE;}
elsif ($opt eq 'sysonly') {$sysonly = TRUE;}
elsif ($opt eq 'nohdr') {$nohdr = TRUE;}
elsif ($opt eq 'noorphan') {$noorphan = TRUE;}
elsif ($opt eq 'nochan') {$nochan = TRUE;}
elsif ($opt =~ /renum/i) {
$renum = TRUE;
($firstchan) = $opt =~ /\=(\d*)/;
if (!$firstchan) {$firstchan = 0;}
}
elsif (substr($opt,0,3) eq 'ex_') {$exclude{Strip(lc(substr($opt,3)))} = TRUE;}
else {LogIt(1,"Programmer specified a bad option $Green$opt$White!");}
}
my $oformat = 0;
if ($keyformat) {$oformat = 1;}
elsif ($posformat) {$oformat = 2;}
my ($filename,$filepath,$fileext) = fileparse($filespec,qr/\.[^.]*/);
if (! -e $filepath) {
make_path($filepath);
if ($?) {LogIt(1,"Cannot create path $filepath");}
return $FileErr;
}
my $outspec = ">$filespec";
if (-e $filespec) {
if ($append) {$outspec = ">>$filespec";}
else {
}
}
if (! open OUT,"$outspec") {
LogIt(1,"RadioCtl4 l2698:Cannot open $filespec \n      Error was=> $Red $!");
return $FileErr;
}
if ($nohdr) {
print OUT "\n*\n*********************************************\n";
print OUT "* New data appended ",Time_Format(time()),"\n";
print OUT "*********************************************\n*\n";
}
else {
print OUT "*RadioCtl   Data file generated: ",Time_Format(time()),"\n";
print OUT "*\n";
};
SYSTAG:
foreach my $sys (@{$data->{'system'}}) {
my $sysno = $sys->{'index'};
if (!$sysno){next;}
my $qkey = $sys->{'qkey'};
if ($sys->{'systemtype'} eq 'cnv') {
if (!defined $qkey) {next;}
if (!looks_like_number($qkey)) {next;}
if ($qkey < 0) {next;}
$qkey = sprintf("%2.2i",$qkey);
my $service = $sys->{'service'};
if (!$service) {$service = "System number $sysno";}
print OUT "*:QUICKKEY: SYSTEM_QK:$qkey  (sysno=$sysno name=$service)\n";
}
else {
my $qkey_string = 'SYSTEM_QK:';
if ((defined $qkey) and (looks_like_number($qkey))) {
$qkey_string = $qkey_string .  sprintf("%2.2i",$qkey);
}
else {$qkey_string = $qkey_string . '(n/a)';}
my $service = $sys->{'service'};
if (!$service) {$service = "System number $sysno";}
print OUT "*:QUICKKEY: $qkey_string Trunked System:sysno=$sysno name=$service)\n";
}
foreach my $site (@{$data->{'site'}}) {
if (!$site->{'index'}) {next;}
if ($site->{'sysno'} != $sysno) {next;}
my $sqkey = $site->{'qkey'};
if ((!defined $sqkey) or (!looks_like_number($sqkey)) or ($sqkey < 0)) {next;}
$sqkey = sprintf("%2.2i",$sqkey);
my $site_no = $site->{'site_number'};
if (!$site_no) {$site_no = $site->{'index'};}
my $service = $site->{'service'};
if (!$service) {$service = "site: $site_no";}
print OUT "*:QUICKKEY:    SITE_QK:$sqkey";
my $dqkey = $site->{'dqkey'};
if ($dqkey and looks_like_number($dqkey) and ($dqkey >= 0)) {
$dqkey = sprintf("%2.2i",$dqkey);
print OUT " DEPT_QK:$dqkey";
}
print OUT "  (siteno=>$site_no name=$service)\n";
}
}## SYSTEM/SITE quickkey process
my @tag_list = ();
my %tagkeys = ();
if (defined  $data->{'tag'}) {
foreach my $rec (@{$data->{'tag'}}) {
if (!$rec->{'index'}) {next;}
my @tagkey = keys %{$rec};
my $index = $rec->{'index'};
foreach my $key (@tagkey) {
if (!$key) {next;}
$key = Strip(lc($key));
if ($key eq 'index') {next;}
if ($key =~ /\_rectype/i) {next;}  
if ($key =~ /quickkey/) {next;}    
push @{$tagkeys{$key}},$index;
}
}### generating list of tags
my @tmp = sort keys %tagkeys;
my @sort_tags = ();
foreach my $key (@tmp) {
if ($key =~ /update/i) {unshift @sort_tags,$key;} 
else {push @sort_tags,uc($key)};
}
foreach my $key (@sort_tags) {
foreach my $recno (@{$tagkeys{$key}}) {
my $value = $data->{'tag'}[$recno]{uc($key)};
if ($value) {
print OUT "*:",uc($key),": $value\n";
}
}
}### for each custom tag
}### tags defined, output tags
my $block_ref = $data->{'_block_tag'};
if ($block_ref and (scalar @{$block_ref})) {
print OUT "*:START:\n";
foreach my $rec (@{$block_ref}) {
print OUT "$rec\n";}
print OUT "*:STOP:\n";
}
print OUT "*\n*\n";
my %head3 = ();
my %head4 = ();
foreach my $rectype (@dblist) {
my $outrec = '#:' . Strip(lc($rectype)) . ':';
my $outrec2 = '*' . sprintf("%-8.8s",Strip(uc($rectype)));
foreach my $fld (@{$version1{$rectype}}) {
if (!$struct_fields{$fld}[0]) {
LogIt(3031,"RADIOCTL.PM:Undefined field $Red$fld$White specified for $rectype!");;
}
$outrec = $outrec . Strip($fld) . ',';
my $n = $struct_fields{$fld}[1];
my $d = $n;
$d =~ s/\-//;   
$outrec2 = $outrec2 . ',' . sprintf("%${n}.${d}s",$fld);
}
$head3{$rectype} = $outrec;
$head4{$rectype} = $outrec2;
}
if (!$nohdr) {print OUT $header2;}
my @freqs = ();
foreach my $frq (@{$data->{'freq'}}) {
my $index = $frq->{'index'};
if (!$index) {next;}
push @freqs,$frq;
}
if ($sortfreq) {
@freqs = sort {$a->{'frequency'} <=> $b->{'frequency'} } @freqs;
}
my $freq_index = 1;
foreach my $rec (@freqs) {
$rec->{'index'} = $freq_index;
$freq_index++;
}
if ($nochan) {
foreach my $rec (@freqs) {
$rec->{'channel'} = '-1';
}
}
elsif ($renum) {
my $channel = $firstchan;
foreach my $rec (@freqs) {
$rec->{'channel'} = $channel;
$channel++;
if ($channel > MAXCHAN) {
LogIt(1,"Maximum channel number exceeded in renumber. Rolled-over to 0");
$channel = 0;
}
}
}### Renumber process
foreach my $sysrec (@{$data->{'system'}}) {
my $sysno = $sysrec->{'index'};
if (!$sysno) {next;}
if (!$sysonly and !$nohdr) {
print OUT "*\n*\n*    #### System Definition #####\n";
if ($oformat != 1) {
print OUT $head3{'system'},"\n";
print OUT $head4{'system'},"\n";
}
}
if ($nohdr) {print OUT "*\n";}
my $systype = $sysrec->{'systemtype'};
if ($systype !~ /mot/i) {
$sysrec->{'endcode'} = '';
$sysrec->{'fleetmap'} = '';
$sysrec->{'custmap'} = '';
}
if (($systype =~ /dmr/i) or ($systype =~ /ed/i)) {
$sysrec->{'p25wait'} = '';
$sysrec->{'p25lvl'} = '';
}
my $blk_comm = $sysrec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($sysrec,'system',$oformat),"\n";
if ($sysonly) {next;}
my $sitecnt = 0;
my $sysname = $sysrec->{'service'};
foreach my $siterec (@{$data->{'site'}}) {
my $siteno = $siterec->{'index'};
if (!$siteno) {next;}
if ($siterec->{'_processed'}) {next;}
if ($siterec->{'sysno'} != $sysno) {next;}
if (!$sitecnt and !$nohdr) {
print OUT "*\n*        ****** Sites for $sysname system ($sysno) *****\n";
}
$sitecnt++;
if ($siterec->{'filter'} and ($siterec->{'filter'} =~ /^o*/i)) {
$siterec->{'filter'} = '';
}
if (($oformat != 1) and (!$nohdr)) {
print OUT $head3{'site'},"\n";
print OUT $head4{'site'},"\n";
}
my $blk_comm = $siterec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($siterec,'site',$oformat),"\n";
$siterec->{'_processed'} = TRUE;
my $bpcnt = 0;
foreach my $bprec (@{$data->{'bplan'}}) {
my $index = $bprec->{'index'};
if (!$index) {next;}
if ($bprec->{'_processed'}) {next;}
if ($bprec->{'siteno'} != $siteno)  {next;}
if (!$bpcnt and !$nohdr) {
print OUT "*\n*      ******* Bandplan for $siterec->{'service'} site.\n";
if (($oformat != 1) and (!$nohdr)) {
print OUT $head3{'bplan'},"\n";
print OUT $head4{'bplan'},"\n";
}
}
foreach my $key (keys %{$bprec}) {
if ($key =~ /freq/) {
my $freq = freq_to_rc($bprec->{$key});
if ($mhz) {$freq = rc_to_freq($freq);}
$bprec->{$key} = $freq;
}
}
my $blk_comm = $bprec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($bprec,'bplan',$oformat),"\n";
$bprec->{'_processed'} = TRUE;
$bpcnt++;
}
my $freqcnt = 0;
foreach my $freqrec (@{$data->{'tfreq'}}) {
my $freqno = $freqrec->{'index'};
if (!$freqno) {next;}
if ($freqrec->{'_processed'}) {next;}
if (!$freqrec->{'siteno'}) {next;}
if ($freqrec->{'siteno'} != $siteno)  {next;}
if (!$freqcnt and !$nohdr) {
print OUT "*\n*      ******* Frequencies for $siterec->{'service'} site.\n";
if (($oformat != 1) and (!$nohdr)) {
print OUT $head3{'tfreq'},"\n";
print OUT $head4{'tfreq'},"\n";
}
}
$freqcnt++;
my $freq = freq_to_rc($freqrec->{'frequency'});
if ($freq <= 0) {
LogIt(1,"RADIOCTL.PM l2950:Siteno=>$siteno TFREQ=>$freqno frequency=>$freqrec->{'frequency'} is not valid!");
$freq = 0;
$freqrec->{'valid'} = FALSE;
}
if ($mhz) {$freq = rc_to_freq($freq);}
$freqrec->{'_frequency'} = $freq;
my $blk_comm = $freqrec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($freqrec,'tfreq',$oformat),"\n";
$freqrec->{'_processed'} = TRUE;
}### all frequencies for this site
if (!$freqcnt) {
print OUT "***** No frequencies defined for this site!\n";
LogIt(1,"No frequencies defined for site $siteno $siterec->{'service'} (system=>$sysname)");
}
if (!$nohdr) {print OUT "\n*\n";}
}
my $grpcnt = 0;
foreach my $grouprec (@{$data->{'group'}}) {
my $groupno = $grouprec->{'index'};
if (!$groupno) {next;}
if ($grouprec->{'_processed'}) {next;}
if (!$grouprec->{'sysno'}) {next;}
if (($grouprec->{'sysno'} != $sysno) ) {next;}
if ($grouprec->{'filter'} and ($grouprec->{'filter'} =~ /^o*/i)) {
$grouprec->{'filter'} = '';
}
if (!$grpcnt and !$nohdr) {
print OUT "*\n*    ### Groups for $sysname system ($sysno). \n";
if (($oformat != 1) and (!$nohdr)) {
print OUT $head3{'group'},"\n";
print OUT $head4{'group'},"\n";
}
}
my $blk_comm = $grouprec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($grouprec,'group',$oformat),"\n";
$grouprec->{'_processed'} = TRUE;
$grpcnt++;
}
if (!$grpcnt) {print OUT "** No groups found for this system!\n";}
my $frqcnt = 0;
foreach my $freqrec (@freqs) {
my $freqno = $freqrec->{'index'};
if (!$freqno) {next;}
if ($freqrec->{'_processed'}) {next;}
my $groupno = $freqrec->{'groupno'};
if (!$groupno) {next;}
my $grpsys = $data->{'group'}[$groupno]{'sysno'};
if (!$grpsys) {next;}
if ($grpsys != $sysno) {next;}
if ((!$frqcnt) and (!$nohdr))  {
my $contents = 'Frequencies';
if (lc($sysrec->{'systemtype'}) ne 'cnv') {$contents = 'TGIDs';}
print OUT "*\n*    #### All $contents for $sysname system ($sysno) ####\n";
if (($oformat == 2) or (!$oformat and ($contents =~ /freq/i) )) {
print OUT $head3{'freq'},"\n";
print OUT $head4{'freq'},"\n";
}
}
my $freq = freq_to_rc($freqrec->{'frequency'});
if ($freq < 0) {
LogIt(1,"RADIO_WRITE:Index $freqno frequency=>$freq is not valid! (less than 0)");
$freq = 0;
}
elsif ($freqrec->{'tgid_valid'}) {
$freq = '';
$freqrec->{'mode'} = '';
$freqrec->{'splfreq'} = '';
$freqrec->{'spltone'} = '';
}
elsif (!$freq) {
if ($freqrec->{'valid'}) {
$freqrec->{'valid'} = FALSE;
my $recno = $freqrec->{'_recno'};
if (!$recno) {
$recno = '?';
print Dumper($freqrec),"\n";
}
LogIt(1,"l3373:0 frequency specified for record=>$recno. Record marked as not valid");
}
}
elsif ($mhz) {
$freq = rc_to_freq($freq);
}
$freqrec->{'_frequency'} = $freq;
my $splfreq = $freqrec->{'splfreq'};
if ($splfreq and $mhz) {$freqrec->{'splfreq'} = rc_to_freq($splfreq);}
my $blk_comm = $freqrec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($freqrec,'freq',$oformat),"\n";
$freqrec->{'_processed'} = TRUE;
$frqcnt++;
my %logrec = ();
my $dolog = FALSE;
foreach my $key (@{$version1{'log'}}) {
if ($key eq 'index') {next;}
$logrec{$key} = $freqrec->{$key};
if ($logrec{$key}) {$dolog = TRUE;}
}
if ($dolog) {
$logrec{'index'} = $freqrec->{'index'};
print OUT write_format(\%logrec,'log',$oformat),"\n";
}
}### all freqs for this group
if (!$frqcnt) {print OUT "*** No frequencies/TGID records for this system\n";}
}### All Systems
if (!$sysonly and !$noorphan) {
foreach my $rectype ('site','tfreq','group','freq') {
my $cnt = 0;
foreach my $rec (@{$data->{$rectype}}) {
if (!$rec->{'index'}) {next;}
if ($rec->{'_processed'}) {next;}
if (!$cnt) {
if ($rectype eq 'site') {
print OUT "*\n*\n* *********** Orphans ***************\n";
}
print OUT "*\n*    #### Orphaned $rectype records ####\n";
if (($oformat != 1) and (!$nohdr)) {
print OUT $head3{$rectype},"\n";
print OUT $head4{$rectype},"\n";
}
}
my $freq = $rec->{'frequency'};
if (($rectype eq 'freq') or ($rectype eq 'tfreq')) {
if ($rec->{'tgid_valid'}) {### not a frequency
$rec->{'mode'} = '';
$rec->{'offset'} = '';
}
elsif (!$freq) {
if ($rec->{'valid'}) {
$rec->{'valid'} = FALSE;
my $recno = $rec->{'_recno'};
if (!$recno) {
$recno = '?';
print Dumper($rec),"\n";
}
LogIt(1,"l3373:0 frequency specified for record=>$recno. Record marked as not valid");
}
}
elsif ($mhz) {
$freq = rc_to_freq($freq);
}
$rec->{'_frequency'} = $freq;
}
my $blk_comm = $rec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($rec,$rectype,$oformat),"\n";
$cnt++;
}
if ($cnt) {LogIt(1,"$cnt $rectype orphans were found!");}
}
}
if ($data->{'search'}[1]{'index'}) {
print OUT "*\n********************* SEARCH records *****************************\n";
if (($oformat != 1) and (!$nohdr)) {
print OUT $head3{'search'},"\n";
print OUT $head4{'search'},"\n";
}
foreach my $rec (@{$data->{'search'}}) {
my $ndxno = $rec->{'index'};
if (!$ndxno) {next;}
foreach my $key ('start_freq','end_freq') {
if ($rec->{$key}) {
my $freq = freq_to_rc($rec->{$key});
if ($freq < 0) {
LogIt(1,"RADIO_WRITE:Search Index $ndxno frequency=>$freq is not valid! (less than 0)");
$freq = 0;
}
if ($mhz) {$freq = rc_to_freq($freq);}
$rec->{$key} = $freq;
}### frequency not 0
}
my $blk_comm = $rec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
print OUT write_format($rec,'search',$oformat),"\n";
}
}
foreach my $rectype (@non_indexed) {
if (!defined $data->{$rectype}) {next;}
my $recount = scalar @{$data->{$rectype}};
if ($recount < 2) {next;}
print OUT
"*\n********************* " . uc($rectype) . " records *****************************\n" ;
foreach my $rec  (@{$data->{$rectype}}) {
if (!$rec->{'index'}) {next;}
my %non_indexed = ();
foreach my $key (keys %{$rec}) {
if ($key =~ /index/i) { next;}   
my $value = $rec->{$key};
if ($key =~ /frequency/i) {
$non_indexed{'_frequency'} = $value;
if ($mhz)  {$non_indexed{'_frequency'} = rc_to_freq($value);}
}
elsif ($key =~ /toneout/i) {
if (looks_like_number($value)) {
$value = Strip(sprintf("%6.1f",$value/10));
}
}
$non_indexed{$key} = $value;
}### format certain keys
my $blk_comm = $rec->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
my $outline = write_format(\%non_indexed,$rectype,1);
print OUT "$outline\n";
}
}### non-indexed record types
my $blk_comm = $data->{'_block_comments'};
if ($blk_comm and (scalar @{$blk_comm})) {
foreach my $rec (@{$blk_comm}) {print OUT "$rec\n";}
}
close OUT;
LogIt(0,"$Bold File $Yellow$filespec$White updated");
return $GoodCode;
}
sub write_format {
my $record = shift @_;
my $rectype = Strip(shift @_);
my $oformat   = shift @_;
my $outrec = sprintf("%-9.9s",uc($rectype));
my $keyformat = FALSE;
if ($oformat == 1) {$keyformat = TRUE;}
elsif ($oformat == 2) {$keyformat = FALSE;}
else {
if ($record->{'_format'} and ($record->{'_format'} == 4)) {$keyformat = TRUE;}
if ($record->{'tgid_valid'}) {$keyformat = TRUE;}
}
if ($keyformat)  {
foreach my $key ( @{$structure{$rectype}}) {
if ($key eq 'dummy') {next;}
if ($key eq 'service') {next;}
if (substr($key,0,1) eq '_'){ next;}
my $value = $record->{$key};
if ($key eq 'frequency') {$value = $record->{'_frequency'};}
if (!defined $value) {next;}
if ($key eq 'channel') {
if ((!looks_like_number($value)) or ($value < 0)) {next;}
}
$value = Strip($value);
if ($value eq '') {next;}
if ($value eq '-') {next;}
if ($key eq 'tone') {next;}
if ($key eq 'tone_type') {next;}
if ($key eq 'sqtone') {
$value = uc($value);
}### SQTONE
if ($value =~ /off/i) {next;} 
if (($key eq 'qkey') or ($key eq 'utag')) {
if (!looks_like_number($value)) {next;}
if ($value < 0) {next;}
}
if (($key eq 'enc') and ($record->{'adtype'} !~ /ndxn/i)) {next;}
if (($key eq 'scangrp') and ($value < 1)) {next;}
if (($key eq 'scan705') and ($value < 1)) {next;}
if (($key eq 'scan8600') and ($value < 1)) {next;}
if (!$value) {
my $ok = TRUE;
if ($key eq 'valid') {$ok = FALSE;}
elsif ($key eq 'channel') {$ok = FALSE;}
elsif ($key =~ /toneout/i) {$ok = FALSE;}
if ($ok) {next;}
}
if ($key eq 'mode') {
foreach my $str (@modestring) {
my $cmpr = Strip($str);
if (lc($value) eq (lc($cmpr)) ) {
$value = $cmpr;
last;
}
}
}
if ($key eq 'adtype') {
if ((!$value) or ($value =~ /an/i)){next;}
my $new_value = $audio_types{uc(Strip($value))};
if (!$new_value) {next;}
$value = $new_value;
}
$outrec = $outrec . ",$key=$value";
}
my $service = $record->{'service'};
if ($service) {$outrec = "$outrec,service=" . Strip($service);}
}
else {
my @keys = ();
my $last_nonblank = '';
my @fields = ();
foreach my $key ( @{$version1{$rectype}}) {
if (!defined $struct_fields{$key}) {
LogIt(3483,"Write_Radioctl l3365:No Struct_Fields definition for $key!");
}
my $value = $record->{$key};
if ($key eq 'flags') {
$value = '';
foreach my $flagkey (keys %flagchar) {
if ($record->{$flagkey}) {
$value = $value . $flagchar{$flagkey};
}
}
}
elsif ($key eq '_extra') {
$value = '';
foreach my $char  (keys %extra_char) {
if (!$extra_char{$char}{$rectype}) {next;}
my $fld_value = $record->{$char};
if (!defined $fld_value) {next;}
$fld_value = Strip($fld_value);
if ($fld_value eq '') {next;}
if (looks_like_number($fld_value)) {
my $min = $extra_char{$char}{'min'};
if ((defined $min) and  ($fld_value < $min)) {next;}
}
if ($char eq 'enc') {
if ($record->{'adtype'} !~ /nxdn/i) {next;}   
}
elsif (!$fld_value) {
my $min = $extra_char{$char}{'min'};
if ($min or (!defined $min)) {next;}
}
$value  = "$value $char=$fld_value";
}
}
elsif ($key eq 'frequency') {
$value = $record->{'_frequency'};
}
elsif ($key eq 'mode') {
foreach my $str (@modestring) {
my $cmpr = Strip($str);
if (lc($value) eq (lc($cmpr)) ) {
$value = $cmpr;
last;
}
}
}
elsif ($key eq 'utag') {
if ((!looks_like_number($value)) or ($value < 0)) {
$value = '';
}
}
elsif ($key eq 'adtype') {
if ($value) {
if ($value =~ /an/i) {$value = '';}   
else {
my $new_value = $audio_types{uc(Strip($value))};
if ($new_value) {$value = $new_value;}
}
}
}
elsif ($key eq 'tone') {next;}
elsif ($key eq 'tone_type') {next;}
elsif ($key eq 'sqtone') {
$value = uc($value);
}### sqtone
if (!defined $value) {$value = '';}
elsif ($value eq '-') {$value = '';}
elsif ($value eq '.') {$value = '';}
$value = Strip($value);
my $s = $struct_fields{$key}[1];
my %fld = ('length' => $s,'value' => $value,'field'=>$key);
push @fields,{%fld};
if ($value ne '') {$last_nonblank = $#fields;} 
}
my $leftover = 0;
foreach my $ndx (0..$last_nonblank) {
my $s = $fields[$ndx]{'length'};
my $sign = 1;
if ($s < 0) {$sign = -1;}
my $fl = abs($s);
my $value = $fields[$ndx]{'value'};
my $field = $fields[$ndx]{'field'};
if ($field eq 'qkey') {
if ((!looks_like_number($value)) or ($value < 0)) {
$value = 'Off';
}
}
my $len = length($value);
my $extra = 0;
if ($fl > $len) {$extra = $fl - $len;}
else {$leftover = $leftover + ($len - $fl);}
if ($leftover) {
if ($leftover <= $extra) {
$s = ($fl - $leftover) * $sign;
$leftover = 0;
}
else {
$leftover = $leftover - $extra;
$s = ($fl - $extra) * $sign;
}
}
$value = sprintf("%${s}s",$value);
$outrec = "$outrec,$value";
}### field output
}### positional output
if ($record->{'_line_comment'}) {
if (!$outrec) {$outrec = '';}
$outrec = $outrec . ' #' . $record->{'_line_comment'};
}
return $outrec;
}
sub read_radioctl {
my $data = shift @_;
my $filespec = shift @_;
if (! -e $filespec) {
LogIt(1,"READ_RADIOCTL l3765: Cannot locate file $filespec");
return 1;
}
my $retcode = 0;
my $firstnon = TRUE;
my @inrecs = ();
if (open INFILE,$filespec) {
@inrecs = <INFILE>;
close INFILE;
}
else {
LogIt(1,"READ_RADIOCTL: Cannot open $filespec");
return 2;
}
my $firstrec = shift @inrecs;
my $filetype = 0;
my $version = 0;
if ($firstrec =~ /^\*radioctl/i) {
$filetype = 1;
$version = \%version1;
}
else {
LogIt(1,"Unknown RadioCtl filetype=>$firstrec");
return 4;
}
my $flag_error = FALSE;
my $recno = 1;
my $usercomment = FALSE;
my %localdb = ();
@{$data->{'_block_comments'}} = ();
@{$data->{'_block_tag'}} = ();
my %old_xref = ();
my %index_required = ('system' => TRUE, 'site' => TRUE, 'group' => TRUE, 'log' => TRUE,
'freq' => TRUE, 'tfreq' => TRUE, 'bplan' => TRUE,);
my %flag_translate;
LogIt(0,"READ_RADIOCTL:Input file $filespec is Record type $filetype");
my $tagstart = FALSE;
my $linecomment = '';
my %field_order = ();
foreach my $rectype (keys %version1) {
foreach my $fld (@{$version1{$rectype}}) {
push @{$field_order{$rectype}},$fld;
}
}
READREC:
while (scalar @inrecs) {
my $linein = shift @inrecs;
$recno++;
my $recsave = $linein;
chomp $linein;
if (!$linein) {next;}
$linein = Strip($linein);
if (!$linein) {next;}
my %rec = ('_recno' => $recno,
'_filespec' => $filespec,
'_block_comments' => [],
);
if (($linein =~ /\*\:/) or ($linein =~ /\#\:/)) {
my ($tagname,$value) = $linein =~ /\:(.*)\:(.*)/;
if (!$tagname) {### Tag issue
LogIt(1,"Improper tag $Red$linein$White in record $Green$recno");
next READREC;
}
$tagname = Strip(lc($tagname));
if ($field_order{$tagname}) {
my @fields = split(',',$value);
$field_order{$tagname} = ();
foreach my $fld (@fields) {
if (!$fld) {next;}
$fld = lc(Strip($fld));
if ($fld eq 'gqkey') {$fld = 'qkey';}
elsif ($fld eq 'site_qkey') {$fld = 'qkey';}
push @{$field_order{$tagname}},$fld;
}
next READREC;
}### Field definition tag
elsif ($tagname eq 'start') {
while (scalar @inrecs) {
$linein = shift @inrecs;
$recno++;
chomp $linein;
$linein = Strip($linein);### remove leading/trailing blanks
if ($linein =~ /\:stop\:/i) {next READREC;} 
if ($linein =~ /\:end\:/i) {next READREC;} 
push @{$data->{'_block_tag'}},$linein;
}
if (!scalar @inrecs) {
LogIt(1,"Missing ':stop' or ':end' tag for block comment tag!\n" .
" Cannot process file $Yellow$filespec");
return 3;
}
}
elsif (($tagname eq 'stop') or ($tagname eq 'end')) {
LogIt(1,"$Yellow$tagname$White found outside of block comment in line $Green$recno");
next READREC;
}
elsif ($tagname eq 'quickkey') {next READREC;}
else {
my %tags = (uc($tagname) => $value);
add_a_record($data,'tag',\%tags,FALSE);
next READREC;
}
}### Tag found
elsif ($linein =~ /^\#/) {
push @{$data->{'_block_comments'}},$linein;
next READREC;
}
elsif ($linein =~ /^\*/) {next READREC;}
else {
}### Defined record type
if (read_line($linein,\%rec,\%field_order)) {
$retcode = $ParmErr;
print "4622: Linein=>$linein\n";
next READREC;
}
my $rectype = $rec{'_rectype'};
my @validate = '';
if (defined $structure{$rectype}) {
@validate = @{$structure{$rectype}};
}
elsif (defined $version1{$rectype}) {
@validate = @{$version1{$rectype}};
}
else {
LogIt(1,"READ_RADIOCTL l4290:No Structure for $rectype record=$recno in $filespec");
$retcode = 3;
next READREC;
}
if (!$rec{'index'} and $index_required{$rectype}) {
LogIt(1,"Read_RadioCtl l4418:Index missing or 0 not allowed for type $rectype in record $recno for $filespec!");
$retcode = 3;
next READREC;
}
if ($rec{'flags'}) {
if (!defined $flag_translate{$rectype}) {
foreach my $key ( @{$structure{$rectype}}) {
my $char = Strip($flagchar{$key});
if (defined $flagchar{$key}) {$flag_translate{$rectype}{$char} = $key ;}
}
}### fillin for record flags
foreach my $key (keys %{$flag_translate{$rectype}}) {$rec{$key} = FALSE;}
my @flags = split "",$rec{'flags'};
foreach my $char (@flags) {
$char = Strip(lc($char));
my $key = $flag_translate{$rectype}{$char};
if ($key) {$rec{$key} = TRUE;}
}
}### flag process
if ($rec{'tgid_valid'}) {
$rec{'frequency'} = 0;
$rec{'sqtone'} = 'Off';
$rec{'spltone'} = '';
}
if ($rec{'_extra'}) {
my @words = split " ",$rec{'_extra'};
foreach my $word (@words) {
if (!$word) {next;}
$word = Strip(lc($word));
my $kwd = '';
my $value = 0;
if ($word =~ /\=/) {
($kwd,$value) = $word =~ /(.*?)\=(.+)/;
}
else {
($kwd,$value) =  $word =~ /(.*?)(\d+)/;
}
if (!$kwd) {
LogIt(1,"Missing keyword for $Red$word$White in EXTRA field in record $Green$recno");
next;
}
if (!$value) {$value = 0;}
if ($extra_char{$kwd}{$rectype}) {$rec{$kwd} = $value;}
else {
LogIt(1,"Keyword $Red$kwd$White " .
"is not valid for EXTRA field in record $Green$recno$White\n" .
"  Value ignored");
}
}
}
foreach my $key ('frequency','splfreq') {
if (defined $rec{$key}) {
my $freq = $rec{$key};
if (!$freq or ($freq eq '') or ($freq eq '.') or ($freq eq '-')) {
$freq = 0;
if ($key eq 'frequency') {$rec{'mode'} = '-';}
}
if (!looks_like_number($freq)) {
LogIt(1,"READ_RADIOCTL l4086:Bad frequency $freq in record $recno of $filespec");
$retcode = 3;
next READREC;
}
if ($freq == 0) {$freq = 0;}
$rec{$key} = $freq;
}
}
if ($rec{'service'}) {$rec{'service'} =~ s/\"//g;}
if ($rec{'mode'}) {
if ($rec{'mode'} =~ /fmun/i) {$rec{'mode'} = 'fmu';}
elsif ($rec{'mode'} =~ /rtty/i) {$rec{'mode'} = 'rt';}
elsif ($rec{'mode'} =~ /lsb/i)  {$rec{'mode'} = 'ls';}
elsif ($rec{'mode'} =~ /usb/i)  {$rec{'mode'} = 'us';}
elsif ($rec{'mode'} =~ /wfm/i)  {$rec{'mode'} = 'wf';}
}
if ((!$rec{'mode'}) or $rec{'mode'} =~ /auto/i) {
if ($rectype =~ /tfreq/i) {$rec{'mode'} = 'fmn';}
elsif ($rectype =~ /freq/i) {
$rec{'mode'} = AutoMode(freq_to_rc($rec{'frequency'}));
}
elsif ($rectype =~ /search/i) {
$rec{'mode'} = AutoMode(freq_to_rc($rec{'start_freq'}));
}
else {$rec{'mode'} = 'fmn';}
}
if ($rec{'adtype'}) {
my $type = Strip($rec{'adtype'});
if ($type =~ /^an/i) {$rec{'adtype'} = 'AN';} 
elsif ($type =~ /all/i) {$rec{'adtype'} = 'AN';} 
else {
my $found = FALSE;
foreach my $key (sort keys %audio_types) {
if (length($type) == 2) {### Two char representation
if ($key =~ /$type/i) {
$found = TRUE;
last;
}
}
else {
if ($audio_types{$key} =~ /$type/i) {
$rec{'adtype'} = $key;
$found = TRUE;
last;
}
}
}### Check all the digital keys
if (!$found) {
LogIt(1,"RC l4816:" .
"Unsupported audio type $type in record $recno of $filespec. Ignored");
$rec{'adtype'} = 'AN';
}### Not found
else {
if ($rec{'mode'} !~ /fm/i) {
LogIt(1,"RC l4825" .
"Digital audio only supported for FM modulation in record $recno of $filespec. Ignored");
$rec{'adtype'} = 'AN';
}
}
}## Digital audio process
}### Some value specified in ADTYPE
else {$rec{'adtype'} = 'AN';}
if ($rectype =~ /freq/i) {
my $tone_type = $rec{'tone_type'};
my $oldtone = $rec{'tone'};
if ($tone_type and $oldtone) {
$oldtone = Strip($oldtone);
if (($tone_type =~ /off/i) or ($oldtone =~ /off/i)) {
$rec{'sqtone'} = 'Off';
}
elsif ($tone_type =~ /ctc/i) {
my ($tt,$tone) = Tone_Xtract("CTC$oldtone");
$rec{'sqtone'} = "$tt$tone";
}
elsif ($tone_type =~ /dcs/i) {$rec{'sqtone'} = "DCS$oldtone";}
}### Older Tone/Tonetype fields
if (!$rec{'sqtone'}) {$rec{'sqtone'} = 'Off';}
if ($rec{'tgid_valid'}) {
$rec{'sqtone'} = 'Off';
$rec{'spltone'} = '';
}
my ($tt,$tone) = Tone_Xtract($rec{'sqtone'});
if ($rec{'sqtone'} !~ /off/i) {                   
if ($rec{'mode'} =~ /fm/i) {                   
my $adtype = $rec{'adtype'};
my $bad = FALSE;
if ($tt =~ /ran/i) { 
if (($adtype !~/nx/i) and ($adtype !~ /vn/i)) {$bad = TRUE;}
else {
if (($tone =~ /^-?\d+$/) and ($tone < 64)) {
}
else {$bad = TRUE;}
}
}### NXDN tone type
elsif ($tt =~ /ccd/i) { 
if ($adtype !~ /dm/i) {$bad = TRUE;}
else {
if (($tone =~ /^-?\d+$/) and ($tone < 16)) {
}
else {$bad = TRUE;}
}
}### DMR tone type
elsif ($tt =~ /nac/i)
{### P25 type tone
if ($adtype !~ /p2/i) {$bad = TRUE;}
else {
if ($tone =~ /[[:xdigit:]]/i) {
if ( hex($tone) > hex('FFF') ) {$bad = TRUE;}
}
else {$bad = TRUE;}
}
}### P25 tone type
elsif ($tt =~ /dsq/i) {### DSTAR type tone
if ($adtype !~ /ds/i) {$bad = TRUE;}
else {
if (($tone =~ /^-?\d+$/) and ($tone < 100)) {
}
else {$bad = TRUE;}
}
}### DSTAR
elsif (($tt =~ /ctc/i) or ($tt =~ /rpt/i)) {
if ($adtype !~ /an/i) {
$bad = TRUE;
}
else {
my $key = uc($tt) . $tone;
if ($tt =~ /rpt/i) {$key = "CTC$tone";}
if ($valid_ctc{$key}) {
}
else {
$bad = TRUE;
}### Bad tone value
}
}
elsif ($tt =~ /dcs/i)  {
if ($adtype !~ /an/i) {$bad = TRUE;}
else {
if ($valid_dcs{"DCS$tone"}) {
}
else {$bad = TRUE;}
}
}
else {
LogIt(1,"l4921: Unrecognized 'sqtone':$Magenta$rec{'sqtone'}$White " .
" in record $Green$recno$White of $Yellow$filespec$White.\n " .
"    Tone is turned off ");
$tt ='Off';
$tone = '';
}
if ($bad) {
my $audio = $audio_types{$adtype};
if (!$audio) {$audio = 'Analog';}
LogIt(1,"l4928: 'sqtone':$Magenta$rec{'sqtone'}$White " .
"is not valid for audio type $Magenta$audio$White " .
" in record $Green$recno$White of $Yellow$filespec$White.\n " .
"    Tone is turned off ");
$tt ='Off';
$tone = '';
}
}### FM modulation
else {
LogIt(1,"l4937:'sqtone':$Magenta$rec{'sqtone'}$White " .
" in record $Green$recno$White of $Yellow$filespec$White.\n " .
"    Tone is turned off ");
$tt ='Off';
$tone = '';
}
$rec{'sqtone'} = "$tt$tone";
}### Tone is NOT off
my $spltone = $rec{'spltone'};
if ($spltone) {
my $bad = FALSE;
if ( ($rec{'mode'} =~ /fm/i) and
(!$rec{'tgid_valid'}) and
($rec{'adtype'} =~ /an/i) and
($rec{'splfreq'}) ) {
my ($tt,$tone) = Tone_Xtract($spltone);
if ($tone and ($tt =~ /rpt/i) or ($tt =~ /ctc/i)) {
my $key = "CTC$tone";
if ($valid_ctc{$key}) {
$rec{'spltone'} = "$tt$tone";
}
else {$bad = TRUE;}
}### Repeater or CTCSS
else {$bad = TRUE;}
}### All conditions for a valid SPLTONE
else {$bad = TRUE;}
if ($bad) {
LogIt(1,"l4996: 'rpttone':$Magenta$spltone$White " .
"is not a valid split tone" .
" in record $Green$recno$White of $Yellow$filespec$White.\n " .
"    Tone is ignored ");
$rec{'spltone'} = '';
}
else {$rec{'spltone'} = "$tt$tone";}
}
}### FREQ record TONE process
my %recsave = %rec;
my $rc = KeyVerify(\%rec,@validate);
if ($rc > 2) {
$retcode = 3;
LogIT(1,"RADIOCTL l4311:Could not correct problem with record $Green$recno");
next READREC;
}
if ($rec{'rfgain'}) {
if (looks_like_number($rec{'rfgain'})) {
}
else {$rec{'rfgain'} = 0;}
}
if ($rectype eq 'toneout') {
foreach my $key ('toneout_a','toneout_b') {
my $toneout = 0;
if ($rec{$key} and looks_like_number($rec{$key})) {
$toneout = $rec{$key};
}
my $newout = int($toneout * 10);
if ($newout > 99999) {
LogIt(1,"READ_RADIOCTL l4389: $key " .
"$Red$toneout$White out of range in record " .
"$Green$recno$White of $Yellow$filespec$White.\n" .
"     Changed to 0!");
}
else {$toneout = $newout;}
$rec{$key} = $toneout;
}
}
if ($OneOnly{$rectype}) {
my $count = 0;
if (defined $localdb{$rectype}) {$count = (scalar @{$localdb{$rectype}});}
if ( $count > 1) {
LogIt(1,"READ_RADIOCTL l4010:Multiple $Magenta$rectype$White records ".
"found in line $Green$recno$White of $Yellow$filespec$White." .
" Previously specified values discarded");
$localdb{$rectype} = ();
}
}
$rec{'_oldindex'} = $rec{'index'};
if ((scalar @{$data->{'_block_comments'}})) {
push @{$rec{'_block_comments'}},@{$data->{'_block_comments'}};
@{$data->{'_block_comments'}} = ();
}
my $newndx = add_a_record(\%localdb,$rectype,\%rec);
$old_xref{$rectype}{$rec{'index'}} = $newndx;
}### Foreach record in file
foreach my $rec (@{$localdb{'log'}}) {
my $freqndx = $rec->{'_oldindex'};
if (!$freqndx) {next;}
if ($old_xref{'freq'}{$freqndx}) {
my $freqref = $old_xref{'freq'}{$freqndx};
foreach my $fld (@{$version1{'log'}}) {
if ($fld eq 'index') {next;}
my $value = $rec->{$fld};
if ((!$value) or (!looks_like_number($value))) {$value = 0;}
$localdb{'freq'}[$freqndx]{$fld} = $value;
}
}
else {
LogIt(1,"LOG record $rec->{'_recno'} references non-existant FREQ record! " .
"Record ignored.");
}
}### Log Record process
foreach my $rec (@{$localdb{'freq'}}) {
if (!$rec->{'index'}) {next;}
my $groupno = $rec->{'groupno'};
if ($groupno) {
if (!$old_xref{'group'}{$groupno}) {
LogIt(1,"FREQ record $rec->{'_recno'} references non-existant GROUP record!" .
"Changed to 0.");
$rec->{'groupno'} = 0;
}
else {
}
}
}### Checking all FREQ records for GROUP references
foreach my $rec (@{$localdb{'group'}}) {
if (!$rec->{'index'}) {next;}
my $sysno = $rec->{'sysno'};
if ($sysno) {
if (!$old_xref{'system'}{$sysno}) {
LogIt(1,"GROUP record $rec->{'_recno'} references non-existant SYSTEM record $sysno!" .
"Changed to 0.");
$rec->{'sysno'} = 0;
}
}
}### Checking all GROUP records for SYSTEM references
foreach my $rectype ('search',@non_indexed) {
foreach my $rec (@{$localdb{$rectype}}) {
if (!$rec->{'index'}) {next;}
my $recno = add_a_record($data,$rectype,$rec);
$rec->{'_found'} = TRUE;
}
}
my %xrefs = ();
my $channel = 0;
foreach my $rec (@{$data->{'freq'}}) {
if ($rec->{'frequency'} and $rec->{'channel'} and ($rec->{'channel'} > $channel) and (!$rec->{'siteno'})) {
$channel = $rec->{'channel'};
}
}
foreach my $rectype ('system','site','bplan','tfreq','group','freq') {
if (!defined $localdb{$rectype}[0]) {next;}
foreach my $rec (@{$localdb{$rectype}}) {
if (!$rec -> {'index'}) {next;}
my $oldndx = Strip($rec->{'_oldindex'});
if (!$oldndx) {
print Dumper($rec),"n";
LogIt(1,"READ_RADIOCTL l4746:No old index stored for this record type=>$rectype");
next;
}
my %newrec = ('_oldindex' => $oldndx);
my @verify = keys %{$rec};
foreach my $key (@verify) {
if ($key ne 'index') {$newrec{$key} = $rec->{$key};}
}
my $ref = 0;
my $field ='';
my $refrec = '';
if (($rectype eq 'site') or ($rectype eq 'group')) {
$refrec = 'system';
$field = 'sysno';
}
elsif (($rectype eq 'tfreq') or ($rectype eq 'bplan')) {
$refrec = 'site';
$field = 'siteno';
}
elsif ($rectype eq 'freq') {
$refrec = 'group';
$field = 'groupno';
}
my $ndx = $rec->{'index'};
if ($refrec) {
$ref = $newrec{$field};
$newrec{'_oldref'} = $ref;
if ($ref) {
if ($xrefs{$refrec}{$ref}) {### reference is OK
$newrec{$field} = $xrefs{$refrec}{$ref};
}
else {
my $msg = "Field '$Cyan$field$White' references non-existant $Yellow$refrec$White:" .
"$Green$ref$White in record $Cyan$rec->{'_recno'}$White in file:$Magenta$filespec$White";
LogRad(1,\%localdb,$rectype,$ndx,$msg);
$newrec{$field} = 0;
}
}### xref is NOT 0
else {
if (($field =~ /group/i) and ($rectype =~ /freq/i) and
(!$rec->{'frequency'}) ) {
}
else {
my $msg = "Field '$Cyan$field$White' is 0 or not set " .
"in file:$Magenta$filespec$White";
LogRad(1,\%localdb,$rectype,$ndx,$msg);
}
$newrec{$field} = 0;
}
if ($rectype eq 'freq') {
my $grpndx = $newrec{'groupno'};
if ($grpndx and $data->{'group'}[$grpndx]{'sysno'}) {
$newrec{'sysno'} = $data->{'group'}[$grpndx]{'sysno'};
}
else {$newrec{'sysno'} = 0;}
}
elsif ($rectype eq 'bplan') {
my $siteref = $newrec{'siteno'};
if ($siteref) {
if ($data->{'site'}[$siteref]{'bplan'}) {
my $msg ="Multiple$Cyan BPLAN$White records assigned to a site! " .
" Second assignment nullified!";
LogRad(1,\%localdb,'bplan',$ndx,$msg);
$newrec{'siteno'} = 0;
}
else {
$data->{'site'}[$siteref]{'bplan'} = $rec->{'index'};
my $sysno = $data->{'site'}[$siteref]{'sysno'};
my $systype = $data->{'system'}[$sysno]{'systemtype'};
if (lc($systype) ne 'motc') {
LogIt(1,"READ_RADIOCTL l4067:Record $rec->{'_recno'}" .
" System/Site Referenced by BPLAN record is not 'MOTC' system type");
}
}
}### if a site is referenced
}## bplan checks
}
my $newindex  = add_a_record($data,$rectype,\%newrec);
$xrefs{$rectype}{$oldndx} = $newindex;
if ($rectype eq 'bplan') {
}
}### for each record in this record type
}### for each record type
return $retcode;
}
sub read_line {
my $line = shift @_;
my $outrec = shift @_;
my $version = shift @_;
my $errinfo = '';
if ($outrec->{'_recno'} and $outrec->{'_filespec'}) {
$errinfo = " in record $outrec->{'_recno'}  for $outrec->{'_filespec'}";
}
my $comment = '';
if ($line =~ /\#/) {($line,$comment) = split '#',$line,2;}
$outrec->{'_line_comment'} = $comment;
my @flds = split ',',$line;
my $rectype = lc(Strip(shift @flds));
$rectype =~ s/\"//g;  
$rectype =~ s/\'//g;
my $fieldref = $version->{$rectype};
if (!$fieldref) {
LogIt(1,"READ_RADIOCTL l4017:Unknown record type $rectype$errinfo!");
return $ParmErr;
}
$outrec->{'_rectype'} = $rectype;
$outrec->{'_format'} = 1;
if ($flds[0] =~ /\=/) {  
while (scalar @flds) {
my ($key,$value) = split '=',shift @flds,2;
$outrec->{Strip(lc($key))} = Strip($value);
}
$outrec->{'_format'} = 4;
}### keyword=value format
else {
foreach my $key (@{$fieldref}) {
if (scalar @flds) {
my $value = Strip(shift @flds);
$outrec->{$key} = $value;
}
else {last;}
}
}### positional key process
return $GoodCode;
}
sub add_a_record {
my $data = shift @_;
my $rectype = shift @_;
my $rec = shift @_;
my $gui = shift @_;
my ($package, $filename, $line) = caller;
my $reftype = ref($data);
if ($reftype ne 'HASH') {LogIt(2536,"ADD_A_RECORD:Data is not a hash reference. Type=$reftype Caller=>$line");}
if (!$rectype) {LogIt(2537,"ADD_A_RECORD:Forgot rectype. Caller=>$line");}
$reftype = ref($rec);
if ($reftype ne 'HASH') {LogIt(2536,"ADD_A_RECORD:REC is not a hash reference. Type=$reftype Caller=>$line");}
foreach my $key (keys %structure) {
if ((! defined $data->{$key}) or (scalar @{$data->{$key}} < 1)) {
$data->{$key}[0] = ({%dummy_record});
}
}
my %record = %$rec;
KeyVerify(\%record,@{$structure{$rectype}});
$record{'_rectype'} = $rectype;
my $recno = (push @{$data->{$rectype}},{%record}) - 1;
$data->{$rectype}[$recno]{'index'} = $recno;
if ($gui) {
my %parms = ('_dbn' => $rectype, '_seq'=> $recno, '_caller' => 'add_a_record');
foreach my $key (keys %record) {
$parms{$key} = $record{$key};
}
$gui->(\%parms);
}
return $recno;
}
sub AutoMode   {
my $freq = shift @_;
if (!$freq) {return 'FMn';}
if (!looks_like_number($freq)) {
my ($pkg,$fn,$caller) = caller;
LogIt(4827,"AUTOMODE:Non-numeric frequency=$freq Caller=>$fn:$caller");}
if ($freq < 30000000) {return 'AM';}
elsif (($freq >= 88000000) and ($freq <= 108000000)) {return 'FMw';}
elsif (($freq > 108000000) and ($freq <= 138000000)) {return 'AM';}
else {return 'FMn';}
}
sub KeyVerify  {
my $blk = shift @_;
if (!$blk) {LogIt(1941,"KeyVerify: No hash reference passed!");}
my @keylist = @_;
my %original = %{$blk};
my $retcode = 0;
my ($pkg,$fn,$caller) = caller;
my $lineno = " (caller:$fn ln:$caller)";
if ($blk->{'_recno'}) {$lineno = "In file record number $Green$blk->{'_recno'}$White (caller=$fn-$caller)";}
if (defined $blk->{'atten'}) {$blk->{'att_amp'} = 'Off';}
foreach my $key (@keylist) {
if (!$key) {next;}
if ($key eq 'rsvd') {next;}
if ($key =~ /^\_.*$/) {next;}  
if ($key =~ /att_amp/i) {next;} 
if (!defined $struct_fields{$key}) {
LogIt(5,"Key $Red$key$White not in struct_fields $lineno! Not processed!");
if (!defined $blk->{$key}) {$blk->{$key} = '';}
next;
}
my $default = $struct_fields{$key}[3];
my $dflt_msg = $default;
if ($default eq '') {$dflt_msg = '(blank)';}
my $type = $struct_fields{$key}[0];
my $fld_flag = $struct_fields{$key}[2];
my $fld_min = $struct_fields{$key}[4];
my $fld_max = $struct_fields{$key}[5];
my $blank_ok   = !($fld_flag =~ /b/);### if 'b' found, blank is NOT ok
my $any_ok     = $fld_flag =~ /a/;   
my $upper_req  = $fld_flag =~ /u/;   
my $first_char = $fld_flag =~ /f/;   
if (defined $blk->{$key}) {
if ($upper_req) {$blk->{$key} = uc($blk->{$key});}
if ($any_ok) {next;}
my $to_check = Strip(lc($blk->{$key}));
if (($to_check eq '.') or ($to_check eq '-')) {$to_check = '';}
if ($blank_ok and ($to_check eq '')) {next;}
my @add_values = ();
if ($struct_fields{$key}[7]) {
my $lastndx = $#{$struct_fields{$key}};
@add_values = @{$struct_fields{$key}}[7..$lastndx];
}
if (($type eq 'c') or ($type eq 'g')) {
if ($to_check eq '') {### blank field
if ($blank_ok) {next;}
else {
LogIt(1,"L4953: $Red$to_check$White a blank is not valid for " .
"$Magenta$key$White\n  $lineno$Eol" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$retcode = 1;
$blk->{$key} = $default;
}
}
else {
my $value_ok = FALSE;
my $opt = '';
if ($upper_req) {$opt = 'u';}
if ($first_char) {$to_check = substr($to_check,0,1);}
foreach my $cmp (@add_values) {
my ($bad,$new) = str_cmpr($to_check,Strip($cmp),$opt);
if (!$bad) {
$blk->{$key} = $new;
$value_ok = TRUE;
last;
}
}## Look at additional values
if (!$value_ok) {
$blk->{$key} = $default;
LogIt(1,"RADIOCTL,PM L5010: $Red$to_check$White is not a valid string or character for " .
"$Magenta$key$White\n  $lineno$Eol" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
print "Add values=>@add_values\n";
$retcode = 1;
}### bad value in field
}##### non-blank field test
}#### character process
elsif ($type eq 'b') {
$blk->{$key} = TrueFalse($blk->{$key});
if ($key eq 'atten') {
if ($blk->{$key}) {$blk->{'att_amp'} = 'atten';}
}
elsif ($key eq 'preamp') {
if ($blk->{$key}) {$blk->{'att_amp'} = 'pamp';}
}
}
elsif ($type eq 'f') {### Frequency
if (looks_like_number($to_check)) {
if ($to_check =~ /\./) { 
$to_check = freq_to_rc($to_check);
$blk->{$key} = $to_check;
}
if (($to_check < $fld_min) or ($to_check >$fld_max)) {
LogIt(1,"L5908: $Red$to_check$White is not a valid frequency for " .
"$Magenta$key$White\n  $lineno$Eol" .
"  Allowed range is $Bold$Yellow$fld_min$Reset to $Bold$Yellow$fld_max$Reset  " .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$retcode = 1;
$blk->{$key} = $default;
}
}### number passed
elsif (!$to_check) {
$blk->{$key} = $default;
}
else {
my $value_ok = FALSE;
my $opt = '';
if ($upper_req) {$opt = 'u';}
if ($first_char) {$to_check = substr($to_check,0,1);}
foreach my $cmp (@add_values) {
my ($bad,$new) = str_cmpr($to_check,Strip($cmp),$opt);
if (!$bad) {
$blk->{$key} = $new;
$value_ok = TRUE;
last;
}
}
if (!$value_ok) {
LogIt(1,"L5074: $Red$to_check$White is not numeric for " .
"$Magenta$key$White\n  $lineno$Eol" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$retcode = 1;
$blk->{$key} = $default;
}### Bad value, set default
}### Not a number
}### frequency check
elsif (($type eq 'n') or ($type eq 'i')) {
if ($key eq 'qkey') {
if (!looks_like_number($to_check)) {
$to_check = $default;
}
}
if (looks_like_number($to_check)) {
my $outarange = FALSE;
if (!looks_like_number($fld_min)) {
print "RADIOCTL.PM l5189:Non-Numeric fld_min for $key\n";exit;
}
if (($fld_min ne '.') and ($to_check < $fld_min)) {$outarange = TRUE;}
if (($fld_max ne '.') and ($to_check > $fld_max)) {$outarange = TRUE;}
if ($outarange) {
LogIt(1,"L5107: $Red$to_check$White is an out-of-range number for " .
"$Magenta$key$White\n  $lineno$Eol" .
"  Allowed range is $Bold$Yellow$fld_min$Reset to $Bold$Yellow$fld_max$Reset  " .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$retcode = 1;
$blk->{$key} = $default;
}
if (($type eq 'i') and looks_like_number($blk->{$key})) {
$blk->{$key} = int($blk->{$key});
}
}
elsif ($key eq 'channel') {
if (looks_like_number(substr($to_check,1))) {
$blk->{$key} = $to_check;
}
else {
LogIt(1,"L5378: $Red$to_check$White is not numeric or acceptable text for " .
"$Magenta$key$White\n  $lineno$Eol" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$retcode = 1;
$blk->{$key} = $default;
}
}#### channel
else {
my $value_ok = FALSE;
my $opt = '';
if ($upper_req) {$opt = 'u';}
if ($first_char) {$to_check = substr($to_check,0,1);}
foreach my $cmp (@add_values) {
my ($bad,$new) = str_cmpr($to_check,Strip($cmp),$opt);
if (!$bad) {
$blk->{$key} = $new;
$value_ok = TRUE;
last;
}
}### Look at aditional values
if (!$value_ok) {
if ($to_check) {
LogIt(1,"L5140: $Red$to_check$White is not numeric or acceptable text for " .
"$Magenta$key$White\n  $lineno$Eol" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$retcode = 1;
}
$blk->{$key} = $default;
}
}
}
elsif ($type eq 'x') {
if ($to_check =~ /[0-9A-F]/i) {
if ($key eq 'custmap') {
if (($to_check =~ /[0-9A-E]/i) and (length($to_check) == 8)) {
$blk->{$key} = $to_check;
}
else {
LogIt(1,"=>$Red$to_check$White<= Is not valid for " .
"$Magenta$key$White\n  $lineno$Eol" .
"   Must be 8 chars hex 0-E.\n" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$blk->{$key} = $default;
}
}### Custmap process
else {
my $dec = hex($to_check);
if ($dec > $fld_max) {
$blk->{$key} = sprintf("%x",$fld_max);
LogIt(1,"$Red$to_check$White Is too large for " .
"$Magenta$key$White\n  $lineno$Eol" .
"   Must be less than or equal to $blk->{$key}\n",
"    Changed to =>$Bold$Green$blk->{$key}$Eol");
}### Too Big
elsif ($dec < $fld_min) {
$blk->{$key} = sprintf("%x",$fld_min);
LogIt(1,"$Red$to_check$White Is too small for " .
"$Magenta$key$White\n  $lineno$Eol" .
"   Must be greater than or equal to $blk->{$key}\n",
"    Changed to$Bold$Green$blk->{$key}");
}### Too Small
else {
$blk->{$key} = $to_check;
}### Just right
}
}
else {
LogIt(1,"$Red$to_check$White Is not valid hex for " .
"$Magenta$key$White\n  $lineno$Eol" .
"    Changed to =>$Bold$Green$dflt_msg$Eol");
$blk->{$key} = $default;
}
}#### Hexadecimal check
elsif ($type eq 'l') {
if ($to_check =~ /a/i) {$blk->{$key} =~ s/m//gi;}
elsif ($to_check =~ /m/i) { $blk->{$key} =~ s/a//gi;  }
}
elsif ($type eq 's') {$blk->{$key} = ''; }
elsif ($type eq 't') {
}
elsif ($type eq 'o') {
}### Tone value checking
elsif ($type eq 'r') {
if ($to_check) {
my ($dec,$dms) = Lat_Lon_Parse($to_check,$key);
if (!$dec) {
LogIt(5,"=>$Yellow$to_check$White is not a valid value for $key $lineno. Changed to blank!");
$retcode = 1;
$blk->{$key} = '';
}
else {$blk->{$key} = $dec;}
}
}### Ordinal value checking
else {LogIt(2973,"KEYVERIFY:No type process for type $Red$type$White key=$Yellow$key$White $lineno");}
}### Field defined
else {
$blk->{$key} = $default;
}
}
return $retcode;
}
sub spec_read {
my %val_check = (#'maxchan' => {'min' => 1,'max' => MAXCHAN},
);
my $filespec = shift @_;
if (!$filespec) {LogIt(3913,"SPEC_READ:What happened to the radio definition spec?");}
my @input = ();
my $retcode = ConfigFileProc($filespec,\@input,'p','c');
if ($retcode) {
if ($retcode == 1) {
LogIt(1,"RADIOCTL.PM l3739:SPEC_READ:Config file $filespec was not found!");
return $retcode;
}
elsif ($retcode == 2) {
LogIt(1,"RADIOCTL.PM l3743:SPEC_READ:Could not read config file $filespec!");
return $retcode;
}
else {
foreach my $rcd (@input) {
if ($rcd->{'errmsg_'}) {LogIt(0,$rcd->{'errmsg_'});}
}
}
}### file failed something
foreach my $rcd (@input) {
my %values = ();
my $rectype = '';
foreach my $num (keys %{$rcd}) {
if ($num eq '0001') {$rectype = lc($rcd->{$num});}
elsif ($num =~ /\_/) {   
$values{$num} = $rcd->{$num};
}
elsif ($rcd->{$num} =~ /\=/) {  
my ($key,$value) = split '=',$rcd->{$num},2;
if ($key =~ /freq/) {
if (looks_like_number($value)) {$value = freq_to_rc($value);}
}### freq convert
$values{lc(Strip($key))} = Strip($value);
}
else {
print Dumper($rcd),"\n";
LogIt(4440,"Unable to deal with record key $num");
}
}
my $recno = $values{'recno_'};
if ($rectype eq 'radio') {
my $name = $values{'name'};
my $proto = $values{'protocol'};
if (!$name) {
LogIt(0,"$Bold$Red ERROR!$White " .
"No name key specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
if (!$proto) {
LogIt(0,"$Bold$Red ERROR!$White " .
"No protocol key specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
if (!$valid_protocols{Strip(lc($proto))}) {
LogIt(0,"$Bold$Red ERROR!$White " .
"Invalid protocol $proto specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
$name = lc($name);
$All_Radios{$name}{'realname'} = $values{'name'};
$All_Radios{$name}{'baudrate'} = '';
$All_Radios{$name}{'port'} = '';
$All_Radios{$name}{'chanper'} = '100';
$All_Radios{$name}{'sdir'} = "$homedir/radioctl";
$All_Radios{$name}{'model'} = '';
$All_Radios{$name}{'radioaddr'} = '08';
foreach my $key (keys %values) {
if ($key =~ '_') {next;}  
my $value = $values{$key};
if ($val_check{$key}) {
my $min = $val_check{$key}{'min'};
my $max = $val_check{$key}{'max'};
if (!looks_like_number($value) or ($value < $min) or ($value > $max)) {
LogIt(0,"$Bold$Red Error! '$Magenta$value$White'" .
"is not a number between $Red$min$White and $Red$max$White for $Blue$key$White in line ".
"$Green$recno$White of $Yellow$filespec$White!");
$retcode = 3;
next;
}
$All_Radios{$name}{$key} = $value;
}
elsif ($key eq 'baudrate') {
if (!defined $baudrates{lc($value)}) {
LogIt(0,"$Bold$Red Error! '$Magenta$value$White'" .
" is not a valid baudrate in line ".
"$Green$recno$White of $Yellow$filespec$White!");
$retcode = 3;
next;
}
}
elsif (($key eq 'sdir') and (! -d $value) ) {
LogIt(0,"$Bold$Red Error! $Blue$key$White " .
"'$Magenta$value$White' does not exist or is not a directory in line ".
"$Green$recno$White of $Yellow$filespec$White!");
$retcode = 3;
next;
}
else {$All_Radios{$name}{$key} = $value;}
}### foreach key
}### Radio definition record
elsif ($rectype eq 'directory') {
foreach my $key (keys %values) {
if ($key =~ /\_/) {next;}  
my $dir = $values{$key};
if (substr($dir,0,1) ne '/') {
LogIt(0,"$Bold$Red Error! Absolute path required for $Blue$dir$White " .
" in line $Green$recno$White of $Yellow$filespec$White!");
$retcode = 3;
next;
}
my $rc = DirExist($dir,TRUE);
if ($rc) {
LogIt(1,"Specified directory $Blue$dir$White " .
" in line $Green$recno$White of $Yellow$filespec$White" .
" does not exist, cannot be created, or is not writable!\n" .
" Value is ignored ");
next;
}
$settings{$key} = $dir;
print "Set $key to $dir\n";
}
}### Directory record
elsif ($rectype eq 'location') {
my $name = $values{'name'};
my $lat = $values{'lat'};
my $lon = $values{'lon'};
if (!$name) {
LogIt(0,"$Bold$Red ERROR!$White " .
"No NAME key specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
if (!$lat) {
LogIt(0,"$Bold$Red ERROR!$White " .
"No LAT key specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
if (!$lon) {
LogIt(0,"$Bold$Red ERROR!$White " .
"No LON key specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
my ($latdec,$latdms) = Lat_Lon_Parse($lat,'lat');
if (!$latdec) {
LogIt(0,"$Bold$Red ERROR!$White " .
"Bad value for LAT=$Cyan$lat$White specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
my ($londec,$londms) = Lat_Lon_Parse($lon,'lon');
if (!$londec) {
LogIt(0,"$Bold$Red ERROR!$White " .
"Bad value for LON=$Cyan$lon$White specified in line $Green$recno$White of $Yellow$filespec$White! Line Ignored.");
$retcode = 3;
next;
}
$known_locations{lc($name)} = {'lat' => $latdec, 'lon' => $londec};
}### Location record
else {
LogIt(0,"$Bold$Red Error! No process defined for record type:$Blue$rectype$White " .
" in line $Green$recno$White of $Yellow$filespec$White!");
$retcode = 3;
next;
}
}## For Each record
if ($retcode) {LogIt(4570,"Config file $filespec. Retcode=$retcode. Please fix config file errors before restarting");}
return 0;
}
sub no_quotes {
my $value = shift @_;
if ($value =~ /\"/) {   
my ($newvalue) = $value =~ /\".*?\"/;
if ($newvalue) {$value = $newvalue;}
}
if ($value =~ /\'/) {
my ($newvalue) = $value =~ /\'(.*?)\'/;
if ($newvalue) {$value = $newvalue;}
}
return $value;
}
sub add_message {
my $msg = shift @_;
my $severity = shift @_;
if (!$severity) {$severity = 0;}
if ($severity == 1) {LogIt(1,"$Bold$Red$msg");}
elsif ($severity == 2) {LogIt(0,"$Bold$Green$msg");}
else {LogIt(0,$msg);}
lock @messages;
push @messages,"$severity,$msg";
}
sub LogRad  {
my ($pkg,$fn,$caller) = caller;
my $sev = shift @_;
if (!$sev) {$sev = 0;}
my $db = shift @_;
if (!$db) {LogIt(5192,"LogRad missing database reference! caller=>$fn line:$caller");}
my $rectype = shift @_;
if (!$db) {LogIt(5194,"LogRad missing record type! caller=>$fn line:$caller");}
my $index = shift @_;
if (!$index) {LogIt(5197,"LogRad missing index! caller=>$fn line:$caller");}
my $msg = shift @_;
if (!$msg) {$msg = '';}
if ($sev == 1) {print STDERR "$Eol$Bold$Yellow Warning:$Reset";}
elsif ($sev > 1) {print STDERR "$Eol$Bold$Red ERROR:$Reset";}
print STDERR "l$caller ";
my $recno = $db->{$rectype}[$index]{'_recno'};
if (!$recno) {$recno = '(n/a)';}
my $service = $db->{$rectype}[$index]{'service'};
if (!$service) {$service = '(n/a)';}
my $sysname = '';
my $sysno = 0;
my $grpno = 0;
my $grpname = '';
my $siteno = 0;
my $sitename = '';
print STDERR "$Reset";
if ($rectype eq 'system') {
}
elsif (($rectype eq 'group') or ($rectype eq 'site')) {
$sysno = $db->{$rectype}[$index]{'sysno'};
if( $sysno) {
$sysname = $db->{'system'}[$sysno]{'service'};
if (!$sysname) {$sysname = '(n/a)';}
}
}
elsif (($rectype eq 'tfreq') or ($rectype eq 'bplan')) {
$siteno = $db->{$rectype}[$index]{'siteno'};
if( $siteno) {
$sitename = $db->{'site'}[$siteno]{'service'};
if (!$sitename) {$sitename = '(n/a)';}
}
}
elsif ($rectype eq 'freq') {
my $grpno =  $db->{$rectype}[$index]{'groupno'};
if ($grpno) {
$grpname =  $db->{'group'}[$grpno]{'service'};
if (!$grpname) {$grpname = '(n/a)';}
}
}
print STDERR "rcd:$Magenta",sprintf("%-5.5s",$recno),"$Reset ";
print STDERR sprintf("%7.7s",$rectype),":$Yellow",sprintf("%-15.15s",$service),"$Reset ";
print STDERR "(ndx:$Green",sprintf("%-4.4u",$index),")$Reset ";
if ($sysno) {
print STDERR "System:$Cyan",sprintf("%-15.15s",$sysname),
"$Reset ($Green",sprintf("%-5.5u",$sysno),"$Reset) ";
}
if ($grpno) {
print STDERR "Group:$Cyan",sprintf("%-15.15s",$grpname),
"$Reset ($Green",sprintf("%-5.5u",$grpno),"$Reset) ";
}
if ($siteno) {
print STDERR "Site:$Cyan",sprintf("%-15.15s",$sitename),
"$Reset ($Green",sprintf("%-5.5u",$siteno),"$Reset) ";
}
if ($sev) {print STDERR "$Bold";}
if ($msg) { print STDERR "$msg$Eol";}
if ($sev > 2) {exit 3;}
return 0;
}
sub write_log {
my $ref = shift @_;
if (!$ref) {LogIt(5845,"WRITE_LOG:No record given!");}
my $logdir = $settings{'logdir'};
my $logfile = "$logdir/$Logfile_Name";
my @rec_fields = ('time_stamp',
'frequency_mhz',
'mode','duration','signal','rssi','channel','service');
my $newfile = FALSE;
if (!-e  $logfile) {
$newfile = TRUE;
}
if (open LOGFILE,">>$logfile") {
if ($newfile) {
my $outrec = "#";
foreach my $fld (@rec_fields){$outrec = "$outrec$fld,";}
print LOGFILE "$outrec\n";
}
$ref->{'time_stamp'} = Time_Format();
if ($ref->{'frequency'}) {
$ref->{'frequency_mhz'} = rc_to_freq($ref->{'frequency'});
}
else  {$ref->{'frequency_mhz'} = '';}
my $outrec = '';
foreach my $fld (@rec_fields) {
if ($ref->{$fld}) {
$outrec = $outrec . $ref->{$fld}
}
$outrec = "$outrec,";
}
print LOGFILE "$outrec\n";
close LOGFILE;
}
else {
LogIt(1,"WRITE_LOG:Could not open $Yellow$logfile!");
return 2;
}
return 0;
}
sub str_cmpr {
my $to_check = shift @_;
my $cmp = shift @_;
my $opt = shift @_;
if (!$opt) {$opt = '';}
my $trunc = FALSE;
if ($opt =~ /e/i) {$trunc = TRUE;}
my $case = FALSE;
if ($opt =~ /c/i) {$case = TRUE;}
if (!$cmp) {
my ($pkg,$fn,$caller) = caller;
LogIt(1,"Null compare string in RADIOCTL.PM:STR_CMP. Caller=>$fn $caller");
return 0;
}
if ($opt =~ /u/i) {
$to_check = uc($to_check);
$cmp = uc($to_check);
}
if ($to_check eq '') {return 0,$to_check;}
if ($to_check eq '*') {return 1;}
my $l = length $cmp;
if ($trunc and ((length $to_check) > $l)) {
$to_check = substr($to_check,0,$l);
}
if ($case) {
if ($cmp ne $to_check) {return 1;}
}
else {
if (lc($cmp) ne lc($to_check)) {return 1;}
}
return 0,$to_check;
}
sub Tone_Xtract {
my $sqtone = shift @_;
my ($pkg,$fn,$caller) = caller;
if (!$sqtone) {return ('',0);}
if ($sqtone =~ /off/i) {return ('Off',0);}
if (length($sqtone) < 4) {
LogIt(1,"Bad tone $sqtone passed to Tone_Xtract! Caller=$caller");
return ('Off',0);
}
my $tt = substr($sqtone,0,3);
if (!$tn_type{lc(Strip($tt))}) {
LogIt(1,"Bad tone type $sqtone passed to Tone_Xtract! Caller=$caller");
return ('Off',0);
}
my $tone = substr($sqtone,3);
if (($tt =~ /ctc/i) or ($tt =~ /rpt/i)) {$tone = Strip(sprintf("%4.1f",$tone));}
elsif ($tt =~ /dcs/i) {$tone = sprintf("%03.3u",$tone)}
else {
}
return ($tt,$tone);
}
sub TrueFalse {
my $str = shift @_;
my $ret = 1;
if ($str) {$str = Strip(lc($str));}
if (!$str) {$ret = 0;}
elsif ($str eq 'no') {$ret = 0;}
elsif ($str eq 'n') {$ret = 0;}
elsif ($str eq 'false') {$ret = 0;}
elsif ($str eq 'f') {$ret = 0;}
elsif ($str eq 'off') {$ret = 0;}
return $ret;
}
sub check_range {
my $freq = shift @_;
my $ref = shift @_;
if (!$ref) {LogIt(6672,"CHECK_RANGE:No reference to limits passed!");}
if (!$ref->{'minfreq'}) {
return FALSE;}
if ( ($freq < $ref->{'minfreq'}) or ($freq > $ref->{'maxfreq'})) {
return FALSE;
}
foreach my $gap (1,2,3,4,5,6) {
my $low_key = "gstart_$gap";
my $high_key = "gstop_$gap";
if (!$ref->{$low_key}) {return TRUE;}
if (($freq >= $ref->{$low_key}) and ($freq < $ref->{$high_key})) {
return FALSE;
}
}
return TRUE;
}
sub DebugIt {
my $msg = shift @_;
my ($package,$caller,$line) = caller();
my $homedir = $ENV{"HOME"};
if (!-d "$homedir/radioctl") {mkdir "$homedir/radioctl";}
my $fn = "$homedir/radioctl/debug.txt";
if ($msg) {
if (open DEBUG,">>$fn") {
print DEBUG "$caller:$line:$msg\n";
close DEBUG;
}
}
return 0;
}
use Scalar::Util qw(looks_like_number);
sub Lat_Lon_Parse {
my $instr = shift @_;
my $type = shift @_;
my $debug = shift @_;
if (!$debug) {$debug = 0;}
my ($pack,$file,$line) = caller();
my $msg = "Given To Lat_Lon_Parse. Caller=$line\n";
if (!$instr) {
if ($debug) {print STDERR "No input $msg";}
return 0;
}
if ($type) {
$type = lc($type);
if ( ($type ne 'lat') and ($type ne 'lon')) {
if ($debug) {print STDERR "Invalid type:$type $msg";}
$type = '';
}
}
else {$type = '';}
my $num = 0;
my $dir = '';
if ($instr =~ /\:/) {
my ($deg,$min,$sec,$indir) = split ':',$instr;
if (!$deg) {
if ($debug) {print STDERR "Input:$instr. DMS 0 degrees $msg";}
return 0;
}
if ( (!looks_like_number($deg)) or ($deg > 180)) {
if ($debug) {print STDERR "Input:$instr. Invalid Deg=$deg $msg";}
return 0;
}
if (!$min) {$min = 0;}
if ((!looks_like_number($min) or ($min > 60))) {
if ($debug) {print STDERR "Input:$instr. Invalid Min=$min $msg";}
return 0;
}
if (!$sec) {$sec = 0;}
if ((!looks_like_number($sec) or ($sec > 60))) {
if ($debug) {print STDERR "Input:$instr.  Invalid Sec=$sec $msg";}
return 0;
}
if ($indir and ($indir !~ /[nesw]/i)) {
if ($debug) {print STDERR "Input:$instr. Invalid direction $indir $msg";}
return 0;
}
if (!$indir) {
if ($type eq 'lon') {$indir = 'W';}
else {$indir = 'N';}
}
$dir = uc($indir);
if ($type) {
if (($type eq 'lon') and ($dir =~ /[ns]/i)) {
if ($debug) {print STDERR "Input:$instr.  Invalid dir=$dir for type=$type $msg";}
return 0;
}
if (($type eq 'lat') and ($dir =~ /[ew]/i)) {
if ($debug) {print STDERR "Input:$instr.  Invalid dir=$dir for type=$type $msg";}
return 0;
}
}
else {
if ($dir =~ /[ns]/i) {$type = 'lat';}
else {$type = 'lon';}
}
$num = $deg +  ($min/60) + ($sec/3600);
$num = sprintf("%8.6f",$num);
if ($num and ($dir =~ /[sw]/i))  {$num = "-$num";} 
}
else {
if ((!looks_like_number($instr)) or (abs($instr) > 180)) {
if ($debug) {print STDERR "Invalid Decimal=$instr $msg";}
return 0,'';
}
$instr =~ s/^\s+//;      
$instr =~ s/\s+$//;      
$num = $instr;
if ($num < 0) {
if ($type eq 'lat') {$dir = 'S';}
else {$dir = 'W';}
}
else {
if ($type eq 'lon') {$dir = 'E';}
else {$dir = 'N'};
}
}
my ($deg,$mmm) = $num =~ /(\d*?)(\.\d*)/;
if (!$deg) {$deg = 0;}
if (!$mmm) {$mmm = 0;}
my $m2 = $mmm * 60;
my ($min,$sec) = $m2 =~ /(\d*?)(\.\d*)/;
if (!$min) {$min = 0;}
if (!$sec) {$sec = 0;}
$sec = $sec * 60;
$sec = sprintf("%4.2f",$sec);
my $dms = abs($deg) . ":$min:$sec:$dir";
return $num,$dms;
}
sub Strip {
my ($string) = @_;
if (! defined $string) {return '';}
$string =~ s/^\s+//;      
$string =~ s/\s+$//;      
return $string;
}
sub Parms_Parse {
use Getopt::Std;
use Getopt::Long;
my $nodie = 0;
my $winok = 0;
my $rootonly = 0;
my $retcode = 0;
foreach my $keyword (@_) {
if (lc($keyword) eq 'nodie') {$nodie = 1;}
elsif (lc($keyword) eq 'winok') {$winok = 1;}
elsif (lc($keyword) eq 'root') {$rootonly = 1;}
else {
print STDERR "$Bold Logic error! Invalid keyword $keyword for Parms_Parse$Eol";
exit 9999;
}
}
if ((!$winok) and (substr($^O,0,3) eq 'MSW')) {
print STDERR "!!!!!#### This routine cannot be run on Windows!\n";
exit 9999;
}
Getopt::Long::Configure ("bundling");
my @wmsg;
$SIG{'__WARN__'} = sub {
push @wmsg,@_;
};
my $rtc = GetOptions(%Options);
if (!$rtc) {
foreach my $m (@wmsg) {
if (lc(substr($m,0,7)) eq 'unknown') {
print STDERR "$Bold Ignoring $m $Eol";
$retcode = 1;
}
else {
print STDERR "$Bold Parms_Parse:Error parsing options!$Eol";
if ($nodie) {$retcode = 2;}
else {exit 2048;}
}
}
}
$SIG{'__WARN__'} = 'DEFAULT';
if ($rootonly) {
(my $name,) = getpwuid $<;
if ($name ne 'root') {
print STDERR "$Bold ## ERROR! This routine MUST be run as ROOT!$Eol";
exit 9999;
}
}
return $retcode;
}
sub LogIt {
use Scalar::Util qw(looks_like_number);
use Sys::Syslog;
use Sys::Syslog qw(:standard :macros);
my $sev = shift @_;
my $msg = shift @_;
if (!$msg) {$msg = '';}
my ($pack,$file,$line) = caller();
my @spl = split '/',$file;
$file = pop @spl;
my $callinfo = "$Magenta$file$White line $Green$line$White:";
my $callnoansi = "$file line $line:";
if (!looks_like_number($sev)) {
print STDERR "$Bold$Red** Check caller of Logit. Forgot Code number! $callinfo$Eol";
exit 9999;
}
my $noansi = $msg;
$noansi =~ s/\x1b\[[^m]+m//g;
if ($sev == 0) {
print STDOUT "$White$msg$Eol";
push @Info_Log,"$noansi\n";
}
elsif ($sev == 1) {
print STDOUT "$Bold$Yellow Warning! $White$msg$Eol";
push @Warning_Log,"*Warning! $noansi\n";
}
elsif ($sev == 2) {
print STDERR $Bold,$Red,"Error$White! $callinfo=>$msg$Eol";
push @Error_Log,"**Error! $callnoansi=>$noansi\n";
}
elsif ($sev ==3) {
print STDERR "$White$msg$Eol";
push @Info_Log,"$noansi\n";
}
elsif ($sev == 4) {
print STDERR "$callinfo=>$msg$Eol";
push @Info_Log,"$callnoansi=>$noansi\n";
}
elsif ($sev == 5) {
print STDOUT "$Bold$Yellow Warning!$White $callinfo=>$White$msg$Eol";
push @Warning_Log,"*Warning! $noansi\n";
}
elsif ($sev == 6) {
print STDOUT time() . ": $White$msg$Eol";
push @Info_Log,time() . ": $noansi\n";
}
elsif ($sev < 10) {
print STDERR "$Bold$Red**Error! $White Check caller of Logit. Used reserved code number $Red$sev$White $callinfo$Eol";
exit 9999;
}
else {
print STDERR $Bold,$Red,"** ERROR $sev$White! $callinfo=>$msg$Eol";
syslog(LOG_ERR,"***Error $sev! $callnoansi=>$noansi");
print STDERR "script is terminated!$Eol";
exit $sev;
}
return $sev;
}
sub Time_Format {
use Scalar::Util qw(looks_like_number);
my $mtime = shift @_;
if (!$mtime) {$mtime = time();}
if (!looks_like_number($mtime)) {
my ($package,$filename,$line) = caller();
print STDERR "$Bold Non-Numeric time value $mtime passed to Time_Format. Caller=$filename line=$line!$Eol";
return '??/??/?? ??:??';
}
my $keyword = shift @_;
if (!$keyword) {$keyword = 'default';}
else {$keyword = lc($keyword);}
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
localtime($mtime);
$mon = sprintf("%2.2u",$mon+1);
$mday = sprintf("%2.2u",$mday);
my $ampm = '';
if ($keyword ne '24hour') {
$ampm = 'am';
if ($hour < 1) {$hour = 12;}
elsif ($hour < 12) {$ampm = 'am';}
else {
$ampm = 'pm';
if ($hour > 12) {$hour = $hour-12;}
}
}
$year = $year + 1900;
my $dt = "$mon/$mday/$year" ;
my $tm = sprintf("%2.2u",$hour) . ':' . sprintf("%2.2u",$min) . $ampm;
my $return = "$dt $tm";
if ($keyword eq 'time') {$return = $tm;}
elsif ($keyword eq 'date') {$return = $dt;}
elsif ($keyword eq 'dyear') {$return = "$year$mon$mday"; }
elsif ($keyword eq 'uyear') {$return =  $year . '_' . $mon . '_' . $mday;}
elsif ($keyword eq 'year') {$return = $year;}
else {$return = "$dt $tm";}
return $return;
}
sub ConfigFileProc {
my ($filespec,$array,$dtype,$dlm,$validate) =  @_;
if (!$filespec) {
print "$Bold$Red Error!$White No filespec passed to ConfigFileProc!$Eol";
exit 9999;
}
if (!$array) {
print "$Bold$Red Error!$White No array reference passed to ConfigFileProc!$Eol";
exit 9999;
}
if (!-e $filespec) {
return 1;
}
my $errmsgkey = 'errmsg_';
my $recnokey = 'recno_';
my $linekey = 'line_';
my $delim = ' ';
my $type = '';
if ($dtype) {
if ($dtype eq '-') { }
elsif ($dtype eq 'k') {$type = 'k';}
elsif ($dtype eq 'p') {$type = 'p';}
else {
print "$Bold$Red Error!$White Invalid config type spec $dtype in ConfigFileProc!$Eol";
exit 9999;
}
}
if ($dlm) {
if ($dlm eq '-') {  }
elsif ($dlm eq 'c') {$delim = ',';}
elsif ($dlm eq 'b') {$delim = ' ';}
else {
print "$Bold$Red Error!$White Invalid delimiter spec $dlm in ConfigFileProc!$Eol";
exit 9999;
}
}
my @rcds = ();
if (open INFILE,"$filespec") {
@rcds = <INFILE>;
close INFILE;
}
else {
return 2;
}
my $recno = 0;
my $retcode = 0;
foreach my $rcd (@rcds) {
$recno++;
chomp $rcd;
if (!$rcd) {next;}
$rcd =~ s/^\s+//;      
if (substr($rcd,0,1) eq '#') { next;}
if (substr($rcd,0,1) eq '*') { next;}
my $comment = '';
($rcd,$comment) = split '#',$rcd,2;
if (!$rcd) {next;}
my %hash = ($recnokey => $recno,$errmsgkey => '',$linekey => $rcd);
my $pos = 0;
my $qcount = () = $rcd =~ /\"/g;
if ($qcount % 2) {
$hash{$errmsgkey} = "$Bold$Red Error!$White Odd number of quotes in line ".
"$Green$recno$White of $Yellow$filespec$White! Line Ignored";
$retcode = 3;
push @{$array},{%hash};
next;
}
if (!$type) {
if ($rcd =~ /\=/) {$type = 'k';}  
else {$type = 'p';}
if ($rcd =~ /\,/) {$delim = ',';}   
}
my @errors = ();
WORD: while ($rcd) {
$pos++;
my $keywd = sprintf("%04.4u",$pos);
my $value = '';
if ($type eq 'k') {
if ($rcd !~ /\=/) {   
push @errors,"$Bold$Red Error!$White Missing '=' after $Blue$rcd$White in line ".
"$Green$recno$White of $Yellow$filespec$White! Rest of line bypassed";
$retcode = 3;
last;
}
($keywd,$rcd) = split '=',$rcd,2;
if (!$keywd) {last;}
if (!defined $rcd) {
push @errors,"$Bold$Red Error!$White Missing value after keyword $Blue$keywd$White in line ".
"$Green$recno$White of $Yellow$filespec$White! Rest of line bypassed";
$retcode = 3;
last;
}
$keywd =~ s/^\s+//;    
if (substr($keywd,0,1) eq '"') { ### if keyword quoted, move quotes to after '='
$keywd = substr($keywd,1);
$rcd = '"' . $rcd;     ### add to value
}
$keywd =~ s/\s+$//;    
if ($keywd =~ / /) {   
push @errors,"$Bold$Red Error!$White keyword $Blue$keywd$White has imbedded blanks in line ".
"$Green$recno$White of $Yellow$filespec$White! Rest of line ($rcd) bypassed";
$retcode = 3;
last;
}
$keywd = lc($keywd);
}
$rcd =~ s/^\s+//;      
if (substr($rcd,0,1) eq '"') {
$rcd = substr($rcd,1);
if ($rcd =~ /\"/) {($value,$rcd) = split ('"',$rcd,2);} 
else {
push @errors,"$Bold$Red Error!$White Missing closing quote in line ".
"$Green$recno$White of $Yellow$filespec$White! Rest of line bypassed";
$retcode = 3;
last;
}
$rcd =~ s/^\s+//;    
if (substr($rcd,0,1) eq $delim) {$rcd = substr($rcd,1);}
}
else {($value,$rcd) = split ($delim,$rcd,2);}
if ($rcd) {$rcd =~ s/^\s+//;}    
if ($validate) {
if ($validate->{$keywd}) {
my $keytype = $validate->{$keywd};
my $emsg = "$Bold$Red Error! '$Magenta$value$White' is not valid for keyword $Blue$keywd$White in line ".
"$Green$recno$White of $Yellow$filespec$White!";
if ((ref $keytype) eq 'ARRAY') {
my $found = FALSE;
foreach my $str (@{$keytype}) {
if (lc($value) eq lc($str)) {
$found = TRUE;
last;
}
}
if (!$found) {
push @errors,$emsg;
$retcode = 3;
next WORD;
}### value not found
}#### array check
elsif (lc($keytype) eq 'n') {
if ((!looks_like_number($value)) or ($value <= 0)) {
push @errors,$emsg;
$retcode = 3;
next WORD;
}
}### number process
elsif (lc($keytype) eq 'i') {
if ($value !~ /^[0-9]*$/) {  
push @errors,$emsg;
$retcode = 3;
next WORD;
}
}### Integer test
elsif (lc($keytype) eq 'x') {
if ($value !~ /^[0-9,a,b,c,d,e,f]*$/i) {  
push @errors,$emsg;
$retcode = 3;
next WORD;
}
}### Integer test
elsif (lc($keytype) eq 'b') {
if ($value) {
my $fc = lc(substr($value,0,1));
if (($fc eq 'y') or ($fc eq 't') or ($fc eq '1')) {$value = TRUE;}
else {$value = FALSE;}
}
else {$value = FALSE;}
}
elsif (lc($keytype) eq 'f'){
if ((looks_like_number($value)) and ($value > 0)) {
if ($value =~ /\./) {### got a decimal
my ($mhz,$khz) = split /\./,$value,2;
$khz = substr($khz . '000000',0,6);
if (!$mhz) {$mhz = 0;}
$value = "$mhz$khz";
}
}
else {
push @errors,$emsg;
$retcode = 3;
next WORD;
}
}
}
}
$hash{$keywd} = $value;
}
foreach my $msg (@errors) {
if (!$msg) {next;}
if ($hash{$errmsgkey} ) {$hash{$errmsgkey} = $hash{$errmsgkey} . "$Eol$msg";}
else{$hash{$errmsgkey} = $msg;}
}
push @{$array},{%hash};
}### record process
return $retcode;
}
sub BenchMark{
use strict;
my $timeref = shift @_;
my $logfile = shift @_;
if (!$timeref) {LogIt(363,"Program Error!$Yellow Useful:BenchMark- Missing hash reference!");}
if (!$logfile) {$logfile = '';}
my %times = ();
foreach my $key (keys %{$timeref}) {
my ($proctype,$procname) = split '_',$key,2;
$proctype = lc($proctype);
if (!$proctype) {$proctype = '';}
if (($proctype ne 'start') and ($proctype ne 'end') ) {
LogIt(429,"Program Error!$Yellow Useful:BenchMark$White unknown process type $Green$proctype for $key!");
}
if (!$procname) {LogIt(431,"Program Error!$Yellow Useful:BenchMark$White no process name  for $key!");}
$times{$procname}{$proctype} = $timeref->{$key};
}
foreach my $procname (keys %times) {
if (!defined $times{$procname}{'start'}) {
LogIt(1,"Program Error!$Yellow Useful:BenchMark missing Start for process=$Green$procname!");
next;
}
if (!defined $times{$procname}{'end'}) {
LogIt(1,"Program Error!$Yellow Useful:BenchMark missing End for process=$Green$procname!");
next;
}
$times{$procname}{'value'} = $times{$procname}{'end'} - $times{$procname}{'start'};
if ($times{$procname}{'value'} == 0) {$times{$procname}{'value'} = '0.1';}
}
LogIt(3,"\nBenchmark timings:");
foreach my $procname (sort keys %times) {
my $seconds = $times{$procname}{'value'};
my $time =  sprintf("%3.1f",$seconds) . "$White seconds";
if ($seconds > 60) {
my $minutes = $seconds/60;
$time =  sprintf("%7.2f",$minutes) . "$White minutes";
}
my $msg = "$Bold " . sprintf("%15.15s",$procname) . ":$Green$time";
LogIt(3,$msg);
$msg =~ s/\x1b\[[^m]+m//g;   
}
return 0;
}
sub DirExist {
use strict;
my $path = shift @_;
if (!$path) {return 99;}
if ($path eq '/') {return 3;}
my $create = shift @_;
if (!-d $path) {
if ($create) { `mkdir -p $path`;}
else {return 2;}
}
if (-d $path) {
my $ndx = 0;
while (1) {
my $filename = "_____test_$ndx";
if (-e "$path/$filename") {
$ndx++;
next;
}
`touch $path/$filename`;
if (-e "$path/$filename") {
`rm "$path/$filename"`;
return 0;
}
else {return 1;}
}
}
return 2;
}
