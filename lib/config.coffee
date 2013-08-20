
require "js-yaml"
path = require "path"
merge = require "deepmerge"

# If name matches ^\w+$ then use one of the built-in configurations,
# otherwise assume it's a path.
exports.loadConfiguration = (name) ->
  name = name or process.env["NODE_ENV"] or "development"
  if /^\w+$/.test(name)
    config = path.resolve "#{__dirname}/../config/#{name}.yml"
  else
    config = path.resolve ".", name
  deflt = require("#{__dirname}/../config/default.yml") or {}
  overlay = require(config) or {}
  merge(merge(deflt, overlay), environment: name)
