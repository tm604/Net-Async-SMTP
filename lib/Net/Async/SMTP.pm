package Net::Async::SMTP;
use strict;
use warnings;
use parent qw(IO::Async::Notifier);

use Net::Async::SMTP::Connection;
use IO::Async::Resolver::DNS;
use Future::Utils qw(try_repeat_until_success);

sub port { shift->{port} }
sub host { shift->{host} }
sub domain { shift->{domain} }
sub auth { shift->{auth} }

=head2 connection

Connects to the SMTP server.

If we had a host, we'll connect directly.

If we have a domain, then we'll do an MX lookup on it.

If we don't have either, you'll probably just see errors
or unresolved futures.

=cut

sub connection {
	my $self = shift;
	(defined($self->host)
	? Future->wrap($self->host)
	: $self->mx_lookup($self->domain))->then(sub {
		my @hosts = @_;
		try_repeat_until_success {
			my $host = shift;
			$self->debug_printf("Trying connection to [%s]", $host);
			$self->loop->connect(
				socktype => 'stream',
				host     => $host,
				service  => $self->port || 'smtp',
			)->on_fail(sub {
				$self->debug_printf("Failed connection to [%s], have %d left to try", $host, scalar @hosts);
			})
		} foreach => \@hosts;
	});
}

=head2 mx_lookup

Looks up MX records for the given domain.

Currently only tries the first.

=cut

sub mx_lookup {
	my $self = shift;
	my $domain = shift;
	my $resolver = $self->loop->resolver;
 
 	my $f = $self->loop->new_future;
	$resolver->res_query(
		dname => $domain,
		type  => "MX",
		on_resolved => sub { $f->done(@_) },
		on_error => sub { $f->fail(@_) },
	);
	$f->transform(
		done => sub {
			my $pkt = shift;
			my @host;
			foreach my $mx ( $pkt->answer ) {
				next unless $mx->type eq "MX";
				push @host, [ $mx->preference, $mx->exchange ];
			}
			# sort things 
			map $_->[1], sort { $_->[0] <=> $_->[1] } @host;
		}
	)
}

=head2 configure

Configure things.

=cut

sub configure {
	my $self = shift;
	my %args = @_;
	for(grep exists $args{$_}, qw(host user pass auth domain)) {
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
			handle => $sock,
			auth => $self->auth,
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

