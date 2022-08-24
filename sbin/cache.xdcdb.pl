#!/usr/bin/env perl
###########################################################################
#
# teragrid=> \d info_services.resources
#                View "info_services.resources"
#         Column        |          Type           | Modifiers 
# ----------------------+-------------------------+-----------
#  grid_resource_name   | character varying(200)  | 
#  pops_name            | text                    | 
#  resource_name        | character varying(200)  | 
#  resource_code        | character varying(64)   | 
#  resource_description | character varying(1000) | 
#  organization_abbrev  | character varying(100)  | 
#  organization_name    | character varying(300)  | 
#  amie_name            | character varying(16)   | 
# View definition:
#  SELECT tg.grid_resource_name, ar.pops_name, r.resource_name, r.resource_code, r.resource_description, org.organization_abbrev, org.organization_name, org.amie_name
#    FROM acct.tg_grids tg
#    LEFT JOIN acct.allocable_resources ar ON tg.grid_resource_id = ar.resource_id, acct.resources r, acct.organizations org
#   WHERE tg.resource_id = r.resource_id AND r.organization_id = org.organization_id;
# Note from 2/1/2011: each r.* has 1 or more tg.grid_resource_name, ar.pops_name
###########################################################################

use   strict;
use   DBI;
use   POSIX;
use   Getopt::Long;
use   DBD::Pg qw(:pg_types);
use   Text::CSV_XS;

my $DBHOST = 'rampsdb.access-ci.org';
my $DBNAME = 'allocations';
my $DBPORT = 5432;
my $DBUSER = 'info_services';

my $FALSE  = 0;
my $TRUE   = 1;
my $DEBUG  = $FALSE;

# Use table field indexes to make code more readable
my $F_grid_resource_name   = 0;
my $F_pops_name            = 1;
my $F_resource_name        = 2;
my $F_resource_code        = 3;
my $F_resource_description = 4;
my $F_organization_abbrev  = 5;
my $F_organization_name    = 6;
my $F_amie_name            = 7;

my ($cache_dir, $kitresources);
GetOptions ('cache|c=s'   => \$cache_dir);
unless ($cache_dir) {
   print "Cache directory not specified\n";
   exit 1;
}

my $dbh = dbconnect();
my @results = dbexecsql($dbh, "select * from info_services.resources");
my $timestamp = strftime "%Y-%m-%dT%H:%M:%SZ", gmtime;
dbdisconnect($dbh);

my @sorted = sort {
      $$a[$F_organization_abbrev] cmp $$b[$F_organization_abbrev] ||
      $$a[$F_organization_name] cmp $$b[$F_organization_name] ||
      $$a[$F_resource_name] cmp $$b[$F_resource_name]
   } @results;
my (%tgcdb, $org, $res);
foreach (@sorted) {
   ############################################################################
   # Process organization information
   ############################################################################
   if ($_->[$F_amie_name] eq 'ANL') {
      $org = 'uc.teragrid.org';
   #} elsif ($_->[$F_amie_name] eq 'SDSC') {
   #   $org = 'sdsc.xsede.org';
   } elsif ($_->[$F_resource_name] =~ /\.teragrid$/) {
      $org = lc($_->[$F_amie_name]) . '.teragrid.org';
   } else {
      $org = lc($_->[$F_amie_name]) . '.xsede.org';
   }
   unless ( $tgcdb{$org} ) {
      $tgcdb{$org}{'organization_abbrev'} = $_->[$F_organization_abbrev];
      $tgcdb{$org}{'organization_name'} = $_->[$F_organization_name];
      $tgcdb{$org}{'amie_name'} = $_->[$F_amie_name];
      print "Organization: $_->[$F_amie_name], $_->[$F_organization_abbrev], $_->[$F_organization_name]\n" if ($DEBUG);
   }

#  2/1/2011 These are "grid resources" for a given physical resource
#  next if ($_->[$F_grid_resource_name] !~ /\.teragrid$/);
#  next if ($_->[$F_grid_resource_name] eq 'staff.teragrid');

   ############################################################################
   # Process Resource information
   ############################################################################
   $res = resource_name_to_resourceid($_->[$F_resource_name]);
   $tgcdb{$org}{resources}{$res}{'resource_name'} = $_->[$F_resource_name];
   $tgcdb{$org}{resources}{$res}{'resource_code'} = $_->[$F_resource_code];
   $tgcdb{$org}{resources}{$res}{'resource_description'} = $_->[$F_resource_description] if ($_->[$F_resource_description]);
   if ( $_->[$F_resource_name] eq $_->[$F_grid_resource_name] && $_->[$F_pops_name] ) {
      $tgcdb{$org}{resources}{$res}{'pops_name'} = $_->[$F_pops_name];
   }
   $tgcdb{$org}{resources}{$res}{grids}{$_->[$F_grid_resource_name]} = $_->[$F_pops_name];
   printf("   %-30s %-20s %-20s %-30s %-30s\n", $_->[$F_resource_name], $_->[$F_resource_code],
      $_->[$F_resource_description], $_->[$F_grid_resource_name], $_->[$F_pops_name]) if ($DEBUG);
}

my $lock_file = "$cache_dir/.lock";
create_lock($lock_file);

my $cache_file = "$cache_dir/tgresources.csv";
my $csv = Text::CSV_XS->new({eol=>$/});#,always_quote=>1});
   $csv->column_names('ResourceID','ResourceName','SiteID','ResourceKits','OrganizationAbbrev','OrganizationName','AmieName','PopsName','TgcdbResourceName','ResourceCode','ResourceDescription','Timestamp');
my $fh;
open($fh, ">$cache_file.NEW") or
   die "Failed to open output '$cache_file'";

my ($org, $res, $id, $grid);
#print $fh 'ResourceID,ResourceName,SiteID,ResourceKits,OrganizationAbbrev,OrganizationName,AmieName,PopsName,TgcdbResourceName,ResourceCode,ResourceDescription,Timestamp' . "\n";
print $fh 'ResourceID,SiteID,OrganizationAbbrev,OrganizationName,AmieName,PopsName,TgcdbResourceName,ResourceCode,ResourceDescription,Timestamp' . "\n";
#$csv->print_hr ($fh, $ref);
#$csv->print_hr ($fh, ['ResourceID,ResourceName,SiteID,ResourceKits,OrganizationAbbrev,OrganizationName,AmieName,PopsName,TgcdbResourceName,ResourceCode,ResourceDescription,Timestamp']);
foreach $org (sort keys %tgcdb) {
   foreach $res ( sort keys %{$tgcdb{$org}{resources}} ) {
   my $printorg = $org;
   #   my $resourcekits='';
   #   #$resourcekits='true' if ( $kitresource{$res} );
   if ($res =~ m/^gordon/) {
	#$printorg =~ s/\.sdsc\.teragrid\.org/\.sdsc\.xsede\.org/g;
	$printorg = "sdsc.xsede.org";
   }
   $csv->print ($fh, [$res,$printorg,$tgcdb{$org}{"organization_abbrev"},$tgcdb{$org}{"organization_name"},$tgcdb{$org}{'amie_name'},$tgcdb{$org}{resources}{$res}{'pops_name'},$tgcdb{$org}{resources}{$res}{'resource_name'},$tgcdb{$org}{resources}{$res}{'resource_code'},$tgcdb{$org}{resources}{$res}{'resource_description'},$timestamp] );
      #print STDOUT '$res,,$org,$resourcekits,$tgcdb{$org}{'organization_abbrev'},$tgcdb{$org}{'organization_name'},$tgcdb{$org}{'amie_name'},$tgcdb{$org}{resources}{$res}{'pops_name'},$tgcdb{$org}{resources}{$res}{'resource_name'},$tgcdb{$org}{resources}{$res}{'resource_code'},$tgcdb{$org}{resources}{$res}{'resource_description'},$timestamp\n';
   }
}
close(STDOUT);

delete_lock($lock_file);

my @outstat = stat("$cache_file.NEW");
if ($outstat[7] != 0) {
   system("mv $cache_file.NEW $cache_file");
}
exit(0);

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

#  $dbh = DBI->connect( "dbi:Pg:dbname=$DBNAME;host=$DBHOST;port=$DBPORT",
   $dbh = DBI->connect( "dbi:Pg:dbname=$DBNAME;host=$DBHOST;port=$DBPORT;sslmode=require",
      $DBUSER, undef, \%args );
   dberror( "Can't connect to database: ", $DBI::errstr ) unless ($dbh);
   $dbh->do("SET search_path TO acct");

   if ($DEBUG) {
      $dbh->do("SET client_min_messages TO debug");
   }

   return $dbh;
}

# Execute sql statements.
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
sub load_csv_file {
   my ($file) = (shift);
   my ($receive, $rawdata);
   open (FL, "<$file") or
      die "Failed to open input '$file'";
   read (FL, $receive, 1048576);
   while ( length($receive) > 0 ) {
      $rawdata .= $receive;
      read (FL, $receive, 1048576);
   }
   close(FL);
      
   my (@field_names, @results, $line, %temp, $status);
   my $lines = 0;
# As you handle the HTML
# ...
# close $fh or die "$!";

   foreach $line ( split("\n", $rawdata) ) {
      $lines++;
      if ( $lines eq 1 ) {
         @field_names = split( /,/, $line );
         next;
      }
      next if ( $line =~ /^\w*$/ );
      $status = $csv->parse($line);
      @temp{@field_names} = $csv->fields();
      push @results, {%temp};
   } 
   return(@results);
}  

sub resource_name_to_resourceid {
   my $resource_name = shift;
   my $resourceid;
   if ( $resource_name =~ /(.*)\.anl\.teragrid$/ ) {
      $resourceid = $1 . '.uc.teragrid.org'; 
   } elsif ( $resource_name eq 'bluegene.sdsc.teragrid' ) {
      $resourceid = 'intimidata.sdsc.teragrid.org'; 
   } elsif ( $resource_name eq 'gordon.sdsc.teragrid' ) {
      $resourceid = 'gordon.sdsc.xsede.org'; 
   } elsif ( $resource_name eq 'gordon-ion.sdsc.teragrid' ) {
      $resourceid = 'gordonio.sdsc.xsede.org'; 
   } elsif ( $resource_name !~ /\.org$/ ) {
      $resourceid = $resource_name . '.org';
   } else {
      $resourceid = $resource_name;
   }
   return($resourceid);
}
