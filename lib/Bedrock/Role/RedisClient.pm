package Bedrock::Role::RedisClient;

#
#    This file is a part of Bedrock, a server-side web scripting tool.
#    Check out http://www.openbedrock.net
#    Copyright (C) 2001, Charles Jones, LLC.
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

use Role::Tiny;

use Bedrock::XML;
use Data::Dumper;
use English qw(-no_match_vars);
use Redis;

use Readonly;

Readonly our $DEFAULT_PORT   => 6379;
Readonly our $DEFAULT_SERVER => 'localhost';
Readonly our $REDIS_CONFIG   => 'redis-session.xml';

our $VERSION = '1.0.1';

our $HANDLE;

########################################################################
sub redis_config {
########################################################################
  my (@args) = @_;

  my ( $file, $config );
  if ( $args[0] && ref $args[0] ) {
    $config = $args[0];
  }
  else {
    $file = $args[0] // $ENV{REDIS_CONFIG};

    if ( !$file ) {
      my @paths;

      for ( grep {defined} $ENV{CONFIG_PATH}, $ENV{BEDROCK_CONFIG_PATH} ) {
        push @paths, ( $_, "$_.d", "$_.d/startup", "$_.d/plugin" );
      }

      for (@paths) {
        $file = sprintf '%s/%s', $_, $REDIS_CONFIG;
        last if -e $file;
      }
    }

    $file //= $REDIS_CONFIG;

    die "no config file found\n"
      if !-e $file;

    $config = eval { return Bedrock::XML->new($file); };

    die sprintf "unable to load config (%s): %s\n", $file, $EVAL_ERROR // q{}
      if !$config || $EVAL_ERROR;
  }

  # Redis configuration might be found in:
  # - the 'config' object if redis-session.xml
  # - the 'redis' object if Bedrock's global config
  # - the root object if reading redis.xml
  return $config->{config} // $config->{redis} // $config;
}

########################################################################
sub redis_connect {
########################################################################
  my (@args) = @_;

  return $HANDLE
    if $HANDLE;

  my $config = ref $args[0] ? $args[0] : {@args};

  $config->{port}   //= $DEFAULT_PORT;
  $config->{server} //= $DEFAULT_SERVER;
  $config->{name}   //= 'session-' . $PID;

  if ( !$config->{sock} && $config->{server} !~ /:\d+$/xsm ) {
    $config->{server} = sprintf '%s:%s', @{$config}{qw(server port)};
  }

  $HANDLE = Redis->new( %{$config} );

  return $HANDLE;
}

########################################################################
sub redis_key {
########################################################################
  my ($session_id) = @_;

  return 'bedrock:session:' . $session_id;
}

########################################################################
sub redis_session {
########################################################################
  my ( $session_key, @args ) = @_;

  my $redis = redis_connect;

  my $session;

  if (@args) {
    my $session_ref = ref $args[0] ? $args[0] : {@args};
    my $session     = Bedrock::XML::writeXML($session_ref);

    my $config = redis_config->{config};

    $redis->set( $session_key, $session, );
    $redis->expire( $session_key, $config->{cookie}->{expiry_secs} );

    return $session_ref;
  }

  return
    if !$redis->exists($session_key);

  return eval { return Bedrock::XML->newFromString( $redis->get($session_key) ); };
}

########################################################################
sub redis_handle {
########################################################################
  return $HANDLE
    if $HANDLE;

  $HANDLE = redis_connect();

  die $EVAL_ERROR
    if !$HANDLE;

  return $HANDLE;
}

1;

## no critic (RequirePodSections)

__END__

=pod

=head1 PUBLIC

Bedrock::RedisClient - role to provide common methods for connecting to Redis server

=head1 SYNOPSIS

 use Role::Tiny:With;
 with 'Bedrock::Role::RedisClient';

 my $redis = redis_handle();

=head1 DESCRIPTION

Implements a role used by L<BLM::Startup::RedisSession>,
L<Bedrock::Apache::RedisSessionHandler> that provides some methods
used by both of these modules.

A Bedrock session using Redis.

=head1 METHODS AND SUBROUTINES

=head2 redis_config

Returns a Redis configuration file as a hash.  Typically the Redis
configuration is stored in a Bedrock XML file named
F<redis-session.xml> (but you can store your Redis configuration in
any Bedrock XML file). The configuration file must exist somewhere in
one of the typcial places Bedrock config files located. The method
will search for the file in:

 $ENV{CONFIG_PATH}
 $ENV{CONFIG_PATH}.d
 $ENV{CONFIG_PATH}.d/startup
 $ENV{CONFIG_PATH}.d/plugin

or the same directories rooted at Bedrock's configuration path
$ENV{BEDROCK_CONFIG_PATH}.

The configuration file is usually a standard Bedrock session
configuration file with provisions for Redis specific requirements
like server name, port, etc embedded in a C<config> object.  See
L<BLM::Startup::RedisSession> for more information about the format of
the configuration file.

You can add whatever additional values for configuring Redis you require.

=over 5

=item * The configuration file should be a Bedrock XML file that represents a
hash of arguments.

=item * If you use the standard session configuration file,
your Redis configuration should be contained within the C<config>
object.

=item * If you use your own Bedrock XML file, the Redis configuration
can be in either the root of the object or contained in within
C<redis> sub-object. This is typically how you would specify the Redis
configuration so that it would be merged into Bedrock's global
configuaration object as 'redis'.

 <object>
   <object name="redis">
     <scalar name="server">docker_redis_1</scalar>
   </object>
 </object>

I<Note that you can place any valid configuration setting supported by
the L<Redis> class.>

=item

=back
 
=head2 redis_handle

Returns a handle to a L<Redis> object.

=head2 redis_key

 redis_key(session-id)

Returns a formatted Redis key that can be used to retrieve a
session. The key stored in Redis will be formatted with a namespace
prefix (C<bedrock:session>). You can override the namespace prefix in the
configuration file by setting the C<namespace> value.

 <!-- Bedrock RedisSessions -->
 <object>
   <scalar name="binding">session</scalar>
   <scalar name="session">yes</scalar>
   <scalar name="module">BLM::Startup::RedisSession</scalar>
 
   <object name="config">
     <scalar name="verbose">2</scalar>
     <scalar name="param">session</scalar>
     <scalar name="namespace">bedrock:session</scalar>
 
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

=head2 redis_session

 redis_session(session-key)

Returns a reference to a hash that represents a user's session.

=head1 AUTHOR

BIGFOOT - <bigfoot@cpan.org>

=head1 SEE OTHER

L<BLM::Startup::RedisSession>, L<Redis>, L<Bedrock::Apache::RedisSessionManager>

=cut
