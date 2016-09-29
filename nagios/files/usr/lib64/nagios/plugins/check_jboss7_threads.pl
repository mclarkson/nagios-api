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


## no time out and we have HTTP response, let's get some data...

my $json_response = decode_json($response->content);


## JSON location for Java thread count
my $JavaThreads = $json_response->{"core-service"}->{"platform-mbean"}->{"type"}->{"threading"}->{"thread-count"};


## test values against threshhold, and print status and exit
$n_status="OK";
$n_output =  "CurrentThreads: $JavaThreads";


  if ( ($o_crit != 0) && ($o_crit <= $JavaThreads) )  {
    $n_status="CRITICAL";
    $n_output .= " :  " . $n_status . " > " .  $o_crit;

  } else {
    if ( ($o_warn != 0) && ($o_warn <= $JavaThreads) )  {
      $n_status="WARNING";
    $n_output .= " :  " . $n_status . " > " .  $o_warn;
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
		integer threshold for warning level
	-c, --critical
		 integer threshold for critical level
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
	print "Usage: $0 -H <host> -w <warning> -c <critical> [-h] [-t <timeout>]\n";
}


sub check_options {
	Getopt::Long::Configure("bundling");
	GetOptions(
        	't:i'   => \$o_timeout,         'timeout:i'     => \$o_timeout,
		'h'	=> \$o_help,		'help'		=> \$o_help,
		'H:s'	=> \$o_host,		'hostname:s'	=> \$o_host,
		'w:i'	=> \$o_warn,		'warning:i'	=> \$o_warn,
		'c:i'	=> \$o_crit,		'critical:i'	=> \$o_crit,
	);

   if ( ! defined($o_warn) || ! defined($o_crit))
        { print "Put warning and critical values!\n";
		usage();
		exit $ERRORS{"UNKNOWN"}
	}
    # Get rid of % sign
#    $o_warn =~ s/\%//g;
#    $o_crit =~ s/\%//g;

        if ( isnnum($o_warn) || isnnum($o_crit))
            { print "Numeric value only for warning or critical !\n";usage(); exit $ERRORS{"UNKNOWN"} }
        if (($o_crit!= 0) && ($o_warn > $o_crit))
           { print "warning <= critical ! \n";usage(); exit $ERRORS{"UNKNOWN"}}


}
