#!/usr/bin/perl -w
## nagios: -epn
use lib "/usr/lib64/nagios/plugins";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use Getopt::Long;
use LWP::UserAgent ;
use JSON ;
use Data::Dumper ;

use vars qw($o_host $o_help $o_warning $o_critical $o_timeout $o_verb);

my %ERRORS=("OK"=>0,"WARNING"=>1,"CRITICAL"=>2,"UNKNOWN"=>3,"DEPENDENT"=>4);

$o_host = undef;
$o_help= undef;
$o_warn= undef;
$o_crit= undef;
$o_timeout=  undef;


my $return_str = "";
my $state = 'UNKNOWN';

check_options();

# Check global timeout if JBoss does not respond
if (defined($TIMEOUT)) {
  verb("Alarm at $TIMEOUT");
  alarm($TIMEOUT);
} else {
  verb("no global timeout defined : $o_timeout + 10");
  alarm ($o_timeout+10);
}

$SIG{'ALRM'} = sub {
 print "No response from host\n";
 exit $ERRORS{"UNKNOWN"};
};

# This figures out which server is being queried
my $getServer = $o_host ;

# set up the LWP query
my $browser = LWP::UserAgent->new;
$browser->agent('Mozilla/5.0');
my $jsonPort = $getServer . ":10090" ;

## send htaccess-type authentication to the JBoss management console
$browser->credentials($jsonPort,"ManagementRealm","epadmin", "Hybr!d");

## get the JBoss7 json response and parse it
my $jsonURL = "http://" . $getServer . ":10090/management/?recursive" ;
my $response = $browser->get( $jsonURL );

##make sure we got JSON response or exit
   while( my  ($k, $v) = each %$response ) {
	if ( $k eq '_rc') {
	## get return code for the browser call
	$rc = $v ;
	}
    }
if ( $rc != 200 ) {
	print "Invalid JSON or bad HTTP response. \n";
	exit $ERRORS{"CRITICAL"};
	}
## no tiome out and we have HTTP resopnse, let'e get some data...

my $json_response = decode_json($response->content);


# set the common memory-pool hash location
## these HEAP values are in bytes
my $PS_Eden_Space = $json_response->{"core-service"}->{"platform-mbean"}->{"type"}->{"memory-pool"}->{"name"}->{"PS_Eden_Space"}->{"usage"}->{"used"};
my $PS_Old_Gen = $json_response->{"core-service"}->{"platform-mbean"}->{"type"}->{"memory-pool"}->{"name"}->{"PS_Old_Gen"}->{"usage"}->{"used"};
my $PS_Perm_Gen = $json_response->{"core-service"}->{"platform-mbean"}->{"type"}->{"memory-pool"}->{"name"}->{"PS_Perm_Gen"}->{"usage"}->{"used"};
my $PS_Survivor_Space = $json_response->{"core-service"}->{"platform-mbean"}->{"type"}->{"memory-pool"}->{"name"}->{"PS_Survivor_Space"}->{"usage"}->{"used"};


## JSON location for all Java Parameters passed at runtime
my $javaParams = $json_response->{"core-service"}->{"platform-mbean"}->{"type"}->{"runtime"}->{"input-arguments"};

## get HEAP -Xmx in Megabytes or exit critical if it is not a JVM parameter
foreach $line (@$javaParams) {
	if ($line =~ '^-[xX]mx') {
		# EndPlay app always passes -Xmx in m(egabytes) but could use this to calculate for gigabytes
		#$increment = substr $line,-1,1 ;
		$line =~ s/[^0-9]//g ;
		$MaxHeapMegabytes = $line ;
		$xmxExists = length($line) ;
	}
   }

if ( $xmxExists < 1 ) {
	print "unknown -Xmx setting on server ";
	exit $ERRORS{"CRITICAL"};
	}

## get NON-HEAP -XX:MaxPermSize in Megabytes or exit critical if it is not a JVM parameter
foreach $line (@$javaParams) {
	if ($line =~ '^-XX:MaxPermSize') {
		# EndPlay app always passes -XX:MaxPermSize in m(egabytes) but could use this to calculate for gigabytes
		#$increment = substr $line,-1,1 ;
		$line =~ s/[^0-9]//g ;
		$MaxNonHeapMegabytes = $line ;
		$nonHeapExists = length($line) ;
	}
   }

if ( $nonHeapExists < 1 ) {
	print "unknown -XX:MaxPermSize setting on server ";
	exit $ERRORS{"CRITICAL"};
	}


## Add up HEAP memory-pools  and convert to megabytes
$HeapTotal =  $PS_Eden_Space + $PS_Old_Gen + $PS_Survivor_Space;
$HeapTotalMegabytes = int(($HeapTotal/1024)/1024) ;

## calculate the percentage and round off for prettiness
$HeapPercent = int( $HeapTotalMegabytes * 100 / $MaxHeapMegabytes ) ;


## Add up NON_HEAP memory-pools and convert to megabytes
$NonHeapTotalMegabytes = int(($PS_Perm_Gen/1024)/1024) ;

## calculate the percentage and round off for prettiness
$NonHeapPercent = int( ($NonHeapTotalMegabytes)*100 /$MaxNonHeapMegabytes) ;

## test values against threshholds, and print status and exit
$n_status="OK";
$n_output =  "HEAP: $HeapTotalMegabytes of $MaxHeapMegabytes MB Used = $HeapPercent% ; NonHEAP: $NonHeapTotalMegabytes of $MaxNonHeapMegabytes MB Used = $NonHeapPercent%";


  if ((($o_critHeap!=0)&&($o_critHeap <= $HeapPercent)) || (($o_critNonHeap!=0)&&($o_critNonHeap <= $NonHeapPercent))) {
    $n_status="CRITICAL";
    $n_output .= " :  " . $n_status . " > " .  $o_critHeap . ", " . $o_critNonHeap;

  } else {
    if ((($o_warnHeap!=0)&&($o_warnHeap <= $HeapPercent)) || (($o_warnNonHeap!=0)&&($o_warnNonHeap <= $NonHeapPercent))) {
      $n_status="WARNING";
    $n_output .= " :  " . $n_status . " > " .  $o_warnHeap . ", " . $o_warnNonHeap;
    }
  }


  print "$n_status - $n_output \n";
  exit $ERRORS{$n_status};



### Functions
sub help {
	version();
	usage();

	print <<HELP;
	-h, --help
   		print this help message
	-H, --hostname=HOST
		name or IP address of host to check
	-w, --warning
		thresholds for HeapWarning,NonHeapWarning as percent of -Xmx(Heap) or MaxPermSize (NonHeap)
	-c, --critical
		thresholds for HeapCritical,NonHeapCritical as percent of -Xmx(Heap) or MaxPermSize (NonHeap)
	-t, --timeout=INTEGER
   		timeout for JBoss Management portal response in seconds (Default: 15)


HELP
}

sub isnnum { # Return true if arg is not a number
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0 ;}
  return 1;
}


sub verb { my $t=shift; print $t,"\n" if defined($o_verb) ; }

sub usage {
	print "Usage: $0 -H <host> -w <HeapWarning,NonHeapWarning> -c <HeapCritical,NonHeapCritical> [-h] [-t <timeout>]\n";
}


sub check_options {
	Getopt::Long::Configure("bundling");
	GetOptions(
        	't:i'   => \$o_timeout,         'timeout:i'     => \$o_timeout,
		'h'	=> \$o_help,		'help'		=> \$o_help,
		'H:s'	=> \$o_host,		'hostname:s'	=> \$o_host,
		'w:s'	=> \$o_warn,		'warning:s'	=> \$o_warn,
		'c:s'	=> \$o_crit,		'critical:s'	=> \$o_crit,
	);

   if ( ! defined($o_warn) || ! defined($o_crit))
        { print "Put warning and critical values!\n";
		usage();
		exit $ERRORS{"UNKNOWN"}
	}
    # Get rid of % sign
    $o_warn =~ s/\%//g;
    $o_crit =~ s/\%//g;
      my @o_warnL=split(/,/ , $o_warn);
      my @o_critL=split(/,/ , $o_crit);

      if (($#o_warnL != 1) || ($#o_critL != 1))
        { print "2 warnings and critical !\n";
	  usage();
	  exit $ERRORS{"UNKNOWN"}
	}
      for (my $i=0;$i<2;$i++) {
        if ( isnnum($o_warnL[$i]) || isnnum($o_critL[$i]))
            { print "Numeric value for warning or critical !\n";usage(); exit $ERRORS{"UNKNOWN"} }
        if (($o_critL[$i]!= 0) && ($o_warnL[$i] > $o_critL[$i]))
           { print "warning <= critical ! \n";usage(); exit $ERRORS{"UNKNOWN"}}
        if ( $o_critL[$i] > 100)
           { print "critical percent must be < 100 !\n";usage(); exit $ERRORS{"UNKNOWN"}}
      }
      $o_warnHeap=$o_warnL[0];$o_warnNonHeap=$o_warnL[1];
      $o_critHeap=$o_critL[0];$o_critNonHeap=$o_critL[1];

}
