#!/usr/bin/env perl 
use strict;
use warnings;
use IO::Async::Loop;
use Net::Async::SMTP;
use Email::Simple;
use Net::DNS;

my $domain = 'perlsite.co.uk';
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

my $loop = IO::Async::Loop->new;
my $smtp = Net::Async::SMTP->new(
	domain => $domain,
);
$loop->add($smtp);

$smtp->connected->then(sub {
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

