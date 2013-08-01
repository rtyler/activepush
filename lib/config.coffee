
require "js-yaml"
merge = require "deepmerge"

exports.loadConfiguration = (name) ->
  name = name or process.env["NODE_ENV"] or "development"
  deflt = require("#{__dirname}/../config/default.yml") or {}
  overlay = require("#{__dirname}/../config/#{name}.yml") or {}
  merge(merge(deflt, overlay), environment: name)
