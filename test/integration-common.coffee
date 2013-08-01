
require("mocha-as-promised")()
chai = require "chai"
chai.use require "chai-as-promised"
{ expect } = chai

Q = require "q"
merge = require "deepmerge"
uuid = require "node-uuid"
QStep = require "q-step"

activepush = require "../activepush"
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
      QStep(
        () -> server.producer.publish "my_push_id", expected
        () -> createClient server.config.http.port, "my_push_id"
        (getMessages) -> getMessages()
        (receivedMessages) -> expect(receivedMessages).to.deep.equal []
      )

    it "should relay the correct messages to a single client", ->
      expected = uniqueMessage("YES")
      QStep(
        () -> createClient server.config.http.port, "my_push_id"
        (getMessages) ->
          @getMessages = getMessages
          Q.all [
            server.producer.publish "my_push_id", expected
            server.producer.publish "other_push_id", uniqueMessage("NO")
          ]
        () -> @getMessages()
        (receivedMessages) -> expect(receivedMessages).to.deep.equal [expected]
      )

    it "should relay the correct messages to multiple clients", (done) ->
      expected = uniqueMessage("YES")
      QStep(
        () -> Q.all(createClient(server.config.http.port, "my_push_id") for index in [0..1])
        (allGetMessages) ->
          @allGetMessages = allGetMessages
          Q.all [
            server.producer.publish "my_push_id", expected
            server.producer.publish "other_push_id", uniqueMessage("NO")
          ]
        () -> Q.all(getMessages() for getMessages in @allGetMessages)
        (allReceivedMessages) -> expect(allReceivedMessages).to.deep.equal [[expected], [expected]]
      )

    it "should relay multiple messages when using XHR transport", ->
      expected = uniqueMessage("YES")
      QStep(
        () -> createClient(server.config.http.port, "my_push_id", transports: ["xhr-polling"], 'try multiple transports': false)
        (getMessages) ->
          @getMessages = getMessages
          Q.all [
            server.producer.publish "my_push_id", expected
            server.producer.publish "my_push_id", expected
          ]
        () -> @getMessages()
        (receivedMessages) -> expect(receivedMessages).to.deep.equal [expected, expected]
      )

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
      QStep(
        () -> Q.all(createClient(server.config.http.port, "my_push_id") for server in servers)
        (allGetMessages) ->
          @allGetMessages = allGetMessages
          promises = []
          @expected = for server, index in servers
            promises.push server.producer.publish "my_push_id", (msg = uniqueMessage("YES#{index}"))
            promises.push server.producer.publish "other_push_id", uniqueMessage("NO")
            msg
          Q.all(promises)
        () -> Q.all(getMessages() for getMessages in @allGetMessages)
        (allReceivedMessages) ->
          allReceivedMessages = (messages.sort() for messages in allReceivedMessages)
          allExpectedMessages = (@expected.sort() for messages in allReceivedMessages)
          expect(allReceivedMessages).to.deep.equal allExpectedMessages
      )

uniqueInbox = ->
  "/topic/activepush-test-"+uuid.v1()

# Use unique messages to ensure we don't messages from other tests, etc.
uniqueMessage = (prefix="") ->
  prefix+(if prefix then "-" else "")+uuid.v1()
