activepush
==========

Web Push service built around ActiveMQ

Usage
-----

    npm install
    bin/activepush [environment]

The optional `environment` argument corresponds to a configuration file in `configure`, which defaults to `development` and overrides values in the "default.yml" configuration file.

By default ActivePush expects a STOMP broker (e.x. ActiveMQ) to be running on `localhost:61613`.

If ActiveMQ is installed you can start it with the following command:

    activemq start broker:stomp://localhost:61613

Testing
-------

    npm test
