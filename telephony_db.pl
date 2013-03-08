#!/usr/bin/perl -w
#
# NOTES:
#
# SCRIPT DEVELOPMENT IN PROGRESS.... 
#
# --------------------------------------------------------------

use strict;

#
# This perl script is intended to be run via cron to get updated copies of
# the telephony database.
# -------------------------------------------------------------------

my $scp_path       = "/usr/bin/scp";
my $remote_host    = "81.187.46.187";
my $remote_user    = "tantalum";
my $remote_pass    = "mu1atnat";
my $remote_path    = "/home/tantalum/mysql_backups";
my $local_sql_path = "/home/tantalum/strowger/mysql_backups";

my $mysql_path     = "/usr/bin/mysql";
my $mysql_user     = "XXXXXX";
my $mysql_pass     = "XXXXXXXX";
my $mysql_dbname   = "socialtelephony";

# This is the name of the sql file we expect to find in each
# directory that gets copied over.
my $sqlfile        = "socialtelephony.sql";

my $expect_script = "/home/tantalum/strowger/fetch_db_update.expect";
# --------------------------------------------------------------------

my $retval = do_initial_sanity_check();
if ($retval > 0) {
    print("Sanity check failed!  Aborting!\n");
    exit;
}

print("Run the expect script to download the mysql dumps....\n");
# Note we are using backticks here to run the expect script so that
# we can capture the output for the log.
my $output = `$expect_script`;
print("Output of Expect script: $output\n"); 


# Find the most recent database dump
my $most_recent_directory = find_latest_directory();

print("Most recent directory = " . $most_recent_directory . "\n");
my $sqlfile_path = $local_sql_path . "/" . $most_recent_directory . "/" . $sqlfile;

print("Latest sql file = $sqlfile_path\n");

# Load the database dump file into MySQL.
print("Loading db file into MySQL\n");
my $cmd = $mysql_path . " -u $mysql_user --password=$mysql_pass $mysql_dbname < $sqlfile_path";

print("cmd = $cmd\n");
my $load_db_output = `$cmd`;
print("MySQL loading output: $load_db_output\n");

# This function goes through the directory specified in
# $local_sql_path and returns the last one in the list.  This
# list of directories is expected in dd-mm-yyyy format.
#
#  23-04-2008
#  24-04-2008
#  25-04-2008
#  ...
#
sub find_latest_directory
{
   my $lastfile = "";
   opendir(LOCAL_SQL_PATH, $local_sql_path) or die "Can't read sql directory!\n";
   my @sortdirlist = ();
  
   my %actualdirlist = ();
   while(my $sqlfile = readdir(LOCAL_SQL_PATH)) {

       if (($sqlfile eq "..") || ($sqlfile eq ".") || ($sqlfile eq ".svn")) {
           next; 
       }

       my $date_days = substr($sqlfile, 0, 2);
       my $date_month = substr($sqlfile, 3, 2);
       my $date_year  = substr($sqlfile, 6, 4);

       my $sortdate = $date_year . $date_month . $date_days;
       print("sortdate = $sortdate\n");
       push(@sortdirlist, $sortdate);
       $actualdirlist{$sortdate} = $sqlfile;
   }
   closedir(LOCAL_SQL_PATH);

   @sortdirlist = sort(@sortdirlist);

   my $num_dirs = @sortdirlist;
   print("Num dirs = $num_dirs\n"); 
   $lastfile = $sortdirlist[$num_dirs - 1];
   return $actualdirlist{$lastfile};
}

# 
# Do a basic sanity check to make sure that the path to the scp
# utility and to the mysql command line utility in fact exist.
# I'll probably add other things to check here too.  Basically if
# any of these fails then we should abort.
sub do_initial_sanity_check
{
    my $failcount = 0;

    print("Performing initial sanity check before running.\n");
    if (!-e $scp_path) {
        print("ERROR: Specified path for scp not found!\n");
        print("       You entered: $scp_path.  Please correct this before running the script again.\n");
        $failcount++;
    }

    if (!-e $mysql_path) {
        print("ERROR: Specified path for mysql not found!\n");
        print("       You entered $mysql_path.  Please correct this before running the script again.\n");
        $failcount++;
    } 

    print("Sanity Check Failcount = $failcount\n");
    return $failcount;
}


 
