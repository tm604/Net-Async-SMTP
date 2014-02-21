#!/usr/bin/env perl 
use strict;
use warnings;
use IO::Async::Loop;
use Net::Async::SMTP;
use Email::Simple;
use Net::DNS;

my $host = 'perlsite.co.uk';
my $user = 'nasmtp@perlsite.co.uk';
my $email = Email::Simple->create(
	header => [
		From => $user,
		To => $user,
		Subject => 'NaSMTP test',
	],
	body => 'some text',
);
warn "Will try to send this email:\n" . $email->as_string;

{ # This blocking lookup should really use the IO::Async resolver
	my $res  = Net::DNS::Resolver->new;
	my @mx   = $res->mx('perlsite.co.uk');
	if (@mx) {
		foreach my $rr (@mx) {
			$host = $rr->exchange;
		}
	} else {
		warn "Can't find MX records for $host ", $res->errorstring, "\n";
	}

}
warn "... to $user via host $host\n";

my $loop = IO::Async::Loop->new;
my $smtp = Net::Async::SMTP->new(
	host => $host,
);
$loop->add($smtp);

$smtp->connection->then(sub {
	# So the login is a separate step here. It should perhaps be done
	# in the background via instantiation.
	$smtp->login(
		user => 'nasmtp@perlsite.co.uk',
		pass => 'EHu0kie2',
	)
})->then(sub {
	# and this is the method for sending.
	$smtp->send(
		to => $user,
		from => $user,
		data => $email->as_string,
	)
})->get;

