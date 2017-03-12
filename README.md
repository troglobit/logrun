Introduction
------------

Logrun is a small script that watches your logs and does stuff when a
regexp match occurs.


Description
-----------

In its basic form logrun looks for various authentication failures and
adds firewall rules to drop packets from the originating IP adresses.
However, anyone familiar with (Perl) regexps easily modifies the code to
do whatever is desirable.

Failed authentication adds the originating IP to a database, keeping
track of the number of failed attempts.  After too many attempts, the
originating address is dropped, thus terminating any communication
between the server and the client.  A passed authentication clears any
entries from the database.

Still TODO is to add timeout to the failed address so that it can be
unlocked automatically after some time in quarantine.


Install
-------

To install, simply run:

	$ sudo perl setup.pl

Configure `/etc/logrun.conf` to suit your needs, and feel free to make
additional rules in the code.

The Perl script detects Debian GNU/Linux systems, some other Linux
systems and OpenBSD.  Support for more systems is most welcome! :)


Origin & References
-------------------

Logrun is based on the excellent [authfail][] script by Bartosz
M. Krajnik.

Logrun started out as a fork of authfail in 2005, then in Subversion and
later converted to Bzr.  Today Logrun is maintained at [GitHub][].

Authors:
- [Joachim Nilsson][]
- Johan Risberg

[GitHub]:           https://github.com/troglobit/logrun
[authfail]:         http://www.sourcefiles.org/System/Daemons/Networking/authfail-1.1.4.tgz.shtml
[Joachim Nilsson]:  http://troglobit.com
