#!/usr/bin/perl
#
# This script sets up a FIFO of all messages collected by syslog.  To make
# syslog write all its logs to the FIFO /etc/syslog.conf is modified.
#
# In OpenBSD the script adds a new table to /etc/pf.conf
#    table <crackers> { }
#
# In Linux no other steps are done.
#
# Next the config file is installed as /etc/logrun.conf and then modified
# according to the local firewall setup.
#
# On OpenBSD pfctl is setup:
#    $ipv4_firewall = "/sbin/pfctl -t crackers -T add ";
#    $ipv6_firewall = $ipv4_firewall;
#
# On Linux shorewall, iptables or ipchains is setup, e.g.:
#    $ipv4_firewall = /sbin/shorewall drop ";
#    $ipv6_firewall = $ipv4_firewall;
#
#

use File::Basename;

$| = 1;

$MYNAME     = `whoami`;
$MYDIR      = "/var/lib/logrun";
$MYFIFO     = $MYDIR . "/FIFO";
$SYSLOGCONF = "/etc/syslog.conf";
$SYSLOGD    = "/etc/init.d/sysklogd";
$FAILTMPL   = "/tmp/logrun";
$FAILFILE   = "/var/lib/logrun/db";
$BLACKLIST  = $FAILFILE . ".blacklist";
$PIDFILE    = "/var/run/logrun.pid";
$LOGRUNCONF = "/etc/logrun.conf";
$LOGRUN = "/usr/sbin/logrun";
$LOGMAN = "/usr/share/man/man8/logrun.8";
$logrun = basename ($LOGRUN);
$logman = basename ($LOGMAN);

# Firewall defaults drop IP and purge all dropped IPs
$DEFAULT_DROP_BSD  = "/sbin/pfctl -t crackers -T add "; 
$DEFAULT_PURGE_BSD = "/sbin/pfctl -t crackers -T delete ";
$DEFAULT_RESTART_BSD = "/sbin/pfctl -t crackers -T zero ";
$RC_FILE_BSD = "/etc/rc.local";

# Firewall defaults drop IP and purge all dropped IPs
$DEFAULT_DROP_LINUX  = "/sbin/iptables -I INPUT -j DROP -s ";
#$DEFAULT_DROP_LINUX  = "/sbin/shorewall drop ";
$DEFAULT_PURGE_LINUX = "/sbin/iptables -D INPUT -j DROP -s ";
#$DEFAULT_PURGE_LINUX = "/sbin/shorewall clear ";
$DEFAULT_RESTART_LINUX = "/sbin/iptables -F INPUT";
#$DEFAULT_RESTART_LINUX = "/sbin/shorewall refresh";
$RC_FILE_LINUX = "/etc/init.d/rcS";

use constant {
    LINUX => 1,
    BSD   => 2,
};

sub is_running ($)
{
    my ($process) = @_;
    return system ("ps ax |grep $process |grep -v grep >/dev/null") == 0;
}

sub create_conf_file ($$$$)
{
    my ($conffile, $drop, $purge, $restart) = @_;

    if(open(LOGCONF, ">$conffile") != 0) {
        print (LOGCONF <<EOT);
# Authfail config file is in -*-Perl-*- format

# Fifo for syslogd to write all logs to.
\$logfile = "$MYFIFO";

# Failed logins database
\$failfile = "$FAILFILE";

#Previously blocked hosts' database
\$blacklist = "$BLACKLIST";

# Facility for syslog (man syslog.conf)
\$facility = "daemon";
        
# PID file location
\$pidfile = "$PIDFILE";

# Number of times ONE host can try and fail login
\$failedattempts = 5;

# Minimum number of days to keep host blocked (0 to disable)
\$blockdays = 88;

#don't add these IP numbers into database - You MUST to add netmask after IP
\@dont_add_into_database = ( "127.0.0.0/255.0.0.0", "192.168.0.0/255.255.255.0");
        
#at the end of this value func update_iptables adds IP
\$ipv4_firewall = "$drop";
\$ipv6_firewall = \$ipv4_firewall;

#Remove command
\$ipv4_rm_firewall = "$purge";

##Purge before restart
#\$command_prestart_iptables = "$restart";

EOT
        printf ("OK\t$filename\n");
    } else {
        $orig = basename ($LOGRUNCONF);
        printf ("ERROR\tCopy $orig to $LOGRUNCONF and edit it to suit your needs.\n");
    }
    
    return 0;
}

# First of all, check that we have root privileges.
if ($MYNAME !~ m/root/) {
    chomp $MYNAME;
    die ("Sorry $MYNAME, but you must be root to install logrun.\n\n");
}

system ("clear");
printf ("Logrun installer ...\n");
printf ("==============================================================================\n");

$system = `uname`;
$debian = 0;
if (-f "/etc/debian_version") {
    $debian = 1;
}

if ($system =~ /Linux/) {
    $YOURSYSTEM = LINUX;
    $RC_FILE = $RC_FILE_LINUX;
    $DEFAULT_DROP = $DEFAULT_DROP_LINUX;
    $DEFAULT_PURGE = $DEFAULT_PURGE_LINUX;
    $DEFAULT_RESTART = $DEFAULT_RESTART_LINUX;
} elsif ($system =~ /OpenBSD/) {
    $YOURSYSTEM = BSD;
    $RC_FILE = $RC_FILE_BSD;
    $DEFAULT_DROP = $DEFAULT_DROP_BSD;
    $DEFAULT_PURGE = $DEFAULT_PURGE_BSD;
    $DEFAULT_RESTART = $DEFAULT_RESTART_BSD;
} else {
    printf ("Sorry, I cannot install logrun on your $system system yet.\n");
    printf ("Read the file INSTALL for manual installation instructions.\n\n");
    exit (1);
}

if ($debian) {
    $sysdesc = "Debian GNU/$system";
} else {
    $sysdesc = "Generic $system";
}
printf ("Detected system\t\t: $sysdesc\n");
printf ("Setting up home dir\t: ");

if (-d $MYDIR) {
#   system ("rm -rf $MYDIR or die ("Cannot cleanup old $MYDIR: $!\n");
    foreach $file (glob("$MYDIR/*")) {
        unlink $file;
    }
    rmdir $MYDIR;
}

system ("mkdir $MYDIR") == 0 or die("ERROR\tCannot create directory $MYDIR: $!\n");
printf ("OK\t$MYDIR\n");
printf ("Setting up FIFO queue\t: ");
system ("mkfifo -m 0600 $MYFIFO") == 0 or die("ERROR\tCannot create $MYFIFO: $!\n");
printf ("OK\t$MYFIFO\n");

printf ("Checking syslog.conf\t: ");
if (system("grep $MYFIFO $SYSLOGCONF >/dev/null")) {
    if (open (SYSLOG, ">>$SYSLOGCONF") != 0) {
        printf (SYSLOG "\nauth,authpriv.*\t\t\t|" . $MYFIFO);
        close (SYSLOG);
        printf ("OK\tModified $SYSLOGCONF\n");
        printf ("Reloading syslogd\t: ");
#    system("ps ax|grep syslog|grep -v grep|awk \'\{system\(\"kill -1 \"\$1\)\}\'");
        if (system ("$SYSLOGD restart 2>&1 >/dev/null")) {
            printf ("ERROR\tRestart it manually please.\n");
        } else {
            printf ("OK\n");
        }
    } else {
        printf ("ERROR\tManually add the following line to $SYSLOGCONF\n\n\tauth,authpriv.*\t\t\t|$MYFIFO\n\n");
    }
} else {
    printf ("OK\tNo need to change $SYSLOGCONF\n");
}

if ($YOURSYSTEM eq BSD) {
    printf ("Modifying /etc/pf.conf\t: ");
    if(open(PFCONF, ">>/etc/pf.conf") != 0) {
        printf (PFCONF "\ntable <crackers> \{ \}\n");
        close(PFCONF);
        printf ("OK\n");
        printf ("===> Reloading PF (Ctrl+C to stop) - pfctl -f /etc/pf.conf ");
        sleep (1);
        printf (".");
        sleep (1);
        printf (".");
        sleep (1);
        printf (".");
        if(system("/sbin/pfctl -f /etc/pf.conf") == 0) {
            printf ("OK\n");
        } else {
            printf ("ERROR\tCannot reload PF filter\n");
        }
    } else {
        printf ("ERROR\tChange your pf.conf file manually by adding the line:\n\ttable\<crackers\> \{ \}\n");
    }
}

printf ("Creating IDS database\t: ");
if (! -f $FAILFILE) {
    unlink ($FAILTMPL);
    system ("touch $FAILTMPL");
    system ("install -D -g root -o root -m 600 $FAILTMPL $FAILFILE");
    printf ("OK\n");
} else {
    printf ("OK\tFile $FAILFILE already exists.\n");
}

if (-f $LOGRUNCONF) {
    $filename = $LOGRUNCONF . ".tmpl";
    $postprocess = 1;
} else {
    $filename = $LOGRUNCONF;
    $postprocess = 0;           # No post processing...
}
printf ("Creating configuration\t: ");
create_conf_file ($filename, $DEFAULT_DROP, $DEFAULT_PURGE, $DEFAULT_RESTART);
if ($postprocess) {
    printf ("\n===> Please review your $LOGRUNCONF and $filename for new options!\n\n");
}

printf ("Installing daemon\t: ");
if (-f $LOGRUN) {
    unlink ($LOGRUN);
}
system ("install -D -o root -g root -m 0700 $logrun $LOGRUN 2>/dev/null") == 0 or die ("Failed installing $logrun to $LOGRUN");
printf ("OK\t$LOGRUN\n");
printf ("Installing manual page\t: ");
if (-f $LOGMAN) {
    unlink ($LOGMAN);
}
system ("install -D -o root -g root -m 644 $logman $LOGMAN 2>/dev/null") == 0 or die ("Failed installing $logman to $LOGMAN");
printf ("OK\t$LOGMAN\n");

$SKELETON = "/etc/init.d/skeleton";
$SCRIPT = "/etc/init.d/logrun";

if ($debian) {
    open (IN, "<$SKELETON") or die ("Cannot open $SKELETON to create new start script.\n");
    open (OUT, ">$SCRIPT") or die ("Cannot open $SCRIPT to write new start script.\n");

    while ($txt = <IN>) {
        if ($txt =~ /^DESC.*/) {
            printf (OUT "DESC=\"Logrun daemon\"\n");
        } elsif ($txt =~ /^NAME.*/) {
            printf (OUT "NAME=logrun\n");
        } elsif ($txt =~ /(^# Provides:.*)skeleton/) {
            printf (OUT "$1logrun\n");
        } elsif ($txt =~ /(^# Short-Description:.*)Example.*/) {
            printf (OUT "$1Regexp triggered actions from system events...\n");
        } elsif ($txt =~ /(^# Description:.*)This.*/) {
            printf (OUT "$1\n");
        } elsif ($txt =~ /(^#.*)placed.*/) {
            printf (OUT "$1\n");
        } elsif ($txt =~ /(^#.*)placed.*/) {
            printf (OUT "$1\n");
#        } elsif ($txt =~ /^set -e/) {
#            printf (OUT "set -x\n");
        } else {
            printf (OUT $txt);
        }
    }

    close (OUT);
    close (IN);
    chmod (0755, $SCRIPT);
    chown (0, 0, $SCRIPT);
    system ("update-rc.d -f $logrun remove >/dev/null");
    system ("update-rc.d $logrun defaults");
    if (is_running ($logrun)) {
        system ("$SCRIPT restart");
    } else {
        system ("$SCRIPT start");
    }
} else {
    printf ("Modifying startup\t: ");
    if (system ("grep $LOGRUN $RC_FILE > /dev/null")) {
        if (open (RCS, ">>$RC_FILE") != 0) {
            printf (RCS "\n$LOGRUN\n");
            close (RCS);
            printf ("OK\t$RC_FILE\n");
        } else {
            printf ("ERROR\tModify your system startup script to include:\n");
            printf ("\n\t$LOGRUN\n\n");
        }
    } else {
        printf ("OK\t$LOGRUN already called in $RC_FILE\n");
    }
    
    if (is_running ($LOGRUN)) {
        printf ("\nRestarting $logrun");
        system ("killall $logrun");
    } else {
        printf ("\nStarting $logrun");
    }
    sleep (1);
    printf (".");
    sleep (1);
    printf (".");
    sleep (1);
    printf (".");
    if(system($LOGRUN) == 0) {
        is_running ($LOGRUN) or die (": ERROR\n\n\tCannot get PID of process: $!\n\n");
        printf ("\t: OK\n");
    } else {
        printf ("\t: ERROR\n\n\tCannot start $LOGRUN: $!\n\nRead INSTALL file and install logrun manually.\n\n");
    }
}
