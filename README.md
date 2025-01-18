# PUBLIC

BLM::Startup::RedisSession - Redis based sessions

# SYNOPSIS

    <pre>
      <trace --output $session>
    </pre>

# DESCRIPTION

Provides a pesistent session store for anonymous or login session.
See [BLM::Startup::UserSession](https://metacpan.org/pod/BLM%3A%3AStartup%3A%3AUserSession) for more details on sessions.

Using a memory cache like Redis for session management offers several
advantages over using a traditional database:

- Performance

    Memory caches like Redis are designed to store data
    in-memory, which provides significantly faster read and write speeds
    compared to disk-based databases. This results in lower latency for
    session management operations, leading to improved overall system
    performance and responsiveness.

- Scalability

    Redis is highly scalable and can handle a large number of
    concurrent requests with ease. It supports clustering and replication,
    allowing you to distribute data across multiple nodes to handle
    increasing loads. This scalability makes it well-suited for
    applications with growing user bases or high traffic volumes.

- Simplicity and Efficiency

    Redis is optimized for storing and
    retrieving small, frequently accessed data structures such as session
    information. Its simple key-value data model and support for data
    structures like sets, lists, and hashes make it efficient for storing
    session-related data.

- Persistence Options

    While Redis primarily stores data in-memory for
    performance reasons, it also offers options for persistence. You can
    configure Redis to periodically dump data to disk or use features like
    Redis Cluster and Redis Sentinel to ensure data durability and high
    availability.

- Built-in Features

    Redis provides several built-in features that are
    useful for session management, such as automatic expiration of keys,
    which allows you to set a TTL (time-to-live) for session data. This
    simplifies session cleanup and helps prevent memory leaks by
    automatically removing expired sessions.

- Atomic Operations

    Redis supports atomic operations on data
    structures, which ensures that session management operations like
    creating, updating, or deleting sessions are performed
    atomically. This helps maintain data consistency and prevents race
    conditions that can occur in distributed systems.

- Ease of Integration

    Redis has client libraries available for a wide
    range of programming languages, making it easy to integrate into
    various types of applications. Many web frameworks and platforms have
    built-in support for Redis, simplifying the process of incorporating
    it into your application architecture.

    Overall, Redis offers a powerful and efficient solution for session
    management, particularly in applications where performance,
    scalability, and simplicity are critical requirements.

    _Source: ChatGPT 3.5_

# CONFIGURATION

Create a Bedrock XML file named `redis-session.xml` and place that in
one of Bedrock's configuration paths.

_Note that you can only have one session class bound to the `$session` object._

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

# METHODS AND SUBROUTINES

Implements the bare minimium methods for session management using a
Redis server. See [BLM::Startup:SessionManager](https://metacpan.org/pod/BLM%3A%3AStartup%3ASessionManager) for more details on
how sessions work and what methods are available. This class uses the
[Bedrock::RedisClient](https://metacpan.org/pod/Bedrock%3A%3ARedisClient) role.

## FETCH\_SESSION

Uses the Redis `get` method to retrieve data from the Redis server.

## KILL\_SESSSION

Uses the Redis `del` method to retrieve data from the Redis server.

## STORE\_SESSION

Uses the Redis `set` method to store data from the Redis server. Use
the `expires` method to set the ttl on keys based on the current
cookie expiration time.

# AUTHOR

Andy Layton

Rob Lauer - rlauer6@comcast.net

# SEE OTHER

[Bedrock::RedisClient](https://metacpan.org/pod/Bedrock%3A%3ARedisClient), [BLM::Startup::BaseSession](https://metacpan.org/pod/BLM%3A%3AStartup%3A%3ABaseSession), [BLM::Startup::SessionManager](https://metacpan.org/pod/BLM%3A%3AStartup%3A%3ASessionManager)
[Bedrock::Apache::RedisSessionHandler](https://metacpan.org/pod/Bedrock%3A%3AApache%3A%3ARedisSessionHandler)
