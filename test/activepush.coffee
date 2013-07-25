assert = require "assert"
activepush = require "../index"
io = require "socket.io-client"

config = activepush.loadConfiguration "test"

connectSocketIO = (push_id, ready) ->
  socket = io.connect "http://localhost:#{config.http.port}"
  socket.on "connect", ->
    socket.emit "subscribe", push_id
    ready socket

sendStompMessage = (push_id, message) ->
  activepush.stompPublish config.stomp.hosts[0], config.stomp.inbox, push_id, message

describe "Single ActivePush instance", ->
  server = null
  before (done) ->
    server = activepush.start config, ->
      done()
  after (done) ->
    server.stop ->
      done()

  it "should relay the correct messages to a single client", (done) ->
    expectedMessages = ["yes1"]
    actualMessages = []

    sendStompMessage "my_push_id", "no1"
    sendStompMessage "other_push_id", "no2"

    connectSocketIO "my_push_id", (socket) ->
      socket.on "message", (message) ->
        actualMessages.push message

      sendStompMessage "my_push_id", "yes1"
      sendStompMessage "other_push_id", "no3"

      # Gross...
      setTimeout ->
        assert.deepEqual expectedMessages, actualMessages
        done()
      , 1000
