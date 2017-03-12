
Welcome to logrun!

An event-based, regexp-triggered, job runner...

In its basic form logrun looks for various authentication failures and adds
firewall rules to drop packets from the originating IP adresses.  However,
anyone familiar with (Perl) regexps easily modifies the code to do whatever
is desirable.

Failed authentication adds the originating IP to a database, keeping track
of the number of failed attempts.  After too many attempts, the originating
address is dropped, thus terminating any communication between the server
and the client.  A passed authentication clears any entries from the
database.

Still TODO is to add timeout to the failed address so that it can be unlocked
automatically after some time in quarantine.

Configure /etc/logrun.conf to suit your needs, and feel free to make additional
rules in the code.

To install, simply run:

	$ sudo perl setup.pl

The script today detects Debian GNU/Linux systems, some other Linux systems
and OpenBSD.  If it fails, please send an email to jocke()vmlinux!org with
some details about your setup.

Original author (authfail):
	Bartosz M. Krajnik

Logrun authors (based on authfail):
	Joachim Nilsson
	Johan Risberg

See the homepage for info:
	https://vmlinux.org/projects/logrun/