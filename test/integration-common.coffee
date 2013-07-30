
require("mocha-as-promised")()
chai = require "chai"
chai.use require "chai-as-promised"
{ expect } = chai

Q = require "q"
merge = require "deepmerge"
uuid = require "node-uuid"

activepush = require "../index"
{ ActivePush } = activepush

TIMEOUT = 20000

createServer = (config) ->
  new ActivePush(config).start()

# These tests can be run either using socket.io-client within Node to simulate a browser, or using WebDriver to test real browsers
exports.initIntegrationTests = (options) ->
  { name, createClient } = options

  config = activepush.config.loadConfiguration "test"
  # config.logging.level = "DEBUG"

  describe "Single ActivePush instance (#{name})", ->
    @timeout TIMEOUT

    server = null
    before ->
      # Use a unique inbox in case we're running multiple tests using the same ActiveMQ server concurrently etc
      inbox = uniqueInbox()
      createServer(merge(config, stomp:inbox:inbox)).then (activePush) ->
        server = activePush
    after ->
      server.stop()

    it "should not buffer messages (treat as transient)", ->
      expected = uniqueMessage("NO")
      server.producer.publish "my_push_id", expected
      createClient(server.config.http.port, "my_push_id").then (getMessages) ->
        getMessages().then (receivedMessages) ->
          expect(receivedMessages).to.deep.equal []

    it "should relay the correct messages to a single client", ->
      expected = uniqueMessage("YES")
      createClient(server.config.http.port, "my_push_id").then (getMessages) ->
        server.producer.publish "my_push_id", expected
        server.producer.publish "other_push_id", uniqueMessage("NO")
        getMessages().then (receivedMessages) ->
          expect(receivedMessages).to.deep.equal [expected]

    it "should relay the correct messages to multiple clients", (done) ->
      expected = uniqueMessage("YES")
      Q.all(for index in [0..1]
        createClient(server.config.http.port, "my_push_id")
      ).then (allGetMessages) ->
        server.producer.publish "my_push_id", expected
        server.producer.publish "other_push_id", uniqueMessage("NO")
        Q.all(getMessages() for getMessages in allGetMessages).then (allReceivedMessages) ->
          expect(allReceivedMessages).to.deep.equal [[expected], [expected]]

    it "should relay multiple messages when using XHR transport", ->
      expected = uniqueMessage("YES")
      # FIXME: figure out how to get rid of this delay
      createClient(server.config.http.port, "my_push_id", transports: ["xhr-polling"], 'try multiple transports': false).delay(1000).then (getMessages) ->
        server.producer.publish "my_push_id", expected
        server.producer.publish "my_push_id", expected
        getMessages().then (receivedMessages) ->
          expect(receivedMessages).to.deep.equal [expected, expected]

  describe "Multiple ActivePush instances (#{name})", ->
    @timeout TIMEOUT

    servers = null
    before ->
      # Use a unique inbox in case we're running multiple tests using the same ActiveMQ server concurrently etc
      inbox = uniqueInbox()
      Q.all(for index in [0..1]
        createServer(merge(config,
          stomp:inbox: inbox
          http:port: config.http.port + index + 1 # Don't re-use the same port from first test
        ))
      ).then (_servers) ->
        servers = _servers
    after ->
      Q.all(server.stop() for server in servers)

    it "should relay the correct messages to multiple clients", (done) ->
      Q.all(for server in servers
        createClient(server.config.http.port, "my_push_id")
      ).then (allGetMessages) ->
        expected = for server, index in servers
          msg = uniqueMessage("YES#{index}")
          server.producer.publish "my_push_id", msg
          server.producer.publish "other_push_id", uniqueMessage("NO")
          msg
        Q.all(getMessages() for getMessages in allGetMessages).then (allReceivedMessages) ->
          allReceivedMessages = (messages.sort() for messages in allReceivedMessages)
          allExpectedMessages = (expected.sort() for messages in allReceivedMessages)
          expect(allReceivedMessages).to.deep.equal allExpectedMessages

uniqueInbox = ->
  "/topic/activepush-test-"+uuid.v1()

# Use unique messages to ensure we don't messages from other tests, etc.
uniqueMessage = (prefix="") ->
  prefix+(if prefix then "-" else "")+uuid.v1()
