package BLM::Startup::RedisSession;

#    Copyright (C) 2024, TBC Development Group, LLC.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#

use parent qw(BLM::Startup::BaseSession);

use strict;
use warnings;

use Bedrock qw(to_loglevel);

use Bedrock::Constants qw(:booleans);
use Carp;
use Data::Dumper;
use English qw(-no_match_vars);
use Redis;
use Scalar::Util qw(reftype);
use Digest::SHA qw(sha256_hex);

use Role::Tiny::With;
with 'Bedrock::Role::RedisClient';
with 'Bedrock::Logger';

our $VERSION = '1.0.1';

# Provide a "namespace" for the keys that we will be storing into Redis
########################################################################
sub _format_session_key {
########################################################################
  my ($key) = @_;

  my $session_key = sprintf 'bedrock:session:%s', $key;

  get_logger()->trace( 'session key ' . $session_key );

  return $session_key;
}

# +---------------------------------------------------------------+
# | ->CONNECT( %options )                                         |
# |                                                               |
# | see: BLM::Startup::BaseSession                                |
# |                                                               |
# +---------------------------------------------------------------+
sub CONNECT {
  my ( $self, %options ) = @_;

  my $config = $self->{config};

  my $verbose  = $config->{verbose};
  my $loglevel = $config->{loglevel};

  $loglevel = to_loglevel( $loglevel // $verbose );

  get_logger()->level($loglevel);

  my $handle = eval { return redis_connect($config) };

  die sprintf 'could not create handle to Redis for: %s', $EVAL_ERROR
    if !$handle || $EVAL_ERROR;

  return $self->handle($handle);
}

########################################################################
sub handle {
########################################################################
  my ( $obj, @args ) = @_;

  my $self = tied %{$obj} || $obj;

  return $self->{_manager_state}->{handle}
    if !@args;

  $self->{_manager_state} = { handle => $args[0] };

  return;
}

# +---------------------------------------------------------------+
# | ->FETCH_SESSION( %options )                                   |
# |                                                               |
# | see: BLM::Startup::BaseSession                                |
# +---------------------------------------------------------------+
sub FETCH_SESSION {
  my ( $self, %options ) = @_;

  my $redis = $self->handle;

  my $session_key = _format_session_key( $options{session} );

  my $data = $redis->get($session_key);

  get_logger()->trace(
    Dumper(
      [ session_key => $session_key,
        data        => $data
      ]
    )
  );

  return [ undef, undef, undef, undef, $data ];
}

# +---------------------------------------------------------------+
# | ->STORE_SESSION( %options )                                   |
# |                                                               |
# | see: BLM::Startup::BaseSession                                |
# +---------------------------------------------------------------+
sub STORE_SESSION {
  my ( $self, %options ) = @_;

  my $redis = $self->handle;

  my $session_key = _format_session_key( $options{session} );

  my $expiry = $options{config}->{cookie}->{expiry_secs};

  get_logger()->debug( 'storing  ' . $session_key );

  get_logger()->debug( Dumper( [ options => \%options ] ) );

  $redis->set( $session_key, $options{data}->{prefs} );

  die sprintf "could not set ttl for %s\n", $session_key
    if !$redis->expire( $session_key, $expiry );

  return $TRUE;
}

# +---------------------------------------------------------------+
# | ->KILL_SESSION( %options )                                    |
# |                                                               |
# | see: BLM::Startup::BaseSession                                |
# +---------------------------------------------------------------+
sub KILL_SESSION {
  my ( $self, %options ) = @_;

  my $redis = $self->handle;

  return $redis->del( _format_session_key( $options{session} ) );
}

########################################################################
sub login {
########################################################################
  my ( $obj, $username, $password ) = @_;

  my $self = tied %{$obj} || $obj;

  my $redis = $self->handle;

  my $users = eval { return JSON->new->decode( $redis->get('bedrock:users') ); };

  die "no users defined\n"
    if !$users;

  my $user = $users->{$username};

  die "no such user\n"
    if !$user;

  die "incorrect password\n"
    if !$self->verify_password( $password, $user->{password} );

  $user->{prefs} //= '<object></object>';

  my $aref = [ @{$user}{qw(username firstname lastname email prefs)} ];

  $self->init_session($aref);

  # Create a new session
  my $session = $self->newSessionID;

  # Delete the `new_session' flag
  delete $self->{new_session};

  # Save the merged prefs and the session id
  my $prefs = Bedrock::XML::writeXMLString( $self->{data}->{prefs} );

  die "could not store session\n"
    if !$self->STORE_SESSION(
    session  => $session,
    data     => { prefs => $prefs },
    expires  => $self->{expires},
    username => $username,
    config   => $self->{config},
    );

  return $session;
}

########################################################################
sub verify_password {
########################################################################
  my ( $self, $entered_password, $password ) = @_;

  my $salt = substr $password, 0, 64;

  my $salted_password = $salt . sha256_hex( $salt . $entered_password );

  get_logger()->debug(
    Dumper(
      [ salt            => $salt,
        salted_password => $salted_password,
        password        => $password,
      ]
    )
  );

  return $password eq $salted_password;
}

########################################################################
sub load_users {
########################################################################
  my ( $obj, $users ) = @_;

  my $self = tied %{$obj} || $obj;

  my $redis = $self->handle;

  my %bedrock_users;

  $users //= [];

  if ( $users && @{$users} ) {
    die "users must be an array of hashes\n"
      if reftype( $users->[0] ) ne 'HASH';

    foreach ( @{$users} ) {
      die "user entries must have at least username and password\n"
        if !$_->{username} || !$_->{password};

      $bedrock_users{ $_->{username} } = $_;
    }
  }

  $redis->set( 'bedrock:users', JSON->new->encode( \%bedrock_users ) );

  return;
}

########################################################################
sub fetch_users {
########################################################################
  my ($obj) = @_;

  my $self = tied %{$obj} || $obj;

  my $redis = $self->handle;

  my $users = eval { return JSON->new->decode( $redis->get('bedrock:users') ); };

  return $users;
}

########################################################################
sub logout {
########################################################################
  my ($obj) = @_;

  my $self = tied %{$obj};

  my ( $verbose, $ctx, $config ) = @{$self}{qw(verbose ctx config)};

  # Reset data
  $self->{data} = {};

  if ( !$config->{cookieless_sessions} ) {

    # Delete the cookie
    $self->cookie(
      $self->{name},
      value   => 'killed',
      expires => -86_400,
    );

    $self->send_cookie;
  }

  $self->handle->del( _format_session_key( $self->{session} ) );

  my $session_id = $self->newSessionID;

  # do not return $self <null $session.logout()> will store $self as
  # the default variable $_.  Bedrock will attempt to destroy $session
  # & $_ and end up calling closeBLM twice.
  return;
}

########################################################################
sub remove_user {
########################################################################
  my ( $obj, $username ) = @_;

  my $self = tied %{$obj} || $obj;

  my $users = $self->fetch_users() // {};

  delete $users->{$username};

  $self->load_users( [ values %{$users} ] );

  return $users;
}

########################################################################
sub create_salt {
########################################################################
  my ($self) = @_;

  my @chars = ( '0' .. '9', 'a' .. 'f' );

  my @salt = map { $chars[ int rand 16 ] } ( 0 .. 63 );

  return join q{}, @salt;
}

########################################################################
sub register {
########################################################################
  my ( $obj, @args ) = @_;

  my $self = tied %{$obj} || $obj;

  my $users = $self->fetch_users() // {};
  my ( $username, $password, $firstname, $lastname, $email ) = @args;

  die "username and password are required\n"
    if !$username || !$password;

  die "duplicate username\n"
    if $users->{$username};

  my $salt = $self->create_salt();

  my %user = (
    username  => $username,
    password  => $salt . sha256_hex( $salt . $password ),
    firstname => $firstname,
    lastname  => $lastname,
    email     => $email,
  );

  $users->{$username} = \%user;

  $self->load_users( [ values %{$users} ] );

  return $users;
}

1;

## no critic (RequirePodSections)

__END__

=pod

=head1 PUBLIC

BLM::Startup::RedisSession - Redis based sessions

=head1 SYNOPSIS

 <pre>
   <trace --output $session>
 </pre>

=head1 DESCRIPTION

Provides a pesistent session store for anonymous or login sessions.
See L<BLM::Startup::UserSession> for more details on sessions.

Using a memory cache like Redis for session management offers several
advantages over using a traditional database:

=over 5

=item Performance

Memory caches like Redis are designed to store data
in-memory, which provides significantly faster read and write speeds
compared to disk-based databases. This results in lower latency for
session management operations, leading to improved overall system
performance and responsiveness.

=item Scalability

Redis is highly scalable and can handle a large number of
concurrent requests with ease. It supports clustering and replication,
allowing you to distribute data across multiple nodes to handle
increasing loads. This scalability makes it well-suited for
applications with growing user bases or high traffic volumes.

=item Simplicity and Efficiency

Redis is optimized for storing and retrieving small, frequently
accessed data structures such as session information. Its simple
key-value data model and support for data structures like sets, lists,
and hashes make it efficient for storing session-related data.

=item Persistence Options

While Redis primarily stores data in-memory for
performance reasons, it also offers options for persistence. You can
configure Redis to periodically dump data to disk or use features like
Redis Cluster and Redis Sentinel to ensure data durability and high
availability.

=item Built-in Features

Redis provides several built-in features that are
useful for session management, such as automatic expiration of keys,
which allows you to set a TTL (time-to-live) for session data. This
simplifies session cleanup and helps prevent memory leaks by
automatically removing expired sessions.

=item Atomic Operations

Redis supports atomic operations on data structures, which ensures
that session management operations like creating, updating, or
deleting sessions are performed atomically. This helps maintain data
consistency and prevents race conditions that can occur in distributed
systems.

=item Ease of Integration

Redis has client libraries available for a wide range of programming
languages, making it easy to integrate into various types of
applications. Many web frameworks and platforms have built-in support
for Redis, simplifying the process of incorporating it into your
application architecture.

Overall, Redis offers a powerful and efficient solution for session
management, particularly in applications where performance,
scalability, and simplicity are critical requirements.

I<Source: ChatGPT 3.5>

=back

=head1 CONFIGURATION

Create a Bedrock XML file named F<redis-session.xml> and place that in
one of Bedrock's configuration paths.

I<Note that you can only have one session class bound to the C<$session> object.>

 <!-- Bedrock RedisSessions -->
 <object>
   <scalar name="binding">session</scalar>
   <scalar name="session">yes</scalar>
   <scalar name="module">BLM::Startup::RedisSession</scalar>
 
   <object name="config">
     <scalar name="verbose">2</scalar>
     <scalar name="param">session</scalar>
 
     <!-- Redis connect information -->
     <scalar name="server">localhost</scalar>
     <scalar name="port">6379</scalar>
 
     <object name="cookie">
       <scalar name="path">/</scalar>
       <scalar name="expiry_secs">3600</scalar>
       <scalar name="domain"></scalar>
     </object>
   </object>
 </object>

=head1 METHODS AND SUBROUTINES

Implements the bare minimium methods for session management using a
Redis server. See L<BLM::Startup:SessionManager> for more details on
how sessions work and what methods are available. This class uses the
L<Bedrock::Role::RedisClient> role.

=head2 FETCH_SESSION

Uses the Redis C<get> method to retrieve data from the Redis server.

=head2 KILL_SESSSION

Uses the Redis C<del> method to retrieve data from the Redis server.

=head2 STORE_SESSION

Uses the Redis C<set> method to store data from the Redis server. Use
the C<expires> method to set the ttl on keys based on the current
cookie expiration time.

=head1 AUTHOR

Andy Layton

Rob Lauer - rlauer6@comcast.net

=head1 SEE OTHER

L<Bedrock::RedisClient>, L<BLM::Startup::BaseSession>, L<BLM::Startup::SessionManager>
L<Bedrock::Apache::RedisSessionHandler>

=cut
