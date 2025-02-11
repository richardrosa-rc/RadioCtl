#!/usr/bin/perl -w
my $author = 'Lydia & Richard';
my $office_prog = 'libreoffice --view';
use constant TRUE  => 1;
use constant FALSE => 0;
use strict;
use autovivification;
no  autovivification;
use Device::SerialPort qw ( :PARAM :STAT 0.07 );
use Text::ParseWords;
use Text::CSV;
use File::Basename;
use Scalar::Util qw(looks_like_number);
use threads;
use threads::shared;
use Thread::Queue;
use Config;
$Config{useithreads} or die "Perl Thread Support missing!";
use Gtk3 '-init';
use constant PANGO_SCALE => 1024;
use constant PANGO_WEIGHT_BOLD => 700;
use constant PANGO_WEIGHT_LIGHT => 300;
use Data::Dumper;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );
my $os = $^O;
my $linux;
my $homedir;
use FindBin qw($RealBin);
use lib "$RealBin";
my $callpath = "$RealBin/";
print STDERR "callpath = $callpath\n";
use scanner;
use radioctl;
print "$Bold RadioCtl GUI$Red Rev=$White$Rev$Eol";
if (substr($os,0,3) eq 'MSW') {
$os = 'WINDOWS';
$homedir = $ENV{"USERPROFILE"};
$linux = FALSE;
print STDERR "$Bold$Red WARNING! $White This program MAY not work correctly on Windows$Eol";
}
else {
$os = 'LINUX';
$homedir = $ENV{"HOME"};
$linux = TRUE;
my $progname = $0;
}
use constant MINCHAN         => 20;
use constant MAXMESSAGE      => 10;
use constant MESSAGELENGTH   => 200;
use constant FILEFORMAT      => 3;
use constant BUTTON_TIMER    => 3;
use constant MAXTIMER        => 6;
my $Start_cmd = '';
my $Clear_all = FALSE;
my $File_load = '';
my $User_conf = '';
my $User_radio = '';
my @Vfo_new = ();
my @Control_new = ();
$Options{'cmd=s'} = \$Start_cmd;
$Options{'init'} = \$Clear_all;
$Options{'file=s'} = \$File_load;
$Options{'cfg=s'} = \$User_conf;
$Options{'radio=s'} = \$User_radio;
$Options{'d1'} = \$Debug1;
$Options{'d2'} = \$Debug2;
$Options{'d3'} = \$Debug3;
Parms_Parse();
if ($Debug1) {
LogIt(0,"Debug Level 1 enabled");
DebugIt("Debug Level 1 enabled");
}
if ($Debug2) {
LogIt(0,"Debug Level 2 enabled");
DebugIt("Debug Level 2 enabled");
}
if ($Debug3) {
LogIt(0,"Debug Level 3 enabled");
DebugIt("Debug Level 3 enabled");
}
$Start_cmd = lc($Start_cmd);
my %valid_starts = (
'frequency_scan' => TRUE,
'channel_scan' => TRUE,
'radio_scan' => TRUE,
'load'       => TRUE,
);
if ($Start_cmd and (!$valid_starts{$Start_cmd})) {
my $msg = "'$Start_cmd' is not a valid startup command. Ignored!";
add_message($msg,1);
$Start_cmd = 'manual';
}
if ($File_load) {
if (!-f $File_load) {
my $msg = "'$File_load' does not exist or is not a text file. Ignored!";
add_message($msg,1);
$File_load = '';
}
}
if ($User_conf) {
if (!-f $User_conf) {
my $msg = "'$User_conf' does not exist or is not a text file. Ignored!";
add_message($msg,1);
$User_conf = '';
}
}
our $deffile = "$homedir/radioctl.conf";
if (!-f $deffile) {$deffile = "$callpath/radioctl.conf";}
if ($User_conf) {$deffile = $User_conf;}
if (-f $deffile) {add_message("Set configuration file to $deffile",0);}
else {
my $msg = "No$Yellow radioctl.conf$White file was located in " .
"$Yellow$homedir$White or $Yellow$callpath$White\n" .
"Program MAY fail!";
if ($User_conf) {
LogIt(1,"Configuration file $Yellow$User_conf$White was not located!\n" .
"Program MAY fail!");
$deffile = '';
}
$deffile = '';
add_message($msg,2);
}### Configuration file missing
our $inifile = "$homedir/radioctl.vars";
@dblist = ('system','group','freq','search','lookup');
our @sub_windows = ('ops','vfo','status','select','signal','global');
our %col_active = ();
our %drop_lookup = ();
our %menu_hash = ();
our $lastdir = "";
our @ports = ();
our %ports = ();
our $pop_up = FALSE;
our %col_xref = ();
our %db_view_menus = ();
our %iters = ();
our %was_focus = ();
$initmessage = "Welcome To RadioCtl Rev $Rev";
our @msgno = ('msg1','msg2','msg3','msg4');
our @timer         = (
0,
0,
0,
0,
0,
0,
);
our @progstates = (
{'state' => 'manual',         'dply' => 'Manual'},
{'state' => 'frequency_scan', 'dply' => 'Scan by Database Frequency' },
{'state' => 'channel_scan',   'dply' => "Scan by Radio's Channel"},
{'state' => 'radio_scan',     'dply' => 'Radio Scan'},
{'state' => 'search',         'dply' => 'Frequency Search'},
{'state' => 'bank_search',    'dply' => 'Frequency Bank Search'},
{'state' => 'load',           'dply' => 'Load From Radio'},
{'state' => 'init',        'dply' => ''},
{'state' => 'quit',        'dply' => ''},
);
if ($deffile) {
LogIt(0,"RadioCtl l413:reading configuration file $deffile");
spec_read($deffile);
}
my %w_info = (
'main'      => {'xsize' => 700,'ysize'=> 300,'xpos'=> 550, 'ypos' =>  80, 'active'=> 1,'init' => 0},
'freq'      => {'xsize' => 900,'ysize'=> 320,'xpos'=>  90, 'ypos' => 270, 'active'=> 1,'init' => 0},
'group'     => {'xsize' => 500,'ysize'=> 320,'xpos'=>  40, 'ypos' => 150, 'active'=> 1,'init' => 0},
'search'    => {'xsize' => 750,'ysize'=> 270,'xpos'=>   1, 'ypos' =>  20, 'active'=> 1,'init' => 0},
'message'   => {'xsize' => 320,'ysize'=> 320,'xpos'=> 900, 'ypos' => 620, 'active'=> 1,'init' => 0},
'parms'     => {'xsize' => 320,'ysize'=> 320,'xpos'=> 200, 'ypos' => 600, 'active'=> 1,'init' => 0},
'system'    => {'xsize' => 300,'ysize'=> 310,'xpos'=> 220, 'ypos' => 620, 'active'=> 1,'init' => 0},
);
foreach my $key (keys %struct_fields) {
if (!defined $clear{$key}) {$clear{$key} = $struct_fields{$key}[3];}
}
$clear{'lookup'} = 0;
read_ini();
foreach my $key (keys %clear) {
if ($Clear_all or (!defined $vfo{$key})) {$vfo{$key} = $clear{$key};}
}
if ($Clear_all) {
foreach my $key (keys %control) {$control{$key} = $clear{$key};}
$vfo{'_last_radio_name'} = 'local';
}
if (!$vfo{'_last_radio_name'}) {$vfo{'_last_radio_name'} = 'local';}
$control{'autobaud'} = TRUE;
delete $control{'logging_file'};
my %colors = ('channel'    => 'blanchedalmond',
'groupno'    => 'aliceblue',
'count'      => 'beige',
'duration'   => 'gainsboro',
'signal'     => 'tomato',
'frequency'  => 'lightgreen',
'start_freq' => 'lightgreen',
'end_freq'   => 'moccasin',
'step'       => 'orange',
'timestamp'  => 'khaki',
'mode'       => 'yellow',
'service'    => 'lightsteelblue',
'tgid'       => 'lightsalmon',
'sqtone'     => 'moccasin',
'att_amp'    =>  'orange',
'sysno'      => 'palegreen',
'systemname' => 'sandybrown',
'groupname'  => 'skyblue',
'dlyrsm'     => 'thistle',
);
my $font = 'face="DejaVu Sans Mono"';
my $fg = 'foreground="blue" ';
my $bg = 'background="black" ';
my $weight = 'weight="heavy"';
my $size = 'size="33300"';
my $style = 'style="normal"';
my $dark = FALSE;
my @str = `cat ~/.config/gtk-3.0/settings.ini`;
foreach my $rec (@str) {
if ($rec =~ /prefer/i) {
if ($rec =~ /theme\=true/){$dark = TRUE;}
last;
}
}
if ($dark) {LogIt(0,"DARK theme detected");}
my $lastfilesave = '';
my %guidb = ('freq' => 0,'system' => 0, 'group' => 0, 'search' => 0,'lookup' => 0,);
my @signal_values  =  ( 0,1, 3, 5, 7, 9, 15, 20, 40, 60);
my $radioctl_icon;
my $radioctl_logo;
if (-e "$callpath/radioctl.ico") {
$radioctl_logo = Gtk3::Image->new_from_file("$callpath/radioctl.ico");
$radioctl_icon = Gtk3::Gdk::Pixbuf->new_from_file("$callpath/radioctl.ico");
}
my @file_menu = (
{'name' => 'open',    'title' => '_Open Frequency File (add records)',     'icon' => 'document-open'},
{'name' => 'opennew', 'title' => 'Open _Frequency File (replace records)', 'icon' => 'open_for_editing'},
{'name' => 'save',    'title' => '_Save Frequency File',                   'icon' => 'document-save-as'},
{'name' => 'read',    'title' => '_Read Radio Definition File',            'icon' => 'document-open-remote'},
{'name' => 'write',   'title' => '_Write Message Log',                     'icon' => 'mail-message-new-list'},
{'name' => 'quit',    'title' => '_Quit',                                  'icon' => 'gtk-quit'},
);
my @help_menu = (
{'name' => 'help',    'title'  => '_Contents', 'icon' => 'help-contents'},
{'name' => 'about',   'title'  => '_About', 'icon' => 'help-about'},
);
my @edit_menu = (
{'name' => 'create', 'title' => '_Add a new record',            'icon' => 'gtk-add'},
{'name' => '_line',},
{'name' => 'delete', 'title' => '_Delete the selected records', 'icon' => 'edit-delete'},
{'name' => 'clear_db',  'title' => 'Remove ALL records in this database',    'icon' => 'project-development-close'},
{'name' => '_line',},
{'name' => 'swap',   'title' => 'S_wap records',                'icon' => 'system-switch-user'},
{'name' => 'edit',   'title' => 'E_dit/Change multiple records','icon' => 'edit-copy'},
{'name' => 'sortf',  'title' => '_Sort by frequency',           'icon' => 'view-sort-ascending', 'dbn' => 'freq'},
{'name' => 'sortc',  'title' => 'Sort by Channel _Number',      'icon' => 'sort_incr', 'dbn' => 'freq'},
{'name' => 'renum',  'title' => 'Renumber Channel Number',      'icon' => 'view-sort-ascending', 'dbn' => 'freq'},
{'name' => 'xfer',   'title' => 'Transfer Selected to lookup', 'icon' => 'go-next-view-page', 'dbn' => 'freq'},
{'name' => 'lookup', 'title' => 'Lookup empty service for Selected', 'icon' => 'go-next-view-page', 'dbn' => 'freq'},
);
my @needs_selected =  ('delete','swap','xfer','edit','lookup');
my %menu_item = ();
my %panels = (
'main' => {'title' => "RadioCtl v$Rev by $author", 'type' => 'w'},
'vfo'  => {'title' => "VFO",     'type' => 'p', 'parent' => 'main'},
'freq' => {'title' => "Frequencies and channels", 'type' => 'd'},
'radio' => {'title' => "Radio",   'type' => 'p', 'parent' =>'main'},
'group' => {'title' => "Groups", 'type' => 'd'},
'search' => {'title' => "Search Banks", 'type' => 'd'},
'lookup' => {'title' => "Lookup Frequencies", 'type' => 'd'},
'system' => {'title' => "Systems", 'type' => 'd'},
'messages' => {'title' => "messages", 'type' => 'p'},
'ops' => {'title' => "Operations", 'type' => 'p', 'parent' => 'main' },
'vchan' => {'title' => "Index", 'type' => 'p','parent' => 'main' },
'vstep' => {'title' => "Step", 'type' => 'p','parent' => 'main' },
'vfreq' => {'title' => "Frequency", 'type' => 'p','parent' => 'main' },
'vmode' => {'title' => "Modulation", 'type' => 'p','parent' => 'main' },
'vext' => {'title' => "Extra Controls", 'type' => 'p','parent' => 'main' },
'rchan' => {'title' => "Channel",       'type' => 'p','parent' => 'main' },
'status' => {'title' => "Status", 'type' => 'p','parent' => 'main'},
'op_search' => {'title' => "Scan/Search Options", 'type' => 'p','parent' => 'main'},
'op_scan' => {'title' => "Scanning Options", 'type' => 'p','parent' => 'main'},
'op_other' => {'title' => "Other Operation Options",'type' => 'p','parent' => 'main'},
'speed' => {'title' => "Speed Limit (Channels/Second)", 'type' => 'p','parent' => 'main'},
'select' => {'title' => "Radio Selection",'type' => 'p','parent' => 'main'},
'signal' => {'title' => "Signal Meter", 'type' => 'p','parent' => 'main'},
);
my %digit_names = (
'vchan' => {'title' => "Index",        'type' => 'p','parent' => 'main', 'len' => (length(MAXINDEX))},
'rchan' => {'title' => "Channel",      'type' => 'p','parent' => 'main', 'len' => (length(MAXCHAN))},
'vstep' => {'title' => "Step",         'type' => 'p','parent' => 'main', 'len' => $fdigits},
'vfreq' => {'title' => "Frequency",    'type' => 'p','parent' => 'main', 'len' => $fdigits},
);
foreach my $key ((keys %panels),(keys %digit_names)) {
if ($digit_names{$key}{'title'}) {$digit_names{$key}{'enable'} = TRUE;}
if ($panels{$key}{'type'} eq 'p') {
$panels{$key}{'gtk'} = Gtk3::Frame->new($panels{$key}{'title'});
my $child = $panels{$key}{'gtk'}->get_child();
}
else {
$panels{$key}{'gtk'} = Gtk3::Window->new;
$panels{$key}{'gtk'}->set_icon($radioctl_icon);
$panels{$key}{'gtk'}->set_decorated(TRUE);
$panels{$key}{'gtk'}->set_resizable(TRUE);
$panels{$key}{'gtk'}->set_title($panels{$key}{'title'});
}
}
our @model = ("Glib::Int");
my @sqtonestring = ('Off');
my %sqtonestring = ('off' => 0);
foreach my $tone (@ctctone) {
if ($tone =~ /off/i) {next;}
my $ndx = push @sqtonestring,$tone;
}
foreach my $tone (@dcstone) {
if ($tone =~ /off/i) {next;}
my $ndx = push @sqtonestring,$tone;
}
our %drop_list = (
'mode'     => {'strings' => [@modestring]},
'sqtone'   => {'strings' => [@sqtonestring]},
'att_amp'  => {'strings' => [@attstring]},
);
our %liststore;
our %treeview;
our %treecol;
DROPDOWNINIT:
foreach my $key (keys %drop_list) {
my @text = ();
if ($key eq 'hld') {
foreach my $ndx (0..255) {push @text,$ndx;}
}
elsif ($key eq 'tag') {
foreach my $ndx (0..999,'-') {push @text,$ndx;}
}
elsif ($key eq 'p25waiting') {
foreach my $ndx (0..10) { push @text,($ndx * 100);}
}
elsif ($key eq 'qkey') {
foreach my $syskey (0..99,'-') {push @text,$syskey;}
}
elsif ($key eq 'systemtype') {
my $ndx = 0;
$text[0] = "Conventional";
}
else {@text = @{$drop_list{$key}{'strings'}};}
my $ndx = (push @model,"Gtk3::ListStore") - 1;
$drop_list{$key}{'model'} = $ndx;
my $liststore = Gtk3::ListStore->new ("Glib::String");
$drop_list{$key}{'liststore'} = $liststore;
foreach my $str (@text) {
my $iter = $liststore->append;
$liststore->set($iter,0,$str);
}
}
our $treendx = -1;
our %dply_def = ();
foreach my $dbndx (keys %panels) {
if ($panels{$dbndx}{'type'} ne 'd') {next;}
foreach my $key (@{$structure{$dbndx}}) {
if ($key eq '_guiend') {
$dply_def{$key}{'title'} = ' ';
my $modeltype = 'Glib::String';
$dply_def{$key}{'modeltype'} = $modeltype;
my $modndx = (push @model,$modeltype) - 1;
$dply_def{$key}{'dbcol'} = $modndx;
$dply_def{$key}{'dplycol'} = $modndx;
$dply_def{$key}{'affect'}{$dbndx} = TRUE;
$dply_def{$key}{'readonly'} = TRUE;
$dply_def{$key}{'type'}  = 'text';
$col_xref{$key} = $modndx;
last;
}
if (!$struct_fields{$key}) {LogIt(1372,"Pass1:Key $key not defined in STRUCT_FIELDS!");}
if (defined $dply_def{$key}{'dbcol'}) {next;}
$dply_def{$key}{'title'} = $key;
my $modeltype = undef;
my $dplyndx = undef;
my $type = $struct_fields{$key}[0];
my $flags = $struct_fields{$key}[2];
if (($dbndx eq 'freq') and ($key eq 'sysno')) {
LogIt(1005,"RADOICTL.PL: SYSNO was defined for a FREQ record");
$flags = $flags . 'r';
LogIt(0,"RadioCtl.pl l1002: $dbndx key=$key flags=$flags");
}
if ($flags =~ /x/i) {
my $xdb = '';
if ($key eq 'groupno') {$xdb = 'group';}
elsif ($key eq 'sysno') {$xdb = 'system';}
else {LogIt(1398,"PASS-1:Unknown XREF field $key");}
$dply_def{$key}{'xref'} = $xdb;
push @{$xrefs{$xdb}},($dbndx,$key);
}
if ($flags =~ /r/i) {  
$dply_def{$key}{'readonly'} = TRUE;
}
if (($type eq 'c') or ($type eq 'g') or ($type eq 'o') ){
$modeltype = 'Glib::String';
my $ndx = $drop_list{$key}{'model'};
if (defined $ndx) {
$dplyndx = $ndx;
$dply_def{$key}{'signal'} = \&comboproc;
$dply_def{$key}{'type'}   = 'combo';
$dply_def{$key}{'list'}   = $key;
}
else {
$dply_def{$key}{'signal'} = \&db_text_proc;
$dply_def{$key}{'type'}  = 'text';
}
}
elsif ($type eq 'b') {
$dply_def{$key}{'type'} = 'toggle';
$modeltype = 'Glib::Boolean';
$dply_def{$key}{'signal'} = \&toggleproc;
}
elsif ($type eq 'f') {
$dply_def{$key}{'type'} = 'freq';
$modeltype = 'Glib::UInt';
$dply_def{$key}{'signal'} = \&db_num_proc;
$dplyndx = (push @model,"Glib::String") - 1;
}
elsif ($type eq 'i') {
if (($key eq 'channel') or ($key eq 'index')) {
$dply_def{$key}{'type'}  = 'index';
$dply_def{$key}{'render'} = \&chan_render;
}
else {
$dply_def{$key}{'type'}  = 'number';
$dply_def{$key}{'render'} = \&number_render;
}
$modeltype = 'Glib::String';
if ($key eq 'index') {$modeltype = 'Glib::Int';}
$dply_def{$key}{'signal'} = \&db_num_proc;
}
elsif ($type eq 'n') {
$dply_def{$key}{'type'}  = 'number';
$modeltype = 'Glib::String';
$dply_def{$key}{'render'} = \&number_render;
}
elsif($type eq 't') {
$dply_def{$key}{'type'}  = 'time';
$modeltype = 'Glib::String';
$dplyndx = (push @model,"Glib::String") - 1;
}
elsif ($type eq 's') {
my $sourcedb = '';
if ($key eq 'systemname') {$sourcedb = 'system';}
elsif ($key eq 'groupname') {$sourcedb = 'group';}
elsif ($key eq 'sitename') {$sourcedb = 'site';}
else {LogIt(1381,"PASS-1:Unknown shadowed field $key");}
$dply_def{$key}{'shadow'} = $sourcedb ;
$dply_def{$key}{'readonly'} = TRUE;
$dply_def{$key}{'type'}  = 'shadow';
$modeltype = 'Glib::String';
}
else {LogIt(1458,"PASS-1:Donno how to deal with key=>$key of type $type for database=>$dbndx");}
my $modndx = (push @model,$modeltype) - 1;
if (!defined $dplyndx) {$dplyndx = $modndx;}
$dply_def{$key}{'modeltype'} = $modeltype;
$dply_def{$key}{'dbcol'} = $modndx;
$dply_def{$key}{'dplycol'} = $dplyndx;
$dply_def{$key}{'affect'}{$dbndx} = TRUE;
if ($dply_def{$key}{'readonly'}) {$dply_def{$key}{'signal'} = undef;}
$col_xref{$key} = $modndx;
}
}### for every database
my %rowsel = ();
foreach my $dbndx (keys %panels) {
if ($panels{$dbndx}{'type'} ne 'd') {next;}
$liststore{$dbndx} = Gtk3::ListStore->new (@model);
$treeview{$dbndx} = Gtk3::TreeView->new ($liststore{$dbndx});
$treeview{$dbndx}->signal_connect(button_press_event => sub {
my ($self,$widget,$dbndx) = @_;
if ($response_pending) {return 0;}
my $type    = $widget->type;
my $button  = $widget->button;
if ($button == 1) { }
elsif ($button == 2) { }
elsif ($button == 3) {
$menu_item{$dbndx}{'_Edit'}->popup_at_pointer();
}
else {LogIt(1,"RADIOCTL l1997:No process for button $button");}
return FALSE;
},$dbndx);
$treeview{$dbndx}->set_activate_on_single_click(TRUE);
$treeview{$dbndx}->get_selection()->set_mode('multiple');
$rowsel{$dbndx} = FALSE;
$treeview{$dbndx}->signal_connect('cursor_changed' => sub {
my $treeview = shift @_;
my $dbndx = shift @_;
$rowsel{$dbndx} = TRUE;
return FALSE;
},$dbndx);
}
LogIt(0,"Processing Pass 2");
PASS2:
foreach my $dbndx (keys %panels) {
if ($panels{$dbndx}{'type'} ne 'd') {next;}
foreach my $key (@{$structure{$dbndx}}) {
my $coldb  = $dply_def{$key}{'dbcol'};
my $dplycol  = $dply_def{$key}{'dplycol'};
my $type  = $dply_def{$key}{'type'};
if (!$type) {LogIt(957,"PASS2:Missing type for key=>$key");}
if (!$dplycol) {LogIt(1688,"PASS2:Missing dplycol for key=$key");}
if (!$coldb) {LogIt(1685,"PASS2:Missing coldb for key=$key");}
my $title  = $dply_def{$key}{'title'};
if ($key eq 'index') {
if ($dbndx eq 'system') {$title = 'System-Num';}
elsif ($dbndx eq 'group') {$title = 'Group-Num';}
elsif ($dbndx eq 'site') {$title = 'Site-Num';}
}
$title =~ s/\_/\-/g;
$title = ucfirst($title);
if ($title =~ /att/i) {$title = 'Att-Amp';}
elsif ($title =~ /dlyrsm/i) {$title = 'Dly-Rsm';}
elsif ($title =~ /tgid/i) {$title = 'TGID';}
my $renderer = $dply_def{$key}{'render'};
my $signal_call = $dply_def{$key}{'signal'};
my $right_j = FALSE;
if (($type eq 'number') or ($type eq 'freq')) {$right_j = TRUE;}
my $hide = FALSE;
my $sortfunction = undef;
my %dbinfo = ('coldb' => $coldb,
'dbndx' => $dbndx,
'key'   => $key,
'dplycol' => $dplycol,
'type'   => $type,
);
my $cellrender;
my @colattributes = ($title);
if ($type eq 'toggle') {
$cellrender = Gtk3::CellRendererToggle->new;
if ($signal_call) {
$cellrender->signal_connect (toggled => $signal_call, \%dbinfo);
$cellrender->set(activatable => TRUE);
}
else {$cellrender->set(activatable => FALSE);}
push @colattributes,$cellrender,'active' => $dplycol;
}
elsif ($type eq 'combo') {
$cellrender = Gtk3::CellRendererCombo->new;
if ($signal_call) {
$cellrender->set(editable => TRUE);
$cellrender->signal_connect (edited => $signal_call, \%dbinfo);
}
else {$cellrender->set(editable => FALSE);}
$cellrender->set(
text_column => 0,
has_entry => FALSE
);
push @colattributes,$cellrender,'text' => $coldb,'model' => $dplycol;
}
else {
$cellrender = Gtk3::CellRendererText->new;
if ($signal_call) {
$cellrender->set(editable => TRUE);
$cellrender->signal_connect (edited => $signal_call, \%dbinfo);
}
else {
$cellrender->set(editable => FALSE);
}
push @colattributes,$cellrender,'text' => $dplycol;
}
if ($right_j) {$cellrender->set(xalign => 1.0);}
else {$cellrender->set(xalign =>0);}
$treecol{$dbndx}{$coldb} = Gtk3::TreeViewColumn->new_with_attributes(@colattributes,);
if ($right_j) {$treecol{$dbndx}{$coldb}->set_alignment(1.0);}
if ($renderer) {$treecol{$dbndx}{$coldb}->set_cell_data_func($cellrender,$renderer,\%dbinfo);}
else {
if ($colors{$key}) {
if ($dark) {$cellrender->set_property('foreground',$colors{$key});}
else {$cellrender->set_property('background',$colors{$key});}
}
}
$treecol{$dbndx}{$coldb}->set_sort_indicator(TRUE);
$treecol{$dbndx}{$coldb}->set_sort_column_id($coldb);
if ($sortfunction) {
}
$treecol{$dbndx}{$coldb}->set_visible(FALSE);
if (!$hide) {
if (!defined $col_active{$dbndx}{$coldb}) {
$col_active{$dbndx}{$coldb} = TRUE;
}
$treecol{$dbndx}{$coldb}->set_resizable(TRUE);
if (!defined $treeview{$dbndx}) {
LogIt(2487,"Oops forgot to define treeview for $dbndx ($title)!");
}
$treeview{$dbndx}->append_column($treecol{$dbndx}{$coldb});
if (!defined $db_view_menus{$dbndx}) {
$db_view_menus{$dbndx} =  Gtk3::Menu->new();
}
if (substr($key,0,1) ne '_') {
my $item = make_view_menu_item($title,
$dbndx,
$treecol{$dbndx}{$coldb},
\$col_active{$dbndx}{$coldb},
'treecol',
$coldb,
);
$db_view_menus{$dbndx} -> append($item);
}
else {$treecol{$dbndx}{$coldb}->set_visible(TRUE);}
}
else {$treecol{$dbndx}{$coldb}->set_visible(FALSE);  }
if ($key eq '_guiend') {
$treecol{$dbndx}{$coldb}->set_visible(TRUE);
last;
}
}### For each key
}### each database
LogIt(0,"Pass 2 complete");
our $thread_ptr ;
$thread_ptr = threads->new(\&manual_state);
$thread_ptr->detach();
my $init_done = FALSE;
my $delaydisplay = 0;
my %active;
foreach my $db (@dblist) {$active{$db} = -1;}
my %up_down_button = (
'time_stamp' => 0,
'delay'      => 0,
'parms'      => '',
'widget'     => '',
);
my @req_queue;
my %validreq = ('vfoctl' => 1,
'open'    => 1,
'save'    => 1,
'create'  => 1,
'delete'  => 1,
'clear'   => 1,
'connect' => 1,
'sort'    => 1,
'batch'   => 1,
'renum'   => 1,
);
my %mem_set   = %clear;
my %copy = %clear;
my $status_dialog = '';
show_long_run('testing');
my %combo = ();
my %combo_text = ();
my %combo_label = ();
my @combos = ('vmode',
'vbw',
'adtype',
'sqtone',
'name','port','baud','vchan','beep','att_amp');
foreach my $key (@combos) {
$combo{$key} = Gtk3::ComboBoxText->new;
my $label = $key;
if ($key =~ /vbw/i) {$label = 'Bandwidth';}
elsif ($key =~ /att/i) {$label = 'Atten/Preamp';}
elsif ($key =~ /sqtone/i) {$label = 'Tone Squelch';}
elsif ($key =~ /adtype/i) {$label = 'Audio';}
$combo_label{$key} = Gtk3::Label->new($label);
my $desc = Pango::FontDescription-> new();
$desc->set_size(13000);
$combo_label{$key}->override_font($desc);
$combo_text{$key} = ();
}
my @dbload;
my @dbsave;
my $end_mark;
my @write_col = ();
my %valid_col = ();
my %handler_id;
my @signal_meter;
my @labels;
my @option_text;
my %radio_dply_label;
my @radio_dply_value;
my %opt_button;
my %opt_value;
my %expand_box;
my %expand_buttons;
my %entry;
my %window_display;
my %window_menu;
my @rparms;
my %scrolled;
my %view_menu;
my @vbox;
my @hbox;
my $hz;
my $color;
my $found;
my $iter;
my $cellrender;
my %headers = ();
my @view_menu = ();
LogIt(0,"Setting up display panels");
my %popup_menu = ();
foreach my $dbndx (keys %panels) {
if ($panels{$dbndx}{'type'} ne 'd') {next;}
my $view_menu_item = Gtk3::MenuItem->new('_View');
$view_menu_item->set_submenu($db_view_menus{$dbndx});
my $menu_bar = Gtk3::MenuBar->new;
$menu_bar->append(make_menu("_File",\@file_menu,$dbndx));
$menu_bar->append($view_menu_item);
$menu_bar->append(make_menu("_Edit",\@edit_menu,$dbndx));
foreach my $rec (@edit_menu) {
my $item = $rec->{'name'};
if ($item eq 'create') {next;}
if ($menu_item{$dbndx}{$item}) {
$menu_item{$dbndx}{$item}->set_sensitive(FALSE);
}
}
$menu_bar->append(make_menu("_Help",\@help_menu,$dbndx));
$vbox[0] = Gtk3::Box->new('vertical',5);
$vbox[0] ->pack_start($menu_bar,FALSE,TRUE ,0);
my $scrolled = Gtk3::ScrolledWindow->new;
$scrolled->set_policy('automatic','automatic');
$scrolled->set_shadow_type('in');
if (TRUE) {
$treeview{$dbndx}->set_grid_lines('horizontal');
$scrolled->add($treeview{$dbndx});
$vbox[0]->pack_start($scrolled,TRUE,TRUE ,0);
$panels{$dbndx}{'gtk'} ->add($vbox[0]);
}
else {
$vbox[0]->pack_start($treeview{$dbndx},TRUE,TRUE,0);
$scrolled->add($vbox[0]);
$panels{$dbndx}{'gtk'} ->add($scrolled);
}
}#### create record type windows
my %maxdply = ();
foreach my $dbndx (@dblist) {
$maxdply{$dbndx} = Gtk3::Label->new($dbcounts{$dbndx});
}
my $vfo_service = Gtk3::Label->new("");
$vfo_service->set_justify('left');
init_vfo_combo();
if (!$vfo{'mode'}) {$vfo{'mode'} = 'FMn';}
my %txref = ();
my $op_search = Gtk3::Box->new('vertical',5);
my $op_scan = Gtk3::Box->new('vertical',5);
my $op_other  = Gtk3::Box->new('vertical',5);
my @opt_button_dply = (
{'key' => 'dlyrsm',   'panel' => $op_search,'dply' => 'During Signal:Global +Delay -Resume'},
{'key' => 'start',    'panel' => $op_scan, 'dply' => 'Scan Start Record/Channel'},
{'key' => 'stop',     'panel' => $op_scan, 'dply' => 'Scan End   Record/Channel'},
{'key' => 'dbdlyrsm', 'panel' => $op_scan, 'dply' => 'During Signal:Data record sets Delay/Resume'},
{'key' => 'scansys',  'panel' => $op_scan, 'dply' => 'Scans Use System Records'},
{'key' => 'scangroup','panel' => $op_scan, 'dply' => 'Scans Use Group Records'},
{'key' => 'manlog',   'panel' => $op_other, 'dply' => 'Update Database In Manual'},
{'key' => 'recorder', 'panel' => $op_other, 'dply' => "Record Audio (=>$settings{'recdir'})"},
{'key' => 'recorder_multi','panel'=>$op_other,'dply'=>'Separate Recordings For Each Squelch Break'},
{'key' => 'logging',  'panel' => $op_other, 'dply' => "Log To File (=>$settings{'recdir'})"},
);
$control{'logging_dir'} = $settings{'logdir'};
$control{'recording_dir'} = $settings{'recdir'};
foreach my $rec (@opt_button_dply) {
my $key = $rec->{'key'};
if (!defined $control{$key}) {$control{$key} = FALSE;}
$opt_button{$key} = Gtk3::CheckButton ->new($rec->{'dply'});
my $child = $opt_button{$key} -> get_child();
my $bgc = 'background="white"';
my $fg = 'foreground="grey" ';
my $weight = ' weight="normal" ';
my $str = "<span $fg $bgc $weight > $rec->{'dply'} </span";
$opt_button{$key}->set_active($control{$key});
$opt_button{$key}->signal_connect(toggled => sub {
my $widget = shift @_;
my $key = shift @_;
$control{$key} = $widget->get_active;
if ($key eq 'dlyrsm') {
if ($control{$key}) {
if ($control{'dlyrsm_value'}) {
$control{'dbdlyrsm'} = FALSE;
$opt_button{'dbdlyrsm'}->set_active(FALSE);
}
else {
$control{$key} = FALSE;
$widget->set_active(FALSE);
}
}
}
elsif ($key eq 'dbdlyrsm') {
if ($control{$key}) {
$control{'dlyrsm'} = FALSE;
$opt_button{'dlyrsm'}->set_active(FALSE);
}
}
elsif ($key eq 'start') { }
elsif ($key eq 'stop') {  }
elsif ($key eq 'logging') {
if ($control{$key}) {
if (DirExist($settings{'logdir'},TRUE)) {
$control{$key} = $widget->set_active(FALSE);
err_dialog("Cannot create log.  Directory:$settings{'logdir'}" .
"Does not exist and cannot be created!","error");
}### Cannot create directory
}### Turning on the logging
}### Logging key
elsif ($key eq 'recorder') {
if ($control{$key}) {### User turned on
my $missing = '';
if (!-e "/usr/bin/sox") {$missing = 'Application /usr/bin/sox Missing/Not Installed';}
elsif (!-e "/usr/bin/parecord") {$missing = 'Application /usr/bin/parecord Missing/Not Installed';}
else {
foreach my $set ('tempdir','recdir') {
my $dir = $settings{$set};
if (DirExist($dir,TRUE)) {
$missing = "Directory $dir (settings{$set} is not present and cannot be created";
last;
}### Directory does not exist
}### For each of the settings directories
}
if ($missing) {
$control{$key} = $widget->set_active(FALSE);
err_dialog("Cannot record: $missing.","error");
$opt_button{'recorder_multi'} -> set_sensitive(FALSE);
}
else {
$opt_button{'recorder_multi'} -> set_sensitive(TRUE);
}
}## Turning on Recording
else {
$opt_button{'recorder_multi'} -> set_sensitive(FALSE);
}
}### Recording key
dply_scan_opt();
return TRUE;
},$key);
$hbox[0] = Gtk3::Box->new('horizontal',5);
if (defined $control{$key . '_value'}) {
$entry{$key} = Gtk3::Entry->new;
$entry{$key} -> set_width_chars(4);
$entry{$key}->signal_connect(activate => \&number_entry,$key);
$entry{$key}->signal_connect(focus_out_event => \&focus_lost,$key);
my $ctlinit = $key . '_value';
my $value = $control{$ctlinit};
if (!defined $value) {
print Dumper(%control),"\n";
LogIt(1,"undefined value for control->$ctlinit ($key)");
}
number_entry($entry{$key},$key);
$hbox[0]->pack_start($entry{$key},FALSE,FALSE,0);
}### Entry field defined for a number
$hbox[0]->pack_start($opt_button{$key},FALSE ,FALSE,0);
$rec->{'panel'}->pack_start($hbox[0],FALSE,FALSE,0);
}### Option Buttons
dply_scan_opt();
my $sqadj = Gtk3::Adjustment->new(0, 0, 90, 1, 1.0, 1.0);
my $sqscale = Gtk3::HScale->new($sqadj);
my $sqlvalue = Gtk3::Label->new("squelch");
$sqscale->set_digits(1);
$sqscale->set_value_pos('left');
$sqscale->set_draw_value(TRUE);
$handler_id{'squelch'} = $sqscale->signal_connect(value_changed => \&squelch_bar_change);
if (!$control{'squelch'}) {$control{'squelch'} = 0;}
$sqscale->set_value($control{'squelch'});
my @speed_value = (0,10,9,8,7,6,5,4,3,2,1,.5);
my $bar_size = (scalar @speed_value) - 1;
my $spscale = Gtk3::Scale->new_with_range('horizontal',0,$bar_size,1);
$spscale->set_value_pos('top');
$spscale->set_draw_value(TRUE);
$spscale->set_has_origin(TRUE);
foreach my $ndx (1..$bar_size) {$spscale->add_mark($ndx,'left',$speed_value[$ndx]);}
$spscale->show;
$spscale->set_sensitive(TRUE);
if (!$control{'speed_bar'}) {$control{'speed_bar'} = 0;}
$control{'speed_bar'} = 0;
$spscale->signal_connect(
value_changed => sub {
my $speed = $speed_value[$spscale->get_value];
if (!$speed) {$speed = 0;}
$control{'speed_bar'} = $speed;
return TRUE;
}
);
$spscale->signal_connect(
format_value  => sub {
my $fmt = shift @_;
my $value = shift @_;
my $retvalue = $speed_value[$value] ;
if (!$retvalue) {$retvalue = 'Off';}
return $retvalue;
}
);
my %status_ctl = ();
my @status_keys = ('sysno','groupno','index','bank','lookup');
my @status2_keys = ('delay','resume');
foreach my $key (@status_keys,@status2_keys) {$status_ctl{$key} = Gtk3::Label->new('0');}
my $connect_status = Gtk3::Button->new_with_label("");
$connect_status->signal_connect(pressed =>
sub {
my %req = ('_cmd' => 'connect',
'baudrate' => $combo{'baud'}->get_active_text(),
'port' => $combo{'port'}->get_active_text(),
);
if ($radio_def{'active'}) {### Radio is already active
%req = ('_cmd' => 'disconnect');
}
else {
my $name = $radio_def{'name'};
my $combo_name = lc($combo{'name'}->get_active_text);
if ((!$name) or ($name ne $combo_name) ) {
radioselproc();
return TRUE;
}### New radio name being selected
}### Radio is Active
$req{'_caller'} = 2480;
push @req_queue,{%req};
});
my $rescan_button = Gtk3::Button->new_with_label("rescan");
$rescan_button->signal_connect(pressed =>
sub {refreshserial();});
my $autobaud_button = Gtk3::CheckButton ->new("Autobaud");
$autobaud_button->signal_connect(toggled => sub {
my $widget = shift @_;
$control{'autobaud'} = $widget->get_active;
if ($control{'autobaud'}) {
$combo{'port'}->set_sensitive(FALSE);
$combo{'baud'}->set_sensitive(FALSE);
}
else {
$combo{'port'}->set_sensitive(TRUE);
$combo{'baud'}->set_sensitive(TRUE);
}
});
$autobaud_button->set_active($control{'autobaud'});
refreshserial();
$combo{'port'} ->signal_connect(popup => \&refreshserial);
my $bdndx = 0;
foreach my $baud (reverse sort numerically keys %baudrates) {
$combo{'baud'} -> append_text($baud);
$baudrates{$baud} = $bdndx;
$bdndx++;
}
$combo{'baud'}->set_active(0);
my $lastradio = '';
if ($User_radio) {$lastradio = lc($User_radio);}
elsif ($vfo{'_last_radio_name'}) {$lastradio = lc($vfo{'_last_radio_name'});}
else {$lastradio = lc($defaultradio);}
my $sel_ndx = -1;
if ($lastradio eq 'local') {$sel_ndx = 0;}
$combo{'name'}->insert_text(0,$defaultradio);
my $combo_ndx = 1;
foreach my $name (sort keys %All_Radios) {
if ($name eq lc($defaultradio)) {next;}
my $realname = $All_Radios{$name}{'realname'};
if (!$realname) {
print Dumper(%All_Radios),"\n";
LogIt(2861,"No 'realname' key for name=$name");
}
$combo{'name'}->insert_text($combo_ndx,$realname);
if ($lastradio eq $name) {$sel_ndx = $combo_ndx;}
$combo_ndx++;
}
if ($sel_ndx < 0) {
if ($User_radio) {
my $msg = "Radio name $User_radio not found in config. Changed to Local";
add_message($msg,1);
}
$sel_ndx = 0;
}
$combo{'name'} ->signal_connect(changed => \&radioselproc);
$combo{'name'}->set_active($sel_ndx);
my %view_parms = ();
$view_menu{'main'} = Gtk3::Menu->new();
my $separator = Gtk3::MenuItem->new('#### Panels #####');
my $child = $separator->get_child;
$separator->set_sensitive(FALSE);
$view_menu{'main'} ->append($separator);
$vbox[0] = Gtk3::Box->new('vertical',10);
our $message_box = Gtk3::TextView->new;
$message_box->set_cursor_visible(FALSE);
$message_box->set_editable(FALSE);
my $top_messages = TRUE;
my $buffer = $message_box->get_buffer();
$buffer->create_tag ("red", foreground => "red");
$buffer->create_tag ("black", );
$buffer->create_tag ("green",);
$buffer->create_tag ("blue", );
$buffer->create_tag ("yellow",);
$buffer->create_tag ("cyan", );
$buffer->create_tag ("bold", weight => PANGO_WEIGHT_BOLD);
$buffer->create_tag ("normal", weight => PANGO_WEIGHT_LIGHT);
$buffer->create_tag ("big", size => 15 * PANGO_SCALE);
$scrolled{'messages'} = Gtk3::ScrolledWindow->new;
$scrolled{'messages'}->set_policy('automatic','automatic');
$scrolled{'messages'}->set_placement('top-left');
if (TRUE) {
$scrolled{'messages'}->add_with_viewport($message_box);
$vbox[0]->pack_start($scrolled{'messages'},TRUE,TRUE,0);
}
else {
$vbox[0]->pack_start($message_box,FALSE,FALSE,0);
}
my $clrbutton = Gtk3::Button->new_with_label("Press to Clear Messages");
$vbox[0] ->pack_end($clrbutton,FALSE,FALSE,0);
$clrbutton->signal_connect(pressed => sub {
my $buffer = $message_box->get_buffer();
my $dialog = Gtk3::Dialog->new_with_buttons('Save Messages?',$panels{'main'}{'gtk'},
[qw/modal destroy-with-parent/],
'gtk-cancel' => 'cancel',
'gtk-yes' => 'yes',
'gtk-no'  =>  'no',
);
my $text = Gtk3::Label->new("Save messages to a file before clearing?");
my $font = 'face="DejaVu Sans Mono"';
my $size = 'size="18000"';
my $weight = ' weight="normal" ';
$text->set_markup ('<span ' . "$font $size $weight " . '>' .
"Save Messages to a file before clearing?" . '</span>');
my $content = $dialog->get_content_area();
$content->add($text);
$dialog->show;
my $response = $dialog->run;
$dialog->destroy;
if ($response eq 'cancel') {return 0;}
if ($response eq 'yes') {
my ($start,$end) = $buffer->get_bounds;
$buffer->delete($start,$end);
}
}
);
$panels{'messages'}{'gtk'} ->add($vbox[0]);
add_view_menu('messages');
my %rbuttons;
my $group = undef;
$vbox[0] = Gtk3::Box->new('vertical',5);
$vbox[1] = Gtk3::Box->new('vertical',5);
my $ndx = 0;
foreach my $sm (@progstates) {
if ($sm-> {'dply'}) {
my $title = $sm->{'dply'};
my $mode = $sm->{'state'};
$rbuttons{$mode}  = Gtk3::RadioButton->new_with_label($group,$title);
my $child = $rbuttons{$mode}->get_child();
if ($child) {
my $fg = '';
$child -> set_markup('<span ' .
$fg .
'>' .
$title . '</span>');
}
if (!$group) { $group = $rbuttons{$mode}->get_group;}
$vbox[$ndx]->pack_start($rbuttons{$mode},FALSE ,FALSE,0);
$handler_id{$mode} =  $rbuttons{$mode}->signal_connect(pressed => \&operation_select, $sm);
$rbuttons{$mode}->signal_connect(released => sub {return 0});
}
}
$hbox[0] =Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start($vbox[0] ,FALSE,FALSE,0);
$hbox[0]->pack_start($vbox[1] ,FALSE,FALSE,0);
$rbuttons{'cancel'} = Gtk3::Button->new_with_label('Cancel operation');
$child = $rbuttons{'cancel'} -> get_child;
$child->set_markup('<span foreground="red" > Cancel Operation </span>');
my %op_parm = ('state' => 'cancel');
$handler_id{'cancel'} =  $rbuttons{'cancel'}->signal_connect(pressed => \&operation_select,\%op_parm);
$vbox[2] = Gtk3::Box->new('vertical',5);
$vbox[2] -> pack_start($hbox[0],FALSE,FALSE,0);
$vbox[2] -> pack_start($rbuttons{'cancel'},FALSE,FALSE,0);
$panels{'ops'}{'gtk'}->add($vbox[2]);
add_view_menu('ops');
$panels{'speed'}{'gtk'}->add($spscale);
add_view_menu('speed');
DIGIT_BUILD:
my %digit = ();
my %digit_dply = ();
my %sbuttons = ();
foreach my $type (keys %digit_names) {
my $count = $digit_names{$type}{'len'};
my @ndx = ();
$digit_dply{$type} = Gtk3::Box->new('horizontal',5);
$digit_dply{$type}->set_spacing(0);
for my $i (0..($count-1)) {
if (defined $digit{$type}{$i}{'ctl'}) { LogIt(2578,"Redefining a digit!");}
push @ndx,$i;
$digit{$type}{$i}{'ctl'} = Gtk3::Label->new();
$digit_dply{$type}->pack_end($digit{$type}{$i}{'ctl'},FALSE,TRUE,0);
$digit{$type}{$i}{'sel'} = FALSE;
$digit{$type}{$i}{'ctl'}->set_selectable(TRUE);
$digit{$type}{$i}{'ctl'}->set_sensitive(TRUE);
foreach my $event ('scroll-event','button_press_event','button_release_event',
) {
my %parms = ('type' => $type,'digit' => $i,'event'=> $event);
$digit{$type}{$i}{'ctl'}->signal_connect($event =>\&vfo_digit,\%parms);
}
$digit{$type}{$i}{'ctl'}->add_events('enter-notify-mask');
$digit{$type}{$i}{'ctl'}->add_events('scroll-mask');
}### all digits
$entry{$type}  = Gtk3::Entry->new;
$entry{$type}->set_width_chars($digit_names{$type}{'len'});
my $proc = \&frequency_entry;
if ($type =~ /chan/i) {$proc = \&number_entry;}
$entry{$type}->signal_connect(activate => $proc,$type);
$entry{$type}->signal_connect(focus_out_event => \&focus_lost,$type);
my $arrows = Gtk3::Box->new('vertical',5);
foreach my $updown ('up','down') {
$sbuttons{$type}{$updown} = Gtk3::ToggleButton->new;
my $arrow = '';
if ($updown eq 'up') {$arrow = Gtk3::Arrow->new('up','in'); }
else {$arrow = Gtk3::Arrow->new('down','out'); }
$sbuttons{$type}{$updown} ->add($arrow);
my $parms = "$type,$updown";
$sbuttons{$type}{$updown} ->signal_connect(pressed => \&inc_press, $parms);
$sbuttons{$type}{$updown} ->signal_connect(released => sub {
$up_down_button{'widget'} = '';
$up_down_button{'delay'} = 0;
$up_down_button{'parms'} = '';
$up_down_button{'time_stamp'} = 0;
});
$arrows->pack_start($sbuttons{$type}{$updown},FALSE,FALSE,0);
}
$vbox[0] = Gtk3::Box->new('vertical',5);
$vbox[0]->pack_start($digit_dply{$type},FALSE,FALSE,0);
$vbox[0]->pack_start($entry{$type},FALSE,FALSE,0);
$hbox[0] = Gtk3::Box->new('horizontal',5);
if ($type =~ /igrp/i) {
$hbox[0]->pack_end($arrows,FALSE,FALSE,0);
}
else {
$hbox[0]->pack_start($arrows,FALSE,FALSE,0);
}
$hbox[0]->pack_start($vbox[0],FALSE,FALSE,0);
$panels{$type}{'gtk'}->add($hbox[0]);
if ($type eq 'rchan') {
}
else {
add_view_menu($type);
}
}
$vbox[0] = Gtk3::Box->new('vertical',5);
$vbox[0]->pack_start($combo{'vmode'},FALSE,FALSE,0);
$vbox[0]->pack_start(Gtk3::Label->new(" "),FALSE,FALSE,0);
$vbox[0]->pack_start($combo{'adtype'},FALSE,FALSE,0);
$vbox[0]->pack_start($combo_label{'adtype'},FALSE,FALSE,0);
$panels{'vmode'}{'gtk'}->add($vbox[0]);
add_view_menu('vmode');
$vbox[0] = Gtk3::Box->new('vertical',5);
foreach my $type ('vbw','att_amp','sqtone') {
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start($combo{$type},FALSE,FALSE,0);
$hbox[0]->pack_start($combo_label{$type},FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
}
$panels{'vext'}{'gtk'}->add($vbox[0]);
add_view_menu('vext');
$vbox[0] = Gtk3::Box->new('horizontal',5);
$vbox[0]->pack_start($panels{'rchan'}{'gtk'},FALSE,FALSE,0);
$vbox[0]->show_all;
$panels{'radio'}{'gtk'}->add($vbox[0]);
dply_vfo_num('rchan',0);
$hbox[2] = Gtk3::Box->new('horizontal',5);
foreach my $type ('vchan','vstep','vfreq','vmode','vext') {
$hbox[2]->pack_start($panels{$type}{'gtk'},FALSE,FALSE,0);
}
$vbox[0] = Gtk3::Box->new('vertical',5);
$vbox[0] ->pack_start($hbox[2],FALSE,FALSE,0);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0] ->pack_start($vfo_service,FALSE,FALSE,0);
$vbox[0] ->pack_start($hbox[0],TRUE,TRUE,0);
$vbox[0]->show_all;
$panels{'vfo'}{'gtk'} ->add($vbox[0]);
LogIt(0,"VFO panel complete");
add_view_menu('vfo');
$vbox[0] =  Gtk3::Box->new('vertical',5);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start(Gtk3::Label->new("      Radio->"),FALSE,FALSE,0);
$hbox[0]->pack_start($combo{'name'},FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start(Gtk3::Label->new("         Port->"),FALSE,FALSE,0);
$hbox[0]->pack_start($combo{'port'},FALSE,FALSE,0);
$hbox[0]->pack_start($rescan_button,FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start(Gtk3::Label->new("Baudrate->"),FALSE,FALSE,0);
$hbox[0]->pack_start($combo{'baud'},FALSE,FALSE,0);
$hbox[0]->pack_start($autobaud_button,FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start(Gtk3::Label->new("    Status->"),FALSE,FALSE,0);
$hbox[0]->pack_start($connect_status,FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$panels{'select'}{'gtk'}->add($vbox[0]);
add_view_menu('select');
$vbox[0] = Gtk3::Box->new('vertical',5);
$hbox[1] = Gtk3::Box->new('horizontal',5);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[2] = Gtk3::Box->new('horizontal',5);
$hbox[3] = Gtk3::Box->new('horizontal',5);
foreach my $key (@status_keys) {
my $title = Strip(ucfirst($key));
if (lc($key) eq 'groupno') {$title = 'Group';}
elsif (lc($key) eq '_seq') {$title = 'Freq ';}
elsif (lc($key) eq 'bank') {$title = 'Srch ';}
elsif (lc($key) eq 'sysno'){$title = 'Systm';}
elsif (lc($key) eq 'lookup') {$title = 'Lookup';}
else {$title = sprintf("%-5.5s",$title);}
my $label = Gtk3::Label->new($title);
$label -> set_markup ('<span ' .
'size="8000" face="DejaVu Sans Mono"' .
'weight="light" style="italic">' .
$title . '</span>');
$hbox[0]->pack_start($label,FALSE,FALSE,13);
$hbox[1]->pack_start($status_ctl{$key},FALSE,FALSE,10);
}
$hbox[1]->pack_start(Gtk3::Label->new("<<<-Current"),FALSE,FALSE,0);
foreach my $key (@dblist) {
$hbox[2]->pack_start($maxdply{$key},FALSE,FALSE,10);
}
$hbox[2]->pack_start(Gtk3::Label->new("<<<-Maximums"),FALSE,FALSE,0);
foreach my $ctl (@status2_keys) {
my $label = Gtk3::Label->new();
$label-> set_justify("right");
$label -> set_markup ('<span ' .
'size="8000" face="DejaVu Sans Mono"' .
'weight="light" style="italic">' .
ucfirst($ctl) . '=></span>');
$hbox[3]->pack_start($label,FALSE,FALSE,13);
$hbox[3]->pack_start($status_ctl{$ctl},FALSE,FALSE,0);
$hbox[3]->pack_start( Gtk3::Label->new('                   '),FALSE,FALSE,0);
}
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[1],FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[2],FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[3],FALSE,FALSE,0);
$panels{'status'}{'gtk'}->add($vbox[0]);
add_view_menu('status');
$vbox[0] = Gtk3::Box->new('vertical',5);
$hbox[0] = Gtk3::Box->new('horizontal',8);
foreach my $i (0..MAXSIGNAL) {
$signal_meter[$i] = Gtk3::Label->new(' ');
my $eventbox = Gtk3::EventBox->new();
$eventbox->add($signal_meter[$i]);
$eventbox->signal_connect('button_press_event' => sub {
push @req_queue,{'_cmd' => 'vfoctl',
'_ctl', => 'signal',
'_value' => $i,
'_debug' => 'signal_button',
};
return $GoodCode;
},$i);
$hbox[0]->pack_start($eventbox,FALSE,FALSE,0);
}
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start($sqscale,TRUE,TRUE,0);
$hbox[0]->pack_start($sqlvalue,FALSE,FALSE,0);
$vbox[0]->pack_start($hbox[0],FALSE,FALSE,0);
$panels{'signal'}{'gtk'} ->add($vbox[0]);
add_view_menu('signal');
$panels{'op_search'}{'gtk'}->add($op_search);
$panels{'op_scan'}{'gtk'}->add($op_scan);
$panels{'op_other'}{'gtk'}->add($op_other);
add_view_menu('op_search');
add_view_menu('op_scan');
add_view_menu('op_other');
foreach my $dbndx (sort keys %panels) {
if ($panels{$dbndx}{'type'} eq 'p') {next;}
$panels{$dbndx}{'gtk'} ->signal_connect (delete_event => \&close_window,$dbndx);
if (defined $w_info{$dbndx}) {
if ($w_info{$dbndx}{'xpos'} and $w_info{$dbndx}{'ypos'}) {
$panels{$dbndx}{'gtk'} ->move($w_info{$dbndx}{'xpos'},$w_info{$dbndx}{'ypos'});
}
if ($w_info{$dbndx}{'xsize'} and $w_info{$dbndx}{'ysize'}) {
$panels{$dbndx}{'gtk'} ->resize($w_info{$dbndx}{'xsize'},$w_info{$dbndx}{'ysize'});
}
}
if ($dbndx eq 'main') {next;}
if (!defined $w_info{$dbndx}{'active'}) {$w_info{$dbndx}{'active'} = FALSE;}
$window_menu{$dbndx} = make_view_menu_item($panels{$dbndx}{'title'},$dbndx,$panels{$dbndx}{'gtk'},\$w_info{$dbndx}{'active'});
$view_menu{'main'} -> prepend($window_menu{$dbndx});
LogIt(0,"Finished updating window $dbndx");
}
$vbox[0] = Gtk3::Box->new('vertical',5);
$vbox[1] = Gtk3::Box->new('vertical',5);
$vbox[2] = Gtk3::Box->new('vertical',5);
$vbox[3] = Gtk3::Box->new('vertical',5);
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[1] = Gtk3::Box->new('horizontal',5);
foreach my $panel ('select','status','signal','speed') {
if ($panels{$panel}{'type'} eq 'p') {
$vbox[0] ->pack_start($panels{$panel}{'gtk'},FALSE,FALSE,0);
}
}
foreach my $panel ('op_search','op_scan','op_other') {
if ($panels{$panel}{'type'} eq 'p') {
$vbox[2] ->pack_start($panels{$panel}{'gtk'},TRUE,TRUE,0);
}
}
foreach my $panel ('ops') {
if ($panels{$panel}{'type'} eq 'p') {
$vbox[3] ->pack_start($panels{$panel}{'gtk'},TRUE,TRUE,0);
}
}
$vbox[3]->pack_start($panels{'radio'}{'gtk'},TRUE,TRUE,0);
$vbox[3]->show_all;
foreach my $ndx (3,0,2) {$hbox[0]->pack_start($vbox[$ndx],FALSE,FALSE,0);}
$hbox[0]->pack_start(Gtk3::Box->new('horizontal',5),TRUE,TRUE,0);
$hbox[0]-> show_all;
$vbox[1] -> pack_start($hbox[0],FALSE,FALSE,0);
if ($panels{'vfo'}{'type'} eq 'p') {
$hbox[2] = Gtk3::Box->new('horizontal',5);
$hbox[2] -> pack_start($panels{'vfo'}{'gtk'},FALSE,FALSE,0);
$hbox[2] -> pack_start(Gtk3::Box->new('horizontal',5),FALSE,FALSE,0);
$vbox[1] -> pack_start($hbox[2],FALSE,FALSE,0);
}
$vbox[1]->pack_start($panels{'messages'}{'gtk'},TRUE,TRUE,0);
$vbox[1]->show_all;
my $menu_bar = Gtk3::MenuBar->new;
$menu_bar->append(make_menu('_File',\@file_menu,'main'));
my $view_menu_item = Gtk3::MenuItem->new('_View');
$view_menu_item->set_submenu($view_menu{'main'});
$menu_bar->append($view_menu_item);
$menu_bar->append(make_menu('_Help',\@help_menu,'main'));
$vbox[2] = Gtk3::Box->new('vertical',5);
$vbox[2] -> pack_start($menu_bar,FALSE,FALSE,0);
$scrolled{'main'} = Gtk3::ScrolledWindow->new;
$scrolled{'main'}->set_policy('automatic','automatic');
if (TRUE) {
$scrolled{'main'}->add($vbox[1]);
$vbox[2]->pack_start($scrolled{'main'},TRUE,TRUE,0);
$panels{'main'}{'gtk'}  ->add ($vbox[2]);
$panels{'main'}{'gtk'} ->show_all;
}
else {
$vbox[2]->pack_start($vbox[1],FALSE,FALSE,0);
$scrolled{'main'}->add($vbox[2]);
$panels{'main'}{'gtk'} -> add($scrolled{'main'});
}
$panels{'main'}{'gtk'}->show_all;
if ($File_load) {
my %request = ('_cmd' => 'open', 'filespec' =>$File_load, 'replace' => TRUE);
push @req_queue,{%request};
}
if ($Start_cmd) {
print "L3724: Executing $Start_cmd\n";
my %request = ('_cmd' => 'statechange', 'state' =>$Start_cmd);
push @req_queue,{%request};
}
my $timer = Glib::Timeout->add($usleep{'TIMEPOP'},\&timepop, undef, 10);
Gtk3->main;
exit 0;
sub timepop {
my $found;
if ($pop_up) {
@req_queue = ();
return 1;
}
if ($delaydisplay) {
$delaydisplay--;
return 1;
}
if ($response_pending) {
if (!$status_dialog) {show_long_run($response_pending);}
}
else {
if ($status_dialog) {
$status_dialog->destroy();
$status_dialog = '';
if ($was_focus{'window'}) {
$panels{$was_focus{'window'}}{'gtk'}->activate();
}
}
}
{
lock @messages;
while (scalar @messages) {
my $msg = shift @messages;
my $sev = 0;
($sev,$msg) = split ',',$msg,2;
message_dply($msg,$sev);
}
}
foreach my $dbndx (keys %panels) {
if ($rowsel{$dbndx}) {
my $treeselection = $treeview{$dbndx}->get_selection();
my $count = $treeselection->count_selected_rows();
foreach my $item (@needs_selected) {
if (!$menu_item{$dbndx}{$item}) {next;}
if (!$count) {$menu_item{$dbndx}{$item}->set_sensitive(FALSE);}
else {
if ($item eq 'swap') {
if ($count == 2) {$menu_item{$dbndx}{$item}->set_sensitive(TRUE);}
else {$menu_item{$dbndx}{$item}->set_sensitive(FALSE);}
}
else {$menu_item{$dbndx}{$item}->set_sensitive(TRUE);}
}
}
$rowsel{$dbndx} = FALSE;
}
}
if ((defined $scan_request{'_rdy'}) ) {
if (!$scan_request{'_cmd'}) {
LogIt(1,"TIMEPOP-3983:ScanRequest missing command=>");
print Dumper(%scan_request),"\n";
return 1;
}
my $command = $scan_request{'_cmd'};
if ($command eq 'update') {
if (!defined $scan_request{'_dbn'}) {
print Dumper(%scan_request),"\n";
LogIt(3369,"Undefined '_dbn' in scan_scanquest");
}
my $dbndx = lc($scan_request{'_dbn'});
if (($dbndx eq -1) or ($dbndx eq 'vfo')) {
print Dumper(%scan_request),"\n";
LogIt(3378,"TIMEPOP:Scanner Requested VFO display sync. Remove this call!");
}
if (!defined $scan_request{'_seq'}) {
print Dumper(%scan_request),"\n";
LogIt(3382,"TIME_POP:Undefined _seq in scan request");
}
if (!$liststore{$dbndx}) {
print Dumper(%scan_request),"\n";
LogIt(3386,"SCAN_REQUEST:Bad database index=>$dbndx");
}
my @indexes = ($scan_request{'_seq'});
set_db_data($dbndx,\@indexes,\%scan_request);
}### sync requested
elsif ($command eq 'batch'){
if (!defined $scan_request{'_dbn'}) {
print Dumper(%scan_request),"\n";
LogIt(3489,"Undefined '_dbn' in scan_scanquest");
}
my $dbndx = lc($scan_request{'_dbn'});
if (!$liststore{$dbndx}) {
print Dumper(%scan_request),"\n";
LogIt(3515,"SCAN_REQUEST:Bad database index=>$dbndx");
}
if (scalar @selected) {
set_db_data($dbndx,\@selected,\%scan_request);
}
else {LogIt(1,"TIMEPOP l3428:No selection for BATCH scanner request!");}
}
elsif ($command eq 'vfodply') {
my $freq = $vfo{'frequency'};
if (!$freq) {$freq = 0;}
if (!$freq and $vfo{'tgid'}) {
$freq = "TGID:" . sprintf("%6.6s",$vfo{'tgid'});
}
dply_vfo_num('vfreq',$freq);
dply_vfo_num('vchan',$vfo{'index'});
dply_vfo_num('rchan',$vfo{'channel'});
dply_vfo_num('vstep',$vfo{'step'});
dply_signal($vfo{'signal'});
dply_combos();
dply_status();
my $value = $vfo{'service'};
if (!$value) {$value = '';}
if ($vfo{'tgid'}) {$value = "$value (TGID:$vfo{'tgid'})";}
dply_service($value);
my $child =  $opt_button{'recorder'}->get_child();
my $bgc = '';
my $fg = '';
my $weight = ' weight="normal" ';
my $msg = "Record Audio on Signal";
if ($dark) {$fg = ' foreground="white" ';}
else {$fg = ' foreground="black" ';}
if ($start_recording) {
$fg = 'foreground="red"';
$msg = "Recording=>$record_file";
$weight = 'weight="heavy"';
}
$child->set_markup("<span $fg $bgc $weight > $msg </span>");
$child =  $opt_button{'logging'}->get_child();
$bgc = '';
$fg = '';
$weight = ' weight="normal" ';
$msg = "Log To File";
if ($dark) {$fg = ' foreground="white" ';}
else {$fg = ' foreground="black" ';}
if ($control{'logging'}) {
$fg = 'foreground="green"';
$msg = "Logging=>$settings{'logdir'}/$Logfile_Name";
$weight = 'weight="heavy"';
}
$child->set_markup("<span $fg $bgc $weight > $msg </span>");
}
elsif ($command eq 'sigdply') {
dply_signal($vfo{'signal'});
}
elsif ($command eq 'init') {
LogIt(0,"GUI started INIT request from scanner");
foreach my $dbndx (keys %panels) {
if ($dbndx eq 'main') {next;}
if ($panels{$dbndx}{'type'} eq 'p') {next;}
if ($w_info{$dbndx}{'active'}) {$panels{$dbndx}{'gtk'} -> show;}
}
radio_parms_dply();
$panels{'main'}{'gtk'} ->show;
$init_done = TRUE;
add_message("test initialization complete.");
lock (%scan_request);
%scan_request = ();
LogIt(0,"GUI completed INIT command");
return 1;
}
elsif ($command eq 'message') {
add_message($scan_request{'msg'},$scan_request{'severity'});
}
elsif ($command eq 'delete') {
if (!defined $scan_request{'_dbn'}) {
print Dumper(%scan_request),"\n";
LogIt(3545,"Undefined '_dbn' in scan_scanquest");
}
my $dbndx = lc($scan_request{'_dbn'});
if (!$liststore{$dbndx}) {
print Dumper(%scan_request),"\n";
LogIt(3551,"SCAN_REQUEST:Bad database index=>$dbndx");
}
if (!scalar @selected) {
LogIt(1,"TIMEPOP l3554: no selected records found for DELETE!");
}
foreach my $no (@selected) {
if (!$no) {next;}
if ($no < 0) {next;}
my $iter = find_iter($dbndx,$no,FALSE,FALSE,3975);
if ($iter eq -1) {
LogIt(1,"TIMEPOP:DELETE:Could not find record $no to delete");
next;
}
$liststore{$dbndx}->remove($iter);
$guidb{$dbndx}--;
if ($guidb{$dbndx} < 0) {LogIt(4111,"RADIOCTL:negative GUIDB value for $dbndx");}
}### for each selected
}### DELETE processing
elsif ($command eq 'clear') {
my $dbndx = $scan_request{'_dbn'};
LogIt(0,"RADIOCTL.PL l3645:Requesting clear of $dbndx");
$liststore{$dbndx} -> clear();
foreach my $rec (@edit_menu) {
my $item = $rec->{'name'};
if ($item eq 'create') {next;}
if ($menu_item{$dbndx}{$item}) {$menu_item{$dbndx}{$item} -> set_sensitive(FALSE);}
}
lock @selected;
@selected = ();
$guidb{$dbndx} = 0;
}
elsif ($command eq 'clearall') {
foreach my $dbndx (@dblist) {
$liststore{$dbndx}->clear();
$guidb{$dbndx} = 0;
foreach my $rec (@edit_menu) {
my $item = $rec->{'name'};
if ($item eq 'create') {next;}
if ($menu_item{$dbndx}{$item}) {$menu_item{$dbndx}{$item} -> set_sensitive(FALSE);}
}
}
lock @selected;
@selected = ();
}### Clear all
elsif ($command eq 'statechange') {
my $progstate = $scan_request{'state'};
if (!defined $progstate) {
print "Request block=>",Dumper(%scan_request),"\n";
LogIt(4167, "TIMEPOP line 4167:Undefined state in scan_req!");
}
print "RadioCtl 4297:progstate BEFORE change=$progstate\n";
if ($progstate eq 'manual') {
$rbuttons{$progstate}->set_active(TRUE);
LogIt(0,"set $progstate button active");
}
else {
print "Request block=>",Dumper(%scan_request),"\n";
LogIt(4226,"TIMEPOP:Scanner thread issued statechange request=$progstate");
}
}### STATECHANGE
elsif ($command eq 'radio') {
if (defined $scan_request{'connect'}) {
init_vfo_combo();
radio_status_dply($scan_request{'connect'});
}
else {
print "Request block=>",Dumper(%scan_request),"\n";
LogIt(4196,"undefined 'connect' key for 'RADIO' scan_request");
}
}
elsif ($command eq 'pop-up') {
err_dialog($scan_request{'msg'},'info','queue');
return 1;
}
elsif ($command eq 'baud') {
my $baud_text = $scan_request{'rate'};
my $port_text = $scan_request{'port'};
if ($baud_text and (defined $baudrates{$baud_text})) {
$combo{'baud'}->set_active($baud_text);
}
if ($port_text and (defined $ports{$port_text})) {
$combo{'port'}->set_active($port_text);
}
}### 'baud' command
elsif ($command eq 'control') {
foreach my $key (keys %scan_request) {
if ($key =~ /^\-/) {next;}  
my $action = $scan_request{$key};
if ($key =~ /autobaud/i) {
if ($action eq 'disable') {$autobaud_button->set_sensitive(FALSE);}
elsif ($action eq 'enable') {$autobaud_button->set_sensitive(TRUE);}
}
elsif (defined $control{$key}) {
if ($action eq 'disable') {
if ($key =~ /value/i) {
my ($vkey) = $key =~ /(.*)\_value/i;
if (defined $entry{$vkey}) {
$entry{$vkey}-> set_sensitive(FALSE);
}
}
}
elsif ($action eq 'enable') {
if ($key =~ /value/i) {
my ($vkey) = $key =~ /(.*)\_value/i;
if (defined $entry{$vkey}) {
$entry{$vkey}-> set_sensitive(TRUE);
}
}
}
}### Control item
elsif (defined $menu_item{'freq'}{$key}) {
foreach my $dbndx ('freq','group','system') {
if (defined $menu_item{$dbndx}{$key}) {
if ($action eq 'disable') {
$menu_item{$dbndx}{$key}->set_sensitive(FALSE);
}
else {
$menu_item{$dbndx}{$key}->set_sensitive(TRUE);
}
}### If menu item defined
}### For each database
}### Menu item control
elsif (defined $panels{$key}{'gtk'}) {
if ($action eq 'disable') {
$digit_names{$key}{'enable'} = FALSE;
}
elsif ($action eq 'enable') {
$digit_names{$key}{'enable'} = TRUE;
}
elsif ($action =~ /hide/i) {
$panels{$key}{'gtk'} ->hide();
}
elsif ($action =~ /show/i) {
$panels{$key}{'gtk'} ->show_all();
}
else {
print "RADIOCTL l4133: Need process for display key $key\n";
}
}### Enabling/disabling/showing/hiding panels
elsif (defined $combo{$key}) {
if ($action eq 'disable') {$combo{$key}->set_sensitive(FALSE);}
elsif ($action eq 'enable') {$combo{$key}->set_sensitive(TRUE);}
}
}### Scan request keys
}### CONTROL request
else {
print STDERR Dumper(%scan_request),"\n";
LogIt(4485,"TIMEPOP:No processing defined for scan_request =>$command on GUI!");
}
{### mark the request as complete
lock (%scan_request);
%scan_request = ();
}
threads->yield;
}### scanner request
if (!$init_done) {return 1};
if ($response_pending) {return 1;}
my $proc_time = 160;
if ($up_down_button{'widget'}) {
my $queue_size = scalar @req_queue;
if ($queue_size < 5) {
if ($up_down_button{'time_stamp'}) {
my $now = Time::HiRes::time();
my $delta = $now - $up_down_button{'time_stamp'};
if ($delta > $up_down_button{'delay'}) {
inc_press($up_down_button{'widget'},$up_down_button{'parms'});
$up_down_button{'delay'} = .1;
}
}
}
}
REQ:
while (scalar @req_queue) {
my $queue_size = scalar @req_queue;
if ($queue_size > 5) {
}
my $key_count = 0;
{### Block for locking
lock %gui_request;
$key_count = scalar keys %gui_request;
}
if ($key_count) {
lock %gui_request;
if (!$gui_request{'_cmd'}) {
print "radioctl.pl l4377: GUI request has leftovers but no _CMD\n";
print "request=>",Dumper(%gui_request),"\n";
%gui_request = ();
next REQ;
}
else {
if ($gui_request{'_in_process'}) {
}
else {
$gui_request{'_count'}++;
if ($gui_request{'_count'} > 100) {
LogIt(1,"RADIOCTL.PL:REQ line 4394:GUI request was not acknowledged by SCANNER thread.\n" .
"  Request is nullified");
print Dumper(%gui_request),"\n";
%gui_request = ();
next REQ;
}
}
return 1;
}###
}### Outstanding GUI Request
if (!scalar @req_queue) {return 1;}
my %request = %{shift @req_queue};
if ($request{'_cmd'} eq 'statechange') {
my $newstate = $request{'state'};
$rbuttons{$newstate}->signal_handler_block($handler_id{$newstate});
$rbuttons{$newstate}->set_active(TRUE);
$rbuttons{$newstate}->signal_handler_unblock($handler_id{$newstate});
}
if (!scalar keys(%request)) {
LogIt(1,"TIMER_POP:Got an empty req_queue element!");
next REQ;
}
{### Block for locking
lock %gui_request;
%gui_request = %request;
$gui_request{'_count'} = 0;
$gui_request{'_timestamp'} = Time::HiRes::time();
$gui_request{'_rdy'} = TRUE;
}
threads->yield;
usleep($proc_time);
}
return 1;
}### timepop
sub show_long_run {
my $msg = shift @_;
if (!$msg) {$msg = "please wait for completion";}
%was_focus = ();
foreach my $win (keys %panels) {
if ($panels{$win}{'type'} eq 'p') {next;}
if ($panels{$win}{'gtk'} ->is_active) {
$was_focus{'widget'} = $panels{$win}{'gtk'} ->get_focus();
$was_focus{'window'} = $win;
last;
}
}
my $parent = $was_focus{'window'};
if (!$parent) {$parent = 'main';}
my %button = ('gtk-cancel' => 'cancel');
if (substr($msg,0,1) eq '_') {
%button = ();
$msg = substr($msg,1);
}
$status_dialog = Gtk3::Dialog->new_with_buttons(
'wait',
$panels{$parent}{'gtk'},
[qw/modal destroy-with-parent/],
%button,
);
my $text = Gtk3::Label->new($msg);
my $font = 'face="DejaVu Sans Mono"';
my $size = 'size="21000"';
my $weight = ' weight="bold" ';
$text->set_markup ('<span ' . "$font $size $weight " . '>' .
$msg . '</span>');
my $content = $status_dialog->get_content_area();
$content->add($text);
$status_dialog->signal_connect(delete_event => sub {
return TRUE;
});
$status_dialog->signal_connect(response => sub {
my $parm1 = shift @_;
my $parm2 = shift @_;
if ($parm2 eq 'cancel') {
$rbuttons{'manual'}->set_active(TRUE);
lock $progstate;
$progstate = 'manual';
}
});
$content->show_all;
$status_dialog->show;
$status_dialog->set_keep_above(TRUE);
return 0;
}
sub dply_vfo_num {
my $type = shift @_;
my $value = shift @_;
my $signal = shift @_;
if (!$signal) {$signal = FALSE;}
if (!defined $value) {
$value = 0;
my ($pkg,$fn,$caller) = caller;
print $Bold,"RADIOCTL DPLY_VFO_NUM:Undefined VALUE. Caller=>$caller$Eol";
}
my  $font = 'face="DejaVu Sans Mono"';
my  $size = 'size="33300"';
my  $bgnorm = 'background="black" ';
my  $bghi   = 'background="#aaaaff"';
my  $bg = $bgnorm;
my  $inverse = FALSE;
my  $fg = 'foreground="red" ';
my  $select = 'background="#555555"';
my $weight = 'weight="heavy"';
my $style = 'style="normal"';
my $fmt = $digit_names{$type}{'len'};
if (!$fmt) {
print "RadioCtl l4823 DIGIT_NAMES 'len' for type=$type was not defined!\n";
$fmt = 3;
}
if ($type eq 'vstep') {
$fg = 'foreground="white" ';
$size  = 'size="16100"';
if (looks_like_number($value)) {
$value = rc_to_freq($value);
}
else {
print "RadioCtl 4474:Non-numeric step value $value\n";
return 0;
}
}
elsif ($type eq 'vfreq') {
if (looks_like_number($value)) {
if ($value) {$value = rc_to_freq($value);}
else {$value = " ---.------";}
}
else {$value = sprintf("%${fmt}.${fmt}s",$value);}
}
elsif ($type eq 'vchan') {
$fg = 'foreground="#0FFFFF" ';## channel is blueish
if ($value  =~ /^[0-9]+$/) {$value = sprintf("%${fmt}.${fmt}u",$value);}
else {$value = sprintf("%${fmt}.${fmt}s",$value);}
}
elsif ($type eq 'rchan') {
$fg = 'foreground="yellow"';
$bg = 'background="black"';
if ($value  =~ /^[0-9]+$/) {$value = sprintf("%${fmt}.${fmt}u",$value);}
else {$value = sprintf("%${fmt}.${fmt}s",$value);}
}
my @chars = reverse split '',$value;
foreach my $ndx (0..($fmt-1)) {
my $bgc = $bg;
my $char = shift @chars;
if (!$digit{$type}{$ndx}{'ctl'}) {### This is a problem
LogIt(1,"RadioCtl l4564:no definition for $type digit=$ndx char=$char value=$value");
last;
}
if ($digit{$type}{$ndx}{'sel'}) {
print "RadioCtl line 4566:Digit $ndx is selected\n";
$bgc = $select; }
$digit{$type}{$ndx}{'ctl'}->set_markup (
'<span ' .
$fg . $font . $size . $weight . $style .$bgc . '>' .
$char . '</span>');
}
return 0;
}
sub dply_signal {
my $value = shift @_;
if (!$value) {$value = 0;}
$fg = ' foreground="black" ';
$size = 'size="21000"';
foreach my $i (0..$#signal_meter) {
if (!$i) {
$bg = ' background="lightgreen" ';
$hz = 'Off';
}
else {
$bg = ' background="white" ';
$hz = $signal_values[$i];
if ($value  >= $i) {$bg = ' background="red" ';}
}
$child = $signal_meter[$i];
if ($child) {
$child -> set_markup('<span ' .
'stretch="condensed" ' .
$fg . $font . $size . $weight . $style .$bg . '>' .
$hz . '</span>');
}
else {LogIt(1,"Line 3888:Could not get signal meter child");}
}
return 0;
}
sub dply_combos   {
my $active = $radio_def{'active'};
foreach my $ctl ('vmode','vbw','att_amp','sqtone','adtype') {
$combo{$ctl}->set_sensitive($active);
if (!$active) {
$combo{$ctl}->signal_handler_block($handler_id{$ctl});
$combo{$ctl}->set_active(0);
$combo{$ctl}->signal_handler_unblock($handler_id{$ctl});
}
}### For every supported combo
foreach my $key (keys %rbuttons) {$rbuttons{$key}->set_sensitive($active);}
foreach my $ctl ('vfreq','rchan') {
foreach my $key (keys %{$digit{$ctl}}) {
$digit{$ctl}{$key}{'ctl'}->set_sensitive($active);
}
$entry{$ctl}->set_sensitive($active);
}
my $dbactive = FALSE;
if ($dbcounts{'freq'}) {$dbactive = TRUE;}
foreach my $key (keys %{$digit{'vchan'}}) {
$digit{'vchan'}{$key}{'ctl'}->set_sensitive($dbactive);
}
$entry{'vchan'}->set_sensitive($dbactive);
if (!$active) {return 0;}
my %ctl_value = ();
my $vfo_mode =  $vfo{'mode'};
if (!$vfo_mode) {$vfo_mode = 'fmn';}
my $mode = Strip(lc($vfo_mode));
my $bw = '';
if (length($mode) >2) {$bw = substr($mode,2,1);}
if (!$bw) {$bw = '(';}
$bw = lc($bw);
$mode = substr($mode,0,2);
if ($mode =~ /wf/i) {$bw = '(';}   
if (($mode !~ /fm/i) and ($bw =~ /u/i)) {$bw = 'n';}
$ctl_value{'vmode'} = $rc_modes{uc($mode)};
$ctl_value{'vbw'} = $bw;
my $att = $attstring[0];
if ($vfo{'atten'}) {$att = $attstring[1];}
elsif ($vfo{'preamp'}) {$att = $attstring[2];}
$ctl_value{'att_amp'} = lc(Strip($att));
my $sqtone = 'off';
my $digital = '';
if ($mode =~ /fm/i) {
$sqtone = $vfo{'sqtone'};
$ctl_value{'sqtone'} = $sqtone;
$digital = $vfo{'adtype'};
if ($digital) {
$ctl_value{'adtype'} = $audio_types{uc($digital)};
$combo{'sqtone'}->set_sensitive('FALSE');
}
else {
$ctl_value{'adtype'} = 'ANALOG';
$combo{'sqtone'}->set_sensitive(TRUE);
}
$combo{'adtype'}->set_sensitive(TRUE);
}
else {
$ctl_value{'sqtone'} = 'off';
$combo{'sqtone'}->set_sensitive(FALSE);
$ctl_value{'adtype'} = 'ANALOG';
$combo{'adtype'}->set_sensitive(FALSE);
}
foreach my $ctl ('vmode','vbw','att_amp','sqtone','adtype') {
if (!scalar keys %{$combo_text{$ctl}}) {next;}
$combo{$ctl}->signal_handler_block($handler_id{$ctl});
my $value = lc($ctl_value{$ctl});
my $index = $combo_text{$ctl}{$value};
if (!defined $index) {
print "RADIOCTL l5078:Got bad index for $ctl => $value\n";
print Dumper($combo_text{$ctl}),"\n";
next;
}
$combo{$ctl}->set_active($index);
$combo{$ctl}->signal_handler_unblock($handler_id{$ctl});
}### For all supported controls
}
sub dply_service   {
my $text = shift @_;
if (!length($text)) {return;}
my $fg = '';
my $size = 'size="18000"';
my $weight = ' weight="normal" ';
my $font = 'face="DejaVu Sans Mono"';
my $style = 'style="normal"';
$text =~ s/>/\)/g;
$text =~ s/</\(/g;
$text =~ s/\&/and/g;   
$vfo_service->set_markup ('<span ' .
$fg . $font . $size . $weight . $style . '>' .
$text . '</span>');
return 0;
}
sub dply_status {
my $fg = '';
my $bg = '';
my $weight = ' weight="light" ';
my $size = ' size="12000" ';
my $font = 'face="DejaVu Sans Mono"';
my $style = 'style="normal"';
foreach my $ctl (@status_keys,@status2_keys) {
if ($ctl eq '_seq') {next;}
my $value = $vfo{$ctl};
if (!defined $vfo{$ctl}) {
LogIt(1,"DPLY_STATUS:VFO key $ctl was not initialized!");
$value = 0;
}
my $l = length(MAXCHAN);
if ($ctl eq 'index') {$l = length(MAXINDEX);}
if (!looks_like_number($value)) {$value = 0;}
if (($ctl eq 'delay') or ($ctl eq 'resume')) {
if ($value) { $fg = ' foreground="red" ';}
else {
if ($dark) {$fg = ' foreground="white" ';}
else {$fg = ' foreground="black" ';}
}
}
else {$fg = '';}
$status_ctl{$ctl} ->set_markup('<span ' .
$fg . $font . $size . $weight . $style .$bg . '>' .
sprintf("%${l}.${l}i",$value) . '</span>');
}
$fg = '';
$bg = '';
foreach my $dbndx (@dblist) {
my $value = $dbcounts{$dbndx};
if (!looks_like_number($value)) {$value = 0;}
my $l = length(MAXCHAN);
if ($dbndx eq 'freq') {$l = length(MAXINDEX);}
$maxdply{$dbndx} ->set_markup('<span ' .
$fg . $font . $size . $weight . $style .$bg . '>' .
sprintf("%${l}.${l}i",$value) . '</span>');
}
return 0;
}
sub radio_status_dply {
my $status = shift @_;
my $bg = ' background = "red" ';
my $fg = ' foreground="black" ';
my $size = 'size="9000"';
if (lc($status) eq 'connected') {
$bg = ' background="green"';
$fg = ' foreground="white"';
$rescan_button->set_sensitive(FALSE);
}
elsif (lc($status) eq 'connecting'){$bg = ' background = "yellow" ';}
elsif (lc($status) eq 'unresponsive'){$bg = ' background = "blue" ';}
else {### should be disconnected
$rescan_button->set_sensitive(TRUE);
}
my $child = $connect_status->get_child;
$child->set_markup('<span ' .
$fg . $font . $size . $weight . $style .$bg . '>' .
"Radio is " . sprintf("%-12.12s",$status) . "\n" .
"Click To Change      " . '</span>');
return 0;
}
sub radio_parms_dply {
return 0;
}
sub combo_change_proc {
my $cell = shift @_;
my $ctl = shift @_;
my $req = $ctl;
my $value = '';
if (($ctl =~ /mode/i) or ($ctl =~ /bw/i)) {
my $mode = Strip($combo{'vmode'}->get_active_text());
if ($mode =~ /cw-r/i) {$mode = 'cr';}
elsif ($mode =~ /rtty-r/i) {$mode = 'rr';}
elsif ($mode =~ /rtty/i) {$mode = 'rt';}
elsif ($mode =~ /wf/i) {$mode = 'wf';}  
elsif ($mode =~ /lsb/i) {$mode = 'ls';}
elsif ($mode =~ /usb/i) {$mode = 'us';}
my $bw = Strip($combo{'vbw'}->get_active_text());
$bw = substr($bw,0,1);
if ($bw =~ /\(/i) {$bw = '';}
elsif (($bw =~ /u/i) and ($mode !~/fm/i)) {$bw = 'n';}
elsif ($mode =~ /wf/i) {$bw = '';}   
$bw = lc($bw);
$value = "$mode$bw";
$req = 'mode';
}
elsif ($ctl =~ /att/i) {
my $att =  Strip($combo{'att_amp'}->get_active_text());
if ($att =~ /att/i) {$value = 'atten';}
elsif ($att =~ /amp/i) {$value = 'preamp';}
else {$value = 'off';}
$req = 'att';
}
elsif ($ctl =~ /tone/i) {
$value = Strip($combo{'sqtone'}->get_active_text());
$req = 'sqtone';
}
elsif ($ctl =~ /adtype/i)  {
my $adtype = Strip($combo{'adtype'}->get_active_text());
if ($adtype =~ /\(/i) {$value = '';}
else {$value = substr($adtype,0,2);}
$req = 'adtype';
}
else {
LogIt(1,"RadioCtl 5311 COMBO_CHANGE_PROC: No process for $ctl");
return TRUE;
}
my %set = ( '_cmd' => 'vfoctl','_ctl' => $req, '_value' => $value,'_debug' =>5457);
push @req_queue,{%set};
return TRUE;
}
sub init_vfo_combo {
my %strings = ('vmode'    => [@gui_modestring],
'adtype'   => [@gui_adtype],
'vbw'      => [@gui_bandwidth],
'att_amp'  => [@gui_attstring],
'sqtone'   => [@gui_tonestring],
);
my %size = ('vmode' => '20000',
'adtype' => '20000'
);
my %bg = ('vmode'   => [1,.3,0,.5],
'vbw'     => [1,1,0,.1],
'adtype'  => [1,1,0,.1],
'att_amp' => [0,0,1,.1],
'sqtone'  => [0,1,1,.1],
);
foreach my $ctl (keys %strings) {
if ($handler_id{$ctl}) {
$combo{$ctl}->signal_handler_block($handler_id{$ctl});
$handler_id{$ctl} = '';
}
$combo{$ctl}->remove_all();
$combo_text{$ctl} = ();
$ndx = 0;
my @data = @{$strings{$ctl}};
if (scalar @data) {
$combo{$ctl}->set_visible(TRUE);
$combo_label{$ctl}->set_visible(TRUE);
foreach (@data) {
my $str = $_;
if (!$str) {next;}
my $dply_text = Strip($str);
if (!$dply_text) {next;}
$combo{$ctl}->append_text($dply_text);
if ($ctl eq 'vbw') {$str = substr($str,0,1);}
$combo_text{$ctl}{lc($str)} = $ndx;
$ndx++;
}### setting combo string
my $child = $combo{$ctl}->get_child;
if ($bg{$ctl}) {
$child->set_background_rgba(Gtk3::Gdk::RGBA->new(@{$bg{$ctl}}));
}
my $desc = Pango::FontDescription-> new();
$desc->set_weight("bold");
if ($size{$ctl}) {$desc->set_size($size{$ctl});}
$child->override_font($desc);
if ($ndx) {$combo{$ctl}->set_active(0);}
}
else {
$combo{$ctl}->set_visible(FALSE);
$combo_label{$ctl}->set_visible(FALSE);
}
if ($handler_id{$ctl}) {
$combo{$ctl}->signal_handler_unblock($handler_id{$ctl});
}
else {
$handler_id{$ctl} = $combo{$ctl}->signal_connect(changed => \&combo_change_proc,$ctl);
}
}### For each control
return 0;
}## Init_vfo_combo
sub radioselproc {
my ($cell, $dbinfo) = @_;
if ($response_pending) {return 0;}
my $combo_name = lc($combo{'name'}->get_active_text);
if ($radio_def{'active'} and ($radio_def{'name'} eq $combo_name)) {return 0;}
my %req = ('_cmd' => 'newradio');
foreach my $key (keys %{$All_Radios{$combo_name}}) {
$req{$key} = $All_Radios{$combo_name}{$key};
}
$req{'baudrate'} = $combo{'baud'}->get_active_text();
$req{'port'} = $combo{'port'}->get_active_text();
$req{'_caller'} = 5770;
push @req_queue,{%req};
return 0;
}## radioselproc
sub refreshserial {
port_read();
my $default = 0;
$combo{'port'}->remove_all();
foreach my $pt (@ports) {
$combo{'port'}->append_text($pt);
}
$combo{'port'}->set_active($default);
return 1;
}
sub operation_select {
my $widget = shift @_;
my $parms = shift @_;
my $newstate = $parms->{'state'};
if ($newstate eq $progstate) {return TRUE;}
elsif ($newstate eq 'cancel') {
LogIt(0,"$Bold$Green Current operation being canceled");
$rbuttons{'manual'}->set_active(TRUE);
lock($progstate);
$progstate = 'manual';
dply_scan_opt();
return TRUE;
}
elsif ($newstate =~ /manual/i) {
}
elsif ($newstate =~ /freq/i) {
if ($response_pending) {return TRUE;}
}
elsif ($newstate =~ /chan/i) {
if ($response_pending) {return TRUE;}
if ((defined $radio_def{'memory'}) and ($radio_def{'memory'} =~ /dy/i)) {
err_dialog("Radio does NOT support $newstate operation",
'error','channel_scan_operation');
return TRUE;
}
}
elsif ($parms->{'state'} =~ /radio/i) {
if ($response_pending) {return TRUE;}
if (!$radio_def{'radioscan'}) {
err_dialog("Radio does NOT support $newstate operation",
'error','radioscan_operation');
return TRUE;
}
elsif ($radio_def{'radioscan'} == 1) {
err_dialog("Please press SCAN button on radio to start operation",
'info','radioscan_operation');
}
}
elsif ($newstate =~ /search/i) {
if ($response_pending) {return TRUE;}
}
elsif ($newstate =~ /load/i) {
if ($response_pending) {return TRUE;}
if ((defined $radio_def{'memory'}) and ($radio_def{'memory'} =~ 'no')) {
err_dialog("Radio does NOT support LOAD operation",'error','load_operation');
return TRUE;
}
$widget->set_active(TRUE);
my @toggles = (
{'key' => 'clear',     'dply' => 'Clear database before LOAD' },
{'key' => 'noskip',    'dply' => "Keep Empty (0 frequency) channels"},
{'key' => 'nodup',     'dply' => "Discard duplicate frequencies"},
);
my @entries = (
{'key' => 'firstchan',      'dply' => 'Starting channel','init' => $radio_def{'origin'} },
{'key' => 'lastchan',       'dply' => 'Ending channel'  ,'init' => $radio_def{'maxchan'} },
);
my $dialog = Gtk3::Dialog->new_with_buttons("LOAD Operation",
$panels{'main'}{'gtk'},
[qw/modal destroy-with-parent/],
'gtk-cancel' => 'cancel',
'gtk-ok' => 'ok',
);
my $content = $dialog ->get_content_area();
my $text = Gtk3::Label->new("Options for LOAD operation:");
$content->add($text);
$content->add(Gtk3::Label->new(" "));
foreach my $rec (@toggles) {
my $button = Gtk3::CheckButton ->new($rec->{'dply'});
$rec->{'ctl'} = $button;
$content->add($button);
}
if ((defined $radio_def{'memory'}) and ($radio_def{'memory'} =~ 'dy')) {
@entries = ();
$control{'firstchan'} = 0;
$control{'lastchan'} = 999;
}
else {
foreach my $rec (@entries) {
my $box = Gtk3::Entry->new;
$box -> set_width_chars(4);
$box -> set_text($rec->{'init'});
$rec->{'ctl'} = $box;
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start($box,FALSE ,FALSE,0);
my $text =  Gtk3::Label->new($rec->{'dply'});
$hbox[0]->pack_start($text,FALSE ,FALSE,0);
$content->add($hbox[0]);
}
}
my $emsg = Gtk3::Label->new("");
$content->add($emsg);
DLOOP1:
while (TRUE) {
$dialog->show_all;
my $response = $dialog->run;
if ($response eq 'ok') {
foreach my $rec (@entries) {
my $key = $rec->{'key'};
my $ctl = $rec->{'ctl'};
my $value = $ctl->get_text();
if ((!looks_like_number($value)) or
($value < $radio_def{'origin'}) or
($value > $radio_def{'maxchan'}) ) {
my $msg = "'$value' is not valid for $rec->{'dply'}!";
my $fg = 'foreground="red" ';
my $bgc = 'background="white"';
$weight = ' weight="heavy" ';
$emsg ->set_markup("<span $fg $bgc $weight > $msg </span>");
next DLOOP1;
}
$control{$key} = $value;
}
if ($control{'firstchan'} > $control{'lastchan'}) {
my $temp = $control{'firstchan'};
$control{'firstchan'} = $control{'lastchan'};
$control{'lastchan'} = $temp;
}
foreach my $rec (@toggles) {
my $key = $rec->{'key'};
my $ctl = $rec->{'ctl'};
$control{$key} = $ctl->get_active();
}
$dialog->destroy;
last DLOOP1;
}### OK response
else {
$dialog->destroy;
LogIt(1,"User canceled LOAD operation");
$widget->set_active(FALSE);
$rbuttons{$progstate}->set_active(TRUE);
return TRUE;
}
}
}### Load state start
else {
LogIt(1,"RADIOCTL l5983:Missing State change code for $newstate");
}
$widget->set_active(TRUE);
lock($progstate);
$progstate = $newstate;
dply_scan_opt();
LogIt(0,"$Bold$White OPERATION_SELECT:Changed scan mode to $Green$progstate");
threads->yield;
return TRUE;
}
sub inc_press {
my $widget = shift @_;
my $parms   = shift @_;
my ($ctl,$direction) = split ',',$parms;
my $sigkill = FALSE;
if (!$digit_names{$ctl}{'enable'}) {return 0;}
$up_down_button{'widget'} = $widget;
$up_down_button{'parms'} = $parms;
$up_down_button{'delay'} = .8;
$up_down_button{'time_stamp'} = Time::HiRes::time();
my $value = 0;
if ($ctl eq 'vstep') {
my $inc = 100;
if ($direction eq 'down') {$inc = -$inc;}
my $newstep = $vfo{'step'};
if (!$newstep) {$newstep = MINFREQ;}
$newstep = $newstep + $inc;
if ($newstep > MAXFREQ) {$newstep = MINFREQ;}
elsif ($newstep < MINFREQ) {$newstep = MAXFREQ;}
lock %vfo;
$vfo{'step'} = $newstep;
dply_vfo_num('vstep',$newstep);
return 0;
}
else {
my %set = ('_cmd' => 'incr', '_ctl' => $ctl,
'_dir' => $direction, '_debug' => 5593);
push @req_queue,{%set};
}
return 0;
}### INC_PRESS process
sub focus_lost {
my ($widget, $event, $ctl) = @_;
return FALSE;
return FALSE;
}
sub frequency_entry {
my ($widget, $ctl) = @_;
my $text = $widget->get_text;
if (length($text) == 0) {return 0;}
$widget->set_text("");
if (!$digit_names{$ctl}{'enable'}) {return 0;}
if ($ctl eq 'vfreq') {
my $frq = freq_to_rc($text);
if (($frq < MINFREQ) or ($frq > MAXFREQ))  {
err_dialog("$text is not a valid frequency",'error','frequency_entry');
return FALSE;
}
my %set = ( '_cmd' => 'vfoctl','_ctl' => $ctl, '_value' => $frq, '_debug' => 5494);
push @req_queue,{%set};
}
elsif ( $ctl eq 'vstep') {
my $frq = freq_to_rc($text);
if (($frq < MINFREQ) or ($frq > MAXFREQ)) {
err_dialog("$text is not a valid step",'error','frequency_entry');
return FALSE;
}
lock %vfo;
$vfo{'step'} = $frq;
dply_vfo_num('vstep',$frq);
}
else {LogIt(6357,"VFO_FREQ_PROC:No process for control=>$ctl");}
return TRUE;
}
sub number_entry {
my ($widget, $ctl) = @_;
my $value = $widget->get_text;
if ($value eq '') {return FALSE;}
if ($digit_names{$ctl}{'title'} and (!$digit_names{$ctl}{'enable'})) {
$widget->set_text("");
return 0;
}
my $bad = '';
my $maxchan = MAXCHAN;
my $minchan = 0;
if ($ctl eq 'rchan') {
$maxchan = 999;
}
elsif ($ctl eq 'vchan') {
$minchan = 1;
}
elsif ($ctl =~ /dly/i) {
$minchan = -(MAXCHAN);
}
if ( (!looks_like_number($value)) or ($value < $minchan) or ($value > $maxchan)) {
$bad = "Value must be $minchan or positive number less than or equal to $maxchan";
}
else {
$value = $value + 0;
$widget->set_text("");
if ($ctl =~ /chan/i)  {   
$widget->set_text("");
my %set = (
'_cmd' => 'vfoctl',
'_ctl' => $ctl,
'_value' => $value,
'_debug' => 5492,
);
push @req_queue,{%set};
}### Channel change request
elsif ($ctl =~ /dly/i) {
$control{'dlyrsm_value'} = $value;
dply_scan_opt();
}
elsif ($ctl =~ /start/i) {
$control{'start_value'} = $value;
dply_scan_opt();
}
elsif ($ctl =~ /stop/i) {
$control{'stop_value'} = $value;
dply_scan_opt();
}
else {
my $ctl_key = $ctl . '_value';
$opt_value{$ctl} -> set_markup ('<span ' .
'size="9000" face="DejaVu Sans Mono"' .
'weight="light" style="italic">' .
$value .
'</span>');
$control{$ctl_key} = $value;
}
}### if not bad
if ($bad) {
err_dialog ("invalid input ($value) $bad!",'error','number_entry');
}
return TRUE;
}
sub log_filename_proc {
return TRUE;
my ($widget, $ctl) = @_;
my $value = $widget->get_text;
my $ctlname = $ctl . '_file';
if (!$value) {
$control{$ctlname} = '';
$opt_button{$ctl}->set_sensitive(FALSE);
return TRUE;
}
my $filespec = "$settings{'logdir'}/$value";
if (-l $filespec) {### Symlink?
$filespec = readlink $filespec;
}
if (-d $filespec) {
my $msg = "'$value' resolves to '$filespec' which is a directory.\n      Setting bypassed!";
err_dialog($msg,'error','log_filename_proc');
LogIt(1,$msg);
$widget->set_text($control{$ctlname});
return TRUE;
}
my $finalmsg = "Log data file '$filespec'";
if (-e $filespec) {
my $msg = "File $filespec already exists!";
LogIt(1,"$msg");
my $dialog = Gtk3::Dialog->new_with_buttons("File Exists",
$panels{'main'}{'gtk'},
[qw/modal destroy-with-parent/],
'gtk-cancel' => 'cancel',
'gtk-ok' => 'ok',
);
my $content = $dialog ->get_content_area();
my $text = Gtk3::Label->new("$msg");
my $font = 'face="DejaVu Sans Mono"';
my $size = 'size="18000"';
my $weight = ' weight="bold" ';
my $red = 'foreground="red"';
my $markup = "<span $font $size $weight $red >" .
"$msg\n</span> <span $font $size $weight >             OK to replace? </span>";
$text->set_markup ($markup);
$content->add($text);
my $action_area = $dialog->get_action_area();
$action_area->set_property("halign","GTK_ALIGN_CENTER");
$dialog->show_all;
my $response = $dialog->run;
$dialog->destroy;
if ($response ne 'ok') {
LogIt(1,"User canceled setting of existing logfile");
return TRUE;
}
$finalmsg = "$finalmsg will be created for logging";
}
else {
$finalmsg = "$finalmsg will be appended to for logging";
}
$control{$ctlname} = $value;
$opt_button{$ctl} ->set_sensitive(TRUE);
add_message($finalmsg,0);
LogIt(0,"$Bold$finalmsg");
return TRUE;
}
sub vfo_digit {
my $widget = shift @_;
my $gevt = shift @_;
my $parm = shift @_;
my $digitno = $parm->{'digit'};
my $type = $parm->{'type'};
my $action = $parm->{'event'};
if (!$digit_names{$type}{'enable'}) {return 0;}
my $curtext = $digit{$type}{$digitno}{'ctl'}->get_text();
if ($curtext =~ /[a-z,A-Z,\.]/) {return 0;}
if (($action eq 'scroll-event') or ($action eq 'button_press_event')) {
my $add = 1;
if ($action eq 'scroll-event') {
my $event = '';
$event = Gtk3->get_current_event;
if ($event and ($event->direction() eq 'down')) {$add = -1;}
}
else {
my $button = $gevt->button();
if ($button == 1) {$add = 1;}
elsif ($button == 3) {$add = -1;}
else {return 0;}
}
if ($curtext =~ /[0-9]/) { 
$curtext = $curtext + $add;
if ($curtext < 0) {$curtext = 9;}
if ($curtext > 9) {$curtext = 0;}
}
else {
if ($add > 0) {$curtext = 1;}
else {$curtext = 9;}
}
my $count = $digit_names{$type}{'len'};
my $newval = '';
foreach my $i (0..($count-1)) {
my $newdigit = $digit{$type}{$i}{'ctl'}->get_text();
if ($i == $digitno) {$newdigit = $curtext;}
$newval = "$newdigit$newval";
}
if (($type =~ /freq/i) or ($type =~ /step/i)) {
$newval = freq_to_rc($newval);
}
if ($type =~ /step/i) {
lock %vfo;
$vfo{'step'} = $newval;
dply_vfo_num($type,$newval);
}
else {
lock %vfo;
$vfo{'direction'} = $add;
my %set = ( '_cmd' => 'vfoctl','_ctl' => $type, '_value' => $newval,'_debug' => 5368);
push @req_queue,{%set};
}
}
elsif (($action eq 'enter_notify_event') or ($action eq 'motion_notify_event')) {
if (!$digit{$type}{$digitno}{'sel'}) {
$digit{$type}{$digitno}{'sel'} = TRUE;
}
}
elsif ($action eq 'leave_notify_event') {
$digit{$type}{$digitno}{'sel'} = FALSE;
}
return TRUE;
}
sub squelch_bar_change {
my  $widget = shift @_;
$control{'squelch'} = int($widget->get_value);
my $dply = int($control{'squelch'}/10);
if ($dply > MAXSIGNAL) {$dply = MAXSIGNAL;}
my $color =  'foreground="red"';
if ($dply) {
$dply = '@' . sprintf("%2.2u","$signal_values[$dply]");
}
else {
$dply = 'Off';
$color = 'foreground="green"';
}
my $markup = '<span face="DejaVu Sans Mono">squelch </span>' .
'<span face="DejaVu Sans Mono" ' . $color . '>' . $dply . '</span>';
$sqlvalue ->set_markup($markup);
if ($Debug1) {
print "\nsquelch value from squelch_bar_change=$control{'squelch'}\n";
}
return 0;
}
sub make_view_menu_item {
my $title = shift @_;
my $window = shift @_;
my $winref = shift @_;
my $global = shift @_;
if (!$global) {$global = '';}
my $wintype = shift @_;
if (!$wintype) {$wintype = 'panel';}
my $col = shift @_;
if (!$col) {$col = '';}
my $item = Gtk3::CheckMenuItem->new("$title");
my %view_parms = ('title' => $title,
'window' => $window,
'winref' => $winref,
'wintype' => $wintype,
'global'  => $global,
'col'     => $col,
);
$item->signal_connect('toggled' => \&view_ops,\%view_parms);
if (!$global) {$item->set_active(TRUE);}
else {$item->set_active($$global);}
my $child = $item->get_child;
return ($item);
}
sub make_menu {
my $parent = shift @_;
my $menu_ref  = shift @_;
my $dbndx = shift @_;
my $routine = \&menu_ops;
my $menu = Gtk3::Menu->new();
foreach my $rcd (@{$menu_ref}) {
my $key = $rcd->{'name'};
if ($key eq '_line') {
my $separator = Gtk3::SeparatorMenuItem->new();
$menu->append($separator);
next;
}
if ($rcd->{'dbn'} and ($rcd->{'dbn'} !~ /$dbndx/)) {next;}
my $title = $rcd->{'title'};
my $icon = $rcd->{'icon'};
$menu_item{$dbndx}{$key} = Gtk3::MenuItem->new();
my $image = Gtk3::Image->new_from_icon_name($rcd->{'icon'},'menu');
my $label = Gtk3::Label->new($title);
my $hbox = Gtk3::Box->new('horizontal',5);
$hbox->pack_start($image,FALSE,FALSE,0);
$hbox->pack_start($label,FALSE,FALSE,0);
$menu_item{$dbndx}{$key} -> add($hbox);
$menu_item{$dbndx}{$key} -> show_all;
my %parms = (
'name' => $key,
'dbndx' => $dbndx,
);
$menu_item{$dbndx}{$key}->signal_connect('activate' =>$routine,\%parms);
$menu->append($menu_item{$dbndx}{$key});
}
$menu_item{$dbndx}{$parent} = $menu;
my $submenu = Gtk3::MenuItem->new($parent);
$submenu->set_submenu($menu);
$child = $submenu->get_child;
return $submenu;
}
sub add_view_menu {
my $key = shift @_;
if ($panels{$key}{'type'} eq 'p') {
my $parent = $panels{$key}{'parent'};
if (!$parent) {$parent = 'main';}
$view_menu{$parent} -> append(make_view_menu_item($panels{$key}{'title'},$key,$panels{$key}{'gtk'}));
}
return 0;
}
sub swap_proc {
LogIt(1,"Swap not yet functional");
return 0;
my ($node1, $node2, $dbndx) = @_;
print "5323 swap proc $node1 $node2 $dbndx \n";
my $max = $guidb{$dbndx};
my $emsg = '';
if ($node1 !~ /[0-9]/) {
$emsg = "Node 1 Invalid input ($node1)\n Data must be numeric!\n";}
else {
if ($node1  > $max) {
$emsg = "Node 1 Invalid input ($node1)\n "
. "Data must be less than or = $max!\n";}
}
if ($node2 !~ /[0-9]/) {
$emsg = $emsg .
"Node 2 invalid input ($node2)\n Data must be numeric!\n";
}
else {
if ($node2  > $max) {
$emsg = $emsg .
"Node 2 invalid input ($node2)\n" .
" Data must be less than or = $max!\n";
}
}
my $iter1;
my $iter2;
if (!$emsg) {
$iter1 = $liststore{$dbndx}->get_iter_from_string($node1);
$iter2 = $liststore{$dbndx}->get_iter_from_string($node2);
if (!$iter1) {$emsg = $emsg . "Empty iter for node 1!\n";}
if (!$iter2) {$emsg = $emsg . "Empty iter for node 2!\n";}
}
if (!$emsg) {
my @ch;
$ch[1] = $liststore{$dbndx}->get($iter1,$col_xref{'index'});
$ch[2] = $liststore{$dbndx}->get($iter2,$col_xref{'index'});
my %chan1 = ('_dbn' => $dbndx,'channel' => $ch[1],'node' => -1);
my %chan2 = ('_dbn' => $dbndx,'channel' => $ch[2],'node' => -1);
get_db_data(\%chan1,'swap_proc');
get_db_data(\%chan2,'swap_proc');
$chan1{'channel'} = $ch[2];
$chan2{'channel'} = $ch[1];
set_db_data(\%chan1,'swap_proc');
set_db_data(\%chan2,'swap_proc');
add_message("Swapped channel $ch[1] with $ch[2]");
}
if ($emsg) {
err_dialog($emsg,'error','swap_proc');
return 1;
}
else {add_message("Error! NULL iter on one or both channels!",1);}
return 0;
}
sub find_iter {
my $dbndx = shift @_;
my $seq = shift @_;
my $makenew = shift @_;
my $sync = shift @_;
my $caller = shift @_;
my $iter = -1;
if (!$liststore{$dbndx}) {LogIt(7010,"FIND_ITER:no liststore reference for database->$dbndx caller=>$caller");}
if (!$col_xref{'index'}) {LogIt(7776,"No DBCOL for 'index'");}
foreach my $row (0..($guidb{$dbndx} - 1) ) {
my $itertest = $liststore{$dbndx}->get_iter_from_string($row);
if ($itertest) {
my $index = $liststore{$dbndx}->get($itertest,$col_xref{'index'});
if ($index) {
if ($index == $seq) {return $itertest;}
}
else {LogIt(1,"FIND_ITER:No index found for row=$row");}
}### itertest
}### Row search
if ($makenew) {
$iter = $liststore{$dbndx}->append;
$guidb{$dbndx}++;
foreach my $key (keys %drop_list) {
my $colno =  $drop_list{$key}{'model'};
if (!defined $colno) {
print Dumper(%drop_list),"\n";
LogIt(7848,"No col number for drop_list $key");
}
$liststore{$dbndx} ->set($iter,$colno,$drop_list{$key}{'liststore'});
}
$liststore{$dbndx} ->set($iter,$col_xref{'index'},$seq);
if ($sync) {
my %request = ();
foreach my $key (keys %clear) {
$request{$key} = $clear{$key};
}
$request{'_dbn'} = $dbndx;
$request{'_seq'} = $seq;
$request{'_cmd'} = 'sync';
$request{'debug'} = 'find_iter';
push @req_queue,{%request};
}
}### makenew
return $iter;
}### FIND_ITER
sub get_db_data {
my $ref = shift @_;
my $caller = shift @_;
if (!$ref) {LogIt(7495,"GET_DB_DATA:Hash ponter is empty! Caller=$caller"); }
foreach my $key ('sysno','index','dbtype') {LogIt(7496,"GET_DB_DATA:Missing key $key! Caller=$caller");}
my $sysno = $ref->{'sysno'};
my $index =  $ref->{'index'};
my $dbtype = $ref->{'dbtype'};
return;
}
sub set_db_data {
my $dbndx = shift @_;
my $indexes = shift @_;
my $keyref = shift @_;
my @options = @_;
if (!$dbndx) {LogIt(6411,"No DBN for SET_DB_DATA!");}
if (!$indexes) {LogIt(6412,"No Indexes for SET_DB_DATA!");}
if (!$keyref) {LogIt(6413,"No Keyref for SET_DB_DATA!");}
if (!$liststore{$dbndx}) {LogIt(6414,"SET_DB_DATA:Liststore for $dbndx was not defined");}
my $newrec = FALSE;
foreach my $opt (@options) {
if (lc($opt) eq 'create') {$newrec = TRUE;}
}
foreach my $item ('clear_db','sortf','sortc','renum') {
if ($menu_item{$dbndx}{$item} and ($progstate !~ /chan/i)) {
$menu_item{$dbndx}{$item}->set_sensitive(TRUE);
}
}
foreach my $seq (@{$indexes}) {
my $iter = $iters{$seq};
if (!$iter) {$iter = find_iter($dbndx,$seq,TRUE,FALSE,6419);}
if ($iter == -1) {LogIt(6431,"SET_DB_DATA:Iter was -1");}
my $path = $liststore{$dbndx}->get_path($iter);
my $found = FALSE;
foreach my $key (keys %{$keyref}) {
if ($key =~ /^\_.*$/) {next;}     
if ($key eq 'rsvd') {next;}
my $ref = $dply_def{$key};
if (!$ref) {next;}
my $colndx = $ref->{'dbcol'};
if (!$colndx) {LogIt(1,"SET_DB_DATA:No 'dbcol' for $key");next;}
my $dplyndx = $ref->{'dplycol'};
if (!$dplyndx) {LogIt(1,"SET_DB_DATA:No 'dplycol' for $key");next;}
$found = TRUE;
my $value = $keyref->{$key};
if (!defined $value) {$value = $clear{$key};}
if (($model[$colndx] eq 'Glib::Int') and ($value eq '')) {$value = -1;}
elsif ($ref->{'type'} eq 'freq') {
my $dplyfreq = rc_to_freq($value);
$liststore{$dbndx}->set($iter,$dplyndx,$dplyfreq);### display formatted as MHZ
}
elsif ($ref->{'type'} eq 'time') {
my $dplystamp = '--';
if (looks_like_number($value) and ($value > 2)) {
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
localtime($value);
$dplystamp = sprintf("%02.2i",($mon +1)) . '/' .
sprintf("%02.2i",$mday) . '/' . ($year+ 1900) .
' ' . sprintf("%02.2i",$hour) . ':' . sprintf("%02.2i",$min);
}
$liststore{$dbndx}->set($iter,$dplyndx,$dplystamp);
}
elsif ($key eq 'mode') {
if ($value eq '') {$value = 'FM';}
else {
my $cmp = Strip(lc($value));
foreach my $mode (@modestring) {
if ($cmp eq Strip(lc($mode))) {
$value = $mode;
last;
}
}
}
}
else { }
$liststore{$dbndx}->set($iter,$colndx,$value,);
}### For every key specified
my $l = length(MAXINDEX);
$liststore{$dbndx}->set($iter,$col_xref{'index'},sprintf("%${l}.${l}i",$seq));
}### For every index specified
%iters = ();
return 0;
}### set_db_data
sub toggleproc {
if ($response_pending) {return 0;}
my ($cell, $row, $dbinfo) = @_;
my $dbndx = $dbinfo->{'dbndx'};
my $colnum = $dbinfo->{'coldb'};
my $keyword = $dbinfo->{'key'};
if (!$keyword) {LogIt(7849,"TOGGLEPROC:No key for column $colnum in comboproc for database $dbndx");}
my $iter = $liststore{$dbndx}->get_iter_from_string ($row);
my $value = ! $liststore{$dbndx}-> get($iter,$colnum);
my $seq = $liststore{$dbndx} -> get($iter,$col_xref{'index'});
my %request = ('_seq' => $seq, '_dbn' => $dbndx, '_cmd' => 'sync',
$keyword => $value);
push @req_queue,{%request};
return 0;
}
sub comboproc {
if ($response_pending) {return 0;}
my ($cell, $row, $value, $dbinfo) = @_;
my $dbndx = $dbinfo->{'dbndx'};
my $colnum = $dbinfo->{'coldb'};
my $keywd = $dbinfo->{'key'};
if (!$keywd) {LogIt(7798,"COMBOPROC:No key for column $colnum in comboproc for database $dbndx");}
my $iter = $liststore{$dbndx}->get_iter_from_string ($row);
$value = Strip(lc($value));
my $seq = $liststore{$dbndx} -> get($iter,$col_xref{'index'});
my %request = ('_seq' => $seq, '_dbn'=> $dbndx, '_cmd' => 'sync',
$keywd => $value,
);
push @req_queue,{%request};
return 0;
}
sub db_num_proc {
if ($response_pending) {return 0;}
my ($cell, $row, $value, $dbinfo) = @_;
if (!defined $value) {return;}
if ($value eq "") {return;}
my $dbndx = $dbinfo->{'dbndx'};
my $colnum = $dbinfo->{'coldb'};
my $dplynum = $dbinfo->{'dplycol'};
my $extra = $dbinfo->{'extra'};
my $keywd = $dbinfo->{'key'};
my $type  = $dbinfo->{'type'};
if (!$keywd) {LogIt(7798,"COMBOPROC:No key for column $colnum in comboproc for database $dbndx");}
my $iter = $liststore{$dbndx}->get_iter_from_string ($row);
my $seq = $liststore{$dbndx} -> get($iter,$col_xref{'index'});
my $emsg = '';
if (($keywd eq 'channel') and (substr(Strip($value),0,1) eq '-')) {$value = -1;}
if (!looks_like_number($value)) {$emsg = "$value is not a valid number!";}
else {
if ($type eq 'freq') {
my $frq = freq_to_rc($value);
if (($frq < 0) or ($frq > MAXFREQ)) {$emsg = "$value is out of range";}
$value = $frq;
}
}
my %request = ('_seq' => $seq, '_dbn'=> $dbndx, '_cmd' => 'sync',
$keywd => $value,
);
if ($emsg) {
err_dialog($emsg,'error','db_num_proc');
return 0;
}
push @req_queue,{%request};
return 0;
}
sub db_text_proc {
if ($response_pending) {return 0;}
my ($cell, $row, $value, $dbinfo) = @_;
my $dbndx = $dbinfo->{'dbndx'};
my $colnum = $dbinfo->{'coldb'};
my $dplynum = $dbinfo->{'dplycol'};
my $extra = $dbinfo->{'extra'};
my $keywd = $dbinfo->{'key'};
my $type  = $dbinfo->{'type'};
if (!defined $value) {$value = '';}
if (!$keywd) {LogIt(7798,"COMBOPROC:No key for column $colnum in comboproc for database $dbndx");}
my $iter = $liststore{$dbndx}->get_iter_from_string ($row);
my $seq = $liststore{$dbndx} -> get($iter,$col_xref{'index'});
my %request = ('_seq' => $seq, '_dbn'=> $dbndx, '_cmd' => 'sync',
$keywd => $value,
);
push @req_queue,{%request};
return 0;
}
sub chan_render {
my ($colnum, $cell, $model, $iter, $dbinfo) = @_;
my $mycol = $dbinfo->{'dplycol'};
if (!$mycol) {
LogIt(1,"Empty my column for $dbinfo dplycol");
$mycol = 0;
}
my $dbndx = $dbinfo->{'dbndx'};
my $key   = $dbinfo->{'key'};
my $data = $cell->get("text");
if (!$data) {$data = 0;}
my $l = length(MAXCHAN);
if ($dbndx eq 'freq') {$l = length(MAXINDEX);}
if (looks_like_number($data)) {
if ($data < 0) {$data = '  -  ';}
else {$data  = sprintf("%${l}.${l}i",$data);}
}
else {$data = '  -  ';}
if ($key eq 'index') {
if ($chan_active{$dbndx} == $data)  {### %chan_active is set in SCANNER thread
$cell->set_property("background","red","foreground","white");
}
else {
if ($dark) {$cell->set_property("background","black","foreground","white");}
else {$cell->set_property("background","white","foreground","black");}
}
}
else {
if ($colors{$key}) {
if ($dark) {$cell->set_property("foreground",$colors{$key});}
else {$cell->set_property("background",$colors{$key});}
}
}
$cell->set("text" => $data);
return 0;
}
sub time_render {
my ($colnum, $cell, $model, $iter, $dbinfo) = @_;
my $mycol = $dbinfo->{'dplycol'};
if (!$mycol) {
LogIt(1,"Empty my column for $dbinfo dplycol");
$mycol = 0;
}
my $dbndx = $dbinfo->{'dbndx'};
my $key   = $dbinfo->{'key'};
my $value = $cell->get("text");
print "RADIOCTL4-TIME_RENDER:column->$colnum cell->$cell model->$model iter-$iter value=>$value\n";
print Dumper($dbinfo),"\n";
my $dplystamp = "     ----     ";
if (looks_like_number($value) and ($value > 2)) {
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
localtime($value);
$dplystamp = sprintf("%02.2i",($mon +1)) . '/' .
sprintf("%02.2i",$mday) . '/' . ($year+ 1900) .
' ' . sprintf("%02.2i",$hour) . ':' . sprintf("%02.2i",$min);
}
if ($colors{$key}) {
if ($dark) {$cell->set('forground-gdk',$colors{$key});}
else {$cell->set('background-gdk',$colors{$key});}
}
$cell->set("text" => $dplystamp);
return 0;
}
sub number_render {
my ($colnum, $cell, $model, $iter, $dbinfo) = @_;
my $mycol = $dbinfo->{'dplycol'};
if (!$mycol) {
LogIt(1,"Empty my column for $dbinfo dplycol");
$mycol = 0;
}
my $dbndx = $dbinfo->{'dbndx'};
my $key   = $dbinfo->{'key'};
my $value = $cell->get("text");
if (!$value) {$value = 0;}
if ($colors{$key}) {
if ($dark) {$cell->set_property('foreground',$colors{$key});}
else {$cell->set_property('background',$colors{$key});}
}
$cell->set("text" => $value);
return 0;
}
sub numsort {
my ($liststore, $itera, $iterb, $dbinfo) = @_;
my ($sortkey, $dbndx, $colndx) = split ' ', $dbinfo;
my $v1 = $liststore->get ($itera,$sortkey);
my $v2 = $liststore->get ($iterb,$sortkey);
my $sortdir = $treecol{$dbndx}[$colndx]->get_sort_order();
if ($v1 == $v2) {return 0;}
if ((!$v2) and ($sortdir eq 'ascending')) {return -1;}
return $v1 <=> $v2;
}
sub stringsort {
my ($liststore, $itera, $iterb, $dbinfo) = @_;
my ($sortkey, $dbndx, $colndx) = split ' ', $dbinfo;
my $v1 = $liststore->get ($itera,$sortkey);
my $v2 = $liststore->get ($iterb,$sortkey);
if (!defined $v1) {$v1 = '';}
if (!defined $v2) {$v2 = '';}
my $sortdir = $treecol{$dbndx}[$colndx]->get_sort_order();
if ($v1 eq $v2) {return 0;}
if (looks_like_number($v1) and looks_like_number($v2)) {return $v1 <=> $v2;}
return $v1 cmp $v2;
}
sub test_ops {
my ($parm1, $parm2, $parm3) = @_;
print "test_ops parm1=>$parm1 parm2=>$parm2 parm3=>$parm3 \n";
return FALSE;
}
sub message_dply {
my ($new_msg,$severity) = @_;
if (!$message_box) {
print "$new_msg (no message box)\n";
return;
}
my $color = 'black';
my $weight = 'normal';
if ($severity) {
if ($severity == 2) {$color = 'green';}
elsif ($severity ==3 ) {$color = 'black';}
else {
$color = 'red';
$weight = 'bold';
}
}
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
localtime(time);
my $timestamp = sprintf("%2.2u",($mon +1))    . '/' .
sprintf("%2.2u",$mday)       . '/' .
sprintf("%4.4u",($year+ 1900)) . " " .
sprintf("%2.2u",$hour)         . ":" .
sprintf("%2.2u",$min)         . ':' .
sprintf("%2.2u",$sec)         . ' '
;
if ($severity > 1) {$timestamp = '';}
my $buffer = $message_box->get_buffer();
if (!$top_messages) {
if ($severity != 3) {
$buffer->insert_with_tags_by_name ($buffer->get_end_iter(),$timestamp,"blue",);
}
$buffer->insert_with_tags_by_name ($buffer->get_end_iter()," $new_msg\n",$color,);
$message_box->scroll_to_iter ($buffer->get_end_iter(), 0, TRUE, 0,1);
my $adjustments = $scrolled{'messages'}->get_vadjustment();
$adjustments->set_value($adjustments->get_upper());
}
else {
$buffer->insert_with_tags_by_name ($buffer->get_start_iter()," $new_msg\n",$color,);
if ($severity != 3) {
$buffer->insert_with_tags_by_name ($buffer->get_start_iter(),$timestamp,"blue",);
}
}
}
sub testclick {
foreach my $parm (@_) {
print "parm=$parm\n";
}
}
sub port_read {
@ports = ();
%ports = ();
push @ports, "(none)";
$ports{"(none)"} = 0;
if ($os eq "LINUX") {
my @tty = </dev/tty*> ;
foreach my $type ('ttyacm','ttyusb','ttys') {
foreach my $file (@tty) {
if ($file =~ /$type/i) {
my $len = push @ports,$file;
$ports{$file} = ($len - 1 );
}
}
}
}
elsif ($os eq "WINDOWS") {
foreach my $port ('com1','com2','com3','com4') {
my $len = push @ports,$port;
$ports{$port} = ($len - 1 );
}
}
return 0,
}
sub find_combo_string {
my $combo = shift @_;
my $string = shift @_;
my $add = shift @_;
my $i = 0;
my $model = $combo->get_model();
my $cmpr = Strip(lc($string));
while (TRUE) {
my $iter = $model->get_iter_from_string($i);
last if not defined $iter;
my $newstr = Strip(lc($model->get($iter,0)));
if ($newstr eq $cmpr) {
$combo->set_active($i);
return 0;
}
++$i;
}
if ($add) {
$combo->append_text($string);
$combo->set_active($i);
return 1;
}
return 2;
}
sub menu_ops {
my $widget = shift @_;
my $parms = shift @_;
my $dbndx = $parms->{'dbndx'};
my $command = $parms->{'name'};
my $filename = '';
if ($response_pending) {
LogIt(1,"Response pending. Menu operation nullified");
return 0;
}
if ($command eq 'help') {
LogIt(1,"No help function available at this time!");
}
elsif (($command eq 'open') or ($command eq 'opennew')) {
my $file_dialog = Gtk3::FileChooserDialog->new(
$command . " Radioctl file",
$panels{'main'}{'gtk'},
'open',
'gtk-cancel'=> 'cancel',
'gtk-ok' => 'ok'
);
my $response = $file_dialog->run;
if ($response eq 'ok') {
$filename = $file_dialog->get_filename;
}
$file_dialog->destroy;
if ($filename) {
my %request = ('_cmd' => 'open', 'filespec' =>$filename, 'replace' => FALSE);
if ($command eq 'opennew') {$request{'replace'} = TRUE;}
push @req_queue,{%request};
$lastfilesave = $filename;
}
}### OPEN process
elsif ($command eq 'save') {
my %request = ('_cmd' => 'save');
my $dialog = Gtk3::Dialog->new_with_buttons('Save',
$panels{'main'}{'gtk'},
[qw/modal destroy-with-parent/],
'gtk-cancel' => 'cancel',
'gtk-ok' => 'ok',
);
my $filetext =  Gtk3::Entry->new();
$filetext->set_text($lastfilesave);
my $filespec = '';
my $getfilename = Gtk3::Button->new_with_label("Enter full filespec above. \n Press this button to search");
my $errmsg = Gtk3::Label->new();
$getfilename->signal_connect(pressed =>
sub {
$errmsg->set_text('');
my $file_dialog = Gtk3::FileChooserDialog->new(
$command . " Radioctl file",
$dialog,
'save',
'gtk-cancel'=> 'cancel',
'gtk-ok' => 'ok'
);
my $response = $file_dialog->run;
if ($response eq 'ok') {
$filetext->set_text($file_dialog->get_filename);
}
$file_dialog->destroy;
}### Sub for getfilename action
);
my $content = $dialog->get_content_area();
$content->add($filetext);
$content->add($getfilename);
$content->add($errmsg);
my %usedb = ();
$content->show_all;
my $response = '';
while (!$response) {
$response = $dialog->run;
if ($response eq 'ok') {
$filespec = Strip($filetext->get_text());
if (!$filespec) {
my $font = 'face="DejaVu Sans Mono"';
my $size = 'size="18000"';
$size = '';
my $fg = 'foreground="red"';
my $weight = 'weight="bold" ';
$errmsg->set_markup ('<span ' . "$fg $font $size $weight " . '>' .
"Filename cannot be blank" . '</span>');
$response = '';
}
else {
if ((-e $filespec) and ($filespec ne $lastfilesave)) {
my $confirm = Gtk3::MessageDialog->new(
$dialog,
'modal',
'question', 'cancel',
"Overwrite existing  $filespec");
$confirm->add_button('overwrite','ok');
$response = $confirm->run;
if ($response eq 'yes') {
$request{'append'} = TRUE;
$response = 'ok';
}
$confirm->destroy;
}
}### filespec has been specified
}### response is OK
}### any response
if ($response eq 'ok') {
foreach my $key (keys %usedb) {
$request{$key} = $usedb{$key}{'ctl'}->get_active;
}
$request{'filespec'} = $filespec;
$lastfilesave = $filespec;
push @req_queue,{%request};
}### OK response
$dialog->destroy;
}### Save command
elsif ($command eq 'create') {
my %request = ('_cmd' => 'create', '_dbn' => $dbndx);
push @req_queue,{%request};
}
elsif ($command eq 'delete') {
if (get_selected($dbndx)) {
LogIt(1,"RADIOCTL l7226, No selected records to delete!");
}
else  {
my %request = ('_cmd' => 'batch', '_dbn' => $dbndx, '_type' => 'delete');
lock $response_pending;
$response_pending = TRUE;
show_long_run('please wait');
unshift @req_queue,{%request};
}
}### Delete process
elsif ($command eq 'edit'  ) {
my @editable = ('valid','sysno','groupno','mode','dlyrsm');
if ($progstate =~ /chan/i) {@editable = ('valid','dlyrsm');}
my $dialog = Gtk3::Dialog->new_with_buttons('Edit',
$panels{$dbndx}{'gtk'},
[qw/modal destroy-with-parent/],
'gtk-cancel' => 'cancel',
'gtk-ok' => 'ok',
);
my $content = $dialog->get_content_area();
if (get_selected($dbndx)) {
LogIt(1,"RADIOCTL l8272, No selected records to edit!");
}
else {
my %use = ();
my %value =();
foreach my $fld (@editable) {
if ($fld eq 'valid') {
$use{$fld}  = Gtk3::CheckButton ->new("Change $fld to =>");
$value{$fld} = Gtk3::CheckButton ->new("Valid");
}
elsif (($fld eq 'dlyrsm') or ($fld eq 'groupno')) {
if ($dbndx =~ /freq/i) {   
$use{$fld} = Gtk3::CheckButton ->new("Change $fld to =>");
$value{$fld} = Gtk3::Entry->new;
}
}
elsif ($fld eq 'sysno') {
if ($dbndx =~ /group/i) { 
$use{$fld} = Gtk3::CheckButton ->new("Change $fld to =>");
$value{$fld} = Gtk3::Entry->new;
}
}
elsif ($fld eq 'mode') {
if ($dbndx =~ /freq/i) {   
$use{$fld} = Gtk3::CheckButton ->new("Change $fld to =>");
$value{$fld} = Gtk3::ComboBoxText->new;
foreach (@modestring) {$value{$fld}->append_text($_);}
$value{$fld}->set_active(0);
}
}
else {
LogIt(1,"RADIOCTL l8312:Forgot to define drop-down for $fld");
}
if ($use{$fld}) {
$hbox[0] = Gtk3::Box->new('horizontal',5);
$hbox[0]->pack_start($use{$fld},FALSE,FALSE,0);
$hbox[0]->pack_start($value{$fld},FALSE,FALSE,0);
$content->add($hbox[0]);
}
}### Foreach field that can be edited
my $errmsg = Gtk3::Label->new();
$content->add($errmsg);
$content->show_all;
my $response = '';
RUNDIALOG:
while (!$response) {
$response = $dialog->run;
if ($response eq 'ok') {
my %request = ('_cmd' => 'batch',  '_dbn' => $dbndx, '_type' => 'edit');
foreach my $fld (keys %use) {
if ($use{$fld}->get_active()) {
if ($fld eq 'valid') {
$request{$fld} = $value{$fld}->get_active();
}
elsif ($fld eq 'mode') {
$request{$fld} = $value{$fld}->get_active_text();
}
else {
$request{$fld} = $value{$fld}->get_text();
if (!looks_like_number($request{$fld})) {
my $font = 'face="DejaVu Sans Mono"';
$errmsg->set_markup('<span foreground="red"' .
'>'.
"Error! $fld value MUST be a number" .
'</span>');
$response = '';
next RUNDIALOG;
}
elsif (($fld eq 'system') or ($fld eq 'group')) {
if ($request{$fld} < 1) {
my $font = 'face="DejaVu Sans Mono"';
$errmsg->set_markup('<span foreground="red"' .
'>'.
"Error! $fld value MUST be > 0" .
'</span>');
$response = '';
next RUNDIALOG;
}
}
}### Number field
}### Field is selected
}### fill in the fields
unshift @req_queue,{%request};
}### response is OK
}
$dialog->destroy;
}### user selected something to edit
}
elsif ($command eq 'swap') {
if (get_selected($dbndx)) {
LogIt(1,"RADIOCTL l7226, No selected records to swap!");
}
else {
if (scalar @selected == 2) {
my %request = ('_cmd' => 'batch', '_dbn' => $dbndx, '_type' => 'swap' );
push @req_queue,{%request};
}
else {
LogIt(1,"RADIOCTL l7419:Must have two and ONLY two records selected for SWAP");
}
}
}
elsif (($command eq 'xfer') or ($command eq 'lookup')) {
if (get_selected($dbndx)) {
LogIt(1,"RADIOCTL l7226, No selected records to swap!");
}
else {
my %request = ('_cmd' => 'batch', '_dbn' => $dbndx, '_type' => "$command" );
push @req_queue,{%request};
}
}
elsif ($command eq 'clear_db') {
my %request = ('_cmd' => 'clear', '_dbn' => $dbndx );
push @req_queue,{%request};
}
elsif ($command =~ /sort/) {
my %request = ('_cmd' => 'sort', '_dbn' => $dbndx, 'type' => $command );
push @req_queue,{%request};
}
elsif ($command eq 'renum') {
my %request = ('_cmd' => 'renum', '_dbn' => $dbndx );
push @req_queue,{%request};
}
elsif ($command eq 'quit') {quit_prog();}
else {LogIt(1,"MENU_OPS:need process for command $command");}
return 0;
}### menu ops
sub get_selected {
my $dbndx = shift @_;
@selected = ();
my $treeselection = $treeview{$dbndx}->get_selection();
my ($paths,$model) = $treeselection->get_selected_rows();
foreach my $pth (@{$paths}) {
my $row = $pth->to_string();
my $iter = $liststore{$dbndx}->get_iter_from_string($row);
my $index = $liststore{$dbndx}->get($iter,$col_xref{'index'});
push @selected,$index;
}
if (!scalar @selected) {return $EmptyChan;}
else {return $GoodCode;}
}
sub write_ini {
open INIFILE, '>' . $inifile or return;
foreach my $wndx (keys %w_info) {
$w_info{$wndx}{'init'} = FALSE;
foreach my $key (keys %{$w_info{$wndx}}) {
print INIFILE '$' . "w_info{$wndx}{$key} = ";
if ($w_info{$wndx}{$key}) {print INIFILE $w_info{$wndx}{$key}, "\n";}
else {print INIFILE "0\n";}
}
}
foreach my $dbndx (keys %col_active) {
foreach my $col (keys %{$col_active{$dbndx}}) {
print INIFILE '$col_active{' . $dbndx . '}{' . $col . '} =' . "$col_active{$dbndx}{$col}\n";
}
}
foreach my $key (keys %control) {
if (defined $control{$key}) {
print INIFILE '$control{' . $key . '} = "' . $control{$key} . '"' . "\n";
}
}
foreach my $key (keys %vfo) {
if (defined $vfo{$key}) {
print INIFILE '$vfo{' . $key . '} = "' .  $vfo{$key} . '"' . "\n";
}
}
if ($lastdir) {
print INIFILE '$','lastdir = "', $lastdir, '"',"\n";
}
foreach my $dbndx (@dblist) {
}
close INIFILE;
}
sub read_ini {
open INIFILE, '<' . $inifile or return;
while (my $inrec = <INIFILE>) {
chomp $inrec;
if (substr($inrec,0,1) eq '$') {
eval $inrec;
}
}
close INIFILE;
}
sub view_ops {
my $widget = shift @_;
my $parms = shift @_;
my $winref = $parms->{'winref'};
my $wintype = $parms->{'wintype'};
my $winname = $parms->{'window'};
my $global = $parms->{'global'};
my $col    = $parms->{'col'};
if (!$col) {$col = '';}
if (!$winref) {LogIt(1,"VIEW_OPS:no winref for $winname!");return 0;}
my $active = $widget->get_active;
if (!$active) {$active = 0;}
if ($wintype eq 'treecol') {$winref->set_visible($active); }
else {
if ($active) {$winref->show_all;}
else {$winref->hide;}
}
if ($global) {
$$global = $active;
}
return 0;
}
sub dply_scan_opt {
my $fg = 'foreground="grey" ';
my $bgc = 'background="white"';
$bgc = '';
$weight = ' weight="normal" ';
my $in_state = FALSE;
if (($progstate =~ /freq/i) or ($progstate =~ /chan/i)) {$in_state = TRUE;}
my $globalmsg = 'Global On Signal:+Delay -Resume';
my $value = $control{'dlyrsm_value'};
if ($value) {
my $rstate = $in_state;
if ($progstate =~ /search/i) {$rstate = TRUE;}
my $secs = abs($value);
my $time = 'second';
if ($secs > 1) {$time = 'seconds';}
if ($value > 0) {
$globalmsg = "Global After Signal:Delay for $secs $time";
if ($rstate and $control{'dlyrsm'}) {
{$fg = 'foreground="green" ';}
}
}
else {
$globalmsg = "Global During Signal:Resume after $secs $time";
if ($rstate and $control{'dlyrsm'}) {
$fg = 'foreground="red" ';
}
}### Negative value
}### DLYRSM value is NOT 0
my $child =  $opt_button{'dlyrsm'}->get_child();
$child->set_markup("<span $fg $bgc $weight >$globalmsg</span>");
foreach my $ctl ('start','stop') {
my $fg = 'foreground="grey" ';
if ($in_state and $control{$ctl} ) {$fg ='foreground="black" ';}
my $child = $opt_button{$ctl} -> get_child();
my $msg = "Scan $ctl ";
my $value =  $control{$ctl . '_value'};
if ($progstate =~ /freq/i) {$msg = "$msg with record $value";}
elsif ($progstate =~ /chan/i) {$msg = "$msg with channel $control{$ctl . '_value'}";}
else {$msg = "$msg with Record/Channel $value";}
$child->set_markup("<span $fg $bgc $weight >$msg</span>");
}
foreach my $ctl ('dbdlyrsm','scansys','scangroup') {
$fg = 'foreground="grey" ';
if ($in_state and $control{$ctl}) { $fg ='foreground="black" ';}
my $child = $opt_button{$ctl} -> get_child();
my $msg = Strip($child->get_text());
$child->set_markup("<span $fg $bgc $weight >$msg</span>");
}
return 0;
}
sub close_window {
my ($window, $event, $dbndx) = @_;
if ($dbndx eq 'main') {quit_prog();}
else {$window_menu{$dbndx} -> set_active(FALSE);}
return TRUE;
}
sub numerically {
if (looks_like_number($a) and (looks_like_number($b))) {$a <=> $b;}
else {$a cmp $b;}
}
sub err_dialog {
my ($emsg,$type,$caller) = @_;
my $image = 'gtk-dialog-warning';
my $foreground = ' foreground="red" ';
if ($type eq 'info') {
$foreground  = ' foreground="green" ';
$image = 'gtk-dialog-info';
}
my $dialog = Gtk3::Dialog->new(
$type,
$panels{'main'}{'gtk'},
'modal',
'gtk-ok' => 'ok',
);
my $label = Gtk3::Label->new($emsg);
my $font = ' face="DejaVu Sans Mono" ';
$label->set_markup('<span '. $foreground  . $font .
'size="15000" weight="heavy" style="normal"' .
'>'.
$emsg .
'</span>');
my $icon = Gtk3::Image->new_from_stock($image,'dialog');
$dialog->get_content_area() ->add($icon);
$dialog->get_content_area() -> add($label);
$dialog->signal_connect(response =>sub {
$_[0]->destroy;
%scan_request = ();
$pop_up = FALSE;
});
$dialog->show_all;
$pop_up = TRUE;
return 1;
}
sub quit_prog {
LogIt(0,"$Bold Got $Green Quit$White request");
for (my $i=0;$i<MAXTIMER;$i++){
$timer[$i] = 0;
}
foreach  my $i (keys %panels) {
if ($panels{$i}{'type'} eq 'p') {next;}
my $pointer = $panels{$i}{'gtk'};
if (!defined $pointer) {next;}
($w_info{$i}{'xsize'},$w_info{$i}{'ysize'}) = $pointer->get_size;
($w_info{$i}{'xpos'},$w_info{$i}{'ypos'}) = $pointer->get_position;
}
write_ini();
foreach my $win (keys %panels) {
if ($panels{$win}{'type'} ne 'p') {$panels{$win}{'gtk'} -> hide;}
}
%gui_request = ('_cmd' => 'term');
%scan_request = ();
$gui_request{'_rdy'} = TRUE;
my $loopcnt = 500;
while ($scanner_thread){
%scan_request = ();
threads->yield;
usleep(10000);
if (!(--$loopcnt)) {
LogIt(1,"could not kill scanner thread");
goto QUIT_ANYWAY;
}
}
QUIT_ANYWAY:
foreach my $win (keys %panels) {
if ($panels{$win}{'type'} ne 'p') {$panels{$win}{'gtk'} ->destroy;}
}
Gtk3->main_quit;
return TRUE;
}
