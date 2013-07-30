
Q = require "q"
io = require "socket.io-client"
merge = require "deepmerge"

integration = require "./integration-common"

# HACK: Delay before checking received messages to ensure all messages get delivered.
# Increase this value if tests are failiing non-deterministically.
# TODO: better way to detect all messages have been delivered?
WAIT_TIME = 100

exports.initIntegrationTests = ->

  integration.initIntegrationTests
    name: "socket.io"
    createClient: (port, push_id, options = {}) ->
      deferred = Q.defer()
      socket = io.connect "http://localhost:#{port}", merge(options, "force new connection": true)
      # For some reason socket.io-client doesn't respect the "transports" option so we have to set it manually
      socket.socket.options.transports = options.transports if options.transports?
      socket.on "connect", ->
        socket.emit "subscribe", push_id
        messages = []
        socket.on "message", (message) ->
          messages.push message
        deferred.resolve ->
          Q.delay(WAIT_TIME).then -> messages
      # FIXME: figure out how to remove this delay (only required when using the XHR transport)
      if socket.socket.options.transports[0] is "xhr-polling" and socket.socket.options.transports.length is 1
        deferred.promise.delay(100)
      else
        deferred.promise

exports.initIntegrationTests()
