
fs = require "fs"
path = require "path"
http = require "http"
express = require "express"
socket_io = require "socket.io"
{ Stomp } = require "stomp"
{ EventEmitter } = require "events"
require "js-yaml"

exports.loadConfiguration = (p) ->
  require path.resolve(".", p)

createSocketIOServer = (config, subscriptions) ->
  app = express()

  app.get "/", (req, res) ->
    res.sendfile "#{__dirname}/demo.html"

  server = http.createServer(app)
  io = socket_io.listen(server)
  server.listen(config.http.port)
  console.log "SOCKET.IO listening on:", config.http.port

  io.sockets.on "connection", (socket) ->
    console.log "SOCKET.IO connection"
    socket.on "subscribe", (push_id) ->
      console.log "SOCKET.IO subscribe:", push_id
      listener = (data) ->
        socket.emit "message", data
      subscriptions.addListener push_id, listener
      socket.on "disconnect", ->
        console.log "SOCKET.IO disconnect, removing listener:", push_id
        subscriptions.removeListener push_id, listener

  [app, io]

createStompConnection = (config, host, subscriptions) ->
  console.log "STOMP connecting to: #{host.host}:#{host.port}#{config.stomp.inbox}"

  stomp = new Stomp host
  stomp.connect()
  stomp.on "connected", ->
    console.log "STOMP connected: #{host.host}:#{host.port}#{config.stomp.inbox}"
    stomp.subscribe { destination: config.stomp.inbox, ack: "client" }, (body, headers) ->
      push_id = headers.push_id
      message = body[0]
      console.log "STOMP message:", push_id, message
      subscriptions.emit push_id, message

  stomp.on "error", (error) ->
    console.log "STOMP error:", error.body
    # stomp.disconnect()

  stomp.on "disconnected", (_) ->
    console.log "STOMP disconnected: #{host.host}:#{host.port}"

  stomp

exports.stompPublish = (host, destination, push_id, message) ->
  stomp = new Stomp host
  stomp.connect()
  stomp.on "connected", ->
    stomp.send
      destination: destination
      push_id: push_id
      body: message
      persistent: false
    , false
    stomp.disconnect()

exports.main = (config) ->
  # EventEmitter used to keep track of subscriptions
  subscriptions = new EventEmitter()

  # Create one Socket.io server
  createSocketIOServer(config, subscriptions)

  # # Create one or more STOMP connections
  for host in config.stomp.hosts
    createStompConnection(config, host, subscriptions)

if require.main is module
  config = exports.loadConfiguration(process.argv[2] or "./config.yml")
  exports.main config
