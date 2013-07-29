
require("mocha-as-promised")()
chai = require "chai"
chai.use require "chai-as-promised"
{ expect } = chai

Q = require "q"

activepush = require "../index"
io = require "socket.io-client"
merge = require "deepmerge"
uuid = require "node-uuid"

# Delay before checking received messages to ensure all messages get delivered.
# Increase this value if tests are failiing non-deterministically.
# TODO: better way to detect all messages have been delivered?
WAIT_TIME = 200

config = activepush.loadConfiguration "test"
# config.logging.level = "DEBUG"

configureActivePush = (config) ->
  deferred = Q.defer()
  server = activepush.start config, ->
    deferred.resolve
      config: config
      server: server
      sendMessage: (push_id, message) ->
        activepush.stompPublish config.stomp.hosts[0], config.stomp.inbox, push_id, message
  deferred.promise

configureSocketIO = (port, push_id, options = {}) ->
  deferred = Q.defer()
  socket = io.connect "http://localhost:#{port}", merge(options, "force new connection": true)
  # For some reason socket.io-client doesn't respect the "transports" option so we have to set it manually
  socket.socket.options.transports = options.transports if options.transports?
  socket.on "connect", ->
    socket.emit "subscribe", push_id
    deferred.resolve collectMessages(socket)
  deferred.promise

uniqueInbox = ->
  "/topic/activepush-test-"+uuid.v1()

# Use unique messages to ensure we don't messages from other tests, etc.
uniqueMessage = (prefix="") ->
  prefix+(if prefix then "-" else "")+uuid.v1()

# Helper to collect messages into an array
collectMessages = (socket) ->
  messages = []
  socket.on "message", (message) ->
    messages.push message
  messages

describe "Single ActivePush instance", ->
  ap = null
  before ->
    # Use a unique inbox in case we're running multiple tests using the same ActiveMQ server concurrently etc
    inbox = uniqueInbox()
    configureActivePush(merge(config, stomp:inbox:inbox)).then (activePush) ->
      ap = activePush
  after (cb) ->
    ap.server.stop cb

  it "should not buffer messages (treat as transient)", ->
    expected = uniqueMessage("NO")
    ap.sendMessage("my_push_id", expected)
    configureSocketIO(ap.config.http.port, "my_push_id").then (receivedMessages) ->
      Q.delay(WAIT_TIME).then ->
        expect(receivedMessages).to.deep.equal []

  it "should relay the correct messages to a single client", ->
    expected = uniqueMessage("YES")
    configureSocketIO(ap.config.http.port, "my_push_id").then (receivedMessages) ->
      ap.sendMessage "my_push_id", expected
      ap.sendMessage "other_push_id", uniqueMessage("NO")
      Q.delay(WAIT_TIME).then ->
        expect(receivedMessages).to.deep.equal [expected]

  it "should relay the correct messages to multiple clients", (done) ->
    expected = uniqueMessage("YES")
    Q.all(for index in [0..1]
      configureSocketIO(ap.config.http.port, "my_push_id")
    ).then (allReceivedMessages) ->
      ap.sendMessage "my_push_id", expected
      ap.sendMessage "other_push_id", uniqueMessage("NO")
      Q.delay(WAIT_TIME).then ->
        expect(allReceivedMessages).to.deep.equal [[expected], [expected]]

  it "should relay multiple messages when using XHR transport", ->
    expected = uniqueMessage("YES")
    configureSocketIO(ap.config.http.port, "my_push_id", transports: ["xhr-polling"], 'try multiple transports': false).then (receivedMessages) ->
      ap.sendMessage "my_push_id", expected
      Q.delay(WAIT_TIME).then ->
        ap.sendMessage "my_push_id", expected
        Q.delay(WAIT_TIME).then ->
          expect(receivedMessages).to.deep.equal [expected, expected]

describe "Multiple ActivePush instances", ->
  aps = null
  before ->
    # Use a unique inbox in case we're running multiple tests using the same ActiveMQ server concurrently etc
    inbox = uniqueInbox()
    Q.all(for index in [0..1]
      configureActivePush(merge(config,
        stomp:inbox: inbox
        http:port: config.http.port + index + 1 # Don't re-use the same port from first test
      ))
    ).then (activePushArr) ->
      aps = activePushArr
  after ->
    Q.all(for ap in aps
      deferred = Q.defer()
      ap.server.stop deferred.resolve
      deferred.promise
    )

  it "should relay the correct messages to multiple clients", (done) ->
    Q.all(for ap in aps
      configureSocketIO(ap.config.http.port, "my_push_id")
    ).then (allReceivedMessages) ->
      expected = for ap, index in aps
        msg = uniqueMessage("YES#{index}")
        ap.sendMessage "my_push_id", msg
        ap.sendMessage "other_push_id", uniqueMessage("NO")
        msg
      Q.delay(WAIT_TIME*2).then ->
        expected.sort()
        messages.sort() for messages in allReceivedMessages
        allExpectedMessages = (expected for messages in allReceivedMessages)
        expect(allReceivedMessages).to.deep.equal allExpectedMessages
