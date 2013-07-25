
fs = require "fs"
http = require "http"
express = require "express"
socket_io = require "socket.io"
{ Stomp } = require "stomp"
{ EventEmitter } = require "events"
require "js-yaml"

config = require "./config.yml"

# Create STOMP client
stomp = new Stomp
  host: config.stomp_host
  port: config.stomp_port
  debug: false
  login: "guest"
  passcode: "guest"

# Create Socket.io and Express webserver
app = express()
server = http.createServer(app)
io = socket_io.listen(server)

app.get "/", (req, res) ->
  res.sendfile "#{__dirname}/demo.html"

server.listen config.http_port
console.info "Listening on port #{config.http_port}"

# EventEmitter used to keep track of subscriptions
subscriptions = new EventEmitter()

# STOMP
stomp.connect()
stomp.on "connected", ->
  console.log "STOMP connection: #{config.stomp_host}:#{config.stomp_port}"
  stomp.subscribe { destination: config.stomp_topic, ack: "client" }, (body, headers) ->
    console.log body, headers
    try
      data = JSON.parse body[0]
      console.log data
      push_id = data.push_id #body[0]
      message = data.message #body[0]
      subscriptions.emit push_id, message
    catch e
      console.warn "error", e
# stomp.on "message", (message) ->
#   stomp.ack message.headers['message-id']


stomp.on "error", (errorFrame) ->
  # TODO: reconnect? exit?
  console.error errorFrame.body
  stomp.disconnect()

# Socket.io
io.sockets.on "connection", (socket) ->
  console.log "Socket.io connection."
  socket.on "subscribe", (push_id) ->
    console.log "subscribe to #{push_id}"
    listener = (data) ->
      socket.emit "message", data
    subscriptions.addListener push_id, listener
    socket.on "disconnect", ->
      console.log "disconnect, removing listener for #{push_id}"
      subscriptions.removeListener push_id, listener
