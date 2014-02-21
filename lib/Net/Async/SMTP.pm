package Net::Async::SMTP;
use strict;
use warnings;
use parent qw(IO::Async::Notifier);

use Net::Async::SMTP::Connection;

sub port { shift->{port} }
sub host { shift->{host} }

=head2 connection

Connects to the SMTP server.

=cut

sub connection {
	my $self = shift;
	$self->loop->connect(
		socktype => 'stream',
		host     => $self->host,
		service  => $self->port || 'smtp',
	);
}

=head2 configure

Configure things.

=cut

sub configure {
	my $self = shift;
	my %args = @_;
	for(grep exists $args{$_}, qw(host user pass auth)) {
		$self->{$_} = delete $args{$_};
	}
	$self->SUPER::configure(%args);
}

=head2 connected

Returns the L<Future> indicating we have a valid connection.

=cut

sub connected {
	my $self = shift;
	$self->{connected} ||= $self->connection->then(sub {
		my $sock = shift;
		my $stream = Net::Async::SMTP::Connection->new(
			handle => $sock
		);
		$self->add_child($stream);
		$stream->send_greeting->then(sub {
			return Future->wrap($stream) unless $stream->has_feature('STARTTLS');
			# Currently need to have this loaded to find ->sslwrite
			require IO::Async::SSLStream;
			$stream->starttls 
		});
	});
}

sub login {
	my $self = shift;
	my %args = @_;
	$self->connected->then(sub {
		my $connection = shift;
		$connection->login(%args);
	});
}

sub send {
	my $self = shift;
	my %args = @_;

	$self->connected->then(sub {
		my $connection = shift;
		$connection->send(%args);
	})
}

1;

