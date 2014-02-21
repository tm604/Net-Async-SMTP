package Net::Async::SMTP::Connection;
use strict;
use warnings;
use parent qw(IO::Async::Stream);

use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use Protocol::SMTP::Client;

sub _add_to_loop {
	my ($self, $loop) = @_;
	$self->{protocol} = Protocol::SMTP::Client->new(
		future_factory => sub { $loop->new_future },
		writer => sub { $self->write(@_) },
	);
	$self->protocol->startup;
	$self->SUPER::_add_to_loop($loop);
}

sub protocol { shift->{protocol} }

sub send_greeting {
	my $self = shift;
	# Start with our greeting, which should receive back a nice list of features
	$self->protocol->send_greeting;
}

sub starttls {
	my $self = shift;
	$self->debug_printf("STARTTLS");
	die "This server does not support TLS" unless $self->has_feature('STARTTLS');

	require IO::Async::SSL;
	$self->protocol->starttls->then(sub {
		$self->loop->SSL_upgrade(
			handle => $self,
			SSL_verify_mode => SSL_VERIFY_NONE,
		)->on_done(sub {
			$self->debug_printf("STARTTLS successful");
		})
		 ->then($self->curry::send_greeting)
		 ->transform(done => sub { $self });
	});
}

sub on_read {
	my ($self, $buffref, $eof) = @_;
	while( $$buffref =~ s/^(.*)\x0D\x0A// ) {
		my $line = $1;
		if($self->{sending_content}) {
			warn "- this is awkward; we shouldn't have anything because we're in the middle of sending: $1";
		} else {
			$self->protocol->handle_line($line);
		}
	}
	return 0;
}

sub has_feature { my $self = shift; $self->protocol->has_feature(@_) }
sub send { my $self = shift; $self->protocol->send(@_) }
sub login { my $self = shift; $self->protocol->login(@_) }

1;
