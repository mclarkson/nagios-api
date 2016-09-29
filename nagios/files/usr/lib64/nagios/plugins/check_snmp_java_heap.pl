#!/usr/bin/perl -w
############################## check_snmp_mem ##############
# Version : 1.1
# Date : Jul 09 2006
# Author  : Patrick Proy (nagios at proy.org)
# Help : http://www.manubulon.com/nagios/
# Licence : GPL - http://www.fsf.org/licenses/gpl.txt
# Contrib : Jan Jungmann
# TODO :
#################################################################
#
# Help : ./check_snmp_mem.pl -h
#

use strict;
use Net::SNMP;
use Getopt::Long;
use Data::Dumper ;

# Nagios specific

use lib "/usr/lib64/nagios/plugins";
use utils qw(%ERRORS $TIMEOUT);
#my $TIMEOUT = 15;
#my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# SNMP Data
my $nets_oldgen_used = "1.3.6.1.4.1.42.2.145.3.163.1.1.2.110.1.11.4"; #JVM Old Gen Used
my $nets_oldgen_max="1.3.6.1.4.1.42.2.145.3.163.1.1.2.110.1.13.4"; #JVM old Gen Max
my $nets_heap_max       = "1.3.6.1.4.1.42.2.145.3.163.1.1.2.13.0";  # JVM Heap Max size
my $nets_heap_used      = "1.3.6.1.4.1.42.2.145.3.163.1.1.2.11.0";  # Heap Used
my $nets_nonheap_max   = "1.3.6.1.4.1.42.2.145.3.163.1.1.2.23.0"; # NonHeap Max Size
my $nets_nonheap_used   = "1.3.6.1.4.1.42.2.145.3.163.1.1.2.21.0"; # NonHeap Used
my @nets_oids           = ($nets_oldgen_max,$nets_oldgen_used,$nets_heap_max,$nets_heap_used,$nets_nonheap_max,$nets_nonheap_used);


# Globals

my $Version='1.1';

my $o_host =    undef;          # hostname
my $o_community = undef;        # community
my $o_port =    3161;           # port
my $o_help=     undef;          # wan't some help ?
my $o_verb=     undef;          # verbose mode
my $o_version=  undef;          # print version
my $o_netsnmp=  1;              # Check with netsnmp (default)
my $o_warn=     undef;          # warning level option
my $o_warnHeap= undef;          # warning level for Real memory
my $o_warnNonHeap=      undef;          # warning levels for swap
my $o_crit=     undef;          # Critical level option
my $o_critHeap= undef;          # critical level for Real memory
my $o_critNonHeap=      undef;          # critical level for swap
my $o_perf=     undef;          # Performance data option
my $o_cache=    undef;          # Include cached memory as used memory
my $o_timeout=  undef;          # Timeout (Default 5)
my $o_version2= undef;          # use snmp v2c
# SNMPv3 specific
my $o_login=    undef;          # Login for snmpv3
my $o_passwd=   undef;          # Pass for snmpv3
my $v3protocols=undef;  # V3 protocol list.
my $o_authproto='md5';          # Auth protocol
my $o_privproto='des';          # Priv protocol
my $o_privpass= undef;          # priv password

# functions

sub p_version { print "check_snmp_java_heap version : $Version\n"; }

sub print_usage {
    print "Usage: $0 [-v] -H <host> -C <snmp_community> [-2] | (-l login -x passwd [-X pass -L <authp>,<privp>])  [-p <port>] -w <HeapWarnlevel,NonHeapWarnLevel> -c <HeapCriticalLevet,NonHeapCriticalLevel> [-f] [-m] [-t <timeout>] [-V]\n";
}

sub isnnum { # Return true if arg is not a number
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0 ;}
  return 1;
}

sub round ($$) {
    sprintf "%.$_[1]f", $_[0];
}

sub help {
   print_usage();
   print <<EOT;
-v, --verbose
   print extra debugging information (including interface list on the system)
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host to check
-C, --community=COMMUNITY NAME
   community name for the host's SNMP agent (implies SNMP v1 or v2c with option)
-2, --v2c
   Use snmp v2c
-l, --login=LOGIN ; -x, --passwd=PASSWD
   Login and auth password for snmpv3 authentication
   If no priv password exists, implies AuthNoPriv
-X, --privpass=PASSWD
   Priv password for snmpv3 (AuthPriv protocol)
-L, --protocols=<authproto>,<privproto>
   <authproto> : Authentication protocol (md5|sha : default md5)
   <privproto> : Priv protocole (des|aes : default des)
-P, --port=PORT
   SNMP port (Default 161)
-w, --warn=INTEGER | INT,INT
   warning level for memory in percent (0 for no checks)
-c, --crit=INTEGER | INT,INT
   critical level for memory in percent (0 for no checks)
-N, --netsnmp (default)
   check Java memory & swap provided by Net SNMP
-f, --perfdata
   Performance data output
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 5)
-V, --version
   prints version number
EOT
}

# For verbose output
sub verb { my $t=shift; print $t,"\n" if defined($o_verb) ; }

# Get the alarm signal (just in case snmp timout screws up)
$SIG{'ALRM'} = sub {
     print ("ERROR: Alarm signal (Nagios time-out)\n");
     exit $ERRORS{"UNKNOWN"};
};

sub check_options {
    Getopt::Long::Configure ("bundling");
        GetOptions(
        'v'     => \$o_verb,            'verbose'       => \$o_verb,
        'h'     => \$o_help,            'help'          => \$o_help,
        'H:s'   => \$o_host,            'hostname:s'    => \$o_host,
        'p:i'   => \$o_port,            'port:i'        => \$o_port,
        'C:s'   => \$o_community,       'community:s'   => \$o_community,
        'l:s'   => \$o_login,           'login:s'       => \$o_login,
        'x:s'   => \$o_passwd,          'passwd:s'      => \$o_passwd,
        'X:s'   => \$o_privpass,                'privpass:s'    => \$o_privpass,
        'L:s'   => \$v3protocols,               'protocols:s'   => \$v3protocols,
        't:i'   => \$o_timeout,         'timeout:i'     => \$o_timeout,
        'V'     => \$o_version,         'version'       => \$o_version,
        'N'     => \$o_netsnmp,         'netsnmp'       => \$o_netsnmp,
        '2'     => \$o_version2,        'v2c'           => \$o_version2,
        'c:s'   => \$o_crit,            'critical:s'    => \$o_crit,
        'w:s'   => \$o_warn,            'warn:s'        => \$o_warn,
    );
    if (defined ($o_help) ) { help(); exit $ERRORS{"UNKNOWN"}};
    if (defined($o_version)) { p_version(); exit $ERRORS{"UNKNOWN"}};
    if ( ! defined($o_host) ) # check host and filter
        { print "No host defined!\n";print_usage(); exit $ERRORS{"UNKNOWN"}}


    # check snmp information
    if ( !defined($o_community) && (!defined($o_login) || !defined($o_passwd)) )
          { print "Put snmp login info!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
        if ((defined($o_login) || defined($o_passwd)) && (defined($o_community) || defined($o_version2)) )
          { print "Can't mix snmp v1,2c,3 protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
        if (defined ($v3protocols)) {
          if (!defined($o_login)) { print "Put snmp V3 login info with protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
          my @v3proto=split(/,/,$v3protocols);
          if ((defined ($v3proto[0])) && ($v3proto[0] ne "")) {$o_authproto=$v3proto[0];        }       # Auth protocol
          if (defined ($v3proto[1])) {$o_privproto=$v3proto[1]; }       # Priv  protocol
          if ((defined ($v3proto[1])) && (!defined($o_privpass))) {
            print "Put snmp V3 priv login info with priv protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
        }
        if (defined($o_timeout) && (isnnum($o_timeout) || ($o_timeout < 2) || ($o_timeout > 60)))
          { print "Timeout must be >1 and <60 !\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
        if (!defined($o_timeout)) {$o_timeout=5;}
        #Check Warning and crit are present
    if ( ! defined($o_warn) || ! defined($o_crit))
        { print "Put warning and critical values!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    # Get rid of % sign
    $o_warn =~ s/\%//g;
    $o_crit =~ s/\%//g;


 if (defined($o_netsnmp)) {
      my @o_warnL=split(/,/ , $o_warn);
      my @o_critL=split(/,/ , $o_crit);
      if (($#o_warnL != 1) || ($#o_critL != 1))
        { print "Need two threshholds for each warning and critical !\n";print_usage(); exit $ERRORS{"UNKNOWN"}}
      for (my $i=0;$i<2;$i++) {
        if ( isnnum($o_warnL[$i]) || isnnum($o_critL[$i]))
            { print "Numeric value for warning or critical !\n";print_usage(); exit $ERRORS{"UNKNOWN"} }
        if (($o_critL[$i]!= 0) && ($o_warnL[$i] > $o_critL[$i]))
           { print "warning <= critical ! \n";print_usage(); exit $ERRORS{"UNKNOWN"}}
        if ( $o_critL[$i] > 100)
           { print "critical percent must be < 100 !\n";print_usage(); exit $ERRORS{"UNKNOWN"}}
      }
      $o_warnHeap=$o_warnL[0];$o_warnNonHeap=$o_warnL[1];
      $o_critHeap=$o_critL[0];$o_critNonHeap=$o_critL[1];
    }

}

########## MAIN #######

check_options();

# Check global timeout if snmp screws up
if (defined($TIMEOUT)) {
  verb("Alarm at $TIMEOUT");
  alarm($TIMEOUT);
} else {
  verb("no timeout defined : $o_timeout + 10");
  alarm ($o_timeout+10);
}

# Connect to host

my ($session,$error);

if ( defined($o_login) && defined($o_passwd)) {
  # SNMPv3 login
  if (!defined ($o_privpass)) {
  verb("SNMPv3 AuthNoPriv login : $o_login, $o_authproto");
    ($session, $error) = Net::SNMP->session(
      -hostname         => $o_host,
      -version          => '3',
      -username         => $o_login,
      -authpassword     => $o_passwd,
      -authprotocol     => $o_authproto,
      -timeout          => $o_timeout
    );
  } else {
    verb("SNMPv3 AuthPriv login : $o_login, $o_authproto, $o_privproto");
    ($session, $error) = Net::SNMP->session(
      -hostname         => $o_host,
      -version          => '3',
      -username         => $o_login,
      -authpassword     => $o_passwd,
      -authprotocol     => $o_authproto,
      -privpassword     => $o_privpass,
          -privprotocol => $o_privproto,
      -timeout      => $o_timeout
    );
  }
} else {
   if (defined ($o_version2)) {
     # SNMPv2 Login
         verb("SNMP v2c login");
         ($session, $error) = Net::SNMP->session(
        -hostname  => $o_host,
            -version   => 2,
        -community => $o_community,
        -port      => $o_port,
        -timeout   => $o_timeout
     );
   } else {
    # SNMPV1 login
        verb("SNMP v1 login");
    ($session, $error) = Net::SNMP->session(
       -hostname  => $o_host,
       -community => $o_community,
       -port      => $o_port,
       -timeout   => $o_timeout
    );
  }
}


if (!defined($session)) {
   printf("ERROR opening session: %s.\n", $error);
   exit $ERRORS{"UNKNOWN"};
}

# Global variable
my $resultat=undef;

########### Net snmp memory check ############
if (defined ($o_netsnmp)) {

  # Get NetSNMP memory values
  $resultat = (Net::SNMP->VERSION < 4) ?
                $session->get_request(@nets_oids)
        :$session->get_request(-varbindlist => \@nets_oids);


  if (!defined($resultat)) {
    printf("ERROR: netsnmp : %s.\n", $session->error);
    $session->close;
    exit $ERRORS{"UNKNOWN"};
  }

} ##end of the IF

my ($heapused,$nonheapused,$oldgenused)=(undef,undef,undef);

$oldgenused = ($$resultat{$nets_oldgen_used})/$$resultat{$nets_oldgen_max} ;
$heapused = ($$resultat{$nets_heap_used})/$$resultat{$nets_heap_max} ;
$nonheapused = ($$resultat{$nets_nonheap_used})/$$resultat{$nets_nonheap_max} ;
$oldgenused=round($oldgenused*100,0);
$heapused=round($heapused*100,0);
$nonheapused=round($nonheapused*100,0);


 my $n_status="OK";
 my $n_output="OldGenHeap : " . $oldgenused . "%, Heap : " . $heapused . "%, NonHeap : " . $nonheapused . "% :";
  if ((($o_critHeap!=0)&&($o_critHeap <= $heapused)) || (($o_critHeap!=0)&&($o_critHeap <= $oldgenused)) || (($o_critNonHeap!=0)&&($o_critNonHeap <= $nonheapused))) {
    $n_output .= " > " . $o_critHeap . ", " . $o_critNonHeap;
    $n_status="CRITICAL";
  } else {
    if ((($o_warnHeap!=0)&&($o_warnHeap <= $heapused)) || (($o_warnNonHeap!=0)&&($o_warnNonHeap <= $nonheapused))) {
      $n_output.=" > " . $o_warnHeap . ", " . $o_warnNonHeap;
      $n_status="WARNING";
    }
  }
  $n_output .= " ; ".$n_status;


  $session->close;
  print "$n_output \n";
  exit $ERRORS{$n_status};

## }

