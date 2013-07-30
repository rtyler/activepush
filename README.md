# activepush

Web push service built around ActiveMQ (or any STOMP broker)

## Usage

    npm install
    bin/activepush [environment]

The optional `environment` argument corresponds to a configuration file in `configure`, which defaults to `development` and overrides values in the "default.yml" configuration file.

By default ActivePush expects a STOMP broker (e.x. ActiveMQ) to be running on `localhost:61613`.

If ActiveMQ is installed you can start it with the following command:

    activemq start broker:stomp://localhost:61613

## Testing

    npm test

The integration tests assume a STOMP broker is running on `localhost:61613`. ActiveMQ can be started with the following command:

    activemq start broker:stomp://localhost:61613

## Architecture

  `index.coffee` creates the server using a (currently) hardcoded producer and consumer. This could be made configurable, or even support multiple simultaneous producer/consumers.

  The STOMP and WebSocket components are implemented in `consumers.coffee` and `producers.coffee`, respectively. Other producers/consumers could be implemented.

  The producer/consumer components share a `subscriptions` object, which is essentially an EventEmitter they can listen or emit `push_id` events to.
