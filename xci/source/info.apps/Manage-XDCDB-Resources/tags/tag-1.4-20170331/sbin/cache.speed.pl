#!/usr/bin/env perl
# Cache SpeedPage information
###########################################################################
use strict;
use DBI;
use POSIX;
#use DBI qw(:sql_types);
use Date::Manip;
use Getopt::Long;
use DBD::mysql;
use Data::Dumper;

my $DBNAME = 'speedpage';
#my $DBUSER = 'guest';
#my $DBPASS = 'tggridinfo'; 
my $DBUSER = 'xsede';
my $DBPASS = 'xsedegridinfo'; 
my $DBHOST = 'quipu.psc.xsede.org'; 
my $DBPORT = '3306'; 

my $mapCSV = '/soft/warehouse-apps-1.0/Manage-XDCDB/var/tgresources.csv';
open DB,"<$mapCSV" or
  die "Failed to open $mapCSV";
my %name_to_id;
my @fields = split(/,/, <DB>);         # CSV column/field headings
while (<DB>) {
  my @list = split(/,/);
  $list[1] =~ s/^"//;
  $list[1] =~ s/"$//;
  $name_to_id{lc($list[1])} = $list[0];       # Case insensitive key
}
close(DB);
$name_to_id{lc('TACC Ranch')} = 'ranch.tacc.teragrid.org';
$name_to_id{lc('NICS Keeneland')} = 'keeneland.nics.teragrid.org';
$name_to_id{lc('PSC Data Supercell')} = 'data.psc.xsede.org';
$name_to_id{lc('SDSC Oasis')} = 'oasis-dm.sdsc.xsede.org';
$name_to_id{lc('SDSC Trestles')} = 'trestles-dm.sdsc.xsede.org';

# Gather for the last 30 days
my $recentInterval = time - (60 * 60 * 24 * 30);

# Selects recent readings
my $speedQuery = "SELECT tstamp,source,src_url,dest,dest_url,xfer_rate
         FROM tput
         WHERE tstamp > $recentInterval";

# Debug setting
my $FALSE  = 0;
my $TRUE   = 1;
my $DEBUG  = $FALSE;

my ($cache_dir);
GetOptions ('cache|c=s'   => \$cache_dir);
unless ($cache_dir) {
   print "Cache directory not specified\n";
   exit 1;
}

my $SpeedCSV = "$cache_dir/speedpage.csv";
my $SpeedLock = "$SpeedCSV.lock";

my $dbh = dbconnect();
my @speedOut = dbexecsql($dbh, $speedQuery);
dbdisconnect($dbh);

if (@speedOut < 10) {
  die "Speedpage database returned less than 10 rows, somethings is amuck";
}

create_lock($SpeedLock);
open(OUT, ">$SpeedCSV") or
   die "Failed to open output '$SpeedCSV'";

my %missing;
print OUT "tstamp,sourceid,source,src_url,destid,dest,dest_url,xfer_rate\n";
foreach (@speedOut) {
   my ($sourceid, $destid);
   my ($c0, $c1, $c2, $c3, $c4, $c5) = ($_->[0], $_->[1], $_->[2], $_->[3], $_->[4], $_->[5]);

   if ( ! exists $name_to_id{lc($c1)} ) {
      print STDERR "Source '$c1' doesn't exist\n" unless ( $missing{lc($c1)} );
      $missing{lc($c1)} = 1;
   }
   $sourceid = $name_to_id{lc($c1)};

   if ( $c3 eq 'file -> /dev/null' ) {
      $destid = 'file-to-null';
   } elsif ( $c3 eq '/dev/zero -> /dev/null' ) {
      $destid = 'zero-to-null';
   } elsif ( $c3 eq '/dev/zero -> file' ) {
      $destid = 'zero-to-file';
   } elsif ( ! exists $name_to_id{lc($c3)} ) {
      print STDERR "Destination '$c3' doesn't exist\n" unless ( $missing{lc($c3)} );
   } else {
      $destid = $name_to_id{lc($c3)};
      $missing{lc($c3)} = 1;
   }
   print OUT "$c0,$sourceid,$c1,$c2,$destid,$c3,$c4,$c5\n";
}

close(OUT);
delete_lock($SpeedLock);
exit;

###############################################################################
# Lock functions
sub create_lock($) {
   my $lockfile = shift;

   unless (-e $lockfile) {
     write_lock($lockfile);
     return;
   }

   unless ( open (LOCKPID, "<$lockfile") ) {
     write_lock($lockfile);
     return;
   }

   my $lockpid = <LOCKPID>;
   close(LOCKPID);
   unless ( $lockpid ) {               # No pid, full disk perhaps, continue
     print "Found lock file '$lockfile' and NULL pid, continuing\n";
     write_lock($lockfile);
     return;
   }

   if ( kill 0 => $lockpid ) {
      chomp $lockpid;
      print "Found lock file '$lockfile' and active process '$lockpid', quitting\n";
      exit 1;
   }

   chomp $lockpid;
   print "Removing lock file '$lockfile' for INACTIVE process '$lockpid'\n";
   write_lock($lockfile);
}

sub write_lock($) {
   my $lockfile = shift;
   open(LOCK, ">$lockfile") or
      die "Error opening lock file '$lockfile': $!";
   print LOCK "$$\n";
   close(LOCK) or
      die "Error closing lock file '$lockfile': $!";
}

sub delete_lock($) {
   my $lockfile = shift;
   if ((unlink $lockfile) != 1) {
      print "Failed to delete lock '$lockfile', quitting\n";
      exit 1;
   }
}

###############################################################################
sub resource_name_to_resourceid {
   my $resource_name = shift;
   my $resourceid;
   if ( $resource_name =~ /(.*)\.anl\.teragrid$/ ) {
      $resourceid = $1 . '.uc.teragrid.org'; 
   } elsif ( $resource_name eq 'bluegene.sdsc.teragrid' ) {
      $resourceid = 'intimidata.sdsc.teragrid.org'; 
   } else {
      $resourceid = $resource_name . '.org';
   }
   return($resourceid);
}

###############################################################################
sub noltgt { #Convert < and > to &lt; and &gt;
   my $line = shift;
   $line =~ s/</&lt;/g;
   $line =~ s/>/&gt;/g;
   return($line);
}

####################################################
# Database Access Subroutines
####################################################
sub dbdisconnect {
   my $dbh = shift;
   my $retval;
   eval { $retval = $dbh->disconnect; };
   if ( $@ || !$retval ) {
      dberror( "Error disconnecting from database", $@ || $DBI::errstr );
   }
}

sub dbconnect {
   my $dbh;

   # I'm using RaiseError because bind_param is too stupid to do
   # anything else, so this allows consistency at least.
   my %args = ( PrintError => 0, RaiseError => 1 );

   debug("connecting to $DBNAME on $DBHOST:$DBPORT as $DBUSER");

#  $dbh = DBI->connect( "dbi:Pg:dbname=$DBNAME;host=$DBHOST;port=$DBPORT;sslmode=require",
   $dbh = DBI->connect( "dbi:mysql:dbname=$DBNAME;host=$DBHOST;port=$DBPORT",
      $DBUSER, $DBPASS, \%args );
   dberror( "Can't connect to database: ", $DBI::errstr ) unless ($dbh);
#  $dbh->do("SET search_path TO acct");

#  if ($DEBUG) {
#     $dbh->do("SET client_min_messages TO debug");
#  }
   
   return $dbh;
}

#
# If called in a list context it will return all result rows.
# If called in a scalar context it will return the last result row.
#
sub dbexecsql {
   my $dbh      = shift;
   my $sql      = shift;
   my $arg_list = shift;

   my ( @values, $result );
   my $i      = 0;
   my $retval = -1;
   my $prepared_sql;

   eval {
      debug("SQL going in=$sql");
      $prepared_sql = $dbh->prepare($sql);

      #or die "$DBI::errstr\n";

      $i = 1;
      foreach my $arg (@$arg_list) {
         $arg = '' unless $arg;
         $prepared_sql->bind_param( $i, $arg );

         #or die "$DBI::errstr\n";
         debug("arg ($i) = $arg");
         $i++;
      }
      $prepared_sql->execute;

      #or die "$DBI::errstr\n";
      @values = ();
      while ( $result = $prepared_sql->fetchrow_arrayref ) {
         push( @values, [@$result] );
         foreach (@$result) { $_ = '' unless defined($_); }
         debug( "result row: ", join( ":", @$result ), "" );
      }
   };

   if ($@) { dberror($@); }

   #   debug("last result = ",$values[-1],"");
   debug( "wantarray = ", wantarray, "" );

   return wantarray ? @values : $values[-1];
}

################################################################################
# DB Functions
sub error {
   print STDERR join( '', "ERROR: ", @_, "\n" );
   exit(1);
}

sub dberror {
   my ( $errstr,  $msg );
   my ( $package, $file, $line, $junk ) = caller(1);

   if ( @_ > 1 ) { $msg = shift; }
   else { $msg = "Error accessing database"; }

   $errstr = shift;

   print STDERR "$msg (at $file $line): $errstr\n";
   exit(0);
}

sub debug {
   return unless ($DEBUG);
   my ( $package, $file, $line ) = caller();
   print join( '', "DEBUG (at $file $line): ", @_, "\n" );
}
