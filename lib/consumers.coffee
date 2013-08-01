
Q = require "q"
Consumer = require("./common").Module

socket_io = require "socket.io"
class SocketIOConsumer extends Consumer
  constructor: (server, options = {}) ->
    Consumer.call @, options
    @server = server

  start: ->
    @server = require("http").createServer() unless @server?

    @io = socket_io.listen @server, log: false, transports: ["websocket", "xhr-polling"]
    @io.sockets.on "connection", @_onConnection

    Q.ninvoke(@server, "listen", @options.port).then =>
      @logger.info "SOCKET.IO listening on port %s", @options.port

  stop: ->
    Q.try =>
      @server.close()

  _onConnection: (socket) =>
    @logger.debug "SOCKET.IO connection"
    socket.on "error", (error) =>
      @logger.warn "SOCKET.IO error: %s", error
    socket.on "subscribe", (push_id) =>
      @logger.info "SOCKET.IO subscribed: %s", push_id
      listener = (message) =>
        @logger.debug "SOCKET.IO send push_id=%s message=%s", push_id, message
        socket.send message
      @subscriptions.addListener push_id, listener
      socket.on "disconnect", =>
        @logger.info "SOCKET.IO disconnected: %s", push_id
        @subscriptions.removeListener push_id, listener

  getHealth: ->
    name: "socketio"
    clients: @io.sockets.clients().length

module.exports = { Consumer, SocketIOConsumer }
