# activepush

Web push service built around ActiveMQ (or any STOMP broker).

ActivePush subscribes to a STOMP broker and relays messages with a specific `push_id` header to subscribed Socket.io clients. The message bodies are opaque to ActivePush, so the service is useful in a variety of applications.

## Usage

Production:

    npm install
    bin/activepush [environment]

Development:

    npm install -d
    bin/activepush

Or, to auto-reload on changes:

    node-dev activepush.coffee

The optional `environment` argument corresponds to a configuration file in `configure`, which defaults to `development` and overrides values in the "default.yml" configuration file.

By default ActivePush expects a STOMP broker (e.x. ActiveMQ) to be running on `localhost:61613`.

If ActiveMQ is installed you can start it with the following command:

    activemq start broker:stomp://localhost:61613

## Configuration

Configuration files are located in the `config` directory. `default.yml` is loaded first, and an environment-specific configuration (defaulting to `development.yml`) overrides the defaults.

The environment can be specified as the first argument the the `activepush` executable, or in the `NODE_ENV` environment variable.

## Production

All HTTP endpoints except those under the "/socket.io" URL should not be exposed externally as they could expose private information (e.g. "/health") or capabilities (e.g. "/send"). Alternatively, those endpoints could easily be moved to a separate port (see commented out code in the `start` method of ActivePush)

Multiple instances of ActivePush can be load-balanced, keeping the following in mind:

* A STOMP message bus rather than a queue should be used to ensure all instances recieve all messages
* Socket.io needs clients to be "pinned" to the same backend across multiple requests (perhaps using cookies or the source IP address), in particular for the XHR polling transport.

## Architecture

The ActivePush class in `activepush.coffee` creates the server using the StompProducer and SocketIOConsumer. This could be made configurable, or even support multiple simultaneous producer/consumers.

The STOMP and WebSocket components are implemented in `consumers.coffee` and `producers.coffee`, respectively. Other producers/consumers could be implemented.

The producer/consumer components share a SubscriptionBroker `subscriptions` object, which is essentially an EventEmitter they can listen or emit `push_id` events to.

ActivePush makes extensive use of "promises" (specifically Q promises, which are compatible with the Promises/A+ standard) in both the application and tests.

## Testing

    npm test

The integration tests assume a STOMP broker is running on `localhost:61613`. ActiveMQ can be started with the following command:

    activemq start broker:stomp://localhost:61613

`integration-common.coffee` implements the logic of the tests while `integration-socketio-client.coffee` and `integration-webdriver.coffee` implement a common API to create either an in-process `socket.io-client` or a remote WebDriver instance running the demo.html page (which stores messages it receives in `window.messages` for introspection by the test)

Unfortunately there is no easy way to tell when all messages have propagated from the running test to the ActiveMQ queue back to the ActivePush server and through the Socket.io client, so we currently have short delays before testing that messages have been received. This leads to occasional non-deterministic test failures. Increasing the delays reduces the frequency at a cost of longer running tests.
## Contributors

* Tom Robinson <tlrobinson@gmail.com>
