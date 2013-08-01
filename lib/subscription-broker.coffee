
{ EventEmitter } = require "events"

class exports.SubscriptionBroker extends EventEmitter
  constructor: ->
    EventEmitter.call @
    @messageCount = 0

  emit: ->
    @messageCount++
    EventEmitter::emit.apply @, arguments

  getHealth: ->
    health =
      name: "subscriptions"
      push_ids: {}
      subscriptions: 0
      messages: @messageCount
    for name, value of @_events
      count = if Array.isArray(value) then value.length else 1
      health.push_ids[name] = count
      health.total += count
    health
