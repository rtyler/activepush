
fs = require "fs"
path = require "path"
http = require "http"
express = require "express"
socket_io = require "socket.io"
merge = require "deepmerge"
{ Stomp } = require "stomp"
{ EventEmitter } = require "events"

winston = require "winston"

require "js-yaml"

exports.loadConfiguration = (environment = "development") ->
  deflt = require("#{__dirname}/config/default.yml") or {}
  overlay = require("#{__dirname}/config/#{environment}.yml") or {}
  merge deflt, overlay

createSocketIOServer = (config, subscriptions) ->
  app = express()

  app.get "/", (req, res) ->
    res.sendfile "#{__dirname}/demo.html"

  server = http.createServer(app)
  io = socket_io.listen server, log: false
  server.listen(config.http.port)
  winston.info "SOCKET.IO listening on port %s", config.http.port

  io.sockets.on "connection", (socket) ->
    winston.debug "SOCKET.IO connection"
    socket.on "error", (error) ->
      winston.warn "SOCKET.IO error: %s", error
    socket.on "subscribe", (push_id) ->
      winston.info "SOCKET.IO subscribed: %s", push_id
      listener = (message) ->
        winston.debug "SOCKET.IO emit push_id=%s message=%s", push_id, message
        socket.emit "message", message
      subscriptions.addListener push_id, listener
      socket.on "disconnect", ->
        winston.info "SOCKET.IO disconnected: %s", push_id
        subscriptions.removeListener push_id, listener

  { app, io, server }

createStompConnection = (config, host, subscriptions) ->
  stomp = new Stomp host
  stomp.connect()
  stomp.on "connected", ->
    winston.info "STOMP connected: %s:%s%s", host.host, host.port, config.stomp.inbox
    stomp.subscribe { destination: config.stomp.inbox, ack: "client" }, (body, headers) ->
      push_id = headers.push_id
      message = body[0]
      # winston.trace "STOMP receive push_id=%s message=%s", push_id, message
      subscriptions.emit push_id, message

  stomp.on "error", (error) ->
    winston.error "STOMP error: %s", error.body
    # stomp.disconnect()

  stomp.on "disconnected", (_) ->
    winston.error "STOMP disconnected: %s:%s", host.host, host.port

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

exports.start = (config, callback) ->
  # EventEmitter used to keep track of subscriptions
  subscriptions = new EventEmitter()

  # Create one Socket.io server
  { app, io, server } = createSocketIOServer(config, subscriptions)

  # # Create one or more STOMP connections
  stomp = createStompConnection(config, config.stomp.hosts[0], subscriptions)

  stomp.on "connected", ->
    callback?(null)

  stop: (callback) ->
    winston.info "Shutting down..."
    stomp.disconnect()
    server.close()
    process.nextTick ->
      callback?(null)

if require.main is module
  # Get the configuration overlays
  config = exports.loadConfiguration process.argv[2]

  # Configure logging
  winston.remove winston.transports.Console
  logOptions =
    level: (config.logging.level or "info").toLowerCase()
  if config.logging.file
    logOptions.filename = config.logging.file
    winston.add winston.transports.File, logOptions
  else
    logOptions.colorize = true
    winston.add winston.transports.Console, logOptions

  # Start the server
  exports.start config
