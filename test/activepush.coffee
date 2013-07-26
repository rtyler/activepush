
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
WAIT_TIME = 100

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

configureSocketIO = (port, push_id) ->
  deferred = Q.defer()
  socket = io.connect "http://localhost:#{port}", "force new connection": true
  socket.on "connect", ->
    socket.emit "subscribe", push_id
    deferred.resolve collectMessages(socket)
  deferred.promise

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
    inbox = "/topic/activepush-test-"+uuid.v1()
    configureActivePush(merge(config, stomp:inbox:inbox)).then (activePush) ->
      ap = activePush
  after (cb) ->
    ap.server.stop cb

  it "should not buffer messages (treat as transient)", ->
    ap.sendMessage("my_push_id", "no")
    configureSocketIO(ap.config.http.port, "my_push_id").then (receivedMessages) ->
      Q.delay(WAIT_TIME).then ->
        expect(receivedMessages).to.deep.equal []

  it "should relay the correct messages to a single client", ->
    configureSocketIO(ap.config.http.port, "my_push_id").then (receivedMessages) ->
      ap.sendMessage "my_push_id", "yes"
      ap.sendMessage "other_push_id", "no"
      Q.delay(WAIT_TIME).then ->
        expect(receivedMessages).to.deep.equal  ["yes"]

  it "should relay the correct messages to multiple clients", (done) ->
    Q.all(for index in [0..1]
      configureSocketIO(ap.config.http.port, "my_push_id")
    ).then (allReceivedMessages) ->
      ap.sendMessage "my_push_id", "yes"
      ap.sendMessage "other_push_id", "no"
      Q.delay(WAIT_TIME).then ->
        expect(allReceivedMessages).to.deep.equal [["yes"], ["yes"]]

describe "Multiple ActivePush instances", ->
  aps = null
  before ->
    # Use a unique inbox in case we're running multiple tests using the same ActiveMQ server concurrently etc
    inbox = "/topic/activepush-test-"+uuid.v1()
    Q.all(for index in [0..1]
      configureActivePush(merge(config,
        stomp:inbox: inbox
        http:port: config.http.port + index
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
      expected = []
      for ap, index in aps
        expected.push "yes#{index}"
        ap.sendMessage "my_push_id", "yes#{index}"
        ap.sendMessage "other_push_id", "no#{index}"
      Q.delay(WAIT_TIME).then ->
        for messages in allReceivedMessages
          expect(messages).to.have.members(expected)
          expect(messages.length).to.equal(expected.length)
